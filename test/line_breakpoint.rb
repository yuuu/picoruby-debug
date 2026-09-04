assert('LineBreakpoint#match? matches file suffix and exact line') do
  bp = MRDebug::LineBreakpoint.new('foo.rb', 10)
  assert_true bp.match?('/path/to/foo.rb', 10)
  assert_false bp.match?('/path/to/foo.rb', 11)
  assert_false bp.match?('/path/to/other.rb', 10)
end

assert('LineBreakpoint#deactivate! makes it inactive and unmatched') do
  bp = MRDebug::LineBreakpoint.new('foo.rb', 10)
  assert_true bp.active?
  bp.deactivate!
  assert_false bp.active?
  assert_false bp.match?('/path/to/foo.rb', 10)
end

assert('LineBreakpoint#to_s and #numbered_line') do
  bp = MRDebug::LineBreakpoint.new('foo.rb', 10)
  assert_equal 'foo.rb:10', bp.to_s
  assert_equal '  #3 foo.rb:10', bp.numbered_line(3)
end
