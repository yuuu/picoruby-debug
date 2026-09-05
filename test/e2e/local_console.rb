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
    x # keep x reachable after the stop, for symmetry with other e2e files
  end

  assert_equal [
    "Breakpoint: #{__FILE__}:#{line}\n",
    '(prdb) ',
    "41\n",
    '(prdb) ',
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

  assert_equal ["Breakpoint: #{__FILE__}:#{line}\n", '(prdb) '], transport.output
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
    "Breakpoint: #{__FILE__}:#{local_console_next_debugger_line}\n",
    '(prdb) ',
    "7\n",
    '(prdb) ',
    "Breakpoint: #{__FILE__}:#{local_console_next_call_line}\n",
    '(prdb) ',
    "7\n",
    '(prdb) ',
  ], transport.output
ensure
  MRDebug::Hook.uninstall
end
