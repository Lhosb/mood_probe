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

## Security notes

`models_dir` is assumed to be a local directory that is not writable by an untrusted process or
principal. Do not mount it from a shared volume that grants another workload write access: doing so
silently revokes the threat-model assumption behind model verification. The gem detects common
misconfigurations such as a root not owned by the current user, a symlinked root, or a
group/world-writable root, but its pathname-based checks do not bind the file Python later reopens
to the inode Ruby verified. See
[mood_probe#2](https://github.com/Lhosb/mood_probe/issues/2) for the identity-binding work required
if a deployment must admit local writers.

## Real Essentia verification

The gem owns deterministic synthetic audio and full-precision goldens under
`spec/fixtures/mood_probe`. Essentia has no arm64 macOS wheel, so run the real
pipeline in an amd64 container. Use `bash -c`, not `bash -lc`; a login shell
resets the image's virtualenv `PATH`.

```sh
docker build --platform linux/amd64 \
  -f Dockerfile.essentia \
  -t mood-probe-essentia \
  .

docker run --rm --platform linux/amd64 --entrypoint bash \
  -e ESSENTIA_SPECS=1 \
  -e MOOD_PROBE_MODELS_DIR=/tmp/mood_probe_models \
  mood-probe-essentia \
  -c 'bundle exec ruby -Ilib exe/mood-probe --models-dir "$MOOD_PROBE_MODELS_DIR" models fetch && bundle exec rspec spec/integration/essentia_golden_spec.rb --format documentation'
```

The integration spec defaults `MOOD_PROBE_FIXTURE_ROOT` to the committed
fixture directory and `MOOD_PROBE_PYTHON` to `python3`. Override either
variable when testing a different fixture set or Python installation.

To regenerate goldens inside the same image, replace the final RSpec command
with:

```sh
bundle exec ruby spec/fixtures/mood_probe/generate_goldens.rb
```
