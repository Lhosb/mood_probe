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

  it "passes comma-separated descriptor ids to analyze" do
    stdout, stderr, status = run_cli(
      "--descriptors", "bpm_rhythm2013,beat_confidence_rhythm2013", "analyze", "track.wav",
      ruby_options: "-r#{root.join('spec/support/recording_cli_analyze.rb')}"
    )

    expect(status).to be_success, stderr
    expect(JSON.parse(stdout)).to eq(
      "path" => "track.wav",
      "descriptors" => %w[bpm_rhythm2013 beat_confidence_rhythm2013]
    )
  end

  it "prints available descriptor ids" do
    stdout, stderr, status = run_cli("descriptors")

    expect(status).to be_success, stderr
    expect(stdout.lines(chomp: true)).to eq(Sonance::Registry.default.ids.map(&:to_s))
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
