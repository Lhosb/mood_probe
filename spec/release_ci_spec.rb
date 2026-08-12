require "yaml"

RSpec.describe "release CI" do
  let(:workflow_path) { Pathname(__dir__).join("../.github/workflows/ci.yml") }
  let(:workflow_source) { workflow_path.read }
  let(:workflow) { YAML.safe_load(workflow_source, aliases: true) }
  let(:jobs) { workflow.fetch("jobs") }

  it "runs all four release jobs on branch pushes" do
    expect(workflow_source).to match(/^  push:\s*$/)
    expect(jobs.keys).to contain_exactly("rspec", "essentia_offline", "essentia_golden", "lint")
  end

  it "enforces frozen-baseline algebraic parity in the ordinary test job" do
    step = jobs.fetch("rspec").fetch("steps").find do |candidate|
      candidate["name"] == "Run frozen baseline algebraic gate"
    end

    expect(step.fetch("run")).to include("spec/baseline_v0_1_0_parity_spec.rb")
  end

  it "separates transport, checksum drift, and golden regression on amd64" do
    job = jobs.fetch("essentia_golden")
    steps = job.fetch("steps")
    names = steps.map { |step| step["name"] }
    commands = steps.filter_map { |step| step["run"] }.join("\n")

    expect(names).to include(
      "Fetch models (upstream transport)",
      "Verify model digests (upstream checksum drift)",
      "Run golden regression gate (our regression)"
    )
    expect(commands).to include(
      "--platform linux/amd64",
      "goldens are amd64-canonical",
      "ESSENTIA_SPECS=1",
      "spec/integration/essentia_golden_spec.rb",
      "status=$?",
      "exit \"$status\"",
      "2 examples, 0 failures"
    )
    expect(commands.scan('--user "$(id -u):$(id -g)"').length).to eq(3)
  end
end
