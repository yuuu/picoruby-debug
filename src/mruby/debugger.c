#include <stdint.h>
#include <mruby.h>
#include <mruby/presym.h>
#include <mruby/array.h>
#include <mruby/class.h>
#include <mruby/data.h>

#include "../../include/breakpoint.h"
#include "../../include/line_breakpoint.h"
#include "../../include/watch_breakpoint.h"
#include "../../include/debug.h"
#include "../../include/debugger.h"

typedef enum {
  DBG_MODE_RUN = 0,
  DBG_MODE_STEP,
  DBG_MODE_NEXT,
} debug_mode;

/* The Debugger's own state. Hook-mechanism bookkeeping (active instance,
 * same-line dedup, etc.) lives in debug.c's globals instead. */
typedef struct {
  mrb_value        *breakpoints;
  int               breakpoint_count;
  int               breakpoint_cap;
  mrb_value        *watches;
  int               watch_count;
  int               watch_cap;
  debug_mode        mode;
  mrb_callinfo     *next_ci;
  int               quit_requested;
} picoruby_debugger;

static void
picoruby_debugger_free(mrb_state *mrb, void *ptr)
{
  picoruby_debugger *d = (picoruby_debugger *)ptr;
  if (!d) return;
  for (int i = 0; i < d->breakpoint_count; i++) {
    mrb_gc_unregister(mrb, d->breakpoints[i]);
  }
  mrb_free(mrb, d->breakpoints);
  for (int i = 0; i < d->watch_count; i++) {
    mrb_gc_unregister(mrb, d->watches[i]);
  }
  mrb_free(mrb, d->watches);
  mrb_free(mrb, d);
}

static const struct mrb_data_type picoruby_debugger_type = {
  "Debugger", picoruby_debugger_free
};

static picoruby_debugger *
debugger_state(mrb_state *mrb, mrb_value self)
{
  picoruby_debugger *d = (picoruby_debugger *)DATA_PTR(self);
  if (!d) {
    d = (picoruby_debugger *)mrb_malloc(mrb, sizeof(*d));
    d->breakpoints = NULL;
    d->breakpoint_count = 0;
    d->breakpoint_cap = 0;
    d->watches = NULL;
    d->watch_count = 0;
    d->watch_cap = 0;
    d->mode = DBG_MODE_RUN;
    d->next_ci = NULL;
    d->quit_requested = 0;
    mrb_data_init(self, d, &picoruby_debugger_type);
  }
  return d;
}

static mrb_value
mrb_debugger_add_breakpoint(mrb_state *mrb, mrb_value self)
{
  const char *file;
  mrb_int file_len;
  mrb_int line;
  mrb_get_args(mrb, "si", &file, &file_len, &line);

  picoruby_debugger *d = debugger_state(mrb, self);

  if (d->breakpoint_count == d->breakpoint_cap) {
    int newcap = d->breakpoint_cap ? d->breakpoint_cap * 2 : 4;
    d->breakpoints = (mrb_value *)mrb_realloc(mrb, d->breakpoints, sizeof(mrb_value) * newcap);
    d->breakpoint_cap = newcap;
  }
  struct RClass *cls = mrb_class_get_id(mrb, MRB_SYM(LineBreakpoint));
  d->breakpoints[d->breakpoint_count++] = debug_line_breakpoint_new(mrb, cls, file, file_len, (int32_t)line);
  return mrb_true_value();
}

static mrb_value
mrb_debugger_clear_breakpoints(mrb_state *mrb, mrb_value self)
{
  picoruby_debugger *d = debugger_state(mrb, self);
  for (int i = 0; i < d->breakpoint_count; i++) {
    mrb_gc_unregister(mrb, d->breakpoints[i]);
  }
  d->breakpoint_count = 0;
  return mrb_true_value();
}

static mrb_value
mrb_debugger_remove_breakpoint(mrb_state *mrb, mrb_value self)
{
  mrb_int index;
  mrb_get_args(mrb, "i", &index);

  picoruby_debugger *d = debugger_state(mrb, self);
  int i = (int)index - 1;
  if (i < 0 || i >= d->breakpoint_count || !debug_breakpoint_active_p(d->breakpoints[i])) {
    return mrb_false_value();
  }
  debug_breakpoint_deactivate(d->breakpoints[i]);
  return mrb_true_value();
}

