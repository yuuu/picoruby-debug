def dap_bridge_test_remote
  session = MRDebug::Session.new
  session.on_line('/device/foo.rb', 1, binding)
  MRDebug::RemoteSession.new(session)
end

assert('DapBridge.initialize handshake: capabilities + initialized event') do
  bridge = MRDebug::CLI::DapBridge.new(dap_bridge_test_remote)
  msgs = bridge.handle('seq' => 1, 'type' => 'request', 'command' => 'initialize')

  assert_equal 2, msgs.size
  assert_equal true, msgs[0]['success']
  assert_equal true, msgs[0]['body']['supportsConfigurationDoneRequest']
  assert_equal 'event', msgs[1]['type']
  assert_equal 'initialized', msgs[1]['event']
  assert_false bridge.handshake_done?
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge attach/launch are both accepted as a no-op before configurationDone') do
  bridge = MRDebug::CLI::DapBridge.new(dap_bridge_test_remote)
  %w[attach launch].each do |cmd|
    msgs = bridge.handle('seq' => 1, 'type' => 'request', 'command' => cmd)
    assert_equal 1, msgs.size
    assert_true msgs[0]['success']
  end
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge configurationDone completes the handshake and reports an entry stop') do
  bridge = MRDebug::CLI::DapBridge.new(dap_bridge_test_remote)
  msgs = bridge.handle('seq' => 1, 'type' => 'request', 'command' => 'configurationDone')

  assert_true bridge.handshake_done?
  assert_equal 2, msgs.size
  assert_true msgs[0]['success']
  assert_equal 'stopped', msgs[1]['event']
  assert_equal 'entry', msgs[1]['body']['reason']
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge rejects continue/next before configurationDone') do
  bridge = MRDebug::CLI::DapBridge.new(dap_bridge_test_remote)
  msgs = bridge.handle('seq' => 1, 'type' => 'request', 'command' => 'continue')
  assert_false msgs[0]['success']
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge setBreakpoints normalizes an absolute client path to a basename') do
  remote = dap_bridge_test_remote
  bridge = MRDebug::CLI::DapBridge.new(remote)

  request = {
    'seq' => 1, 'type' => 'request', 'command' => 'setBreakpoints',
    'arguments' => {
      'source' => { 'path' => '/Users/dev/workspace/foo.rb' }, # VS Code's absolute path
      'breakpoints' => [{ 'line' => 10 }, { 'line' => 20 }],
    },
  }
  msgs = bridge.handle(request)

  assert_true msgs[0]['success']
  assert_equal [10, 20], msgs[0]['body']['breakpoints'].map { |bp| bp['line'] }
  # The device's own LineBreakpoint suffix-matches against the basename,
  # not the client's full absolute path (see LineBreakpoint#match?).
  assert_equal 2, remote.breakpoints.select(&:active?).size
  assert_equal 'foo.rb', remote.breakpoints[0].file
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge setBreakpoints replaces the prior set for the same file') do
  remote = dap_bridge_test_remote
  bridge = MRDebug::CLI::DapBridge.new(remote)
  base_request = {
    'seq' => 1, 'type' => 'request', 'command' => 'setBreakpoints',
    'arguments' => { 'source' => { 'path' => 'foo.rb' }, 'breakpoints' => [{ 'line' => 10 }] },
  }
  bridge.handle(base_request)

  second_request = {
    'seq' => 2, 'type' => 'request', 'command' => 'setBreakpoints',
    'arguments' => { 'source' => { 'path' => 'foo.rb' }, 'breakpoints' => [{ 'line' => 99 }] },
  }
  bridge.handle(second_request)

  active = remote.breakpoints.select(&:active?)
  assert_equal 1, active.size
  assert_equal 99, active[0].line
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge continue/next/stepIn drive RemoteSession and report terminated') do
  remote = dap_bridge_test_remote
  bridge = MRDebug::CLI::DapBridge.new(remote)
  bridge.handle('seq' => 1, 'type' => 'request', 'command' => 'configurationDone')

  msgs = bridge.handle('seq' => 2, 'type' => 'request', 'command' => 'continue')
  assert_true msgs[0]['success']
  assert_equal 'terminated', msgs[1]['event']
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge threads reports a single fixed thread') do
  bridge = MRDebug::CLI::DapBridge.new(dap_bridge_test_remote)
  bridge.handle('seq' => 1, 'type' => 'request', 'command' => 'configurationDone')
  msgs = bridge.handle('seq' => 2, 'type' => 'request', 'command' => 'threads')
  assert_equal [{ 'id' => 1, 'name' => 'main' }], msgs[0]['body']['threads']
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge disconnect reports success and a terminated event') do
  bridge = MRDebug::CLI::DapBridge.new(dap_bridge_test_remote)
  bridge.handle('seq' => 1, 'type' => 'request', 'command' => 'configurationDone')
  msgs = bridge.handle('seq' => 2, 'type' => 'request', 'command' => 'disconnect')
  assert_true msgs[0]['success']
  assert_equal 'terminated', msgs[1]['event']
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge reports stackTrace/scopes/variables/evaluate/stepOut as not supported yet') do
  bridge = MRDebug::CLI::DapBridge.new(dap_bridge_test_remote)
  bridge.handle('seq' => 1, 'type' => 'request', 'command' => 'configurationDone')

  %w[stackTrace scopes variables evaluate stepOut].each do |cmd|
    msgs = bridge.handle('seq' => 2, 'type' => 'request', 'command' => cmd)
    assert_false msgs[0]['success']
    assert_true msgs[0]['message'].include?('not supported yet')
  end
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge reports an unsupported command instead of raising') do
  bridge = MRDebug::CLI::DapBridge.new(dap_bridge_test_remote)
  bridge.handle('seq' => 1, 'type' => 'request', 'command' => 'configurationDone')
  msgs = bridge.handle('seq' => 2, 'type' => 'request', 'command' => 'restart')
  assert_false msgs[0]['success']
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge converts a raised exception into a success:false response') do
  remote = dap_bridge_test_remote
  bridge = MRDebug::CLI::DapBridge.new(remote)
  bridge.handle('seq' => 1, 'type' => 'request', 'command' => 'configurationDone')

  request = {
    'seq' => 2, 'type' => 'request', 'command' => 'setBreakpoints',
    'arguments' => { 'source' => { 'path' => 'foo.rb' }, 'breakpoints' => 'not-an-array' },
  }
  msgs = bridge.handle(request)
  assert_false msgs[0]['success']
  assert_true msgs[0]['message'].size > 0
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge#handle_message round-trips full JSON request/response text') do
  bridge = MRDebug::CLI::DapBridge.new(dap_bridge_test_remote)
  request_json = MRDebug::CLI::Json.generate(
    'seq' => 1, 'type' => 'request', 'command' => 'initialize'
  )
  responses = bridge.handle_message(request_json)

  assert_equal 2, responses.size
  parsed = MRDebug::CLI::Json.parse(responses[0])
  assert_true parsed['success']
  assert_equal 'response', parsed['type']
ensure
  MRDebug::Hook.uninstall
end
