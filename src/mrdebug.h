#ifndef MRDEBUG_H
#define MRDEBUG_H

#include <mruby.h>

/* hook.c owns the debuggee's paused context; frame.c walks it. */
struct mrb_context *mrdebug_paused_ctx(void);

/* Registers frame_count/frame_position/frame_binding on hook_mod. */
void mrdebug_frame_init(mrb_state *mrb, struct RClass *hook_mod);

#endif
