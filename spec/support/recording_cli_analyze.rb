require "sonance"

Sonance::Extractor.class_eval do
  define_method(:initialize) { |**options| @options = options }
  define_method(:analyze) do |path, descriptors:|
    Data.define(:path, :descriptors).new(path:, descriptors:)
  end
end
