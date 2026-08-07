RSpec.describe "MoodProbe error hierarchy" do
  it "groups per-track errors separately from fatal run errors" do
    expect(MoodProbe::UnreadableAudioError).to be < MoodProbe::TrackError
    expect(MoodProbe::TimeoutError).to be < MoodProbe::TrackError
    expect(MoodProbe::ConfigurationError).to be < MoodProbe::FatalError
    expect(MoodProbe::BackendError).to be < MoodProbe::FatalError
    expect(MoodProbe::TrackError).to be < MoodProbe::Error
    expect(MoodProbe::FatalError).to be < MoodProbe::Error
  end
end
