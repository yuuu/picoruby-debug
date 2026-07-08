#ifndef PICORUBY_DEBUG_WATCH_BREAKPOINT_H
#define PICORUBY_DEBUG_WATCH_BREAKPOINT_H

#include <mruby.h>
#include <mruby/class.h>

mrb_value debug_watch_breakpoint_new(mrb_state *mrb, struct RClass *cls, const char *expr, mrb_int expr_len);

struct RClass *mrb_picoruby_debug_watch_breakpoint_init(mrb_state *mrb, struct RClass *breakpoint_super);

#endif /* PICORUBY_DEBUG_WATCH_BREAKPOINT_H */
