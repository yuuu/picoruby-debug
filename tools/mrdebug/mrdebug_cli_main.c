/*
 * Generic launcher for the `mrdebug` host CLI binary. mruby's `spec.bins`
 * convention always builds a bin from C sources under tools/<bin-name>/*.c
 * with no way to point one at a Ruby entry point directly, so this file
 * carries no debugger logic: it opens an mrb_state, exposes argv as ARGV,
 * calls MRDebug::CLI.start(ARGV), and maps an uncaught exception to a
 * nonzero exit status.
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
