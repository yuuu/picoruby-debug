module MRDebug
  module CLI
    # `transport` is the CLI's own I/O (Stdio by default, swappable for a
    # Loopback in tests); --port/--sock-path hand off to #relay instead,
    # which talks to real STDIN/STDOUT directly.
    def self.start(argv, transport = MRDebug::Transport::Stdio.new)
      options = Options.parse(argv)

      if options.help
        transport.write("#{usage}\n")
      elsif options.version
        transport.write("mrdebug (interim build -- no wire protocol yet)\n")
      elsif options.port
        connect_tcp(options, transport)
      elsif options.sock_path
        connect_unix(options, transport)
      elsif options.unsupported
        transport.write("#{unsupported_message(options.unsupported)}\n")
      elsif argv.empty?
        connect_auto(transport)
      else
        transport.write("(interim build: no remote device yet -- simulating a single local stop)\n")
        run_demo_session(options, transport)
      end
    end

    # `mrdebug` with no args: MRDEBUG_SOCK, else MRDEBUG_PORT, else 4711.
    def self.connect_auto(transport)
      sock = MRDebug.default_sock
      if sock
        connect_unix(Options.parse(['--sock-path', sock]), transport)
      else
        connect_tcp(Options.parse(['--port', MRDebug.default_port.to_s]), transport)
      end
    end

    def self.usage
      "Usage: mrdebug [file[:line]]\n" \
      "  (no args)         connect to MRDEBUG_SOCK, else 127.0.0.1:MRDEBUG_PORT (#{MRDebug::DEFAULT_PORT})\n" \
      "  --port PORT        connect to a device listening on 127.0.0.1:PORT\n" \
      "  --sock-path PATH   connect to a device listening on a Unix socket\n" \
      "  --serial DEV, --open   (not supported yet)\n" \
      '  --help, --version'
    end

    def self.unsupported_message(flag)
      "#{flag}: not supported yet -- no serial transport exists. Use --port " \
      'or --sock-path against a device that called MRDebug.listen_tcp/listen_unix.'
    end

    TCP_HOST = '127.0.0.1'

    def self.connect_tcp(options, transport)
      remote = MRDebug::Transport::TCP.connect(TCP_HOST, options.port)
      transport.write("Connected to #{TCP_HOST}:#{options.port}\n")
      relay(remote.io, transport)
    rescue => e
      transport.write("connect #{TCP_HOST}:#{options.port} failed: #{e.class}: #{e.message}\n")
    ensure
      remote.close if remote
    end

    def self.connect_unix(options, transport)
      remote = MRDebug::Transport::Unix.connect(options.sock_path)
      transport.write("Connected to #{options.sock_path}\n")
      relay(remote.io, transport)
    rescue => e
      transport.write("connect #{options.sock_path} failed: #{e.class}: #{e.message}\n")
    ensure
      remote.close if remote
    end

    # Raw byte pump (the device's prompt has no trailing newline, so
    # #gets would block forever). Stops watching local_in on EOF rather
    # than ending the relay -- only the device closing its end does that.
    def self.relay(remote_io, transport, local_in = STDIN, local_out = STDOUT)
      local_open = true
      loop do
        watch = local_open ? [remote_io, local_in] : [remote_io]
        ready, = IO.select(watch)
        next unless ready
        if ready.include?(remote_io)
          drain(remote_io, local_out)
        end
        if local_open && ready.include?(local_in)
          begin
            remote_io.write(local_in.sysread(4096))
          rescue EOFError
            local_open = false
          end
        end
      end
    rescue EOFError
      transport.write("\n(connection closed)\n")
    end

    # A ready select() doesn't mean one sysread(4096) drains it all.
    def self.drain(io, out)
      loop do
        out.write(io.sysread(4096))
        out.flush
        break unless IO.select([io], nil, nil, 0)
      end
    end

    def self.run_demo_session(options, transport)
      session = MRDebug::Session.new
      remote = MRDebug::RemoteSession.new(session)
      session.on_line(options.file, options.line, binding)
      MRDebug::UI::LocalConsole.new(transport).on_stop(remote)
      transport.write("(session ended -- nothing more to run in this interim build)\n")
    ensure
      MRDebug::Hook.uninstall
    end
  end
end
