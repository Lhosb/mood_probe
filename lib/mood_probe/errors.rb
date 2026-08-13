module MoodProbe
  # Base class for every public mood_probe failure.
  class Error < StandardError; end

  # Base class returned in batch results, or raised by `Extractor#analyze`,
  # for a failure limited to one input track.
  class TrackError < Error; end
  # Returned in a batch, or raised by `Extractor#analyze`, when audio cannot be opened or decoded.
  class UnreadableAudioError < TrackError; end
  # Returned in a batch, or raised by `Extractor#analyze`, when one track times out.
  class TimeoutError < TrackError; end
  # Returned in a batch, or raised by `Extractor#analyze`, for a malformed descriptor value.
  class MalformedOutputError < TrackError; end
  # Returned in a batch, or raised by `Extractor#analyze`, when inference fails for one track.
  class InferenceError < TrackError; end
  # Returned in a batch, or raised by `Extractor#analyze`, when the process fails for one track.
  class BackendProcessError < TrackError; end

  # Base class raised for failures that invalidate the extraction run.
  class FatalError < Error; end
  # Raised for invalid configuration, unknown ids, or unavailable model files.
  class ConfigurationError < FatalError; end
  # Raised when the backend environment, protocol, or download transport fails.
  class BackendError < FatalError; end
  # Raised when backend output violates the requested result schema.
  class SchemaError < FatalError; end
end
