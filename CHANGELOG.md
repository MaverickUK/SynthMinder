# Changelog

All notable changes to SynthMinder are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and SynthMinder follows [Semantic Versioning](https://semver.org).

## [Unreleased]

### Added
- A `SHA256SUMS` file with each release's zip, to check the download.

## [0.1.0-dev.1] - 2026-11-17

### Added
- The Minder-style screen, GameMinder's sibling: a **Synth** tab (the synth's packs, its volume, balance and state, and the Bay) and a **Bay** tab (the hard disk and CD-ROM images on the Bay's card); help (F1); confirmations before changing the disc or the next boot's hard disk.
- Changing the synth's volume (`+` `-`), balance (`<` `>`) and pack (Enter); the CD-ROM's disc (Enter, `E` to eject); the hard disk from the next power-on.
- The SynthMinder protocol, drafted ([docs/protocol.md](docs/protocol.md)): ATA command 8Dh carrying the HDD Synth's sentences, relayed by the Bay, and `$SB…` sentences for the Bay.
- `SYNMIND /DEMO`: a pretend Bay and synth answering with the protocol's sentences.
- Finding the Bay on the primary and secondary IDE channels by IDENTIFY, and saying so when there's none, or its firmware can't talk to SynthMinder yet.
- `SYNMIND /STATUS` (print and exit), `/V`, and `/DUMP=SYNTH|BAY` (for tests: saves the screen).
- Unit tests for the sentences, the model and the demo; `scripts/build.sh` builds and tests with Turbo Pascal 7 in DOSBox-X.

[Unreleased]: https://github.com/MaverickUK/SynthMinder/compare/v0.1.0-dev.1...HEAD
[0.1.0-dev.1]: https://github.com/MaverickUK/SynthMinder/releases/tag/v0.1.0-dev.1
