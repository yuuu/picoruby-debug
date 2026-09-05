module MRDebug
  module CLI
    # A DAP request handler on top of a RemoteSession (route (b): this
    # class never touches a device directly). #handle takes a parsed
    # request Hash and returns response/event Hashes, so it's testable
    # without a socket; #handle_message wraps that with Json for raw text.
    # stepOut/stackTrace/scopes/variables/evaluate aren't handled yet --
    # RemoteSession has no frame API to forward them to
    # (docs/phase4-to-phase3-requests.md). continue/next/stepIn report
    # `terminated` right after resuming, since nothing keeps running behind
    # RemoteSession's in-process delegate yet.
    class DapBridge
      def initialize(remote)
        @remote = remote
        @seq = 0
        @handshake_done = false
      end

      def handshake_done?
        @handshake_done
      end

      # request_json -> Array of response/event JSON strings.
      def handle_message(request_json)
        request = Json.parse(request_json)
        handle(request).map { |msg| Json.generate(msg) }
      end

      # request Hash -> Array of response/event Hashes, in the order they
      # should be sent.
      def handle(request)
        @handshake_done ? handle_stop_request(request) : handle_handshake_request(request)
      rescue => e
        [error_response(request, e)]
      end

      private

      def next_seq
        @seq += 1
        @seq
      end

      def response(request, body = {}, success: true, message: nil)
        msg = {
          'seq' => next_seq,
          'type' => 'response',
          'request_seq' => request['seq'],
          'success' => success,
          'command' => request['command'],
          'body' => body,
        }
        msg['message'] = message if message
        msg
      end

      def error_response(request, err)
        response(request, {}, success: false, message: "#{err.class}: #{err.message}")
      end

      def event(name, body = {})
        { 'seq' => next_seq, 'type' => 'event', 'event' => name, 'body' => body }
      end

      def not_supported(request)
        response(request, {}, success: false,
                 message: "#{request['command']}: not supported yet -- needs Phase3's frame API " \
                          'over the wire (see docs/phase4-to-phase3-requests.md)')
      end

      def handle_handshake_request(request)
        case request['command']
        when 'initialize'
          [response(request, { 'supportsConfigurationDoneRequest' => true }), event('initialized')]
        when 'attach', 'launch'
          [response(request)]
        when 'setBreakpoints'
          [response(request, set_breakpoints_body(request))]
        when 'configurationDone'
          @handshake_done = true
          [response(request), stopped_event('entry')]
        else
          [response(request, {}, success: false,
                     message: "unexpected before configurationDone: #{request['command']}")]
        end
      end

      def handle_stop_request(request)
        case request['command']
        when 'continue'
          @remote.run_mode!
          [response(request, { 'allThreadsContinued' => true }), terminated_event]
        when 'next'
          @remote.next_mode!
          [response(request), terminated_event]
        when 'stepIn'
          @remote.step_mode!
          [response(request), terminated_event]
        when 'stepOut', 'stackTrace', 'scopes', 'variables', 'evaluate'
          [not_supported(request)]
        when 'setBreakpoints'
          [response(request, set_breakpoints_body(request))]
        when 'threads'
          [response(request, { 'threads' => [{ 'id' => 1, 'name' => 'main' }] })]
        when 'disconnect'
          [response(request), terminated_event]
        else
          [response(request, {}, success: false, message: "unsupported command: #{request['command']}")]
        end
      end

      def stopped_event(reason)
        event('stopped', 'reason' => reason, 'threadId' => 1, 'allThreadsStopped' => true)
      end

      def terminated_event
        event('terminated')
      end

      # Replaces the full breakpoint set for one file: deactivate its
      # existing breakpoints, then re-add the requested lines. Normalizes
      # to a basename first -- VS Code's absolute path won't suffix-match
      # the device's short running path otherwise (dap/06's lesson).
      def set_breakpoints_body(request)
        args = request['arguments'] || {}
        file = basename(((args['source'] || {})['path']).to_s)
        lines = (args['breakpoints'] || []).map { |bp| bp['line'] }

        @remote.breakpoints.each_with_index do |bp, i|
          @remote.remove_breakpoint(i + 1) if bp.active? && bp.file == file
        end
        lines.each { |line| @remote.add_breakpoint(file, line) }

        { 'breakpoints' => lines.map { |line| { 'verified' => true, 'line' => line } } }
      end

      def basename(path)
        slash = path.rindex('/')
        slash ? path[(slash + 1), path.size - slash - 1] : path
      end
    end
  end
end
