# Known-risky case: the FIRST stop is via binding.debugger (no VM hook
# involved, so Hook.frame_count sees no paused context), and the user
# immediately types "next" right there.
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

def outer(x)
  binding.debugger
  inner(x)
  x * 2
end

outer(1)

p session.stops
