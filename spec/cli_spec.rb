require "json"
require "open3"

RSpec.describe "sonance CLI" do
  let(:root) { Pathname(__dir__).join("..").expand_path }
  let(:executable) { root.join("exe/sonance") }

  it "requires --descriptors for analyze" do
    _stdout, stderr, status = run_cli("analyze", "track.wav")

    expect(status).not_to be_success
    expect(stderr).to include("analyze requires --descriptors")
    expect(stderr).not_to include("ArgumentError")
  end

  it "emits scalar descriptor values as numbers, keyed by the requested ids" do
    stdout, stderr, status = analyze_cli("bpm_rhythm2013,beat_confidence_rhythm2013")

    expect(status).to be_success, stderr
    payload = JSON.parse(stdout)

    # Keys prove the comma-separated ids were parsed and forwarded in order; values prove
    # the serialization path emits numbers rather than object inspect strings (issue #5).
    expect(payload.keys).to eq(%w[bpm_rhythm2013 beat_confidence_rhythm2013])
    expect(payload).to eq(
      "bpm_rhythm2013" => 123.5,
      "beat_confidence_rhythm2013" => 3.25
    )
    expect(payload.values).to all(be_a(Numeric))
  end

  it "emits a vector descriptor as an array of numbers" do
    stdout, stderr, status = analyze_cli("embedding_musicnn")

    expect(status).to be_success, stderr
    values = JSON.parse(stdout).fetch("embedding_musicnn")

    expect(values).to be_a(Array)
    expect(values.length).to eq(200)
    expect(values).to all(be_a(Numeric))
    expect(values.first(3)).to eq([0.001, 0.002, 0.003])
  end

  it "emits no Ruby object inspect strings for any registered descriptor" do
    stdout, stderr, status = analyze_cli(Sonance::Registry.default.ids.join(","))

    expect(status).to be_success, stderr
    expect(stdout).not_to match(/#<Sonance::/)

    payload = JSON.parse(stdout)
    expect(payload.keys).to eq(Sonance::Registry.default.ids.map(&:to_s))
    expect(payload.values).to all(satisfy { |value| value.is_a?(Numeric) || value.is_a?(Array) })
  end

  it "renders output the analysis builder can rebuild without translation" do
    descriptors = %i[bpm_rhythm2013 embedding_musicnn]
    stdout, stderr, status = analyze_cli(descriptors.join(","))

    expect(status).to be_success, stderr
    rebuilt = Sonance::AnalysisBuilder.new(registry: Sonance::Registry.default).call(
      requested: descriptors,
      raw_values: JSON.parse(stdout)
    )

    expect(rebuilt[:bpm_rhythm2013].value).to eq(123.5)
    expect(rebuilt[:embedding_musicnn].values.length).to eq(200)
  end

  # Non-vacuity floor for the three examples above: they only prove what the stub can
  # produce, so the stub must cover every registered descriptor. Requires the value table
  # alone -- loading the stub itself here would monkey-patch Extractor suite-wide.
  it "covers every registered descriptor in the recording stub" do
    require Pathname(__dir__).join("support/recording_cli_values.rb").to_s

    expect(RecordingCliValues::RAW_VALUES.keys).to match_array(Sonance::Registry.default.ids)
  end

  it "prints available descriptor ids" do
    stdout, stderr, status = run_cli("descriptors")

    expect(status).to be_success, stderr
    expect(stdout.lines(chomp: true)).to eq(Sonance::Registry.default.ids.map(&:to_s))
  end

  def analyze_cli(descriptor_ids)
    run_cli(
      "--descriptors", descriptor_ids, "analyze", "track.wav",
      ruby_options: "-r#{root.join('spec/support/recording_cli_analyze.rb')}"
    )
  end

  def run_cli(*arguments, ruby_options: nil)
    environment = ruby_options ? { "RUBYOPT" => ruby_options } : {}
    Open3.capture3(
      environment,
      Gem.ruby,
      "-I#{root.join('lib')}",
      executable.to_s,
      *arguments,
      chdir: root
    )
  end
end
