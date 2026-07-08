#include <stdint.h>
#include <mruby.h>
#include <mruby/presym.h>
#include <mruby/class.h>
#include <mruby/debug.h>
#include <mruby/irep.h> /* irep->iseq; debug.h only fwd-decls mrb_irep */
#include <mruby/proc.h>
#include <mruby/internal.h> /* mrb_env_new; must follow proc.h (MRUBY_PROC_H-gated) */
#include <mruby/variable.h>

#include "../../include/breakpoint.h"
#include "../../include/line_breakpoint.h"
#include "../../include/watch_breakpoint.h"
#include "../../include/debugger.h"
#include "../../include/debug.h"

/* Defined in mruby-binding/src/binding.c; no public header declares it. */
mrb_value mrb_binding_new(mrb_state *mrb, const struct RProc *proc, mrb_value recv, struct REnv *env);

/* No console output from C: printing happens on the Ruby side, keeping this
 * gem free of HAL/stdio dependencies. */

/* VM-hook bookkeeping, never touched by Ruby-facing Debugger methods. Only
 * one Debugger can own the hook at a time, so globals beat per-instance
 * state. */
static mrb_value active_debugger_self;
static int active_debugger_p = 0;
static int debugger_self_registered = 0;
static int in_break = 0;         /* re-entrancy guard while at a prompt */
static int32_t prev_line = -1;   /* same-line dedup */
static const mrb_irep *prev_irep = NULL;

static void debug_code_fetch_hook(mrb_state *mrb, const mrb_irep *irep, const mrb_code *pc, mrb_value *regs);

static const char *
debug_current_file(mrb_state *mrb, const mrb_irep *irep, const mrb_code *pc)
{
  uint32_t off = (uint32_t)(pc - irep->iseq);
  return mrb_debug_get_filename(mrb, irep, off);
}

static int32_t
debug_current_line(mrb_state *mrb, const mrb_irep *irep, const mrb_code *pc)
{
  uint32_t off = (uint32_t)(pc - irep->iseq);
  return mrb_debug_get_line(mrb, irep, off);
}

/* Build a Binding for ci's frame (same boxing as Kernel#binding); nil for a
 * C frame. */
static mrb_value
debug_make_binding(mrb_state *mrb, struct mrb_context *c, mrb_callinfo *ci)
{
  const struct RProc *proc = ci->proc;
  if (!proc || MRB_PROC_CFUNC_P(proc)) return mrb_nil_value();
  struct REnv *env = mrb_vm_ci_env(ci);
  if (!env) {
    int nstacks = proc->body.irep->nlocals;
    env = mrb_env_new(mrb, c, ci, nstacks, ci->stack, mrb_vm_ci_target_class(ci));
    ci->u.env = env;
  }
  mrb_value recv = ci->stack[0];
  return mrb_binding_new(mrb, proc, recv, env);
}

/* Call Debugger#on_break. A funcall on the same context would realloc the
 * task's stack and dangle the enclosing mrb_vm_exec's cached ci/regs, so
 * switch to the previous context; the hook is disabled during the call to
 * avoid recursion. `real_stop` is false for a watch-forced per-line visit
 * with no other reason to stop; on_break then returns silently unless a
 * watch changed.
 * TODO: mrb_protect the funcall so an exception can't escape with the
 * hook/context swapped out. */
static void
debug_invoke_on_break(mrb_state *mrb, mrb_value self, const char *file, int32_t line, mrb_value binding, int real_stop)
{
  in_break = 1;
  mrb->code_fetch_hook = NULL;
  mrb_value fv = mrb_str_new_cstr(mrb, file ? file : "(unknown)");
  mrb_value lv = mrb_fixnum_value(line);
  mrb_value rv = mrb_bool_value(real_stop);
  struct mrb_context *task_c = mrb->c;
  if (task_c->prev) mrb->c = task_c->prev;

  mrb_funcall_id(mrb, self, MRB_SYM(on_break), 4, fv, lv, binding, rv);

  mrb->c = task_c;
  if (mrb_debugger_quit_requested_p(mrb, self)) {
    /* MRB_TASK_STOPPED makes the VM's NEXT dispatch bail out of mrb_vm_exec
     * (the same mechanism mrb_stop_task uses), Sandbox/Task or not. */
    mrb->c->status = MRB_TASK_STOPPED;
    return;
  }
  mrb_debugger_update_next_ci(mrb, self, real_stop);
  mrb->code_fetch_hook = debug_code_fetch_hook;
  in_break = 0;
}

