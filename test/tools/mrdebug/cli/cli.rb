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
  assert_equal '--serial', MRDebug::CLI::Options.parse(['--serial', '/dev/ttyUSB0']).unsupported
  assert_nil MRDebug::CLI::Options.parse(['--serial', '/dev/ttyUSB0']).port
end

assert('CLI::Options parses --port') do
  options = MRDebug::CLI::Options.parse(['--port', '4711'])
  assert_equal 4711, options.port
  assert_nil options.unsupported
end

assert('CLI::Options parses --sock-path') do
  options = MRDebug::CLI::Options.parse(['--sock-path', '/tmp/mrdebug.sock'])
  assert_equal '/tmp/mrdebug.sock', options.sock_path
  assert_nil options.unsupported
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
  MRDebug::CLI.start(['--serial', '/dev/ttyUSB0'], transport)
  assert_equal 1, transport.output.size
  assert_true transport.output[0].include?('not supported yet')
ensure
  MRDebug::Hook.uninstall
end

assert('CLI.start --port reports a connection failure instead of stalling on stdin') do
  server = TCPServer.new('127.0.0.1', 0)
  port = server.addr[1]
  server.close # nothing listens at `port` from here on

  transport = MRDebug::Transport::Loopback.new
  MRDebug::CLI.start(['--port', port.to_s], transport)

  out = transport.output.join
  assert_true out.include?("connect 127.0.0.1:#{port} failed")
end

assert('CLI.start --sock-path reports a connection failure instead of stalling on stdin') do
  transport = MRDebug::Transport::Loopback.new
  MRDebug::CLI.start(['--sock-path', '/tmp/mrdebug-cli-test-no-such.sock'], transport)

  out = transport.output.join
  assert_true out.include?('connect /tmp/mrdebug-cli-test-no-such.sock failed')
end

assert('CLI.start with no args auto-connects to MRDEBUG_PORT and reports failure instead of stalling') do
  server = TCPServer.new('127.0.0.1', 0)
  port = server.addr[1]
  server.close # nothing listens at `port` from here on

  saved_port = ENV['MRDEBUG_PORT']
  saved_sock = ENV['MRDEBUG_SOCK']
  ENV.delete('MRDEBUG_SOCK')
  ENV['MRDEBUG_PORT'] = port.to_s

  transport = MRDebug::Transport::Loopback.new
  MRDebug::CLI.start([], transport)

  out = transport.output.join
  assert_true out.include?("connect 127.0.0.1:#{port} failed")
ensure
  if saved_port.nil? then ENV.delete('MRDEBUG_PORT') else ENV['MRDEBUG_PORT'] = saved_port end
  if saved_sock.nil? then ENV.delete('MRDEBUG_SOCK') else ENV['MRDEBUG_SOCK'] = saved_sock end
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
