RSpec.describe MoodProbe::Extractor do
  let(:backend) do
    double(
      "backend",
      preflight_environment!: true,
      preflight_plan!: true,
      analyze: nil
    )
  end
  let(:model_store) { double("model_store", verify!: true) }
  let(:extractor) do
    described_class.new(
      models_dir: "/models",
      backend:,
      model_store:
    )
  end

  it "requires descriptors for verification and analysis" do
    expect { extractor.verify! }.to raise_error(ArgumentError, /descriptors/)
    expect { extractor.analyze("track.wav") }.to raise_error(ArgumentError, /descriptors/)
    expect { extractor.analyze_all(["track.wav"]) }.to raise_error(ArgumentError, /descriptors/)
  end

  it "preflights an algorithm-only descriptor set once" do
    extractor.verify!(descriptors: [:bpm])
    extractor.verify!(descriptors: [:bpm])

    expect(backend).to have_received(:preflight_environment!).once
    expect(backend).to have_received(:preflight_plan!).once
    expect(model_store).to have_received(:verify!).with(filenames: []).once
  end

  it "re-preflights when a mixed request adds an algorithm with no model file" do
    extractor.verify!(descriptors: [:mood_happy])
    extractor.verify!(descriptors: %i[mood_happy bpm])

    expect(backend).to have_received(:preflight_environment!).once
    expect(backend).to have_received(:preflight_plan!).twice
    expect(model_store).to have_received(:verify!).with(
      filenames: ["msd-musicnn-1.pb", "mood_happy-msd-musicnn-1.pb"]
    ).twice
  end

  it "does not memoize a failed environment preflight" do
    allow(backend).to receive(:preflight_environment!)
      .and_raise(MoodProbe::ConfigurationError, "missing Python")

    2.times do
      expect { extractor.verify!(descriptors: [:bpm]) }
        .to raise_error(MoodProbe::ConfigurationError, "missing Python")
    end

    expect(backend).to have_received(:preflight_environment!).twice
    expect(backend).not_to have_received(:preflight_plan!)
  end

  it "raises for an unavailable Python executable on an algorithm-only request" do
    Dir.mktmpdir do |dir|
      unavailable = described_class.new(
        models_dir: dir,
        python_executable: "/nonexistent"
      )

      expect { unavailable.verify!(descriptors: [:bpm]) }
        .to raise_error(MoodProbe::ConfigurationError, /unable to launch Python/)
    end
  end

  it "does not let algorithm-only verification satisfy a later model-backed analysis" do
    Dir.mktmpdir do |dir|
      real_store = MoodProbe::ModelStore.new(dir, registry: MoodProbe::Registry.default)
      scoped = described_class.new(
        models_dir: dir,
        backend:,
        model_store: real_store
      )

      expect(scoped.verify!(descriptors: [:bpm])).to be(true)
      expect { scoped.analyze("track.wav", descriptors: [:mood_happy]) }
        .to raise_error(MoodProbe::ConfigurationError, /missing model.*msd-musicnn-1\.pb/)
      expect(backend).not_to have_received(:analyze)
    end
  end

  {
    "an unrequested id" => {
      requested: %i[mood_happy],
      payload: { mood_happy: 0.5, bpm: 120.0 },
      message: /unexpected descriptor: bpm/
    },
    "a missing id" => {
      requested: %i[mood_happy bpm],
      payload: { mood_happy: 0.5 },
      message: /missing descriptor: bpm/
    },
    "a wrong value type" => {
      requested: %i[mood_happy],
      payload: { mood_happy: "0.5" },
      message: /mood_happy.*numeric/
    }
  }.each do |description, test_case|
    it "raises and stops the batch for #{description}" do
      allow(backend).to receive(:analyze)
        .with(Pathname("one.wav"), plan: kind_of(MoodProbe::Plan))
        .and_return(test_case.fetch(:payload))
      allow(backend).to receive(:analyze)
        .with(Pathname("two.wav"), plan: kind_of(MoodProbe::Plan))
        .and_return(test_case.fetch(:payload))

      expect do
        extractor.analyze_all(%w[one.wav two.wav], descriptors: test_case.fetch(:requested))
      end.to raise_error(MoodProbe::SchemaError, test_case.fetch(:message))
      expect(backend).not_to have_received(:analyze)
        .with(Pathname("two.wav"), plan: kind_of(MoodProbe::Plan))
    end
  end

  it "constructs a requested 200-float MusiCNN vector" do
    allow(backend).to receive(:analyze)
      .and_return(musicnn_embedding: Array.new(200, 0.25))

    analysis = extractor.analyze("track.wav", descriptors: [:musicnn_embedding])

    expect(analysis[:musicnn_embedding]).to be_a(MoodProbe::Vector)
    expect(analysis[:musicnn_embedding].values.length).to eq(200)
  end

  it "raises a per-track vector length error with the descriptor and lengths" do
    allow(backend).to receive(:analyze)
      .and_return(musicnn_embedding: Array.new(199, 0.25))

    expect { extractor.analyze("track.wav", descriptors: [:musicnn_embedding]) }
      .to raise_error(
        MoodProbe::MalformedOutputError,
        /musicnn_embedding.*expected 200.*got 199/
      )
  end
end
