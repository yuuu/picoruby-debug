require 'sandbox'

class Debugger
  LIST_RADIUS = 5

  # Enables a DAP session for the *next* Debugger instance (the one the
  # first binding.debugger call creates -- see mrb_binding_debugger in
  # src/mruby/debug.c). There's no Debugger instance to call this on
  # earlier than that, so it's a class-level switch rather than a normal
  # instance method; ENV['PRDB_DAP_PORT'] is the equivalent zero-code-change
  # knob for launchers that can't add a `Debugger.listen_dap` call.
  def self.listen_dap(port)
    @dap_port = port
  end

  def self.dap_port
    @dap_port || (ENV['PRDB_DAP_PORT'] && ENV['PRDB_DAP_PORT'].to_i)
  end

  def initialize
    @displays = []
    require 'editor' # To save memory
    @editor = Class.new(Editor::Line) do
      def initialize
        # Skip Editor::Base#initialize's terminal-size probe: on piped/
        # non-tty stdin it swallows already-buffered command bytes. prdb's
        # one-line commands never need real wrap/scroll math, so a fixed
        # size suffices.
        @height, @width = 24, 80
        @buffer = Editor::Buffer.new
        @history = [[""]]
        @history_index = 0
        @prev_cursor_y = 0
        self.prompt = "(prdb)"
      end
    end.new
    port = self.class.dap_port
    @dap_session = DapSession.new(DapTransport.new(port)) if port && DapTransport.available?
  end

  def show_source(file, current_line, center)
    begin
      f = File.open(file, "r")
    rescue => e
      puts "Cannot open #{file}: #{e.message}"
      return
    end
    lines = []
    begin
      while line = f.gets
        lines << line.chomp
      end
    ensure
      f.close
    end
    if lines.empty?
      puts "No source available for #{file}"
      return
    end
    first = center - LIST_RADIUS
    first = 1 if first < 1
    last = center + LIST_RADIUS
    last = lines.size if last > lines.size
    puts "[#{first}, #{last}] in #{file}"
    width = last.to_s.length
    (first..last).each do |n|
      marker = n == current_line ? "=>" : "  "
      puts "#{marker} #{n.to_s.rjust(width)}| #{lines[n - 1]}"
    end
  end

  # Shared by the CLI's `p`/`print` and DapSession's `evaluate` request:
  # evaluate expr against bnd, returning [success, message-or-inspected-
  # result] rather than printing, so DAP can put the result in a response
  # body instead of stdout.
  def evaluate_expression(bnd, expr)
    return [false, "No binding available for this breakpoint"] if bnd.nil?
    begin
      result = bnd.eval(expr)
      [true, result.inspect]
    rescue Exception => e
      # Exception, not StandardError: a bad expression can raise SyntaxError,
      [false, "#{e.class}: #{e.message}"]
    end
  end

  def print_expr(bnd, expr)
    _ok, message = evaluate_expression(bnd, expr)
    puts message
  end

  def add_display_cmd(bnd, expr)
    d = Display.new(expr)
    @displays << d
    idx = @displays.size
    puts "Display #{idx} added: #{expr}"
    d.print_line(bnd, idx)
  end

  def list_displays(bnd)
    shown = false
    @displays.each_with_index do |d, i|
      next unless d.active?
      shown = true
      d.print_line(bnd, i + 1)
    end
    puts "No display expressions set" unless shown
  end

  def delete_display(arg)
    if arg.nil? || arg.strip.empty?
      @displays.each(&:deactivate!)
      puts "Deleted all display expressions"
      return
    end
    n = arg.to_i
    idx = n - 1
    if n > 0 && idx < @displays.size && @displays[idx].active?
      @displays[idx].deactivate!
      puts "Deleted display ##{n}"
    else
      puts "No display ##{arg}"
    end
  end

  def show_displays(bnd)
    @displays.each_with_index do |d, i|
      next unless d.active?
      d.print_line(bnd, i + 1)
    end
  end

  def add_watch_cmd(bnd, expr)
    add_watch(expr)
    idx = watches.size
    puts "Watchpoint #{idx} added: #{expr}"
    puts watches[idx - 1].add_initial_value(bnd)
  end

  def list_watches
    list_entries(watches, "No watchpoints set")
  end

  def delete_watch(arg)
    if arg.nil? || arg.strip.empty?
      clear_watches
      puts "Deleted all watchpoints"
      return
    end
    n = arg.to_i
    if n > 0 && remove_watch(n)
      puts "Deleted watchpoint ##{n}"
    else
      puts "No watchpoint ##{arg}"
    end
  end

  def check_watches(bnd)
    return [] if bnd.nil?
    messages = []
    watches.each_with_index do |w, i|
      msg = w.break?(i + 1, bnd)
      messages << msg if msg
    end
    messages
  end

  def set_breakpoint(file, location)
    colon_pos = location.rindex(":")
    if colon_pos
      bp_file = location[0, colon_pos]
      bp_file = file if bp_file.empty?
      bp_line = location[(colon_pos + 1)..-1].to_i
    else
      bp_file = file
      bp_line = location.to_i
    end
    if bp_line > 0
      add_breakpoint(bp_file, bp_line)
      puts "Breakpoint added at #{bp_file}:#{bp_line}"
    else
      puts "Invalid line number"
    end
  end

  def list_breakpoints
    list_entries(breakpoints, "No breakpoints set")
  end

  # DapSession's setBreakpoints handler: DAP sends "the full current set
  # for this file" on every call, unlike add_breakpoint's append-only/
  # stable-numbering CLI design, so reconcile by deactivating this file's
  # existing breakpoints (suffix-matched, same rule the hot path uses) and
  # re-adding the requested lines.
  def reconcile_breakpoints(file, lines)
    breakpoints.each_with_index do |bp, i|
      next unless bp.active?
      next if bp.file.empty? || !file.end_with?(bp.file)
      remove_breakpoint(i + 1)
    end
    lines.each { |line| add_breakpoint(file, line) }
  end

  def print_backtrace
    count = frame_count
    if count == 0
      puts "No frame information available"
      return
    end
    count.times do |depth|
      pos = frame_position(depth)
      next unless pos # e.g. the C frame a binding.debugger call itself runs in
      puts "  ##{depth} #{pos[0]}:#{pos[1]}"
    end
  end

  def list_entries(collection, empty_message)
    shown = false
    collection.each_with_index do |bp, i|
      next unless bp.active?
      shown = true
      puts bp.numbered_line(i + 1)
    end
    puts empty_message unless shown
  end

  def delete_breakpoint(arg)
    if arg.nil? || arg.strip.empty?
      clear_breakpoints
      puts "Deleted all breakpoints"
      return
    end
    n = arg.to_i
    if n > 0 && remove_breakpoint(n)
      puts "Deleted breakpoint ##{n}"
    else
      puts "No breakpoint ##{arg}"
    end
  end

  # Dispatches one command line typed at the (prdb) prompt. Returns true if
  # the prompt loop should stop reading input and let the paused script
  # resume (continue/step/next/quit), false to keep prompting.
  def dispatch_command(cmd, verb, arg, file, line, bnd)
    case verb
    when "", "c", "continue"
      set_run_mode
      return true
    when "s", "step"
      set_step_mode
      return true
    when "n", "next"
      set_next_mode
      return true
    when "q", "quit"
      request_quit
      return true
    when "bt", "where"
      print_backtrace
    when "l", "list"
      center = arg ? arg.to_i : line
      center = line if center <= 0
      show_source(file, line, center)
    when "b", "break"
      if arg
        set_breakpoint(file, arg)
      else
        list_breakpoints
      end
    when "d", "delete"
      delete_breakpoint(arg)
    when "p", "print"
      if arg
        print_expr(bnd, arg)
      else
        puts "Usage: p <expression>"
      end
    when "disp", "display"
      if arg
        add_display_cmd(bnd, arg)
      else
        list_displays(bnd)
      end
    when "undisp", "undisplay"
      delete_display(arg)
    when "w", "watch"
      if arg
        add_watch_cmd(bnd, arg)
      else
        list_watches
      end
    when "uw", "unwatch"
      delete_watch(arg)
    else
      puts "unknown command: #{cmd}"
    end
    false
  end

  # Called from the C code_fetch_hook. bnd is a Binding for the paused frame
  # (nil if none could be built). real_stop is false for a watch-forced
  # per-line visit: return silently then unless a watch changed.
  def on_break(file, line, bnd, real_stop)
    changes = check_watches(bnd)
    return if !real_stop && changes.empty?

    if @dap_session
      # DAP requires initialize/attach/setBreakpoints/configurationDone
      # before any breakpoint can fire, but this debugger only starts
      # watching for breakpoints from the first binding.debugger call
      # onward -- so that call's own on_break is the one and only place
      # "the script hasn't run yet" and "we can still talk to a client"
      # overlap. A dropped connection during the handshake just leaves the
      # session running under the CLI below for the rest of the script.
      if @dap_session.perform_handshake(self)
        @dap_session.run_request_loop(self)
        return
      end
      @dap_session = nil
    end

    cli_on_break(file, line, bnd, changes)
  end

  private

  # The interactive (prdb) prompt loop, split out from on_break so its
  # `ensure` (terminal mode restore) stays scoped to a path that always
  # assigns prev_term first -- on_break itself can return earlier than
  # this, via the DAP branch above, without ever touching the terminal.
  def cli_on_break(file, line, bnd, changes)
    puts
    puts "Breakpoint: #{file}:#{line}"
    changes.each { |m| puts m }
    show_displays(bnd)
    # TERM=dumb short-circuits Editor::Line#refresh's per-keystroke
    # cursor-position query, which swallows piped input like the size probe
    # in Debugger#initialize. Scoped to the prompt loop only.
    prev_term = ENV['TERM']
    ENV['TERM'] = 'dumb'
    # Force raw mode once: STDIN.read_nonblock only saves/restores termios
    # around each call, so between polls a real POSIX tty reverts to cooked
    # mode and its kernel echo doubles every typed character. Restored via
    # cooked! in ensure so the debugged script's own gets etc. behave
    # normally.
    STDIN.raw!
    @editor.start do |editor, buffer, c|
      case c
      when 10, 13 # Enter
        cmd = buffer.dump.chomp.strip
        editor.feed_at_bottom
        editor.save_history
        buffer.clear
        verb, arg = cmd.split(" ", 2)
        verb ||= ""
        break if dispatch_command(cmd, verb, arg, file, line, bnd)
      end
    end
  ensure
    STDIN.cooked!
    ENV['TERM'] = prev_term
  end
end
