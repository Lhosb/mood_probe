RSpec.describe MoodProbe::ModelStore do
  # rubocop:disable Naming/VariableNumber
  let(:model) do
    MoodProbe::Registry.default.model(:msd_musicnn_1).with(
      filename: "model.pb",
      sha256: Digest::SHA256.hexdigest("expected")
    )
  end
  let(:other_model) do
    MoodProbe::Registry.default.model(:mood_happy_msd_musicnn_1).with(
      filename: "other.pb",
      sha256: Digest::SHA256.hexdigest("other")
    )
  end
  let(:registry) { MoodProbe::Registry.new(models: [model, other_model], descriptors: []) }
  # rubocop:enable Naming/VariableNumber

  it "verifies only the requested model filenames" do
    Dir.mktmpdir do |dir|
      File.binwrite(File.join(dir, "model.pb"), "expected")

      expect(described_class.new(dir, registry:).verify!(filenames: ["model.pb"])).to be(true)
    end
  end

  it "raises ConfigurationError for missing or mismatched requested models" do
    Dir.mktmpdir do |dir|
      store = described_class.new(dir, registry:)
      expect { store.verify!(filenames: ["model.pb"]) }
        .to raise_error(MoodProbe::ConfigurationError, /missing/)

      File.binwrite(File.join(dir, "model.pb"), "wrong")
      expect { store.verify!(filenames: ["model.pb"]) }
        .to raise_error(MoodProbe::ConfigurationError, /digest/)
    end
  end

  it "rejects an unregistered requested filename" do
    Dir.mktmpdir do |dir|
      expect { described_class.new(dir, registry:).verify!(filenames: ["unknown.pb"]) }
        .to raise_error(MoodProbe::ConfigurationError, /unknown model: unknown\.pb/)
    end
  end

  it "does not download models during verification" do
    downloader = instance_double(MoodProbe::ModelStore::Downloader)

    Dir.mktmpdir do |dir|
      store = described_class.new(dir, registry:, downloader:)
      expect(downloader).not_to receive(:download)
      expect { store.verify!(filenames: ["model.pb"]) }
        .to raise_error(MoodProbe::ConfigurationError)
    end
  end

  it "downloads every registered model when fetch! is called explicitly" do
    downloader = instance_double(MoodProbe::ModelStore::Downloader)

    Dir.mktmpdir do |dir|
      store = described_class.new(dir, registry:, downloader:)
      allow(downloader).to receive(:download) do |url, path|
        contents = url == model.source_url ? "expected" : "other"
        File.binwrite(path, contents)
      end

      expect(store.fetch!).to be(true)
      expect(downloader).to have_received(:download).twice
    end
  end
end
