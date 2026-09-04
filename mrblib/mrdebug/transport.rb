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
    end
  end
end
