# mrdebug: a debugger core for mruby.
#
# Everything except the VM hook itself (src/hook.c, src/frame.c) lives on
# the Ruby side.
module MRDebug
  VERSION = '0.0.1'

  def self.session
    @session
  end

  def self.session=(session)
    @session = session
  end

  def self.break(bnd)
    file, line = bnd.source_location
    session.on_line(file, line, bnd)
  end
end
