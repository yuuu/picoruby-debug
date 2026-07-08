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

#endif /* PICORUBY_DEBUG_DEBUGGER_H */
