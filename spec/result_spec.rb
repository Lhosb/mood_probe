RSpec.describe MoodProbe::Result do
  let(:features) do
    MoodProbe::Features.new(
      valence: 0.4, arousal: 0.6, danceability: 0.7,
      mood_acoustic: 0.2, mood_relaxed: 0.8, mood_happy: 0.5
    )
  end

  it "represents a successful path" do
    result = described_class.new(path: Pathname("/tmp/good.wav"), features:)

    expect(result).to be_ok
    expect(result.path).to eq(Pathname("/tmp/good.wav"))
    expect(result.features).to eq(features)
    expect(result.error).to be_nil
  end

  it "represents a failed path" do
    error = MoodProbe::UnreadableAudioError.new("bad audio")
    result = described_class.new(path: "/tmp/bad.wav", error:)

    expect(result).not_to be_ok
    expect(result.features).to be_nil
    expect(result.error).to equal(error)
  end

  it "rejects results with both or neither payload set" do
    expect { described_class.new(path: "bad", features:, error: MoodProbe::TrackError.new) }
      .to raise_error(ArgumentError)
    expect { described_class.new(path: "bad") }.to raise_error(ArgumentError)
  end
end
