# Consolidates brk_entry.rb (Binding#debugger/#b/#break's own file/line/
# Binding correctness) and session_next_from_binding_debugger.rb (Session's
# next_mode! tracking depth precisely from a *direct* stop, via
# Session::DIRECT_STOP_FRAME_OFFSET) -- both exercise the direct
# Binding#debugger/#b/#break entry point rather than a hook-triggered
# breakpoint. Hook-triggered Session behavior lives in session.rb.

# Small duplicate of session.rb's own with_session: each e2e file is loaded
# independently by mrbtest, and there's no cross-file require in this
# gem's e2e layer, so it's redefined here rather than shared.
def with_session(session)
  MRDebug.session = session
  yield
ensure
  MRDebug::Hook.uninstall
end

# --- Ported from e2e/scenarios/brk_entry.rb ---
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

# --- Ported from e2e/scenarios/session_next_from_binding_debugger.rb: a
# direct binding.debugger stop's "next" tracks depth precisely via
# Session::DIRECT_STOP_FRAME_OFFSET, instead of falling back to step. ---
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
  # :next stays armed past with_session's own Hook.uninstall, so that line
  # itself also gets recorded as a 3rd stop -- hence checking only first(3).
  assert_equal [session_next_fbd_debugger_line, session_next_fbd_call_line, session_next_fbd_final_line],
               recorder.stops.first(3)
  assert_false recorder.stops.include?(session_next_fbd_inner_line)
ensure
  MRDebug::Hook.uninstall
end
