# Drives a plain mruby checkout to build and test mrdebug.
#
# Point MRDEBUG_MRUBY_DIR at an mruby checkout (mruby 4.0.0 or later):
#
#   MRDEBUG_MRUBY_DIR=~/src/mruby rake build
#
MRDEBUG_ROOT = __dir__
BUILD_CONFIG = File.join(MRDEBUG_ROOT, 'e2e', 'build_config.rb')
BUILD_DIR    = File.join(MRDEBUG_ROOT, 'build')
MRUBY_BIN    = File.join(BUILD_DIR, 'host', 'bin', 'mruby')

def mruby_dir
  dir = ENV['MRDEBUG_MRUBY_DIR']
  if dir.nil? || dir.empty?
    abort 'MRDEBUG_MRUBY_DIR is not set: point it at an mruby checkout (e.g. ~/src/mruby)'
  end
  dir = File.expand_path(dir)
  abort "#{dir}/Rakefile not found: MRDEBUG_MRUBY_DIR does not look like an mruby checkout" unless File.exist?(File.join(dir, 'Rakefile'))
  dir
end

# Runs mruby's own rake with mrdebug mounted as a gem. Artifacts land in
# mrdebug's build/ directory, never in the mruby checkout.
def mruby_rake(*tasks)
  env = {
    'MRUBY_CONFIG' => BUILD_CONFIG,
    'MRUBY_BUILD_DIR' => BUILD_DIR,
  }
  sh env, 'rake', '-f', File.join(mruby_dir, 'Rakefile'), *tasks
end

desc 'Build mruby with mrdebug linked in (build/host/bin/mruby)'
task :build do
  mruby_rake
end

desc 'Run mrdebug\'s unit tests (test/*.rb, mruby assert)'
namespace :test do
  task :unit do
    mruby_rake 'test:build'
    sh File.join(BUILD_DIR, 'host', 'bin', 'mrbtest')
  end
end

desc 'Remove mrdebug build artifacts'
task :clean do
  rm_rf BUILD_DIR
end

task default: :build
