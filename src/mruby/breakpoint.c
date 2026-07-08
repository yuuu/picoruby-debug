#include <mruby.h>
#include <mruby/presym.h>
#include <mruby/class.h>
#include <mruby/data.h>

#include "../../include/breakpoint.h"

int
debug_breakpoint_active_p(mrb_value bp)
{
  debug_breakpoint *b = (debug_breakpoint *)DATA_PTR(bp);
  return b && b->active;
}

void
debug_breakpoint_deactivate(mrb_value bp)
{
  debug_breakpoint *b = (debug_breakpoint *)DATA_PTR(bp);
  if (b) b->active = 0;
}

static mrb_value
mrb_breakpoint_active_p(mrb_state *mrb, mrb_value self)
{
  return mrb_bool_value(debug_breakpoint_active_p(self));
}

static mrb_value
mrb_breakpoint_deactivate_bang(mrb_state *mrb, mrb_value self)
{
  debug_breakpoint_deactivate(self);
  return self;
}

struct RClass *
mrb_picoruby_debug_breakpoint_init(mrb_state *mrb)
{
  struct RClass *breakpoint = mrb_define_class_id(mrb, MRB_SYM(Breakpoint), mrb->object_class);
  MRB_SET_INSTANCE_TT(breakpoint, MRB_TT_CDATA);
  mrb_define_method_id(mrb, breakpoint, MRB_SYM_Q(active), mrb_breakpoint_active_p, MRB_ARGS_NONE());
  mrb_define_method_id(mrb, breakpoint, MRB_SYM_B(deactivate), mrb_breakpoint_deactivate_bang, MRB_ARGS_NONE());
  return breakpoint;
}
