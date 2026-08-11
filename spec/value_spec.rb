RSpec.describe "MoodProbe typed values" do
  let(:registry) { MoodProbe::Registry.default }
  let(:provenance) do
    MoodProbe::Provenance.new(
      source: :model,
      model_filename: "mood_happy-msd-musicnn-1.pb",
      model_version: "2",
      model_sha256: "a" * 64,
      algorithm: "TensorflowPredict2D",
      reduction: :mean_over_frames,
      essentia_version: "test",
      gem_version: MoodProbe::VERSION
    )
  end

  describe MoodProbe::Scalar do
    it "exposes descriptor metadata with a finite scalar value" do
      value = described_class.new(
        descriptor: registry.fetch(:mood_happy),
        provenance:,
        value: 0.75
      )

      expect(value).to have_attributes(
        id: :mood_happy,
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
          descriptor: registry.fetch(:mood_happy),
          provenance:,
          value: "0.75"
        )
      end.to raise_error(MoodProbe::SchemaError, /mood_happy.*numeric/)
    end

    it "enforces the descriptor sanity range" do
      expect do
        described_class.new(
          descriptor: registry.fetch(:valence_emomusic),
          provenance:,
          value: 13.1
        )
      end.to raise_error(MoodProbe::MalformedOutputError, /valence_emomusic.*-3.0.*13.0/)
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
        descriptor: registry.fetch(:danceability),
        provenance:,
        value: 1.0
      )

      expect(accepted.value).to eq(1.0)
      expect do
        described_class.new(
          descriptor: registry.fetch(:danceability),
          provenance:,
          value: 1.0001
        )
      end.to raise_error(MoodProbe::MalformedOutputError, /danceability.*0.0.*1.0/)
    end

    it "normalizes an integer scalar to Float" do
      value = described_class.new(
        descriptor: registry.fetch(:danceability),
        provenance:,
        value: 1
      )

      expect(value.value).to eql(1.0)
    end
  end

  describe MoodProbe::Vector do
    it "accepts a 200-float MusiCNN embedding" do
      value = described_class.new(
        descriptor: registry.fetch(:musicnn_embedding),
        provenance:,
        values: Array.new(200, 0.25)
      )

      expect(value.id).to eq(:musicnn_embedding)
      expect(value.values.length).to eq(200)
    end

    it "rejects a wrong-length MusiCNN embedding with both lengths in the error" do
      expect do
        described_class.new(
          descriptor: registry.fetch(:musicnn_embedding),
          provenance:,
          values: Array.new(199, 0.25)
        )
      end.to raise_error(
        MoodProbe::MalformedOutputError,
        /musicnn_embedding.*expected 200.*got 199/
      )
    end
  end

  describe MoodProbe::Analysis do
    it "preserves request order and raises for an unrequested descriptor" do
      happy = MoodProbe::Scalar.new(
        descriptor: registry.fetch(:mood_happy),
        provenance:,
        value: 0.75
      )
      bpm = MoodProbe::Scalar.new(
        descriptor: registry.fetch(:bpm),
        provenance:,
        value: 120.0
      )
      analysis = described_class.new(mood_happy: happy, bpm:)

      expect(analysis.keys).to eq(%i[mood_happy bpm])
      expect(analysis[:bpm]).to equal(bpm)
      expect(analysis.to_h).to eq(mood_happy: happy, bpm:)
      expect { analysis[:arousal_emomusic] }.to raise_error(KeyError)
    end

    describe MoodProbe::AnalysisBuilder do
      it "normalizes string descriptor keys from Python output" do
        analysis = described_class.new(registry:).call(
          requested: [:mood_happy],
          raw_values: { "mood_happy" => 0.5 }
        )

        expect(analysis.keys).to eq([:mood_happy])
        expect(analysis[:mood_happy].value).to eq(0.5)
      end
    end
  end

  it "defines categorical and series values without registry series rows" do
    expect(MoodProbe::Categorical).to be < MoodProbe::Value
    expect(MoodProbe::Series).to be < MoodProbe::Value
  end
end
