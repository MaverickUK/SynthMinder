# CLAUDE.md: context for working on SynthMinder

SynthMinder is a DOS program that shows and changes the HDD Synth and the IDE Synth Bay from the PC the Bay is fitted to. It's GameMinder's sibling (`../GameMinder`): the same PathMinder-style screen, Classic colours, Turbo Pascal 7 and Free Pascal, and the same habits (README, BUILD.md, ROADMAP.md, CHANGELOG.md, `VERSION.INC`, `scripts/check-version.sh`).

The owner is an experienced software architect (C#/.NET, TypeScript, Python), who wrote GameMinder in Turbo Pascal 7. Favour clear, idiomatic code over clever code.

## The other repositories

- **IDE Synth Bay** (`../HDDSynthPro`, called HDD Synth Pro until 10 Nov 2026): the RP2350 emulating an IDE drive. Its IDENTIFY model is `HDDSYNTH PROTO` (`HDDSYNTH PRO CD-ROM` for a CD-ROM as device 0), its firmware revision the firmware version. It will answer SynthMinder's command 8Dh: not yet built.
- **HDD Synth** (`../HDDSynth_Native`): the synth. Its companion app protocol (`$HDQ`, `$HDC`, `$HDS`, `$HDP`, `$HDK`; `src/host_protocol.*`, README) is what SynthMinder sends through the Bay. Today it answers it on USB only.
- **FDD Synth Duo** (`../FDDSynthPro`): later, as a third tab.

## How it talks

[docs/protocol.md](docs/protocol.md) is the contract: ATA command 8Dh (SEND and RECEIVE, one sector each way), sentences in the synth's format, `$HD…` relayed to the synth and `$SB…` for the Bay. **`DEMO.PAS` must answer exactly as the protocol says**, and `tests/TESTS.PAS` holds it to it: the demo is what the firmware will be checked against. Change the three together. Once the Bay implements the protocol, its docs hold the reference copy.

## Rules

- **Plain DOS, real mode.** `IDE.PAS` uses the ports directly; never from a Windows DOS box.
- **Never write to the drive** other than through the SynthMinder command. IDENTIFY and 8Dh only: SynthMinder runs from, or beside, the owner's disks.
- `SENTENCE`, `MODEL` and `DEMO` use no screen, ports or DOS calls, so they're unit tested on any OS. Keep it so.
- **Turbo Pascal 7's limits:** lines under 120 characters (it stops at 126; CI checks), strings of 255, 64 KB of data. Large buffers go at unit level, not on the stack (16 KB).
- **`Crt` takes over `Output`**: `UseDosOutput` (SCREEN.PAS) puts it back for anything printed (`/STATUS`, `/V`, errors), so it can be redirected; `StartScreen` gives it to Crt again.
- **Release builds are Free Pascal**: Turbo Pascal 7's `Crt` gives runtime error 200 on CPUs over about 200 MHz. `FpuFix` must be the first unit (CI checks).
- Sources (`.PAS`, `.INC`, `.TXT`, `.BAT`) keep **CRLF** line endings (`.gitattributes`); after editing with tools that write LF, `sed -i 's/\r*$/\r/' FILE`.
- Code page 437 characters go in as `#nnn` codes, never as UTF-8 in the source.

## Building and testing

- `scripts/build.sh` builds `SYNMIND.EXE` and `TESTS.EXE` with Turbo Pascal 7 in DOSBox-X (no window), runs the tests, `/V`, `/DEMO /STATUS`, dumps the demo's five tabs, and checks a scripted session at the keyboard; `scripts/screen.py build/tp7/SOUND.BIN` prints one. Look at the screens after any change to the drawing code.
- `--run` opens the demo in a DOSBox-X window.
- CI (`.github/workflows/ci.yml`): the unit tests with Free Pascal on Linux, the DOS build with an FPC i8086-msdos cross compiler, a smoke test in DOSBox, and a release zip. Tag `vX.Y.Z` matching `VERSION.INC` for a draft release.

## Versioning

SemVer in `VERSION.INC` (`AppVersion`). Add a `CHANGELOG.md` entry under `[Unreleased]` (Keep a Changelog) with each notable change, and keep `scripts/check-version.sh` passing. Releases are cut with `scripts/release.sh <major|minor|patch|X.Y.Z>` (sets the version, dates the changelog, commits and tags; pushes nothing); BUILD.md has the steps.
