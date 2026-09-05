module MRDebug
  module Command
    VERBS = {
      '' => :continue, 'c' => :continue, 'continue' => :continue,
      's' => :step, 'step' => :step,
      'n' => :next, 'next' => :next,
      'b' => :break, 'break' => :break,
      'd' => :delete, 'delete' => :delete,
      'l' => :list, 'list' => :list,
      'p' => :print, 'print' => :print,
      'display' => :display,
    }

    # Lines of context shown before/after the target line by `list`.
    LIST_CONTEXT = 5

    # Parses one command line and dispatches it against `session`.
    # Returns [output_lines, :stay | :resume]; never prints (the UI does).
    def self.dispatch(session, line)
      verb, arg = split(line)
      case VERBS[verb]
      when :continue
        session.run_mode!
        [[], :resume]
      when :step
        session.step_mode!(parse_count(arg))
        [[], :resume]
      when :next
        session.next_mode!(parse_count(arg))
        [[], :resume]
      when :break
        [break_cmd(session, arg), :stay]
      when :delete
        [delete_cmd(session, arg), :stay]
      when :list
        [list_cmd(session, arg), :stay]
      when :print
        [print_cmd(session, arg), :stay]
      when :display
        [display_cmd(session, arg), :stay]
      else
        [["unknown command: #{line}"], :stay]
      end
    end

    # Not String#strip -- mruby-string-ext methods misbehave under mrbtest.
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

    # Blank or non-positive defaults to 1.
    def self.parse_count(arg)
      return 1 if blank?(arg)
      n = trim(arg).to_i
      n > 0 ? n : 1
    end

    def self.split(line)
      verb, arg = trim(line).split(' ', 2)
      [verb || '', arg]
    end

    def self.break_cmd(session, arg)
      return list_breakpoints(session) if blank?(arg)

      location, condition = split_condition(arg)
      file, ln = parse_location(session.file, location)
      return ['Invalid line number'] unless ln && ln > 0

      n = session.add_breakpoint(file, ln, condition)
      suffix = condition ? " if #{condition}" : ''
      ["Breakpoint #{n} added at #{file}:#{ln}#{suffix}"]
    end

    # Splits "<location> if <condition>" at the first " if ". Returns
    # [location, nil] when there's no such clause.
    def self.split_condition(arg)
      idx = find_if_clause(arg)
      return [arg, nil] unless idx
      [trim(arg[0, idx]), trim(arg[(idx + 4)..-1])]
    end

    def self.find_if_clause(str)
      i = 0
      last = str.size - 4
      while i <= last
        return i if str[i, 4] == ' if '
        i += 1
      end
      nil
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

    def self.display_cmd(session, arg)
      return ['Usage: display <expression>'] if blank?(arg)
      n = session.add_display(arg)
      ["#{n}: #{arg}"]
    end

    # No argument shows the selected frame's own position (session.file/line);
    # "<line>" or "<file>:<line>" (parse_location, same as break) targets
    # somewhere else instead.
    def self.list_cmd(session, arg)
      file = session.file
      return ['No current position (not stopped anywhere yet)'] if file.nil?

      line = session.line
      unless blank?(arg)
        file, line = parse_location(file, arg)
        return ['Invalid line number'] unless line && line > 0
      end
      source_listing(file, line)
    end

    # Reads `file` off disk and formats LIST_CONTEXT lines on either side of
    # `line`. Core (mrblib/) has no I/O dependency of its own -- `File` only
    # exists here at all on a host build (mrbgem.rake adds mruby-io under
    # spec.build.host?), so `defined?(File)` is the fallback for a firmware
    # build that never linked it in.
    def self.source_listing(file, line)
      return ['Source listing is not available (no filesystem access in this build)'] unless defined?(File)

      text = begin
        File.read(file)
      rescue Exception
        nil
      end
      return ["Cannot open #{file}"] if text.nil?

      # Not String#lines/#each_line -- mruby-string-ext, misbehaves under
      # mrbtest (see CLAUDE.md). #split is a core String method.
      all_lines = text.split("\n")
      return ["Line #{line} is out of range for #{file} (#{all_lines.size} lines)"] if line > all_lines.size

      first = line - LIST_CONTEXT
      first = 1 if first < 1
      last = line + LIST_CONTEXT
      last = all_lines.size if last > all_lines.size

      out = []
      i = first
      while i <= last
        marker = i == line ? '=>' : '  '
        out << "#{marker} #{i}  #{all_lines[i - 1]}"
        i += 1
      end
      out
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
