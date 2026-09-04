module MRDebug
  module UI
    # The (prdb) prompt, one line at a time via STDIN.gets -- avoids the
    # old picoruby-editor multi-command-in-one-read bug by construction.
    class LocalConsole < Base
      def on_stop(session)
        puts "Breakpoint: #{session.file}:#{session.line}"
        loop do
          print '(prdb) '
          line = STDIN.gets
          return if line.nil? # EOF: let the script run to completion
          output, action = Command.dispatch(session, line.chomp)
          output.each { |l| puts l }
          return if action == :resume
        end
      end
    end
  end
end
