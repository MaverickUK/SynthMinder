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

## 0.4.0: the FDD Synth Duo (FDDSynthPro)

Built on 18 Nov 2026 in SynthMinder branch `fdd-duo` (PR MaverickUK/SynthMinder#3) and FDD Synth Duo 0.25.0-dev.1 (FDDSynthPro branch `synthminder-mailbox`): the reserved cylinder of [docs/fdd-channel.md](docs/fdd-channel.md), so it works with one drive or two. The mock-ups are on the [Floppy tab canvas](https://claude.ai/artifact/B5nTmhbA4wwChe4Vxqzz7z).

- [x] The Duo's mailbox at cylinder 82 (`MailboxSource`, `duo_commands`), host-tested with its virtual PC: the reply on the first revolution at the board's write costs, at 500 and 250 kbit/s; write-protect released at cylinder 82; a hello from power-on, so finding it only reads
- [x] `FLOPPY.PAS`: INT 13h, SMARTDRV told to forget its floppy reads, DOS told of disk changes; the Floppy tab, the Duo's settings, `/FDA=` `/FDB=` `/FDEJECT=` `/FDPACK=` `/FDVOL=`; the pretend Duo in `/DEMO`; the model and demo unit-tested
- [ ] `SYNMIND.EXE` built by CI, and the Floppy tab looked at in DOSBox-X (`/DEMO`, `/DUMP=FLOPPY`)
- [x] **On a PC with the Duo** (the Evesham, 18 Nov): found on A: with a disk in, the images listed, a disk swapped, the volume, the Settings tab's Duo group
- [ ] Still to try: two drives, a write-protected disk, SMARTDRV loaded
- [ ] BIOSes that check the cylinder against their drive table and refuse 82: program the controller directly (ports 3F0h-3F7h, DMA channel 2)
- [ ] **The mailbox with no disk in: the exchange through the floppy controller and DMA, without the BIOS** (next, 19 Nov). At cylinder 82 an empty Duo answers as if a disk were in (Duo 0.25.0-dev.2), but on the Evesham (18 Nov) the BIOS recalibrates before every read on a drive whose disk it hasn't recognised and reads at cylinder 0: no use, even with the head at 82. `FdcSeekMailbox` (`SYNMIND /FDSEEK=A`) showed the controller's own seek works: `st0=20 pcn=82`. What's left: the data rate (CCR, 3F7h: the Duo's stand-in serves the last disk's format), DMA channel 2 (mask, mode, address, page, count), then Write Data and Read Data (C 82, H 0, R 1 and 5-9, N 2, EOT, GPL, DTL FFh), their seven result bytes, and the BIOS's records (motor, cylinder, the interrupt flag) left as it expects. Until then the Duo needs a disk in to be found
- [x] The seek's sound: the trip back from cylinder 82 is silent (Duo 0.25.0-dev.2); the trip out is heard, since it's like any other seek until it ends
- [ ] A floppy per game from GameMinder: see *GameMinder: the right disc and disk for each game*, below

## Later

- Themes (GameMinder's `THEMES.TXT`), 43/50-line screens
- [x] Command-line changes for batch files: `/VOL=`, `/BAL=`, `/PACK=`, `/DISC=`, `/Q` and ERRORLEVELs (18 Nov 2026; to try on the Evesham, and whether MSCDEX sees a disc changed by `/DISC=` at once)
- [x] More of the Bay's settings: the Settings tab (second drive, HDD Synth, speed and safety), with IDE Synth Bay's `$SBQ,1,SETTINGS` and wider `SET` (18 Nov 2026; to try on the Evesham)
- [x] The bus's settings, shown only on the Settings tab: the bus program, DMA, the mode, the geometry (IDE Synth Bay 0.36.0-dev.2's SETTINGS; 18 Nov 2026). Changing them stays in HDDSYNTH.INI: the PC must be right for each
- **GameMinder: the right disc and disk for each game.** A game's `!GM_INFO.TXT` names what it needs, and GameMinder has SynthMinder put it in before the game starts, as a person would before typing the game's name:
  - **New keys:** `cd:QUAKE.ISO` (into the Bay's CD-ROM drive), `floppy:MONKEY1.IMG` (into the Duo's A:; `floppyb:` for B:), and `synthpack:` / `floppypack:` for the sound to go with it (a 1990 game on the 1985 stepper drive's pack).
  - **The call:** GameMinder runs `SYNMIND /DISC=... /FDA=... /PACK=... /Q` before the game's `exec:` (a `SynthMinder=` path in its `SETTINGS.TXT`, else `SYNMIND` on the PATH), and reads the ERRORLEVEL. On anything but 0 it says why (no Bay, no Duo, not on the card) and asks whether to start the game anyway.
  - **What's already there:** SynthMinder's options, run in order, and `/FDA=` waiting until the disk is in and DOS has been told (so `exec:A:\MONKEY.EXE` works straight after). GameMinder needs only the keys, the setting and the call; ExecWithSwap leaves room for SYNMIND then the game, one after the other.
  - **To try first, on a PC:** whether MSCDEX sees a disc changed by `/DISC=` at once (or the game needs a moment), and how long `/FDA=` adds to a launch (about two seconds: the exchange, the swap, the check).
  - **Later:** games on several floppies (swapping mid-game is the Duo's front panel, or `SYNMIND /FDA=` from a shell), and GameMinder's own screen showing which disc or disk a game will use.
- The synth's model (`$HDM`) and the Bay's seek timing shown together
- **FDD Synth Duo**: the Floppy tab, below (0.4.0)
