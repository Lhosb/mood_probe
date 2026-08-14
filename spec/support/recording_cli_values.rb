require "sonance"

# The payload table used by the CLI recording stub, kept separate from the stub itself so a
# spec can assert its coverage without loading `recording_cli_analyze.rb`. That file
# monkey-patches `Sonance::Extractor` for the CLI subprocess; requiring it inside the main
# RSpec process would clobber the extractor for every other spec.
module RecordingCliValues
  # Deterministic, distinct, and inside each descriptor's declared range so `Value`
  # construction exercises its real validations. Distinct values let the spec detect a
  # descriptor mix-up, which a shared placeholder would hide.
  RAW_VALUES = {
    valence_emomusic: 4.5,
    arousal_emomusic: 6.25,
    danceability_musicnn: 0.75,
    mood_acoustic_musicnn: 0.125,
    mood_relaxed_musicnn: 0.5,
    mood_happy_musicnn: 0.875,
    embedding_musicnn: Array.new(200) { |index| (index + 1) / 1000.0 }.freeze,
    bpm_rhythm2013: 123.5,
    beat_confidence_rhythm2013: 3.25
  }.freeze

  def self.fetch(id)
    RAW_VALUES.fetch(id) { raise KeyError, "recording stub has no payload for #{id}" }
  end
end
