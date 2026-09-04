# Binding#debugger/b/break must report the exact line they're called on --
# not a hook-derived approximation, since no VM hook fires for this path.
class StubSession
  attr_reader :stops
  def initialize; @stops = []; end
  def on_line(file, line, bnd)
    @stops << [file, line]
    puts "Breakpoint: #{file}:#{line}"
    puts "  x=#{bnd.eval("defined?(x) ? x : nil").inspect}" if bnd
  end
end

MRDebug.session = StubSession.new

def inner(x)
  binding.debugger
  x + 1
end

def outer(x)
  y = x * 2
  inner(y)
  binding.b
end

x = 1
binding.debugger
outer(x)
binding.break

p MRDebug.session.stops
