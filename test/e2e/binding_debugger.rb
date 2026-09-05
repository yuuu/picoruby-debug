# The direct Binding#debugger/#b/#break entry point, not a hook-triggered
# breakpoint (see session.rb for that).

def with_session(session)
  MRDebug.session = session
  yield
ensure
  MRDebug::Hook.uninstall
end

class BrkEntryStub
  attr_reader :stops
  def initialize; @stops = []; end
  def on_line(file, line, bnd)
    @stops << [file, line, bnd && bnd.eval("defined?(x) ? x : nil")]
  end
end

def brk_entry_inner(x, expected)
  line = __LINE__; binding.debugger
  expected << [__FILE__, line, x]
  x + 1
end

def brk_entry_outer(x, expected)
  y = x * 2
  brk_entry_inner(y, expected)
  line = __LINE__; binding.b
  expected << [__FILE__, line, x]
end

assert('Binding#debugger/b/break report the exact call-site line and a working Binding') do
  stub = BrkEntryStub.new
  expected = []

  with_session(stub) do
    x = 1
    line = __LINE__; binding.debugger
    expected << [__FILE__, line, x]

    brk_entry_outer(x, expected) # inner's binding.debugger, then outer's binding.b

    line = __LINE__; binding.break
    expected << [__FILE__, line, x]
  end

  assert_equal expected, stub.stops
ensure
  MRDebug::Hook.uninstall
end

class SessionNextFromBindingDebuggerRecorder < MRDebug::Session
  attr_reader :stops
  def initialize
    super
    @stops = []
    @next_armed = false
  end
  def on_line(file, line, bnd = nil)
    stopped = super
    return stopped unless stopped
    @stops << line
    unless @next_armed
      @next_armed = true
      next_mode!
    end
    stopped
  end
end

session_next_fbd_inner_line = __LINE__ + 1
def session_next_fbd_inner(x)
  x + 1
end

session_next_fbd_debugger_line = __LINE__ + 2
def session_next_fbd_outer(x)
  binding.debugger
  session_next_fbd_inner(x)
  x * 2
end
session_next_fbd_call_line = session_next_fbd_debugger_line + 1
session_next_fbd_final_line = session_next_fbd_debugger_line + 2

assert('Session#next_mode! from a direct binding.debugger stop tracks depth precisely, not stopping inside the call') do
  recorder = SessionNextFromBindingDebuggerRecorder.new
  with_session(recorder) do
    session_next_fbd_outer(1)
  end
  assert_equal [session_next_fbd_debugger_line, session_next_fbd_call_line, session_next_fbd_final_line],
               recorder.stops.first(3)
  assert_false recorder.stops.include?(session_next_fbd_inner_line)
ensure
  MRDebug::Hook.uninstall
end
