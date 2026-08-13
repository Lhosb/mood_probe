RSpec.describe MoodProbe::Backends::EssentiaPython do
  let(:runner) { instance_double(described_class::CommandRunner) }
  let(:backend) do
    described_class.new(
      models_dir: "/models",
      timeout_per_file: 60,
      python_executable: "/custom/python",
      command_runner: runner
    )
  end
  let(:model_plan) do
    MoodProbe::Planner.new(registry: MoodProbe::Registry.default)
                      .plan_for(descriptors: [:mood_happy_musicnn])
  end
  let(:algorithm_plan) do
    MoodProbe::Planner.new(registry: MoodProbe::Registry.default)
                      .plan_for(descriptors: [:bpm_rhythm2013])
  end

  it "preflights the Python and Essentia environment independently" do
    allow(runner).to receive(:call).and_return(success)

    expect(backend.preflight_environment!).to be(true)
    expect(runner).to have_received(:call).with(
      ["/custom/python", "-c", "import essentia.standard"],
      timeout: 10
    )
  end

  it "passes the resolved plan to Python for model-backed preflight" do
    allow(runner).to receive(:call).and_return(success)

    expect(backend.preflight_plan!(model_plan)).to be(true)
    expect(runner).to have_received(:call).with(
      [
        "/custom/python",
        kind_of(String),
        "--verify",
        "--models-dir",
        "/models",
        "--plan-json",
        JSON.generate(model_plan.to_h)
      ],
      timeout: 70
    )
  end

  it "passes algorithm-only plans to Python construction preflight" do
    allow(runner).to receive(:call).and_return(success)

    expect(backend.preflight_plan!(algorithm_plan)).to be(true)
    expect(runner).to have_received(:call).with(
      [
        "/custom/python",
        kind_of(String),
        "--verify",
        "--models-dir",
        "/models",
        "--plan-json",
        JSON.generate(algorithm_plan.to_h)
      ],
      timeout: 70
    )
  end

  it "uses the injected Python executable and accepts a Pathname" do
    allow(runner).to receive(:call).and_return(
      described_class::CommandRunner::Result.new(
        stdout: JSON.generate(path: "track.wav", features: valid_features) << "\n",
        stderr: "",
        exitstatus: 0
      )
    )

    expect(backend.analyze(Pathname("track.wav"), plan: model_plan)).to eq(valid_features)
    expect(runner).to have_received(:call).with(
      [
        "/custom/python",
        kind_of(String),
        "track.wav",
        "--models-dir",
        "/models",
        "--plan-json",
        JSON.generate(model_plan.to_h)
      ],
      timeout: 70
    )
  end

  it "spills plans above 64 KiB to a temporary file and removes it" do
    large_plan = model_plan.with(
      emit: Array.new(2_000) { |index| model_plan.emit.first.merge(id: "mood_happy_#{index}") }
    )
    plan_path = nil
    allow(runner).to receive(:call) do |command, timeout:|
      plan_index = command.index("--plan-file")
      plan_path = Pathname(command.fetch(plan_index + 1))

      expect(timeout).to eq(70)
      expect(JSON.parse(plan_path.read).fetch("emit").length).to eq(2_000)
      success
    end

    expect(backend.preflight_plan!(large_plan)).to be(true)
    expect(plan_path).not_to exist
  end

  it "maps per-file protocol errors to TrackError instances" do
    allow(runner).to receive(:call).and_return(
      described_class::CommandRunner::Result.new(
        stdout: JSON.generate(
          path: "bad.wav",
          error: { type: "unreadable_audio", message: "decode failed" }
        ) << "\n",
        stderr: "",
        exitstatus: 0
      )
    )

    error = backend.analyze("bad.wav", plan: model_plan)

    expect(error).to be_a(MoodProbe::UnreadableAudioError)
    expect(error.message).to eq("decode failed")
  end

  it "maps malformed output protocol errors to MalformedOutputError" do
    allow(runner).to receive(:call).and_return(
      described_class::CommandRunner::Result.new(
        stdout: JSON.generate(
          path: "bad.wav",
          error: { type: "malformed_output", message: "non-finite feature values" }
        ) << "\n",
        stderr: "",
        exitstatus: 0
      )
    )

    error = backend.analyze("bad.wav", plan: model_plan)

    expect(error).to be_a(MoodProbe::MalformedOutputError)
    expect(error.message).to eq("non-finite feature values")
  end

  it "treats unknown protocol error types as fatal" do
    allow(runner).to receive(:call).and_return(
      described_class::CommandRunner::Result.new(
        stdout: JSON.generate(
          path: "bad.wav",
          error: { type: "new_backend_error", message: "new failure" }
        ) << "\n",
        stderr: "",
        exitstatus: 0
      )
    )

    expect { backend.analyze("bad.wav", plan: model_plan) }
      .to raise_error(MoodProbe::BackendError, /unknown error type: new_backend_error/)
  end

  it "maps command timeouts to a TrackError" do
    allow(runner).to receive(:call).and_raise(described_class::CommandTimeout)

    expect(backend.analyze("slow.wav", plan: model_plan)).to be_a(MoodProbe::TimeoutError)
  end

  it "maps an unavailable Python executable to a fatal configuration error" do
    unavailable_backend = described_class.new(
      models_dir: "/models",
      python_executable: "/definitely/missing/python"
    )

    expect { unavailable_backend.preflight_environment! }
      .to raise_error(MoodProbe::ConfigurationError, /python/i)
  end

  it "maps configuration and crash exits to fatal errors" do
    allow(runner).to receive(:call).and_return(
      described_class::CommandRunner::Result.new(stdout: "", stderr: "bad config", exitstatus: 2)
    )
    expect { backend.preflight_plan!(model_plan) }
      .to raise_error(MoodProbe::ConfigurationError, /bad config/)

    allow(runner).to receive(:call).and_return(
      described_class::CommandRunner::Result.new(stdout: "", stderr: "crash", exitstatus: 1)
    )
    expect { backend.analyze("track.wav", plan: model_plan) }
      .to raise_error(MoodProbe::BackendError, /crash/)
  end

  it "keeps a nil exit status inside the MoodProbe error taxonomy" do
    allow(runner).to receive(:call).and_return(
      described_class::CommandRunner::Result.new(
        stdout: "",
        stderr: "",
        exitstatus: nil,
        termsig: nil
      )
    )

    expect { backend.analyze("track.wav", plan: model_plan) }
      .to raise_error(MoodProbe::BackendError, /terminated/)
  end

  it "maps environment and plan preflight timeouts to BackendError" do
    allow(runner).to receive(:call).and_raise(described_class::CommandTimeout)

    expect { backend.preflight_environment! }
      .to raise_error(MoodProbe::BackendError, /environment preflight timed out/)
    expect { backend.preflight_plan!(model_plan) }
      .to raise_error(MoodProbe::BackendError, /plan preflight timed out/)
  end

  {
    "no result" => "",
    "wrong path" => JSON.generate(
      path: "other.wav",
      features: { "mood_happy_musicnn" => 0.4 }
    ) << "\n",
    "omitted features" => JSON.generate(path: "track.wav") << "\n",
    "invalid NDJSON" => "not json\n"
  }.each do |description, stdout|
    it "maps #{description} to BackendError" do
      allow(runner).to receive(:call).and_return(
        described_class::CommandRunner::Result.new(stdout:, stderr: "", exitstatus: 0)
      )

      expect { backend.analyze("track.wav", plan: model_plan) }
        .to raise_error(MoodProbe::BackendError)
    end
  end

  it "treats multiple NDJSON results for one path as a fatal protocol error" do
    line = JSON.generate(path: "track.wav", features: valid_features)
    allow(runner).to receive(:call).and_return(
      described_class::CommandRunner::Result.new(
        stdout: "#{line}\n#{line}\n",
        stderr: "",
        exitstatus: 0
      )
    )

    expect { backend.analyze("track.wav", plan: model_plan) }
      .to raise_error(MoodProbe::BackendError, /returned 2 results for 1 paths/)
  end

  def success
    described_class::CommandRunner::Result.new(stdout: "", stderr: "", exitstatus: 0)
  end

  def valid_features
    {
      "mood_happy_musicnn" => 0.5
    }
  end
end
