# `step` must stop at every subsequent line, including inside a call.
class RecordingSession < MRDebug::Session
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

session = RecordingSession.new
MRDebug.session = session

def inner(x)
  x + 1
end

def outer(x)
  inner(x)
end

session.step_mode!
outer(1)

p session.stops
