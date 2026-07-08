#include <mruby.h>
#include <mruby/presym.h>
#include <mruby/class.h>
#include <mruby/data.h>

#include "../../include/breakpoint.h"
#include "../../include/watch_breakpoint.h"

typedef struct {
  debug_breakpoint base;
  char *expr;
} debug_watch_breakpoint;

static void
debug_watch_breakpoint_free(mrb_state *mrb, void *ptr)
{
  debug_watch_breakpoint *w = (debug_watch_breakpoint *)ptr;
  if (!w) return;
  mrb_free(mrb, w->expr);
  mrb_free(mrb, w);
}

static const struct mrb_data_type debug_watch_breakpoint_type = {
  "WatchBreakpoint", debug_watch_breakpoint_free
};

mrb_value
debug_watch_breakpoint_new(mrb_state *mrb, struct RClass *cls, const char *expr, mrb_int expr_len)
{
  debug_watch_breakpoint *w = (debug_watch_breakpoint *)mrb_malloc(mrb, sizeof(*w));
  w->base.active = 1;
  char *ecopy = (char *)mrb_malloc(mrb, (size_t)expr_len + 1);
  for (mrb_int i = 0; i < expr_len; i++) ecopy[i] = expr[i];
  ecopy[expr_len] = '\0';
  w->expr = ecopy;
  struct RData *data = mrb_data_object_alloc(mrb, cls, w, &debug_watch_breakpoint_type);
  mrb_value v = mrb_obj_value(data);
  mrb_gc_register(mrb, v);
  return v;
}

static mrb_value
mrb_watch_breakpoint_expr(mrb_state *mrb, mrb_value self)
{
  debug_watch_breakpoint *w = DATA_GET_PTR(mrb, self, &debug_watch_breakpoint_type, debug_watch_breakpoint);
  return mrb_str_new_cstr(mrb, w->expr);
}

struct RClass *
mrb_picoruby_debug_watch_breakpoint_init(mrb_state *mrb, struct RClass *breakpoint_super)
{
  struct RClass *wb = mrb_define_class_id(mrb, MRB_SYM(WatchBreakpoint), breakpoint_super);
  mrb_define_method_id(mrb, wb, MRB_SYM(expr), mrb_watch_breakpoint_expr, MRB_ARGS_NONE());
  return wb;
}
