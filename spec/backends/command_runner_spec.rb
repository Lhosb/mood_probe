require "rbconfig"

RSpec.describe MoodProbe::Backends::EssentiaPython::CommandRunner do
  it "terminates the subprocess group and returns promptly on timeout" do
    runner = described_class.new
    child_pid = nil

    Dir.mktmpdir do |dir|
      pid_file = File.join(dir, "child.pid")
      script = <<~RUBY
        child = spawn(#{RbConfig.ruby.inspect}, "-e", "sleep 3")
        File.write(ARGV.fetch(0), child)
        sleep 3
      RUBY
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      expect { runner.call([RbConfig.ruby, "-e", script, pid_file], timeout: 0.2) }
        .to raise_error(MoodProbe::Backends::EssentiaPython::CommandTimeout)

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
      child_pid = Integer(File.read(pid_file))
      expect(elapsed).to be < 1.5
      expect { Process.kill(0, child_pid) }.to raise_error(Errno::ESRCH)
    end
  ensure
    begin
      Process.kill("KILL", child_pid) if child_pid
    rescue Errno::ESRCH
      nil
    end
  end
end
