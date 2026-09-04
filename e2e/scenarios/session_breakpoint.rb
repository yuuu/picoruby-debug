# Records every line MRDebug::Session decides to stop at, without actually
# blocking on input -- the interactive loop is Step 7's job.
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

def add(a, b)
  a + b
end

session.add_breakpoint(__FILE__, 22)

add(1, 2)
add(3, 4)
add(5, 6)

p session.stops
