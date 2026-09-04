# Consolidates what used to be 4 separate files (hook_trace.rb,
# hook_armed_toggle.rb, hook_gc.rb, hook_stress.rb): low-level
# MRDebug::Hook mechanics exercised directly against a bare object
# implementing #on_line, with no Session involved. The frame-walking API
# (frame_count/frame_position/frame_binding) has its own file,
# hook_frames.rb.

# Every scenario below repeated the same install/arm/uninstall dance;
# Hook.uninstall alone already disarms too (src/hook.c), so nothing else is
# needed on the way out.
#
# Plain positional `armed`, not a keyword argument: a kwarg default here
# triggers a real mrbc/mruby-test presym-table crash ("mrc_init_presym:
# Assertion `id == symTable[i].index + offset' failed") as soon as a
# callback wrapped by this helper does a real Binding#eval -- reproduced
# in isolation, not root-caused further (same class of build-time presym
# fragility as CLAUDE.md's mruby-string-ext note; not worth chasing
# further when a plain positional argument avoids it entirely).
def with_hook(stub, armed = true)
  MRDebug::Hook.install(stub)
  MRDebug::Hook.armed = true if armed
  yield
ensure
  MRDebug::Hook.uninstall
end

# --- Ported from e2e/scenarios/hook_trace.rb ---
class HookTraceTracer
  attr_reader :seen
  def initialize; @seen = []; end
  def on_line(file, line, bnd = nil)
    @seen << [file, line]
    nil
  end
end

def hook_trace_add(a, b)
  a + b
end

assert('MRDebug::Hook traces every executed line while armed, including inside a called method') do
  tracer = HookTraceTracer.new
  x = 1
  y = nil
  z = nil
  call_line = nil
  with_hook(tracer) do
    call_line = __LINE__ + 1
    y = hook_trace_add(x, 2)
    z = y * 2
  end

  assert_equal 6, z
  assert_true tracer.seen.size > 0
  assert_true tracer.seen.all? { |file, _| file == __FILE__ }
  assert_true tracer.seen.any? { |_, line| line == call_line }
ensure
  MRDebug::Hook.uninstall
end

# --- Ported from e2e/scenarios/hook_armed_toggle.rb ---
class HookArmedToggle
  attr_reader :seen
  attr_accessor :disarm_at
  def initialize; @seen = []; end
  def on_line(file, line, bnd = nil)
    @seen << line
    MRDebug::Hook.armed = false if line == @disarm_at
    nil
  end
end

def hook_armed_toggle_noisy1
  1 + 1
  2 + 2
end

assert('MRDebug::Hook.install alone does not arm the hook') do
  t = HookArmedToggle.new
  with_hook(t, false) { hook_armed_toggle_noisy1 }
  assert_equal [], t.seen
ensure
  MRDebug::Hook.uninstall
end

assert('MRDebug::Hook.armed= disarming from inside the callback stops tracing after that line') do
  t = HookArmedToggle.new

  with_hook(t) do
    t.disarm_at = __LINE__ + 3
    def hook_armed_toggle_noisy2
      1 + 1 # traced
      2 + 2 # traced; disarms itself here
      3 + 3 # must NOT be traced
      4 + 4 # must NOT be traced
    end
    hook_armed_toggle_noisy2
  end

  # Not an exact-array match: entering the method's own irep also traces
  # the "def" line itself, a VM codegen detail unrelated to this scenario.
  assert_true t.seen.size > 0
  assert_equal t.disarm_at, t.seen.last
  assert_false t.seen.include?(t.disarm_at + 1) # "3 + 3", must not be traced
  assert_false t.seen.include?(t.disarm_at + 2) # "4 + 4", must not be traced
ensure
  MRDebug::Hook.uninstall
end

# --- Ported from e2e/scenarios/hook_gc.rb: forces a full GC mark while
# paused inside the callback, so both the debugger's and the debuggee's
# context must stay reachable. ---
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
  res = nil
  with_hook(probe) { res = hook_gc_walk(40, []) }

  assert_true probe.n > 0
  assert_equal 40, res.length
  assert_equal '40', res.first
  assert_equal '1', res.last
  assert_nothing_raised { GC.start }
ensure
  MRDebug::Hook.uninstall
end

# --- Ported from e2e/scenarios/hook_stress.rb: the callback recurses
# deeply and occasionally raises, which must not reach or corrupt the
# debuggee. ---
class HookStress
  def initialize; @n = 0; @raised = 0; end
  attr_reader :n, :raised

  def deep(k)
    return [k.to_s] * 4 if k <= 0
    deep(k - 1) + [k.to_s]
  end

  def on_line(file, line, bnd = nil)
    @n += 1
    deep(60)
    if @n % 7 == 0
      @raised += 1
      raise "boom from on_line"
    end
    nil
  end
end

def hook_stress_fact(n)
  return 1 if n <= 1
  n * hook_stress_fact(n - 1)
end

assert('MRDebug::Hook survives a deep-recursing, occasionally-raising callback without corrupting the debuggee') do
  s = HookStress.new
  r = nil
  with_hook(s) { r = hook_stress_fact(120) }

  assert_true s.n > 0
  assert_true s.raised > 0
  assert_equal (1..120).reduce(1) { |a, b| a * b }, r

  assert_nothing_raised { GC.start }
ensure
  MRDebug::Hook.uninstall
end
