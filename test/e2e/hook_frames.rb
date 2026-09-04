# Ported from e2e/scenarios/hook_frames.rb.
class HookFramesProbe
  attr_reader :frames
  def initialize(target_line); @frames = nil; @target_line = target_line; end
  def on_line(file, line, bnd = nil)
    return unless line == @target_line
    n = MRDebug::Hook.frame_count
    @frames = (0...n).map do |d|
      pos = MRDebug::Hook.frame_position(d)
      b = MRDebug::Hook.frame_binding(d)
      x = b ? b.eval("defined?(x) ? x : nil") : nil
      [pos, x]
    end
    MRDebug::Hook.armed = false
  end
end

hook_frames_inner_line = __LINE__ + 2
def hook_frames_inner(x)
  x + 1
end

def hook_frames_outer(x)
  hook_frames_inner(x * 2)
end

assert('MRDebug::Hook.frame_count/frame_position/frame_binding walk the paused call stack, innermost first') do
  probe = HookFramesProbe.new(hook_frames_inner_line)
  MRDebug::Hook.install(probe)
  MRDebug::Hook.armed = true
  result = hook_frames_outer(10)
  MRDebug::Hook.armed = false
  MRDebug::Hook.uninstall

  assert_equal 21, result
  assert_not_nil probe.frames
  assert_true probe.frames.size >= 2

  pos0, x0 = probe.frames[0] # innermost: inside hook_frames_inner
  assert_equal [__FILE__, hook_frames_inner_line], pos0
  assert_equal 20, x0 # hook_frames_inner's own param x (10 * 2)

  _pos1, x1 = probe.frames[1] # one level out: inside hook_frames_outer
  assert_equal 10, x1 # hook_frames_outer's own param x
ensure
  MRDebug::Hook.uninstall
end
