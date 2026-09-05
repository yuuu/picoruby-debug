/*
 * Generic launcher for the `mrdebug` host CLI binary (docs/plan-phase4.md
 * step 4). mruby's `spec.bins` convention (tasks/bin.rake) always builds a
 * bin from C sources under tools/<bin-name>/*.c -- there is no way to point
 * a bin directly at a Ruby entry point -- so this file exists purely to
 * satisfy that convention. It carries no debugger logic: it opens an
 * mrb_state (which auto-loads every gem's mrblib, including all of this
 * gem's Ruby -- MRDebug::CLI included), exposes argv as the Ruby-level
 * ARGV constant the same way mruby-bin-mruby's own tools/mruby/mruby.c
 * does, calls MRDebug::CLI.start(ARGV), and maps an uncaught exception to
 * a nonzero exit status. This keeps Phase1's "C is only for what Ruby
 * cannot do" constraint intact in spirit: this file is boilerplate the
 * build system requires, not new debugger behavior.
 */
#include <mruby.h>
#include <mruby/array.h>
#include <mruby/string.h>
#include <stdlib.h>

int
main(int argc, char **argv)
{
  mrb_state *mrb = mrb_open();
  if (!mrb) {
    return EXIT_FAILURE;
  }

  mrb_value mrb_argv = mrb_ary_new_capa(mrb, argc > 0 ? argc - 1 : 0);
  for (int i = 1; i < argc; i++) {
    mrb_ary_push(mrb, mrb_argv, mrb_str_new_cstr(mrb, argv[i]));
  }
  mrb_define_global_const(mrb, "ARGV", mrb_argv);

  mrb_funcall(mrb, mrb_top_self(mrb), "mrdebug_cli_main", 0);

  int status = EXIT_SUCCESS;
  if (mrb->exc) {
    mrb_print_error(mrb);
    status = EXIT_FAILURE;
  }

  mrb_close(mrb);
  return status;
}
