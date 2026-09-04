/*
** frame.c - walks the debuggee's paused call stack (hook.c's
** mrdebug_paused_ctx()) to answer MRDebug::Hook.frame_*.
*/

#include <stdint.h>
#include <mruby.h>
#include <mruby/array.h>
#include <mruby/debug.h>
#include <mruby/irep.h>
#include <mruby/presym.h>
#include <mruby/proc.h>
#include <mruby/internal.h>
#include "mrdebug.h"

mrb_value mrb_binding_new(mrb_state *mrb, const struct RProc *proc, mrb_value recv, struct REnv *env);

static int
frame_count(struct mrb_context *c)
{
  return (int)(c->ci - c->cibase) + 1;
}

static mrb_callinfo *
frame_at(struct mrb_context *c, int depth)
{
  int count = frame_count(c);
  if (depth < 0 || depth >= count) return NULL;
  return &c->cibase[count - 1 - depth];
}

static mrb_bool
frame_position(mrb_state *mrb, mrb_callinfo *ci, mrb_bool is_top, int32_t *line, const char **file)
{
  if (!ci->proc || MRB_PROC_CFUNC_P(ci->proc) || !ci->pc) return FALSE;
  const mrb_irep *irep = ci->proc->body.irep;
  if (!irep) return FALSE;
  const mrb_code *pc = is_top ? ci->pc : &ci->pc[-1];
  uint32_t off = (uint32_t)(pc - irep->iseq);
  return mrb_debug_get_position(mrb, irep, off, line, file);
}

static mrb_value
frame_binding(mrb_state *mrb, struct mrb_context *c, mrb_callinfo *ci)
{
  const struct RProc *proc = ci->proc;
  if (!proc || MRB_PROC_CFUNC_P(proc)) return mrb_nil_value();
  struct REnv *env = mrb_vm_ci_env(ci);
  if (!env) {
    env = mrb_env_new(mrb, c, ci, proc->body.irep->nlocals, ci->stack, mrb_vm_ci_target_class(ci));
    ci->u.env = env;
  }
  return mrb_binding_new(mrb, proc, ci->stack[0], env);
}

static mrb_value
hook_s_frame_count(mrb_state *mrb, mrb_value self)
{
  struct mrb_context *c = mrdebug_paused_ctx(mrb);
  return mrb_fixnum_value(c ? frame_count(c) : 0);
}

static mrb_value
hook_s_frame_position(mrb_state *mrb, mrb_value self)
{
  mrb_int depth;
  mrb_get_args(mrb, "i", &depth);

  struct mrb_context *c = mrdebug_paused_ctx(mrb);
  mrb_callinfo *ci = c ? frame_at(c, (int)depth) : NULL;
  if (!ci) return mrb_nil_value();

  int32_t line;
  const char *file;
  if (!frame_position(mrb, ci, depth == 0, &line, &file)) return mrb_nil_value();

  mrb_value ary = mrb_ary_new_capa(mrb, 2);
  mrb_ary_push(mrb, ary, mrb_str_new_cstr(mrb, file));
  mrb_ary_push(mrb, ary, mrb_fixnum_value(line));
  return ary;
}

static mrb_value
hook_s_frame_binding(mrb_state *mrb, mrb_value self)
{
  mrb_int depth;
  mrb_get_args(mrb, "i", &depth);

  struct mrb_context *c = mrdebug_paused_ctx(mrb);
  mrb_callinfo *ci = c ? frame_at(c, (int)depth) : NULL;
  if (!ci) return mrb_nil_value();

  return frame_binding(mrb, c, ci);
}

void
mrdebug_frame_init(mrb_state *mrb, struct RClass *hook_mod)
{
  mrb_define_module_function_id(mrb, hook_mod, MRB_SYM(frame_count), hook_s_frame_count, MRB_ARGS_NONE());
  mrb_define_module_function_id(mrb, hook_mod, MRB_SYM(frame_position), hook_s_frame_position, MRB_ARGS_REQ(1));
  mrb_define_module_function_id(mrb, hook_mod, MRB_SYM(frame_binding), hook_s_frame_binding, MRB_ARGS_REQ(1));
}
