class WatchBreakpoint < Breakpoint
  def to_s
    expr
  end

  def break?(index, bnd)
    return nil if bnd.nil? || !active?
    begin
      value = bnd.eval(expr)
    rescue Exception
      return nil
    end
    if @has_cached_value
      prev = @cached_value
      @cached_value = value
      return nil if prev == value
      "Watchpoint #{index}: #{expr}\n  old: #{prev.inspect}\n  new: #{value.inspect}"
    else
      @has_cached_value = true
      @cached_value = value
      nil
    end
  end

  def add_initial_value(bnd)
    return "  no binding available; cannot evaluate initial value" if bnd.nil?
    begin
      value = bnd.eval(expr)
      @has_cached_value = true
      @cached_value = value
      "  initial value: #{value.inspect}"
    rescue Exception => e
      "  #{e.class}: #{e.message}"
    end
  end
end
