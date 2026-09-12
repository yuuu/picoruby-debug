assert('Transport::Loopback#gets returns queued input in order, then nil') do
  transport = MRDebug::Transport::Loopback.new(['n', 'p x', 'c'])
  assert_equal 'n', transport.gets
  assert_equal 'p x', transport.gets
  assert_equal 'c', transport.gets
  assert_nil transport.gets
end

assert('Transport::Loopback#push queues a message for a later #gets') do
  transport = MRDebug::Transport::Loopback.new(['n'])
  transport.push('c')
  assert_equal 'n', transport.gets
  assert_equal 'c', transport.gets
  assert_nil transport.gets
end

assert('Transport::Loopback#write records each call in #output, in order') do
  transport = MRDebug::Transport::Loopback.new
  transport.write('(prdb) ')
  transport.write("Stop: a.rb:1\n")
  assert_equal ['(prdb) ', "Stop: a.rb:1\n"], transport.output
end
