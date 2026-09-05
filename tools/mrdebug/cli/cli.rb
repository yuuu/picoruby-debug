module MRDebug
  module CLI
    # No wire protocol to connect over yet, so this manufactures a
    # single local stop instead of receiving one from a device -- proving a
    # compiled `mrdebug` binary can drive Command/LocalConsole through a
    # RemoteSession the way a wire-connected build eventually will.
    # `transport` defaults to Stdio but everything goes through it (not
    # straight to STDOUT), so a test can hand in a Loopback instead.
    def self.start(argv, transport = MRDebug::Transport::Stdio.new)
      options = Options.parse(argv)

      if options.help
        transport.write("#{usage}\n")
      elsif options.version
        transport.write("mrdebug (interim build -- no wire protocol yet)\n")
      elsif options.unsupported
        transport.write("#{unsupported_message(options.unsupported)}\n")
      else
        transport.write("(interim build: no remote device yet -- simulating a single local stop)\n")
        run_demo_session(options, transport)
      end
    end

    def self.usage
      "Usage: mrdebug [file[:line]]\n" \
      "  --port PORT, --sock-path PATH, --serial DEV, --open   (not supported yet)\n" \
      '  --help, --version'
    end

    def self.unsupported_message(flag)
      "#{flag}: not supported yet -- no wire protocol exists yet, so mrdebug " \
      'cannot attach to a remote device. Run with no connection flags for a ' \
      'local demo session instead.'
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
