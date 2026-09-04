module MRDebug
  module Transport
    # The (prdb) prompt's I/O contract: one line in, one string out. Nothing
    # here knows about a wire protocol (DAP, rdbg's console protocol, ...) --
    # those are framing layers meant to sit on top of a Transport, not a
    # Transport implementation themselves. Keeping this to two methods is
    # what lets LocalConsole (tools/mrdebug/ui/local_console.rb) stay
    # transport-agnostic, the same way MRDebug::Command stays UI-agnostic by
    # returning strings instead of printing.
    class Base
      # Reads exactly one message and returns it, or nil on EOF/disconnect.
      # Implementations decide what "one message" means (a line for a
      # terminal-shaped transport); callers never see partial reads, which
      # is what avoids the old picoruby-editor bug of losing a piped
      # multi-command input's tail after a resuming command.
      def gets
        raise NotImplementedError, "#{self.class} must implement #gets"
      end

      # Writes a raw string. No trailing newline is added -- callers append
      # "\n" themselves when they mean a full line (mirroring the old
      # LocalConsole's mix of `print` for the prompt and `puts` for output).
      def write(str)
        raise NotImplementedError, "#{self.class} must implement #write"
      end

      def close
      end
    end
  end
end
