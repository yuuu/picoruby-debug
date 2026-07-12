#ifndef PICORUBY_DEBUG_H
#define PICORUBY_DEBUG_H

#include <mruby.h>

mrb_value mrb_debugger_enable_hook(mrb_state *mrb, mrb_value self);
mrb_value mrb_debugger_disable_hook(mrb_state *mrb, mrb_value self);

#endif /* PICORUBY_DEBUG_H */
