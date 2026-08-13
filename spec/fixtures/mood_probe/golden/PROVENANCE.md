# Current golden fixture provenance

- Origin: commit `c74a15b72ece4384da039cb179c5e52bf27a03cf` updated the four JSON files in this directory.
- Historical limitation: that commit does not record the command, model directory, model digests, container image, CPU, or other execution details used to produce those bytes. Its generation method is therefore unrecorded.
- Current generator: `spec/fixtures/mood_probe/generate_goldens.rb`.
- Current environment requirement: the generator calls `CanonicalEssentiaEnvironment.verify!` and requires detector-confirmed native x86_64, an Essentia Python installation, and the registry-pinned model files under `MOOD_PROBE_MODELS_DIR`.

To regenerate deliberately in the canonical environment:

```sh
MOOD_PROBE_MODELS_DIR=/path/to/models \
MOOD_PROBE_PYTHON=python3 \
bundle exec ruby spec/fixtures/mood_probe/generate_goldens.rb
```

The command rewrites all four JSON files from the committed `audio/*.wav` fixtures. Review and commit the resulting byte diffs together with the reason for the new measurements and the complete execution environment.
