# Suffix matching (plain end_with?, matching the old C implementation's
# debug_file_match -- no path-separator boundary check) and stable
# numbering: delete deactivates in place rather than compacting the array,
# so surviving breakpoints keep their numbers.
bp = MRDebug::LineBreakpoint.new('foo.rb', 10)
raise 'suffix match failed' unless bp.match?('/path/to/foo.rb', 10)
raise 'wrong file matched' if bp.match?('/path/to/other.rb', 10)
raise 'wrong line matched' if bp.match?('/path/to/foo.rb', 11)

session = MRDebug::Session.new

n1 = session.add_breakpoint(__FILE__, 100)
n2 = session.add_breakpoint(__FILE__, 200)
n3 = session.add_breakpoint(__FILE__, 300)
raise "expected 1,2,3 got #{[n1, n2, n3].inspect}" unless [n1, n2, n3] == [1, 2, 3]

raise 'remove #2 failed' unless session.remove_breakpoint(2)
raise 'removing #2 again should fail' if session.remove_breakpoint(2)

n4 = session.add_breakpoint(__FILE__, 400)
raise "expected #4 to be a fresh number, got #{n4}" unless n4 == 4

active = session.breakpoints.each_with_index.select { |bp, _| bp.active? }.map { |_, i| i + 1 }
raise "expected [1, 3, 4] active, got #{active.inspect}" unless active == [1, 3, 4]

puts 'ok'
