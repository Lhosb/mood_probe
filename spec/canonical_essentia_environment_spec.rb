require "open3"
require_relative "support/canonical_essentia_environment"

RSpec.describe "canonical Essentia golden environment" do
  it "rejects a non-amd64 host with the canonical environment named" do
    expect do
      CanonicalEssentiaEnvironment.verify!(host_cpu: "arm64", allow_non_canonical: false)
    end.to raise_error(RuntimeError) { |error|
      expect(error.message).to include(
        "goldens are amd64-canonical",
        "host is arm64",
        "Dockerfile.essentia"
      )
    }
  end

  it "accepts amd64 and an explicit non-canonical override" do
    expect do
      CanonicalEssentiaEnvironment.verify!(host_cpu: "x86_64", allow_non_canonical: false)
      CanonicalEssentiaEnvironment.verify!(host_cpu: "arm64", allow_non_canonical: true)
    end.not_to raise_error
  end

  it "prevents the golden generator from writing on arm64 before model loading" do
    generator = Pathname(__dir__).join("fixtures/mood_probe/generate_goldens.rb")
    ruby = <<~RUBY
      require "rbconfig"
      RbConfig::CONFIG["host_cpu"] = "arm64"
      load ARGV.fetch(0)
    RUBY
    _stdout, stderr, status = Open3.capture3(
      { "MOOD_PROBE_MODELS_DIR" => "/definitely/missing" },
      RbConfig.ruby, "-e", ruby, generator.to_s
    )

    expect(status).not_to be_success
    expect(stderr).to match(/goldens are amd64-canonical.*host is arm64/i)
    expect(stderr).not_to include("missing model")
  end
end
