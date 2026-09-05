# Called by tools/mrdebug/mrdebug_cli_main.c's main(); a one-line hand-off
# so all real behavior stays in MRDebug::CLI, testable without the binary.
def mrdebug_cli_main
  MRDebug::CLI.start(ARGV)
end