static mrb_value
mrb_debugger_breakpoints(mrb_state *mrb, mrb_value self)
{
  picoruby_debugger *d = debugger_state(mrb, self);
  mrb_value ary = mrb_ary_new_capa(mrb, d->breakpoint_count);
  for (int i = 0; i < d->breakpoint_count; i++) {
    mrb_ary_push(mrb, ary, d->breakpoints[i]);
  }
  return ary;
}

static mrb_value
mrb_debugger_add_watch(mrb_state *mrb, mrb_value self)
{
  const char *expr;
  mrb_int expr_len;
  mrb_get_args(mrb, "s", &expr, &expr_len);

  picoruby_debugger *d = debugger_state(mrb, self);

  if (d->watch_count == d->watch_cap) {
    int newcap = d->watch_cap ? d->watch_cap * 2 : 4;
    d->watches = (mrb_value *)mrb_realloc(mrb, d->watches, sizeof(mrb_value) * newcap);
    d->watch_cap = newcap;
  }
  struct RClass *cls = mrb_class_get_id(mrb, MRB_SYM(WatchBreakpoint));
  d->watches[d->watch_count++] = debug_watch_breakpoint_new(mrb, cls, expr, expr_len);
  return mrb_true_value();
}

static mrb_value
mrb_debugger_clear_watches(mrb_state *mrb, mrb_value self)
{
  picoruby_debugger *d = debugger_state(mrb, self);
  for (int i = 0; i < d->watch_count; i++) {
    mrb_gc_unregister(mrb, d->watches[i]);
  }
  d->watch_count = 0;
  return mrb_true_value();
}

static mrb_value
mrb_debugger_remove_watch(mrb_state *mrb, mrb_value self)
{
  mrb_int index;
  mrb_get_args(mrb, "i", &index);

  picoruby_debugger *d = debugger_state(mrb, self);
  int i = (int)index - 1;
  if (i < 0 || i >= d->watch_count || !debug_breakpoint_active_p(d->watches[i])) {
    return mrb_false_value();
  }
  debug_breakpoint_deactivate(d->watches[i]);
  return mrb_true_value();
}

static mrb_value
mrb_debugger_watches(mrb_state *mrb, mrb_value self)
{
  picoruby_debugger *d = debugger_state(mrb, self);
  mrb_value ary = mrb_ary_new_capa(mrb, d->watch_count);
  for (int i = 0; i < d->watch_count; i++) {
    mrb_ary_push(mrb, ary, d->watches[i]);
  }
  return ary;
}

static mrb_value
mrb_debugger_set_run_mode(mrb_state *mrb, mrb_value self)
{
  debugger_state(mrb, self)->mode = DBG_MODE_RUN;
  return mrb_true_value();
}

static mrb_value
mrb_debugger_set_step_mode(mrb_state *mrb, mrb_value self)
{
  debugger_state(mrb, self)->mode = DBG_MODE_STEP;
  return mrb_true_value();
}

static mrb_value
mrb_debugger_set_next_mode(mrb_state *mrb, mrb_value self)
{
  debugger_state(mrb, self)->mode = DBG_MODE_NEXT;
  return mrb_true_value();
}

static mrb_value
mrb_debugger_request_quit(mrb_state *mrb, mrb_value self)
{
  debugger_state(mrb, self)->quit_requested = 1;
  return mrb_true_value();
}

/* --- Hot-path query/mutator surface for debug.c (include/debugger.h) --- */

int
mrb_debugger_watching_p(mrb_state *mrb, mrb_value self)
{
  picoruby_debugger *d = debugger_state(mrb, self);
  for (int i = 0; i < d->watch_count; i++) {
    if (debug_breakpoint_active_p(d->watches[i])) return 1;
  }
  return 0;
}

int
mrb_debugger_mode_run_p(mrb_state *mrb, mrb_value self)
{
  return debugger_state(mrb, self)->mode == DBG_MODE_RUN;
}

int
mrb_debugger_has_breakpoints_p(mrb_state *mrb, mrb_value self)
{
  return debugger_state(mrb, self)->breakpoint_count > 0;
}

/* RUN-mode fast path: without this, a sub-call in an unrelated file clobbers
 * the hook's same-line dedup and re-stops on the same line. */
