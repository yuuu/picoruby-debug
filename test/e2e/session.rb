# Consolidates session_breakpoint.rb, session_step.rb, session_next.rb and
# session_next_recovery.rb: MRDebug::Session's run/step/next behavior
# backed by the real VM hook (a breakpoint or step/next actually fires from
# executed code, not a hand-called #on_line). Session stops reached via a
# direct binding.debugger/#b/#break call have their own file,
# binding_debugger.rb.

# Every scenario below assigns MRDebug.session=, which arms Hook.install
# under the hood (Session#initialize already does too); every one of them
# owes Hook.uninstall on the way out, per CLAUDE.md's "every test that
# creates a Session must clean up the VM hook".
def with_session(session)
  MRDebug.session = session
  yield
ensure
  MRDebug::Hook.uninstall
end

# --- Ported from e2e/scenarios/session_breakpoint.rb ---
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

# --- Conditional breakpoints: the condition is evaluated against the
# stopped frame's binding, backed by the real VM hook. ---
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

# --- Ported from e2e/scenarios/session_step.rb: `step` must stop at every
# subsequent line, including inside a call, via the real VM hook. ---
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
  # step mode has no fast path, so it's still armed right up to with_session's
  # own Hook.uninstall -- which is exactly where the original scenario also
  # stopped tracing, immediately after the call and before these assertions.
  assert_true recorder.stops.include?(session_step_outer_call_line)
  assert_true recorder.stops.include?(session_step_inner_line)
ensure
  MRDebug::Hook.uninstall
end

# --- Ported from e2e/scenarios/session_next.rb ---
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
  # :next stays armed past with_session's own Hook.uninstall, so that line
  # itself gets traced too and lands as a 3rd stop -- hence checking only
  # first(2), same as session_next_from_binding_debugger's direct-stop case.
  assert_equal [session_next_bp_line, session_next_bp_line + 1], recorder.stops.first(2)
  assert_false recorder.stops.include?(session_next_inner_line) # next must not stop inside the call
ensure
  MRDebug::Hook.uninstall
end

# --- Ported from e2e/scenarios/session_next_recovery.rb: @direct_stop's
# offset compensation (see binding_debugger.rb) must not leak into a later,
# hook-triggered next on the same session. ---
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
    # Run 1: direct stop -> next must not descend into the call.
    session_next_recovery_via_binding_debugger(1)
    recorder.run_mode! # not Hook.uninstall: that would also clear hook.session, needed for run 2
    assert_equal [session_next_recovery_debugger_line, session_next_recovery_call_line1, session_next_recovery_final_line1],
                 recorder.stops.first(3)
    assert_false recorder.stops.include?(session_next_recovery_inner_line)

    # Run 2: hook-triggered stop -> next must still track depth precisely,
    # proving run 1's @direct_stop offset didn't leak into this session.
    recorder.reset_for_next_run
    recorder.add_breakpoint(__FILE__, session_next_recovery_bp_line)
    session_next_recovery_via_breakpoint(2)

    assert_equal [session_next_recovery_bp_line, session_next_recovery_bp_line + 1], recorder.stops.first(2)
    assert_false recorder.stops.include?(session_next_recovery_inner_line)
  end
ensure
  MRDebug::Hook.uninstall
end
