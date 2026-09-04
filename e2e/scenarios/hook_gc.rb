# Forces a full mark while mrb->c is the debugger context and the debuggee's
# context hangs off ->prev: both must be marked, and the debugger context must
# carry no stale value from the previous callback.
class GcProbe
  attr_reader :n
  def initialize; @n = 0; end
  def on_line(file, line)
    @n += 1
    junk = (1..30).map { |i| "s#{i}-#{line}" }
    GC.start
    junk.size
  end
end

def walk(d, acc)
  return acc if d == 0
  walk(d - 1, acc + [d.to_s])
end

probe = GcProbe.new
MRDebug::Hook.install(probe)
MRDebug::Hook.armed = true
res = walk(40, [])
MRDebug::Hook.armed = false
MRDebug::Hook.uninstall
puts "callbacks=#{probe.n} len=#{res.length} first=#{res.first} last=#{res.last}"
GC.start
puts "ok"
