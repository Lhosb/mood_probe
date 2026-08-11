# Run the independently reproducible real-Essentia gate from the gem root:
#   docker build --platform linux/amd64 -f Dockerfile.essentia -t mood-probe-essentia .
#   docker run --rm --platform linux/amd64 --entrypoint bash \
#     -e ESSENTIA_SPECS=1 -e MOOD_PROBE_MODELS_DIR=/tmp/mood_probe_models \
#     mood-probe-essentia \
#     -c 'bundle exec ruby -Ilib exe/mood-probe --models-dir "$MOOD_PROBE_MODELS_DIR" models fetch &&
#         bundle exec rspec spec/integration/essentia_golden_spec.rb --format documentation'
# Goldens record the gem's native descriptor values.
RSpec.describe "MoodProbe Essentia goldens", :essentia do
  let(:root) { Pathname(__dir__).join("../..").expand_path }
  let(:descriptors) do
    %i[
      valence_emomusic
      arousal_emomusic
      danceability
      mood_acoustic
      mood_relaxed
      mood_happy
    ]
  end
  let(:fixture_root) do
    Pathname(ENV.fetch("MOOD_PROBE_FIXTURE_ROOT", root.join("spec/fixtures/mood_probe").to_s))
  end
  let(:models_dir) do
    ENV.fetch("MOOD_PROBE_MODELS_DIR", File.expand_path("~/.cache/mood_probe/models"))
  end
  let(:extractor) do
    MoodProbe::Extractor.new(
      models_dir:,
      python_executable: ENV.fetch("MOOD_PROBE_PYTHON", "python3")
    )
  end

  it "reproduces every native-value golden bit-identically" do
    audio_dir = fixture_root.join("audio")
    golden_dir = fixture_root.join("golden")
    names = %w[chirp clicks sine_440 white_noise]

    results = extractor.analyze_all(
      names.map { |name| audio_dir.join("#{name}.wav") },
      descriptors:
    )

    expect(results).to all(be_ok)
    results.zip(names).each do |result, name|
      expected = JSON.parse(golden_dir.join("#{name}.json").read, symbolize_names: true)
      actual = result.analysis.to_h.transform_values(&:value)
      expect(actual).to eq(expected)
    end
  end

  it "returns a TrackError for the Phase 1 undecodable fixture" do
    result = extractor.analyze_all(
      [fixture_root.join("audio/undecodable.m4a")],
      descriptors:
    ).first

    expect(result).not_to be_ok
    expect(result.error).to be_a(MoodProbe::UnreadableAudioError)
  end
end
