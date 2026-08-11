RSpec.describe "real Python to Ruby legacy protocol seam" do
  let(:root) { Pathname(__dir__).join("../..").expand_path }
  let(:backend) { MoodProbe::Backends::EssentiaPython.new(models_dir: "/models") }
  let(:plan) do
    MoodProbe::Planner.new(registry: MoodProbe::Registry.default)
                      .plan_for(descriptors: [:mood_happy])
  end

  around do |example|
    original = ENV.fetch("PYTHONPATH", nil)
    ENV["PYTHONPATH"] = root.join("spec/support/fake_essentia").to_s
    example.run
  ensure
    ENV["PYTHONPATH"] = original
  end

  it "parses the six current floats without changing the Python script" do
    expect(backend.analyze("good-1.wav", plan:)).to eq(
      "valence" => 0.4,
      "arousal" => 0.6,
      "danceability" => 0.7,
      "mood_acoustic" => 0.2,
      "mood_relaxed" => 0.8,
      "mood_happy" => 0.5
    )
  end

  it "keeps inference failures isolated between real subprocess calls" do
    outcomes = %w[good-1.wav crash.wav good-2.wav].map do |path|
      backend.analyze(path, plan:)
    end

    expect(outcomes[1]).to be_a(MoodProbe::InferenceError)
    expect(outcomes.values_at(0, 2).map { |outcome| outcome.fetch("valence") })
      .to eq([0.4, 0.4])
  end

  it "keeps non-finite failures isolated between real subprocess calls" do
    outcomes = %w[good-1.wav nan-audio.wav good-2.wav infinity-audio.wav].map do |path|
      backend.analyze(path, plan:)
    end

    expect(outcomes.values_at(1, 3)).to all(be_a(MoodProbe::MalformedOutputError))
    expect(outcomes.values_at(0, 2).map { |outcome| outcome.fetch("valence") })
      .to eq([0.4, 0.4])
  end
end
