# Every test here creates a Session, whose #initialize installs it as
# MRDebug::Hook's active session; adding a breakpoint or leaving step/next
# mode set also arms the VM hook. Hook.uninstall in each assert block's
# ensure keeps that from leaking into the rest of mrbtest's run (mruby's own
# test suite included) as a permanently-armed hook.

assert('Session#add_breakpoint numbers sequentially, 1-based') do
  session = MRDebug::Session.new
  assert_equal 1, session.add_breakpoint('a.rb', 1)
  assert_equal 2, session.add_breakpoint('b.rb', 2)
  assert_equal 3, session.add_breakpoint('c.rb', 3)
ensure
  MRDebug::Hook.uninstall
end

assert('Session#remove_breakpoint deactivates in place; numbers stay stable') do
  session = MRDebug::Session.new
  session.add_breakpoint('a.rb', 1)
  session.add_breakpoint('b.rb', 2)
  session.add_breakpoint('c.rb', 3)

  assert_true session.remove_breakpoint(2)
  assert_false session.remove_breakpoint(2) # already removed
  assert_false session.remove_breakpoint(99) # out of range

  assert_equal 4, session.add_breakpoint('d.rb', 4) # a fresh number, not a reused #2

  active_numbers = []
  session.breakpoints.each_with_index { |bp, i| active_numbers << i + 1 if bp.active? }
  assert_equal [1, 3, 4], active_numbers
ensure
  MRDebug::Hook.uninstall
end

assert('Session#clear_breakpoints deactivates all') do
  session = MRDebug::Session.new
  session.add_breakpoint('a.rb', 1)
  session.add_breakpoint('b.rb', 2)
  session.clear_breakpoints
  assert_true session.breakpoints.all? { |bp| !bp.active? }
ensure
  MRDebug::Hook.uninstall
end

assert('Session#on_line stops on a matching breakpoint in run mode') do
  session = MRDebug::Session.new
  session.add_breakpoint('foo.rb', 10)
  assert_true session.on_line('/path/to/foo.rb', 10)
  assert_equal '/path/to/foo.rb', session.file
  assert_equal 10, session.line
ensure
  MRDebug::Hook.uninstall
end

assert('Session#on_line does not stop on a non-matching file or line') do
  session = MRDebug::Session.new
  session.add_breakpoint('foo.rb', 10)
  assert_false session.on_line('/path/to/foo.rb', 11)
  assert_false session.on_line('/path/to/other.rb', 10)
ensure
  MRDebug::Hook.uninstall
end

assert('Session#on_line always stops when a Binding is given directly') do
  session = MRDebug::Session.new
  bnd = binding
  assert_true session.on_line('x.rb', 1, bnd)
  assert_same bnd, session.binding
ensure
  MRDebug::Hook.uninstall
end

assert('Session#step_mode! stops on every line') do
  session = MRDebug::Session.new
  session.step_mode!
  assert_true session.on_line('a.rb', 1)
  assert_true session.on_line('a.rb', 2)
  assert_true session.on_line('b.rb', 99)
ensure
  MRDebug::Hook.uninstall
end

assert('Session#next_mode! stops at the recorded depth or shallower') do
  # Hook.frame_count reads the live VM call stack (src/frame.c), which a
  # plain unit test doesn't control -- stub it so the :next comparison in
  # Session#should_break? can be checked deterministically, per
  # docs/plan-phase1.md's Verification 3.
  depth = [2]
  MRDebug::Hook.define_singleton_method(:frame_count) { depth[0] }
  begin
    session = MRDebug::Session.new
    session.next_mode! # records next_depth = 2 (the stub's current value)

    depth[0] = 3
    assert_false session.on_line('a.rb', 1) # deeper than recorded: keep going

    depth[0] = 2
    assert_true session.on_line('a.rb', 2) # same depth: stop

    depth[0] = 1
    assert_true session.on_line('a.rb', 3) # shallower: stop
  ensure
    MRDebug::Hook.uninstall
  end
ensure
  MRDebug::Hook.singleton_class.send(:remove_method, :frame_count)
end
