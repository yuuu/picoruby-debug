class LineBreakpoint < Breakpoint
  def to_s
    "#{file}:#{line}"
  end
end
