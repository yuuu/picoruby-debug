# MRDebug.autostart / MRDEBUG_PORT / MRDEBUG_SOCK (tools/mrdebug/device.rb).
# listen_tcp/listen_unix are stubbed so nothing actually binds.

def with_env(name, value)
  saved = ENV[name]
  if value.nil?
    ENV.delete(name)
  else
    ENV[name] = value
  end
  yield
ensure
  if saved.nil?
    ENV.delete(name)
  else
    ENV[name] = saved
  end
end

assert('MRDebug.default_port honors MRDEBUG_PORT, falls back to DEFAULT_PORT, ignores blank') do
  with_env('MRDEBUG_PORT', nil) do
    assert_equal MRDebug::DEFAULT_PORT, MRDebug.default_port
  end
  with_env('MRDEBUG_PORT', '5005') do
    assert_equal 5005, MRDebug.default_port
  end
  with_env('MRDEBUG_PORT', '') do
    assert_equal MRDebug::DEFAULT_PORT, MRDebug.default_port
  end
end

assert('MRDebug.default_sock returns MRDEBUG_SOCK, else nil, ignores blank') do
  with_env('MRDEBUG_SOCK', nil) do
    assert_nil MRDebug.default_sock
  end
  with_env('MRDEBUG_SOCK', '/tmp/mrdebug-test.sock') do
    assert_equal '/tmp/mrdebug-test.sock', MRDebug.default_sock
  end
  with_env('MRDEBUG_SOCK', '') do
    assert_nil MRDebug.default_sock
  end
end

assert('MRDebug.autostart: MRDEBUG_PORT -> TCP listener, MRDEBUG_SOCK -> Unix listener') do
  saved_tcp = MRDebug.method(:listen_tcp)
  saved_unix = MRDebug.method(:listen_unix)
  calls = []
  MRDebug.define_singleton_method(:listen_tcp) { |*a| calls << [:tcp, *a] }
  MRDebug.define_singleton_method(:listen_unix) { |*a| calls << [:unix, *a] }

  with_env('MRDEBUG_SOCK', nil) do
    with_env('MRDEBUG_PORT', '6120') do
      MRDebug.autostart
      assert_equal [[:tcp, 6120]], calls
    end
  end

  calls.clear
  with_env('MRDEBUG_SOCK', '/tmp/mrdebug-auto.sock') do
    MRDebug.autostart
    assert_equal [[:unix, '/tmp/mrdebug-auto.sock']], calls
  end
ensure
  MRDebug.define_singleton_method(:listen_tcp) { |*a| saved_tcp.call(*a) }
  MRDebug.define_singleton_method(:listen_unix) { |*a| saved_unix.call(*a) }
end

assert('MRDebug.autostart with neither env var attaches the local stdio console, no listener') do
  saved_tcp = MRDebug.method(:listen_tcp)
  saved_unix = MRDebug.method(:listen_unix)
  listened = false
  MRDebug.define_singleton_method(:listen_tcp) { |*| listened = true }
  MRDebug.define_singleton_method(:listen_unix) { |*| listened = true }

  with_env('MRDEBUG_SOCK', nil) do
    with_env('MRDEBUG_PORT', nil) do
      MRDebug.autostart
    end
  end

  assert_false listened
  assert_true MRDebug.session.is_a?(MRDebug::Session)
  assert_true MRDebug.session.ui.is_a?(MRDebug::UI::LocalConsole)
ensure
  MRDebug.define_singleton_method(:listen_tcp) { |*a| saved_tcp.call(*a) }
  MRDebug.define_singleton_method(:listen_unix) { |*a| saved_unix.call(*a) }
  MRDebug.instance_variable_set(:@session, nil)
  MRDebug::Hook.uninstall
end

assert('MRDebug.break runs autostart while no session is configured, and stops once one exists') do
  saved_autostart = MRDebug.method(:autostart)
  autostart_calls = 0
  MRDebug.define_singleton_method(:autostart) { autostart_calls += 1 }

  MRDebug.instance_variable_set(:@session, nil)
  MRDebug.break(binding)
  MRDebug.break(binding)
  assert_equal 2, autostart_calls # stub sets no session, so every stop retries

  MRDebug.session = MRDebug::Session.new
  MRDebug.break(binding)
  assert_equal 2, autostart_calls # session set: autostart skipped
ensure
  MRDebug.define_singleton_method(:autostart) { saved_autostart.call }
  MRDebug.instance_variable_set(:@session, nil)
  MRDebug::Hook.uninstall
end
