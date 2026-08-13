require "yaml"

RSpec.describe "release CI" do
  let(:workflow_path) { Pathname(__dir__).join("../.github/workflows/ci.yml") }
  let(:workflow_source) { workflow_path.read }
  let(:workflow) { YAML.safe_load(workflow_source, aliases: true) }
  let(:jobs) { workflow.fetch("jobs") }
  let(:capture_source) { Pathname(__dir__).join("../script/capture_essentia_outputs.rb").read }
  let(:golden_spec_source) { Pathname(__dir__).join("integration/essentia_golden_spec.rb").read }
  let(:parity_spec_source) { Pathname(__dir__).join("baseline_v0_1_0_parity_spec.rb").read }

  it "runs all four release jobs on branch pushes" do
    expect(workflow_source).to match(/^  push:\s*$/)
    expect(jobs.keys).to contain_exactly("rspec", "essentia_offline", "essentia_golden", "lint")
  end

  it "enforces frozen-baseline algebraic parity in the ordinary test job" do
    step = jobs.fetch("rspec").fetch("steps").find do |candidate|
      candidate["name"] == "Run frozen baseline algebraic gate"
    end
    command = step.fetch("run")

    expect(command).to include(
      "find spec/fixtures/sonance/baseline_v0_1_0",
      "spec/baseline_v0_1_0_parity_spec.rb",
      "example_count",
      "pending_count"
    )
    expect(command).to match(/test.*example_count.*-ge.*floor/m)
    expect(command).to match(/test.*pending_count.*-eq.*0/m)
  end

  it "fails closed when fixture discovery is empty inside either spec" do
    expect(golden_spec_source).to include(
      'raise "no golden fixtures discovered" if golden_fixture_names.empty?'
    )
    expect(parity_spec_source).to include(
      'raise "no baseline fixtures discovered" if baseline_fixture_names.empty?'
    )
  end

  it "keeps every capture-script descriptor registered" do
    descriptor_block = capture_source.match(/descriptors = %i\[(.*?)\]/m)
    expect(descriptor_block).not_to be_nil

    descriptor_ids = descriptor_block[1].scan(/[a-z][a-z0-9_]*/).map(&:to_sym)
    expect(descriptor_ids).not_to be_empty

    expect do
      descriptor_ids.each { |id| Sonance::Registry.default.fetch(id) }
    end.not_to raise_error
  end

  it "separates transport, checksum drift, environment capability, and golden regression" do
    job = jobs.fetch("essentia_golden")
    steps = job.fetch("steps")
    names = steps.map { |step| step["name"] }
    commands = steps.filter_map { |step| step["run"] }.join("\n")

    expect(names).to include(
      "Fetch models (upstream transport)",
      "Verify model digests (upstream checksum drift)",
      "Capture native outputs (environment incapable)",
      "Run golden regression gate (our regression)"
    )
    expect(names).not_to include("Set up amd64 emulation")
    expect(job.fetch("runs-on")).to eq("ubuntu-latest")
    expect(commands).to include(
      "--platform linux/amd64",
      "ESSENTIA_SPECS=1",
      "script/capture_essentia_outputs.rb",
      "SONANCE_ACTUAL_ROOT=/actual",
      "spec/integration/essentia_golden_spec.rb",
      "status=$?",
      "exit \"$status\"",
      "find spec/fixtures/sonance/golden",
      "example_count",
      "pending_count"
    )
    expect(commands).to match(/test.*example_count.*-ge.*floor/m)
    expect(commands).to match(/test.*pending_count.*-eq.*0/m)
    expect(commands).not_to include("2 examples, 0 failures")
    regression_command = steps.find do |step|
      step["name"] == "Run golden regression gate (our regression)"
    end.fetch("run")
    expect(regression_command).to match(/-c '\s*set -e\s+floor=/m)
    expect(commands.scan('--user "$(id -u):$(id -g)"').length).to eq(4)
    # This assertion keeps environment verification in capture, so comparison stays pure arithmetic.
    expect(capture_source).to include("CanonicalEssentiaEnvironment.verify!")
  end
end
