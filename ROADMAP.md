# Roadmap

In thin slices, each one usable on its own.

## 0.1.0: the screens, against the demo (this repository)

- [x] The Minder-style screen: Synth and Bay tabs, help, confirmations
- [x] The protocol, drafted ([docs/protocol.md](docs/protocol.md)), and the demo answering it
- [x] Finding the Bay on the IDE bus by IDENTIFY, and saying so when its firmware can't talk yet
- [x] Unit tests (sentences, the model, the demo against the protocol)
- [x] Built with Turbo Pascal 7 in DOSBox-X (`scripts/build.sh`)
- [x] Built with Free Pascal on GitHub Actions, with a release zip; tagged releases (`scripts/release.sh`)
- [x] Tried on the Evesham (17 Nov 2026, FreeDOS on `SYNTHMIN.IMG`): `SYNMIND` finds the Bay; with firmware that talks, so the "can't talk yet" message wasn't seen
- [ ] `/DEMO` on real VGA, and `SYNMIND` against firmware without 8Dh (IDE Synth Bay 0.35.0)

## 0.2.0: the Bay talks (HDDSynthPro)

Built in IDE Synth Bay 0.36.0-dev.1 (branch `synthminder`, PR MaverickUK/HDDSynthPro#3), run on the Evesham on 17 Nov 2026.

- [x] Command `8Dh` in `ata_device`, SEND and RECEIVE through core 0, no IORDY
- [x] `$SBQ STATUS`, `$SBQ FILES`, `$SBC DISC`, `$SBC SET device0`
- [x] SynthMinder on the Evesham: the Bay tab live (its status, its disk images and ISOs listed)
- [x] Fixed on the way: the native tests didn't build on macOS (`exchange()` against `std::exchange`); `hdm_rejected` counted every relayed answer
- [ ] Changing the CD (`$SBC DISC`) and the next power-on's disk (`$SBC SET device0`) from the Bay tab
- [ ] **Some exchanges take 50-109 ms instead of under a millisecond** (seen in the first minutes after a restart, on early answers). Likely cause: while SynthMinder polls Status back to back, core 1's early-answers loop (`serveBusEarly`) only posts the message's fetch to core 0, and collects its result, in idle moments between accesses, and gets none until the PC's 55 ms timer interrupt pauses the polling: two ticks is the 109 ms ceiling. Fix to try: post a waiting fetch, and take a waiting result, before going back to the FIFO. Core 1's hot loop, so measure it on hardware (`-m speed`, the layout check)
- [ ] Core 1's new layout benchmarked and recorded (`-m speed`, `check_core1_layout.py --update`): the PR's CI fails until then
- [ ] Rig tests through the USB adapter's ATA pass-through (Windows)
- [ ] SynthMinder on the ICL 386 (ISA, `isa = on`)

## 0.3.0: the synth through the Bay (HDDSynthPro and HDDSynth_Native)

Built in HDD Synth 0.25.0 (branch `synthminder-link`, PR MaverickUK/HDDSynth_Native#1) and IDE Synth Bay 0.36.0-dev.1; run on the Evesham on 17 Nov 2026.

- [x] The synth answers `$HDQ`/`$HDC` on the link UART (HDDSynth_Native)
- [x] The Bay relays `$HD…` sentences and collects the replies, beside `$HDA`/`$HDE`/`$HDM`
- [x] The Synth Link brought up, both wires (IDE Synth Bay 0.35.0 with HDD Synth 0.24.1, on a retro PC)
- [x] SynthMinder's requests relayed over it on the Evesham: the synth's status, volume changed, the pack list
- [x] The pack list arrives: the synth takes about 900 ms to list 12 packs, so the Bay's relay timeout went from 500 ms to 1.5 s (SynthMinder waits 2 s)
- [ ] **The synth keeps its pack list** (built once, rebuilt after a card remount) so `$HDQ,1,PACKS` answers at once: committed to `synthminder-link`, host-tested, **not yet flashed** (the synth was mid-flash when its USB hub was unplugged: it may need flashing again from its bootloader)
- [ ] The Synth tab's balance and pack change, tried
- [ ] SynthMinder with the Bay's CD-ROM configured (`ide_bus`), and with no synth on the link (`RELAY,ERR,nosynth`)

## Before merging the three branches

1. Flash the synth from `synthminder-link` and time `$HDQ,1,PACKS` (it should answer in milliseconds).
2. The early-answers fix for slow exchanges (0.2.0 above), measured on hardware; then core 1's layout benchmarked and recorded.
3. The rest of the Bay and Synth tabs tried on the Evesham: CD change, next power-on's disk, balance, pack.
4. Merge HDDSynth_Native `synthminder-link` (tag v0.25.0), then HDDSynthPro `synthminder` (0.36.0). SynthMinder's `firmware-protocol` was merged into `main` on 18 Nov 2026.

The test disk is `SYNTHMIN.IMG` on the Bay's card (FreeDOS, `SYNMIND.EXE` from this branch's CI build, `HDDBENCH`), built by HDDSynthPro's `tools/bench-image/build_image.py` with `SYNMIND.EXE` and a plain `AUTOEXEC.BAT` added by mtools. The card's `device0` points at it; `WIN98.IMG` is the owner's usual disk.

## Later

- Themes (GameMinder's `THEMES.TXT`), 43/50-line screens
- [x] Command-line changes for batch files: `/VOL=`, `/BAL=`, `/PACK=`, `/DISC=`, `/Q` and ERRORLEVELs (18 Nov 2026; to try on the Evesham, and whether MSCDEX sees a disc changed by `/DISC=` at once)
- [x] More of the Bay's settings: the Settings tab (second drive, HDD Synth, speed and safety), with IDE Synth Bay's `$SBQ,1,SETTINGS` and wider `SET` (18 Nov 2026; to try on the Evesham)
- The rest of the Bay's settings, shown and then changed with a warning where the PC must be right for them: the bus program, DMA, the mode, the geometry (show only)
- GameMinder: a CD image per game, put in the Bay's drive (`SYNMIND /DISC=`) before the game starts
- The synth's model (`$HDM`) and the Bay's seek timing shown together
- **FDD Synth Duo**: a third tab. The floppy cable carries no commands, so SynthMinder would talk to it through a mailbox in sectors: a reserved cylinder past the end of the disk (on whichever drive the Duo serves, whatever disk is in), or a virtual control drive B when that slot is free; a few tenths of a second an exchange. Ideas, and what to settle first: [docs/fdd-channel.md](docs/fdd-channel.md). To design with FDDSynthPro
