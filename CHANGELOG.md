# Changelog

All notable changes to SynthMinder are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and SynthMinder follows [Semantic Versioning](https://semver.org).

## [Unreleased]

### Added
- **The FDD Synth Duo, a Floppy tab.** The floppy cable carries no commands, so SynthMinder talks to the Duo through its mailbox at cylinder 82, past the end of an 80-track disk (`FLOPPY.PAS`, through the BIOS's INT 13h): a request written to sector 1, the reply read from sectors 5-9, about half a second an exchange. It never writes to a drive it hasn't found to be a Duo: the Duo's reply sectors hold a hello from power-on, so finding it only reads. The tab lists the images on the Duo's card (3.5in, 5.25in and other disks) and its sample packs, and shows the Duo and each of its drives. Enter puts a disk in at once (with two drives, it asks which; `A` and `B` pick one), `E` takes one out, Enter on a pack plays it, `+` `-` set its volume. Swapping the disk SynthMinder runs from asks first. Before a swap DOS writes out what it holds, and after one, or when SynthMinder is the first to hear of a disk change, it tells DOS to read the disk afresh. Needs FDD Synth Duo firmware 0.25.0 (FDDSynthPro's `docs/synthminder.md`).
- **The Duo needs a disk in to be found.** On the Evesham (18 Nov 2026) the BIOS recalibrates before every read on a drive whose disk it hasn't recognised and reads at cylinder 0, so an empty Duo can't be reached through the BIOS, even with the head sent to cylinder 82 first (by the BIOS, or by the floppy controller itself: `FdcSeekMailbox`, which got it there). The Floppy tab says to put a disk in from the Duo's panel, and ejecting the disk SynthMinder talks through warns that it loses the Duo until one is back in. `SYNMIND /FDSEEK=A`, a diagnostic, moves the head with the controller and prints what it reported at each step.
- **The bus's settings, shown only**, on the Settings tab: the bus program, DMA, the mode and the geometry, as the Bay runs them and as HDDSYNTH.INI has them (IDE Synth Bay 0.36.0-dev.2). Enter says they're set in the file.
- **The Duo's settings** on the Settings tab: its drives (A:, or A: and B:) and the disk each starts with.
- **Command-line options for the Duo**: `/FDA=` and `/FDB=` (an image into that drive, waiting until it's in), `/FDEJECT=A` or `B`, `/FDPACK=` and `/FDVOL=`; ERRORLEVEL 5 when there's no Duo.
- SynthMinder runs with a Duo and no Bay (it opens on the Floppy tab). With a Bay, it looks for the Duo when the Floppy tab is first opened (a second or two), or at start for `/STATUS` and the floppy options.
- `SYNMIND /DEMO` has a pretend Duo on A: and B:; `/DUMP=FLOPPY` draws its tab.
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
