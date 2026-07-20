#include <stdint.h>
#include <mruby.h>
#include <mruby/presym.h>
#include <mruby/class.h>
#include <mruby/data.h>

#include "../../include/breakpoint.h"
#include "../../include/line_breakpoint.h"

static int
debug_strlen(const char *s)
{
  int n = 0;
  if (!s) return 0;
  while (s[n]) n++;
  return n;
}

/* Index of the start of the filename component within the first `len` bytes
 * of `s` (i.e. just past the last '/', or 0 if there is none). */
static int
debug_basename_offset(const char *s, int len)
{
  int i = len;
  while (i > 0 && s[i - 1] != '/') i--;
  return i;
}

/* `suffix` (whatever a DAP client sent, e.g. via setBreakpoints) matches
 * `full` (the interpreter's own running-file path, e.g. "./foo.rb") if
 * `full` ends with `suffix` byte-for-byte -- this lets a bare CLI breakpoint
 * like "foo.rb" or "lib/foo.rb" match a longer running path.
 *
 * A real DAP client (VS Code, Zed, ...) instead sends its own full local
 * absolute path, which is longer than the device's own short running path
 * and never shares a literal byte-for-byte suffix with it (the device's
 * "./foo.rb" has no absolute path ending in literal "./foo.rb" characters).
 * That direction can only be resolved by filename: fall back to comparing
 * just the last path component of each. */
static int
debug_file_match(const char *full, const char *suffix)
{
  if (!full || !suffix) return 0;
  int lf = debug_strlen(full);
  int ls = debug_strlen(suffix);
  if (ls <= lf) {
    const char *tail = full + (lf - ls);
    for (int i = 0; i < ls; i++) {
      if (tail[i] != suffix[i]) return 0;
    }
    return 1;
  }
  int full_base = debug_basename_offset(full, lf);
  int suffix_base = debug_basename_offset(suffix, ls);
  int flen = lf - full_base;
  int slen = ls - suffix_base;
  if (flen != slen) return 0;
  for (int i = 0; i < flen; i++) {
    if (full[full_base + i] != suffix[suffix_base + i]) return 0;
  }
  return 1;
}

typedef struct {
  debug_breakpoint base;
  char    *file;
  int32_t  line;
} debug_line_breakpoint;

static void
debug_line_breakpoint_free(mrb_state *mrb, void *ptr)
{
  debug_line_breakpoint *bp = (debug_line_breakpoint *)ptr;
  if (!bp) return;
  mrb_free(mrb, bp->file);
  mrb_free(mrb, bp);
}

static const struct mrb_data_type debug_line_breakpoint_type = {
  "LineBreakpoint", debug_line_breakpoint_free
};

mrb_value
debug_line_breakpoint_new(mrb_state *mrb, struct RClass *cls, const char *file, mrb_int file_len, int32_t line)
{
  debug_line_breakpoint *bp = (debug_line_breakpoint *)mrb_malloc(mrb, sizeof(*bp));
  bp->base.active = 1;
  char *fcopy = (char *)mrb_malloc(mrb, (size_t)file_len + 1);
  for (mrb_int i = 0; i < file_len; i++) fcopy[i] = file[i];
  fcopy[file_len] = '\0';
  bp->file = fcopy;
  bp->line = line;
  struct RData *data = mrb_data_object_alloc(mrb, cls, bp, &debug_line_breakpoint_type);
  mrb_value v = mrb_obj_value(data);
  mrb_gc_register(mrb, v);
  return v;
}

static int
debug_line_breakpoint_matches_at(debug_line_breakpoint *bp, const char *file, int32_t line)
{
  if (!bp->base.active || bp->line != line) return 0;
  return !bp->file[0] || debug_file_match(file, bp->file);
}

int
debug_line_breakpoint_file_matches(mrb_value bp_v, const char *file)
{
  debug_line_breakpoint *bp = (debug_line_breakpoint *)DATA_PTR(bp_v);
  if (!bp->base.active) return 0;
  return !bp->file[0] || debug_file_match(file, bp->file);
}

int
debug_line_breakpoint_stops_at(mrb_value bp_v, const char *file, int32_t line)
{
  debug_line_breakpoint *bp = (debug_line_breakpoint *)DATA_PTR(bp_v);
  return debug_line_breakpoint_matches_at(bp, file, line);
}

static mrb_value
mrb_line_breakpoint_file(mrb_state *mrb, mrb_value self)
{
  debug_line_breakpoint *bp = DATA_GET_PTR(mrb, self, &debug_line_breakpoint_type, debug_line_breakpoint);
  return mrb_str_new_cstr(mrb, bp->file);
}

static mrb_value
mrb_line_breakpoint_line(mrb_state *mrb, mrb_value self)
{
  debug_line_breakpoint *bp = DATA_GET_PTR(mrb, self, &debug_line_breakpoint_type, debug_line_breakpoint);
  return mrb_fixnum_value(bp->line);
}

static mrb_value
mrb_line_breakpoint_break_p(mrb_state *mrb, mrb_value self)
{
  const char *file;
  mrb_int file_len;
  mrb_int line;
  mrb_get_args(mrb, "si", &file, &file_len, &line);
  debug_line_breakpoint *bp = DATA_GET_PTR(mrb, self, &debug_line_breakpoint_type, debug_line_breakpoint);
  return mrb_bool_value(debug_line_breakpoint_matches_at(bp, file, (int32_t)line));
}

struct RClass *
mrb_picoruby_debug_line_breakpoint_init(mrb_state *mrb, struct RClass *breakpoint_super)
{
  struct RClass *lb = mrb_define_class_id(mrb, MRB_SYM(LineBreakpoint), breakpoint_super);
  mrb_define_method_id(mrb, lb, MRB_SYM(file), mrb_line_breakpoint_file, MRB_ARGS_NONE());
  mrb_define_method_id(mrb, lb, MRB_SYM(line), mrb_line_breakpoint_line, MRB_ARGS_NONE());
  mrb_define_method_id(mrb, lb, MRB_SYM_Q(break), mrb_line_breakpoint_break_p, MRB_ARGS_REQ(2));
  return lb;
}
