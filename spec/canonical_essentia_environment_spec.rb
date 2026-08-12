require "open3"
require_relative "support/canonical_essentia_environment"

RSpec.describe "canonical Essentia golden environment" do
  it "rejects a non-x86 host with the canonical environment named" do
    expect do
      CanonicalEssentiaEnvironment.verify!(
        host_cpu: "arm64",
        cpu_identifier: "Apple M4",
        allow_non_canonical: false
      )
    end.to raise_error(RuntimeError) { |error|
      expect(error.message).to include(
        "goldens require native x86_64",
        "host is arm64",
        "CPU is Apple M4",
        "Dockerfile.essentia"
      )
    }
  end

  it "rejects emulated amd64 even though the ISA reports x86_64" do
    expect do
      CanonicalEssentiaEnvironment.verify!(
        host_cpu: "x86_64",
        cpu_identifier: "QEMU Virtual CPU version 2.5+",
        allow_non_canonical: false
      )
    end.to raise_error(RuntimeError, /native x86_64.*QEMU Virtual CPU/m)
  end

  it "accepts a native Xeon or EPYC and an explicit override" do
    expect do
      CanonicalEssentiaEnvironment.verify!(
        host_cpu: "x86_64",
        cpu_identifier: "Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz",
        allow_non_canonical: false
      )
      CanonicalEssentiaEnvironment.verify!(
        host_cpu: "arm64",
        cpu_identifier: "Apple M4",
        allow_non_canonical: true
      )
    end.not_to raise_error
  end

  it "names the GitHub-runner-class CPU allowlist honestly" do
    expect(
      CanonicalEssentiaEnvironment.github_runner_class_x86_64?(
        "x86_64",
        "AMD EPYC 7763 64-Core Processor"
      )
    ).to be(true)
    expect(
      CanonicalEssentiaEnvironment.github_runner_class_x86_64?(
        "x86_64",
        "Intel(R) Core(TM) i7-12700K"
      )
    ).to be(false)
  end

  it "prevents the golden generator from writing on arm64 before model loading" do
    generator = Pathname(__dir__).join("fixtures/mood_probe/generate_goldens.rb")
    ruby = <<~RUBY
      require #{Pathname(__dir__).join('support/canonical_essentia_environment').to_s.inspect}
      require "rbconfig"
      RbConfig::CONFIG["host_cpu"] = "arm64"
      def CanonicalEssentiaEnvironment.cpu_identifier(...) = "Apple M4"
      load ARGV.fetch(0)
    RUBY
    _stdout, stderr, status = Open3.capture3(
      { "MOOD_PROBE_MODELS_DIR" => "/definitely/missing" },
      RbConfig.ruby, "-e", ruby, generator.to_s
    )

    expect(status).not_to be_success
    expect(stderr).to match(/goldens require native x86_64.*host is arm64/i)
    expect(stderr).not_to include("missing model")
  end
end
