require "rbconfig"

module CanonicalEssentiaEnvironment
  CANONICAL_CPUS = %w[amd64 x86_64].freeze
  NATIVE_CPU_PATTERN = /(?:Intel\(R\) Xeon\(R\)|AMD EPYC)/
  OVERRIDE_ENV = "MOOD_PROBE_ALLOW_NON_CANONICAL".freeze

  def self.cpu_identifier(cpuinfo: "/proc/cpuinfo")
    return "unknown CPU" unless File.exist?(cpuinfo)

    File.read(cpuinfo)[/^model name\s*:\s*(.+)$/, 1] || "unknown CPU"
  end

  def self.verify!(
    host_cpu: RbConfig::CONFIG.fetch("host_cpu"),
    cpu_identifier: CanonicalEssentiaEnvironment.cpu_identifier,
    allow_non_canonical: ENV[OVERRIDE_ENV] == "1"
  )
    return if github_runner_class_x86_64?(host_cpu, cpu_identifier) || allow_non_canonical

    raise <<~MESSAGE.strip
      Essentia goldens require native x86_64; this host is #{host_cpu}, CPU is #{cpu_identifier}.
      AMD64 names an ISA, not an execution environment; emulated amd64 is non-canonical.
      Run the Dockerfile.essentia native x86_64 command documented in README.md.
      Set #{OVERRIDE_ENV}=1 only for deliberate non-canonical investigation.
    MESSAGE
  end

  def self.github_runner_class_x86_64?(host_cpu, cpu_identifier)
    CANONICAL_CPUS.include?(host_cpu) && NATIVE_CPU_PATTERN.match?(cpu_identifier)
  end
end
