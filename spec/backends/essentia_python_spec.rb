RSpec.describe MoodProbe::Backends::EssentiaPython do
  let(:runner) { instance_double(described_class::CommandRunner) }
  let(:model_store) { instance_double(MoodProbe::ModelStore, verify!: true) }
  let(:backend) do
    described_class.new(
      models_dir: "/models",
      timeout_per_file: 60,
      python_executable: "/custom/python",
      command_runner: runner,
      model_store:
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

    expect(backend.analyze(Pathname("track.wav"))).to eq(valid_features)
    expect(runner).to have_received(:call).with(
      ["/custom/python", kind_of(String), "track.wav", "--models-dir", "/models"],
      timeout: 70
    )
  end

  it "loads and verifies all model graphs during preflight" do
    allow(runner).to receive(:call).and_return(
      described_class::CommandRunner::Result.new(stdout: "", stderr: "", exitstatus: 0)
    )

    expect(backend.verify!).to be(true)
    expect(model_store).to have_received(:verify!)
    expect(runner).to have_received(:call).with(
      ["/custom/python", kind_of(String), "--verify", "--models-dir", "/models"],
      timeout: 70
    )
  end

  it "memoizes a successful preflight" do
    allow(runner).to receive(:call).and_return(
      described_class::CommandRunner::Result.new(stdout: "", stderr: "", exitstatus: 0)
    )

    expect(backend.verify!).to be(true)
    expect(backend.verify!).to be(true)

    expect(model_store).to have_received(:verify!).once
    expect(runner).to have_received(:call).once
  end

  it "maps per-file protocol errors to TrackError instances" do
    allow(runner).to receive(:call).and_return(
      described_class::CommandRunner::Result.new(
        stdout: JSON.generate(path: "bad.wav", error: { type: "unreadable_audio", message: "decode failed" }) << "\n",
        stderr: "",
        exitstatus: 0
      )
    )

    error = backend.analyze("bad.wav")

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

    error = backend.analyze("bad.wav")

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

    expect { backend.analyze("bad.wav") }
      .to raise_error(MoodProbe::BackendError, /unknown error type: new_backend_error/)
  end

  it "initializes verification state" do
    expect(backend.instance_variable_get(:@verified)).to be(false)
  end

  it "maps command timeouts to a TrackError" do
    allow(runner).to receive(:call).and_raise(MoodProbe::Backends::EssentiaPython::CommandTimeout)

    expect(backend.analyze("slow.wav")).to be_a(MoodProbe::TimeoutError)
  end

  it "maps an unavailable Python executable to a fatal configuration error" do
    unavailable_backend = described_class.new(
      models_dir: "/models",
      python_executable: "/definitely/missing/python",
      model_store:
    )

    expect { unavailable_backend.analyze("track.wav") }
      .to raise_error(MoodProbe::ConfigurationError, /python/i)
  end

  it "maps configuration and crash exits to fatal errors" do
    allow(runner).to receive(:call).and_return(
      described_class::CommandRunner::Result.new(stdout: "", stderr: "bad config", exitstatus: 2)
    )
    expect { backend.verify! }.to raise_error(MoodProbe::ConfigurationError, /bad config/)

    allow(runner).to receive(:call).and_return(
      described_class::CommandRunner::Result.new(stdout: "", stderr: "crash", exitstatus: 1)
    )
    expect { backend.analyze("track.wav") }.to raise_error(MoodProbe::BackendError, /crash/)
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

    expect { backend.analyze("track.wav") }
      .to raise_error(MoodProbe::BackendError, /terminated/)
  end

  it "maps verify timeouts to BackendError" do
    allow(runner).to receive(:call).and_raise(described_class::CommandTimeout)

    expect { backend.verify! }.to raise_error(MoodProbe::BackendError, /preflight timed out/)
  end

  {
    "no result" => "",
    "wrong path" => JSON.generate(path: "other.wav", features: { "valence" => 0.4 }) << "\n",
    "omitted features" => JSON.generate(path: "track.wav") << "\n",
    "invalid NDJSON" => "not json\n"
  }.each do |description, stdout|
    it "maps #{description} to BackendError" do
      allow(runner).to receive(:call).and_return(
        described_class::CommandRunner::Result.new(stdout:, stderr: "", exitstatus: 0)
      )

      expect { backend.analyze("track.wav") }.to raise_error(MoodProbe::BackendError)
    end
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
