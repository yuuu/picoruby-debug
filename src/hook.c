/*
** hook.c - installs code_fetch_hook and calls back into Ruby once per
** source line; everything else lives on the Ruby side. Frame walking
** (src/frame.c) is the only other C in mrdebug.
*/

#include <stdint.h>
#include <mruby.h>
#include <mruby/class.h>
#include <mruby/debug.h>
#include <mruby/error.h>
#include <mruby/gc.h>
#include <mruby/irep.h>
#include <mruby/presym.h>
#include <mruby/string.h>
#include "mrdebug.h"

#define DBG_STACK_SIZE 128
#define DBG_CI_SIZE 32
#define DBG_RESET_SLOTS 2

/* One hook, one debuggee: file-static state, not threaded through the
 * hookless code_fetch_hook signature. */
static struct mrdebug_hook {
  mrb_value session;
  mrb_bool armed;
  mrb_bool in_callback;

  const mrb_irep *prev_irep;
  int32_t prev_line;

  struct mrb_context *ctx;
  struct mrb_context *paused;

  struct {
    const mrb_irep *irep;
    const char *cstr;
    mrb_value str;
  } filename;
} hook;

struct on_line_args {
  mrb_value session, file, line, bnd;
};

static void hook_code_fetch(mrb_state *mrb, const mrb_irep *irep, const mrb_code *pc, mrb_value *regs);

static struct mrb_context *
dbg_context_new(mrb_state *mrb)
{
  static const struct mrb_context ctx_zero = { 0 };
  static const mrb_callinfo ci_zero = { 0 };

  struct mrb_context *c = (struct mrb_context *)mrb_malloc(mrb, sizeof(struct mrb_context));
  *c = ctx_zero;

  c->stbase = (mrb_value *)mrb_malloc(mrb, DBG_STACK_SIZE * sizeof(mrb_value));
  c->stend = c->stbase + DBG_STACK_SIZE;
  for (mrb_value *s = c->stbase; s < c->stend; s++) {
    SET_NIL_VALUE(*s);
  }

  c->cibase = (mrb_callinfo *)mrb_malloc(mrb, DBG_CI_SIZE * sizeof(mrb_callinfo));
  c->ciend = c->cibase + DBG_CI_SIZE;
  c->cibase[0] = ci_zero;
  c->ci = c->cibase;
  c->ci->u.target_class = mrb->object_class;
  c->ci->stack = c->stbase;
  c->ci->vis = 1;

  c->status = MRB_FIBER_CREATED;
  return c;
}

static void
dbg_context_reset(mrb_state *mrb, struct mrb_context *c)
{
  static const mrb_callinfo ci_zero = { 0 };

  c->prev = NULL;
  c->ci = c->cibase;
  c->cibase[0] = ci_zero;
  c->ci->u.target_class = mrb->object_class;
  c->ci->stack = c->stbase;
  c->ci->vis = 1;
  if (c->svars) c->svars[0] = NULL;

  size_t slots = DBG_RESET_SLOTS;
  if ((size_t)(c->stend - c->stbase) < slots) slots = (size_t)(c->stend - c->stbase);
  for (size_t i = 0; i < slots; i++) {
    SET_NIL_VALUE(c->stbase[i]);
  }
}

static mrb_value
filename_value(mrb_state *mrb, const mrb_irep *irep, const char *file)
{
  if (irep == hook.filename.irep && file == hook.filename.cstr) return hook.filename.str;

  if (!mrb_nil_p(hook.filename.str)) mrb_gc_unregister(mrb, hook.filename.str);
  hook.filename.str = mrb_str_new_cstr_frozen(mrb, file);
  mrb_gc_register(mrb, hook.filename.str);
  hook.filename.irep = irep;
  hook.filename.cstr = file;
  return hook.filename.str;
}

static mrb_value
call_on_line(mrb_state *mrb, void *userdata)
{
  struct on_line_args *a = (struct on_line_args *)userdata;
  return mrb_funcall_id(mrb, a->session, MRB_SYM(on_line), 3, a->file, a->line, a->bnd);
}

