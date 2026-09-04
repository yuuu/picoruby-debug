# Ported from e2e/scenarios/session_next_from_binding_debugger.rb: known-risky
# case from docs/plan-phase1.md where a direct binding.debugger stop's "next" falls back to step.
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

inner_line = __LINE__ + 1
def session_next_fbd_inner(x)
  x + 1
end

debugger_line = __LINE__ + 2
def session_next_fbd_outer(x)
  binding.debugger
  session_next_fbd_inner(x)
  x * 2
end
call_line = debugger_line + 1
final_line = debugger_line + 2

assert('Session#next_mode! from a direct binding.debugger stop falls back to stepping every line') do
  session = SessionNextFromBindingDebuggerRecorder.new
  MRDebug.session = session

  session_next_fbd_outer(1)
  MRDebug::Hook.uninstall # step mode has no fast path; stop right away

  # Not a strict positional match: arming mid-callback also traces a couple
  # of MRDebug.break/Hook.enter's own mrblib lines while unwinding.
  assert_equal debugger_line, session.stops.first
  idx_call = session.stops.index(call_line)
  idx_inner = session.stops.index(inner_line)
  idx_final = session.stops.index(final_line)
  assert_not_nil idx_call
  assert_not_nil idx_inner
  assert_not_nil idx_final
  assert_true idx_call < idx_inner
  assert_true idx_inner < idx_final
ensure
  MRDebug::Hook.uninstall
end
