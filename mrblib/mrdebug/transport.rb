module MRDebug
  module Transport
    # The (prdb) prompt's I/O contract -- not a wire protocol (DAP, rdbg, ...).
    class Base
      def gets
        raise NotImplementedError, "#{self.class} must implement #gets"
      end

      def write(str)
        raise NotImplementedError, "#{self.class} must implement #write"
      end

      def close
      end

      protected

      # Not String#chomp -- mruby-string-ext misbehaves under mrbtest.
      def strip_eol(line)
        len = line.size
        len -= 1 if len > 0 && line[len - 1] == "\n"
        len -= 1 if len > 0 && line[len - 1] == "\r"
        line[0, len]
      end
    end
  end
end
