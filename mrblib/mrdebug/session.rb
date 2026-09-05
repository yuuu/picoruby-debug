module MRDebug
  class Session
    # Binding#debugger -> MRDebug.break -> MRDebug::Hook.enter is a fixed
    # 3-frame call chain captured before the debugger context swap, so a
    # direct stop's Hook.frame_count always includes these 3 extra frames.
    DIRECT_STOP_FRAME_OFFSET = 3

    attr_reader :file, :line, :binding
    attr_accessor :ui

    def initialize
      @breakpoints = []
      @mode = :run
      @next_depth = nil
      @remaining = 1
      @displays = []
      @watches = []
      MRDebug::Hook.install(self)
    end

    def breakpoints
      @breakpoints
    end

    def watches
      @watches
    end

    # Doesn't touch armed state -- see docs/known-bugs.md.
    def add_display(expr)
      @displays << DisplayExpression.new(expr)
      @displays.size
    end

    # Doesn't touch armed state -- see docs/known-bugs.md.
    def add_watch(expr)
      @watches << WatchExpression.new(expr)
      @watches.size
    end

    def display_lines
      return [] if @displays.empty? || @binding.nil?
      @displays.map { |d| [d.expr, d.result(@binding)] }
    end

    def add_breakpoint(file, line, condition = nil)
      @breakpoints << LineBreakpoint.new(file, line, condition)
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

    def step_mode!(count = 1)
      @mode = :step
      @remaining = count
      update_armed
    end

    def next_mode!(count = 1)
      @mode = :next
      @next_depth = MRDebug::Hook.frame_count
      @next_depth -= DIRECT_STOP_FRAME_OFFSET if @direct_stop
      @remaining = count
      update_armed
    end

    # bnd is set only for a direct MRDebug.break stop, which always stops.
    def on_line(file, line, bnd = nil)
      return false unless bnd || should_break?(file, line)
      if bnd.nil? && (@mode == :step || @mode == :next) && @remaining > 1
        @remaining -= 1
        return false
      end
      @file = file
      @line = line
      @binding = bnd || MRDebug::Hook.frame_binding(0)
      @direct_stop = !bnd.nil?
      ui.on_stop(self) if ui
      true
    end

    private

    def should_break?(file, line)
      return false if OwnSource.file?(file)
      return true if watch_triggered?
      case @mode
      when :step then true
      when :next then MRDebug::Hook.frame_count <= @next_depth
      else
        bp = @breakpoints.find { |b| b.match?(file, line) }
        bp ? condition_met?(bp) : false
      end
    end

    # Skips the frame_binding fetch entirely when there's nothing to check.
    def watch_triggered?
      return false if @watches.empty?
      bnd = MRDebug::Hook.frame_binding(0)
      @watches.map { |w| w.changed?(bnd) }.any?
    end

    # A raise during evaluation fails open (stops) rather than silently
    # never stopping.
    def condition_met?(bp)
      return true unless bp.condition
      begin
        MRDebug::Hook.frame_binding(0).eval(bp.condition) ? true : false
      rescue Exception
        true
      end
    end

    def update_armed
      MRDebug::Hook.armed = @mode != :run || @breakpoints.any?(&:active?) || @watches.any?
    end
  end
end
