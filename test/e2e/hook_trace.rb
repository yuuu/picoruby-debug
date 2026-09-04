# Ported from e2e/scenarios/hook_trace.rb.
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
  MRDebug::Hook.install(tracer)
  MRDebug::Hook.armed = true
  x = 1
  call_line = __LINE__ + 1
  y = hook_trace_add(x, 2)
  z = y * 2
  MRDebug::Hook.armed = false
  MRDebug::Hook.uninstall

  assert_equal 6, z
  assert_true tracer.seen.size > 0
  assert_true tracer.seen.all? { |file, _| file == __FILE__ }
  assert_true tracer.seen.any? { |_, line| line == call_line }
ensure
  MRDebug::Hook.uninstall
end
