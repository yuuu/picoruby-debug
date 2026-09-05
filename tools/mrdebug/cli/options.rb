module MRDebug
  module CLI
    # Recognizes rdbg's own connection flags but reports them as "not
    # supported yet" (see CLI.start) -- RemoteSession has nowhere to
    # connect to until Phase3 ships a wire protocol.
    class Options
      attr_reader :file, :line, :help, :version, :unsupported

      def self.parse(argv)
        new(argv)
      end

      def initialize(argv)
        @file = '(remote)'
        @line = 1
        @help = false
        @version = false
        @unsupported = nil

        argv.each do |arg|
          case arg
          when '--help', '-h'
            @help = true
          when '--version'
            @version = true
          when '--port', '--sock-path', '--serial', '--open', '-O'
            @unsupported ||= arg
          else
            @file, @line = parse_location(arg) unless arg[0, 1] == '-'
          end
        end
      end

      private

      # `[<file>:]<line>`
      def parse_location(arg)
        colon = arg.rindex(':')
        return [arg, 1] unless colon
        [arg[0, colon], arg[(colon + 1)..-1].to_i]
      end
    end
  end
end
