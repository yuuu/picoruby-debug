module MRDebug
  # This gem's own Ruby source files, so Session can exclude them from
  # tracing (CLAUDE.md's "Stepping through mrdebug's own source" gap).
  # Hardcoded, not discovered at runtime (Dir.glob would need a filesystem,
  # which a PicoRuby target may not have) -- update FILES when adding,
  # removing, or renaming a file under mrblib/mrdebug/ or tools/mrdebug/.
  module OwnSource
    FILES = [
      'mrblib/mrdebug.rb',
      'mrblib/binding.rb',
      'mrblib/mrdebug/command.rb',
      'mrblib/mrdebug/display_expression.rb',
      'mrblib/mrdebug/line_breakpoint.rb',
      'mrblib/mrdebug/own_source.rb',
      'mrblib/mrdebug/session.rb',
      'mrblib/mrdebug/transport.rb',
      'mrblib/mrdebug/transport/loopback.rb',
      'mrblib/mrdebug/ui.rb',
      'mrblib/mrdebug/watch_expression.rb',
      'tools/mrdebug/transport/stdio.rb',
      'tools/mrdebug/ui/local_console.rb',
    ]

    # Suffix match, same idiom as LineBreakpoint#match? -- the VM reports
    # absolute paths, and this list only knows relative ones.
    def self.file?(file)
      FILES.any? { |suffix| file[-suffix.size, suffix.size] == suffix }
    end
  end
end
