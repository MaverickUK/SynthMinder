# Building SynthMinder

SynthMinder builds with **Turbo Pascal 7** (local builds) or **Free Pascal** (releases and CI), as GameMinder does.

> **Release builds use Free Pascal.** Turbo Pascal 7's `Crt` unit stops with runtime error 200 on CPUs faster than about 200 MHz (the Evesham's Athlon XP among them). Turbo Pascal builds are for DOSBox-X and slow PCs.

## Turbo Pascal 7, in DOSBox-X

```
scripts/build.sh          # build, run the unit tests and the demo's checks
scripts/build.sh --run    # then open SYNMIND /DEMO in a DOSBox-X window
```

It runs Turbo Pascal inside DOSBox-X without a window (needs `dosbox-x`, and Turbo Pascal in `C:\TPWDB` or `TP_DIR`) and leaves everything in `build/tp7/`:

| File | |
|---|---|
| `SYNMIND.EXE`, `TESTS.EXE` | the programs |
| `BUILD.LOG` | the compiler's output |
| `TESTS.TXT` | the unit tests' results |
| `STATUS.TXT` | `SYNMIND /DEMO /STATUS` |
| `NOBAY.TXT` | `SYNMIND` with no Bay (DOSBox-X has none) |
| `SOUND.BIN`, `FLOPPY.BIN`, `HARDDISK.BIN`, `CDROM.BIN`, `SETTINGS.BIN` | the demo's tabs, from `SYNMIND /DEMO /DUMP=SOUND` and so on |
| `KEYS.BIN`, `KEYS1.BIN` to `KEYS5.BIN` | after a scripted session at the keyboard: the screen it left, then each tab (`/DUMP=EXIT`), which the build checks for the session's changes |

To see a screen: `scripts/screen.py build/tp7/SOUND.BIN` (text), or with `--html` (in its colours).

## The README's demo

`scripts/record-demo.sh path/to/SYNMIND.EXE` records `SYNMIND /DEMO` in DOSBox-X (keys typed by its `AUTOTYPE`, the screen by `DX-CAPTURE`, no window unless `--show`) and writes `docs/synthminder-demo.gif` and `.mp4` with ffmpeg. Use a Free Pascal build, from a CI run: `gh run download <run-id> -n synmind-dos`. To change what it shows, edit the script's `keys` line.

In DOS itself, from the repository's directory:

```
TPC /M SYNMIND.PAS
TPC /M TESTS\TESTS.PAS
```

Turbo Pascal 7 takes lines of up to 126 characters; keep source lines under 120.

## Free Pascal

The [CI workflow](.github/workflows/ci.yml) has the full steps:

1. The unit tests, natively (Linux, macOS or Windows):
   ```
   mkdir -p build
   fpc -Mtp -Fu. -FUbuild -obuild/tests tests/TESTS.PAS
   build/tests
   ```
2. `SYNMIND.EXE` with an i8086-msdos cross compiler, built from the FPC 3.2.2 source as GameMinder's BUILD.md describes:
   ```
   ppcross8086 -Tmsdos -WmLarge -Mtp -O2 -Fu. -Fu$UNITS/* -FUbuild/dos -obuild/dos/SYNMIND.EXE SYNMIND.PAS
   ```

## Line endings

The Pascal sources, `VERSION.INC` and text files keep CRLF line endings on every platform (`.gitattributes`), so they work as they are when copied to a DOS PC.

## Versions and the changelog

SynthMinder follows [Semantic Versioning](https://semver.org): `AppVersion` in [VERSION.INC](VERSION.INC) is the one place the version lives. Before 1.0.0, a minor version may change the protocol or the command line; a patch version only fixes.

Every change worth mentioning gets a line under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md) ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/): Added, Changed, Deprecated, Removed, Fixed, Security), in the same pull request. CI runs `scripts/check-version.sh` on every push and pull request.

## Releasing

```
scripts/release.sh minor           # or major, patch, or a version: 0.2.0, 0.2.0-beta.1
git push --atomic origin main v0.2.0
```

From a clean `main`, `release.sh` sets `VERSION.INC`, moves the Unreleased changes under the new version and today's date, updates the changelog's compare links, commits `Release X.Y.Z` and tags `vX.Y.Z`. It pushes nothing, so the commit can still be checked (`git show`) or undone (`git tag -d vX.Y.Z && git reset --hard HEAD~1`).

Pushing the tag runs the [release workflow](.github/workflows/release.yml): the whole CI again, then, if the tag is on `main` and matches `VERSION.INC`, a **draft** GitHub release with `SynthMinder-X.Y.Z.zip`, `SHA256SUMS` and that version's changelog section as its notes. A version with a pre-release part (`-beta.1`) is marked as a pre-release. Review the draft on GitHub, then publish it.
