module MRDebug
  class LineBreakpoint
    attr_reader :file, :line, :condition

    def initialize(file, line, condition = nil)
      @file = file
      @line = line
      @condition = condition
      @active = true
    end

    def active?
      @active
    end

    def deactivate!
      @active = false
    end

    def match?(file, line)
      active? && @line == line && file[-@file.size, @file.size] == @file
    end

    def to_s
      condition ? "#{file}:#{line} if #{condition}" : "#{file}:#{line}"
    end

    def numbered_line(index)
      "  ##{index} #{self}"
    end
  end
end
