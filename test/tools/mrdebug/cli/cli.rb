assert('CLI::Options parses a bare file:line') do
  options = MRDebug::CLI::Options.parse(['foo.rb:42'])
  assert_equal 'foo.rb', options.file
  assert_equal 42, options.line
  assert_false options.help
  assert_false options.version
  assert_nil options.unsupported
end

assert('CLI::Options defaults file/line when none is given') do
  options = MRDebug::CLI::Options.parse([])
  assert_equal '(remote)', options.file
  assert_equal 1, options.line
end

assert('CLI::Options treats a location with no colon as line 1') do
  options = MRDebug::CLI::Options.parse(['just_a_file.rb'])
  assert_equal 'just_a_file.rb', options.file
  assert_equal 1, options.line
end

assert('CLI::Options recognizes --help/--version') do
  assert_true MRDebug::CLI::Options.parse(['--help']).help
  assert_true MRDebug::CLI::Options.parse(['-h']).help
  assert_true MRDebug::CLI::Options.parse(['--version']).version
end

assert('CLI::Options flags a connection flag as unsupported') do
  assert_equal '--port', MRDebug::CLI::Options.parse(['--port', '1234']).unsupported
  assert_equal '--sock-path', MRDebug::CLI::Options.parse(['--sock-path', '/tmp/x']).unsupported
  assert_equal '--serial', MRDebug::CLI::Options.parse(['--serial', '/dev/ttyUSB0']).unsupported
end

assert('CLI.start --help writes usage and never opens a Session') do
  transport = MRDebug::Transport::Loopback.new
  MRDebug::CLI.start(['--help'], transport)
  assert_equal 1, transport.output.size
  assert_true transport.output[0].include?('Usage: mrdebug')
ensure
  MRDebug::Hook.uninstall
end

assert('CLI.start with a connection flag reports it as unsupported, no Session') do
  transport = MRDebug::Transport::Loopback.new
  MRDebug::CLI.start(['--port', '1234'], transport)
  assert_equal 1, transport.output.size
  assert_true transport.output[0].include?('not supported yet')
ensure
  MRDebug::Hook.uninstall
end

assert('CLI.start with no args runs a demo session against RemoteSession end to end') do
  transport = MRDebug::Transport::Loopback.new(['print 1 + 1', 'continue'])
  MRDebug::CLI.start(['foo.rb:10'], transport)

  out = transport.output.join
  assert_true out.include?('Breakpoint: foo.rb:10')
  assert_true out.include?('2')
  assert_true out.include?('session ended')
ensure
  MRDebug::Hook.uninstall
end

assert('CLI.start demo session resumes on step/next same as a real Session would') do
  transport = MRDebug::Transport::Loopback.new(['n'])
  MRDebug::CLI.start(['foo.rb:1'], transport)
  assert_true transport.output.join.include?('session ended')
ensure
  MRDebug::Hook.uninstall
end

assert('CLI.run_demo_session wires RemoteSession, not the Session, into LocalConsole') do
  transport = MRDebug::Transport::Loopback.new(['continue'])
  MRDebug::CLI.run_demo_session(MRDebug::CLI::Options.new(['x.rb:5']), transport)
  assert_true transport.output.join.include?('Breakpoint: x.rb:5')
ensure
  MRDebug::Hook.uninstall
end
