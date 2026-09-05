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

assert('Session#display_lines is empty before any stop or with nothing registered') do
  session = MRDebug::Session.new
  assert_equal [], session.display_lines
  session.add_display('1 + 1')
  assert_equal [], session.display_lines # no stop yet: no binding to evaluate against
ensure
  MRDebug::Hook.uninstall
end

assert('Session#display_lines evaluates registered expressions against the stopped binding') do
  session = MRDebug::Session.new
  x = 42
  session.add_display('x')
  session.add_display('x + 1')
  session.on_line('/x.rb', 1, binding)
  assert_equal [['x', '42'], ['x + 1', '43']], session.display_lines
ensure
  MRDebug::Hook.uninstall
end

assert('Session#display_lines reports a raised exception instead of crashing') do
  session = MRDebug::Session.new
  session.add_display('this_is_not_defined')
  session.on_line('/x.rb', 1, binding)
  expr, result = session.display_lines[0]
  assert_equal 'this_is_not_defined', expr
  assert_true result.include?('NoMethodError')
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

assert('Session#step_mode!(N) skips the first N-1 matching lines before stopping') do
  # Stub Hook.armed= to a no-op -- step_mode! really arms the hook, so this
  # block's own subsequent lines would otherwise spend counts too. alias_method,
  # not remove_method: removing a singleton method that shadowed a C-defined
  # one deletes it outright instead of un-shadowing it.
  MRDebug::Hook.singleton_class.send(:alias_method, :orig_armed_setter_for_test, :armed=)
  MRDebug::Hook.define_singleton_method(:armed=) { |_flag| }
  begin
    session = MRDebug::Session.new
    session.step_mode!(3)
    assert_false session.on_line('a.rb', 1) # 1st match: skip
    assert_false session.on_line('a.rb', 2) # 2nd match: skip
    assert_true session.on_line('a.rb', 3)  # 3rd match: stop
    assert_true session.on_line('a.rb', 4)  # repeat count spent: back to stopping every line
  ensure
    MRDebug::Hook.uninstall
  end
ensure
  MRDebug::Hook.singleton_class.send(:alias_method, :armed=, :orig_armed_setter_for_test)
  MRDebug::Hook.singleton_class.send(:remove_method, :orig_armed_setter_for_test)
end

assert('Session#on_line with a Binding stops immediately, ignoring a pending repeat count') do
  session = MRDebug::Session.new
  session.step_mode!(5)
  assert_true session.on_line('x.rb', 1, binding)
ensure
  MRDebug::Hook.uninstall
end

assert('Session#next_mode! stops at the recorded depth or shallower') do
  # Hook.frame_count reads the live VM call stack (src/frame.c), which a
  # plain unit test doesn't control -- stub it so the :next comparison in
  # Session#should_break? can be checked deterministically, per
  # docs/plan-phase1.md's Verification 3.
  depth = [2]
  MRDebug::Hook.singleton_class.send(:alias_method, :orig_frame_count_for_test, :frame_count)
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
  MRDebug::Hook.singleton_class.send(:alias_method, :frame_count, :orig_frame_count_for_test)
  MRDebug::Hook.singleton_class.send(:remove_method, :orig_frame_count_for_test)
end

assert('Session#next_mode!(N) must satisfy the depth condition N times before stopping') do
  # Same Hook.armed= stub as step_mode!(N)'s test above, for the same reason.
  depth = [2]
  MRDebug::Hook.singleton_class.send(:alias_method, :orig_frame_count_for_test, :frame_count)
  MRDebug::Hook.define_singleton_method(:frame_count) { depth[0] }
  MRDebug::Hook.singleton_class.send(:alias_method, :orig_armed_setter_for_test, :armed=)
  MRDebug::Hook.define_singleton_method(:armed=) { |_flag| }
  begin
    session = MRDebug::Session.new
    session.next_mode!(3) # records next_depth = 2

    assert_false session.on_line('a.rb', 1) # 1st match at recorded depth: skip
    assert_false session.on_line('a.rb', 2) # 2nd match: skip
    assert_true session.on_line('a.rb', 3)  # 3rd match: stop
  ensure
    MRDebug::Hook.uninstall
  end
ensure
  MRDebug::Hook.singleton_class.send(:alias_method, :frame_count, :orig_frame_count_for_test)
  MRDebug::Hook.singleton_class.send(:remove_method, :orig_frame_count_for_test)
  MRDebug::Hook.singleton_class.send(:alias_method, :armed=, :orig_armed_setter_for_test)
  MRDebug::Hook.singleton_class.send(:remove_method, :orig_armed_setter_for_test)
end
