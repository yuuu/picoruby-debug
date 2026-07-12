#ifndef PICORUBY_DEBUG_DEBUGGER_H
#define PICORUBY_DEBUG_DEBUGGER_H

#include <stdint.h>
#include <mruby.h>

void mrb_picoruby_debug_debugger_init(mrb_state *mrb);

/* Hot-path queries from debug.c's hook. */
int mrb_debugger_watching_p(mrb_state *mrb, mrb_value self);
int mrb_debugger_mode_run_p(mrb_state *mrb, mrb_value self);
int mrb_debugger_has_breakpoints_p(mrb_state *mrb, mrb_value self);
int mrb_debugger_file_relevant_p(mrb_state *mrb, mrb_value self, const char *file);
int mrb_debugger_should_break_p(mrb_state *mrb, mrb_value self, const char *file, int32_t line);

int mrb_debugger_quit_requested_p(mrb_state *mrb, mrb_value self);
void mrb_debugger_update_next_ci(mrb_state *mrb, mrb_value self, int real_stop);
void mrb_debugger_reset_mode(mrb_state *mrb, mrb_value self);

/* Frame-walking API, called from debug.c's hook (and future frame-scoped
 * evaluate). depth=0 is the innermost (currently executing) frame. */
int mrb_debug_frame_count(mrb_state *mrb, struct mrb_context *c);
mrb_callinfo *mrb_debug_frame_at(mrb_state *mrb, struct mrb_context *c, int depth);
mrb_bool mrb_debug_frame_position(mrb_state *mrb, mrb_callinfo *ci, mrb_bool is_top, int32_t *line, const char **file);
mrb_value mrb_debug_frame_binding(mrb_state *mrb, struct mrb_context *c, mrb_callinfo *ci);

/* debug.c's debug_invoke_on_break records the paused task's context here
 * (before swapping mrb->c to call Debugger#on_break) so the frame_count/
 * frame_position/frame_binding methods exposed to Ruby can walk the paused
 * stack while mrb->c itself points elsewhere for the duration of on_break. */
void mrb_debugger_set_paused_context(mrb_state *mrb, mrb_value self, struct mrb_context *c);

#endif /* PICORUBY_DEBUG_DEBUGGER_H */
