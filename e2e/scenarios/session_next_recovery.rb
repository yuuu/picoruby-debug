# @direct_stop must reflect each stop independently: a binding.debugger
# stop's "next" falls back to step (see session_next_from_binding_debugger),
# but a separate, later hook-triggered stop must still track depth
# precisely -- the fallback must not stick around once we're past it.
class RecordingSession < MRDebug::Session
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

session = RecordingSession.new
MRDebug.session = session

def inner(x)
  x + 1
end

def outer_via_binding_debugger(x)
  binding.debugger
  inner(x)
  x * 2
end

def outer_via_breakpoint(x)
  inner(x)
  x * 2
end

outer_via_binding_debugger(1) # run 1: direct stop -> next falls back to step
run1_stops = session.stops.dup

session.run_mode! # also disarms the hook, so run 2 starts clean
session.reset_for_next_run
session.add_breakpoint(__FILE__, 45) # the inner(x) call inside outer_via_breakpoint
outer_via_breakpoint(2) # run 2: hook-triggered stop -> next tracks depth precisely

p run1_stops
p session.stops
