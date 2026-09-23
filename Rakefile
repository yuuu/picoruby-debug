# Drives a plain mruby checkout to build and test mrdebug.
#
# Point MRDEBUG_MRUBY_DIR at an mruby checkout (mruby 4.0.0 or later):
#
#   MRDEBUG_MRUBY_DIR=~/src/mruby rake build
#
# and MRDEBUG_PICORUBY_DIR at a picoruby checkout for the picoruby:* tasks.
#
require 'open3'

MRDEBUG_ROOT = __dir__
BUILD_CONFIG = File.join(MRDEBUG_ROOT, 'e2e', 'build_config.rb')
BUILD_DIR    = File.join(MRDEBUG_ROOT, 'build')
MRUBY_BIN    = File.join(BUILD_DIR, 'host', 'bin', 'mruby')

PICORUBY_BUILD_CONFIG = File.join(MRDEBUG_ROOT, 'e2e', 'picoruby_build_config.rb')
PICORUBY_BUILD_DIR    = File.join(BUILD_DIR, 'picoruby')
PICORUBY_BIN          = File.join(PICORUBY_BUILD_DIR, 'host', 'bin', 'picoruby')
SMOKE_DIR             = File.join(MRDEBUG_ROOT, 'e2e', 'smoke')

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

# Runs each e2e/smoke/NAME.rb under +bin+ with NAME.in piped to the (prdb)
# prompt, and compares stdout with NAME.out. Scripts run from e2e/smoke/ by
# relative path, so the stop banners in NAME.out don't depend on where the
# repo is checked out. Set MRDEBUG_SMOKE_UPDATE=1 to rewrite NAME.out.
def run_smoke(bin)
  abort "#{bin} not found: build it first" unless File.exist?(bin)
  update = ENV['MRDEBUG_SMOKE_UPDATE'] == '1'
  failed = []
  Dir.glob(File.join(SMOKE_DIR, '*.rb')).sort.each do |script|
    name = File.basename(script, '.rb')
    input = File.read(File.join(SMOKE_DIR, "#{name}.in"))
    expected_path = File.join(SMOKE_DIR, "#{name}.out")
    actual, status = Open3.capture2(bin, "#{name}.rb", stdin_data: input, chdir: SMOKE_DIR)
    if update
      File.write(expected_path, actual)
      puts "updated #{name}.out"
    elsif status.success? && actual == File.read(expected_path)
      puts "ok     #{name}"
    else
      puts "FAILED #{name} (#{status})"
      puts '--- expected', File.read(expected_path), '--- actual', actual
      failed << name
    end
  end
  abort "smoke test failed: #{failed.join(', ')}" unless failed.empty?
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

  desc 'Pipe (prdb) commands into e2e/smoke/*.rb under build/host/bin/mruby'
  task smoke: :build do
    run_smoke MRUBY_BIN
  end
end

namespace :picoruby do
  desc 'Build PicoRuby (MRDEBUG_PICORUBY_DIR) with mrdebug linked in (build/picoruby/host/bin/picoruby)'
  task :build do
    picoruby_rake
  end

  desc 'Pipe (prdb) commands into e2e/smoke/*.rb under build/picoruby/host/bin/picoruby'
  task smoke: :build do
    run_smoke PICORUBY_BIN
  end
end

desc 'Remove mrdebug build artifacts'
task :clean do
  rm_rf BUILD_DIR
end

task default: :build
