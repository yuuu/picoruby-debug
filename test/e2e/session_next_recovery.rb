# Ported from e2e/scenarios/session_next_recovery.rb: @direct_stop's offset
# compensation must not leak into a later, hook-triggered next on the same session.
class SessionNextRecoveryRecorder < MRDebug::Session
  attr_reader :stops
  def initialize
    super
    @stops = []
    @next_armed = false
  end
  def reset_for_next_run
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
def session_next_recovery_inner(x)
  x + 1
end

debugger_line = __LINE__ + 2
def session_next_recovery_via_binding_debugger(x)
  binding.debugger
  session_next_recovery_inner(x)
  x * 2
end
call_line1 = debugger_line + 1
final_line1 = debugger_line + 2

bp_line = __LINE__ + 2
def session_next_recovery_via_breakpoint(x)
  session_next_recovery_inner(x)
  x * 2
end

assert('Session#next_mode! tracks depth precisely on both a direct-stop and a later hook-triggered stop, same session') do
  session = SessionNextRecoveryRecorder.new
  MRDebug.session = session

  # Run 1: direct stop -> next must not descend into the call.
  session_next_recovery_via_binding_debugger(1)
  session.run_mode! # not Hook.uninstall: that would also clear hook.session, needed for run 2
  assert_equal [debugger_line, call_line1, final_line1], session.stops.first(3)
  assert_false session.stops.include?(inner_line)

  # Run 2: hook-triggered stop -> next must still track depth precisely,
  # proving run 1's @direct_stop offset didn't leak into this session.
  session.reset_for_next_run
  session.add_breakpoint(__FILE__, bp_line)
  session_next_recovery_via_breakpoint(2)
  MRDebug::Hook.uninstall

  assert_equal [bp_line, bp_line + 1], session.stops.first(2)
  assert_false session.stops.include?(inner_line)
ensure
  MRDebug::Hook.uninstall
end
