module MRDebug
  module CLI
    # A DAP request handler on top of a @remote (a RemoteSession for the
    # same-process interim demo, or a DeviceLink for a real TCP-connected
    # device -- see device_link.rb). #handle takes a parsed request Hash
    # and returns response/event Hashes, so it's testable without a
    # socket; #handle_message wraps that with Json for raw text. stepOut/
    # stackTrace/scopes/variables/evaluate aren't handled yet -- @remote
    # has no frame API to forward them to. continue/next/stepIn only ack
    # here; the *next* stop (or termination) is reported later via
    # #stopped_notification/#terminated_notification, once whoever is
    # actually watching @remote (DapServer, for a real device) observes it
    # -- @remote's own resume methods no longer block waiting for it.
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

      # An unprompted `stopped` event for the caller to send whenever it
      # observes @remote stop on its own (e.g. DapServer polling a
      # DeviceLink after a continue/next/stepIn).
      def stopped_notification(reason)
        stopped_event(reason)
      end

      # An unprompted `terminated` event, likewise.
      def terminated_notification
        terminated_event
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
                 message: "#{request['command']}: not supported yet -- needs a frame API over the wire")
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
          [response(request, { 'allThreadsContinued' => true })]
        when 'next'
          @remote.next_mode!
          [response(request)]
        when 'stepIn'
          @remote.step_mode!
          [response(request)]
        when 'stepOut', 'stackTrace', 'scopes', 'variables', 'evaluate'
          [not_supported(request)]
        when 'setBreakpoints'
          [response(request, set_breakpoints_body(request))]
        when 'threads'
          [response(request, { 'threads' => [{ 'id' => 1, 'name' => 'main' }] })]
        when 'disconnect'
          # Let the device run free rather than relying on connection-close
          # (EOF) alone to unblock its LocalConsole loop -- the same
          # already-proven run_mode! continue uses, not a new mechanism.
          @remote.run_mode!
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
