# `next` must not stop inside a call made from the recorded depth, only at
# the same or a shallower depth. next_mode! is called from on_line's own
# dynamic extent, as the real command loop will (Step 6/7): a breakpoint hit
# is hook-triggered, so Hook.frame_count correctly sees the paused context.
class RecordingSession < MRDebug::Session
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

session = RecordingSession.new
MRDebug.session = session

def inner(x)
  x + 1
end

def outer(x)
  inner(x)
  x * 2
end

session.add_breakpoint(__FILE__, 34)
outer(1)

p session.stops
