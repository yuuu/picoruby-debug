#ifndef PICORUBY_DEBUG_H
#define PICORUBY_DEBUG_H

#include <stdint.h>
#include <mruby.h>

mrb_value mrb_debugger_enable_hook(mrb_state *mrb, mrb_value self);
mrb_value mrb_debugger_disable_hook(mrb_state *mrb, mrb_value self);

/* Frame-walking API for debugger.c (backtrace/print, future frame-scoped
 * evaluate). depth=0 is the innermost (currently executing) frame. */
int mrb_debug_frame_count(mrb_state *mrb, struct mrb_context *c);
mrb_callinfo *mrb_debug_frame_at(mrb_state *mrb, struct mrb_context *c, int depth);
mrb_bool mrb_debug_frame_position(mrb_state *mrb, mrb_callinfo *ci, mrb_bool is_top, int32_t *line, const char **file);
mrb_value mrb_debug_frame_binding(mrb_state *mrb, struct mrb_context *c, mrb_callinfo *ci);

#endif /* PICORUBY_DEBUG_H */
