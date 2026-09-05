MRuby::Gem::Specification.new('mrdebug') do |spec|
  spec.license = 'MIT'
  spec.author  = 'Yuhei Okazaki'
  spec.summary = 'Debugger core for mruby'

  spec.build.defines << 'MRB_USE_DEBUG_HOOK'

  spec.add_dependency 'mruby-binding', core: 'mruby-binding'
  spec.add_dependency 'mruby-eval', core: 'mruby-eval'

  if spec.build.host?
    spec.add_dependency 'mruby-io', core: 'mruby-io'
    spec.add_dependency 'mruby-socket', core: 'mruby-socket'
    spec.rbfiles += Dir.glob("#{spec.dir}/tools/mrdebug/**/*.rb").sort

    # Host CLI binary (docs/plan-phase4.md step 4). mruby's `spec.bins`
    # convention (tasks/bin.rake) builds this from C sources under
    # tools/mrdebug/*.c (a bare launcher only -- see that file's header);
    # all real behavior lives in the Ruby just added above.
    spec.bins << 'mrdebug'
  end
end
