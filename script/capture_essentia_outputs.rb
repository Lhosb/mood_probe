require "json"
require "mood_probe"
require "pathname"
require_relative "../spec/support/canonical_essentia_environment"

CanonicalEssentiaEnvironment.verify!

root = Pathname(__dir__).join("..").expand_path
audio_dir = root.join("spec/fixtures/mood_probe/audio")
actual_dir = Pathname(ARGV.fetch(0)).expand_path
models_dir = ENV.fetch("MOOD_PROBE_MODELS_DIR")
descriptors = %i[
  valence_emomusic
  arousal_emomusic
  danceability
  mood_acoustic
  mood_relaxed
  mood_happy
]
names = %w[chirp clicks sine_440 white_noise]
extractor = MoodProbe::Extractor.new(models_dir:)

actual_dir.mkpath
results = extractor.analyze_all(
  names.map { |name| audio_dir.join("#{name}.wav") },
  descriptors:
)
results.zip(names).each do |result, name|
  raise result.error unless result.ok?

  values = result.analysis.to_h.transform_values(&:value)
  actual_dir.join("#{name}.json").write("#{JSON.pretty_generate(values)}\n")
end

undecodable = extractor.analyze_all(
  [audio_dir.join("undecodable.m4a")],
  descriptors:
).first
undecodable_payload =
  if undecodable.ok?
    { ok: true }
  else
    { ok: false, error_class: undecodable.error.class.name }
  end
actual_dir.join("undecodable.json").write("#{JSON.generate(undecodable_payload)}\n")
