# mood_probe

`mood_probe` extracts six normalized mood features from audio using an
operator-provided Essentia Python installation and six separately licensed
TensorFlow model files.

The gem ships neither Essentia nor model weights. See `NOTICE`.

```ruby
extractor = MoodProbe::Extractor.new(models_dir: "/path/to/models")
extractor.verify!
features = extractor.analyze("/path/to/audio.wav")
results = extractor.analyze_all(["one.wav", Pathname("two.wav")])
```

Model downloads are always explicit:

```sh
mood-probe --models-dir /path/to/models models fetch
mood-probe --models-dir /path/to/models models verify
mood-probe --models-dir /path/to/models analyze track.wav
```
