# Minimal DAP (Debug Adapter Protocol) message framing over a TCP socket:
# `Content-Length: <n>\r\n\r\n<n bytes of JSON>`, same framing LSP/DAP both
# use. This class only does I/O + framing; DAP request/response semantics
# are a later phase.
#
# `picoruby-socket` is a soft dependency: it's a much bigger commitment
# (C bindings, per-platform network stack) than this gem's existing
# dependencies, so it's not declared in mrbgem.rake. A build without it
# still compiles; `DapTransport.available?` just returns false and every
# other method becomes a no-op, mirroring the `Object.const_defined?`
# pattern picoruby-bdffont uses for its own optional font gems.
class DapTransport
  def self.available?
    return @available unless @available.nil?
    begin
      require 'socket'
    rescue LoadError
      # picoruby-socket isn't part of this build.
    end
    @available = !!defined?(TCPServer)
  end

  def initialize(port)
    require 'json' # To save memory: only loaded once DapTransport is actually used
    @port = port
    @server = nil
    @socket = nil
  end

  def connected?
    !@socket.nil? && !@socket.closed?
  end

  # Blocks until a client connects. TCPServer#accept is itself a sleep_ms
  # poll loop (no IO.select in picoruby-socket), so this must be called
  # synchronously from the same task that's willing to block -- never from
  # a separate task/Fiber watching the debugged script.
  def listen
    return false unless self.class.available?
    @server = TCPServer.new(nil, @port)
    @socket = @server.accept
    true
  end

  # Reads one full message and returns its parsed JSON value, or nil on
  # EOF/malformed framing (either way, the connection should be treated as
  # closed).
  def receive_message
    return nil unless connected?
    headers = {}
    while (line = @socket.gets("\r\n"))
      line = line[0..-3] # drop the trailing "\r\n"
      break if line.empty?
      colon = line.index(':')
      next unless colon
      key = line[0...colon].strip
      value = line[(colon + 1)..-1].strip
      headers[key] = value
    end
    return nil if headers.empty?
    length = headers['Content-Length'].to_i
    return nil if length <= 0
    body = @socket.read(length)
    return nil if body.nil?
    JSON.parse(body)
  end

  def send_message(obj)
    return false unless connected?
    body = JSON.generate(obj)
    @socket.write("Content-Length: #{body.bytesize}\r\n\r\n")
    @socket.write(body)
    true
  end

  def close
    @socket&.close
    @server&.close
    @socket = nil
    @server = nil
  end

  # Phase 3 has no DAP semantics yet: just prove the framing/IO by
  # listening for one connection and echoing every message back until the
  # peer disconnects.
  def run_echo_loop
    return false unless listen
    while (msg = receive_message)
      send_message(msg)
    end
    close
    true
  end
end
