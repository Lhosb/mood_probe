require "open3"

RSpec.describe "Python plan security boundary" do
  let(:root) { Pathname(__dir__).join("..").expand_path }
  let(:script) { root.join("python/mood_probe_extract.py") }
  let(:fixture_dir) { root.join("spec/fixtures/mood_probe/plans") }
  let(:tripwire_path) { root.join("spec/support/import_tripwire").to_s }

  it "reports every registered algorithm capability before importing Essentia" do
    Dir.mktmpdir do |dir|
      sentinel = Pathname(dir).join("imported")
      stdout, stderr, status = Open3.capture3(
        tripwire_environment(sentinel),
        "python3", script.to_s, "--capabilities"
      )
      capabilities = JSON.parse(stdout).fetch("algorithms")
      registered = MoodProbe::Registry.default.models.map do |model|
        MoodProbe::Planner::GRAPH_ALGORITHMS.fetch(model.algorithm)
      end
      registered.concat(
        MoodProbe::Registry.default.descriptors.filter_map do |descriptor|
          source = descriptor.produced_by
          source.name if source.is_a?(MoodProbe::FromAlgorithm)
        end
      )

      expect(status).to be_success, stderr
      expect(sentinel).not_to exist
      expect(capabilities).to include(*registered.uniq)
    end
  end

  it "rejects traversal and an unlisted algorithm before attempting an Essentia import" do
    invalid_plans = {
      "graphs[0].file" => algorithm_plan.merge(
        "graphs" => [
          {
            "ref" => "g0",
            "file" => "../../etc/passwd",
            "algorithm" => "TensorflowPredict2D",
            "output" => "model/Softmax",
            "sample_rate" => 16_000,
            "input" => { "audio" => 16_000 }
          }
        ]
      ),
      "algorithms[0].name" => deep_merge_algorithm(name: "os.system")
    }

    invalid_plans.each do |rejected_element, plan|
      Dir.mktmpdir do |dir|
        sentinel = Pathname(dir).join("imported")
        _stdout, stderr, status = run_plan(plan, dir:, sentinel:)

        expect(status.exitstatus).to eq(2)
        expect(stderr).to include(rejected_element)
        expect(sentinel).not_to exist
      end
    end
  end

  it "proves the import tripwire is active with an otherwise valid plan" do
    Dir.mktmpdir do |dir|
      sentinel = Pathname(dir).join("imported")
      _stdout, _stderr, status = run_plan(algorithm_plan, dir:, sentinel:)

      expect(status.exitstatus).to eq(99)
      expect(sentinel.read).to eq("imported\n")
    end
  end

  it "rejects a symlinked model path before attempting an Essentia import" do
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      root.join("real.pb").binwrite("model")
      root.join("linked.pb").make_symlink("real.pb")
      sentinel = root.join("imported")
      plan = algorithm_plan.merge(
        "loads" => [{ "sample_rate" => 16_000 }],
        "graphs" => [
          {
            "ref" => "g0",
            "file" => "linked.pb",
            "algorithm" => "TensorflowPredict2D",
            "output" => "model/Softmax",
            "sample_rate" => 16_000,
            "input" => { "audio" => 16_000 }
          }
        ],
        "algorithms" => [],
        "emit" => [
          {
            "id" => "mood_happy",
            "kind" => "scalar",
            "from" => "g0",
            "take" => { "index" => 0 },
            "reduce" => "mean_over_frames"
          }
        ],
        "required_files" => ["linked.pb"]
      )
      _stdout, stderr, status = run_plan(plan, dir:, sentinel:)

      expect(status.exitstatus).to eq(2)
      expect(stderr).to include("graphs[0].file", "non-symlink")
      expect(sentinel).not_to exist
    end
  end

  it "rejects an unsupported schema version before importing Essentia" do
    Dir.mktmpdir do |dir|
      sentinel = Pathname(dir).join("imported")
      _stdout, stderr, status = run_plan(
        algorithm_plan.merge("schema_version" => 2),
        dir:,
        sentinel:
      )

      expect(status.exitstatus).to eq(2)
      expect(stderr).to include("schema_version 2", "expected 1")
      expect(sentinel).not_to exist
    end
  end

  it "rejects a boolean schema version rather than treating true as version one" do
    Dir.mktmpdir do |dir|
      sentinel = Pathname(dir).join("imported")
      _stdout, stderr, status = run_plan(
        algorithm_plan.merge("schema_version" => true),
        dir:,
        sentinel:
      )

      expect(status.exitstatus).to eq(2)
      expect(stderr).to include("schema_version True", "expected 1")
      expect(sentinel).not_to exist
    end
  end

  it "rejects unknown algorithm parameters by default" do
    Dir.mktmpdir do |dir|
      sentinel = Pathname(dir).join("imported")
      plan = deep_merge_algorithm(params: { "filename" => "/tmp/injected" })
      _stdout, stderr, status = run_plan(plan, dir:, sentinel:)

      expect(status.exitstatus).to eq(2)
      expect(stderr).to include("algorithms[0].params.filename")
      expect(sentinel).not_to exist
    end
  end

  {
    "method" => 1,
    "maxTempo" => "200",
    "minTempo" => "40",
    "maxTempo-bool" => true,
    "minTempo-bool" => false
  }.each do |key, invalid_value|
    parameter = key.delete_suffix("-bool")

    it "rejects the wrong value type for the #{parameter} algorithm parameter" do
      Dir.mktmpdir do |dir|
        sentinel = Pathname(dir).join("imported")
        plan = deep_merge_algorithm(params: { parameter => invalid_value })
        _stdout, stderr, status = run_plan(plan, dir:, sentinel:)

        expect(status.exitstatus).to eq(2)
        expect(stderr).to include("algorithms[0].params.#{parameter}")
        expect(sentinel).not_to exist
      end
    end
  end

  %w[minTempo maxTempo].product(%w[NaN Infinity -Infinity 1e309]).each do |key, token|
    it "rejects #{token} for the #{key} algorithm parameter before importing Essentia" do
      Dir.mktmpdir do |dir|
        sentinel = Pathname(dir).join("imported")
        payload = plan_json_with_raw_param(key, token)
        _stdout, stderr, status = run_plan_json(payload, dir:, sentinel:)

        expect(status.exitstatus).to eq(2)
        expect(stderr).to include("algorithms[0].params.#{key}", "finite")
        expect(sentinel).not_to exist
      end
    end
  end

  {
    "method" => "unsupported",
    "minTempo" => 39,
    "minTempo-high" => 181,
    "maxTempo" => 59,
    "maxTempo-high" => 251
  }.each do |key, invalid_value|
    parameter = key.delete_suffix("-high")

    it "rejects an out-of-domain #{parameter} algorithm parameter" do
      Dir.mktmpdir do |dir|
        sentinel = Pathname(dir).join("imported")
        plan = deep_merge_algorithm(params: { parameter => invalid_value })
        _stdout, stderr, status = run_plan(plan, dir:, sentinel:)

        expect(status.exitstatus).to eq(2)
        expect(stderr).to include("algorithms[0].params.#{parameter}")
        expect(sentinel).not_to exist
      end
    end
  end

  it "rejects a tempo interval too narrow for RhythmExtractor2013" do
    Dir.mktmpdir do |dir|
      sentinel = Pathname(dir).join("imported")
      plan = deep_merge_algorithm(params: { "minTempo" => 40, "maxTempo" => 60 })
      _stdout, stderr, status = run_plan(plan, dir:, sentinel:)

      expect(status.exitstatus).to eq(2)
      expect(stderr).to include("algorithms[0].params", "more than 20 BPM")
      expect(sentinel).not_to exist
    end
  end

  it "default-denies params for graph algorithms that declare none" do
    Dir.mktmpdir do |dir|
      sentinel = Pathname(dir).join("imported")
      model = Pathname(dir).join("model.pb")
      model.binwrite("model")
      plan = algorithm_plan.merge(
        "algorithms" => [],
        "graphs" => [
          {
            "ref" => "g0",
            "file" => "model.pb",
            "algorithm" => "TensorflowPredict2D",
            "output" => "model/Softmax",
            "sample_rate" => 16_000,
            "input" => { "audio" => 16_000 },
            "params" => { "anything" => true }
          }
        ]
      )
      _stdout, stderr, status = run_plan(plan, dir:, sentinel:)

      expect(status.exitstatus).to eq(2)
      expect(stderr).to include("graphs[0].params")
      expect(sentinel).not_to exist
    end
  end

  it "rejects empty and negative graph projections" do
    [nil, {}].each do |projection|
      Dir.mktmpdir do |dir|
        root = Pathname(dir)
        root.join("model.pb").binwrite("model")
        sentinel = root.join("imported")
        take = projection || { "index" => -1 }
        plan = graph_plan(take:)
        _stdout, stderr, status = run_plan(plan, dir:, sentinel:)

        expect(status.exitstatus).to eq(2)
        expect(stderr).to include("emit[0].take")
        expect(sentinel).not_to exist
      end
    end
  end

  it "rejects projection shapes that do not match their source type" do
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      root.join("model.pb").binwrite("model")
      sentinel = root.join("imported")
      graph_with_output = graph_plan(take: { "output" => "bpm" })
      algorithm_with_index = algorithm_plan
      algorithm_with_index.fetch("emit").first["take"] = { "index" => 0 }

      [graph_with_output, algorithm_with_index].each do |plan|
        _stdout, stderr, status = run_plan(plan, dir:, sentinel:)

        expect(status.exitstatus).to eq(2)
        expect(stderr).to include("emit[0].take")
        expect(sentinel).not_to exist
      end
    end
  end

  it "rejects a graph that references itself instead of an earlier graph" do
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      root.join("model.pb").binwrite("model")
      sentinel = root.join("imported")
      plan = graph_plan(take: { "index" => 0 })
      plan.fetch("graphs").first["input"] = { "graph" => "g0" }
      plan.fetch("graphs").first.delete("sample_rate")
      plan["loads"] = []
      _stdout, stderr, status = run_plan(plan, dir:, sentinel:)

      expect(status.exitstatus).to eq(2)
      expect(stderr).to include("graphs[0].input.graph", "earlier graph")
      expect(sentinel).not_to exist
    end
  end

  it "accepts every declared RhythmExtractor2013 parameter type before importing Essentia" do
    valid_params = [
      { "method" => "multifeature", "minTempo" => 40, "maxTempo" => 200.0 },
      { "method" => "degara", "minTempo" => 180.0, "maxTempo" => 250 }
    ]

    valid_params.each do |params|
      Dir.mktmpdir do |dir|
        sentinel = Pathname(dir).join("imported")
        plan = deep_merge_algorithm(params:)
        _stdout, _stderr, status = run_plan(plan, dir:, sentinel:)

        expect(status.exitstatus).to eq(99)
        expect(sentinel).to exist
      end
    end
  end

  def algorithm_plan
    JSON.parse(fixture_dir.join("algorithm_only.json").read)
  end

  def deep_merge_algorithm(name: nil, params: nil)
    plan = algorithm_plan
    algorithm = plan.fetch("algorithms").first
    algorithm["name"] = name if name
    algorithm["params"] = params if params
    plan
  end

  def graph_plan(take:)
    algorithm_plan.merge(
      "loads" => [{ "sample_rate" => 16_000 }],
      "graphs" => [graph_definition],
      "algorithms" => [],
      "emit" => [emit_definition(take)],
      "required_files" => ["model.pb"]
    )
  end

  def graph_definition
    {
      "ref" => "g0",
      "file" => "model.pb",
      "algorithm" => "TensorflowPredict2D",
      "output" => "model/Softmax",
      "sample_rate" => 16_000,
      "input" => { "audio" => 16_000 }
    }
  end

  def emit_definition(take)
    {
      "id" => "mood_happy",
      "kind" => "scalar",
      "from" => "g0",
      "take" => take,
      "reduce" => "mean_over_frames"
    }
  end

  def tripwire_environment(sentinel)
    {
      "PYTHONPATH" => tripwire_path,
      "MOOD_PROBE_IMPORT_SENTINEL" => sentinel.to_s
    }
  end

  def run_plan(plan, dir:, sentinel:)
    run_plan_json(JSON.generate(plan), dir:, sentinel:)
  end

  def run_plan_json(payload, dir:, sentinel:)
    Open3.capture3(
      tripwire_environment(sentinel),
      "python3", script.to_s,
      "--models-dir", dir,
      "--plan-json", payload,
      "--verify"
    )
  end

  def plan_json_with_raw_param(key, token)
    marker = "__RAW_PARAMETER__"
    plan = deep_merge_algorithm(params: { key => marker })
    JSON.generate(plan).sub(JSON.generate(marker), token)
  end
end
