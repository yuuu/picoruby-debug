module MRDebug
  # Fallback for a port that's wanted but unspecified (bare listen_tcp,
  # `mrdebug` with no args). Matches rdbg's convention.
  DEFAULT_PORT = 4711

  # Opens a Session, blocks for the CLI to connect, wires it to LocalConsole.
  def self.listen_tcp(port = default_port, host = '0.0.0.0')
    session = Session.new
    session.ui = UI::LocalConsole.new(Transport::TCP.listen(port, host))
    self.session = session
    session
  end

  def self.listen_unix(path)
    session = Session.new
    session.ui = UI::LocalConsole.new(Transport::Unix.listen(path))
    self.session = session
    session
  end

  # The (prdb) prompt on this process's own STDIN/STDOUT -- no socket, no CLI.
  def self.attach_stdio
    session = Session.new
    session.ui = UI::LocalConsole.new
    self.session = session
    session
  end

  # MRDebug.break calls this on the first binding.debugger hit with no
  # session: MRDEBUG_SOCK -> Unix listener, MRDEBUG_PORT -> TCP listener,
  # neither -> the local console. One-shot via the @session.nil? gate.
  def self.autostart
    sock = default_sock
    return listen_unix(sock) if sock

    port = env_value('MRDEBUG_PORT')
    return listen_tcp(port.to_i) if port

    attach_stdio
  end

  def self.default_port
    port = env_value('MRDEBUG_PORT')
    port ? port.to_i : DEFAULT_PORT
  end

  def self.default_sock
    env_value('MRDEBUG_SOCK')
  end

  # nil when mruby-env is absent or the value is blank.
  def self.env_value(name)
    value = defined?(ENV) ? ENV[name] : nil
    value && !value.empty? ? value : nil
  end
end
