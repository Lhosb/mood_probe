RSpec.describe "mood_probe.gemspec" do
  subject(:gemspec) { Gem::Specification.load(Pathname(__dir__).join("../mood_probe.gemspec").to_s) }

  it "uses publishable author metadata" do
    expect(gemspec.authors).not_to include("MoodProbe contributors")
    expect(gemspec.email).not_to include("opensource@example.invalid")
    expect(gemspec.homepage).to eq("https://github.com/Lhosb/mood_probe")
  end
end
