RSpec.describe MoodProbe::ModelStore do
  let(:model) do
    MoodProbe::ModelRegistry::Model.new(
      filename: "model.pb",
      output_node: "model/output",
      positive_index: nil,
      sha256: Digest::SHA256.hexdigest("expected"),
      source_url: "https://essentia.upf.edu/model.pb"
    )
  end
  let(:registry) { class_double(MoodProbe::ModelRegistry, models: [model]) }

  it "verifies that every model is present with the registered digest" do
    Dir.mktmpdir do |dir|
      File.binwrite(File.join(dir, "model.pb"), "expected")

      expect(described_class.new(dir, registry:).verify!).to be(true)
    end
  end

  it "raises ConfigurationError for missing or mismatched models" do
    Dir.mktmpdir do |dir|
      store = described_class.new(dir, registry:)
      expect { store.verify! }.to raise_error(MoodProbe::ConfigurationError, /missing/)

      File.binwrite(File.join(dir, "model.pb"), "wrong")
      expect { store.verify! }.to raise_error(MoodProbe::ConfigurationError, /digest/)
    end
  end

  it "does not download models during verification" do
    downloader = instance_double(MoodProbe::ModelStore::Downloader)

    Dir.mktmpdir do |dir|
      store = described_class.new(dir, registry:, downloader:)
      expect(downloader).not_to receive(:download)
      expect { store.verify! }.to raise_error(MoodProbe::ConfigurationError)
    end
  end

  it "downloads models when fetch! is called explicitly" do
    downloader = instance_double(MoodProbe::ModelStore::Downloader)

    Dir.mktmpdir do |dir|
      store = described_class.new(dir, registry:, downloader:)
      allow(downloader).to receive(:download) { |_url, path| File.binwrite(path, "expected") }

      expect(store.fetch!).to be(true)
      expect(downloader).to have_received(:download).with(model.source_url, kind_of(Pathname))
    end
  end
end
