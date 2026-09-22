module MRDebug
  module CLI
    # Bridges a Content-Length-framed DAP client (e.g. vscode-rdbg's
    # "attach", pointed at this server's port) to a device already
    # connected via DeviceLink's plain-text (prdb) protocol. Route (b) from
    # the design notes: no JSON/DAP ever reaches the device, only this
    # host-side process speaks it. One client at a time; #run blocks for
    # its whole lifetime.
    class DapServer
      CONTENT_LENGTH = 'Content-Length: '.freeze
      HEADER_END = "\r\n\r\n".freeze

      def initialize(device, dap_port, dap_host = '0.0.0.0')
        @device = device
        @bridge = DapBridge.new(device)
        @server = TCPServer.new(dap_host, dap_port)
      end

      def run
        client = @server.accept
        @server.close
        @buf = ''
        loop do
          drain_device_stops(client)
          ready, = IO.select([client, @device.io])
          next unless ready
          break if ready.include?(@device.io) && !handle_device(client)
          break if ready.include?(client) && !handle_client(client)
        end
      ensure
        client.close if client
      end

      private

      # Any response chunk already fully buffered on the device side (e.g.
      # queued up while we were busy) is drained before the next select,
      # so a stop already sitting in the buffer isn't missed.
      def drain_device_stops(client)
        while @device.chunk_ready?
          send_stop(client) if @device.try_extract
        end
      end

      # Returns false on EOF (device connection closed).
      def handle_device(client)
        lines = @device.poll
        send_stop(client) if lines
        true
      rescue EOFError
        false
      end

      # Returns false on EOF (client disconnected).
      def handle_client(client)
        data = read_some(client)
        return false if data.nil?
        @buf += data
        loop do
          msg, rest = extract_message(@buf)
          break unless msg
          @buf = rest
          request = Json.parse(msg)
          @bridge.handle(request).each { |m| write_message(client, m) }
        end
        true
      rescue EOFError
        false
      end

      def send_stop(client)
        reason = breakpoint_stop?(@device.stopped_by) ? 'breakpoint' : 'step'
        write_message(client, @bridge.stopped_notification(reason))
      end

      def breakpoint_stop?(banner)
        banner && banner[0, 10] == 'Breakpoint'
      end

      def write_message(client, msg)
        body = Json.generate(msg)
        client.write("#{CONTENT_LENGTH}#{body.size}\r\n\r\n#{body}")
      end

      # [message_body, remaining_buf], or [nil, buf] if not fully buffered.
      def extract_message(buf)
        header_end = buf.index(HEADER_END)
        return [nil, buf] unless header_end
        len = content_length(buf[0, header_end])
        return [nil, buf] unless len
        body_start = header_end + HEADER_END.size
        return [nil, buf] if buf.size < body_start + len
        [buf[body_start, len], buf[(body_start + len)..-1]]
      end

      def content_length(header)
        idx = header.index(CONTENT_LENGTH)
        return nil unless idx
        rest = header[(idx + CONTENT_LENGTH.size)..-1]
        eol = rest.index("\r\n") || rest.size
        rest[0, eol].to_i
      end

      def read_some(io)
        io.respond_to?(:sysread) ? io.sysread(4096) : io.readpartial(4096)
      rescue EOFError
        nil
      end
    end
  end
end
