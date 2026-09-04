module MRDebug
  module Transport
    # Host builds only -- STDIN/STDOUT via mruby-io.
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

      # Not String#chomp -- that's mruby-string-ext, which misbehaves under mrbtest.
      def strip_eol(line)
        len = line.size
        len -= 1 if len > 0 && line[len - 1] == "\n"
        len -= 1 if len > 0 && line[len - 1] == "\r"
        line[0, len]
      end
    end
  end
end
