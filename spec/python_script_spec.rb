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

  it "reports inference failures per file and continues the run" do
    paths = %w[good-1.wav crash.wav good-2.wav]
    stdout, stderr, status = Open3.capture3(
      { "PYTHONPATH" => python_path },
      "python3", script.to_s, *paths, "--models-dir", "/models"
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
      "python3", script.to_s, "good.wav", "--models-dir", "/models"
    )

    expect(status.exitstatus).to eq(2)
    expect(stdout).to be_empty
    expect(stderr).to include("configuration failed")
  end
end
