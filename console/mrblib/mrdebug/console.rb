require 'editor'
require 'io/console'

module MRDebug
  module UI
    # The (prdb) prompt read directly off the device's own console (raw
    # STDIN/STDOUT via picoruby-io-console), using picoruby-editor's
    # Editor::Line for line editing/history -- the on-device counterpart to
    # LocalConsole (tools/mrdebug/ui/local_console.rb), which is Transport-
    # driven and host-only.
    class Console < Base
      def initialize
        @editor = Class.new(Editor::Line) do
          def initialize
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

        prev_term = ENV['TERM']
        ENV['TERM'] = 'dumb'
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

  def self.autostart
    session = Session.new
    session.ui = UI::Console.new
    self.session = session
    session
  end
end
