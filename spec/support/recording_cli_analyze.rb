require "sonance"
require_relative "recording_cli_values"

# Replaces the extractor's backend, not its result type.
#
# The previous stub returned a JSON-native `Data` object, which made the CLI spec
# structurally incapable of observing https://github.com/Lhosb/sonance/issues/5: the only
# object that reproduces the defect is the `Analysis` the stub replaced. This stub returns
# a real `Analysis` of real `Value` objects built through the real `AnalysisBuilder`, so
# the spec exercises the serialization path it claims to cover.
#
# This file is loaded via RUBYOPT into the CLI subprocess only. Do not require it from the
# main RSpec process: the class_eval below would clobber `Sonance::Extractor` suite-wide.
module RecordingCliAnalyze
  def self.analysis_for(descriptors)
    requested = descriptors.map(&:to_sym)
    raw_values = requested.to_h { |id| [id, RecordingCliValues.fetch(id)] }

    Sonance::AnalysisBuilder.new(registry: Sonance::Registry.default).call(requested:, raw_values:)
  end
end

Sonance::Extractor.class_eval do
  define_method(:initialize) { |**options| @options = options }
  define_method(:analyze) { |_path, descriptors:| RecordingCliAnalyze.analysis_for(descriptors) }
end
