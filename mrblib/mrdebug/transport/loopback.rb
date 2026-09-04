module MRDebug
  module Transport
    # In-process transport: no real I/O, just two plain Ruby queues. Feed it
    # the whole command sequence up front (or push to it as you go) and
    # inspect #output afterwards. This is what makes UI code (LocalConsole
    # and friends) testable without stdio, the same "return data, don't
    # touch I/O directly" split that MRDebug::Command already applies one
    # layer down. Also usable as a same-process embedding transport, not
    # just for tests.
    class Loopback < Base
      def initialize(input_lines = [])
        @input = input_lines.dup
        @output = []
      end

      attr_reader :output

      def gets
        @input.shift
      end

      # Feeds one more message for a subsequent #gets to return, without
      # replacing what's already queued.
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
