module MRDebug
  module Transport
    # Host builds only -- STDIN/STDOUT via mruby-io. Reads exactly one line
    # per #gets, matching Base's "never see a partial read" contract; this
    # is what avoids the old picoruby-editor bug of losing a piped
    # multi-command input's tail after a resuming command (see
    # docs/plan-phase1.md).
    class Stdio < Base
      def gets
        line = STDIN.gets
        return nil if line.nil?
        strip_eol(line)
      end

      def write(str)
        STDOUT.write(str)
      end

      def close
      end

      private

      # Manual trailing-newline strip, not String#chomp -- #chomp lives in
      # mruby-string-ext, which misbehaves under mrbtest (see
      # docs/plan-phase1.md's "Avoid mruby-string-ext methods" note in
      # CLAUDE.md). This file is host-only but still gets loaded (and, via
      # a Loopback-backed test, exercised) under mrbtest, so it follows the
      # same rule as mrblib/mrdebug/command.rb's hand-rolled trim.
      def strip_eol(line)
        len = line.size
        len -= 1 if len > 0 && line[len - 1] == "\n"
        len -= 1 if len > 0 && line[len - 1] == "\r"
        line[0, len]
      end
    end
  end
end
