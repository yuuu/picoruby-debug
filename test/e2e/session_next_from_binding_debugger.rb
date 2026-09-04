# Ported from e2e/scenarios/session_next_from_binding_debugger.rb: a direct
# binding.debugger stop's "next" now tracks depth precisely via
# Session::DIRECT_STOP_FRAME_OFFSET, instead of falling back to step.
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

assert('Session#next_mode! from a direct binding.debugger stop tracks depth precisely, not stopping inside the call') do
  session = SessionNextFromBindingDebuggerRecorder.new
  MRDebug.session = session

  session_next_fbd_outer(1)
  MRDebug::Hook.uninstall # :next stays armed past this point, so this line itself also gets recorded

  assert_equal [debugger_line, call_line, final_line], session.stops.first(3)
  assert_false session.stops.include?(inner_line)
ensure
  MRDebug::Hook.uninstall
end
