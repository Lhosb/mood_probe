require "digest"
require "sonance"

module Sonance
  module RecordingModelFetch
    PAYLOADS = {
      "notice-a.pb" => "notice-a-payload",
      "notice-b.pb" => "notice-b-payload"
    }.freeze

    MODELS = Registry.default.models.first(2).zip(PAYLOADS).map do |model, (filename, payload)|
      model.with(
        id: filename.delete_suffix(".pb").tr("-", "_").to_sym,
        filename:,
        sha256: Digest::SHA256.hexdigest(payload),
        source_url: "https://essentia.upf.edu/models/#{filename}",
        license: "LICENSE-#{filename.upcase}",
        attribution: "ATTRIBUTION-#{filename.upcase}"
      )
    end.freeze

    REGISTRY = Registry.new(models: MODELS, descriptors: [])

    module RegistryOverride
      def default
        RecordingModelFetch::REGISTRY
      end
    end

    module DownloaderOverride
      def download(url, output)
        filename = File.basename(URI(url).path)
        puts "DOWNLOAD #{filename}"
        output.write(RecordingModelFetch::PAYLOADS.fetch(filename))
      end
    end
  end
end

Sonance::Registry.singleton_class.prepend(Sonance::RecordingModelFetch::RegistryOverride)
Sonance::ModelStore::Downloader.prepend(Sonance::RecordingModelFetch::DownloaderOverride)
