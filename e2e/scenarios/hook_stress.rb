# 1. the callback itself recurses deeply and allocates, forcing the debugger
#    context's cibase/stbase to grow while the debuggee is paused mid-recursion
# 2. the callback raises, which must not reach the debuggee
class Stress
  def initialize; @n = 0; @raised = 0; end
  attr_reader :n, :raised

  def deep(k)
    return [k.to_s] * 4 if k <= 0
    deep(k - 1) + [k.to_s]
  end

  def on_line(file, line)
    @n += 1
    deep(60)
    if @n % 7 == 0
      @raised += 1
      raise "boom from on_line"
    end
    nil
  end
end

def fact(n)
  return 1 if n <= 1
  n * fact(n - 1)
end

s = Stress.new
MRDebug::Hook.install(s)
MRDebug::Hook.armed = true
r = fact(120)
MRDebug::Hook.armed = false
MRDebug::Hook.uninstall
puts "callbacks=#{s.n} raised=#{s.raised}"
puts "fact(120) ok=#{r == (1..120).reduce(1) { |a, b| a * b }}"
GC.start
puts "gc ok"
