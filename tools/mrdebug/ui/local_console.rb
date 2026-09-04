module MRDebug
  module UI
    # The (prdb) prompt, driven by a Transport -- avoids the old
    # picoruby-editor multi-command-in-one-read bug by construction.
    class LocalConsole < Base
      def initialize(transport = Transport::Stdio.new)
        @transport = transport
      end

      def on_stop(session)
        @transport.write("Breakpoint: #{session.file}:#{session.line}\n")
        loop do
          @transport.write('(prdb) ')
          line = @transport.gets
          return if line.nil? # EOF: let the script run to completion
          output, action = Command.dispatch(session, line)
          output.each { |l| @transport.write("#{l}\n") }
          return if action == :resume
        end
      end
    end
  end
end