static void
debug_code_fetch_hook(mrb_state *mrb, const mrb_irep *irep, const mrb_code *pc, mrb_value *regs)
{
  if (!active_debugger_p) return;
  if (in_break) return;

  mrb_value self = active_debugger_self;
  int watching = mrb_debugger_watching_p(mrb, self);

  if (mrb_debugger_mode_run_p(mrb, self) && !mrb_debugger_has_breakpoints_p(mrb, self) && !watching) return;

  const char *file = debug_current_file(mrb, irep, pc);
  /* RUN only needs ireps in a breakpoint's file; a watch can change from any
   * file, so it forces all ireps (as STEP/NEXT do). */
  if (mrb_debugger_mode_run_p(mrb, self) && !watching && !mrb_debugger_file_relevant_p(mrb, self, file)) return;

  int32_t line = debug_current_line(mrb, irep, pc);
  if (line < 0) return; /* no debug info for this instruction */
  /* One line = several instructions; act only on the first. */
  if (line == prev_line && irep == prev_irep) return;
  prev_line = line;
  prev_irep = irep;

  int should_break = mrb_debugger_should_break_p(mrb, self, file, line);
  if (!should_break && !watching) return;
  /* Bind before debug_invoke_on_break switches away from the paused frame. */
  mrb_value binding = debug_make_binding(mrb, mrb->c, mrb->c->ci);
  debug_invoke_on_break(mrb, self, file, line, binding, should_break);
}

/* Registered on Debugger by debugger.c; kept here because they own the VM
 * hook and the globals above. */
mrb_value
mrb_debugger_enable_hook(mrb_state *mrb, mrb_value self)
{
  if (!debugger_self_registered) {
    mrb_gc_register(mrb, self);
    debugger_self_registered = 1;
  }
  in_break = 0;
  prev_line = -1;
  prev_irep = NULL;
  mrb_debugger_reset_mode(mrb, self);
  active_debugger_self = self;
  active_debugger_p = 1;
  mrb->code_fetch_hook = debug_code_fetch_hook;
  return mrb_true_value();
}

mrb_value
mrb_debugger_disable_hook(mrb_state *mrb, mrb_value self)
{
  mrb->code_fetch_hook = NULL;
  active_debugger_p = 0;
  if (debugger_self_registered) {
    mrb_gc_unregister(mrb, self);
    debugger_self_registered = 0;
  }
  return mrb_true_value();
}

static mrb_value
mrb_binding_debugger(mrb_state *mrb, mrb_value self)
{
  const mrb_irep *caller_irep = NULL;
  const mrb_code *caller_pc   = NULL;
  mrb_callinfo *ci = mrb->c->ci;
  while (ci > mrb->c->cibase) {
    ci--;
    if (!ci->proc || MRB_PROC_CFUNC_P(ci->proc) || !ci->pc) continue;
    caller_irep = ci->proc->body.irep;
    /* ci->pc is the resume address (already past the call); step back one
     * instruction to the call site, as mruby's backtrace.c does. */
    caller_pc   = &ci->pc[-1];
    break;
  }

  const char *file = caller_irep ? debug_current_file(mrb, caller_irep, caller_pc) : NULL;
  int32_t     line = caller_irep ? debug_current_line(mrb, caller_irep, caller_pc) : -1;
  if (!file) file = "(unknown)";
  if (line < 0) line = 0;

  mrb_sym dbg_ivar = mrb_intern_lit(mrb, "@debugger");
  mrb_value dbg = mrb_iv_get(mrb, self, dbg_ivar);
  if (mrb_nil_p(dbg)) {
    struct RClass *cls = mrb_class_get_id(mrb, MRB_SYM(Debugger));
    dbg = mrb_obj_new(mrb, cls, 0, NULL);
    mrb_iv_set(mrb, self, dbg_ivar, dbg);
  }

  if (!debugger_self_registered) {
    mrb_gc_register(mrb, dbg);
    debugger_self_registered = 1;
  }
  prev_line = line;
  prev_irep = caller_irep;
  active_debugger_self = dbg;
  active_debugger_p = 1;

  /* self is already the Binding captured at the call site; real_stop is
   * always true for an explicit binding.debugger. */
  debug_invoke_on_break(mrb, dbg, file, line, self, 1);
  return mrb_nil_value();
}

void
mrb_picoruby_debug_gem_init(mrb_state *mrb)
{
  struct RClass *breakpoint = mrb_picoruby_debug_breakpoint_init(mrb);
  mrb_picoruby_debug_line_breakpoint_init(mrb, breakpoint);
  mrb_picoruby_debug_watch_breakpoint_init(mrb, breakpoint);
  mrb_picoruby_debug_debugger_init(mrb);

  struct RClass *binding = mrb_class_get(mrb, "Binding");
  mrb_define_method(mrb, binding, "debugger", mrb_binding_debugger, MRB_ARGS_NONE());
  mrb_define_method(mrb, binding, "b", mrb_binding_debugger, MRB_ARGS_NONE());
  mrb_define_method(mrb, binding, "break", mrb_binding_debugger, MRB_ARGS_NONE());
}

void
mrb_picoruby_debug_gem_final(mrb_state *mrb)
{
}
