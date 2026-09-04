# Ported from e2e/scenarios/session_next_recovery.rb: a direct-stop "next"
# fallback to step must not stick around for a later, hook-triggered stop.
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

def session_next_recovery_inner(x)
  x + 1
end

def session_next_recovery_via_binding_debugger(x)
  binding.debugger
  session_next_recovery_inner(x)
  x * 2
end

bp_line = __LINE__ + 2
def session_next_recovery_via_breakpoint(x)
  session_next_recovery_inner(x)
  x * 2
end

assert('Session#next_mode! tracks depth precisely again on a later, hook-triggered stop, even after a direct-stop fallback earlier') do
  session = SessionNextRecoveryRecorder.new
  MRDebug.session = session

  # Run 1: direct stop -> next falls back to step.
  session_next_recovery_via_binding_debugger(1)
  session.run_mode! # not Hook.uninstall: that would also clear hook.session, needed for run 2

  # Run 2: hook-triggered stop -> next must track depth precisely again.
  session.reset_for_next_run
  session.add_breakpoint(__FILE__, bp_line)
  session_next_recovery_via_breakpoint(2)
  MRDebug::Hook.uninstall

  assert_equal [bp_line, bp_line + 1], session.stops.first(2)
ensure
  MRDebug::Hook.uninstall
end
