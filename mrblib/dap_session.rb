# Minimal DAP (Debug Adapter Protocol) request handling on top of
# DapTransport's framing/IO. This is a second front end for the same core
# Debugger operations mrblib/debugger.rb's CLI dispatch_command already
# uses (add_breakpoint, set_run_mode, frame_count/frame_position/
# frame_binding, ...) -- mirroring ruby/debug's "REPL and DAP are separate
# front ends over one internal session API" design. No CLI behavior is
# touched: a Debugger with no DAP session configured never loads/calls
# this class.
#
# Only the minimal request set needed for a first working session is
# handled: initialize, attach (launch is treated as an alias -- this
# debugger has no separate "launch a process" step), setBreakpoints,
# configurationDone, continue/next/stepIn/stepOut, stackTrace, scopes,
# variables, evaluate, threads, and disconnect. Unhandled commands get a
# success:false response rather than being silently dropped.
class DapSession
  def initialize(transport)
    @transport = transport
    @seq = 0
    @handshake_done = false
    @pending_reason = "entry"
  end

  def handshake_done?
    @handshake_done
  end

  def pending_reason
    @pending_reason
  end

  def send_event(event, body = {})
    @seq += 1
    @transport.send_message(seq: @seq, type: "event", event: event, body: body)
  end

  def send_response(request, body = {}, success: true, message: nil)
    @seq += 1
    msg = {
      seq: @seq,
      type: "response",
      request_seq: request["seq"],
      success: success,
      command: request["command"],
      body: body,
    }
    msg[:message] = message if message
    @transport.send_message(msg)
  end

  # Blocks until a client connects and walks it through
  # initialize -> attach/launch -> setBreakpoints (0 or more) ->
  # configurationDone, exactly once. Called from Debugger#on_break at the
  # very first stop, before that stop is reported -- this is the only
  # place in this debugger's design where "the script hasn't started
  # running yet" and "we can talk to a client" overlap.
  def perform_handshake(debugger)
    return true if @handshake_done
    return false unless @transport.listen
    loop do
      req = @transport.receive_message
      return false unless req
      begin
        case req["command"]
        when "initialize"
          send_response(req, { supportsConfigurationDoneRequest: true })
          send_event("initialized")
        when "attach", "launch"
          send_response(req)
        when "setBreakpoints"
          send_response(req, set_breakpoints_body(req, debugger))
        when "configurationDone"
          send_response(req)
          @handshake_done = true
          @pending_reason = "entry"
          return true
        else
          send_response(req, {}, success: false, message: "unexpected before configurationDone: #{req['command']}")
        end
      rescue => e
        # A bug in one handler shouldn't take down the whole session (or,
        # worse, get silently swallowed by debug_invoke_on_break's
        # mrb_protect_error and leave the client hanging) -- report it as a
        # failed request instead.
        send_response(req, {}, success: false, message: "#{e.class}: #{e.message}")
      end
    end
  end

  # Reports the current stop, then processes requests until one of them
  # resumes execution (continue/next/stepIn/stepOut) or the client
  # disconnects. Returns after setting whatever mode the debugged task
  # should resume in.
  def run_request_loop(debugger)
    send_event("stopped", { reason: @pending_reason, threadId: 1, allThreadsStopped: true })
    loop do
      req = @transport.receive_message
      unless req
        debugger.set_run_mode # client vanished; let the script finish on its own
        return
      end
      return if dispatch_stop_request(req, debugger)
    end
  end

  private

  # Returns true if this request resumes execution (the caller should stop
  # looping and let on_break return), false to keep processing requests.
  # A bug in one handler is reported as a failed response rather than
  # aborting the whole loop (or, worse, escaping to debug_invoke_on_break's
  # mrb_protect_error and leaving the client hanging with no response at
  # all).
  def dispatch_stop_request(req, debugger)
    case req["command"]
    when "continue"
      debugger.set_run_mode
      @pending_reason = "breakpoint"
      send_response(req, { allThreadsContinued: true })
      return true
    when "next"
      debugger.set_next_mode
      @pending_reason = "step"
      send_response(req)
      return true
    when "stepIn"
      debugger.set_step_mode
      @pending_reason = "step"
      send_response(req)
      return true
    when "stepOut"
      debugger.set_step_out_mode
      @pending_reason = "step"
      send_response(req)
      return true
    when "stackTrace"
      send_response(req, stack_trace_body(debugger))
    when "scopes"
      send_response(req, scopes_body(req))
    when "variables"
      send_response(req, variables_body(req, debugger))
    when "evaluate"
      send_response(req, evaluate_body(req, debugger))
    when "setBreakpoints"
      send_response(req, set_breakpoints_body(req, debugger))
    when "threads"
      send_response(req, { threads: [{ id: 1, name: "main" }] })
    when "disconnect"
      debugger.request_quit
      send_response(req)
      send_event("terminated")
      @transport.close
      return true
    else
      send_response(req, {}, success: false, message: "unsupported command: #{req['command']}")
    end
    false
  rescue => e
    send_response(req, {}, success: false, message: "#{e.class}: #{e.message}")
    false
  end

  def stack_trace_body(debugger)
    frames = []
    debugger.frame_count.times do |depth|
      pos = debugger.frame_position(depth)
      next unless pos # e.g. the C frame a binding.debugger call itself runs in
      frames << {
        id: depth,
        name: "frame ##{depth}",
        source: { path: pos[0] },
        line: pos[1],
        column: 1,
      }
    end
    { stackFrames: frames, totalFrames: frames.size }
  end

  def scopes_body(req)
    frame_id = (req["arguments"] || {})["frameId"].to_i
    # variablesReference is a single Locals scope per frame; offset by 1
    # since DAP reserves 0 to mean "no children".
    { scopes: [{ name: "Locals", variablesReference: frame_id + 1, expensive: false }] }
  end

  def variables_body(req, debugger)
    var_ref = (req["arguments"] || {})["variablesReference"].to_i
    bnd = debugger.frame_binding(var_ref - 1)
    return { variables: [] } if bnd.nil?
    vars = []
    bnd.local_variables.each do |sym|
      # Some internal/compiler-generated local slots surface here with an
      # empty name (not filtered out by mrb_proc_local_variables, which
      # only drops '*'/'&'-prefixed and unset slots); local_variable_get
      # raises NameError for those, so skip rather than fail the request.
      next if sym.to_s.empty?
      vars << { name: sym.to_s, value: bnd.local_variable_get(sym).inspect, variablesReference: 0 }
    end
    { variables: vars }
  end

  def evaluate_body(req, debugger)
    args = req["arguments"] || {}
    depth = args["frameId"] ? args["frameId"].to_i : 0
    bnd = debugger.frame_binding(depth)
    _ok, result = debugger.evaluate_expression(bnd, args["expression"].to_s)
    { result: result, variablesReference: 0 }
  end

  def set_breakpoints_body(req, debugger)
    args = req["arguments"] || {}
    file = (args["source"] || {})["path"].to_s
    lines = (args["breakpoints"] || []).map { |b| b["line"] }
    debugger.reconcile_breakpoints(file, lines)
    { breakpoints: lines.map { |l| { verified: true, line: l } } }
  end
end
