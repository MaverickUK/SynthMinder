# Roadmap

In thin slices, each one usable on its own.

## 0.1.0: the screens, against the demo (this repository)

- [x] The Minder-style screen: Synth and Bay tabs, help, confirmations
- [x] The protocol, drafted ([docs/protocol.md](docs/protocol.md)), and the demo answering it
- [x] Finding the Bay on the IDE bus by IDENTIFY, and saying so when its firmware can't talk yet
- [x] Unit tests (sentences, the model, the demo against the protocol)
- [x] Built with Turbo Pascal 7 in DOSBox-X (`scripts/build.sh`)
- [ ] Built with Free Pascal on GitHub Actions, with a release zip (CI written; first run when the repository is on GitHub)
- [ ] Tried on the Evesham: `SYNMIND` finds the Bay and says its firmware can't talk yet; `/DEMO` draws right on real VGA

## 0.2.0: the Bay talks (HDDSynthPro)

- [ ] Command `8Dh` in `ata_device`, SEND and RECEIVE through core 0, no IORDY
- [ ] `$SBQ STATUS`, `$SBQ FILES`, `$SBC DISC`, `$SBC SET device0`
- [ ] Rig tests through the USB adapter's ATA pass-through (Windows)
- [ ] SynthMinder on the Evesham and the ICL 386: the Bay tab live

## 0.3.0: the synth through the Bay (HDDSynthPro and HDDSynth_Native)

- [ ] The synth answers `$HDQ`/`$HDC` on the link UART (HDDSynth_Native)
- [ ] The Bay relays `$HD…` sentences and collects the replies, beside `$HDA`/`$HDE`/`$HDM` (after the Synth Link's bring-up: HDDSynthPro's docs/synth-link-plan.md)
- [ ] The Synth tab live: volume, balance, pack

## Later

- Themes (GameMinder's `THEMES.TXT`), 43/50-line screens
- Command-line changes for batch files: `/VOL=`, `/BAL=`, `/PACK=`, `/DISC=`
- More of the Bay's settings, shown and then changed (with a warning where the PC must be right for them: the bus program, DMA)
- The synth's model (`$HDM`) and the Bay's seek timing shown together
- **FDD Synth Duo**: a third tab. It sits on the floppy bus, which has no spare command, so it needs a way of its own to talk to the PC (a reserved sector or track on a virtual disk, or through the Bay) — to design with FDDSynthPro
