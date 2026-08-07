require "pathname"

module MoodProbe
  class Extractor
    def initialize(
      models_dir:,
      timeout_per_file: 60,
      python_executable: "python3",
      backend: nil
    )
      @backend = backend || Backends::EssentiaPython.new(
        models_dir:,
        timeout_per_file:,
        python_executable:
      )
      @verified = false
    end

    def verify!
      return true if @verified

      backend.verify!
      @verified = true
    end

    def analyze(path)
      result = analyze_all([path]).first
      raise result.error unless result.ok?

      result.features
    end

    def analyze_all(paths)
      normalized_paths = paths.map { |path| Pathname(path) }
      verify!

      normalized_paths.map do |path|
        outcome = backend.analyze(path)
        if outcome.is_a?(TrackError)
          Result.new(path:, error: outcome)
        else
          result_for_features(path, outcome)
        end
      end
    end

    private

    attr_reader :backend

    def result_for_features(path, values)
      Result.new(path:, features: Features.new(values))
    rescue MalformedOutputError => e
      Result.new(path:, error: e)
    end
  end
end
