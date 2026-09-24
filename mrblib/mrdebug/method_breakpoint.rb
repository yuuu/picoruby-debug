module MRDebug
  # A breakpoint on a method by name, matched at the call site by the VM
  # hook (src/hook.c decodes OP_SEND). No resolution to file/line: the class
  # need not exist yet. Lives in Session's @breakpoints next to LineBreakpoint.
  class MethodBreakpoint
    attr_reader :class_name, :method_name, :condition

    # class_name: "Foo" / "Foo::Bar" / nil (any class). singleton: true for
    # `Foo.bar`, false for `Foo#bar`.
    def initialize(class_name, method_name, singleton = false, condition = nil)
      @class_name = class_name
      @method_name = method_name
      @singleton = singleton
      @condition = condition
      @active = true
      @cfunc = false
    end

    def active?
      @active
    end

    def deactivate!
      @active = false
    end

    def method_sym
      @method_name.to_sym
    end

    # Method breakpoints are matched at the call site by the VM hook, never
    # by (file, line); this keeps Session's line-match loop uniform.
    def match?(_file, _line)
      false
    end

    # recv is the actual receiver of the call. Policy: `Foo#bar` matches when
    # bar runs on any Foo (subclasses and module includers included);
    # `Foo.bar` matches when bar runs on Foo itself.
    def matches_call?(recv)
      return false unless @active
      return true if @class_name.nil?
      klass = MethodBreakpoint.resolve(@class_name)
      return false unless klass
      @singleton ? recv.equal?(klass) : recv.is_a?(klass)
    end

    def cfunc!
      @cfunc = true
    end

    def stop_banner(siblings, location)
      line = "Breakpoint #{siblings.index(self) + 1}: #{self}"
      @cfunc ? "#{line} (about to call a C method)" : line
    end

    def to_s
      s = @class_name ? "#{@class_name}#{@singleton ? '.' : '#'}#{@method_name}" : @method_name
      @condition ? "#{s} if #{@condition}" : s
    end

    def numbered_line(index)
      "  ##{index} #{self}"
    end

    # "Foo::Bar" -> the constant, or nil if it isn't defined yet.
    def self.resolve(name)
      name.split('::').reduce(Object) { |mod, part| mod.const_get(part) }
    rescue NameError
      nil
    end
  end
end
