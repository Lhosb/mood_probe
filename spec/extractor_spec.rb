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
end
