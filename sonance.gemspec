require_relative "lib/sonance/version"

Gem::Specification.new do |spec|
  spec.name = "sonance"
  spec.version = Sonance::VERSION
  spec.authors = ["Luke Olson"]
  spec.email = ["49695362+Lhosb@users.noreply.github.com"]

  spec.summary = "Extract registry-driven audio descriptors through Essentia"
  spec.description = "A Ruby interface and CLI for verified, demand-driven Essentia extraction."
  spec.homepage = "https://github.com/Lhosb/sonance"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir[
    "LICENSE.txt",
    "NOTICE",
    "README.md",
    "exe/*",
    "lib/**/*.rb",
    "python/*.py"
  ]
  spec.bindir = "exe"
  spec.executables = ["sonance"]
  spec.require_paths = ["lib"]

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"
end
