assert('OwnSource.file? matches mrdebug\'s own source by suffix') do
  assert_true MRDebug::OwnSource.file?('/home/user/mrdebug/mrblib/mrdebug.rb')
  assert_true MRDebug::OwnSource.file?('/home/user/mrdebug/mrblib/binding.rb')
  assert_true MRDebug::OwnSource.file?('/home/user/mrdebug/mrblib/mrdebug/session.rb')
  assert_true MRDebug::OwnSource.file?('/home/user/mrdebug/mrblib/mrdebug/command.rb')
  assert_true MRDebug::OwnSource.file?('/home/user/mrdebug/mrblib/mrdebug/display_expression.rb')
  assert_true MRDebug::OwnSource.file?('/home/user/mrdebug/mrblib/mrdebug/line_breakpoint.rb')
  assert_true MRDebug::OwnSource.file?('/home/user/mrdebug/mrblib/mrdebug/own_source.rb')
  assert_true MRDebug::OwnSource.file?('/home/user/mrdebug/mrblib/mrdebug/watch_var_breakpoint.rb')
  assert_true MRDebug::OwnSource.file?('/home/user/mrdebug/mrblib/mrdebug/transport.rb')
  assert_true MRDebug::OwnSource.file?('/home/user/mrdebug/mrblib/mrdebug/transport/loopback.rb')
  assert_true MRDebug::OwnSource.file?('/home/user/mrdebug/mrblib/mrdebug/ui.rb')
  assert_true MRDebug::OwnSource.file?('/home/user/mrdebug/tools/mrdebug/ui/local_console.rb')
  assert_true MRDebug::OwnSource.file?('/home/user/mrdebug/tools/mrdebug/transport/stdio.rb')
end

assert('OwnSource.file? does not match an unrelated user script') do
  assert_false MRDebug::OwnSource.file?('/home/user/app/script.rb')
  assert_false MRDebug::OwnSource.file?('script.rb')
  assert_false MRDebug::OwnSource.file?('/home/user/app/mrdebug_helper.rb') # similar name, not a real path match
end

assert('OwnSource.file? does not false-positive on a short or unrelated path') do
  assert_false MRDebug::OwnSource.file?('a.rb')
  assert_false MRDebug::OwnSource.file?('')
end
