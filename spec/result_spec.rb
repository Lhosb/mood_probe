RSpec.describe MoodProbe::Result do
  let(:analysis) { MoodProbe::Analysis.new({}) }

  it "represents a successful path" do
    result = described_class.new(path: Pathname("/tmp/good.wav"), analysis:)

    expect(result).to be_ok
    expect(result.path).to eq(Pathname("/tmp/good.wav"))
    expect(result.analysis).to equal(analysis)
    expect(result.error).to be_nil
  end

  it "represents a failed path" do
    error = MoodProbe::UnreadableAudioError.new("bad audio")
    result = described_class.new(path: "/tmp/bad.wav", error:)

    expect(result).not_to be_ok
    expect(result.analysis).to be_nil
    expect(result.error).to equal(error)
  end

  it "rejects results with both or neither payload set" do
    expect { described_class.new(path: "bad", analysis:, error: MoodProbe::TrackError.new) }
      .to raise_error(ArgumentError)
    expect { described_class.new(path: "bad") }.to raise_error(ArgumentError)
  end
end
