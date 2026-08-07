module MoodProbe
  class Features
    HEADS = %i[valence arousal danceability mood_acoustic mood_relaxed mood_happy].freeze
    REGRESSION_HEADS = %i[valence arousal].freeze
    CLASSIFICATION_HEADS = (HEADS - REGRESSION_HEADS).freeze
    SANITY_RANGE = (-0.5..1.5)
    OUTPUT_RANGE = (0.0..1.0)

    def initialize(values = nil, **keyword_values)
      source = values || keyword_values
      normalized = source.to_h.transform_keys(&:to_sym)
      validate_keys!(normalized)

      @values = HEADS.to_h do |head|
        value = normalized.fetch(head)
        validate_number!(head, value)
        validate_range!(head, value)
        [head, REGRESSION_HEADS.include?(head) ? value.clamp(OUTPUT_RANGE) : value]
      end.freeze
    end

    def to_h
      @values.dup
    end

    private

    def validate_keys!(values)
      missing = HEADS - values.keys
      raise BackendError, "missing mood head: #{missing.first}" if missing.any?

      extra = values.keys - HEADS
      raise BackendError, "unexpected mood head: #{extra.first}" if extra.any?
    end

    def validate_number!(head, value)
      return if value.is_a?(Numeric) && value.finite?

      raise BackendError, "#{head} must be a finite numeric value"
    end

    def validate_range!(head, value)
      raise BackendError, "#{head} is outside the sanity window #{SANITY_RANGE}" unless SANITY_RANGE.cover?(value)
      return unless CLASSIFICATION_HEADS.include?(head)
      return if OUTPUT_RANGE.cover?(value)

      raise BackendError, "#{head} must be within #{OUTPUT_RANGE}"
    end
  end
end
