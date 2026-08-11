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

  it "rejects a symlink even when its target has the expected digest" do
    Dir.mktmpdir do |dir|
      target = File.join(dir, "target.pb")
      link = File.join(dir, "model.pb")
      File.binwrite(target, "expected")
      File.symlink(target, link)

      expect { described_class.new(dir, registry:).verify!(filenames: ["model.pb"]) }
        .to raise_error(MoodProbe::ConfigurationError, /symlink/)
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

  describe MoodProbe::ModelStore::Downloader do
    it "rejects an HTTP redirect before following it" do
      redirect = Net::HTTPFound.new("1.1", "302", "Found")
      redirect["location"] = "http://127.0.0.1/private"
      allow(Net::HTTP).to receive(:get_response).and_return(redirect)

      Dir.mktmpdir do |dir|
        destination = Pathname(dir).join("model.pb")

        expect do
          described_class.new.download(
            "https://essentia.upf.edu/models/model.pb",
            destination
          )
        end.to raise_error(MoodProbe::BackendError, /HTTPS/)
      end

      expect(Net::HTTP).to have_received(:get_response).once
    end
  end
end
