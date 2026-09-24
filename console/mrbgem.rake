MRuby::Gem::Specification.new('mrdebug-console') do |spec|
  spec.license = 'MIT'
  spec.author  = 'Yuhei Okazaki'
  spec.summary = 'On-device interactive (mrdbg) console for mrdebug on PicoRuby'

  spec.add_dependency 'mrdebug', gemdir: File.expand_path('..', spec.dir)
  spec.add_dependency 'picoruby-editor', core: 'picoruby-editor'
  spec.add_dependency 'picoruby-io-console', core: 'picoruby-io-console'
end
