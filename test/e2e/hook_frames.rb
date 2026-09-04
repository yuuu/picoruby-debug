# Consolidates hook_frames.rb + hook_frames_edge.rb: MRDebug::Hook's
# frame-walking API (frame_count/frame_position/frame_binding), both the
# normal call-stack walk and its edge cases (inert with no paused context,
# out-of-range/negative depths). Everything else about the VM hook lives
# in hook.rb.

# Small duplicate of hook.rb's own with_hook: each e2e file is loaded
# independently by mrbtest, and there's no cross-file require in this
# gem's e2e layer, so it's redefined here rather than shared.
#
# Plain positional `armed`, not a keyword argument -- see hook.rb's copy
# of this helper for why a kwarg default here crashes mrbtest itself.
def with_hook(stub, armed = true)
  MRDebug::Hook.install(stub)
  MRDebug::Hook.armed = true if armed
  yield
ensure
  MRDebug::Hook.uninstall
end

# --- Ported from e2e/scenarios/hook_frames.rb ---
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
  result = nil
  with_hook(probe) { result = hook_frames_outer(10) }

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

# --- Ported from e2e/scenarios/hook_frames_edge.rb ---
class HookFramesEdgeProbe
  attr_reader :results
  def initialize(target_line); @results = nil; @target_line = target_line; end
  def on_line(file, line, bnd = nil)
    return unless line == @target_line
    @results = {
      count: MRDebug::Hook.frame_count,
      out_of_range_position: MRDebug::Hook.frame_position(99),
      out_of_range_binding: MRDebug::Hook.frame_binding(99),
      negative_position: MRDebug::Hook.frame_position(-1),
    }
    MRDebug::Hook.armed = false
  end
end

hook_frames_edge_target_line = __LINE__ + 2
def hook_frames_edge_target
  1 + 1
end

assert('MRDebug::Hook.frame_* is inert outside a callback (no paused context)') do
  assert_nothing_raised do
    MRDebug::Hook.frame_count
    MRDebug::Hook.frame_position(0)
    MRDebug::Hook.frame_binding(0)
  end
end

assert('MRDebug::Hook.frame_position/frame_binding return nil for out-of-range or negative depths') do
  probe = HookFramesEdgeProbe.new(hook_frames_edge_target_line)
  with_hook(probe) { hook_frames_edge_target }

  assert_not_nil probe.results
  assert_true probe.results[:count] > 0
  assert_nil probe.results[:out_of_range_position]
  assert_nil probe.results[:out_of_range_binding]
  assert_nil probe.results[:negative_position]
ensure
  MRDebug::Hook.uninstall
end
