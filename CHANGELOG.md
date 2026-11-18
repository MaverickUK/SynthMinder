# Changelog

All notable changes to SynthMinder are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and SynthMinder follows [Semantic Versioning](https://semver.org).

## [Unreleased]

### Added
- **The Settings tab**: the Bay's second drive (device 1, the CD at power-on), the HDD Synth (seek timing, the Synth Link) and speed and safety (write-behind, read-ahead, the SD card's speed), with what each does, what the Bay runs now and what it will from the next power-on (a dot marks a change). Enter changes one: a chooser for seek timing, device 1 and the CD; a question, with what it trades, for the on/off ones. Needs IDE Synth Bay 0.36.0's `$SBQ,1,SETTINGS` and its wider `SET`; with older firmware the tab says so.
- **Command-line changes for batch files**: `/DISC=` (an image, or `-` to eject), `/PACK=` (by number, folder or name), `/VOL=`, `/BAL=`, and `/Q`, run in the order given, with an ERRORLEVEL for each outcome (`OPTIONS.PAS`, unit-tested).
- The README's demo animation (`docs/synthminder-demo.gif`, and an MP4), recorded in DOSBox-X by `scripts/record-demo.sh` from `SYNMIND /DEMO`, as GameMinder's is.
- A `SHA256SUMS` file with each release's zip, to check the download.
- Words for the Bay's `key` and `card` reasons (a setting it can't change; HDDSYNTH.INI it couldn't write).

### Changed
- No Bay found now ends with ERRORLEVEL 2 (it was 1, now a bad option's), as does a Bay that doesn't answer.
- The protocol's reference copy is HDDSynthPro's `docs/synthminder-protocol.md`, now that the firmware implements it (IDE Synth Bay 0.36.0-dev.1, HDD Synth 0.25.0).

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
