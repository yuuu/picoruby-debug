# Ported from e2e/scenarios/hook_gc.rb: forces a full GC mark while paused
# inside the callback, so both contexts must stay reachable.
class HookGcProbe
  attr_reader :n
  def initialize; @n = 0; end
  def on_line(file, line, bnd = nil)
    @n += 1
    junk = (1..30).map { |i| "s#{i}-#{line}" }
    GC.start
    junk.size
  end
end

def hook_gc_walk(d, acc)
  return acc if d == 0
  hook_gc_walk(d - 1, acc + [d.to_s])
end

assert('MRDebug::Hook keeps both the debugger and debuggee context reachable across a GC.start inside the callback') do
  probe = HookGcProbe.new
  MRDebug::Hook.install(probe)
  MRDebug::Hook.armed = true
  res = hook_gc_walk(40, [])
  MRDebug::Hook.armed = false
  MRDebug::Hook.uninstall

  assert_true probe.n > 0
  assert_equal 40, res.length
  assert_equal '40', res.first
  assert_equal '1', res.last
  assert_nothing_raised { GC.start }
ensure
  MRDebug::Hook.uninstall
end
