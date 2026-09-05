MRuby::Gem::Specification.new('mrdebug') do |spec|
  spec.license = 'MIT'
  spec.author  = 'Yuhei Okazaki'
  spec.summary = 'Debugger core for mruby'

  spec.build.defines << 'MRB_USE_DEBUG_HOOK'

  # PicoRuby's PICORB_VM_MRUBY builds vendor mruby-binding/mruby-eval/
  # mruby-io/mruby-socket under mrbgems/picoruby-mruby/lib/mruby/mrbgems
  # rather than MRUBY_ROOT/mrbgems, so `core:` (which always looks under
  # MRUBY_ROOT) can't find them there; `gemdir:` pointing straight at the
  # vendored path is what PicoRuby's own stdlib.gembox already does for the
  # same two gems. `build.picoruby?` only exists on PicoRuby's build
  # subclass (lib/picoruby/build.rb monkeypatch), hence respond_to? first --
  # plain mruby keeps using `core:` exactly as before.
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
    else
      spec.add_dependency 'mruby-io', core: 'mruby-io'
      spec.add_dependency 'mruby-socket', core: 'mruby-socket'
    end
    spec.rbfiles += Dir.glob("#{spec.dir}/tools/mrdebug/**/*.rb").sort

    # Host CLI binary (docs/plan-phase4.md step 4). mruby's `spec.bins`
    # convention (tasks/bin.rake) builds this from C sources under
    # tools/mrdebug/*.c (a bare launcher only -- see that file's header);
    # all real behavior lives in the Ruby just added above.
    spec.bins << 'mrdebug'
  end

  # PicoRuby's vendored mruby fork's struct mrb_context has no `svars`
  # field (mainline-only, added for Fiber-scoped special variables) --
  # see src/hook.c's dbg_context_reset for the guard this feeds.
  if spec.build.respond_to?(:picoruby?) && spec.build.picoruby?
    spec.build.defines << 'MRDEBUG_NO_SVARS'
  end
end
