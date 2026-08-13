require "open3"

plan_fixture_names =
  Pathname(__dir__).join("fixtures/mood_probe/plans").glob("*.json").map(&:basename).sort
raise "no plan fixtures discovered" if plan_fixture_names.empty?

RSpec.describe "committed plans at the Python boundary" do
  let(:root) { Pathname(__dir__).join("..").expand_path }
  let(:script) { root.join("python/mood_probe_extract.py") }
  let(:fixture_dir) { root.join("spec/fixtures/mood_probe/plans") }

  it "parses every byte-identical committed plan fixture without importing Essentia" do
    Dir.mktmpdir do |dir|
      plan_fixture_names.each do |filename|
        fixture = fixture_dir.join(filename)
        prepare_models(fixture, dir)
        stdout, stderr, status = validate_fixture(fixture, dir)

        expect(status).to be_success, "#{fixture.basename}: #{stderr}"
        expect(stdout).to eq("#{fixture.basename}\n")
      end
    end
  end

  it "rejects a plan fixture with a missing top-level collection" do
    Dir.mktmpdir do |dir|
      plan = JSON.parse(fixture_dir.join("algorithm_only.json").read)
      plan.delete("emit")
      fixture = Pathname(dir).join("missing-emit.json")
      fixture.write(JSON.generate(plan))
      _stdout, stderr, status = validate_fixture(fixture, dir)

      expect(status.exitstatus).to eq(2)
      expect(stderr).to include("plan.emit")
    end
  end

  it "rejects an unsupported graph reduction" do
    Dir.mktmpdir do |dir|
      plan = JSON.parse(fixture_dir.join("musicnn_only.json").read)
      plan.fetch("emit").first["reduce"] = "sum"
      fixture = Pathname(dir).join("bad-reduce.json")
      fixture.write(JSON.generate(plan))
      prepare_models(fixture, dir)
      _stdout, stderr, status = validate_fixture(fixture, dir)

      expect(status.exitstatus).to eq(2)
      expect(stderr).to include("emit[0].reduce", "mean_over_frames")
    end
  end

  def prepare_models(fixture, dir)
    JSON.parse(fixture.read).fetch("required_files", []).each do |filename|
      Pathname(dir).join(filename).binwrite("model")
    end
  end

  def validate_fixture(fixture, models_dir)
    harness = <<~PYTHON
      import importlib.util
      import json
      import sys
      from pathlib import Path

      spec = importlib.util.spec_from_file_location("mood_probe_extract", sys.argv[1])
      module = importlib.util.module_from_spec(spec)
      spec.loader.exec_module(module)
      try:
          module.validate_plan(json.loads(Path(sys.argv[2]).read_text()), Path(sys.argv[3]))
      except (json.JSONDecodeError, module.PlanValidationError) as exc:
          print(f"mood_probe plan invalid: {exc}", file=sys.stderr)
          raise SystemExit(2)
      print(Path(sys.argv[2]).name)
    PYTHON

    Open3.capture3(
      "python3", "-c", harness,
      script.to_s, fixture.to_s, models_dir.to_s
    )
  end
end
