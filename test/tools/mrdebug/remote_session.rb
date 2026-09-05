assert('RemoteSession forwards breakpoint operations to the wrapped Session') do
  session = MRDebug::Session.new
  remote = MRDebug::RemoteSession.new(session)

  assert_equal 1, remote.add_breakpoint('a.rb', 1)
  assert_equal 2, remote.add_breakpoint('b.rb', 2)
  assert_equal session.breakpoints, remote.breakpoints

  assert_true remote.remove_breakpoint(1)
  assert_false remote.remove_breakpoint(1)

  remote.clear_breakpoints
  assert_true session.breakpoints.all? { |bp| !bp.active? }
ensure
  MRDebug::Hook.uninstall
end

assert('RemoteSession forwards run/step/next mode changes to the wrapped Session') do
  session = MRDebug::Session.new
  remote = MRDebug::RemoteSession.new(session)

  remote.step_mode!
  assert_true session.on_line('a.rb', 1)

  remote.run_mode!
  session.add_breakpoint('a.rb', 5)
  assert_false session.on_line('a.rb', 1)
ensure
  MRDebug::Hook.uninstall
end

assert('RemoteSession#file/#line/#binding mirror the wrapped Session after a stop') do
  session = MRDebug::Session.new
  remote = MRDebug::RemoteSession.new(session)

  bnd = binding
  session.on_line('/x.rb', 7, bnd)

  assert_equal '/x.rb', remote.file
  assert_equal 7, remote.line
  assert_same bnd, remote.binding
ensure
  MRDebug::Hook.uninstall
end

assert('Command.dispatch continue/step/next resume the same via RemoteSession') do
  remote = MRDebug::RemoteSession.new(MRDebug::Session.new)

  out, action = MRDebug::Command.dispatch(remote, 'c')
  assert_equal [], out
  assert_equal :resume, action

  out, action = MRDebug::Command.dispatch(remote, 'step')
  assert_equal :resume, action

  out, action = MRDebug::Command.dispatch(remote, 'n')
  assert_equal :resume, action
ensure
  MRDebug::Hook.uninstall
end

assert('Command.dispatch break/delete/print work identically through RemoteSession') do
  session = MRDebug::Session.new
  remote = MRDebug::RemoteSession.new(session)
  session.on_line('/path/to/foo.rb', 5, binding)

  out, action = MRDebug::Command.dispatch(remote, 'break 10')
  assert_equal :stay, action
  assert_equal ['Breakpoint 1 added at /path/to/foo.rb:10'], out

  out, _ = MRDebug::Command.dispatch(remote, 'break')
  assert_equal ['  #1 /path/to/foo.rb:10'], out

  out, _ = MRDebug::Command.dispatch(remote, 'delete 1')
  assert_equal ['Deleted breakpoint #1'], out

  x = 42
  session.on_line('/path/to/foo.rb', 5, binding)
  out, _ = MRDebug::Command.dispatch(remote, 'print x')
  assert_equal ['42'], out
ensure
  MRDebug::Hook.uninstall
end

assert('Command.dispatch reports an unknown command through RemoteSession too') do
  remote = MRDebug::RemoteSession.new(MRDebug::Session.new)
  out, action = MRDebug::Command.dispatch(remote, 'xyz')
  assert_equal :stay, action
  assert_equal ['unknown command: xyz'], out
ensure
  MRDebug::Hook.uninstall
end
