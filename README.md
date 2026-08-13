# mood_probe

`mood_probe` extracts a registry of Essentia descriptors from audio using an
operator-provided Essentia Python installation. Values are emitted in each
descriptor's native range, declared on its registry row; normalization is the
consumer's responsibility. Demand-driven planning verifies only the model
files required by the requested descriptors, and `[:bpm]` requires no model
files.

The gem ships neither Essentia nor model weights. See `NOTICE`.

```ruby
extractor = MoodProbe::Extractor.new(models_dir: "/path/to/models")
descriptors = %i[bpm musicnn_embedding]
extractor.verify!(descriptors:)
features = extractor.analyze("/path/to/audio.wav", descriptors:)
results = extractor.analyze_all(["one.wav", Pathname("two.wav")], descriptors:)
```

Consumers can provide a compatible registry with
`MoodProbe::Extractor.new(models_dir: "/path/to/models", registry: my_registry)`.

Model downloads are always explicit:

```sh
mood-probe --models-dir /path/to/models models fetch
mood-probe --models-dir /path/to/models models verify
mood-probe descriptors
mood-probe --models-dir /path/to/models --descriptors bpm,musicnn_embedding analyze track.wav
```

`models verify` verifies the registered model files and their digests. It no
longer preflights Python or Essentia; use `Extractor#verify!(descriptors:)` or
an extraction command to verify the runtime environment for a descriptor set.

## Implementing a backend

A backend provides `preflight_environment!`, `preflight_plan!(plan)`, and
`analyze(path, plan:)`. It may also provide `analyze_all(paths, plan:)` for
batch execution. `analyze` returns either a raw descriptor hash or a
`MoodProbe::TrackError`; `analyze_all` returns the same outcomes in input
order. Backends return per-track errors from both methods rather than raising
them. `Extractor#analyze_all` converts returned errors to failed `Result`
objects, while `Extractor#analyze` re-raises the returned error for its
single-file caller. Fatal configuration or backend failures are raised.

## Adding an algorithm

The executable algorithm surface is intentionally static, with separate
extension paths:

- A model-backed graph algorithm requires a mapping in
  `Planner::GRAPH_ALGORITHMS`, an entry in Python's `_GRAPH_ALGORITHMS`, and a
  construction branch in `build_pipeline`. Graph algorithms take no `params`;
  plan validation rejects them unconditionally.
- A standalone algorithm name on a registry `FromAlgorithm` row is forwarded
  by the planner without a Ruby enum. Add its parameter type allowlist to
  `_ALGORITHM_PARAMS`, its allowed domains to `_ALGORITHM_PARAM_DOMAINS`, and
  its construction branch to `build_pipeline`. If it has a cross-parameter
  minimum-span rule, declare that in `_ALGORITHM_MINIMUM_SPANS` and provide
  omitted-value defaults in `_ALGORITHM_PARAM_DEFAULTS`.

Both paths require a gem patch; a registry row alone cannot add executable
code.

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
`spec/fixtures/mood_probe`. Essentia can run natively on arm64 macOS when the
Python package and model files are installed. The release gate captures output
on native x86_64 and compares all six descriptor values at the calibrated
bound `max(1e-4 * |expected|, 1e-10)`. Use `bash -c`, not `bash -lc`; a login
shell resets the image's virtualenv `PATH`.

The golden spec and generator require detector-confirmed native x86_64. They
use both Ruby's configured host CPU and the CPU model from `/proc/cpuinfo`; an amd64 ISA
reported inside QEMU or another emulation layer is not the canonical
environment. `MOOD_PROBE_ALLOW_NON_CANONICAL=1` is available only for
deliberate investigation; it must not be used to produce committed goldens.

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
