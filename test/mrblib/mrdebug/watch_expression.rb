assert('WatchExpression#changed? is true the first time it is checked') do
  w = MRDebug::WatchExpression.new('1 + 1')
  assert_true w.changed?(binding)
end

assert('WatchExpression#changed? is true only when the evaluated value differs from the last check') do
  x = 1
  w = MRDebug::WatchExpression.new('x')
  assert_true w.changed?(binding)
  assert_false w.changed?(binding)
  x = 2
  assert_true w.changed?(binding)
  assert_false w.changed?(binding)
end

assert('WatchExpression#changed? reports a raised exception as a value, not a crash') do
  w = MRDebug::WatchExpression.new('this_is_not_defined')
  assert_true w.changed?(binding)
  assert_false w.changed?(binding)
end

assert('WatchExpression#to_s and #numbered_line') do
  w = MRDebug::WatchExpression.new('x + 1')
  assert_equal 'watch: x + 1', w.to_s
  assert_equal '  #2 watch: x + 1', w.numbered_line(2)
end
