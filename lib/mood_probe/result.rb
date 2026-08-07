require "pathname"

module MoodProbe
  class Result
    attr_reader :path, :features, :error

    def initialize(path:, features: nil, error: nil)
      raise ArgumentError, "set exactly one of features or error" if features.nil? == error.nil?
      raise ArgumentError, "error must be a TrackError" if error && !error.is_a?(TrackError)

      @path = Pathname(path)
      @features = features
      @error = error
      freeze
    end

    def ok?
      !features.nil?
    end
  end
end
