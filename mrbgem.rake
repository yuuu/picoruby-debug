MRuby::Gem::Specification.new('mrdebug') do |spec|
  spec.license = 'MIT'
  spec.author  = 'Yuhei Okazaki'
  spec.summary = 'Debugger core for mruby'

  spec.build.defines << 'MRB_USE_DEBUG_HOOK'

  spec.add_dependency 'mruby-binding', core: 'mruby-binding'
  spec.add_dependency 'mruby-eval', core: 'mruby-eval'

  if spec.build.host?
    spec.add_dependency 'mruby-io', core: 'mruby-io'
    spec.rbfiles += Dir.glob("#{spec.dir}/tools/mrdebug/**/*.rb").sort
  end
end
