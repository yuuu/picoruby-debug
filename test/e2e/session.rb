# MRDebug::Session's run/step/next behavior backed by the real VM hook.
# Direct binding.debugger stops have their own file, binding_debugger.rb.

def with_session(session)
  MRDebug.session = session
  yield
ensure
  MRDebug::Hook.uninstall
end

class SessionBreakpointRecorder < MRDebug::Session
  attr_reader :stops
  def initialize
    super
    @stops = []
  end
  def on_line(file, line, bnd = nil)
    stopped = super
    @stops << line if stopped
    stopped
  end
end

session_breakpoint_target_line = __LINE__ + 2
def session_breakpoint_add(a, b)
  a + b
end

assert('Session, backed by the real VM hook, stops repeatedly at a set breakpoint') do
  recorder = SessionBreakpointRecorder.new
  with_session(recorder) do
    recorder.add_breakpoint(__FILE__, session_breakpoint_target_line)

    session_breakpoint_add(1, 2)
    session_breakpoint_add(3, 4)
    session_breakpoint_add(5, 6)
  end

  assert_equal [session_breakpoint_target_line] * 3, recorder.stops
ensure
  MRDebug::Hook.uninstall
end

class SessionConditionalRecorder < MRDebug::Session
  attr_reader :stops
  def initialize
    super
    @stops = []
  end
  def on_line(file, line, bnd = nil)
    stopped = super
    @stops << line if stopped
    stopped
  end
end

session_conditional_target_line = __LINE__ + 2
def session_conditional_add(i)
  i + 1
end

assert('a conditional breakpoint only stops when its condition evaluates true') do
  recorder = SessionConditionalRecorder.new
  with_session(recorder) do
    recorder.add_breakpoint(__FILE__, session_conditional_target_line, 'i > 1')
    session_conditional_add(1) # condition false: must not stop
    session_conditional_add(2) # condition true: must stop
    session_conditional_add(3) # condition true: must stop
  end
  assert_equal [session_conditional_target_line] * 2, recorder.stops
ensure
  MRDebug::Hook.uninstall
end

assert('a conditional breakpoint whose condition raises fails open (stops anyway)') do
  recorder = SessionConditionalRecorder.new
  with_session(recorder) do
    recorder.add_breakpoint(__FILE__, session_conditional_target_line, 'this_is_not_defined')
    session_conditional_add(1)
  end
  assert_equal [session_conditional_target_line], recorder.stops
ensure
  MRDebug::Hook.uninstall
end

class SessionStepRecorder < MRDebug::Session
  attr_reader :stops
  def initialize
    super
    @stops = []
  end
  def on_line(file, line, bnd = nil)
    stopped = super
    @stops << line if stopped
    stopped
  end
end

session_step_inner_line = __LINE__ + 2
def session_step_inner(x)
  x + 1
end

session_step_outer_call_line = __LINE__ + 2
def session_step_outer(x)
  session_step_inner(x)
end

assert('Session#step_mode! stops at every line, including inside a call') do
  recorder = SessionStepRecorder.new
  with_session(recorder) do
    recorder.step_mode!
    session_step_outer(1)
  end
  assert_true recorder.stops.include?(session_step_outer_call_line)
  assert_true recorder.stops.include?(session_step_inner_line)
ensure
  MRDebug::Hook.uninstall
end

class SessionStepNRecorder < MRDebug::Session
  attr_reader :stops
  def initialize
    super
    @stops = []
  end
  def on_line(file, line, bnd = nil)
    stopped = super
    @stops << line if stopped
    stopped
  end
end

# Computed before with_session, not inside it -- once armed, this file's
# own lines count too.
session_step_n_l1 = __LINE__ + 8
session_step_n_l2 = __LINE__ + 8
session_step_n_l3 = __LINE__ + 8

assert('Session#step_mode!(N), backed by the real VM hook, skips the first N-1 lines') do
  recorder = SessionStepNRecorder.new
  with_session(recorder) do
    recorder.step_mode!(3)
    x = 1
    y = 2
    z = 3
  end
  assert_false recorder.stops.include?(session_step_n_l1)
  assert_false recorder.stops.include?(session_step_n_l2)
  assert_true recorder.stops.include?(session_step_n_l3)
