class FrameProbe
  def on_line(file, line)
    return unless line == 17 # inside innermost
    n = MRDebug::Hook.frame_count
    puts "frames=#{n}"
    n.times do |d|
      pos = MRDebug::Hook.frame_position(d)
      bnd = MRDebug::Hook.frame_binding(d)
      x = bnd ? bnd.eval("defined?(x) ? x : nil") : nil
      puts "  ##{d} #{pos.inspect} x=#{x.inspect}"
    end
    MRDebug::Hook.armed = false
  end
end

def inner(x)
  x + 1 # line 15
end

def outer(x)
  inner(x * 2)
end

MRDebug::Hook.install(FrameProbe.new)
MRDebug::Hook.armed = true
result = outer(10)
MRDebug::Hook.uninstall
puts "result=#{result}"
