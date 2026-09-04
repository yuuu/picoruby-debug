module MRDebug
  module Command
    VERBS = {
      '' => :continue, 'c' => :continue, 'continue' => :continue,
      's' => :step, 'step' => :step,
      'n' => :next, 'next' => :next,
      'b' => :break, 'break' => :break,
      'd' => :delete, 'delete' => :delete,
      'p' => :print, 'print' => :print,
    }

    # Parses one command line and dispatches it against `session`.
    # Returns [output_lines, :stay | :resume]; never prints (the UI does).
    def self.dispatch(session, line)
      verb, arg = split(line)
      case VERBS[verb]
      when :continue
        session.run_mode!
        [[], :resume]
      when :step
        session.step_mode!
        [[], :resume]
      when :next
        session.next_mode!
        [[], :resume]
      when :break
        [break_cmd(session, arg), :stay]
      when :delete
        [delete_cmd(session, arg), :stay]
      when :print
        [print_cmd(session, arg), :stay]
      else
        [["unknown command: #{line}"], :stay]
      end
    end

    # Manual trim, not String#strip -- mruby-string-ext methods misbehave
    # under mrbtest (see docs/plan-phase1.md); core String methods are fine.
    def self.space?(c)
      c == ' ' || c == "\t" || c == "\n" || c == "\r"
    end

    def self.trim(str)
      i = 0
      i += 1 while i < str.size && space?(str[i])
      j = str.size - 1
      j -= 1 while j >= i && space?(str[j])
      str[i, j - i + 1]
    end

    def self.blank?(str)
      str.nil? || trim(str).size == 0
    end

    def self.split(line)
      verb, arg = trim(line).split(' ', 2)
      [verb || '', arg]
    end

    def self.break_cmd(session, arg)
      return list_breakpoints(session) if blank?(arg)

      file, ln = parse_location(session.file, arg)
      return ['Invalid line number'] unless ln && ln > 0

      n = session.add_breakpoint(file, ln)
      ["Breakpoint #{n} added at #{file}:#{ln}"]
    end

    # `[<file>:]<line>`: split at the last ':', else current_file is used.
    def self.parse_location(current_file, arg)
      colon = last_colon_index(arg)
      if colon
        file = arg[0, colon]
        file = current_file if file.empty?
        [file, arg[(colon + 1)..-1].to_i]
      else
        [current_file, arg.to_i]
      end
    end

    def self.last_colon_index(str)
      i = str.size - 1
      while i >= 0
        return i if str[i] == ':'
        i -= 1
      end
      nil
    end

    def self.list_breakpoints(session)
      lines = []
      session.breakpoints.each_with_index do |bp, i|
        lines << bp.numbered_line(i + 1) if bp.active?
      end
      lines.empty? ? ['No breakpoints set'] : lines
    end

    def self.delete_cmd(session, arg)
      if blank?(arg)
        session.clear_breakpoints
        return ['Deleted all breakpoints']
      end
      n = arg.to_i
      if n > 0 && session.remove_breakpoint(n)
        ["Deleted breakpoint ##{n}"]
      else
        ["No breakpoint ##{arg}"]
      end
    end

    def self.print_cmd(session, arg)
      return ['Usage: p <expression>'] if blank?(arg)
      bnd = session.binding
      return ['No binding available for this breakpoint'] if bnd.nil?
      begin
        [bnd.eval(arg).inspect]
      rescue Exception => e
        # Exception, not StandardError: a bad expression can raise SyntaxError.
        ["#{e.class}: #{e.message}"]
      end
    end
  end
end