ensure
  MRDebug::Hook.uninstall
end

session_next_n_l1 = __LINE__ + 8
session_next_n_l2 = __LINE__ + 8
session_next_n_l3 = __LINE__ + 8

assert('Session#next_mode!(N), backed by the real VM hook, skips the first N-1 lines') do
  recorder = SessionStepNRecorder.new
  with_session(recorder) do
    recorder.next_mode!(3)
    x = 1
    y = 2
    z = 3
  end
  assert_false recorder.stops.include?(session_next_n_l1)
  assert_false recorder.stops.include?(session_next_n_l2)
  assert_true recorder.stops.include?(session_next_n_l3)
ensure
  MRDebug::Hook.uninstall
end

class SessionNextRecorder < MRDebug::Session
  attr_reader :stops
  def initialize
    super
    @stops = []
    @next_armed = false
  end
  def on_line(file, line, bnd = nil)
    stopped = super
    return stopped unless stopped
    @stops << line
    unless @next_armed
      @next_armed = true
      next_mode! # simulate the user typing "next" at this first stop
    end
    stopped
  end
end

session_next_inner_line = __LINE__ + 1
def session_next_inner(x)
  x + 1
end

session_next_bp_line = __LINE__ + 2
def session_next_outer(x)
  session_next_inner(x)
  x * 2
end

assert("Session#next_mode!, armed from a real breakpoint hit, does not stop inside a call") do
  recorder = SessionNextRecorder.new
  with_session(recorder) do
    recorder.add_breakpoint(__FILE__, session_next_bp_line)
    session_next_outer(1)
  end
  assert_equal [session_next_bp_line, session_next_bp_line + 1], recorder.stops.first(2)
  assert_false recorder.stops.include?(session_next_inner_line) # next must not stop inside the call
ensure
  MRDebug::Hook.uninstall
end

class SessionNextRecoveryRecorder < MRDebug::Session
  attr_reader :stops
  def initialize
    super
    @stops = []
    @next_armed = false
  end
  def reset_for_next_run
    @stops = []
    @next_armed = false
  end
  def on_line(file, line, bnd = nil)
    stopped = super
    return stopped unless stopped
    @stops << line
    unless @next_armed
      @next_armed = true
      next_mode!
    end
    stopped
  end
end

session_next_recovery_inner_line = __LINE__ + 1
def session_next_recovery_inner(x)
  x + 1
end

session_next_recovery_debugger_line = __LINE__ + 2
def session_next_recovery_via_binding_debugger(x)
  binding.debugger
  session_next_recovery_inner(x)
  x * 2
end
session_next_recovery_call_line1 = session_next_recovery_debugger_line + 1
session_next_recovery_final_line1 = session_next_recovery_debugger_line + 2

session_next_recovery_bp_line = __LINE__ + 2
def session_next_recovery_via_breakpoint(x)
  session_next_recovery_inner(x)
  x * 2
end

assert('Session#next_mode! tracks depth precisely on both a direct-stop and a later hook-triggered stop, same session') do
  recorder = SessionNextRecoveryRecorder.new
  with_session(recorder) do
    session_next_recovery_via_binding_debugger(1)
    recorder.run_mode! # not Hook.uninstall: that would also clear hook.session
    assert_equal [session_next_recovery_debugger_line, session_next_recovery_call_line1, session_next_recovery_final_line1],
                 recorder.stops.first(3)
    assert_false recorder.stops.include?(session_next_recovery_inner_line)

    recorder.reset_for_next_run
    recorder.add_breakpoint(__FILE__, session_next_recovery_bp_line)
    session_next_recovery_via_breakpoint(2)

    assert_equal [session_next_recovery_bp_line, session_next_recovery_bp_line + 1], recorder.stops.first(2)
    assert_false recorder.stops.include?(session_next_recovery_inner_line)
  end
ensure
  MRDebug::Hook.uninstall
end
