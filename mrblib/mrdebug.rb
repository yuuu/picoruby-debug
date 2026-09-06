# mrdebug: a debugger core for mruby. Everything but the VM hook itself
# (src/hook.c, src/frame.c) lives on the Ruby side.
module MRDebug
  VERSION = '0.0.1'

  def self.session
    @session
  end

  def self.session=(session)
    @session = session
    MRDebug::Hook.install(session)
  end

  # Overridden on host builds (tools/mrdebug/device.rb); a no-op otherwise.
  def self.autostart
  end

  def self.break(bnd)
    autostart if @session.nil?
    return unless @session
    file, line = bnd.source_location
    MRDebug::Hook.enter(file, line, bnd)
  end
end
