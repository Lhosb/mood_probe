RSpec.describe Sonance::Extractor do
  let(:backend) { instance_double(Sonance::Backends::EssentiaPython) }
  let(:model_store) { instance_double(Sonance::ModelStore, verify!: true) }
  let(:extractor) do
    described_class.new(models_dir: "/models", backend:, model_store:)
  end
  let(:plan) { kind_of(Sonance::Plan) }

  before do
    allow(backend).to receive(:preflight_environment!).and_return(true)
    allow(backend).to receive(:preflight_plan!).and_return(true)
    allow(backend).to receive(:analyze)
  end

  it "returns positionally aligned results for mixed good and bad input" do
    paths = %w[good-1.wav bad-1.wav good-2.wav bad-2.wav]
    allow(backend).to receive(:analyze).and_return(
      { mood_happy_musicnn: 0.5 },
      Sonance::UnreadableAudioError.new("bad 1"),
      { mood_happy_musicnn: 0.9 },
      Sonance::TimeoutError.new("bad 2")
    )

    results = extractor.analyze_all(paths, descriptors: [:mood_happy_musicnn])

    expect(results.map(&:path)).to eq(paths.map { |path| Pathname(path) })
    expect(results.map(&:ok?)).to eq([true, false, true, false])
    expect(results.map(&:error).compact).to all(be_a(Sonance::TrackError))
    expect(results[2].analysis[:mood_happy_musicnn].value).to eq(0.9)
  end

  it "uses analyze_all on any backend that provides it" do
    batch_backend = Class.new do
      attr_reader :analyzed_paths

      def preflight_environment!; end
      def preflight_plan!(*); end

      def analyze_all(paths, **)
        @analyzed_paths = paths
        paths.map { { mood_happy_musicnn: 0.5 } }
      end

      def analyze(*)
        raise "per-file analyze should not be called"
      end
    end.new
    batch_extractor = described_class.new(
      models_dir: "/models",
      backend: batch_backend,
      model_store:
    )

    results = batch_extractor.analyze_all(
      %w[one.wav two.wav],
      descriptors: [:mood_happy_musicnn]
    )

    expect(batch_backend.analyzed_paths).to eq(%w[one.wav two.wav].map { |path| Pathname(path) })
    expect(results.map { |result| result.analysis[:mood_happy_musicnn].value }).to eq([0.5, 0.5])
  end

  it "raises configuration errors before any file is processed" do
    allow(model_store).to receive(:verify!)
      .and_raise(Sonance::ConfigurationError, "bad models")

    expect { extractor.analyze_all(%w[one.wav two.wav], descriptors: [:mood_happy_musicnn]) }
      .to raise_error(Sonance::ConfigurationError, "bad models")
    expect(backend).not_to have_received(:analyze)
  end

  it "still performs configuration preflight for an empty input list" do
    allow(backend).to receive(:preflight_environment!)
      .and_raise(Sonance::ConfigurationError, "bad Python")

    expect { extractor.analyze_all([], descriptors: [:bpm_rhythm2013]) }
      .to raise_error(Sonance::ConfigurationError, "bad Python")
    expect(backend).not_to have_received(:analyze)
  end

  it "raises a per-track result error from analyze" do
    allow(backend).to receive(:analyze)
      .and_return(Sonance::UnreadableAudioError.new("bad audio"))

    expect { extractor.analyze("bad.wav", descriptors: [:mood_happy_musicnn]) }
      .to raise_error(Sonance::UnreadableAudioError, "bad audio")
  end

  it "accepts String and Pathname inputs" do
    allow(backend).to receive(:analyze).and_return({ mood_happy_musicnn: 0.5 })

    results = extractor.analyze_all(
      ["string.wav", Pathname("pathname.wav")],
      descriptors: [:mood_happy_musicnn]
    )

    expect(results.map(&:path)).to eq([Pathname("string.wav"), Pathname("pathname.wav")])
  end

  it "retries descriptor verification after a failed plan preflight" do
    allow(backend).to receive(:preflight_plan!)
      .and_raise(Sonance::BackendError, "preflight failed")

    expect { extractor.verify!(descriptors: [:mood_happy_musicnn]) }
      .to raise_error(Sonance::BackendError, /preflight failed/)

    allow(backend).to receive(:preflight_plan!).and_return(true)
    expect(extractor.verify!(descriptors: [:mood_happy_musicnn])).to be(true)
    expect(backend).to have_received(:preflight_environment!).once
    expect(backend).to have_received(:preflight_plan!).twice
    expect(model_store).to have_received(:verify!).twice
  end

  it "propagates fatal BackendError and stops processing later paths" do
    allow(backend).to receive(:analyze).with(Pathname("one.wav"), plan:)
                                       .and_return(mood_happy_musicnn: 0.5)
    allow(backend).to receive(:analyze).with(Pathname("two.wav"), plan:)
                                       .and_raise(Sonance::BackendError, "invalid NDJSON")
    allow(backend).to receive(:analyze).with(Pathname("three.wav"), plan:)
                                       .and_return(mood_happy_musicnn: 0.5)

    expect do
      extractor.analyze_all(
        %w[one.wav two.wav three.wav],
        descriptors: [:mood_happy_musicnn]
      )
    end.to raise_error(Sonance::BackendError, /invalid NDJSON/)
    expect(backend).not_to have_received(:analyze).with(Pathname("three.wav"), plan:)
  end

  it "keeps positional results when one file returns a malformed scalar" do
    allow(backend).to receive(:analyze).and_return(
      { mood_happy_musicnn: 0.1 },
      { mood_happy_musicnn: Float::NAN },
      { mood_happy_musicnn: 0.4 }
    )

    results = extractor.analyze_all(
      %w[good-1.wav malformed.wav good-2.wav],
      descriptors: [:mood_happy_musicnn]
    )

    expect(results.map(&:ok?)).to eq([true, false, true])
    expect(results[1].error).to be_a(Sonance::MalformedOutputError)
    expect(results.values_at(0, 2).map { |result| result.analysis[:mood_happy_musicnn].value })
      .to eq([0.1, 0.4])
  end
end
