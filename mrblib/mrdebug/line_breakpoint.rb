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

    # `file` here is the full path the VM reports; @file may be a shorter
    # suffix the user typed (e.g. `break foo.rb:8` matches `/path/to/foo.rb`).
    def match?(file, line)
      active? && @line == line && file.end_with?(@file)
    end

    def to_s
      "#{file}:#{line}"
    end

    def numbered_line(index)
      "  ##{index} #{self}"
    end
  end
end
