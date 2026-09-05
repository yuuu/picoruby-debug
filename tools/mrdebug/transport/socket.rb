module MRDebug
  module Transport
    # Host builds only -- mruby-socket.
    class Socket < Base
      attr_reader :io

      def initialize(io)
        @io = io
      end

      def gets
        line = @io.gets
        return nil if line.nil?
        strip_eol(line)
      end

      def write(str)
        @io.write(str)
      end

      def close
        @io.close
      end
    end

    class TCP < Socket
      def self.listen(port, host = '0.0.0.0')
        server = TCPServer.new(host, port)
        io = server.accept
        server.close
        new(io)
      end

      def self.connect(host, port)
        new(TCPSocket.new(host, port))
      end
    end

    class Unix < Socket
      def self.listen(path)
        File.delete(path) if File.exist?(path)
        server = UNIXServer.new(path)
        io = server.accept
        server.close
        new(io)
      end

      def self.connect(path)
        new(UNIXSocket.new(path))
      end
    end
  end
end
