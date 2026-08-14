require "open3"
require "pathname"
require "tempfile"
require_relative "support/canonical_essentia_environment"

CANONICAL_CPU = "Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz".freeze
# F1: use a literal, not the constant under test — a constant-derived control moves with the bound
PINNED_NUMPY = "2.5.2".freeze

RSpec.describe "canonical Essentia golden environment" do
  it "accepts the uppercase Intel Xeon model reported by the failing GitHub runner" do
    expect do
      CanonicalEssentiaEnvironment.verify!(
        host_cpu: "x86_64",
        cpu_identifier: "INTEL(R) XEON(R) PLATINUM 8573C",
        numpy_ver: PINNED_NUMPY,
        allow_non_canonical: false
      )
    end.not_to raise_error

    expect do
      CanonicalEssentiaEnvironment.verify!(
        host_cpu: "x86_64",
        cpu_identifier: "INTEL(R) CORE(TM) I7-12700K",
        numpy_ver: PINNED_NUMPY,
        allow_non_canonical: false
      )
    end.to raise_error(RuntimeError, /unrecognised CPU model.*INTEL\(R\) CORE/m)
  end

  it "accepts mixed-case Intel Xeon and AMD EPYC runner families" do
    expect do
      CanonicalEssentiaEnvironment.verify!(
        host_cpu: "x86_64",
        cpu_identifier: CANONICAL_CPU,
        numpy_ver: PINNED_NUMPY,
        allow_non_canonical: false
      )
      CanonicalEssentiaEnvironment.verify!(
        host_cpu: "amd64",
        cpu_identifier: "Amd Epyc 7763 64-Core Processor",
        numpy_ver: PINNED_NUMPY,
        allow_non_canonical: false
      )
    end.not_to raise_error

    expect do
      CanonicalEssentiaEnvironment.verify!(
        host_cpu: "x86_64",
        cpu_identifier: "Intel(R) Core(TM) i7-12700K",
        numpy_ver: PINNED_NUMPY,
        allow_non_canonical: false
      )
    end.to raise_error(RuntimeError, /unrecognised CPU model.*Intel\(R\) Core/m)
  end

  it "rejects a non-x86 host while the same CPU family is accepted on x86_64" do
    expect do
      CanonicalEssentiaEnvironment.verify!(
        host_cpu: "arm64",
        cpu_identifier: CANONICAL_CPU,
        numpy_ver: PINNED_NUMPY,
        allow_non_canonical: false
      )
    end.to raise_error(RuntimeError) { |error|
      expect(error.message).to include(
        "goldens require native x86_64",
        "host is arm64",
        "CPU is #{CANONICAL_CPU}",
        "Dockerfile.essentia"
      )
    }

    expect do
      CanonicalEssentiaEnvironment.verify!(
        host_cpu: "x86_64",
        cpu_identifier: CANONICAL_CPU,
        numpy_ver: PINNED_NUMPY,
        allow_non_canonical: false
      )
    end.not_to raise_error
  end

  it "rejects detected VirtualApple emulation while accepting a native runner CPU" do
    expect do
      CanonicalEssentiaEnvironment.verify!(
        host_cpu: "x86_64",
        cpu_identifier: "VirtualApple @ 2.50GHz",
        numpy_ver: PINNED_NUMPY,
        allow_non_canonical: false
      )
    end.to raise_error(RuntimeError) { |error|
      expect(error.message).to include(
        "detected CPU emulation",
        "VirtualApple @ 2.50GHz",
        "non-canonical"
      )
      expect(error.message).not_to include("unrecognised CPU model")
    }

    expect do
      CanonicalEssentiaEnvironment.verify!(
        host_cpu: "x86_64",
        cpu_identifier: "AMD EPYC 7763 64-Core Processor",
        numpy_ver: PINNED_NUMPY,
        allow_non_canonical: false
      )
    end.not_to raise_error
  end

  it "uses SONANCE_ALLOW_NON_CANONICAL=1 as the only bypass" do
    expect do
      CanonicalEssentiaEnvironment.verify!(
        host_cpu: "arm64",
        cpu_identifier: "Apple M4",
        numpy_ver: "0.0.0",
        allow_non_canonical: true
      )
    end.not_to raise_error

    expect do
      CanonicalEssentiaEnvironment.verify!(
        host_cpu: "arm64",
        cpu_identifier: "Apple M4",
        numpy_ver: PINNED_NUMPY,
        allow_non_canonical: false
      )
    end.to raise_error(RuntimeError, /native x86_64/)

    expect do
      CanonicalEssentiaEnvironment.verify!(
        host_cpu: "arm64",
        cpu_identifier: "Apple M4",
        numpy_ver: PINNED_NUMPY,
        allow_non_canonical: "true"
      )
    end.to raise_error(RuntimeError, /native x86_64/)
  end

  it "distinguishes an unrecognised x86 CPU from detected emulation" do
    expect do
      CanonicalEssentiaEnvironment.verify!(
        host_cpu: "x86_64",
        cpu_identifier: "Intel(R) Core(TM) i7-12700K",
        numpy_ver: PINNED_NUMPY,
        allow_non_canonical: false
      )
    end.to raise_error(RuntimeError) { |error|
      expect(error.message).to include(
        "unrecognised CPU model",
        "Intel(R) Core(TM) i7-12700K",
        "may be a legitimate native CPU not yet in the allowlist",
        "NATIVE_CPU_PATTERN"
      )
      expect(error.message).not_to include("detected CPU emulation")
    }

    expect do
      CanonicalEssentiaEnvironment.verify!(
        host_cpu: "x86_64",
        cpu_identifier: "QEMU Virtual CPU version 2.5+",
        numpy_ver: PINNED_NUMPY,
        allow_non_canonical: false
      )
    end.to raise_error(RuntimeError, /detected CPU emulation.*QEMU Virtual CPU/m)
  end

  it "prevents the golden generator from writing on arm64 before model loading" do
    generator = Pathname(__dir__).join("fixtures/sonance/generate_goldens.rb")
    ruby = <<~RUBY
      require #{Pathname(__dir__).join('support/canonical_essentia_environment').to_s.inspect}
      require "rbconfig"
      RbConfig::CONFIG["host_cpu"] = "arm64"
      def CanonicalEssentiaEnvironment.cpu_identifier(...) = "Apple M4"
      load ARGV.fetch(0)
    RUBY
    _stdout, stderr, status = Open3.capture3(
      { "SONANCE_MODELS_DIR" => "/definitely/missing" },
      RbConfig.ruby, "-e", ruby, generator.to_s
    )

    expect(status).not_to be_success
    expect(stderr).to match(/goldens require native x86_64.*host is arm64/i)
    expect(stderr).not_to include("missing model")
  end

  it "rejects a canonical CPU with the wrong numpy version and names both in the message" do
    expect do
      CanonicalEssentiaEnvironment.verify!(
        host_cpu: "x86_64",
        cpu_identifier: CANONICAL_CPU,
        numpy_ver: "2.4.0",
        allow_non_canonical: false
      )
    end.to raise_error(RuntimeError) { |error|
      expect(error.message).to include("numpy #{PINNED_NUMPY}")
      expect(error.message).to include("numpy 2.4.0")
      expect(error.message).to include(CANONICAL_CPU)
    }
  end

  it "accepts a canonical CPU with the correct numpy version" do
    expect do
      CanonicalEssentiaEnvironment.verify!(
        host_cpu: "x86_64",
        cpu_identifier: CANONICAL_CPU,
        numpy_ver: PINNED_NUMPY,
        allow_non_canonical: false
      )
    end.not_to raise_error
  end

  # F2: exercise the real numpy_version detector via its python: seam
  describe ".numpy_version" do
    it "returns 'unavailable' when the interpreter does not exist" do
      expect(CanonicalEssentiaEnvironment.numpy_version(python: "/nonexistent/python3"))
        .to eq("unavailable")
    end

    it "returns the numpy version printed by the interpreter" do
      stub_python = Tempfile.new(["stub_python", ".sh"])
      begin
        stub_python.write("#!/bin/sh\necho 2.5.2\n")
        stub_python.close
        File.chmod(0o755, stub_python.path)
        expect(CanonicalEssentiaEnvironment.numpy_version(python: stub_python.path))
          .to eq("2.5.2")
      ensure
        stub_python.unlink
      end
    end
  end

  # F3: constraints.txt pin must match CANONICAL_NUMPY_VERSION in the Ruby module —
  # two independent literals that must stay in sync; a spec is the cross-check.
  it "constraints.txt numpy pin matches CANONICAL_NUMPY_VERSION" do
    constraints_path = Pathname(__dir__).parent.join("constraints.txt")
    pinned_in_file = constraints_path.read[/^numpy==(\S+)/, 1]
    expect(pinned_in_file).to eq(CanonicalEssentiaEnvironment::CANONICAL_NUMPY_VERSION),
                              "constraints.txt pins numpy==#{pinned_in_file} but CANONICAL_NUMPY_VERSION is " \
                              "#{CanonicalEssentiaEnvironment::CANONICAL_NUMPY_VERSION} — update both together"
  end
end
