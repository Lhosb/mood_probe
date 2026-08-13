RSpec.describe "real Python to Ruby plan protocol seam" do
  let(:root) { Pathname(__dir__).join("../..").expand_path }
  let(:models_dir) { Pathname(Dir.mktmpdir) }
  let(:backend) { Sonance::Backends::EssentiaPython.new(models_dir:) }
  let(:plan) do
    Sonance::Planner.new(registry: Sonance::Registry.default)
                    .plan_for(
                      descriptors: %i[
                        valence_emomusic
                        arousal_emomusic
                        mood_happy_musicnn
                      ]
                    )
  end

  around do |example|
    original = ENV.fetch("PYTHONPATH", nil)
    ENV["PYTHONPATH"] = root.join("spec/support/fake_essentia").to_s
    plan.required_files.each { |filename| models_dir.join(filename).binwrite("model") }
    example.run
  ensure
    ENV["PYTHONPATH"] = original
    FileUtils.remove_entry(models_dir)
  end

  it "parses requested native descriptor values" do
    expect(backend.analyze("good-1.wav", plan:)).to eq(
      "valence_emomusic" => 4.2,
      "arousal_emomusic" => 5.8,
      "mood_happy_musicnn" => 0.5
    )
  end

  it "keeps inference failures isolated between real subprocess calls" do
    outcomes = %w[good-1.wav crash.wav good-2.wav].map do |path|
      backend.analyze(path, plan:)
    end

    expect(outcomes[1]).to be_a(Sonance::InferenceError)
    expect(outcomes.values_at(0, 2).map { |outcome| outcome.fetch("valence_emomusic") })
      .to eq([4.2, 4.2])
  end

  it "keeps non-finite failures isolated between real subprocess calls" do
    outcomes = %w[good-1.wav nan-audio.wav good-2.wav infinity-audio.wav].map do |path|
      backend.analyze(path, plan:)
    end

    expect(outcomes.values_at(1, 3)).to all(be_a(Sonance::MalformedOutputError))
    expect(outcomes.values_at(0, 2).map { |outcome| outcome.fetch("valence_emomusic") })
      .to eq([4.2, 4.2])
  end
end
