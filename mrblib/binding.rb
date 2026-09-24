# Entry point into mrdebug from user scripts.
class Binding
  def debugger
    MRDebug.break(self)
  end
  alias b debugger
  alias break debugger
end
