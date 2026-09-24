module MRDebug
  module CLI
    # Drives a device's existing plain-text (mrdbg) protocol (LocalConsole +
    # Command.dispatch, unchanged -- see tools/mrdebug/ui/local_console.rb)
    # as DapBridge's @remote, over a real Transport::TCP/Unix connection.
    # PROMPT never gets a trailing newline, which is exactly what makes it
    # usable as an end-of-response marker: everything buffered before the
    # first PROMPT match is that response's output lines.
    class DeviceLink
      PROMPT = '(mrdbg) '.freeze

      # Not Struct.new -- its dynamically-defined accessors have caused a
      # presym mismatch under mrbtest elsewhere in this gem (see CLAUDE.md's
      # "Avoid mruby-string-ext methods" note for the same class of bug).
      class Bp
        attr_accessor :file, :line, :active
        alias active? active

        def initialize(file, line, active)
          @file = file
          @line = line
          @active = active
        end
      end

      attr_reader :io, :stopped_by, :breakpoints

      def initialize(io)
        @io = io
        @buf = ''
        @breakpoints = []
        @stopped_by = nil
      end

      # Blocks for the device's first stop (the entry stop from
      # binding.debugger) -- call once right after connecting, before
      # handling any DAP requests.
      def wait_for_entry
        lines = wait_for_chunk
        @stopped_by = lines[0] if lines[0]
        lines
      end

      # True if a full response is already buffered -- lets a caller drain
      # everything pending before blocking in IO.select.
      def chunk_ready?
        !@buf.index(PROMPT).nil?
      end

      # Blocks until one full response chunk is available; returns its
      # output lines (used for the entry stop and :stay-style commands).
      def wait_for_chunk
        loop do
          lines = extract_chunk
          return lines if lines
          @buf += read_some(@io)
        end
      end

      # Call after IO.select reports @io readable: reads once, then returns
      # the parsed output lines if a full chunk just completed (also
      # updates #stopped_by), or nil if more data is still needed. The
      # first line of a chunk that follows a resume command
      # (run_mode!/next_mode!/step_mode!) is the device's *next* stop
      # banner, not an ack -- there is no separate ack in this protocol.
      def poll
        @buf += read_some(@io)
        try_extract
      end

      # Like #poll but never reads -- only returns a chunk already fully
      # buffered. Used to drain multiple stops that arrived in one read
      # without blocking on a select for data that's already here.
      def try_extract
        lines = extract_chunk
        return nil unless lines
        @stopped_by = lines[0] if lines[0]
        lines
      end

      def send(cmd)
        @io.write("#{cmd}\n")
      end

      # :stay-style command (break/delete/...): send + block for its echo.
      def command(cmd)
        send(cmd)
        wait_for_chunk
      end

      def add_breakpoint(file, line, condition = nil)
        @breakpoints << Bp.new(file, line, true)
        n = @breakpoints.size
        loc = condition ? "#{file}:#{line} if #{condition}" : "#{file}:#{line}"
        command("break #{loc}")
        n
      end

      def remove_breakpoint(n)
        bp = @breakpoints[n - 1]
        return false unless bp && bp.active?
        bp.active = false
        command("delete #{n}")
        true
      end

      # Raw content of `path` on the device (its `cat` command) -- for
      # DAP's `source` request, when VS Code has no local copy of a file
      # it only knows by the device's own path.
      def source(path)
        lines = command("cat #{path}")
        lines.join("\n")
      end

      # [[file, line], ...] from the device's `bt` command, parsing
      # "#N file:line" lines -- same shape as RemoteSession#backtrace's
      # direct Session#backtrace call, so DapBridge can treat either
      # @remote identically.
      def backtrace
        lines = command('bt')
        frames = []
        lines.each do |line|
          frame = parse_backtrace_line(line)
          frames << frame if frame
        end
        frames
      end

      # Resume commands never block: the next chunk is the device's *next*
      # stop, delivered later via #poll from the caller's own select loop,
      # not a synchronous reply to this call.
      def run_mode!
        send('c')
      end

      def next_mode!(count = 1)
        send(count > 1 ? "n #{count}" : 'n')
      end

      def step_mode!(count = 1)
        send(count > 1 ? "s #{count}" : 's')
      end

      def close
        @io.close
      end

      private

      def extract_chunk
        idx = @buf.index(PROMPT)
        return nil unless idx
        head = @buf[0, idx]
        @buf = @buf[(idx + PROMPT.size)..-1]
        head.empty? ? [] : head.split("\n")
      end

      def read_some(io)
        io.respond_to?(:sysread) ? io.sysread(4096) : io.readpartial(4096)
      end

      # "#N file:line" -> [file, line], or nil for a non-matching line
      # ("No frame information available").
      def parse_backtrace_line(line)
        sp = line.index(' ')
        return nil unless sp
        rest = line[(sp + 1)..-1]
        colon = rest.rindex(':')
        return nil unless colon
        [rest[0, colon], rest[(colon + 1)..-1].to_i]
      end
    end
  end
end
