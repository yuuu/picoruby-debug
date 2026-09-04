module MRDebug
  module Transport
    # In-process transport backed by two arrays; no real I/O.
    class Loopback < Base
      def initialize(input_lines = [])
        @input = input_lines.dup
        @output = []
      end

      attr_reader :output

      def gets
        @input.shift
      end

      def push(line)
        @input << line
      end

      def write(str)
        @output << str
      end

      def close
      end
    end
  end
end
