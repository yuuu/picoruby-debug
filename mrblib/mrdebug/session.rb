module MRDebug
  class Session
    # Binding#debugger -> MRDebug.break -> MRDebug::Hook.enter is a fixed
    # 3-frame call chain captured before the debugger context swap, so a
    # direct stop's Hook.frame_count always includes these 3 extra frames.
    DIRECT_STOP_FRAME_OFFSET = 3

    attr_reader :file, :line, :binding, :stopped_by
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
      @watches << WatchVarBreakpoint.new(expr)
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

    def add_method_breakpoint(class_name, method_name, singleton = false, condition = nil)
      @breakpoints << MethodBreakpoint.new(class_name, method_name, singleton, condition)
      sync_method_names
      update_armed
      @breakpoints.size
    end

    def remove_breakpoint(n)
      bp = @breakpoints[n - 1]
      return false unless bp && bp.active?
      bp.deactivate!
      sync_method_names
      update_armed
      true
    end

    def clear_breakpoints
      @breakpoints.each(&:deactivate!)
      sync_method_names
      update_armed
    end

    # Called from the VM hook (src/hook.c) at a call to a watched method
    # name: returns the MethodBreakpoint that matches this receiver, or nil.
    # Like line breakpoints, only active in run mode (not mid step/next).
    def method_bp_for(recv, method_sym, is_cfunc)
      return nil unless @mode == :run
      name = method_sym.to_s
      bp = nil
      @breakpoints.each do |b|
        next unless b.is_a?(MethodBreakpoint) && b.method_name == name
        if b.matches_call?(recv)
          bp = b
          break
        end
      end
      return nil unless bp
      bp.cfunc! if is_cfunc
      bp
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

    # Headline for the current stop, delegated to whatever @stopped_by is.
    def stop_banner
      loc = "#{@file}:#{@line}"
      siblings = [@breakpoints, @watches].find { |list| list.include?(@stopped_by) }
      siblings ? @stopped_by.stop_banner(siblings, loc) : "Stop: #{loc}"
    end

    # bnd is set only for a direct MRDebug.break stop, which always stops.
    # forced is a MethodBreakpoint the VM hook already matched at a call site.
    def on_line(file, line, bnd = nil, forced = nil)
      reason = forced || (bnd ? :debugger : stop_reason_for(file, line))
      return false unless reason
      return false if forced.is_a?(MethodBreakpoint) && !condition_met?(forced)
      if bnd.nil? && forced.nil? && (@mode == :step || @mode == :next) && @remaining > 1
        @remaining -= 1
        return false
      end
      @file = file
      @line = line
      @binding = bnd || MRDebug::Hook.frame_binding(0)
      @direct_stop = !bnd.nil?
      @stopped_by = reason
      ui.on_stop(self) if ui
      true
    end

    private

    def sync_method_names
      names = []
      @breakpoints.each { |b| names << b.method_sym if b.is_a?(MethodBreakpoint) && b.active? }
      MRDebug::Hook.watch_method_names(names)
    end

    # nil, or why we stop: a LineBreakpoint/WatchVarBreakpoint object, :step, or :next.
    def stop_reason_for(file, line)
      return nil if OwnSource.file?(file)
      wp = triggered_watch
      return wp if wp
      case @mode
      when :step then :step
      when :next then MRDebug::Hook.frame_count <= @next_depth ? :next : nil
      else
        bp = @breakpoints.find { |b| b.match?(file, line) }
        bp && condition_met?(bp) ? bp : nil
      end
    end

    # #select, not #find: every watch must re-check (and cache) its value each line.
    def triggered_watch
      return nil if @watches.empty?
      bnd = MRDebug::Hook.frame_binding(0)
      @watches.select { |w| w.changed?(bnd) }.first
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
