# Smoke specs drive an already-built mruby/picoruby binary (MRDEBUG_SMOKE_BIN)
# from CRuby: `rake test:smoke` / `rake picoruby:smoke` build it and set this.
require 'open3'
require 'tmpdir'

module SmokeHelper
  PROMPT = '(mrdbg) '

  def smoke_bin
    bin = ENV['MRDEBUG_SMOKE_BIN']
    if bin.nil? || bin.empty?
      raise 'MRDEBUG_SMOKE_BIN is not set: run via rake test:smoke or rake picoruby:smoke'
    end
    raise "#{bin} not found: build it first" unless File.exist?(bin)
    File.expand_path(bin)
  end

  # Runs +source+ (as script.rb, by relative path so stop banners don't
  # depend on a tmpdir) with +commands+ piped to the (mrdbg) prompt.
  # Returns [[nil, output before the first prompt], [command, its output], ...];
  # the last command's output also holds whatever the script printed after
  # resuming for good.
  def debug(source, *commands)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'script.rb'), source)
      out, status = Open3.capture2(smoke_bin, 'script.rb',
                                   stdin_data: commands.map { |c| "#{c}\n" }.join,
                                   chdir: dir)
      expect(status).to be_success, "exited with #{status}:\n#{out}"
      [nil, *commands].zip(out.split(PROMPT, -1))
    end
  end
end

RSpec.configure do |config|
  config.include SmokeHelper
  config.disable_monkey_patching!
end
