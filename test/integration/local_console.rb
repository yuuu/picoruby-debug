# Exercises MRDebug::UI::LocalConsole through a Transport::Loopback instead
# of real stdio.

def with_session(session)
  MRDebug.session = session
  yield
ensure
  MRDebug::Hook.uninstall
end

assert('LocalConsole, driven by a Loopback transport, evaluates print and resumes on continue') do
  transport = MRDebug::Transport::Loopback.new(['p x', 'c'])
  session = MRDebug::Session.new
  session.ui = MRDebug::UI::LocalConsole.new(transport)

  line = nil
  with_session(session) do
    x = 41
    line = __LINE__; binding.debugger
    x # keep x reachable after the stop, for symmetry with other integration files
  end

  assert_equal [
    "Stop: #{__FILE__}:#{line}\n",
    '(mrdbg) ',
    "41\n",
    '(mrdbg) ',
  ], transport.output
ensure
  MRDebug::Hook.uninstall
end

assert('LocalConsole treats a nil #gets (transport EOF/disconnect) as continue, not an error') do
  transport = MRDebug::Transport::Loopback.new # empty queue: #gets returns nil immediately
  session = MRDebug::Session.new
  session.ui = MRDebug::UI::LocalConsole.new(transport)

  line = nil
  with_session(session) do
    line = __LINE__; binding.debugger
  end

  assert_equal ["Stop: #{__FILE__}:#{line}\n", '(mrdbg) '], transport.output
ensure
  MRDebug::Hook.uninstall
end

local_console_next_inner_line = __LINE__ + 1
def local_console_next_inner(x)
  x + 1
end

local_console_next_debugger_line = __LINE__ + 2
def local_console_next_outer(x)
  binding.debugger
  local_console_next_inner(x)
end
local_console_next_call_line = local_console_next_debugger_line + 1

assert('LocalConsole processes a whole piped-in command sequence across a next and a continue') do
  transport = MRDebug::Transport::Loopback.new(['p x', 'n', 'p x', 'c'])
  session = MRDebug::Session.new
  session.ui = MRDebug::UI::LocalConsole.new(transport)

  with_session(session) do
    local_console_next_outer(7)
  end

  assert_equal [
    "Stop: #{__FILE__}:#{local_console_next_debugger_line}\n",
    '(mrdbg) ',
    "7\n",
    '(mrdbg) ',
    "Stop: #{__FILE__}:#{local_console_next_call_line}\n",
    '(mrdbg) ',
    "7\n",
    '(mrdbg) ',
  ], transport.output
ensure
  MRDebug::Hook.uninstall
end

local_console_frame_inner_line = __LINE__ + 2
def local_console_frame_inner(x)
  binding.debugger
  x + 1
end

local_console_frame_outer_line = __LINE__ + 2
def local_console_frame_outer(x)
  local_console_frame_inner(x * 2)
end

assert('LocalConsole up/down/frame select a caller frame, and print evaluates against it') do
  transport = MRDebug::Transport::Loopback.new(
    ['p x', 'up', 'p x', 'list', 'down', 'p x', 'frame 1', 'frame', 'down', 'down', 'frame 99', 'c']
  )
  session = MRDebug::Session.new
  session.ui = MRDebug::UI::LocalConsole.new(transport)

  result = nil
  with_session(session) do
    result = local_console_frame_outer(10)
  end
  assert_equal 21, result

  out = transport.output.reject { |l| l == '(mrdbg) ' }
  assert_equal "Stop: #{__FILE__}:#{local_console_frame_inner_line}\n", out[0]
  assert_equal "20\n", out[1]
  assert_equal "#1 #{__FILE__}:#{local_console_frame_outer_line}\n", out[2]
  assert_equal "10\n", out[3]
  # list follows the selected frame: its marked line is the caller's call site.
  listing = out[4, 11]
  assert_true listing.include?("=> #{local_console_frame_outer_line}    local_console_frame_inner(x * 2)\n")
  rest = out[15..-1]
  assert_equal [
    "#0 #{__FILE__}:#{local_console_frame_inner_line}\n",
    "20\n",
    "#1 #{__FILE__}:#{local_console_frame_outer_line}\n",
    "#1 #{__FILE__}:#{local_console_frame_outer_line}\n",
    "#0 #{__FILE__}:#{local_console_frame_inner_line}\n",
    "Already at the innermost frame\n",
    "No frame #99\n",
  ], rest
ensure
  MRDebug::Hook.uninstall
end
