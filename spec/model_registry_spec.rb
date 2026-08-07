RSpec.describe MoodProbe::ModelRegistry do
  it "records all six models with inference and provenance metadata" do
    models = described_class.models

    expect(models.length).to eq(6)
    expect(models.map(&:filename)).to contain_exactly(
      "msd-musicnn-1.pb",
      "danceability-msd-musicnn-1.pb",
      "mood_acoustic-msd-musicnn-1.pb",
      "mood_relaxed-msd-musicnn-1.pb",
      "mood_happy-msd-musicnn-1.pb",
      "emomusic-msd-musicnn-2.pb"
    )
    expect(models).to all(
      have_attributes(
        output_node: be_a(String),
        sha256: match(/\A[0-9a-f]{64}\z/),
        source_url: start_with("https://essentia.upf.edu/")
      )
    )
  end
end
