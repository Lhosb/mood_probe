require_relative "lib/mood_probe/version"

Gem::Specification.new do |spec|
  spec.name = "mood_probe"
  spec.version = MoodProbe::VERSION
  spec.authors = ["MoodProbe contributors"]
  spec.email = ["opensource@example.invalid"]

  spec.summary = "Extract six mood features from audio through Essentia"
  spec.description = "A Ruby interface and CLI for verified Essentia TensorFlow mood extraction."
  spec.homepage = "https://github.com/Lhosb/mood_probe"
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
  spec.executables = ["mood-probe"]
  spec.require_paths = ["lib"]

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"
end
