module MRDebug
  class Session
    attr_reader :file, :line, :binding

    def initialize
      @breakpoints = []
      @mode = :run
      @next_depth = nil
      MRDebug::Hook.install(self)
    end

    def breakpoints
      @breakpoints
    end

    def add_breakpoint(file, line)
      @breakpoints << LineBreakpoint.new(file, line)
      update_armed
      @breakpoints.size
    end

    def remove_breakpoint(n)
      bp = @breakpoints[n - 1]
      return false unless bp && bp.active?
      bp.deactivate!
      update_armed
      true
    end

    def clear_breakpoints
      @breakpoints.each(&:deactivate!)
      update_armed
    end

    def run_mode!
      @mode = :run
      update_armed
    end

    def step_mode!
      @mode = :step
      update_armed
    end

    def next_mode!
      # A direct Binding#debugger stop's Hook.frame_count includes
      # MRDebug.break's own wrapper frames on top of the debuggee's, which
      # doesn't shrink back to the debuggee-only count a later hook-
      # triggered comparison would see -- not a small, fixed offset, just
      # not comparable. Fall back to stepping through every line instead of
      # a depth check that would rarely fire at all.
      return step_mode! if @direct_stop

      @mode = :next
      @next_depth = MRDebug::Hook.frame_count
      update_armed
    end

    # Called with 2 args from the VM hook (src/hook.c), or with 3 from
    # MRDebug.break -- an explicit, unconditional stop that already has its
    # own Binding in hand. Returns true if execution should stop here.
    def on_line(file, line, bnd = nil)
      return false unless bnd || should_break?(file, line)
      @file = file
      @line = line
      @binding = bnd || MRDebug::Hook.frame_binding(0)
      @direct_stop = !bnd.nil?
      true
    end

    private

    def should_break?(file, line)
      case @mode
      when :step then true
      when :next then MRDebug::Hook.frame_count <= @next_depth
      else @breakpoints.any? { |bp| bp.match?(file, line) }
      end
    end

    def update_armed
      MRDebug::Hook.armed = @mode != :run || @breakpoints.any?(&:active?)
    end
  end
end
