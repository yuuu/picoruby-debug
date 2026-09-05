module MRDebug
  class Session
    # Binding#debugger/#b/#break -> MRDebug.break -> MRDebug::Hook.enter is a
    # fixed 3-frame call chain that Hook.enter's invoke_on_line (src/hook.c)
    # captures mrb->c through *before* swapping into the debugger context --
    # so a direct stop's Hook.frame_count always includes exactly these 3
    # extra frames on top of the debuggee's own depth at the call site.
    # Confirmed empirically across nesting depths, all 3 Binding aliases,
    # and repeated direct stops in the same session.
    DIRECT_STOP_FRAME_OFFSET = 3

    attr_reader :file, :line, :binding
    attr_accessor :ui

    def initialize
      @breakpoints = []
      @mode = :run
      @next_depth = nil
      @remaining = 1
      @displays = []
      MRDebug::Hook.install(self)
    end

    def breakpoints
      @breakpoints
    end

    # Doesn't touch armed state -- see docs/known-bugs.md.
    def add_display(expr)
      @displays << DisplayExpression.new(expr)
      @displays.size
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

    # Called with 2 args from the VM hook (src/hook.c), or with 3 from
    # MRDebug.break -- an explicit, unconditional stop that already has its
    # own Binding in hand. Returns true if execution should stop here.
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
      case @mode
      when :step then true
      when :next then MRDebug::Hook.frame_count <= @next_depth
      else
        bp = @breakpoints.find { |b| b.match?(file, line) }
        bp ? condition_met?(bp) : false
      end
    end

    # A conditionless breakpoint always stops. A conditional one evaluates
    # against the stopped frame's binding; a raise during evaluation (a
    # typo'd expression) fails open rather than silently never stopping.
    def condition_met?(bp)
      return true unless bp.condition
      begin
        MRDebug::Hook.frame_binding(0).eval(bp.condition) ? true : false
      rescue Exception
        true
      end
    end

    def update_armed
      MRDebug::Hook.armed = @mode != :run || @breakpoints.any?(&:active?)
    end
  end
end
