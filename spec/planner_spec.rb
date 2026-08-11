RSpec.describe MoodProbe::Planner do
  subject(:planner) { described_class.new(registry: MoodProbe::Registry.default) }

  fixture_root = Pathname(__dir__).join("fixtures/mood_probe/plans")

  {
    "musicnn_only" => %i[mood_happy],
    "algorithm_only" => %i[bpm],
    "mixed" => %i[bpm mood_happy]
  }.each do |fixture_name, descriptors|
    it "matches the committed #{fixture_name} plan fixture" do
      expected = JSON.parse(
        fixture_root.join("#{fixture_name}.json").read,
        symbolize_names: true
      )

      expect(planner.plan_for(descriptors:).to_h).to eq(expected)
    end
  end

  it "omits model graphs for an algorithm-only request" do
    expect(planner.plan_for(descriptors: [:bpm]).graphs).to be_empty
  end

  it "resolves the inverted relaxed class by name" do
    plan = planner.plan_for(descriptors: [:mood_relaxed])

    expect(plan.emit.fetch(0).fetch(:take)).to eq(index: 1)
  end

  it "loads model and algorithm sample rates in dependency order" do
    plan = planner.plan_for(descriptors: %i[bpm mood_happy])

    expect(plan.loads.map { |load| load.fetch(:sample_rate) }).to eq([16_000, 44_100])
  end

  it "lists only files required by the requested descriptors" do
    expect(planner.plan_for(descriptors: [:bpm]).required_files).to eq([])
    expect(planner.plan_for(descriptors: [:mood_happy]).required_files).to eq(
      ["msd-musicnn-1.pb", "mood_happy-msd-musicnn-1.pb"]
    )
  end
end
