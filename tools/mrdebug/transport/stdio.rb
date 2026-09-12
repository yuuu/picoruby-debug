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
    end
  end
end
