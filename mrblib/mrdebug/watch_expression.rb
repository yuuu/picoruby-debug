module MRDebug
  class WatchExpression
    UNSET = Object.new

    attr_reader :expr

    def initialize(expr)
      @expr = expr
      @last_value = UNSET
    end

    # True the first time it's checked, and again whenever the evaluated
    # value differs from the previous check.
    def changed?(bnd)
      current = safe_eval(bnd)
      changed = @last_value == UNSET || current != @last_value
      @last_value = current
      changed
    end

    def to_s
      "watch: #{expr}"
    end

    def numbered_line(index)
      "  ##{index} #{self}"
    end

    private

    def safe_eval(bnd)
      bnd.eval(expr)
    rescue Exception => e
      "#{e.class}: #{e.message}"
    end
  end
end
