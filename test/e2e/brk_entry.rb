# Ported from e2e/scenarios/brk_entry.rb.
class BrkEntryStub
  attr_reader :stops
  def initialize; @stops = []; end
  def on_line(file, line, bnd)
    @stops << [file, line, bnd && bnd.eval("defined?(x) ? x : nil")]
  end
end

def brk_entry_inner(x, expected)
  line = __LINE__; binding.debugger
  expected << [__FILE__, line, x]
  x + 1
end

def brk_entry_outer(x, expected)
  y = x * 2
  brk_entry_inner(y, expected)
  line = __LINE__; binding.b
  expected << [__FILE__, line, x]
end

assert('Binding#debugger/b/break report the exact call-site line and a working Binding') do
  MRDebug.session = BrkEntryStub.new
  expected = []

  x = 1
  line = __LINE__; binding.debugger
  expected << [__FILE__, line, x]

  brk_entry_outer(x, expected) # inner's binding.debugger, then outer's binding.b

  line = __LINE__; binding.break
  expected << [__FILE__, line, x]

  assert_equal expected, MRDebug.session.stops
ensure
  MRDebug::Hook.uninstall
end
