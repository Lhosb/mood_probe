RSpec.describe "mood_probe v0.1.0 algebraic parity" do
  let(:fixture_root) { Pathname(__dir__).join("fixtures/mood_probe") }
  let(:baseline_dir) { fixture_root.join("baseline_v0_1_0") }
  let(:golden_dir) { fixture_root.join("golden") }
  let(:head_mapping) do
    {
      "danceability" => "danceability",
      "mood_acoustic" => "mood_acoustic",
      "mood_relaxed" => "mood_relaxed",
      "mood_happy" => "mood_happy",
      "valence" => "valence_emomusic",
      "arousal" => "arousal_emomusic"
    }
  end

  it "preserves the frozen public values through the native-value goldens" do
    %w[chirp clicks sine_440 white_noise].each do |name|
      baseline = JSON.parse(baseline_dir.join("#{name}.json").read)
      golden = JSON.parse(golden_dir.join("#{name}.json").read)

      head_mapping.each do |baseline_head, golden_head|
        expected = baseline.fetch(baseline_head)
        raw = golden.fetch(golden_head)
        actual = %w[valence arousal].include?(baseline_head) ? (raw - 1.0) / 8.0 : raw
        tolerance = [1e-4 * expected.abs, 1e-10].max

        expect(actual).to be_within(tolerance).of(expected),
                          "#{name}.json #{baseline_head} drifted"
      end
    end
  end
end
