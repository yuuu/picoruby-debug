module MRDebug
  module UI
    # The (prdb) prompt. Reads one message at a time via a Transport
    # (mrblib/mrdebug/transport.rb) -- avoids the old picoruby-editor
    # multi-command-in-one-read bug by construction, same as before this
    # was pulled out from a hardcoded STDIN.gets. Defaults to
    # Transport::Stdio so existing callers (and the manual smoke check in
    # README.md) see no change; pass a Transport::Loopback (or any other
    # Transport) to drive this UI without real stdio, e.g. in tests.
    class LocalConsole < Base
      def initialize(transport = Transport::Stdio.new)
        @transport = transport
      end

      def on_stop(session)
        @transport.write("Breakpoint: #{session.file}:#{session.line}\n")
        loop do
          @transport.write('(prdb) ')
          line = @transport.gets
          return if line.nil? # EOF/disconnect: let the script run to completion
          output, action = Command.dispatch(session, line)
          output.each { |l| @transport.write("#{l}\n") }
          return if action == :resume
        end
      end
    end
  end
end
