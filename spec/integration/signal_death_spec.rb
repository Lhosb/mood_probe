require "rbconfig"

module SignalDeathSpec
  class Runner
    def initialize
      @analyze_calls = 0
      @real_runner = MoodProbe::Backends::EssentiaPython::CommandRunner.new
    end

    def call(command, timeout:)
      return success_result if command.include?("--verify")

      @analyze_calls += 1
      return signal_result(timeout:) if @analyze_calls == 3

      path = command.fetch(2)
      features = {
        valence: @analyze_calls / 10.0,
        arousal: 0.6,
        danceability: 0.7,
        mood_acoustic: 0.2,
        mood_relaxed: 0.8,
        mood_happy: 0.5
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
      MoodProbe::Backends::EssentiaPython::CommandRunner::Result.new(
        stdout:,
        stderr: "",
        exitstatus: 0
      )
    end
  end
end

RSpec.describe "signal-killed backend isolation" do
  it "keeps siblings aligned when one real child dies by signal" do
    model_store = instance_double(MoodProbe::ModelStore, verify!: true)
    backend = MoodProbe::Backends::EssentiaPython.new(
      models_dir: "/models",
      command_runner: SignalDeathSpec::Runner.new,
      model_store:
    )
    extractor = MoodProbe::Extractor.new(models_dir: "/models", backend:)
    paths = %w[one.wav two.wav signal.wav four.wav]

    results = extractor.analyze_all(paths)

    expect(results.map(&:path)).to eq(paths.map { |path| Pathname(path) })
    expect(results.map(&:ok?)).to eq([true, true, false, true])
    expect(results[2].error).to be_a(MoodProbe::BackendProcessError)
    expect(results[2].error.message).to include("signal 9")
    expect(results.values_at(0, 1, 3).map { |result| result.features.to_h[:valence] }).to eq([0.1, 0.2, 0.4])
  end
end
