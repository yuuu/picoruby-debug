assert('WatchVarBreakpoint#changed? is true the first time it is checked') do
  w = MRDebug::WatchVarBreakpoint.new('1 + 1')
  assert_true w.changed?(binding)
end

assert('WatchVarBreakpoint#changed? is true only when the evaluated value differs from the last check') do
  x = 1
  w = MRDebug::WatchVarBreakpoint.new('x')
  assert_true w.changed?(binding)
  assert_false w.changed?(binding)
  x = 2
  assert_true w.changed?(binding)
  assert_false w.changed?(binding)
end

assert('WatchVarBreakpoint#changed? reports a raised exception as a value, not a crash') do
  w = MRDebug::WatchVarBreakpoint.new('this_is_not_defined')
  assert_true w.changed?(binding)
  assert_false w.changed?(binding)
end

assert('WatchVarBreakpoint#to_s and #numbered_line') do
  w = MRDebug::WatchVarBreakpoint.new('x + 1')
  assert_equal 'watch: x + 1', w.to_s
  assert_equal '  #2 watch: x + 1', w.numbered_line(2)
end

assert('WatchVarBreakpoint#stop_banner names itself and its number') do
  w = MRDebug::WatchVarBreakpoint.new('x')
  others = [MRDebug::WatchVarBreakpoint.new('a'), MRDebug::WatchVarBreakpoint.new('b'), w]
  assert_equal 'Watchpoint 3: /path/foo.rb:12', w.stop_banner(others, '/path/foo.rb:12')
end
