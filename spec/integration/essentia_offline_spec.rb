require "open3"

RSpec.describe "MoodProbe offline Essentia execution", :essentia do
  let(:root) { Pathname(__dir__).join("../..").expand_path }
  let(:audio_dir) { root.join("spec/fixtures/mood_probe/audio") }
  let(:python) { ENV.fetch("MOOD_PROBE_PYTHON", "python3") }
  let(:ground_truth_bpm) { 120.0 }
  let(:bpm_tolerance) { 2.0 }
  let(:max_resampling_delta) { 1.0 }
  let(:octave_ratios) { [0.5, 2.0] }
  let(:octave_ratio_tolerance) { 0.05 }
  let(:verdicts) { %w[no_material_resampling_change finding] }

  it "proves the committed 44.1 kHz click train is native and byte-reproducible" do
    fixture = audio_dir.join("clicks_44100.wav")
    stdout, stderr, status = Open3.capture3(
      "ffprobe", "-v", "error",
      "-select_streams", "a:0",
      "-show_entries", "stream=sample_rate",
      "-of", "default=noprint_wrappers=1:nokey=1",
      fixture.to_s
    )

    expect(status).to be_success, stderr
    expect(stdout.strip).to eq("44100")

    Dir.mktmpdir do |dir|
      generated = Pathname(dir)
      FileUtils.cp(audio_dir.join("generate.sh"), generated.join("generate.sh"))
      _output, generation_error, generation_status = Open3.capture3(
        "sh", generated.join("generate.sh").to_s
      )

      expect(generation_status).to be_success, generation_error
      expect(generated.join("clicks_44100.wav").binread).to eq(fixture.binread)
    end
  end

  it "analyzes BPM against an empty models directory without creating model files" do
    Dir.mktmpdir do |models_dir|
      extractor = MoodProbe::Extractor.new(models_dir:, python_executable: python)

      analysis = extractor.analyze(
        audio_dir.join("clicks.wav"),
        descriptors: [:bpm_rhythm2013]
      )

      expect(analysis[:bpm_rhythm2013].value).to be_within(bpm_tolerance).of(ground_truth_bpm)
      expect(Pathname(models_dir).children).to be_empty
    end
  end

  it "rejects a mixed model request against the same empty models directory" do
    Dir.mktmpdir do |models_dir|
      extractor = MoodProbe::Extractor.new(models_dir:, python_executable: python)

      expect do
        extractor.analyze(
          audio_dir.join("clicks.wav"),
          descriptors: %i[bpm_rhythm2013 mood_happy_musicnn]
        )
      end.to raise_error(
        MoodProbe::ConfigurationError,
        /missing model.*msd-musicnn-1\.pb/
      )
    end
  end

  it "constructs every registered algorithm and keeps its whitelist within real parameters" do
    registry = MoodProbe::Registry.default
    algorithm_ids = registry.descriptors.filter_map do |descriptor|
      descriptor.id if descriptor.produced_by.is_a?(MoodProbe::FromAlgorithm)
    end

    Dir.mktmpdir do |models_dir|
      extractor = MoodProbe::Extractor.new(models_dir:, python_executable: python)
      expect(extractor.verify!(descriptors: algorithm_ids)).to be(true)
    end

    harness = <<~PYTHON
      import importlib.util
      import essentia
      import json
      import sys
      import essentia.standard as es

      spec = importlib.util.spec_from_file_location("mood_probe_extract", sys.argv[1])
      module = importlib.util.module_from_spec(spec)
      spec.loader.exec_module(module)
      algorithm = es.RhythmExtractor2013()
      def construction_result(**params):
          try:
              es.RhythmExtractor2013(**params)
              return "accepted"
          except RuntimeError:
              return "rejected"

      declared_types = {}
      for key, expected in module._ALGORITHM_PARAMS["RhythmExtractor2013"].items():
          declared_types[key] = (
              "INTEGER" if expected is int else
              "STRING" if expected is str else
              "UNSUPPORTED"
          )
      domains = {}
      for key, domain in module._ALGORITHM_PARAM_DOMAINS["RhythmExtractor2013"].items():
          domains[key] = sorted(domain) if isinstance(domain, frozenset) else list(domain)
      # Construction isolates three range edges, so __doc__ is corroboration
      # there. The maxTempo lower edge remains doc-text-only: 40/59 violates
      # both the lower bound and the 20 BPM interval, while minTempo <= 39 is
      # itself invalid. The unconfounded 40/60 acceptance still pins that corner.
      # Integer probes record both sides: min low 39/40, min high 181/180,
      # max low 59/60, and max high 251/250.
      construction_probes = {
          "min_low_outside_39": construction_result(minTempo=39),
          "min_low_inside_40": construction_result(minTempo=40),
          "min_high_outside_181": construction_result(minTempo=181),
          "min_high_inside_180": construction_result(minTempo=180),
          "max_low_outside_59": construction_result(minTempo=40, maxTempo=59),
          "max_low_inside_60": construction_result(minTempo=40, maxTempo=60),
          "max_high_outside_251": construction_result(maxTempo=251),
          "max_high_inside_250": construction_result(maxTempo=250),
          "interval_19": construction_result(minTempo=180, maxTempo=199),
          "interval_20": construction_result(minTempo=180, maxTempo=200),
      }
      print(json.dumps({
          "essentia_version": essentia.__version__,
          "declared_essentia_version": module._ESSENTIA_VERSION,
          "whitelist": sorted(module._ALGORITHM_PARAMS["RhythmExtractor2013"]),
          "actual": sorted(algorithm.parameterNames()),
          "declared_types": declared_types,
          "actual_types": {
              name: algorithm.paramType(name)
              for name in algorithm.parameterNames()
          },
          "declared_defaults": module._ALGORITHM_PARAM_DEFAULTS["RhythmExtractor2013"],
          "actual_defaults": {
              name: algorithm.paramValue(name)
              for name in algorithm.parameterNames()
              if name in module._ALGORITHM_PARAM_DEFAULTS["RhythmExtractor2013"]
          },
          "domains": domains,
          "documentation": algorithm.__doc__,
          "construction_probes": construction_probes,
      }))
    PYTHON
    stdout, stderr, status = Open3.capture3(
      python, "-c", harness, root.join("python/mood_probe_extract.py").to_s
    )
    parameters = JSON.parse(stdout)

    expect(status).to be_success, stderr
    expect(parameters.fetch("whitelist") - parameters.fetch("actual")).to be_empty
    expect(parameters.fetch("declared_essentia_version")).to eq(
      parameters.fetch("essentia_version")
    )
    expect(parameters.fetch("declared_types")).to eq(parameters.fetch("actual_types"))
    expect(parameters.fetch("declared_defaults")).to eq(parameters.fetch("actual_defaults"))
    expect(parameters.fetch("domains")).to eq(
      "method" => %w[degara multifeature],
      "minTempo" => [40, 180],
      "maxTempo" => [60, 250]
    )
    expect(parameters.fetch("documentation")).to include(
      "integer ∈ [40,180]",
      "integer ∈ [60,250]",
      "string ∈ {multifeature,degara}"
    )
    expect(parameters.fetch("construction_probes")).to eq(
      "min_low_outside_39" => "rejected",
      "min_low_inside_40" => "accepted",
      "min_high_outside_181" => "rejected",
      "min_high_inside_180" => "accepted",
      "max_low_outside_59" => "rejected",
      "max_low_inside_60" => "accepted",
      "max_high_outside_251" => "rejected",
      "max_high_inside_250" => "accepted",
      "interval_19" => "rejected",
      "interval_20" => "accepted"
    )
  end

  # Measured in the amd64 image: native=120.0335693359375, resampled=120.0335693359375,
  # ground truth=120.0, delta=0.0; verdict=no_material_resampling_change.
  it "distinguishes acceptable drift, excessive drift, and octave errors" do
    expect(resampling_verdict(120.0, 120.5)).to eq("no_material_resampling_change")
    expect(resampling_verdict(120.0, 122.0)).to eq("finding")
    expect(resampling_verdict(120.0, 60.0)).to eq("finding")
    expect(finding_details).to include(
      finding_owner: "mood_probe maintainers",
      follow_up: a_string_including("Block Phase A", "Lhosb/mood_probe issue")
    )
  end

  it "records a closed resampling verdict from native and resampled click trains" do
    measurement_path.delete if measurement_path.exist?
    native_bpm = analyze_bpm(audio_dir.join("clicks_44100.wav"))
    resampled_bpm = analyze_bpm(audio_dir.join("clicks.wav"))
    native_error = (native_bpm - ground_truth_bpm).abs
    delta = (native_bpm - resampled_bpm).abs
    observed_ratios = {
      native_44100_bpm: native_bpm / ground_truth_bpm,
      resampled_16000_bpm: resampled_bpm / ground_truth_bpm
    }

    expect(native_error).to be <= bpm_tolerance

    verdict = resampling_verdict(native_bpm, resampled_bpm)
    measurement = {
      native_44100_bpm: native_bpm,
      resampled_16000_bpm: resampled_bpm,
      ground_truth_bpm:,
      delta:,
      octave_ratio: observed_ratios,
      verdict:
    }
    measurement.merge!(finding_details) if verdict == "finding"
    measurement_path.dirname.mkpath
    measurement_path.write("#{JSON.pretty_generate(measurement)}\n")

    # CI's upload-artifact if-no-files-found setting is the persistence guard.
    expect(measurement_path).to exist
    expect(verdicts).to include(verdict)
  end

  def analyze_bpm(path)
    Dir.mktmpdir do |models_dir|
      extractor = MoodProbe::Extractor.new(models_dir:, python_executable: python)
      return extractor.analyze(
        path,
        descriptors: [:bpm_rhythm2013]
      )[:bpm_rhythm2013].value
    end
  end

  def resampling_verdict(native_bpm, resampled_bpm)
    delta = (native_bpm - resampled_bpm).abs
    octave_relation = [native_bpm, resampled_bpm].any? do |bpm|
      ratio = bpm / ground_truth_bpm
      octave_ratios.any? do |octave|
        (ratio - octave).abs <= octave_ratio_tolerance
      end
    end

    if delta <= max_resampling_delta && !octave_relation
      "no_material_resampling_change"
    else
      "finding"
    end
  end

  def measurement_path
    Pathname(
      ENV.fetch(
        "MOOD_PROBE_RESAMPLING_MEASUREMENT",
        root.join("tmp/resampling_measurement.json").to_s
      )
    )
  end

  def finding_details
    {
      finding_owner: "mood_probe maintainers",
      follow_up: "Block Phase A and open a Lhosb/mood_probe issue for the measured resampling regression"
    }
  end
end
