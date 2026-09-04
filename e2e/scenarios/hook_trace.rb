class Tracer
  attr_reader :seen
  def initialize; @seen = []; end
  def on_line(file, line)
    @seen << "#{file}:#{line}"
    nil
  end
end

def add(a, b)
  a + b
end

tracer = Tracer.new
MRDebug::Hook.install(tracer)
MRDebug::Hook.armed = true
x = 1
y = add(x, 2)
z = y * 2
MRDebug::Hook.armed = false
MRDebug::Hook.uninstall
puts "z=#{z}"
tracer.seen.each { |s| puts s }
