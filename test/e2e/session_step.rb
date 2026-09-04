# Ported from e2e/scenarios/session_step.rb: `step` must stop at every
# subsequent line, including inside a call, via the real VM hook.
class SessionStepRecorder < MRDebug::Session
  attr_reader :stops
  def initialize
    super
    @stops = []
  end
  def on_line(file, line, bnd = nil)
    stopped = super
    @stops << line if stopped
    stopped
  end
end

inner_line = __LINE__ + 2
def session_step_inner(x)
  x + 1
end

outer_call_line = __LINE__ + 2
def session_step_outer(x)
  session_step_inner(x)
end

assert('Session#step_mode! stops at every line, including inside a call') do
  session = SessionStepRecorder.new
  MRDebug.session = session

  session.step_mode!
  session_step_outer(1)
  MRDebug::Hook.uninstall # stop tracing immediately -- step mode has no fast path

  assert_true session.stops.include?(outer_call_line)
  assert_true session.stops.include?(inner_line)
ensure
  MRDebug::Hook.uninstall
end
