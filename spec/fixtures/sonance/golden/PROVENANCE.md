# Current golden fixture provenance

- Origin: commit `c74a15b72ece4384da039cb179c5e52bf27a03cf` updated the four JSON files in this directory.
- Historical limitation: that commit does not record the command, model directory, model digests, container image, CPU, or other execution details used to produce those bytes. Its generation method is therefore unrecorded.
- Current generator: `spec/fixtures/sonance/generate_goldens.rb`.
- Current environment requirement: the generator calls `CanonicalEssentiaEnvironment.verify!` and requires detector-confirmed native x86_64, an Essentia Python installation, and the registry-pinned model files under `SONANCE_MODELS_DIR`.
- Relabelling: the 0.3.0 descriptor-id commit containing this line renamed the four MusicNN keys in every JSON file without regenerating measurements. Before and after, the ordered-value manifest had SHA-256 `719c5e7e815a80e55c3fa83d6c6b47997ed2ef3d2a7aaa3a5814d9053f1d4828`, and `cmp` reported byte identity.
- Baseline path history: the 0.3.0 namespace commit moved the frozen baseline from `spec/fixtures/mood_probe/baseline_v0_1_0/` to `spec/fixtures/sonance/baseline_v0_1_0/`; every file retained its pre-move SHA-256 digest.

To regenerate deliberately in the canonical environment:

```sh
SONANCE_MODELS_DIR=/path/to/models \
SONANCE_PYTHON=python3 \
bundle exec ruby spec/fixtures/sonance/generate_goldens.rb
```

The command rewrites all four JSON files from the committed `audio/*.wav` fixtures. Review and commit the resulting byte diffs together with the reason for the new measurements and the complete execution environment.
