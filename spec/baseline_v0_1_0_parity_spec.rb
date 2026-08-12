RSpec.describe "mood_probe v0.1.0 algebraic parity" do
  let(:fixture_root) { Pathname(__dir__).join("fixtures/mood_probe") }
  let(:baseline_dir) { fixture_root.join("baseline_v0_1_0") }
  let(:golden_dir) { fixture_root.join("golden") }
  let(:softmax_heads) { %w[danceability mood_acoustic mood_relaxed mood_happy] }
  let(:emomusic_heads) do
    {
      "valence" => "valence_emomusic",
      "arousal" => "arousal_emomusic"
    }
  end

  it "preserves the frozen public values through the native-value goldens" do
    %w[chirp clicks sine_440 white_noise].each do |name|
      baseline = JSON.parse(baseline_dir.join("#{name}.json").read)
      golden = JSON.parse(golden_dir.join("#{name}.json").read)

      softmax_heads.each do |head|
        expect(golden.fetch(head)).to eq(baseline.fetch(head)), "#{name}.json #{head} drifted"
      end

      emomusic_heads.each do |baseline_head, golden_head|
        expected = baseline.fetch(baseline_head)
        actual = (golden.fetch(golden_head) - 1.0) / 8.0
        tolerance = [1e-4 * expected.abs, 1e-10].max

        expect(actual).to be_within(tolerance).of(expected),
                          "#{name}.json #{baseline_head} drifted"
      end
    end
  end
end
