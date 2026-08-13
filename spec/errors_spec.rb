RSpec.describe "Sonance error hierarchy" do
  it "groups per-track errors separately from fatal run errors" do
    expect(Sonance::UnreadableAudioError).to be < Sonance::TrackError
    expect(Sonance::TimeoutError).to be < Sonance::TrackError
    expect(Sonance::MalformedOutputError).to be < Sonance::TrackError
    expect(Sonance::InferenceError).to be < Sonance::TrackError
    expect(Sonance::BackendProcessError).to be < Sonance::TrackError
    expect(Sonance::ConfigurationError).to be < Sonance::FatalError
    expect(Sonance::BackendError).to be < Sonance::FatalError
    expect(Sonance::SchemaError).to be < Sonance::FatalError
    expect(Sonance::SchemaError).not_to be < Sonance::BackendError
    expect(Sonance::SchemaError).not_to be < Sonance::TrackError
    expect(Sonance::TrackError).to be < Sonance::Error
    expect(Sonance::FatalError).to be < Sonance::Error
  end
end
