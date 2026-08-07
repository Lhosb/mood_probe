module MoodProbe
  class Error < StandardError; end

  class TrackError < Error; end
  class UnreadableAudioError < TrackError; end
  class TimeoutError < TrackError; end
  class MalformedOutputError < TrackError; end

  class FatalError < Error; end
  class ConfigurationError < FatalError; end
  class BackendError < FatalError; end
end
