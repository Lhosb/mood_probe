RSpec.describe "real Python to Ruby Features seam" do
  let(:root) { Pathname(__dir__).join("../..").expand_path }
  let(:model_store) { instance_double(MoodProbe::ModelStore, verify!: true) }

  around do |example|
    original = ENV.fetch("PYTHONPATH", nil)
    ENV["PYTHONPATH"] = root.join("spec/support/fake_essentia").to_s
    example.run
  ensure
    ENV["PYTHONPATH"] = original
  end

  it "produces the six documented floats end to end" do
    backend = MoodProbe::Backends::EssentiaPython.new(models_dir: "/models", model_store:)
    extractor = MoodProbe::Extractor.new(models_dir: "/models", backend:)

    result = extractor.analyze_all(["good-1.wav"]).first

    expect(result).to be_ok
    expect(result.features.to_h).to eq(
      valence: 0.4,
      arousal: 0.6,
      danceability: 0.7,
      mood_acoustic: 0.2,
      mood_relaxed: 0.8,
      mood_happy: 0.5
    )
  end

  it "keeps real Python inference failures positionally aligned" do
    backend = MoodProbe::Backends::EssentiaPython.new(models_dir: "/models", model_store:)
    extractor = MoodProbe::Extractor.new(models_dir: "/models", backend:)

    results = extractor.analyze_all(%w[good-1.wav crash.wav good-2.wav])

    expect(results.map(&:ok?)).to eq([true, false, true])
    expect(results[1].error).to be_a(MoodProbe::InferenceError)
    expect(results.values_at(0, 2).map { |result| result.features.to_h[:valence] }).to eq([0.4, 0.4])
  end
end
