assert('Json.generate encodes scalars') do
  assert_equal 'null', MRDebug::CLI::Json.generate(nil)
  assert_equal 'true', MRDebug::CLI::Json.generate(true)
  assert_equal 'false', MRDebug::CLI::Json.generate(false)
  assert_equal '42', MRDebug::CLI::Json.generate(42)
  assert_equal '"hi"', MRDebug::CLI::Json.generate('hi')
  assert_equal '"hi"', MRDebug::CLI::Json.generate(:hi)
end

assert('Json.generate escapes quotes, backslashes and control characters') do
  assert_equal '"a\\"b"', MRDebug::CLI::Json.generate('a"b')
  assert_equal '"a\\\\b"', MRDebug::CLI::Json.generate('a\\b')
  assert_equal '"a\\nb"', MRDebug::CLI::Json.generate("a\nb")
  assert_equal '"a\\u0001b"', MRDebug::CLI::Json.generate("a\x01b")
end

assert('Json.generate encodes arrays and hashes, preserving key order') do
  assert_equal '[1,2,3]', MRDebug::CLI::Json.generate([1, 2, 3])
  assert_equal '{"a":1,"b":[true,null]}', MRDebug::CLI::Json.generate('a' => 1, 'b' => [true, nil])
end

assert('Json.generate uses hash keys as strings via #to_s') do
  assert_equal '{"seq":1}', MRDebug::CLI::Json.generate(seq: 1)
end

assert('Json.parse decodes scalars') do
  assert_nil MRDebug::CLI::Json.parse('null')
  assert_true MRDebug::CLI::Json.parse('true')
  assert_false MRDebug::CLI::Json.parse('false')
  assert_equal 42, MRDebug::CLI::Json.parse('42')
  assert_equal(-7, MRDebug::CLI::Json.parse('-7'))
  assert_equal 'hi', MRDebug::CLI::Json.parse('"hi"')
end

assert('Json.parse decodes floats built without String#to_f') do
  assert_float 3.14, MRDebug::CLI::Json.parse('3.14')
  assert_float(-0.5, MRDebug::CLI::Json.parse('-0.5'))
  assert_float 150.0, MRDebug::CLI::Json.parse('1.5e2')
end

assert('Json.parse decodes escaped strings') do
  assert_equal 'a"b', MRDebug::CLI::Json.parse('"a\\"b"')
  assert_equal "a\nb", MRDebug::CLI::Json.parse('"a\\nb"')
  assert_equal 'AB', MRDebug::CLI::Json.parse('"\\u0041\\u0042"')
end

assert('Json.parse decodes nested arrays/objects and skips whitespace') do
  parsed = MRDebug::CLI::Json.parse(" { \"a\" : [1, 2, {\"b\": true}] } ")
  assert_equal({ 'a' => [1, 2, { 'b' => true }] }, parsed)
end

assert('Json.parse raises MRDebug::CLI::Json::ParseError on malformed input') do
  assert_raise(MRDebug::CLI::Json::ParseError) { MRDebug::CLI::Json.parse('{') }
  assert_raise(MRDebug::CLI::Json::ParseError) { MRDebug::CLI::Json.parse('[1, ') }
  assert_raise(MRDebug::CLI::Json::ParseError) { MRDebug::CLI::Json.parse('nul') }
end

assert('Json round-trips a DAP-shaped request') do
  request = {
    'seq' => 1,
    'type' => 'request',
    'command' => 'setBreakpoints',
    'arguments' => { 'source' => { 'path' => '/tmp/foo.rb' }, 'breakpoints' => [{ 'line' => 10 }] },
  }
  round_tripped = MRDebug::CLI::Json.parse(MRDebug::CLI::Json.generate(request))
  assert_equal request, round_tripped
end
