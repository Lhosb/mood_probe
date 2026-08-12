require "pathname"
require "mood_probe"

models_dir = Pathname(ARGV.fetch(0)).expand_path
models_dir.mkpath
downloader = MoodProbe::ModelStore::Downloader.new

MoodProbe::Registry.default.models.each do |model|
  path = models_dir.join(model.filename)
  File.open(path, "wb", 0o600) do |output|
    downloader.download(model.source_url, output)
  end
  puts "Fetched #{model.filename}"
end
