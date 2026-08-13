RSpec.describe "Sonance typed values" do
  let(:registry) { Sonance::Registry.default }
  let(:provenance) do
    Sonance::Provenance.new(
      source: :model,
      model_filename: "mood_happy-msd-musicnn-1.pb",
      model_version: "2",
      model_sha256: "a" * 64,
      algorithm: "TensorflowPredict2D",
      reduction: :mean_over_frames,
      essentia_version: "test",
      gem_version: Sonance::VERSION
    )
  end

  describe Sonance::Scalar do
    it "exposes descriptor metadata with a finite scalar value" do
      value = described_class.new(
        descriptor: registry.fetch(:mood_happy_musicnn),
        provenance:,
        value: 0.75
      )

      expect(value).to have_attributes(
        id: :mood_happy_musicnn,
        kind: :scalar,
        native_range: (0.0..1.0),
        range_kind: :hard,
        units: :probability,
        value: 0.75
      )
    end

    it "rejects a wrong value type as schema drift" do
      expect do
        described_class.new(
          descriptor: registry.fetch(:mood_happy_musicnn),
          provenance:,
          value: "0.75"
        )
      end.to raise_error(Sonance::SchemaError, /mood_happy_musicnn.*numeric/)
    end

    it "enforces the descriptor sanity range" do
      expect do
        described_class.new(
          descriptor: registry.fetch(:valence_emomusic),
          provenance:,
          value: 13.1
        )
      end.to raise_error(Sonance::MalformedOutputError, /valence_emomusic.*-3.0.*13.0/)
    end

    it "accepts both inclusive edges of a nominal descriptor sanity range" do
      values = [-3.0, 13.0].map do |edge|
        described_class.new(
          descriptor: registry.fetch(:valence_emomusic),
          provenance:,
          value: edge
        )
      end

      expect(values.map(&:value)).to eq([-3.0, 13.0])
    end

    it "accepts the hard upper edge and rejects a value just beyond it" do
      accepted = described_class.new(
        descriptor: registry.fetch(:danceability_musicnn),
        provenance:,
        value: 1.0
      )

      expect(accepted.value).to eq(1.0)
      expect do
        described_class.new(
          descriptor: registry.fetch(:danceability_musicnn),
          provenance:,
          value: 1.0001
        )
      end.to raise_error(Sonance::MalformedOutputError, /danceability_musicnn.*0.0.*1.0/)
    end

    it "normalizes an integer scalar to Float" do
      value = described_class.new(
        descriptor: registry.fetch(:danceability_musicnn),
        provenance:,
        value: 1
      )

      expect(value.value).to eql(1.0)
    end
  end

  describe Sonance::Vector do
    it "accepts a 200-float MusiCNN embedding" do
      value = described_class.new(
        descriptor: registry.fetch(:embedding_musicnn),
        provenance:,
        values: Array.new(200, 0.25)
      )

      expect(value.id).to eq(:embedding_musicnn)
      expect(value.values.length).to eq(200)
    end

    it "rejects a wrong-length MusiCNN embedding with both lengths in the error" do
      expect do
        described_class.new(
          descriptor: registry.fetch(:embedding_musicnn),
          provenance:,
          values: Array.new(199, 0.25)
        )
      end.to raise_error(
        Sonance::MalformedOutputError,
        /embedding_musicnn.*expected 200.*got 199/
      )
    end
  end

  describe Sonance::Analysis do
    it "preserves request order and raises for an unrequested descriptor" do
      happy = Sonance::Scalar.new(
        descriptor: registry.fetch(:mood_happy_musicnn),
        provenance:,
        value: 0.75
      )
      bpm = Sonance::Scalar.new(
        descriptor: registry.fetch(:bpm_rhythm2013),
        provenance:,
        value: 120.0
      )
      analysis = described_class.new(mood_happy_musicnn: happy, bpm_rhythm2013: bpm)

      expect(analysis.keys).to eq(%i[mood_happy_musicnn bpm_rhythm2013])
      expect(analysis[:bpm_rhythm2013]).to equal(bpm)
      expect(analysis.to_h).to eq(mood_happy_musicnn: happy, bpm_rhythm2013: bpm)
      expect { analysis[:arousal_emomusic] }.to raise_error(KeyError)
    end

    describe Sonance::AnalysisBuilder do
      it "normalizes string descriptor keys from Python output" do
        analysis = described_class.new(registry:).call(
          requested: [:mood_happy_musicnn],
          raw_values: { "mood_happy_musicnn" => 0.5 }
        )

        expect(analysis.keys).to eq([:mood_happy_musicnn])
        expect(analysis[:mood_happy_musicnn].value).to eq(0.5)
      end
    end
  end

  it "defines categorical and series values without registry series rows" do
    expect(Sonance::Categorical).to be < Sonance::Value
    expect(Sonance::Series).to be < Sonance::Value
  end
end
