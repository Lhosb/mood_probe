RSpec.describe "committed golden fixtures" do
  let(:fixture_root) { Pathname(__dir__).join("fixtures/mood_probe") }
  let(:descriptor_ids) do
    %w[
      valence_emomusic
      arousal_emomusic
      danceability_musicnn
      mood_acoustic_musicnn
      mood_relaxed_musicnn
      mood_happy_musicnn
    ]
  end

  it "owns all audio and golden files needed by the Docker parity gate" do
    names = %w[chirp clicks sine_440 white_noise]

    expect(names.map { |name| fixture_root.join("audio/#{name}.wav") }).to all(exist)
    expect(fixture_root.join("audio/undecodable.m4a")).to exist
    names.each do |name|
      payload = JSON.parse(fixture_root.join("golden/#{name}.json").read)
      expect(payload.keys.sort).to eq(descriptor_ids.sort)
    end
  end
end
