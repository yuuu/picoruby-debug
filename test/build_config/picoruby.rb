# Build config used to verify mrdebug against PicoRuby's PICORB_VM_MRUBY
# POSIX host build (the picoruby counterpart of test/build_config/mruby.rb).
#
# Loaded by PicoRuby's own Rakefile:
#
#   MRUBY_CONFIG=<mrdebug>/test/build_config/picoruby.rb \
#   MRUBY_BUILD_DIR=<mrdebug>/build/picoruby \
#   rake -f <picoruby>/Rakefile
#
# `rake picoruby:build` in the mrdebug repo does exactly that. PicoRuby's
# Rakefile has no mrbtest (its mruby test.rake is not loaded), so this build
# is checked by `rake picoruby:smoke` instead of `rake test:unit`.
MRDEBUG_ROOT = File.expand_path('../..', __dir__)

# Unnamed, i.e. "host": mrbgem.rake gates the console/CLI on build.host?.
MRuby::Build.new do |conf|
  conf.toolchain :gcc

  conf.cc.defines << "MRB_TICK_UNIT=4"
  conf.cc.defines << "MRB_TIMESLICE_TICK_COUNT=3"
  conf.cc.defines << "PICORB_PLATFORM_POSIX"
  conf.cc.defines << "MRB_INT64"
  conf.cc.defines << "MRB_NO_BOXING"
  conf.cc.defines << "MRB_UTF8_STRING"

  conf.picoruby

  # picoruby-socket (pulled in by mrdebug on host builds) links OpenSSL.
  conf.linker.libraries << 'ssl'
  conf.linker.libraries << 'crypto'

  conf.gembox "mruby-posix"
  conf.gembox "minimum"
  conf.gembox "core"
  conf.gembox "stdlib"
  conf.gem core: 'picoruby-bin-picoruby'
  conf.gem gemdir: MRDEBUG_ROOT

  conf.enable_debug
end
