module MoodProbe
  class ModelRegistry
    Model = Struct.new(
      :filename,
      :output_node,
      :positive_index,
      :sha256,
      :source_url,
      keyword_init: true
    )

    MODELS = [
      Model.new(
        filename: "msd-musicnn-1.pb",
        output_node: "model/dense/BiasAdd",
        positive_index: nil,
        sha256: "cdea0722bcee7f731286843f2233e3aa69887bb5c3e2dce011eff55f38d04f3e",
        source_url: "https://essentia.upf.edu/models/feature-extractors/musicnn/msd-musicnn-1.pb"
      ),
      Model.new(
        filename: "danceability-msd-musicnn-1.pb",
        output_node: "model/Softmax",
        positive_index: 0,
        sha256: "874a4b86afc9e12de3f15a47baf9ff1ac676ace109c56203e26103f2259eb95e",
        source_url: "https://essentia.upf.edu/models/classification-heads/danceability/" \
                    "danceability-msd-musicnn-1.pb"
      ),
      Model.new(
        filename: "mood_acoustic-msd-musicnn-1.pb",
        output_node: "model/Softmax",
        positive_index: 0,
        sha256: "519ee3af8210fe32e021002a0094546aeb6fb5a59d22b7d53c48e4ee1ac9e6cc",
        source_url: "https://essentia.upf.edu/models/classification-heads/mood_acoustic/" \
                    "mood_acoustic-msd-musicnn-1.pb"
      ),
      Model.new(
        filename: "mood_relaxed-msd-musicnn-1.pb",
        output_node: "model/Softmax",
        positive_index: 1,
        sha256: "1252d28ca7d2204e34e0cdf84a00aa2bc9627a87bdcf923df3aad39cfa69d2d9",
        source_url: "https://essentia.upf.edu/models/classification-heads/mood_relaxed/" \
                    "mood_relaxed-msd-musicnn-1.pb"
      ),
      Model.new(
        filename: "mood_happy-msd-musicnn-1.pb",
        output_node: "model/Softmax",
        positive_index: 0,
        sha256: "d7382bc60304ea4578c298222968cd8d600c31252c7bf3e90b1f728ebb3ec36d",
        source_url: "https://essentia.upf.edu/models/classification-heads/mood_happy/" \
                    "mood_happy-msd-musicnn-1.pb"
      ),
      Model.new(
        filename: "emomusic-msd-musicnn-2.pb",
        output_node: "model/Identity",
        positive_index: nil,
        sha256: "fcfb486510213b35e0a691975325f58170f648ad4a02d749bce790da13ded43b",
        source_url: "https://essentia.upf.edu/models/classification-heads/emomusic/" \
                    "emomusic-msd-musicnn-2.pb"
      )
    ].each(&:freeze).freeze

    def self.models
      MODELS
    end
  end
end
