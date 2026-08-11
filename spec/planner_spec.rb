RSpec.describe MoodProbe::Planner do
  subject(:planner) { described_class.new(registry: MoodProbe::Registry.default) }

  fixture_root = Pathname(__dir__).join("fixtures/mood_probe/plans")

  {
    "musicnn_only" => %i[mood_happy],
    "algorithm_only" => %i[bpm],
    "mixed" => %i[bpm mood_happy],
    "emomusic" => %i[valence_emomusic]
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

  it "pins the current inverted relaxed projection pending the Phase B upstream JSON gate" do
    plan = planner.plan_for(descriptors: [:mood_relaxed])

    expect(plan.emit.fetch(0).fetch(:take)).to eq(index: 1)
  end

  # rubocop:disable Naming/VariableNumber
  it "rejects class projection from the MusiCNN embedding output" do
    descriptor = MoodProbe::Descriptor.new(
      id: :invalid_musicnn_class,
      kind: :scalar,
      produced_by: MoodProbe::FromModel.new(
        model: :msd_musicnn_1,
        select: { class: "happy" }
      ),
      native_range: nil,
      range_kind: :unbounded,
      sanity_range: nil,
      units: :unitless,
      shape: nil,
      notes: "Invalid projection used to pin the output contract."
    )
    registry = MoodProbe::Registry.new(
      models: MoodProbe::Registry.default.models,
      descriptors: [descriptor]
    )

    expect do
      described_class.new(registry:).plan_for(descriptors: [:invalid_musicnn_class])
    end.to raise_error(MoodProbe::ConfigurationError, /does not expose classes/)
  end
  # rubocop:enable Naming/VariableNumber

  it "returns immutable required files" do
    plan = planner.plan_for(descriptors: [:mood_happy])

    expect(plan.required_files).to be_frozen
    expect { plan.required_files << "extra.pb" }.to raise_error(FrozenError)
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
