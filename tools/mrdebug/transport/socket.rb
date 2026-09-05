module MRDebug
  module Transport
    # Host builds only -- mruby-socket. #gets uses #sysread, not the
    # buffered IO#gets, to avoid an ESPIPE from #write's internal lseek.
    class Socket < Base
      attr_reader :io

      def initialize(io)
        @io = io
        @buf = ''
      end

      def gets
        loop do
          nl = @buf.index("\n")
          if nl
            line = @buf[0, nl]
            @buf = @buf[(nl + 1)..-1]
            return strip_eol(line)
          end
          @buf += @io.sysread(4096)
        end
      rescue EOFError
        return nil if @buf.empty?
        line = @buf
        @buf = ''
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
