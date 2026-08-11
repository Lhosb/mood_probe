require "digest"
require "net/http"
require "pathname"
require "securerandom"
require "uri"

module MoodProbe
  class ModelStore
    class Files
      CREATE_FLAGS = File::RDWR | File::CREAT | File::EXCL | File::NOFOLLOW
      READ_FLAGS = File::RDONLY | File::NOFOLLOW
      READ_SIZE = 16 * 1024
      TEMP_ATTEMPTS = 10

      def initialize(root)
        @root = Pathname(root).expand_path
      end

      def ensure_directory!
        root.mkpath
      end

      def digest(filename)
        path = path_for(filename)
        File.open(path, READ_FLAGS) do |file|
          raise ConfigurationError, "model path must be a regular file: #{path}" unless file.stat.file?

          digest_io(file)
        end
      rescue Errno::ELOOP
        raise ConfigurationError, "model path must not be a symlink: #{path}"
      rescue Errno::ENOENT
        raise ConfigurationError, "missing model: #{path}"
      end

      def create_temporary(filename)
        ensure_directory!

        TEMP_ATTEMPTS.times do
          path = root.join(".#{filename}.#{SecureRandom.hex(16)}.download")
          return [path, File.open(path, CREATE_FLAGS, 0o600)]
        rescue Errno::EEXIST, Errno::ELOOP
          next
        end

        raise BackendError, "unable to create a secure temporary model file"
      end

      def digest_io(file)
        file.flush
        file.rewind
        digest = Digest::SHA256.new
        while (chunk = file.read(READ_SIZE))
          digest.update(chunk)
        end
        digest.hexdigest
      end

      def replace(temporary, filename)
        File.rename(temporary, path_for(filename))
      end

      def delete(temporary)
        temporary&.delete if temporary&.exist?
      end

      private

      attr_reader :root

      def path_for(filename)
        path = root.join(filename).expand_path
        return path if path.dirname == root && path.basename.to_s == filename

        raise ConfigurationError, "model path escapes models directory: #{filename}"
      end
    end

    class Downloader
      REDIRECT_LIMIT = 5

      def download(url, output)
        response = request(URI(url), REDIRECT_LIMIT)
        unless response.is_a?(Net::HTTPSuccess)
          raise BackendError, "model download failed with HTTP #{response.code}: #{url}"
        end

        output.write(response.body)
      end

      private

      def request(uri, redirects_remaining)
        raise BackendError, "model downloads require HTTPS: #{uri}" unless uri.is_a?(URI::HTTPS)

        response = Net::HTTP.get_response(uri)
        return response unless response.is_a?(Net::HTTPRedirection)
        raise BackendError, "too many redirects downloading #{uri}" if redirects_remaining.zero?

        location = response["location"]
        raise BackendError, "redirect omitted location downloading #{uri}" unless location

        request(URI.join(uri, location), redirects_remaining - 1)
      end
    end

    def initialize(models_dir, registry: Registry.default, downloader: Downloader.new)
      @model_files = Files.new(models_dir)
      @registry = registry
      @downloader = downloader
    end

    def verify!(filenames:)
      filenames.each { |filename| verify_model!(model_for(filename)) }
      true
    end

    def fetch!
      model_files.ensure_directory!
      registry.models.each { |model| fetch_model!(model) }
      verify!(filenames: registry.models.map(&:filename))
    end

    private

    attr_reader :model_files, :registry, :downloader

    def model_for(filename)
      registry.models.find { |model| model.filename == filename } ||
        raise(ConfigurationError, "unknown model: #{filename}")
    end

    def verify_model!(model)
      return if model_files.digest(model.filename) == model.sha256

      raise ConfigurationError, "model digest mismatch: #{model.filename}"
    end

    def fetch_model!(model)
      temporary, output = model_files.create_temporary(model.filename)

      downloader.download(model.source_url, output)
      unless model_files.digest_io(output) == model.sha256
        raise ConfigurationError, "downloaded model digest mismatch: #{model.filename}"
      end

      model_files.replace(temporary, model.filename)
    ensure
      output&.close
      model_files.delete(temporary)
    end
  end
end
