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
                      .plan_for(descriptors: [:mood_happy])
  end
  let(:algorithm_plan) do
    MoodProbe::Planner.new(registry: MoodProbe::Registry.default)
                      .plan_for(descriptors: [:bpm])
  end

  it "preflights the Python and Essentia environment independently" do
    allow(runner).to receive(:call).and_return(success)

    expect(backend.preflight_environment!).to be(true)
    expect(runner).to have_received(:call).with(
      ["/custom/python", "-c", "import essentia.standard"],
      timeout: 10
    )
  end

  it "uses the current graph verification path for a model-backed plan" do
    allow(runner).to receive(:call).and_return(success)

    expect(backend.preflight_plan!(model_plan)).to be(true)
    expect(runner).to have_received(:call).with(
      ["/custom/python", kind_of(String), "--verify", "--models-dir", "/models"],
      timeout: 70
    )
  end

  it "does not launch the current all-model verifier for an algorithm-only plan" do
    expect(runner).not_to receive(:call)

    expect(backend.preflight_plan!(algorithm_plan)).to be(true)
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
      ["/custom/python", kind_of(String), "track.wav", "--models-dir", "/models"],
      timeout: 70
    )
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
    "wrong path" => JSON.generate(path: "other.wav", features: { "mood_happy" => 0.4 }) << "\n",
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
      .to raise_error(MoodProbe::BackendError, /returned no result/)
  end

  def success
    described_class::CommandRunner::Result.new(stdout: "", stderr: "", exitstatus: 0)
  end

  def valid_features
    {
      "valence" => 0.4,
      "arousal" => 0.6,
      "danceability" => 0.7,
      "mood_acoustic" => 0.2,
      "mood_relaxed" => 0.8,
      "mood_happy" => 0.5
    }
  end
end
