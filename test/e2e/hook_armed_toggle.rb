# Ported from e2e/scenarios/hook_armed_toggle.rb.
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
  MRDebug::Hook.install(t)
  hook_armed_toggle_noisy1
  assert_equal [], t.seen
ensure
  MRDebug::Hook.uninstall
end

assert('MRDebug::Hook.armed= disarming from inside the callback stops tracing after that line') do
  t = HookArmedToggle.new
  MRDebug::Hook.install(t)

  t.disarm_at = __LINE__ + 4
  MRDebug::Hook.armed = true
  def hook_armed_toggle_noisy2
    1 + 1 # traced
    2 + 2 # traced; disarms itself here
    3 + 3 # must NOT be traced
    4 + 4 # must NOT be traced
  end
  hook_armed_toggle_noisy2

  # Not an exact-array match: entering the method's own irep also traces
  # the "def" line itself, a VM codegen detail unrelated to this scenario.
  assert_true t.seen.size > 0
  assert_equal t.disarm_at, t.seen.last
  assert_false t.seen.include?(t.disarm_at + 1) # "3 + 3", must not be traced
  assert_false t.seen.include?(t.disarm_at + 2) # "4 + 4", must not be traced
ensure
  MRDebug::Hook.uninstall
end
