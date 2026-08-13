require "rbconfig"

module SignalDeathSpec
  class Runner
    def initialize
      @analyze_calls = 0
      @real_runner = Sonance::Backends::EssentiaPython::CommandRunner.new
    end

    def call(command, timeout:)
      return success_result if command.include?("--verify")

      @analyze_calls += 1
      return signal_result(timeout:) if @analyze_calls == 3

      path = command.fetch(2)
      features = {
        mood_happy_musicnn: @analyze_calls / 10.0
      }
      success_result(JSON.generate(path:, features:) << "\n")
    end

    private

    def signal_result(timeout:)
      @real_runner.call(
        [RbConfig.ruby, "-e", "Process.kill('KILL', Process.pid)"],
        timeout:
      )
    end

    def success_result(stdout = "")
      Sonance::Backends::EssentiaPython::CommandRunner::Result.new(
        stdout:,
        stderr: "",
        exitstatus: 0
      )
    end
  end
end

RSpec.describe "signal-killed backend isolation" do
  it "keeps siblings aligned when one real child dies by signal" do
    backend = Sonance::Backends::EssentiaPython.new(
      models_dir: "/models",
      command_runner: SignalDeathSpec::Runner.new
    )
    plan = Sonance::Planner.new(registry: Sonance::Registry.default)
                           .plan_for(descriptors: [:mood_happy_musicnn])
    paths = %w[one.wav two.wav signal.wav four.wav]

    results = paths.map { |path| backend.analyze(path, plan:) }

    expect(results[2]).to be_a(Sonance::BackendProcessError)
    expect(results[2].message).to include("signal 9")
    expect(results.values_at(0, 1, 3).map { |result| result.fetch("mood_happy_musicnn") })
      .to eq([0.1, 0.2, 0.4])
  end
end
