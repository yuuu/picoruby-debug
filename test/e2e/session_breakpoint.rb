# Ported from e2e/scenarios/session_breakpoint.rb.
class SessionBreakpointRecorder < MRDebug::Session
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

target_line = __LINE__ + 2
def session_breakpoint_add(a, b)
  a + b
end

assert('Session, backed by the real VM hook, stops repeatedly at a set breakpoint') do
  session = SessionBreakpointRecorder.new
  MRDebug.session = session

  session.add_breakpoint(__FILE__, target_line)

  session_breakpoint_add(1, 2)
  session_breakpoint_add(3, 4)
  session_breakpoint_add(5, 6)

  assert_equal [target_line, target_line, target_line], session.stops
ensure
  MRDebug::Hook.uninstall
end
