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
      else
        transport.write("(interim build: no remote device yet -- simulating a single local stop)\n")
        run_demo_session(options, transport)
      end
    end

    def self.usage
      "Usage: mrdebug [file[:line]]\n" \
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

    # Raw byte pump, not #gets-based: the device's "(prdb) " prompt has no
    # trailing newline, so a line-oriented read here would block forever
    # waiting for one. IO.select lets STDIN and the socket interrupt each
    # other instead.
    def self.relay(remote_io, transport, local_in = STDIN, local_out = STDOUT)
      loop do
        ready, = IO.select([remote_io, local_in])
        next unless ready
        if ready.include?(remote_io)
          local_out.write(remote_io.sysread(4096))
          local_out.flush
        end
        if ready.include?(local_in)
          remote_io.write(local_in.sysread(4096))
        end
      end
    rescue EOFError
      transport.write("\n(connection closed)\n")
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
