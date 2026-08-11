module MoodProbe
  Provenance = Data.define(
    :source,
    :model_filename,
    :model_version,
    :model_sha256,
    :algorithm,
    :reduction,
    :essentia_version,
    :gem_version
  )

  class Value
    attr_reader :descriptor, :provenance

    def initialize(descriptor:, provenance:)
      @descriptor = descriptor
      @provenance = provenance
    end

    def id
      descriptor.id
    end

    def kind
      descriptor.kind
    end

    def native_range
      descriptor.native_range
    end

    def range_kind
      descriptor.range_kind
    end

    def units
      descriptor.units
    end

    private

    def validate_kind!(expected)
      return if kind == expected

      raise SchemaError, "#{id} is registered as #{kind}, not #{expected}"
    end

    def validate_numeric!(name, value)
      raise SchemaError, "#{name} must be numeric" unless value.is_a?(Numeric)
      return if value.finite?

      raise MalformedOutputError, "#{name} must be finite"
    end

    def validate_sanity_range!(value)
      return unless descriptor.sanity_range
      return if descriptor.sanity_range.cover?(value)

      raise MalformedOutputError,
            "#{id} is outside sanity range #{descriptor.sanity_range}"
    end
  end

  class Scalar < Value
    attr_reader :value

    def initialize(descriptor:, provenance:, value:)
      super(descriptor:, provenance:)
      validate_kind!(:scalar)
      validate_numeric!(id, value)
      validate_sanity_range!(value)
      @value = value.to_f
      freeze
    end
  end

  class Categorical < Value
    attr_reader :label, :strength, :distribution

    def initialize(descriptor:, provenance:, label:, strength: nil, distribution: nil)
      super(descriptor:, provenance:)
      validate_kind!(:categorical)
      raise SchemaError, "#{id} label must be a String" unless label.is_a?(String)

      validate_numeric!("#{id} strength", strength) if strength
      validate_distribution!(distribution)
      @label = label.freeze
      @strength = strength&.to_f
      @distribution = distribution&.transform_values(&:to_f)&.freeze
      freeze
    end

    private

    def validate_distribution!(distribution)
      distribution&.each do |name, probability|
        raise SchemaError, "#{id} distribution labels must be Strings" unless name.is_a?(String)

        validate_numeric!("#{id} distribution #{name}", probability)
      end
    end
  end

  class Vector < Value
    attr_reader :values

    def initialize(descriptor:, provenance:, values:)
      super(descriptor:, provenance:)
      validate_kind!(:vector)
      raise SchemaError, "#{id} values must be an Array" unless values.is_a?(Array)

      unless values.length == descriptor.shape
        raise MalformedOutputError,
              "#{id} vector length mismatch: expected #{descriptor.shape}, got #{values.length}"
      end

      values.each_with_index { |value, index| validate_numeric!("#{id}[#{index}]", value) }
      @values = values.map(&:to_f).freeze
      freeze
    end
  end

  class Series < Value
    attr_reader :times, :values

    def initialize(descriptor:, provenance:, times:, values:)
      super(descriptor:, provenance:)
      validate_kind!(:series)
      validate_arrays!(times, values)
      validate_lengths!(times, values)
      validate_values!("time", times)
      validate_values!("value", values)
      @times = times.map(&:to_f).freeze
      @values = values.map(&:to_f).freeze
      freeze
    end

    private

    def validate_arrays!(times, values)
      return if times.is_a?(Array) && values.is_a?(Array)

      raise SchemaError, "#{id} times and values must be Arrays"
    end

    def validate_lengths!(times, values)
      return if times.length == values.length

      raise MalformedOutputError,
            "#{id} series length mismatch: #{times.length} times, #{values.length} values"
    end

    def validate_values!(name, values)
      values.each_with_index { |value, index| validate_numeric!("#{id} #{name}[#{index}]", value) }
    end
  end

  class Analysis
    include Enumerable

    def initialize(values = nil, **keyword_values)
      @values = (values || keyword_values).to_h.transform_keys(&:to_sym).freeze
      freeze
    end

    def [](id)
      fetch(id)
    end

    def fetch(id)
      @values.fetch(id.to_sym)
    end

    def key?(id)
      @values.key?(id.to_sym)
    end

    def keys
      @values.keys
    end

    def each(&)
      @values.each_value(&)
    end

    def to_h
      @values.dup
    end
  end

  class AnalysisBuilder
    VALUE_CLASSES = {
      scalar: Scalar,
      categorical: Categorical,
      vector: Vector,
      series: Series
    }.freeze

    def initialize(registry:)
      @registry = registry
    end

    def call(requested:, raw_values:)
      normalized = raw_values.to_h.transform_keys(&:to_sym)
      validate_requested_set!(requested, normalized.keys)
      values = requested.to_h do |id|
        descriptor = registry.fetch(id)
        [id, build_value(descriptor, normalized.fetch(id))]
      end
      Analysis.new(values)
    end

    private

    attr_reader :registry

    def validate_requested_set!(requested, returned)
      missing = requested - returned
      raise SchemaError, "missing descriptor: #{missing.first}" if missing.any?

      unexpected = returned - requested
      raise SchemaError, "unexpected descriptor: #{unexpected.first}" if unexpected.any?
    end

    def build_value(descriptor, payload)
      attributes = { descriptor:, provenance: provenance_for(descriptor) }

      case descriptor.kind
      when :scalar
        Scalar.new(**attributes, value: payload)
      when :vector
        Vector.new(**attributes, values: payload)
      else
        VALUE_CLASSES.fetch(descriptor.kind).new(
          **attributes,
          **payload.transform_keys(&:to_sym)
        )
      end
    end

    def provenance_for(descriptor)
      source = descriptor.produced_by
      source.is_a?(FromModel) ? model_provenance(source) : algorithm_provenance(source)
    end

    def model_provenance(source)
      model = registry.model(source.model)
      Provenance.new(
        source: :model,
        model_filename: model.filename,
        model_version: model.model_version,
        model_sha256: model.sha256,
        algorithm: Planner::GRAPH_ALGORITHMS.fetch(model.algorithm),
        reduction: model.reduction,
        essentia_version: nil,
        gem_version: VERSION
      )
    end

    def algorithm_provenance(source)
      Provenance.new(
        source: :algorithm,
        model_filename: nil,
        model_version: nil,
        model_sha256: nil,
        algorithm: source.name,
        reduction: nil,
        essentia_version: nil,
        gem_version: VERSION
      )
    end
  end
end
