# Ported from e2e/scenarios/hook_stress.rb: the callback recurses deeply and
# occasionally raises, which must not reach or corrupt the debuggee.
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
  MRDebug::Hook.install(s)
  MRDebug::Hook.armed = true
  r = hook_stress_fact(120)
  MRDebug::Hook.armed = false
  MRDebug::Hook.uninstall

  assert_true s.n > 0
  assert_true s.raised > 0
  assert_equal (1..120).reduce(1) { |a, b| a * b }, r

  assert_nothing_raised { GC.start }
ensure
  MRDebug::Hook.uninstall
end
