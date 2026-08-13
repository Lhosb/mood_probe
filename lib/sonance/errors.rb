module Sonance
  # Base class for every public sonance failure.
  class Error < StandardError; end

  # Backend implementations return this from `analyze` or `analyze_all` for a
  # failure limited to one track; they do not raise it. `Extractor#analyze`
  # re-raises the returned error for its single-file caller.
  class TrackError < Error; end
  # Returned by a backend when audio cannot be opened or decoded.
  class UnreadableAudioError < TrackError; end
  # Returned by a backend when extracting one track times out.
  class TimeoutError < TrackError; end
  # Returned by a backend for a malformed descriptor value.
  class MalformedOutputError < TrackError; end
  # Returned by a backend when inference fails for one track.
  class InferenceError < TrackError; end
  # Returned by a backend when its process fails for one track.
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
