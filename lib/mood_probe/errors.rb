module MoodProbe
  # Base class for every public mood_probe failure.
  class Error < StandardError; end

  # Base class returned for a failure limited to one input track.
  class TrackError < Error; end
  # Returned when an audio file cannot be opened or decoded.
  class UnreadableAudioError < TrackError; end
  # Returned when extracting one track exceeds its configured timeout.
  class TimeoutError < TrackError; end
  # Returned when a descriptor value is non-finite, out of range, or malformed.
  class MalformedOutputError < TrackError; end
  # Returned when Essentia cannot infer descriptors for one track.
  class InferenceError < TrackError; end
  # Returned when the backend process fails while handling one track.
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
