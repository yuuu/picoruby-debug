MRuby::Gem::Specification.new('mrdebug') do |spec|
  spec.license = 'MIT'
  spec.author  = 'Yuhei Okazaki'
  spec.summary = 'Debugger core for mruby'

  spec.build.defines << 'MRB_USE_DEBUG_HOOK'

  # PicoRuby vendors these gems outside MRUBY_ROOT, so core: can't find
  # them there; gemdir: is PicoRuby's own stdlib.gembox pattern.
  if spec.build.respond_to?(:picoruby?) && spec.build.picoruby?
    mruby_dir = "#{MRUBY_ROOT}/mrbgems/picoruby-mruby/lib/mruby/mrbgems"
    spec.add_dependency 'mruby-binding', gemdir: "#{mruby_dir}/mruby-binding"
    spec.add_dependency 'mruby-eval', gemdir: "#{mruby_dir}/mruby-eval"
  else
    spec.add_dependency 'mruby-binding', core: 'mruby-binding'
    spec.add_dependency 'mruby-eval', core: 'mruby-eval'
  end

  if spec.build.host?
    if spec.build.respond_to?(:picoruby?) && spec.build.picoruby?
      mruby_dir = "#{MRUBY_ROOT}/mrbgems/picoruby-mruby/lib/mruby/mrbgems"
      spec.add_dependency 'mruby-io', gemdir: "#{mruby_dir}/mruby-io"
      spec.add_dependency 'mruby-socket', gemdir: "#{mruby_dir}/mruby-socket"
      spec.add_dependency 'mruby-env', gemdir: "#{mruby_dir}/mruby-env"
    else
      spec.add_dependency 'mruby-io', core: 'mruby-io'
      spec.add_dependency 'mruby-socket', core: 'mruby-socket'
      spec.add_dependency 'mruby-env', core: 'mruby-env'
    end
    spec.rbfiles += Dir.glob("#{spec.dir}/tools/mrdebug/**/*.rb").sort

    # Host CLI binary (docs/plan-phase4.md step 4). mruby's `spec.bins`
    # convention (tasks/bin.rake) builds this from C sources under
    # tools/mrdebug/*.c (a bare launcher only -- see that file's header);
    # all real behavior lives in the Ruby just added above.
    spec.bins << 'mrdebug'
  end

  # PicoRuby's mrb_context has no svars field; see src/hook.c's guard.
  if spec.build.respond_to?(:picoruby?) && spec.build.picoruby?
    spec.build.defines << 'MRDEBUG_NO_SVARS'
  end
end
