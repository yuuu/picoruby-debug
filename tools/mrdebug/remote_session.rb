module MRDebug
  # Interim shape only: forwards straight through to a same-process Session
  # until a real wire protocol exists to forward over instead. `binding`
  # will need to become a `.eval(expr)`-only proxy once @session is no
  # longer in this process -- a live Binding can't cross that boundary.
  class RemoteSession
    def initialize(session)
      @session = session
    end

    def file
      @session.file
    end

    def line
      @session.line
    end

    def binding
      @session.binding
    end

    def location
      @session.location
    end

    def frame_index
      @session.frame_index
    end

    def select_frame(n)
      @session.select_frame(n)
    end

    def stopped_by
      @session.stopped_by
    end

    def stop_banner
      @session.stop_banner
    end

    def breakpoints
      @session.breakpoints
    end

    def backtrace
      @session.backtrace
    end

    # Raw file content, via the same `cat` Command a real DeviceLink would
    # send over the wire (not a direct File read -- @session is I/O-free).
    def source(path)
      out, = MRDebug::Command.dispatch(@session, "cat #{path}")
      out.join("\n")
    end

    def add_display(expr)
      @session.add_display(expr)
    end

    def display_lines
      @session.display_lines
    end

    def add_breakpoint(file, line, condition = nil)
      @session.add_breakpoint(file, line, condition)
    end

    def remove_breakpoint(n)
      @session.remove_breakpoint(n)
    end

    def clear_breakpoints
      @session.clear_breakpoints
    end

    def run_mode!
      @session.run_mode!
    end

    def step_mode!(count = 1)
      @session.step_mode!(count)
    end

    def next_mode!(count = 1)
      @session.next_mode!(count)
    end
  end
end
