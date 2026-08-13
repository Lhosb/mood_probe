RSpec.describe Sonance::Registry do
  # rubocop:disable Naming/VariableNumber
  subject(:registry) { described_class.default }

  it "indexes unique model and descriptor ids" do
    model = registry.models.first
    descriptor = registry.descriptors.first
    custom_registry = described_class.new(models: [model], descriptors: [descriptor])

    expect(custom_registry.model(model.id)).to equal(model)
    expect(custom_registry.fetch(descriptor.id)).to equal(descriptor)
  end

  it "rejects duplicate descriptor ids" do
    descriptor = registry.descriptors.first

    expect { described_class.new(models: [], descriptors: [descriptor, descriptor]) }
      .to raise_error(ArgumentError, /duplicate descriptor id: #{descriptor.id}/)
  end

  it "rejects duplicate model ids" do
    model = registry.models.first

    expect { described_class.new(models: [model, model], descriptors: []) }
      .to raise_error(ArgumentError, /duplicate model id: #{model.id}/)
  end

  it "registers the six current descriptors plus embedding and rhythm descriptors" do
    expect(registry.ids).to eq(
      %i[
        valence_emomusic
        arousal_emomusic
        danceability_musicnn
        mood_acoustic_musicnn
        mood_relaxed_musicnn
        mood_happy_musicnn
        embedding_musicnn
        bpm_rhythm2013
        beat_confidence_rhythm2013
      ]
    )
  end

  it "accepts String descriptor ids" do
    expect(registry.fetch("bpm_rhythm2013")).to equal(registry.fetch(:bpm_rhythm2013))
  end

  it "raises a gem configuration error for an unknown descriptor id" do
    expect { registry.fetch("tempo") }
      .to raise_error(
        Sonance::ConfigurationError,
        /unknown descriptor: tempo.*valid descriptors:.*\bbpm_rhythm2013\b/
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
    descriptor = registry.fetch(:mood_happy_musicnn)

    expect { model.filename << ".tampered" }.to raise_error(FrozenError)
    expect { model.classes.first << "_tampered" }.to raise_error(FrozenError)
    expect { descriptor.produced_by.select.fetch(:class) << "_tampered" }
      .to raise_error(FrozenError)
    expect { descriptor.notes << " tampered" }.to raise_error(FrozenError)
  end

  it "does not attach classification labels to the MusiCNN embedding output" do
    expect(registry.model(:msd_musicnn_1).classes).to be_nil
  end

  it "pins current head classes and their name-based selectors pending the Phase B upstream JSON gate" do
    expectations = {
      danceability_musicnn: [%w[danceable not_danceable], "danceable"],
      mood_acoustic_musicnn: [%w[acoustic non_acoustic], "acoustic"],
      mood_relaxed_musicnn: [%w[non_relaxed relaxed], "relaxed"],
      mood_happy_musicnn: [%w[happy non_happy], "happy"],
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
    expect(defined?(Sonance::ModelRegistry)).to be_nil
  end

  it "declares the required ranges and sanity ranges" do
    %i[valence_emomusic arousal_emomusic].each do |id|
      expect(registry.fetch(id)).to have_attributes(
        native_range: (1.0..9.0),
        range_kind: :nominal,
        sanity_range: (-3.0..13.0)
      )
    end

    %i[danceability_musicnn mood_acoustic_musicnn mood_relaxed_musicnn mood_happy_musicnn].each do |id|
      expect(registry.fetch(id)).to have_attributes(
        native_range: (0.0..1.0),
        range_kind: :hard,
        sanity_range: (0.0..1.0)
      )
    end
  end

  it "raises when a hard descriptor has different native and sanity ranges" do
    expect do
      Sonance::Descriptor.new(
        id: :invalid,
        kind: :scalar,
        produced_by: Sonance::FromAlgorithm.new(
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
    expect(registry.descriptors).not_to be_empty
    expect(registry.descriptors.map(&:produced_by))
      .to all(be_a(Sonance::FromModel).or(be_a(Sonance::FromAlgorithm)))
  end

  it "defines Series without registering any series descriptor" do
    expect(Sonance::Series).to be_a(Class)
    expect(registry.descriptors).not_to be_empty
    expect(registry.descriptors).not_to include(have_attributes(kind: :series))
  end

  describe Sonance::Model do
    subject(:model) { Sonance::Registry.default.model(:mood_happy_msd_musicnn_1) }

    it "accepts the valid default model metadata" do
      expect(model.filename).to eq("mood_happy-msd-musicnn-1.pb")
      expect(model.source_url).to start_with("https://essentia.upf.edu/")
    end

    {
      "../escaped.pb" => /bare \.pb basename/,
      "/absolute.pb" => /bare \.pb basename/,
      "nested/model.pb" => /bare \.pb basename/,
      "..pb" => /bare \.pb basename/,
      "model.bin" => /bare \.pb basename/
    }.each do |filename, message|
      it "rejects unsafe filename #{filename.inspect}" do
        expect { model.with(filename:) }.to raise_error(ArgumentError, message)
      end
    end

    it "rejects non-HTTPS model sources" do
      expect { model.with(source_url: "http://essentia.upf.edu/model.pb") }
        .to raise_error(ArgumentError, /HTTPS/)
      expect { model.with(source_url: :"https://essentia.upf.edu/model.pb") }
        .to raise_error(ArgumentError, /String/)
    end

    it "accepts HTTPS model sources outside the download allowlist" do
      expect(model.with(source_url: "https://models.example.test/model.pb").source_url)
        .to eq("https://models.example.test/model.pb")
    end

    it "requires a SHA-256 digest and positive byte length" do
      expect { model.with(sha256: nil) }.to raise_error(ArgumentError, /sha256/)
      expect { model.with(sha256: "A" * 64) }.to raise_error(ArgumentError, /sha256/)
      expect { model.with(sha256: "a" * 63) }.to raise_error(ArgumentError, /sha256/)
      expect { model.with(sha256: ("a" * 64).to_sym) }
        .to raise_error(ArgumentError, /sha256.*String/)
      expect { model.with(byte_length: nil) }.to raise_error(ArgumentError, /byte_length/)
      expect { model.with(byte_length: 0) }.to raise_error(ArgumentError, /byte_length/)
      expect { model.with(byte_length: -1) }.to raise_error(ArgumentError, /byte_length/)
      expect { model.with(byte_length: 1.5) }.to raise_error(ArgumentError, /byte_length/)
    end
  end
  # rubocop:enable Naming/VariableNumber
end
