RSpec.describe "python/mood_probe_extract.py" do
  let(:root) { Pathname(__dir__).join("..").expand_path }
  let(:script) { root.join("python/mood_probe_extract.py") }
  let(:python_path) { root.join("spec/support/fake_essentia").to_s }

  it "emits aligned NDJSON for mixed good/bad/good/bad paths and exits zero" do
    paths = %w[good-1.wav bad-1.wav good-2.wav bad-2.wav]
    stdout, stderr, status = Open3.capture3(
      { "PYTHONPATH" => python_path },
      "python3", script.to_s, *paths, "--models-dir", "/models"
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
      "python3", script.to_s, "--verify", "--models-dir", "/models"
    )

    expect(status).to be_success, stderr
    expect(stdout).to be_empty
  end

  it "preserves partial output and exits one for an unexpected inference crash" do
    paths = %w[good-1.wav crash.wav good-2.wav]
    stdout, stderr, status = Open3.capture3(
      { "PYTHONPATH" => python_path },
      "python3", script.to_s, *paths, "--models-dir", "/models"
    )
    payloads = stdout.lines.map { |line| JSON.parse(line) }

    expect(status.exitstatus).to eq(1)
    expect(payloads.map { |payload| payload.fetch("path") }).to eq(["good-1.wav"])
    expect(stderr).to include("backend crashed")
  end
end
