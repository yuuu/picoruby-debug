MRuby::Gem::Specification.new('picoruby-debug') do |spec|
  spec.license = 'MIT'
  spec.author  = 'Yuhei Okazaki'
  spec.summary = 'Debugger for PicoRuby (mruby only)'

  spec.add_dependency 'picoruby-sandbox'
  spec.add_dependency 'picoruby-editor'
  spec.add_dependency 'picoruby-io-console'
  if build.vm_mruby?
    spec.add_dependency 'mruby-binding', gemdir: "#{MRUBY_ROOT}/mrbgems/picoruby-mruby/lib/mruby/mrbgems/mruby-binding"
    spec.add_dependency 'mruby-eval', gemdir: "#{MRUBY_ROOT}/mrbgems/picoruby-mruby/lib/mruby/mrbgems/mruby-eval"
  end

  build.defines << 'MRB_USE_DEBUG_HOOK' if build.vm_mruby?
end
