$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)

require "json"
require "mood_probe"
require "pathname"
require_relative "../../support/canonical_essentia_environment"

CanonicalEssentiaEnvironment.verify!

fixture_root = Pathname(__dir__)
models_dir = ENV.fetch("MOOD_PROBE_MODELS_DIR", File.expand_path("~/.cache/mood_probe/models"))
extractor = MoodProbe::Extractor.new(
  models_dir:,
  python_executable: ENV.fetch("MOOD_PROBE_PYTHON", "python3")
)

descriptors = %i[
  valence_emomusic
  arousal_emomusic
  danceability_musicnn
  mood_acoustic_musicnn
  mood_relaxed_musicnn
  mood_happy_musicnn
]

%w[chirp clicks sine_440 white_noise].each do |name|
  analysis = extractor.analyze(
    fixture_root.join("audio/#{name}.wav"),
    descriptors:
  )
  values = analysis.to_h.transform_values(&:value)
  fixture_root.join("golden/#{name}.json").write("#{JSON.pretty_generate(values)}\n")
end
