module MRDebug
  # Device-side setup: opens a Session, blocks for the CLI to connect,
  # wires that connection to LocalConsole.
  def self.listen_tcp(port, host = '0.0.0.0')
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
end
