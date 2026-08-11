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
      allow(downloader).to receive(:download) do |url, output|
        contents = url == model.source_url ? "expected" : "other"
        output.write(contents)
      end

      expect(store.fetch!).to be(true)
      expect(downloader).to have_received(:download).twice
    end
  end

  it "does not follow a pre-planted predictable download symlink" do
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.instance_variable_set(:@read, true)
    response.instance_variable_set(:@body, "network-payload")
    allow(Net::HTTP).to receive(:get_response).and_return(response)

    Dir.mktmpdir do |dir|
      models_dir = Pathname(dir).join("models")
      models_dir.mkpath
      victim = Pathname(dir).join("victim")
      victim.binwrite("original")
      predictable = models_dir.join("model.pb.download")
      predictable.make_symlink(victim)
      scoped_registry = MoodProbe::Registry.new(models: [model], descriptors: [])

      expect { described_class.new(models_dir, registry: scoped_registry).fetch! }
        .to raise_error(MoodProbe::ConfigurationError, /digest mismatch/)
      expect(victim.binread).to eq("original")
      expect(predictable).to be_symlink
      expect(models_dir.children.map(&:basename).map(&:to_s))
        .to contain_exactly("model.pb.download")
    end
  end

  it "rejects a symlinked models directory before downloading" do
    downloader = instance_double(MoodProbe::ModelStore::Downloader)

    Dir.mktmpdir do |dir|
      outside = Pathname(dir).join("outside")
      outside.mkpath
      models_dir = Pathname(dir).join("models")
      models_dir.make_symlink(outside)
      scoped_registry = MoodProbe::Registry.new(models: [model], descriptors: [])

      expect(downloader).not_to receive(:download)
      expect do
        described_class.new(models_dir, registry: scoped_registry, downloader:).fetch!
      end.to raise_error(MoodProbe::ConfigurationError, /models directory.*symlink/)
      expect(outside.children).to be_empty
    end
  end

  it "rejects a shared-writable models directory before downloading" do
    downloader = instance_double(MoodProbe::ModelStore::Downloader)

    Dir.mktmpdir do |dir|
      models_dir = Pathname(dir).join("models")
      models_dir.mkpath
      models_dir.chmod(0o777)
      scoped_registry = MoodProbe::Registry.new(models: [model], descriptors: [])

      expect(downloader).not_to receive(:download)
      expect do
        described_class.new(models_dir, registry: scoped_registry, downloader:).fetch!
      end.to raise_error(MoodProbe::ConfigurationError, /must not be group- or world-writable/)
    ensure
      models_dir&.chmod(0o700) if models_dir&.exist?
    end
  end

  it "does not install a replacement swapped under the opened temporary file" do
    downloader = instance_double(MoodProbe::ModelStore::Downloader)

    Dir.mktmpdir do |dir|
      models_dir = Pathname(dir).join("models")
      scoped_registry = MoodProbe::Registry.new(models: [model], descriptors: [])
      allow(downloader).to receive(:download) do |_url, output|
        output.write("expected")
        path = Pathname(output.path)
        path.delete
        path.binwrite("replacement")
      end

      expect do
        described_class.new(models_dir, registry: scoped_registry, downloader:).fetch!
      end.to raise_error(MoodProbe::ConfigurationError, /temporary model file was replaced/)
      expect(models_dir.join("model.pb")).not_to exist
      expect(models_dir.children).to be_empty
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
