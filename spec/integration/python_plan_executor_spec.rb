require "open3"

RSpec.describe "real Python plan executor seam" do
  let(:root) { Pathname(__dir__).join("../..").expand_path }
  let(:script) { root.join("python/sonance_extract.py") }
  let(:python_path) { root.join("spec/support/fake_essentia").to_s }
  let(:registry) { Sonance::Registry.default }
  let(:planner) { Sonance::Planner.new(registry:) }

  it "completes requested descriptor ids end to end through the real subprocess seam" do
    plan = planner.plan_for(descriptors: %i[valence_emomusic mood_happy_musicnn])

    Dir.mktmpdir do |models_dir|
      prepare_models(plan, models_dir)
      backend = Sonance::Backends::EssentiaPython.new(models_dir:)

      with_fake_essentia do
        expect(backend.analyze("good.wav", plan:)).to eq(
          "valence_emomusic" => 4.2,
          "mood_happy_musicnn" => 0.5
        )
      end
    end
  end

  it "emits a complete reduced MusiCNN embedding when no projection is requested" do
    plan = planner.plan_for(descriptors: [:embedding_musicnn])

    Dir.mktmpdir do |models_dir|
      prepare_models(plan, models_dir)
      backend = Sonance::Backends::EssentiaPython.new(models_dir:)

      with_fake_essentia do
        embedding = backend.analyze("good.wav", plan:).fetch("embedding_musicnn")

        expect(embedding).to eq(Array.new(200, 0.25))
      end
    end
  end

  it "constructs one shared embedding and invokes it once per path" do
    plan = planner.plan_for(descriptors: %i[mood_happy_musicnn mood_relaxed_musicnn])

    Dir.mktmpdir do |dir|
      models_dir = Pathname(dir).join("models")
      models_dir.mkdir
      prepare_models(plan, models_dir)
      trace = Pathname(dir).join("trace")
      paths = %w[one.wav two.wav three.wav]
      model_store = instance_double(Sonance::ModelStore, verify!: true)
      extractor = Sonance::Extractor.new(
        models_dir:,
        model_store:
      )

      with_fake_essentia(trace:) do
        extractor.verify!(descriptors: %i[mood_happy_musicnn mood_relaxed_musicnn])
        trace.write("")
        results = extractor.analyze_all(
          paths,
          descriptors: %i[mood_happy_musicnn mood_relaxed_musicnn]
        )

        expect(results).to all(be_ok)
      end
      events = trace.readlines(chomp: true)

      expect(events.count { |event| event == "TensorflowPredictMusiCNN.init" }).to eq(1)
      expect(events.count { |event| event == "TensorflowPredictMusiCNN.call" }).to eq(3)
      %w[mood_happy mood_relaxed].each do |head|
        expect(events.count { |event| event == "TensorflowPredict2D.init:#{head}" }).to eq(1)
        expect(events.count { |event| event == "TensorflowPredict2D.call:#{head}" }).to eq(3)
      end
    end
  end

  {
    "nan-vector.wav" => "NaN",
    "infinity-vector.wav" => "Infinity",
    "negative-infinity-vector.wav" => "-Infinity"
  }.each do |path, value_name|
    it "maps nested #{value_name} in a Vector to a precise malformed-output error" do
      plan = planner.plan_for(descriptors: [:embedding_musicnn])

      Dir.mktmpdir do |models_dir|
        prepare_models(plan, models_dir)
        backend = Sonance::Backends::EssentiaPython.new(models_dir:)

        with_fake_essentia do
          error = backend.analyze(path, plan:)

          expect(error).to be_a(Sonance::MalformedOutputError)
          expect(error.message).to include("embedding_musicnn[17]", value_name)
        end
      end
    end
  end

  {
    "nan-categorical.wav" => "NaN",
    "infinity-categorical.wav" => "Infinity",
    "negative-infinity-categorical.wav" => "-Infinity"
  }.each do |path, value_name|
    it "maps nested #{value_name} in a Categorical distribution to malformed output" do
      base_plan = planner.plan_for(descriptors: [:beat_confidence_rhythm2013])
      plan = base_plan.with(
        emit: [
          base_plan.emit.first.merge(
            id: "beat_category",
            kind: "categorical"
          )
        ]
      )
      Dir.mktmpdir do |models_dir|
        backend = Sonance::Backends::EssentiaPython.new(models_dir:)

        with_fake_essentia do
          error = backend.analyze(path, plan:)

          expect(error).to be_a(Sonance::MalformedOutputError)
          expect(error.message).to include(
            "beat_category.distribution.unstable",
            value_name
          )
        end
      end
    end
  end

  it "reports a non-finite Categorical distribution key precisely" do
    base_plan = planner.plan_for(descriptors: [:beat_confidence_rhythm2013])
    plan = base_plan.with(
      emit: [
        base_plan.emit.first.merge(
          id: "beat_category",
          kind: "categorical"
        )
      ]
    )
    Dir.mktmpdir do |models_dir|
      backend = Sonance::Backends::EssentiaPython.new(models_dir:)

      with_fake_essentia do
        error = backend.analyze("serialization-categorical.wav", plan:)

        expect(error).to be_a(Sonance::MalformedOutputError)
        expect(error.message).to include(
          "beat_category.distribution.<key>",
          "NaN"
        )
      end
    end
  end

  it "isolates an unsupported serialization type within a real subprocess batch" do
    base_plan = planner.plan_for(descriptors: [:beat_confidence_rhythm2013])
    plan = base_plan.with(
      emit: [
        base_plan.emit.first.merge(
          id: "beat_category",
          kind: "categorical"
        )
      ]
    )
    Dir.mktmpdir do |models_dir|
      backend = Sonance::Backends::EssentiaPython.new(models_dir:)

      with_fake_essentia do
        outcomes = backend.analyze_all(
          %w[one.wav type-error-categorical.wav three.wav],
          plan:
        )

        expect(outcomes.values_at(0, 2)).to all(eq("beat_category" => 0.9))
        expect(outcomes[1]).to be_a(Sonance::MalformedOutputError)
        expect(outcomes[1].message).to include(
          "descriptor serialization failed",
          "not JSON serializable"
        )
      end
    end
  end

  it "isolates a non-finite descriptor within a real subprocess batch" do
    plan = planner.plan_for(descriptors: [:embedding_musicnn])

    Dir.mktmpdir do |models_dir|
      prepare_models(plan, models_dir)
      backend = Sonance::Backends::EssentiaPython.new(models_dir:)

      with_fake_essentia do
        outcomes = backend.analyze_all(
          %w[one.wav nan-vector.wav three.wav],
          plan:
        )

        expect(outcomes.values_at(0, 2)).to all(
          include("embedding_musicnn" => Array.new(200, 0.25))
        )
        expect(outcomes[1]).to be_a(Sonance::MalformedOutputError)
        expect(outcomes[1].message).to include("embedding_musicnn[17]", "NaN")
      end
    end
  end

  def prepare_models(plan, models_dir)
    Pathname(models_dir).mkpath
    plan.required_files.each do |filename|
      Pathname(models_dir).join(filename).binwrite("model")
    end
  end

  def with_fake_essentia(trace: nil)
    original = ENV.fetch("PYTHONPATH", nil)
    original_trace = ENV.fetch("SONANCE_FAKE_TRACE", nil)
    ENV["PYTHONPATH"] = python_path
    ENV["SONANCE_FAKE_TRACE"] = trace.to_s if trace
    yield
  ensure
    ENV["PYTHONPATH"] = original
    ENV["SONANCE_FAKE_TRACE"] = original_trace
  end
end
