class MBTestBase
  def go; end
end

class MBTestSub < MBTestBase
end

module MBTestMod
  def moded; end
end

assert('MethodBreakpoint#to_s renders instance / singleton / bare / conditional forms') do
  assert_equal 'Foo#bar', MRDebug::MethodBreakpoint.new('Foo', 'bar').to_s
  assert_equal 'Foo.bar', MRDebug::MethodBreakpoint.new('Foo', 'bar', true).to_s
  assert_equal 'A::B#bar', MRDebug::MethodBreakpoint.new('A::B', 'bar').to_s
  assert_equal 'bar', MRDebug::MethodBreakpoint.new(nil, 'bar').to_s
  assert_equal 'Foo#bar if x > 1', MRDebug::MethodBreakpoint.new('Foo', 'bar', false, 'x > 1').to_s
end

assert('MethodBreakpoint#matches_call? uses is_a? for instance, identity for singleton') do
  inst = MRDebug::MethodBreakpoint.new('MBTestBase', 'go')
  assert_true inst.matches_call?(MBTestBase.new)
  assert_true inst.matches_call?(MBTestSub.new) # subclass: policy B
  assert_false inst.matches_call?(MBTestBase)   # the class itself is not an instance
  assert_false inst.matches_call?('a string')

  sing = MRDebug::MethodBreakpoint.new('MBTestBase', 'go', true)
  assert_true sing.matches_call?(MBTestBase)
  assert_false sing.matches_call?(MBTestSub)
  assert_false sing.matches_call?(MBTestBase.new)
end

assert('MethodBreakpoint#matches_call? with no class name matches any receiver, and a module matches includers') do
  any = MRDebug::MethodBreakpoint.new(nil, 'go')
  assert_true any.matches_call?(MBTestBase.new)
  assert_true any.matches_call?(42)

  mod = MRDebug::MethodBreakpoint.new('MBTestMod', 'moded')
  includer = Class.new { include MBTestMod }
  assert_true mod.matches_call?(includer.new)
end

assert('MethodBreakpoint#matches_call? is false while inactive or when the class is undefined') do
  bp = MRDebug::MethodBreakpoint.new('MBTestBase', 'go')
  bp.deactivate!
  assert_false bp.matches_call?(MBTestBase.new)

  assert_false MRDebug::MethodBreakpoint.new('NoSuchClassHere', 'go').matches_call?(MBTestBase.new)
end

assert('MethodBreakpoint#stop_banner names itself, its number, and flags a C method') do
  bp = MRDebug::MethodBreakpoint.new('Foo', 'bar')
  assert_equal 'Breakpoint 1: Foo#bar', bp.stop_banner([bp], 'x.rb:9')
  bp.cfunc!
  assert_equal 'Breakpoint 1: Foo#bar (about to call a C method)', bp.stop_banner([bp], 'x.rb:9')
end

assert('MethodBreakpoint#match? (file, line) is always false -- it is matched at the call site') do
  assert_false MRDebug::MethodBreakpoint.new('Foo', 'bar').match?('Foo.rb', 3)
end
