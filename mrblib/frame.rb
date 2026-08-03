# Selected stack frame (frame/up/down) for one on_break stop; Debugger#on_break builds a fresh instance every time execution pauses.
class Frame
  def initialize(debugger, file, line, bnd, offset)
    @debugger = debugger
    @break_file = file
    @break_line = line
    @break_binding = bnd
    @offset = offset # 1 if depth 0 has no Ruby-level position of its own (binding.debugger), else 0
    @depth = 0
  end

  def count
    @debugger.frame_count - @offset
  end

  def position_at(depth)
    return [@break_file, @break_line] if depth == 0
    @debugger.frame_position(depth + @offset)
  end

  def binding_at(depth)
    return @break_binding if depth == 0
    @debugger.frame_binding(depth + @offset)
  end

  def position
    position_at(@depth)
  end

  def binding
    binding_at(@depth)
  end

  def print_backtrace
    n = count
    if n == 0
      puts "No frame information available"
      return
    end
    n.times do |depth|
      pos = position_at(depth)
      next unless pos # e.g. a C frame deeper in the stack
      marker = depth == @depth ? "=>" : "  "
      puts "#{marker}##{depth} #{pos[0]}:#{pos[1]}"
    end
  end

  def show(depth = @depth)
    pos = position_at(depth)
    if pos
      puts "##{depth} #{pos[0]}:#{pos[1]}"
    else
      puts "##{depth} (no source)"
    end
  end

  def select(arg)
    n = count
    if n == 0
      puts "No frame information available"
      return
    end
    depth = arg.to_i
    if depth < 0 || depth >= n
      puts "No frame ##{arg}"
      return
    end
    @depth = depth
    show
  end

  def move(delta) # delta > 0 moves up (toward the caller), delta < 0 moves down (toward the callee)
    n = count
    if n == 0
      puts "No frame information available"
      return
    end
    target = @depth + delta
    if target >= n
      puts "Already at the outermost frame in the stack"
      return
    end
    if target < 0
      puts "Already at the innermost frame in the stack"
      return
    end
    @depth = target
    show
  end
end
