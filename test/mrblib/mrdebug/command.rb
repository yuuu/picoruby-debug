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

class CommandStepNextRecorder < MRDebug::Session
  attr_reader :step_counts, :next_counts
  def initialize
    super
    @step_counts = []
    @next_counts = []
  end
  def step_mode!(count = 1)
    @step_counts << count
    super
  end
  def next_mode!(count = 1)
    @next_counts << count
    super
  end
end

assert('Command.dispatch step/next parse an optional repeat count') do
  session = CommandStepNextRecorder.new
  MRDebug::Command.dispatch(session, 'step 3')
  MRDebug::Command.dispatch(session, 's')
  MRDebug::Command.dispatch(session, 'next 5')
  MRDebug::Command.dispatch(session, 'n')
  MRDebug::Command.dispatch(session, 'n 0')   # non-positive falls back to 1
  MRDebug::Command.dispatch(session, 'n abc') # non-numeric falls back to 1

  assert_equal [3, 1], session.step_counts
  assert_equal [5, 1, 1, 1], session.next_counts
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

assert('Command.dispatch display registers an expression, numbered sequentially') do
  session = MRDebug::Session.new
  session.on_line('/x.rb', 1, binding)

  out, action = MRDebug::Command.dispatch(session, 'display x')
  assert_equal :stay, action
  assert_equal ['1: x'], out

  out, _ = MRDebug::Command.dispatch(session, 'display y + 1')
  assert_equal ['2: y + 1'], out
ensure
  MRDebug::Hook.uninstall
end

assert('Command.dispatch display with no expression shows usage') do
  session = MRDebug::Session.new
  out, _ = MRDebug::Command.dispatch(session, 'display')
  assert_equal ['Usage: display <expression>'], out
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

assert('Command.dispatch list with no current position reports it') do
  session = MRDebug::Session.new
  out, action = MRDebug::Command.dispatch(session, 'list')
  assert_equal :stay, action
  assert_equal ['No current position (not stopped anywhere yet)'], out
ensure
  MRDebug::Hook.uninstall
end

assert('Command.dispatch list rejects an invalid line number') do
  session = MRDebug::Session.new
  session.on_line(__FILE__, 1, binding)
  out, action = MRDebug::Command.dispatch(session, 'list 0')
  assert_equal :stay, action
  assert_equal ['Invalid line number'], out
ensure
  MRDebug::Hook.uninstall
end

assert('Command.dispatch list reports a line past the end of the file') do
  session = MRDebug::Session.new
  session.on_line(__FILE__, 1, binding)
  out, _ = MRDebug::Command.dispatch(session, 'list 999999')
  assert_equal 1, out.size
  assert_true out[0].include?('out of range')
ensure
  MRDebug::Hook.uninstall
end

assert('Command.dispatch list <file>:<line> reports a read failure for a nonexistent file') do
  session = MRDebug::Session.new
  session.on_line(__FILE__, 1, binding)
  out, _ = MRDebug::Command.dispatch(session, 'list nonexistent-file-xyz.rb:5')
  assert_equal ['Cannot open nonexistent-file-xyz.rb'], out
ensure
  MRDebug::Hook.uninstall
end

assert('Command.dispatch list with no argument reads the current file (this test file) from disk') do
  session = MRDebug::Session.new
  session.on_line(__FILE__, 1, binding)
  out, action = MRDebug::Command.dispatch(session, 'list')
  assert_equal :stay, action
  assert_equal '=> 1  # Every test here creates a Session, which registers itself with', out.first
ensure
  MRDebug::Hook.uninstall
end

assert('Command.dispatch list <line> targets a different line of the current file') do
  session = MRDebug::Session.new
  session.on_line(__FILE__, 50, binding)
  out, _ = MRDebug::Command.dispatch(session, 'list 1')
  assert_equal '=> 1  # Every test here creates a Session, which registers itself with', out.first
ensure
  MRDebug::Hook.uninstall
end

list_probe_line1 = __LINE__ + 1
list_probe_a = 1 # list-probe-a
list_probe_line2 = __LINE__ + 1
list_probe_b = 2 # list-probe-b
list_probe_line3 = __LINE__ + 1
list_probe_c = 3 # list-probe-c

assert('Command.dispatch list shows 5 lines of context on each side, current line marked with =>') do
  session = MRDebug::Session.new
  session.on_line(__FILE__, list_probe_line2, binding)

  out, action = MRDebug::Command.dispatch(session, 'list')
  assert_equal :stay, action
  assert_equal 11, out.size

  marked = out.select { |l| l[0, 2] == '=>' }
  assert_equal 1, marked.size
  assert_equal "=> #{list_probe_line2}  list_probe_b = 2 # list-probe-b", marked[0]

  assert_true out.include?("   #{list_probe_line1}  list_probe_a = 1 # list-probe-a")
  assert_true out.include?("   #{list_probe_line3}  list_probe_c = 3 # list-probe-c")
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
