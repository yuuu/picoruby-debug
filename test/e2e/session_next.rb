# Ported from e2e/scenarios/session_next.rb.
class SessionNextRecorder < MRDebug::Session
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
      next_mode! # simulate the user typing "next" at this first stop
    end
    stopped
  end
end

inner_line = __LINE__ + 1
def session_next_inner(x)
  x + 1
end

bp_line = __LINE__ + 2
def session_next_outer(x)
  session_next_inner(x)
  x * 2
end

assert("Session#next_mode!, armed from a real breakpoint hit, does not stop inside a call") do
  session = SessionNextRecorder.new
  MRDebug.session = session

  session.add_breakpoint(__FILE__, bp_line)
  session_next_outer(1)
  MRDebug::Hook.uninstall # next mode never reverts to run on its own; stop right away

  # first(2): :next stays armed past this point, so the uninstall line itself also gets recorded.
  assert_equal [bp_line, bp_line + 1], session.stops.first(2)
  assert_false session.stops.include?(inner_line) # next must not stop inside the call
ensure
  MRDebug::Hook.uninstall
end
