/*
** hook.c - installs code_fetch_hook and calls back into Ruby once per
** source line; everything else lives on the Ruby side. Frame walking
** (src/frame.c) is the only other C in mrdebug.
*/

#include <stdint.h>
#include <mruby.h>
#include <mruby/array.h>
#include <mruby/class.h>
#include <mruby/debug.h>
#include <mruby/error.h>
#include <mruby/gc.h>
#include <mruby/internal.h>
#include <mruby/irep.h>
#include <mruby/opcode.h>
#include <mruby/presym.h>
#include <mruby/proc.h>
#include <mruby/string.h>
#include "mrdebug.h"

#define DBG_STACK_SIZE 128
#define DBG_CI_SIZE 32
#define DBG_RESET_SLOTS 2
#define DBG_MAX_METHOD_NAMES 32

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

  /* Method breakpoints: a name pre-filter (synced from Ruby) plus a
   * one-tick-deferred stop so a Ruby method call lands inside the callee,
   * not at the call site. deferred_bp is GC-registered while set. */
  mrb_sym method_names[DBG_MAX_METHOD_NAMES];
  int method_name_count;
  mrb_value deferred_bp;

  struct {
    const mrb_irep *irep;
    const char *cstr;
    mrb_value str;
  } filename;
} hook;

struct on_line_args {
  mrb_value session, file, line, bnd, forced;
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
#ifndef MRDEBUG_NO_SVARS
  /* PicoRuby's mrb_context has no svars field (mrbgem.rake defines this). */
  if (c->svars) c->svars[0] = NULL;
#endif

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
  if (mrb_nil_p(a->forced)) {
    return mrb_funcall_id(mrb, a->session, MRB_SYM(on_line), 3, a->file, a->line, a->bnd);
  }
  return mrb_funcall_id(mrb, a->session, MRB_SYM(on_line), 4, a->file, a->line, a->bnd, a->forced);
}

/* Swap to the dedicated debugger context, run `fn`, swap back and reset --
 * shared by the on_line callback and the method-breakpoint query. */
static mrb_value
run_in_dbg_context(mrb_state *mrb, mrb_value (*fn)(mrb_state *, void *), void *ud, mrb_bool *err)
{
  struct mrb_context *task_c = mrb->c;

  hook.in_callback = TRUE;
  mrb->code_fetch_hook = NULL;

  if (!hook.ctx) hook.ctx = dbg_context_new(mrb);
  hook.ctx->prev = task_c;
  hook.paused = task_c;
  mrb->c = hook.ctx;

  mrb_value result = mrb_protect_error(mrb, fn, ud, err);

  mrb->c = task_c;
  hook.paused = NULL;
  dbg_context_reset(mrb, hook.ctx);

  hook.in_callback = FALSE;
  if (hook.armed) mrb->code_fetch_hook = hook_code_fetch;
  return result;
}

static mrb_value
invoke_on_line_forced(mrb_state *mrb, mrb_value file, int32_t line, mrb_value bnd, mrb_value forced)
{
  struct on_line_args args = { hook.session, file, mrb_fixnum_value(line), bnd, forced };
  return run_in_dbg_context(mrb, call_on_line, &args, NULL);
}

static mrb_value
invoke_on_line(mrb_state *mrb, mrb_value file, int32_t line, mrb_value bnd)
{
  return invoke_on_line_forced(mrb, file, line, bnd, mrb_nil_value());
}

struct method_query_args {
  mrb_value session, recv, mid, cfunc;
};

static mrb_value
call_method_bp_for(mrb_state *mrb, void *userdata)
{
  struct method_query_args *a = (struct method_query_args *)userdata;
  return mrb_funcall_id(mrb, a->session, MRB_SYM(method_bp_for), 3, a->recv, a->mid, a->cfunc);
}

/* Ask Session which MethodBreakpoint (if any) matches this call. Returns the
 * breakpoint object, or nil. */
static mrb_value
query_method_bp(mrb_state *mrb, mrb_value recv, mrb_sym mid, mrb_bool is_cfunc)
{
  struct method_query_args args = {
    hook.session, recv, mrb_symbol_value(mid), mrb_bool_value(is_cfunc)
  };
  mrb_bool err = FALSE;
  mrb_value bp = run_in_dbg_context(mrb, call_method_bp_for, &args, &err);
  return err ? mrb_nil_value() : bp;
}

static void
set_deferred_bp(mrb_state *mrb, mrb_value bp)
{
  if (!mrb_nil_p(hook.deferred_bp)) mrb_gc_unregister(mrb, hook.deferred_bp);
  hook.deferred_bp = bp;
  if (!mrb_nil_p(bp)) mrb_gc_register(mrb, bp);
}

/* Decode the instruction about to run; if it is a call to a watched method
 * name, ask Ruby whether a MethodBreakpoint matches. A C method is stopped
 * on here (its body runs no hook); a Ruby method is deferred one tick so
 * the stop lands on the callee's first instruction. */
