# Drives a plain mruby checkout to build and test mrdebug.
#
# Point MRDEBUG_MRUBY_DIR at an mruby checkout (mruby 4.0.0 or later):
#
#   MRDEBUG_MRUBY_DIR=~/src/mruby rake build
#
# and MRDEBUG_PICORUBY_DIR at a picoruby checkout for the picoruby:* tasks.
#
MRDEBUG_ROOT = __dir__
BUILD_CONFIG = File.join(MRDEBUG_ROOT, 'test', 'build_config', 'mruby.rb')
BUILD_DIR    = File.join(MRDEBUG_ROOT, 'build')
MRUBY_BIN    = File.join(BUILD_DIR, 'host', 'bin', 'mruby')

PICORUBY_BUILD_CONFIG = File.join(MRDEBUG_ROOT, 'test', 'build_config', 'picoruby.rb')
PICORUBY_BUILD_DIR    = File.join(BUILD_DIR, 'picoruby')
PICORUBY_BIN          = File.join(PICORUBY_BUILD_DIR, 'host', 'bin', 'picoruby')

def checkout_dir(var, what)
  dir = ENV[var]
  if dir.nil? || dir.empty?
    abort "#{var} is not set: point it at #{what} checkout"
  end
  dir = File.expand_path(dir)
  abort "#{dir}/Rakefile not found: #{var} does not look like #{what} checkout" unless File.exist?(File.join(dir, 'Rakefile'))
  dir
end

def mruby_dir
  checkout_dir('MRDEBUG_MRUBY_DIR', 'an mruby')
end

def picoruby_dir
  checkout_dir('MRDEBUG_PICORUBY_DIR', 'a picoruby')
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

# Same as mruby_rake, but drives a PicoRuby checkout (PICORB_VM_MRUBY host
# build). Artifacts land in build/picoruby/.
def picoruby_rake(*tasks)
  env = {
    'MRUBY_CONFIG' => PICORUBY_BUILD_CONFIG,
    'MRUBY_BUILD_DIR' => PICORUBY_BUILD_DIR,
  }
  sh env, 'rake', '-f', File.join(picoruby_dir, 'Rakefile'), *tasks
end

# Runs spec/ (RSpec, under CRuby) against an already-built +bin+.
def run_smoke(bin)
  sh({ 'MRDEBUG_SMOKE_BIN' => bin }, 'bundle', 'exec', 'rspec')
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

  desc 'Run the spec/ smoke specs against build/host/bin/mruby'
  task smoke: :build do
    run_smoke MRUBY_BIN
  end
end

namespace :picoruby do
  desc 'Build PicoRuby (MRDEBUG_PICORUBY_DIR) with mrdebug linked in (build/picoruby/host/bin/picoruby)'
  task :build do
    picoruby_rake
  end

  desc 'Run the spec/ smoke specs against build/picoruby/host/bin/picoruby'
  task smoke: :build do
    run_smoke PICORUBY_BIN
  end
end

desc 'Remove mrdebug build artifacts'
task :clean do
  rm_rf BUILD_DIR
end

task default: :build
