RSpec.describe "python/sonance_extract.py" do
  let(:root) { Pathname(__dir__).join("..").expand_path }
  let(:script) { root.join("python/sonance_extract.py") }
  let(:python_path) { root.join("spec/support/fake_essentia").to_s }
  let(:models_dir) { Pathname(Dir.mktmpdir) }
  let(:plan) do
    Sonance::Planner.new(registry: Sonance::Registry.default)
                    .plan_for(descriptors: [:mood_happy_musicnn])
  end

  around do |example|
    plan.required_files.each { |filename| models_dir.join(filename).binwrite("model") }
    example.run
  ensure
    FileUtils.remove_entry(models_dir)
  end

  it "emits aligned NDJSON for mixed good/bad/good/bad paths and exits zero" do
    paths = %w[good-1.wav bad-1.wav good-2.wav bad-2.wav]
    stdout, stderr, status = Open3.capture3(
      { "PYTHONPATH" => python_path },
      "python3", script.to_s, *paths, *plan_arguments
    )
    payloads = stdout.lines.map { |line| JSON.parse(line) }

    expect(status).to be_success, stderr
    expect(payloads.map { |payload| payload.fetch("path") }).to eq(paths)
    expect(payloads.map { |payload| payload.key?("features") }).to eq([true, false, true, false])
    expect(payloads.values_at(1, 3)).to all(include("error" => include("type" => "unreadable_audio")))
  end

  it "loads model graphs without touching audio during verification" do
    stdout, stderr, status = Open3.capture3(
      { "PYTHONPATH" => python_path },
      "python3", script.to_s, "--verify", *plan_arguments
    )

    expect(status).to be_success, stderr
    expect(stdout).to be_empty
  end

  it "reports inference failures per file and continues the run" do
    paths = %w[good-1.wav crash.wav good-2.wav]
    stdout, stderr, status = Open3.capture3(
      { "PYTHONPATH" => python_path },
      "python3", script.to_s, *paths, *plan_arguments
    )
    payloads = stdout.lines.map { |line| JSON.parse(line) }

    expect(status).to be_success, stderr
    expect(payloads.map { |payload| payload.fetch("path") }).to eq(paths)
    expect(payloads[1]).to include("error" => include("type" => "inference_error"))
    expect(payloads.values_at(0, 2)).to all(include("features"))
  end

  it "exits two when model preflight fails end to end" do
    stdout, stderr, status = Open3.capture3(
      { "PYTHONPATH" => python_path, "FAKE_ESSENTIA_CONFIG_ERROR" => "1" },
      "python3", script.to_s, "good.wav", *plan_arguments
    )

    expect(status.exitstatus).to eq(2)
    expect(stdout).to be_empty
    expect(stderr).to include("configuration failed")
  end

  it "exits one when an unexpected run-level crash occurs" do
    harness = <<~PYTHON
      import importlib.util
      import sys

      spec = importlib.util.spec_from_file_location("sonance_extract", sys.argv[1])
      sonance_extract = importlib.util.module_from_spec(spec)
      spec.loader.exec_module(sonance_extract)

      class ExplodingPaths:
          def __bool__(self):
              return True

          def __iter__(self):
              raise RuntimeError("unexpected run crash")

      class Args:
          audio_paths = ExplodingPaths()
          models_dir = "/models"
          verify = False
          capabilities = False
          plan_json = "{}"
          plan_file = None

      sonance_extract.argparse.ArgumentParser.parse_args = lambda self: Args()
      sonance_extract.load_plan = lambda plan_json, plan_file, models_dir: {}
      sonance_extract.build_pipeline = lambda plan, models_dir: object()
      sys.exit(sonance_extract.main())
    PYTHON

    stdout, stderr, status = Open3.capture3("python3", "-c", harness, script.to_s)

    expect(status.exitstatus).to eq(1)
    expect(stdout).to be_empty
    expect(stderr).to include("backend crashed: unexpected run crash")
  end

  def plan_arguments
    [
      "--models-dir", models_dir.to_s,
      "--plan-json", JSON.generate(plan.to_h)
    ]
  end
end
