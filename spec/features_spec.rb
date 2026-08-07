RSpec.describe MoodProbe::Features do
  subject(:features) { described_class.new(values) }

  let(:values) do
    {
      valence: 0.4,
      arousal: 0.6,
      danceability: 0.7,
      mood_acoustic: 0.2,
      mood_relaxed: 0.8,
      mood_happy: 0.5
    }
  end

  it "returns a symbol-keyed hash containing exactly the six mood heads" do
    expect(features.to_h).to eq(values)
  end

  it "normalizes string keys from JSON output" do
    string_values = values.transform_keys(&:to_s)

    expect(described_class.new(string_values).to_h).to eq(values)
  end

  it "clamps regression heads just outside the output range" do
    values[:valence] = -0.004
    values[:arousal] = 1.025

    expect(features.to_h).to include(valence: 0.0, arousal: 1.0)
  end

  it "accepts and clamps the inclusive sanity-window edges" do
    values[:valence] = -0.5
    values[:arousal] = 1.5

    expect(features.to_h).to include(valence: 0.0, arousal: 1.0)
  end

  it "rejects a non-finite value" do
    values[:valence] = Float::NAN

    expect { features }.to raise_error(MoodProbe::MalformedOutputError, /finite/)
  end

  it "rejects a missing key" do
    values.delete(:mood_happy)

    expect { features }.to raise_error(MoodProbe::SchemaError, /mood_happy/)
  end

  it "rejects an unexpected key as schema drift" do
    values[:mood_joy] = 0.5

    expect { features }.to raise_error(MoodProbe::SchemaError, /mood_joy/)
  end

  it "rejects a non-numeric type as schema drift" do
    values[:valence] = "0.4"

    expect { features }.to raise_error(MoodProbe::SchemaError, /numeric/)
  end

  it "rejects regression values outside the sanity window" do
    values[:valence] = -0.5001

    expect { features }.to raise_error(MoodProbe::MalformedOutputError, /sanity/)
  end

  it "strictly rejects classification values outside 0.0..1.0" do
    values[:danceability] = 1.0001

    expect { features }.to raise_error(MoodProbe::MalformedOutputError, /danceability/)
  end
end
