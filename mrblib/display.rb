class Display
  attr_reader :expr

  def initialize(expr)
    @expr = expr
    @active = true
  end

  def active?
    @active
  end

  def deactivate!
    @active = false
  end

  def print_line(bnd, index)
    if bnd.nil?
      puts "#{index}: #{expr} (no binding available for this breakpoint)"
      return
    end
    begin
      value = bnd.eval(expr)
      puts "#{index}: #{expr} = #{value.inspect}"
    rescue Exception => e
      # Exception, not StandardError: see Debugger#print_expr for why.
      puts "#{index}: #{expr} raised #{e.class}: #{e.message}"
    end
  end
end
