module MRDebug
  module UI
    # The (prdb) prompt read directly off the device's own console (raw
    # STDIN/STDOUT via picoruby-io-console), using picoruby-editor's
    # Editor::Line for line editing/history -- the on-device counterpart to
    # LocalConsole (tools/mrdebug/ui/local_console.rb), which is Transport-
    # driven and host-only.
    class Console < Base
      def initialize
        # Deferred to first use, not gem-init time: the filesystem isn't
        # mounted yet during gem_init, and a require failing there silently
        # aborts every later gem_init (see CLAUDE.md's mrb_open() note).
        require 'editor'
        require 'io-console'
        @editor = Class.new(Editor::Line) do
          def initialize
            # Skip Editor::Base#initialize's terminal-size probe: on
            # piped/non-tty stdin it swallows already-buffered command
            # bytes. prdb's one-line commands never need real wrap/scroll
            # math, so a fixed size suffices.
            @height, @width = 24, 80
            @buffer = Editor::Buffer.new
            @history = [[""]]
            @history_index = 0
            @prev_cursor_y = 0
            self.prompt = "(prdb) "
          end
        end.new
      end

      def on_stop(session)
        puts session.stop_banner
        session.display_lines.each { |expr, result| puts "#{expr} = #{result}" }

        # TERM=dumb short-circuits Editor::Line#refresh's per-keystroke
        # cursor-position query, which otherwise swallows piped/pasted input.
        prev_term = ENV['TERM']
        ENV['TERM'] = 'dumb'
        # STDIN.read_nonblock only saves/restores termios around each call,
        # so between polls a real tty reverts to cooked mode and echoes
        # every typed character twice. cooked! in ensure restores it so the
        # debugged script's own gets etc. behave normally afterward.
        STDIN.raw!
        @editor.start do |editor, buffer, c|
          case c
          when 10, 13 # Enter
            line = buffer.dump.chomp
            editor.feed_at_bottom
            editor.save_history
            buffer.clear
            output, action = Command.dispatch(session, line)
            output.each { |l| puts l }
            break if action == :resume
          end
        end
      ensure
        STDIN.cooked!
        ENV['TERM'] = prev_term
      end
    end
  end

  # The (prdb) prompt on this device's own console -- no socket, no host
  # CLI. Mirrors MRDebug.attach_stdio (tools/mrdebug/device.rb, host builds)
  # for the on-device case.
  def self.attach_console
    session = Session.new
    session.ui = UI::Console.new
    self.session = session
    session
  end
end
