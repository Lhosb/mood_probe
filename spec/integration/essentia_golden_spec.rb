RSpec.describe "MoodProbe Essentia goldens", :essentia do
  it "reproduces every Phase 1 golden bit-identically" do
    fixture_root = Pathname(ENV.fetch("MOOD_PROBE_FIXTURE_ROOT"))
    audio_dir = fixture_root.join("audio")
    golden_dir = fixture_root.join("golden")
    extractor = MoodProbe::Extractor.new(
      models_dir: ENV.fetch("MOOD_PROBE_MODELS_DIR"),
      python_executable: ENV.fetch("MOOD_PROBE_PYTHON", "python3")
    )
    names = %w[chirp clicks sine_440 white_noise]

    results = extractor.analyze_all(names.map { |name| audio_dir.join("#{name}.wav") })

    expect(results).to all(be_ok)
    results.zip(names).each do |result, name|
      expected = JSON.parse(golden_dir.join("#{name}.json").read, symbolize_names: true)
      expect(result.features.to_h).to eq(expected)
    end
  end

  it "returns a TrackError for the Phase 1 undecodable fixture" do
    fixture_root = Pathname(ENV.fetch("MOOD_PROBE_FIXTURE_ROOT"))
    extractor = MoodProbe::Extractor.new(
      models_dir: ENV.fetch("MOOD_PROBE_MODELS_DIR"),
      python_executable: ENV.fetch("MOOD_PROBE_PYTHON", "python3")
    )

    result = extractor.analyze_all([fixture_root.join("audio/undecodable.m4a")]).first

    expect(result).not_to be_ok
    expect(result.error).to be_a(MoodProbe::UnreadableAudioError)
  end
end
