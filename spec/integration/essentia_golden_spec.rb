# Run the real-Essentia gate from a native x86_64 host at the gem root:
#   docker build --platform linux/amd64 -f Dockerfile.essentia -t mood-probe-essentia .
#   docker run --rm --platform linux/amd64 --entrypoint bash \
#     -e ESSENTIA_SPECS=1 -e MOOD_PROBE_MODELS_DIR=/tmp/mood_probe_models \
#     mood-probe-essentia \
#     -c 'bundle exec ruby -Ilib exe/mood-probe --models-dir "$MOOD_PROBE_MODELS_DIR" models fetch &&
#         bundle exec rspec spec/integration/essentia_golden_spec.rb --format documentation'
# Goldens record the gem's native descriptor values.
# Native-run evidence on identical trees: EPYC 9V74 measured 4.369e-06 (22.9x inside the bound);
# EPYC 7763 measured 3.894e-06 (25.7x inside). M1 outcome (b), ANSWERED-NOT-RUN: differing runner
# populations refute unscoped bit identity, while n=1 per CPU model says nothing about model-scoped eq.
require_relative "../support/canonical_essentia_environment"

golden_fixture_names =
  Pathname(__dir__).join("../fixtures/mood_probe/golden").expand_path.glob("*.json").map(&:basename).sort
raise "no golden fixtures discovered" if golden_fixture_names.empty?

RSpec.describe "MoodProbe Essentia goldens", :essentia do
  let(:root) { Pathname(__dir__).join("../..").expand_path }
  let(:descriptors) do
    %i[
      valence_emomusic
      arousal_emomusic
      danceability
      mood_acoustic
      mood_relaxed
      mood_happy
    ]
  end
  let(:fixture_root) do
    Pathname(ENV.fetch("MOOD_PROBE_FIXTURE_ROOT", root.join("spec/fixtures/mood_probe").to_s))
  end
  let(:models_dir) do
    ENV.fetch("MOOD_PROBE_MODELS_DIR", File.expand_path("~/.cache/mood_probe/models"))
  end
  let(:golden_rel_tol) { 1e-4 }
  let(:golden_abs_floor) { 1e-10 }
  let(:actual_root) do
    value = ENV.fetch("MOOD_PROBE_ACTUAL_ROOT", nil)
    Pathname(value) if value
  end
  let(:extractor) do
    MoodProbe::Extractor.new(
      models_dir:,
      python_executable: ENV.fetch("MOOD_PROBE_PYTHON", "python3")
    )
  end

  golden_fixture_names.each do |filename|
    it "keeps #{filename} within the calibrated cross-environment bound" do
      CanonicalEssentiaEnvironment.verify! unless actual_root

      name = filename.basename(".json").to_s
      expected = JSON.parse(fixture_root.join("golden", filename).read, symbolize_names: true)
      actual = actual_values(name)

      compare_with_tolerance(actual, expected, "#{filename} golden")
    end
  end

  it "reports the full-fixture deviation from the frozen public baseline" do
    CanonicalEssentiaEnvironment.verify! unless actual_root

    baseline_dir = fixture_root.join("baseline_v0_1_0")

    baseline_comparisons = []
    golden_fixture_names.each do |filename|
      name = filename.basename(".json").to_s
      baseline = JSON.parse(baseline_dir.join(filename).read, symbolize_names: true)
      actual = actual_values(name)
      baseline_comparisons.concat(comparisons(public_values(actual), baseline, name))
    end

    worst = baseline_comparisons.max_by { |comparison| comparison.fetch(:relative_deviation) }
    puts "M2 full-fixture max rel dev #{format('%.3e', worst.fetch(:relative_deviation))} " \
         "on #{worst.fetch(:fixture)}.#{worst.fetch(:head)} " \
         "[cpu: #{CanonicalEssentiaEnvironment.cpu_identifier}]"
  end

  it "returns a TrackError for the Phase 1 undecodable fixture" do
    if actual_root
      error = JSON.parse(actual_root.join("undecodable.json").read)
      expect(error).to eq(
        "ok" => false,
        "error_class" => "MoodProbe::UnreadableAudioError"
      )
    else
      result = extractor.analyze_all(
        [fixture_root.join("audio/undecodable.m4a")],
        descriptors:
      ).first

      expect(result).not_to be_ok
      expect(result.error).to be_a(MoodProbe::UnreadableAudioError)
    end
  end

  it "rejects every golden cell just outside its calibrated bound with attribution" do
    golden_dir = fixture_root.join("golden")

    golden_dir.glob("*.json").sort.each do |path|
      expected = JSON.parse(path.read, symbolize_names: true)
      expected.each do |head, value|
        tolerance = [golden_rel_tol * value.abs, golden_abs_floor].max
        actual = expected.merge(head => value + (1.1 * tolerance))

        expect do
          compare_with_tolerance(actual, expected, "#{path.basename} golden")
        end.to raise_error(
          RSpec::Expectations::ExpectationNotMetError,
          /#{Regexp.escape(path.basename.to_s)} golden #{head}/
        )
      end
    end
  end

  it "accepts every golden cell just inside its calibrated bound" do
    golden_dir = fixture_root.join("golden")

    golden_dir.glob("*.json").sort.each do |path|
      expected = JSON.parse(path.read, symbolize_names: true)
      expected.each do |head, value|
        tolerance = [golden_rel_tol * value.abs, golden_abs_floor].max
        actual = expected.merge(head => value + (0.9 * tolerance))

        compare_with_tolerance(actual, expected, "#{path.basename} golden")
      end
    end
  end

  def public_values(actual)
    {
      valence: (actual.fetch(:valence_emomusic) - 1.0) / 8.0,
      arousal: (actual.fetch(:arousal_emomusic) - 1.0) / 8.0,
      danceability: actual.fetch(:danceability_musicnn),
      mood_acoustic: actual.fetch(:mood_acoustic_musicnn),
      mood_relaxed: actual.fetch(:mood_relaxed_musicnn),
      mood_happy: actual.fetch(:mood_happy_musicnn)
    }
  end

  def actual_values(name)
    if actual_root
      JSON.parse(actual_root.join("#{name}.json").read, symbolize_names: true)
    else
      result = extractor.analyze(
        fixture_root.join("audio", "#{name}.wav"),
        descriptors:
      )
      result.to_h.transform_values(&:value)
    end
  end

  def compare_with_tolerance(actual, expected, fixture)
    comparisons(actual, expected, fixture).each do |comparison|
      message = "#{fixture} #{comparison.fetch(:head)} expected #{comparison.fetch(:expected)}, " \
                "got #{comparison.fetch(:actual)}, tolerance #{comparison.fetch(:tolerance)}"
      expect(comparison.fetch(:absolute_deviation))
        .to be <= comparison.fetch(:tolerance), message
    end
  end

  def comparisons(actual, expected, fixture)
    expected.map do |head, expected_value|
      actual_value = actual.fetch(head)
      absolute_deviation = (actual_value - expected_value).abs
      relative_deviation =
        if expected_value.zero?
          absolute_deviation.zero? ? 0.0 : Float::INFINITY
        else
          absolute_deviation / expected_value.abs
        end
      {
        fixture:,
        head:,
        expected: expected_value,
        actual: actual_value,
        absolute_deviation:,
        relative_deviation:,
        tolerance: [golden_rel_tol * expected_value.abs, golden_abs_floor].max
      }
    end
  end
end
