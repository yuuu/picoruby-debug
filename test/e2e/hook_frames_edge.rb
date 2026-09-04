# Ported from e2e/scenarios/hook_frames_edge.rb.
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

target_line = __LINE__ + 2
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
  probe = HookFramesEdgeProbe.new(target_line)
  MRDebug::Hook.install(probe)
  MRDebug::Hook.armed = true
  hook_frames_edge_target
  MRDebug::Hook.armed = false
  MRDebug::Hook.uninstall

  assert_not_nil probe.results
  assert_true probe.results[:count] > 0
  assert_nil probe.results[:out_of_range_position]
  assert_nil probe.results[:out_of_range_binding]
  assert_nil probe.results[:negative_position]
ensure
  MRDebug::Hook.uninstall
end
