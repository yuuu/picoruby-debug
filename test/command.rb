# Every test here creates a Session, which registers itself with
# MRDebug::Hook (see test/session.rb's header for why the ensure matters).

assert('Command.dispatch continue/step/next resume without output') do
  session = MRDebug::Session.new

  out, action = MRDebug::Command.dispatch(session, 'c')
  assert_equal [], out
  assert_equal :resume, action

  out, action = MRDebug::Command.dispatch(session, 'step')
  assert_equal :resume, action

  out, action = MRDebug::Command.dispatch(session, 'n')
  assert_equal :resume, action

  out, action = MRDebug::Command.dispatch(session, '') # empty input == continue
  assert_equal :resume, action
ensure
  MRDebug::Hook.uninstall
end

assert('Command.dispatch break adds and lists breakpoints') do
  session = MRDebug::Session.new
  session.on_line('/path/to/foo.rb', 5, binding) # establishes the "current" file

  out, action = MRDebug::Command.dispatch(session, 'break 10')
  assert_equal :stay, action
  assert_equal ['Breakpoint 1 added at /path/to/foo.rb:10'], out

  out, _ = MRDebug::Command.dispatch(session, 'b other.rb:20')
  assert_equal ['Breakpoint 2 added at other.rb:20'], out

  out, _ = MRDebug::Command.dispatch(session, 'break')
  assert_equal ['  #1 /path/to/foo.rb:10', '  #2 other.rb:20'], out
ensure
  MRDebug::Hook.uninstall
end

assert('Command.dispatch break rejects an invalid line number') do
  session = MRDebug::Session.new
  session.on_line('/x.rb', 1, binding)
  out, action = MRDebug::Command.dispatch(session, 'break 0')
  assert_equal :stay, action
  assert_equal ['Invalid line number'], out
ensure
  MRDebug::Hook.uninstall
end

assert('Command.dispatch break with no prior stop has no current file') do
  session = MRDebug::Session.new
  out, _ = MRDebug::Command.dispatch(session, 'break 5')
  assert_equal ['Breakpoint 1 added at :5'], out
ensure
  MRDebug::Hook.uninstall
end

assert('Command.dispatch break with an "if" clause adds a conditional breakpoint') do
  session = MRDebug::Session.new
  session.on_line('/path/to/foo.rb', 5, binding)

  out, action = MRDebug::Command.dispatch(session, 'break 10 if x > 5')
  assert_equal :stay, action
  assert_equal ['Breakpoint 1 added at /path/to/foo.rb:10 if x > 5'], out
  assert_equal 'x > 5', session.breakpoints[0].condition

  out, _ = MRDebug::Command.dispatch(session, 'b other.rb:20 if y == 1')
  assert_equal ['Breakpoint 2 added at other.rb:20 if y == 1'], out

  out, _ = MRDebug::Command.dispatch(session, 'break')
  assert_equal ['  #1 /path/to/foo.rb:10 if x > 5', '  #2 other.rb:20 if y == 1'], out
ensure
  MRDebug::Hook.uninstall
end

assert('Command.dispatch break with no breakpoints set reports that') do
  session = MRDebug::Session.new
  out, _ = MRDebug::Command.dispatch(session, 'break')
  assert_equal ['No breakpoints set'], out
ensure
  MRDebug::Hook.uninstall
end

assert('Command.dispatch delete removes one breakpoint; numbers stay stable') do
  session = MRDebug::Session.new
  session.on_line('/x.rb', 1, binding)
  MRDebug::Command.dispatch(session, 'break 10')
  MRDebug::Command.dispatch(session, 'break 20')

  out, action = MRDebug::Command.dispatch(session, 'delete 1')
  assert_equal :stay, action
  assert_equal ['Deleted breakpoint #1'], out

  out, _ = MRDebug::Command.dispatch(session, 'd 1')
  assert_equal ['No breakpoint #1'], out

  out, _ = MRDebug::Command.dispatch(session, 'break')
  assert_equal ['  #2 /x.rb:20'], out
ensure
  MRDebug::Hook.uninstall
end

assert('Command.dispatch delete with no argument clears all breakpoints') do
  session = MRDebug::Session.new
  session.on_line('/x.rb', 1, binding)
  MRDebug::Command.dispatch(session, 'break 10')
  MRDebug::Command.dispatch(session, 'break 20')

  out, _ = MRDebug::Command.dispatch(session, 'delete')
  assert_equal ['Deleted all breakpoints'], out

  out, _ = MRDebug::Command.dispatch(session, 'break')
  assert_equal ['No breakpoints set'], out
ensure
  MRDebug::Hook.uninstall
end

assert('Command.dispatch print evaluates against the stopped binding') do
  session = MRDebug::Session.new
  x = 42
  session.on_line('/x.rb', 1, binding)

  out, action = MRDebug::Command.dispatch(session, 'print x')
  assert_equal :stay, action
  assert_equal ['42'], out
ensure
  MRDebug::Hook.uninstall
end

assert('Command.dispatch print reports a raised exception instead of crashing') do
  session = MRDebug::Session.new
  session.on_line('/x.rb', 1, binding)

  out, _ = MRDebug::Command.dispatch(session, 'p 1/0')
  assert_equal 1, out.size
  assert_true out[0].include?('ZeroDivisionError')
ensure
  MRDebug::Hook.uninstall
end

assert('Command.dispatch print with no binding available') do
  session = MRDebug::Session.new
  out, _ = MRDebug::Command.dispatch(session, 'print 1')
  assert_equal ['No binding available for this breakpoint'], out
ensure
  MRDebug::Hook.uninstall
end

assert('Command.dispatch print with no expression shows usage') do
  session = MRDebug::Session.new
  out, _ = MRDebug::Command.dispatch(session, 'print')
  assert_equal ['Usage: p <expression>'], out
ensure
  MRDebug::Hook.uninstall
end

assert('Command.dispatch reports an unknown command') do
  session = MRDebug::Session.new
  out, action = MRDebug::Command.dispatch(session, 'xyz')
  assert_equal :stay, action
  assert_equal ['unknown command: xyz'], out
ensure
  MRDebug::Hook.uninstall
end
