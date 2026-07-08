#ifndef PICORUBY_DEBUG_LINE_BREAKPOINT_H
#define PICORUBY_DEBUG_LINE_BREAKPOINT_H

#include <stdint.h>
#include <mruby.h>
#include <mruby/class.h>

mrb_value debug_line_breakpoint_new(mrb_state *mrb, struct RClass *cls, const char *file, mrb_int file_len, int32_t line);

int debug_line_breakpoint_file_matches(mrb_value bp_v, const char *file);
int debug_line_breakpoint_stops_at(mrb_value bp_v, const char *file, int32_t line);

struct RClass *mrb_picoruby_debug_line_breakpoint_init(mrb_state *mrb, struct RClass *breakpoint_super);

#endif /* PICORUBY_DEBUG_LINE_BREAKPOINT_H */
