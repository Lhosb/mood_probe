require "digest"
require "fileutils"
require "net/http"
require "pathname"
require "uri"

module MoodProbe
  class ModelStore
    class Downloader
      REDIRECT_LIMIT = 5

      def download(url, destination)
        response = request(URI(url), REDIRECT_LIMIT)
        unless response.is_a?(Net::HTTPSuccess)
          raise BackendError, "model download failed with HTTP #{response.code}: #{url}"
        end

        destination.binwrite(response.body)
      end

      private

      def request(uri, redirects_remaining)
        response = Net::HTTP.get_response(uri)
        return response unless response.is_a?(Net::HTTPRedirection)
        raise BackendError, "too many redirects downloading #{uri}" if redirects_remaining.zero?

        location = response["location"]
        raise BackendError, "redirect omitted location downloading #{uri}" unless location

        request(URI.join(uri, location), redirects_remaining - 1)
      end
    end

    def initialize(models_dir, registry: ModelRegistry, downloader: Downloader.new)
      @models_dir = Pathname(models_dir)
      @registry = registry
      @downloader = downloader
    end

    def verify!
      registry.models.each { |model| verify_model!(model) }
      true
    end

    def fetch!
      models_dir.mkpath
      registry.models.each { |model| fetch_model!(model) }
      verify!
    end

    private

    attr_reader :models_dir, :registry, :downloader

    def verify_model!(model)
      path = models_dir.join(model.filename)
      raise ConfigurationError, "missing model: #{path}" unless path.file?
      return if Digest::SHA256.file(path).hexdigest == model.sha256

      raise ConfigurationError, "model digest mismatch: #{path}"
    end

    def fetch_model!(model)
      destination = models_dir.join(model.filename)
      temporary = destination.sub_ext("#{destination.extname}.download")

      downloader.download(model.source_url, temporary)
      unless Digest::SHA256.file(temporary).hexdigest == model.sha256
        raise ConfigurationError, "downloaded model digest mismatch: #{model.filename}"
      end

      FileUtils.mv(temporary, destination)
    ensure
      temporary&.delete if temporary&.exist?
    end
  end
end