static mrb_value
invoke_on_line(mrb_state *mrb, mrb_value file, int32_t line, mrb_value bnd)
{
  struct mrb_context *task_c = mrb->c;

  hook.in_callback = TRUE;
  mrb->code_fetch_hook = NULL;

  if (!hook.ctx) hook.ctx = dbg_context_new(mrb);
  hook.ctx->prev = task_c;
  hook.paused = task_c;
  mrb->c = hook.ctx;

  struct on_line_args args = { hook.session, file, mrb_fixnum_value(line), bnd };
  mrb_value result = mrb_protect_error(mrb, call_on_line, &args, NULL);

  mrb->c = task_c;
  hook.paused = NULL;
  dbg_context_reset(mrb, hook.ctx);

  hook.in_callback = FALSE;
  if (hook.armed) mrb->code_fetch_hook = hook_code_fetch;
  return result;
}

static void
hook_code_fetch(mrb_state *mrb, const mrb_irep *irep, const mrb_code *pc, mrb_value *regs)
{
  (void)regs;

  if (hook.in_callback) return;

  uint32_t off = (uint32_t)(pc - irep->iseq);
  int32_t line = mrb_debug_get_line(mrb, irep, off);
  if (line < 0) return;
  if (irep == hook.prev_irep && line == hook.prev_line) return;
  hook.prev_irep = irep;
  hook.prev_line = line;

  const char *file = mrb_debug_get_filename(mrb, irep, off);
  if (!file) return;

  invoke_on_line(mrb, filename_value(mrb, irep, file), line, mrb_nil_value());
}

struct mrb_context *
mrdebug_paused_ctx(mrb_state *mrb)
{
  return hook.paused ? hook.paused : mrb->c;
}

static mrb_value
hook_s_enter(mrb_state *mrb, mrb_value self)
{
  mrb_value file, bnd;
  mrb_int line;
  mrb_get_args(mrb, "Sio", &file, &line, &bnd);
  return invoke_on_line(mrb, file, (int32_t)line, bnd);
}

static mrb_value
hook_s_install(mrb_state *mrb, mrb_value self)
{
  mrb_value session;
  mrb_get_args(mrb, "o", &session);

  if (!mrb_nil_p(hook.session)) mrb_gc_unregister(mrb, hook.session);
  hook.session = session;
  mrb_gc_register(mrb, hook.session);

  hook.in_callback = FALSE;
  hook.prev_irep = NULL;
  hook.prev_line = -1;
  hook.armed = FALSE;
  mrb->code_fetch_hook = NULL;
  return session;
}

static mrb_value
hook_s_uninstall(mrb_state *mrb, mrb_value self)
{
  mrb->code_fetch_hook = NULL;
  hook.armed = FALSE;
  if (!mrb_nil_p(hook.session)) {
    mrb_gc_unregister(mrb, hook.session);
    hook.session = mrb_nil_value();
  }
  return mrb_nil_value();
}

static mrb_value
hook_s_armed_set(mrb_state *mrb, mrb_value self)
{
  mrb_value flag;
  mrb_get_args(mrb, "o", &flag);
  hook.armed = !mrb_nil_p(hook.session) && mrb_test(flag);
  if (!hook.in_callback) {
    mrb->code_fetch_hook = hook.armed ? hook_code_fetch : NULL;
  }
  return mrb_bool_value(hook.armed);
}

void
mrb_mrdebug_gem_init(mrb_state *mrb)
{
  hook.session = mrb_nil_value();
  hook.filename.str = mrb_nil_value();

  struct RClass *mod = mrb_define_module_id(mrb, MRB_SYM(MRDebug));
  struct RClass *hook_mod = mrb_define_module_under_id(mrb, mod, MRB_SYM(Hook));

  mrb_define_module_function_id(mrb, hook_mod, MRB_SYM(install), hook_s_install, MRB_ARGS_REQ(1));
  mrb_define_module_function_id(mrb, hook_mod, MRB_SYM(uninstall), hook_s_uninstall, MRB_ARGS_NONE());
  mrb_define_module_function_id(mrb, hook_mod, MRB_SYM_E(armed), hook_s_armed_set, MRB_ARGS_REQ(1));
  mrb_define_module_function_id(mrb, hook_mod, MRB_SYM(enter), hook_s_enter, MRB_ARGS_REQ(3));
  mrdebug_frame_init(mrb, hook_mod);
}

void
mrb_mrdebug_gem_final(mrb_state *mrb)
{
  mrb->code_fetch_hook = NULL;
  hook.armed = FALSE;
  if (hook.ctx) {
    mrb_free_context(mrb, hook.ctx);
    hook.ctx = NULL;
  }
}
