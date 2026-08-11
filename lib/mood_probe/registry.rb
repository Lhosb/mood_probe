module MoodProbe
  Model = Data.define(
    :id,
    :filename,
    :sha256,
    :source_url,
    :byte_length,
    :license,
    :attribution,
    :pack,
    :model_version,
    :framework,
    :sample_rate,
    :algorithm,
    :input_node,
    :output_node,
    :classes,
    :reduction,
    :embedding
  )

  FromModel = Data.define(:model, :select)
  FromAlgorithm = Data.define(:name, :output, :params, :sample_rate)

  Descriptor = Data.define(
    :id,
    :kind,
    :produced_by,
    :native_range,
    :range_kind,
    :sanity_range,
    :units,
    :shape,
    :notes
  ) do
    def initialize(**attributes)
      super
      return unless range_kind == :hard && sanity_range != native_range

      raise ArgumentError, "hard descriptor native and sanity ranges must match"
    end
  end

  # The default manifest is deliberately literal so upstream model facts remain reviewable together.
  # rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Naming/VariableNumber
  class Registry
    ATTRIBUTION = "Music Technology Group, Universitat Pompeu Fabra — https://essentia.upf.edu/models/".freeze
    LICENSE = "CC-BY-NC-ND-4.0".freeze

    class << self
      def default
        @default ||= new(models: default_models, descriptors: default_descriptors).freeze
      end

      private

      def default_models
        [
          model(
            id: :msd_musicnn_1,
            filename: "msd-musicnn-1.pb",
            sha256: "cdea0722bcee7f731286843f2233e3aa69887bb5c3e2dce011eff55f38d04f3e",
            source_url: "https://essentia.upf.edu/models/feature-extractors/musicnn/msd-musicnn-1.pb",
            byte_length: 3_197_999,
            model_version: "1",
            framework: "tensorflow-1.15.0",
            algorithm: :tensorflow_predict_musicnn,
            input_node: "model/Placeholder",
            output_node: "model/dense/BiasAdd",
            classes: [
              "rock", "pop", "alternative", "indie", "electronic", "female vocalists", "dance",
              "00s", "alternative rock", "jazz", "beautiful", "metal", "chillout",
              "male vocalists", "classic rock", "soul", "indie rock", "Mellow", "electronica",
              "80s", "folk", "90s", "chill", "instrumental", "punk", "oldies", "blues",
              "hard rock", "ambient", "acoustic", "experimental", "female vocalist", "guitar",
              "Hip-Hop", "70s", "party", "country", "easy listening", "sexy", "catchy", "funk",
              "electro", "heavy metal", "Progressive rock", "60s", "rnb", "indie pop", "sad",
              "House", "happy"
            ],
            embedding: nil
          ),
          model(
            id: :danceability_msd_musicnn_1,
            filename: "danceability-msd-musicnn-1.pb",
            sha256: "874a4b86afc9e12de3f15a47baf9ff1ac676ace109c56203e26103f2259eb95e",
            source_url: "https://essentia.upf.edu/models/classification-heads/danceability/" \
                        "danceability-msd-musicnn-1.pb",
            byte_length: 82_458,
            model_version: "2",
            framework: "tensorflow-2.4.0",
            algorithm: :tensorflow_predict_2d,
            input_node: "model/Placeholder",
            output_node: "model/Softmax",
            classes: %w[danceable not_danceable],
            embedding: :msd_musicnn_1
          ),
          model(
            id: :mood_acoustic_msd_musicnn_1,
            filename: "mood_acoustic-msd-musicnn-1.pb",
            sha256: "519ee3af8210fe32e021002a0094546aeb6fb5a59d22b7d53c48e4ee1ac9e6cc",
            source_url: "https://essentia.upf.edu/models/classification-heads/mood_acoustic/" \
                        "mood_acoustic-msd-musicnn-1.pb",
            byte_length: 82_458,
            model_version: "2",
            framework: "tensorflow-2.4.0",
            algorithm: :tensorflow_predict_2d,
            input_node: "model/Placeholder",
            output_node: "model/Softmax",
            classes: %w[acoustic non_acoustic],
            embedding: :msd_musicnn_1
          ),
          model(
            id: :mood_relaxed_msd_musicnn_1,
            filename: "mood_relaxed-msd-musicnn-1.pb",
            sha256: "1252d28ca7d2204e34e0cdf84a00aa2bc9627a87bdcf923df3aad39cfa69d2d9",
            source_url: "https://essentia.upf.edu/models/classification-heads/mood_relaxed/" \
                        "mood_relaxed-msd-musicnn-1.pb",
            byte_length: 82_458,
            model_version: "2",
            framework: "tensorflow-2.4.0",
            algorithm: :tensorflow_predict_2d,
            input_node: "model/Placeholder",
            output_node: "model/Softmax",
            classes: %w[non_relaxed relaxed],
            embedding: :msd_musicnn_1
          ),
          model(
            id: :mood_happy_msd_musicnn_1,
            filename: "mood_happy-msd-musicnn-1.pb",
            sha256: "d7382bc60304ea4578c298222968cd8d600c31252c7bf3e90b1f728ebb3ec36d",
            source_url: "https://essentia.upf.edu/models/classification-heads/mood_happy/" \
                        "mood_happy-msd-musicnn-1.pb",
            byte_length: 82_458,
            model_version: "2",
            framework: "tensorflow-2.4.0",
            algorithm: :tensorflow_predict_2d,
            input_node: "model/Placeholder",
            output_node: "model/Softmax",
            classes: %w[happy non_happy],
            embedding: :msd_musicnn_1
          ),
          model(
            id: :emomusic_msd_musicnn_2,
            filename: "emomusic-msd-musicnn-2.pb",
            sha256: "fcfb486510213b35e0a691975325f58170f648ad4a02d749bce790da13ded43b",
            source_url: "https://essentia.upf.edu/models/classification-heads/emomusic/" \
                        "emomusic-msd-musicnn-2.pb",
            byte_length: 82_460,
            model_version: "2",
            framework: "tensorflow-2.6.0",
            algorithm: :tensorflow_predict_2d,
            input_node: "model/Placeholder",
            output_node: "model/Identity",
            classes: %w[valence arousal],
            embedding: :msd_musicnn_1
          )
        ].freeze
      end

      def model(**attributes)
        Model.new(
          **attributes,
          license: LICENSE,
          attribution: ATTRIBUTION,
          pack: :core_musicnn,
          sample_rate: 16_000,
          reduction: :mean_over_frames,
          classes: attributes[:classes]&.freeze
        )
      end

      def default_descriptors
        [
          emomusic_descriptor(:valence_emomusic, "valence"),
          emomusic_descriptor(:arousal_emomusic, "arousal"),
          probability_descriptor(
            :danceability,
            :danceability_msd_musicnn_1,
            "danceable"
          ),
          probability_descriptor(
            :mood_acoustic,
            :mood_acoustic_msd_musicnn_1,
            "acoustic"
          ),
          probability_descriptor(
            :mood_relaxed,
            :mood_relaxed_msd_musicnn_1,
            "relaxed"
          ),
          probability_descriptor(
            :mood_happy,
            :mood_happy_msd_musicnn_1,
            "happy"
          ),
          Descriptor.new(
            id: :musicnn_embedding,
            kind: :vector,
            produced_by: FromModel.new(model: :msd_musicnn_1, select: nil),
            native_range: nil,
            range_kind: :unbounded,
            sanity_range: nil,
            units: nil,
            shape: 200,
            notes: "Penultimate-layer MSD MusiCNN embedding."
          ),
          rhythm_descriptor(:bpm, "bpm", :bpm),
          rhythm_descriptor(:beat_confidence, "confidence", :unitless)
        ].freeze
      end

      def emomusic_descriptor(id, selected_class)
        Descriptor.new(
          id:,
          kind: :scalar,
          produced_by: FromModel.new(
            model: :emomusic_msd_musicnn_2,
            select: { class: selected_class }.freeze
          ),
          native_range: (1.0..9.0),
          range_kind: :nominal,
          sanity_range: (-3.0..13.0),
          units: :unitless,
          shape: nil,
          notes: "Native emoMusic arousal-valence output."
        )
      end

      def probability_descriptor(id, model_id, selected_class)
        Descriptor.new(
          id:,
          kind: :scalar,
          produced_by: FromModel.new(
            model: model_id,
            select: { class: selected_class }.freeze
          ),
          native_range: (0.0..1.0),
          range_kind: :hard,
          sanity_range: (0.0..1.0),
          units: :probability,
          shape: nil,
          notes: "Mean-reduced frame-wise softmax probability."
        )
      end

      def rhythm_descriptor(id, output, units)
        Descriptor.new(
          id:,
          kind: :scalar,
          produced_by: FromAlgorithm.new(
            name: "RhythmExtractor2013",
            output:,
            params: { method: "multifeature" }.freeze,
            sample_rate: 44_100
          ),
          native_range: nil,
          range_kind: :unbounded,
          sanity_range: nil,
          units:,
          shape: nil,
          notes: "Essentia RhythmExtractor2013 #{output} output."
        )
      end
      # rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Naming/VariableNumber
    end

    attr_reader :models, :descriptors

    def initialize(models:, descriptors:)
      @models = deep_freeze(models.dup)
      @descriptors = deep_freeze(descriptors.dup)
      @models_by_id = models.to_h { |model| [model.id, model] }.freeze
      @descriptors_by_id = descriptors.to_h { |descriptor| [descriptor.id, descriptor] }.freeze
    end

    def ids
      descriptors.map(&:id)
    end

    def fetch(id)
      @descriptors_by_id.fetch(id.to_sym)
    end

    def model(id)
      @models_by_id.fetch(id.to_sym)
    end

    private

    def deep_freeze(value)
      case value
      when Array
        value.each { |item| deep_freeze(item) }
      when Hash
        value.each do |key, item|
          deep_freeze(key)
          deep_freeze(item)
        end
      when Data
        value.to_h.each_value { |item| deep_freeze(item) }
      end
      value.freeze
    end
  end
end