static void
check_method_call(mrb_state *mrb, const mrb_irep *irep, const mrb_code *pc, mrb_value *regs)
{
  struct mrb_insn_data in = mrb_decode_insn(pc);
  mrb_value recv;
  mrb_sym mid;

  switch (in.insn) {
  case OP_SEND: case OP_SEND0: case OP_SENDB:
    recv = regs[in.a];
    mid = irep->syms[in.b];
    break;
  case OP_SSEND: case OP_SSEND0: case OP_SSENDB:
    recv = regs[0];
    mid = irep->syms[in.b];
    break;
  default:
    return;
  }

  int watched = 0;
  for (int i = 0; i < hook.method_name_count; i++) {
    if (hook.method_names[i] == mid) { watched = 1; break; }
  }
  if (!watched) return;

  struct RClass *c = mrb_class(mrb, recv);
  mrb_method_t m = mrb_method_search_vm(mrb, &c, mid);
  if (MRB_METHOD_UNDEF_P(m)) return;
  mrb_bool is_cfunc = MRB_METHOD_CFUNC_P(m);

  mrb_value bp = query_method_bp(mrb, recv, mid, is_cfunc);
  if (mrb_nil_p(bp)) return;

  if (is_cfunc) {
    uint32_t off = (uint32_t)(pc - irep->iseq);
    int32_t line = mrb_debug_get_line(mrb, irep, off);
    const char *file = mrb_debug_get_filename(mrb, irep, off);
    if (file && line >= 0) {
      invoke_on_line_forced(mrb, filename_value(mrb, irep, file), line, mrb_nil_value(), bp);
    }
  }
  else {
    set_deferred_bp(mrb, bp);
  }
}

static void
hook_code_fetch(mrb_state *mrb, const mrb_irep *irep, const mrb_code *pc, mrb_value *regs)
{
  if (hook.in_callback) return;

  uint32_t off = (uint32_t)(pc - irep->iseq);
  int32_t line = mrb_debug_get_line(mrb, irep, off);
  const char *file;

  /* A Ruby-method breakpoint deferred from the previous tick: we are now on
   * the callee's first instruction. */
  if (!mrb_nil_p(hook.deferred_bp)) {
    mrb_value bp = hook.deferred_bp;
    set_deferred_bp(mrb, mrb_nil_value());
    file = mrb_debug_get_filename(mrb, irep, off);
    if (file && line >= 0) {
      hook.prev_irep = irep;
      hook.prev_line = line;
      invoke_on_line_forced(mrb, filename_value(mrb, irep, file), line, mrb_nil_value(), bp);
    }
    return;
  }

  if (line >= 0 && !(irep == hook.prev_irep && line == hook.prev_line)) {
    hook.prev_irep = irep;
    hook.prev_line = line;
    file = mrb_debug_get_filename(mrb, irep, off);
    if (file) invoke_on_line(mrb, filename_value(mrb, irep, file), line, mrb_nil_value());
  }

  if (hook.method_name_count > 0 && mrb_nil_p(hook.deferred_bp) && !hook.in_callback) {
    check_method_call(mrb, irep, pc, regs);
  }
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
  hook.method_name_count = 0;
  set_deferred_bp(mrb, mrb_nil_value());
  mrb->code_fetch_hook = NULL;
  return session;
}

static mrb_value
hook_s_uninstall(mrb_state *mrb, mrb_value self)
{
  mrb->code_fetch_hook = NULL;
  hook.armed = FALSE;
  hook.method_name_count = 0;
  set_deferred_bp(mrb, mrb_nil_value());
  if (!mrb_nil_p(hook.session)) {
    mrb_gc_unregister(mrb, hook.session);
    hook.session = mrb_nil_value();
  }
  return mrb_nil_value();
}

/* Sync the method-name pre-filter from Session. Argument is an array of
 * Symbols (the method names of the active MethodBreakpoints). */
static mrb_value
hook_s_watch_method_names(mrb_state *mrb, mrb_value self)
{
  mrb_value ary;
  mrb_get_args(mrb, "A", &ary);

  mrb_int n = RARRAY_LEN(ary);
  if (n > DBG_MAX_METHOD_NAMES) n = DBG_MAX_METHOD_NAMES;
  hook.method_name_count = (int)n;
  for (mrb_int i = 0; i < n; i++) {
    hook.method_names[i] = mrb_symbol(mrb_ary_ref(mrb, ary, i));
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
  hook.deferred_bp = mrb_nil_value();
  hook.filename.str = mrb_nil_value();

  struct RClass *mod = mrb_define_module_id(mrb, MRB_SYM(MRDebug));
  struct RClass *hook_mod = mrb_define_module_under_id(mrb, mod, MRB_SYM(Hook));

  mrb_define_module_function_id(mrb, hook_mod, MRB_SYM(install), hook_s_install, MRB_ARGS_REQ(1));
  mrb_define_module_function_id(mrb, hook_mod, MRB_SYM(uninstall), hook_s_uninstall, MRB_ARGS_NONE());
  mrb_define_module_function_id(mrb, hook_mod, MRB_SYM_E(armed), hook_s_armed_set, MRB_ARGS_REQ(1));
  mrb_define_module_function_id(mrb, hook_mod, MRB_SYM(enter), hook_s_enter, MRB_ARGS_REQ(3));
  mrb_define_module_function_id(mrb, hook_mod, MRB_SYM(watch_method_names), hook_s_watch_method_names, MRB_ARGS_REQ(1));
  mrdebug_frame_init(mrb, hook_mod);
}

void
mrb_mrdebug_gem_final(mrb_state *mrb)
{
  mrb->code_fetch_hook = NULL;
  hook.armed = FALSE;
  hook.method_name_count = 0;
  if (!mrb_nil_p(hook.deferred_bp)) {
    mrb_gc_unregister(mrb, hook.deferred_bp);
    hook.deferred_bp = mrb_nil_value();
  }
  if (hook.ctx) {
    mrb_free_context(mrb, hook.ctx);
    hook.ctx = NULL;
  }
}
