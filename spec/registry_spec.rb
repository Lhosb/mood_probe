RSpec.describe MoodProbe::Registry do
  # rubocop:disable Naming/VariableNumber
  subject(:registry) { described_class.default }

  it "registers the six current descriptors plus embedding and rhythm descriptors" do
    expect(registry.ids).to eq(
      %i[
        valence_emomusic
        arousal_emomusic
        danceability
        mood_acoustic
        mood_relaxed
        mood_happy
        musicnn_embedding
        bpm
        beat_confidence
      ]
    )
  end

  it "records complete immutable model metadata" do
    expect(registry.models.length).to eq(6)
    expect(registry.models).to all(
      have_attributes(
        sha256: match(/\A[0-9a-f]{64}\z/),
        byte_length: be_a(Integer),
        license: "CC-BY-NC-ND-4.0",
        attribution: include("Music Technology Group"),
        pack: :core_musicnn,
        model_version: be_a(String),
        reduction: :mean_over_frames
      )
    )
    expect(registry.models.map(&:embedding).compact.uniq).to eq([:msd_musicnn_1])
  end

  it "deep-freezes nested default registry metadata" do
    model = registry.model(:mood_happy_msd_musicnn_1)
    descriptor = registry.fetch(:mood_happy)

    expect { model.filename << ".tampered" }.to raise_error(FrozenError)
    expect { model.classes.first << "_tampered" }.to raise_error(FrozenError)
    expect { descriptor.produced_by.select.fetch(:class) << "_tampered" }
      .to raise_error(FrozenError)
    expect { descriptor.notes << " tampered" }.to raise_error(FrozenError)
  end

  it "transcribes the MusiCNN model classes verbatim even though its descriptor selects the embedding" do
    expect(registry.model(:msd_musicnn_1).classes).to eq(
      [
        "rock", "pop", "alternative", "indie", "electronic", "female vocalists", "dance",
        "00s", "alternative rock", "jazz", "beautiful", "metal", "chillout",
        "male vocalists", "classic rock", "soul", "indie rock", "Mellow", "electronica",
        "80s", "folk", "90s", "chill", "instrumental", "punk", "oldies", "blues",
        "hard rock", "ambient", "acoustic", "experimental", "female vocalist", "guitar",
        "Hip-Hop", "70s", "party", "country", "easy listening", "sexy", "catchy", "funk",
        "electro", "heavy metal", "Progressive rock", "60s", "rnb", "indie pop", "sad",
        "House", "happy"
      ]
    )
  end

  it "transcribes upstream classes verbatim and selects scalar projections by class name" do
    expectations = {
      danceability: [%w[danceable not_danceable], "danceable"],
      mood_acoustic: [%w[acoustic non_acoustic], "acoustic"],
      mood_relaxed: [%w[non_relaxed relaxed], "relaxed"],
      mood_happy: [%w[happy non_happy], "happy"],
      valence_emomusic: [%w[valence arousal], "valence"],
      arousal_emomusic: [%w[valence arousal], "arousal"]
    }

    expectations.each do |descriptor_id, (classes, selected_class)|
      descriptor = registry.fetch(descriptor_id)
      model = registry.model(descriptor.produced_by.model)

      expect(model.classes).to eq(classes)
      expect(descriptor.produced_by.select).to eq(class: selected_class)
    end
  end

  it "does not retain the legacy positive-index registry" do
    expect(defined?(MoodProbe::ModelRegistry)).to be_nil
  end

  it "declares the required ranges and sanity ranges" do
    %i[valence_emomusic arousal_emomusic].each do |id|
      expect(registry.fetch(id)).to have_attributes(
        native_range: (1.0..9.0),
        range_kind: :nominal,
        sanity_range: (-3.0..13.0)
      )
    end

    %i[danceability mood_acoustic mood_relaxed mood_happy].each do |id|
      expect(registry.fetch(id)).to have_attributes(
        native_range: (0.0..1.0),
        range_kind: :hard,
        sanity_range: (0.0..1.0)
      )
    end
  end

  it "raises when a hard descriptor has different native and sanity ranges" do
    expect do
      MoodProbe::Descriptor.new(
        id: :invalid,
        kind: :scalar,
        produced_by: MoodProbe::FromAlgorithm.new(
          name: "Example",
          output: "value",
          params: {},
          sample_rate: 16_000
        ),
        native_range: (0.0..1.0),
        range_kind: :hard,
        sanity_range: (-1.0..1.0),
        units: :unitless,
        shape: nil,
        notes: ""
      )
    end.to raise_error(ArgumentError, /hard.*ranges must match/i)
  end

  it "is fully introspectable without constructing Python, Essentia, or a model store" do
    expect(registry.models.map(&:filename)).to contain_exactly(
      "msd-musicnn-1.pb",
      "danceability-msd-musicnn-1.pb",
      "mood_acoustic-msd-musicnn-1.pb",
      "mood_relaxed-msd-musicnn-1.pb",
      "mood_happy-msd-musicnn-1.pb",
      "emomusic-msd-musicnn-2.pb"
    )
    expect(registry.descriptors.map(&:produced_by))
      .to all(be_a(MoodProbe::FromModel).or(be_a(MoodProbe::FromAlgorithm)))
  end

  it "defines Series without registering any series descriptor" do
    expect(MoodProbe::Series).to be_a(Class)
    expect(registry.descriptors).not_to include(have_attributes(kind: :series))
  end
  # rubocop:enable Naming/VariableNumber
end
