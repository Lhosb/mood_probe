require "pathname"

module MoodProbe
  class Result
    attr_reader :path, :analysis, :error

    def initialize(path:, analysis: nil, error: nil)
      raise ArgumentError, "set exactly one of analysis or error" if analysis.nil? == error.nil?
      raise ArgumentError, "error must be a TrackError" if error && !error.is_a?(TrackError)

      @path = Pathname(path)
      @analysis = analysis
      @error = error
      freeze
    end

    def ok?
      !analysis.nil?
    end
  end
end
