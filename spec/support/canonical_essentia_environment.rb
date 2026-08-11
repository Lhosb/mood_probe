require "rbconfig"

module CanonicalEssentiaEnvironment
  CANONICAL_CPUS = %w[amd64 x86_64].freeze
  OVERRIDE_ENV = "MOOD_PROBE_ALLOW_NON_CANONICAL".freeze

  def self.verify!(
    host_cpu: RbConfig::CONFIG.fetch("host_cpu"),
    allow_non_canonical: ENV[OVERRIDE_ENV] == "1"
  )
    return if CANONICAL_CPUS.include?(host_cpu) || allow_non_canonical

    raise <<~MESSAGE.strip
      Essentia goldens are amd64-canonical; this host is #{host_cpu}.
      Run the Dockerfile.essentia amd64 command documented in README.md.
      Set #{OVERRIDE_ENV}=1 only for deliberate non-canonical investigation.
    MESSAGE
  end
end
