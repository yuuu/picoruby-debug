# install alone must not fire the hook; armed= toggles it; disarming from
# inside a callback must stop tracing after that line, not before.
class Toggle
  attr_reader :seen
  def initialize; @seen = []; end
  def on_line(file, line)
    @seen << line
    MRDebug::Hook.armed = false if line == 15
    nil
  end
end

def noisy
  1 + 1 # line 13
  2 + 2 # line 14
  3 + 3 # line 15 -- disarms itself here
  4 + 4 # line 16 -- must NOT be traced
end

t = Toggle.new
MRDebug::Hook.install(t)
noisy # not armed yet: no callbacks expected from this call
MRDebug::Hook.armed = true
noisy # armed until it disarms itself at line 15
MRDebug::Hook.uninstall
puts t.seen.inspect
