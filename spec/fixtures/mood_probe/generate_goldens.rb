$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)

require "json"
require "mood_probe"
require "pathname"

fixture_root = Pathname(__dir__)
models_dir = ENV.fetch("MOOD_PROBE_MODELS_DIR", File.expand_path("~/.cache/mood_probe/models"))
extractor = MoodProbe::Extractor.new(
  models_dir:,
  python_executable: ENV.fetch("MOOD_PROBE_PYTHON", "python3")
)

%w[chirp clicks sine_440 white_noise].each do |name|
  features = extractor.analyze(fixture_root.join("audio/#{name}.wav"))
  fixture_root.join("golden/#{name}.json").write("#{JSON.pretty_generate(features.to_h)}\n")
end
