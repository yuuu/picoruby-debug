# Build config used to verify mrdebug against a plain mruby checkout.
#
# It is loaded by mruby's Rakefile, not by mrdebug's, so paths are derived
# from this file's own location rather than from the working directory:
#
#   MRUBY_CONFIG=<mrdebug>/e2e/build_config.rb \
#   MRUBY_BUILD_DIR=<mrdebug>/build \
#   rake -f <mruby>/Rakefile
#
# `rake build` in the mrdebug repo does exactly that. MRUBY_BUILD_DIR keeps
# every artifact inside the mrdebug repo, so the mruby checkout being built
# against is never written to.
MRDEBUG_ROOT = File.expand_path('..', __dir__)

# The build has to be named "host" (not, say, "mrdebug-host"): MRuby::Build#host?
# is literally `@name == "host"`, and mrbgem.rake gates the local console front
# end and its mruby-io dependency on it.
MRuby::Build.new('host') do |conf|
  conf.toolchain

  conf.gembox 'default'
  conf.gem gemdir: MRDEBUG_ROOT

  conf.enable_test
end
