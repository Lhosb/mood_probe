RSpec.describe MoodProbe::Extractor do
  let(:good_features) do
    {
      valence: 0.4, arousal: 0.6, danceability: 0.7,
      mood_acoustic: 0.2, mood_relaxed: 0.8, mood_happy: 0.5
    }
  end
  let(:backend) { instance_double(MoodProbe::Backends::EssentiaPython) }
  let(:extractor) { described_class.new(models_dir: "/models", backend:) }

  before do
    allow(backend).to receive(:verify!).and_return(true)
    allow(backend).to receive(:analyze)
  end

  it "returns positionally aligned results for mixed good/bad/good/bad input without raising" do
    paths = [
      "/audio/good-1.wav",
      Pathname("/audio/bad-1.wav"),
      Pathname("/audio/good-2.wav"),
      "/audio/bad-2.wav"
    ]
    allow(backend).to receive(:analyze).and_return(
      good_features,
      MoodProbe::UnreadableAudioError.new("bad 1"),
      good_features.merge(valence: 0.9),
      MoodProbe::TimeoutError.new("bad 2")
    )

    results = nil
    expect { results = extractor.analyze_all(paths) }.not_to raise_error

    expect(results.map(&:path)).to eq(paths.map { |path| Pathname(path) })
    expect(results.map(&:ok?)).to eq([true, false, true, false])
    expect(results.map(&:error).compact).to all(be_a(MoodProbe::TrackError))
    expect(results[2].features.to_h[:valence]).to eq(0.9)
  end

  it "raises configuration errors before any file is processed" do
    allow(backend).to receive(:verify!).and_raise(MoodProbe::ConfigurationError, "bad models")

    expect { extractor.analyze_all(%w[one.wav two.wav]) }
      .to raise_error(MoodProbe::ConfigurationError, "bad models")
    expect(backend).not_to have_received(:analyze)
  end

  it "still performs configuration preflight for an empty input list" do
    allow(backend).to receive(:verify!).and_raise(MoodProbe::ConfigurationError, "bad models")

    expect { extractor.analyze_all([]) }
      .to raise_error(MoodProbe::ConfigurationError, "bad models")
    expect(backend).not_to have_received(:analyze)
  end

  it "raises a per-track result error from analyze" do
    allow(backend).to receive(:analyze).and_return(MoodProbe::UnreadableAudioError.new("bad audio"))

    expect { extractor.analyze("bad.wav") }.to raise_error(MoodProbe::UnreadableAudioError, "bad audio")
  end

  it "accepts String and Pathname inputs" do
    allow(backend).to receive(:analyze).and_return(good_features, good_features)

    results = extractor.analyze_all(["string.wav", Pathname("pathname.wav")])

    expect(results.map(&:path)).to eq([Pathname("string.wav"), Pathname("pathname.wav")])
  end

  it "preflights exactly once for a multi-path analyze_all" do
    allow(backend).to receive(:analyze).and_return(good_features)
    allow(extractor).to receive(:verify!).and_call_original

    extractor.analyze_all(%w[one.wav two.wav three.wav])

    expect(extractor).to have_received(:verify!).once
  end

  it "preflights exactly once across repeated analyze calls" do
    allow(backend).to receive(:analyze).and_return(good_features)

    extractor.analyze("one.wav")
    extractor.analyze("two.wav")

    expect(backend).to have_received(:verify!).once
  end

  it "propagates fatal BackendError and stops processing later paths" do
    allow(backend).to receive(:analyze).with(Pathname("one.wav")).and_return(good_features)
    allow(backend).to receive(:analyze).with(Pathname("two.wav"))
                                       .and_raise(MoodProbe::BackendError, "invalid NDJSON")
    allow(backend).to receive(:analyze).with(Pathname("three.wav")).and_return(good_features)

    expect { extractor.analyze_all(%w[one.wav two.wav three.wav]) }
      .to raise_error(MoodProbe::BackendError, /invalid NDJSON/)
    expect(backend).not_to have_received(:analyze).with(Pathname("three.wav"))
  end

  {
    "a non-finite value" => ->(features) { features.merge(valence: Float::NAN) },
    "a value outside the sanity window" => ->(features) { features.merge(arousal: 1.5001) },
    "a value below the sanity window" => ->(features) { features.merge(valence: -0.5001) },
    "a classification value outside its range" => ->(features) { features.merge(danceability: -0.0001) }
  }.each do |description, malformed_features|
    it "keeps positional results when one file returns #{description}" do
      paths = %w[good-1.wav good-2.wav malformed.wav good-3.wav]
      allow(backend).to receive(:analyze).and_return(
        good_features.merge(valence: 0.1),
        good_features.merge(valence: 0.2),
        malformed_features.call(good_features),
        good_features.merge(valence: 0.4)
      )

      results = nil
      expect { results = extractor.analyze_all(paths) }.not_to raise_error

      expect(results.map(&:path)).to eq(paths.map { |path| Pathname(path) })
      expect(results.map(&:ok?)).to eq([true, true, false, true])
      expect(results[2].error).to be_a(MoodProbe::MalformedOutputError)
      expect(results.values_at(0, 1, 3).map { |result| result.features.to_h[:valence] }).to eq([0.1, 0.2, 0.4])
    end
  end

  {
    "a missing key" => ->(features) { features.except(:mood_happy) },
    "an unexpected key" => ->(features) { features.merge(mood_joy: 0.5) },
    "a non-numeric type" => ->(features) { features.merge(valence: "0.4") }
  }.each do |description, schema_drift|
    it "raises SchemaError and stops later files when one file returns #{description}" do
      allow(backend).to receive(:analyze).with(Pathname("one.wav")).and_return(good_features)
      allow(backend).to receive(:analyze).with(Pathname("schema-drift.wav"))
                                         .and_return(schema_drift.call(good_features))
      allow(backend).to receive(:analyze).with(Pathname("three.wav")).and_return(good_features)

      expect { extractor.analyze_all(%w[one.wav schema-drift.wav three.wav]) }
        .to raise_error(MoodProbe::SchemaError)
      expect(backend).not_to have_received(:analyze).with(Pathname("three.wav"))
    end
  end

  it "raises MalformedOutputError when analyze receives malformed features" do
    allow(backend).to receive(:analyze).and_return(good_features.merge(valence: Float::NAN))

    expect { extractor.analyze("malformed.wav") }
      .to raise_error(MoodProbe::MalformedOutputError, /finite/)
  end
end
