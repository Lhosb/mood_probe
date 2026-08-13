# mood_probe v0.1.0 baseline provenance

- Source: the four `golden/*.json` files at mood_probe `v0.1.0` (`5360f8fd8609eae39edb5dfab8a07f6439a0b137`), copied byte-for-byte into this directory on 2026-08-10.
- Original measurement environment: an amd64 Linux Docker container running on an Apple Silicon arm64 Mac through Docker Desktop emulation.
- Essentia package: `essentia-tensorflow==2.1b6.dev1389` (`essentia.__version__ == "2.1-beta6-dev"`).
- Not recorded at original measurement time: Docker Desktop version, whether Rosetta 2 or QEMU TCG performed translation, emulated CPU model and flags, TensorFlow kernel selection, and oneDNN state.

Those omissions are historical facts, not permission to remeasure this anchor. Current native x86_64 output is compared with `max(1e-4 * |expected|, 1e-10)` precision. AMD64 names an ISA; a numerical execution environment requires the CPU and translation details above.
