assert('DisplayExpression#expr and #result evaluate against the given binding') do
  x = 42
  d = MRDebug::DisplayExpression.new('x')
  assert_equal 'x', d.expr
  assert_equal '42', d.result(binding)
end

assert('DisplayExpression#result re-evaluates every time, not just once') do
  x = 1
  d = MRDebug::DisplayExpression.new('x')
  assert_equal '1', d.result(binding)
  x = 2
  assert_equal '2', d.result(binding)
end

assert('DisplayExpression#result reports a raised exception as a value, not a crash') do
  d = MRDebug::DisplayExpression.new('this_is_not_defined')
  assert_true d.result(binding).include?('NoMethodError')
end
