root = Pathname(__dir__).join("..").expand_path
source_patterns = %w[
  lib/**/*.rb
  spec/**/*.rb
  script/**/*.rb
  exe/*
  .github/workflows/*.yml
  .github/workflows/*.yaml
].freeze
descriptor_source_paths = source_patterns.flat_map { |pattern| root.glob(pattern) }.select(&:file?).uniq.sort
raise "no descriptor source files discovered" if descriptor_source_paths.empty?

valid_descriptor_ids = Sonance::Registry.default.ids.to_set(&:to_s)
descriptor_context = /(?:\bdescriptors?\b|DESCRIPTORS)\W{0,80}\z/i
descriptor_id_occurrences = descriptor_source_paths.flat_map do |path|
  source = path.read
  custom_descriptor_ids = source.scan(
    /Sonance::Descriptor\.new\(\s*id:\s*:([a-z][a-z0-9_]*)/m
  ).flatten.to_set
  known_descriptor_ids = valid_descriptor_ids | custom_descriptor_ids
  occurrences = []

  source.to_enum(:scan, /%[iw]\[([^\]]*)\]/m).each do
    match = Regexp.last_match
    ids = match[1].scan(/[a-z][a-z0-9_]*/)
    prefix = source[[match.begin(0) - 80, 0].max...match.begin(0)]
    next unless ids.any? { |id| known_descriptor_ids.include?(id) } || prefix.match?(descriptor_context)

    line = source[0...match.begin(0)].count("\n") + 1
    occurrences.concat(ids.map { |id| { path:, line:, id:, known: known_descriptor_ids.include?(id) } })
  end

  source.to_enum(:scan, /descriptors:\s*\[([^\]]*)\]/m).each do
    match = Regexp.last_match
    ids = match[1].scan(/(?::|["'])([a-z][a-z0-9_]*)/).flatten
    line = source[0...match.begin(0)].count("\n") + 1
    occurrences.concat(ids.map { |id| { path:, line:, id:, known: known_descriptor_ids.include?(id) } })
  end

  occurrences
end
raise "no descriptor ids discovered" if descriptor_id_occurrences.empty?

RSpec.describe "repository descriptor ids" do
  it "keeps every descriptor-list id registered" do
    invalid_occurrences = descriptor_id_occurrences.reject { |occurrence| occurrence.fetch(:known) }
    details = invalid_occurrences.map do |occurrence|
      "#{occurrence.fetch(:path).relative_path_from(root)}:#{occurrence.fetch(:line)} " \
        "#{occurrence.fetch(:id)}"
    end

    expect(details).to be_empty, "unregistered descriptor ids:\n#{details.join("\n")}"
  end
end
