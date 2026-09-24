#ifndef MRDEBUG_H
#define MRDEBUG_H

#include <mruby.h>

struct mrb_context *mrdebug_paused_ctx(mrb_state *mrb);

void mrdebug_frame_init(mrb_state *mrb, struct RClass *hook_mod);

#endif
