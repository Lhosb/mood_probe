RSpec.describe "MoodProbe error hierarchy" do
  it "groups per-track errors separately from fatal run errors" do
    expect(MoodProbe::UnreadableAudioError).to be < MoodProbe::TrackError
    expect(MoodProbe::TimeoutError).to be < MoodProbe::TrackError
    expect(MoodProbe::MalformedOutputError).to be < MoodProbe::TrackError
    expect(MoodProbe::InferenceError).to be < MoodProbe::TrackError
    expect(MoodProbe::BackendProcessError).to be < MoodProbe::TrackError
    expect(MoodProbe::ConfigurationError).to be < MoodProbe::FatalError
    expect(MoodProbe::BackendError).to be < MoodProbe::FatalError
    expect(MoodProbe::SchemaError).to be < MoodProbe::FatalError
    expect(MoodProbe::SchemaError).not_to be < MoodProbe::BackendError
    expect(MoodProbe::SchemaError).not_to be < MoodProbe::TrackError
    expect(MoodProbe::TrackError).to be < MoodProbe::Error
    expect(MoodProbe::FatalError).to be < MoodProbe::Error
  end
end