int
mrb_debugger_file_relevant_p(mrb_state *mrb, mrb_value self, const char *file)
{
  picoruby_debugger *d = debugger_state(mrb, self);
  for (int i = 0; i < d->breakpoint_count; i++) {
    if (debug_line_breakpoint_file_matches(d->breakpoints[i], file)) return 1;
  }
  return 0;
}

int
mrb_debugger_should_break_p(mrb_state *mrb, mrb_value self, const char *file, int32_t line)
{
  picoruby_debugger *d = debugger_state(mrb, self);
  switch (d->mode) {
  case DBG_MODE_STEP:
    return 1;
  case DBG_MODE_NEXT:
    /* Lower ci address = shallower frame; deeper than the snapshot means we
     * stepped into a call. */
    return (intptr_t)d->next_ci >= (intptr_t)mrb->c->ci;
  case DBG_MODE_RUN:
  default:
    for (int i = 0; i < d->breakpoint_count; i++) {
      if (debug_line_breakpoint_stops_at(d->breakpoints[i], file, line)) return 1;
    }
    return 0;
  }
}

int
mrb_debugger_quit_requested_p(mrb_state *mrb, mrb_value self)
{
  return debugger_state(mrb, self)->quit_requested;
}

/* Snapshot only on a genuine stop: a watch-only visit (real_stop false) can
 * come from a deeper frame than the NEXT was issued from and would corrupt
 * the depth comparison, causing spurious stops inside called methods. */
void
mrb_debugger_update_next_ci(mrb_state *mrb, mrb_value self, int real_stop)
{
  picoruby_debugger *d = debugger_state(mrb, self);
  if (real_stop && d->mode == DBG_MODE_NEXT) d->next_ci = mrb->c->ci;
}

void
mrb_debugger_reset_mode(mrb_state *mrb, mrb_value self)
{
  picoruby_debugger *d = debugger_state(mrb, self);
  d->mode = DBG_MODE_RUN;
  d->next_ci = NULL;
}

void
mrb_picoruby_debug_debugger_init(mrb_state *mrb)
{
  struct RClass *debugger = mrb_define_class_id(mrb, MRB_SYM(Debugger), mrb->object_class);
  MRB_SET_INSTANCE_TT(debugger, MRB_TT_CDATA);
  mrb_define_method_id(mrb, debugger, MRB_SYM(enable_hook), mrb_debugger_enable_hook, MRB_ARGS_NONE());
  mrb_define_method_id(mrb, debugger, MRB_SYM(disable_hook), mrb_debugger_disable_hook, MRB_ARGS_NONE());
  mrb_define_method_id(mrb, debugger, MRB_SYM(add_breakpoint), mrb_debugger_add_breakpoint, MRB_ARGS_REQ(2));
  mrb_define_method_id(mrb, debugger, MRB_SYM(clear_breakpoints), mrb_debugger_clear_breakpoints, MRB_ARGS_NONE());
  mrb_define_method_id(mrb, debugger, MRB_SYM(remove_breakpoint), mrb_debugger_remove_breakpoint, MRB_ARGS_REQ(1));
  mrb_define_method_id(mrb, debugger, MRB_SYM(breakpoints), mrb_debugger_breakpoints, MRB_ARGS_NONE());
  mrb_define_method_id(mrb, debugger, MRB_SYM(add_watch), mrb_debugger_add_watch, MRB_ARGS_REQ(1));
  mrb_define_method_id(mrb, debugger, MRB_SYM(clear_watches), mrb_debugger_clear_watches, MRB_ARGS_NONE());
  mrb_define_method_id(mrb, debugger, MRB_SYM(remove_watch), mrb_debugger_remove_watch, MRB_ARGS_REQ(1));
  mrb_define_method_id(mrb, debugger, MRB_SYM(watches), mrb_debugger_watches, MRB_ARGS_NONE());
  mrb_define_method_id(mrb, debugger, MRB_SYM(set_run_mode), mrb_debugger_set_run_mode, MRB_ARGS_NONE());
  mrb_define_method_id(mrb, debugger, MRB_SYM(set_step_mode), mrb_debugger_set_step_mode, MRB_ARGS_NONE());
  mrb_define_method_id(mrb, debugger, MRB_SYM(set_next_mode), mrb_debugger_set_next_mode, MRB_ARGS_NONE());
  mrb_define_method_id(mrb, debugger, MRB_SYM(request_quit), mrb_debugger_request_quit, MRB_ARGS_NONE());
}
