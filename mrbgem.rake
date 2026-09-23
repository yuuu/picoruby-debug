MRuby::Gem::Specification.new('mrdebug') do |spec|
  spec.license = 'MIT'
  spec.author  = 'Yuhei Okazaki'
  spec.summary = 'Debugger core for mruby'

  # picoruby? exists only on PicoRuby's MRuby::Build subclass.
  build    = spec.build
  picoruby = build.respond_to?(:picoruby?) && build.picoruby?
  host     = build.host?

  # PicoRuby vendors mruby's gems outside MRUBY_ROOT/mrbgems.
  add_mruby_gem = lambda do |name|
    if picoruby
      spec.add_dependency name, gemdir: "#{MRUBY_ROOT}/mrbgems/picoruby-mruby/lib/mruby/mrbgems/#{name}"
    else
      spec.add_dependency name, core: name
    end
  end

  # mruby-socket/-env collide with picoruby-socket/-env's class defs.
  add_socket_and_env = lambda do
    prefix = picoruby ? 'picoruby' : 'mruby'
    spec.add_dependency "#{prefix}-socket", core: "#{prefix}-socket"
    spec.add_dependency "#{prefix}-env", core: "#{prefix}-env"
  end

  build.defines << 'MRB_USE_DEBUG_HOOK'
  # PicoRuby's mrb_context has no svars field; see src/hook.c's guard.
  build.defines << 'MRDEBUG_NO_SVARS' if picoruby

  add_mruby_gem.call('mruby-binding')
  add_mruby_gem.call('mruby-eval')

  if host
    add_mruby_gem.call('mruby-io')
    add_socket_and_env.call
    spec.rbfiles += Dir.glob("#{spec.dir}/tools/mrdebug/**/*.rb").sort
    spec.bins << 'mrdebug'
  elsif picoruby
    # Firmware: device-side socket transport only (no CLI, no stdio).
    add_socket_and_env.call
    spec.rbfiles += %w[transport/socket.rb ui/local_console.rb device.rb]
                      .map { |f| "#{spec.dir}/tools/mrdebug/#{f}" }
  end
end
