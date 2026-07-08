#ifndef PICORUBY_DEBUG_BREAKPOINT_H
#define PICORUBY_DEBUG_BREAKPOINT_H

#include <mruby.h>
#include <mruby/class.h>

/* Embedded as the FIRST member of each subclass's struct: C99 6.7.2.1 makes
 * the pointers interconvertible (the sockaddr idiom), so the helpers below
 * work on any subclass without dispatch. */
typedef struct debug_breakpoint {
  int active;
} debug_breakpoint;

int debug_breakpoint_active_p(mrb_value bp);
void debug_breakpoint_deactivate(mrb_value bp);

struct RClass *mrb_picoruby_debug_breakpoint_init(mrb_state *mrb);

#endif /* PICORUBY_DEBUG_BREAKPOINT_H */
