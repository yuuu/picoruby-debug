module MRDebug
  class LineBreakpoint
    attr_reader :file, :line

    def initialize(file, line)
      @file = file
      @line = line
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
      "#{file}:#{line}"
    end

    def numbered_line(index)
      "  ##{index} #{self}"
    end
  end
end
