module MRDebug
  module CLI
    # --port/--sock-path take a value, so parsing walks argv by index
    # instead of a plain #each.
    class Options
      attr_reader :file, :line, :help, :version, :host, :port, :sock_path, :dap_port, :unsupported

      DEFAULT_HOST = '127.0.0.1'

      def self.parse(argv)
        new(argv)
      end

      def initialize(argv)
        @file = '(remote)'
        @line = 1
        @help = false
        @version = false
        @host = DEFAULT_HOST
        @port = nil
        @sock_path = nil
        @dap_port = nil
        @unsupported = nil

        i = 0
        while i < argv.size
          arg = argv[i]
          case arg
          when '--help', '-h'
            @help = true
          when '--version'
            @version = true
          when '--host'
            i += 1
            @host = argv[i]
          when '--port'
            i += 1
            @port = argv[i].to_i
          when '--sock-path'
            i += 1
            @sock_path = argv[i]
          when '--dap-port'
            i += 1
            @dap_port = argv[i].to_i
          when '--serial', '--open', '-O'
            @unsupported ||= arg
          else
            @file, @line = parse_location(arg) unless arg[0, 1] == '-'
          end
          i += 1
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
