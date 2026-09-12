module MRDebug
  module UI
    # A UI attached to a Session's #ui is called synchronously from
    # Session#on_line, inside the VM hook's own callback stack.
    class Base
      def on_stop(session)
        raise NotImplementedError, "#{self.class} must implement #on_stop"
      end
    end
  end
end
