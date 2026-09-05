module MRDebug
  # Interim shape only (docs/plan-phase4.md step 3): forwards straight
  # through to a same-process Session until Phase3 has a real wire protocol
  # to forward over instead (docs/phase4-to-phase3-requests.md). `binding`
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

    def breakpoints
      @session.breakpoints
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
