# Frame API outside a callback (hook.paused is nil) must be inert, not crash.
puts MRDebug::Hook.frame_count
p MRDebug::Hook.frame_position(0)
p MRDebug::Hook.frame_binding(0)

class P
  def on_line(file, line)
    return unless line == 18
    puts "count=#{MRDebug::Hook.frame_count}"
    p MRDebug::Hook.frame_position(99) # out of range
    p MRDebug::Hook.frame_binding(99)
    p MRDebug::Hook.frame_position(-1) # negative
    MRDebug::Hook.armed = false
  end
end

def target
  1 + 1 # line 21
end

MRDebug::Hook.install(P.new)
MRDebug::Hook.armed = true
target
MRDebug::Hook.uninstall
