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
| `SYNTH.BIN`, `BAY.BIN` | the demo's two screens, from `SYNMIND /DEMO /DUMP=SYNTH` and `/DUMP=BAY` |

To see a screen: `scripts/screen.py build/tp7/SYNTH.BIN` (text), or with `--html` (in its colours).

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

## Releasing

1. Update `AppVersion` in [VERSION.INC](VERSION.INC) (e.g. `0.1.0`, or `0.1.0-beta.1`).
2. Move the `Unreleased` changes in [CHANGELOG.md](CHANGELOG.md) under that version and date.
3. Check they match: `scripts/check-version.sh`
4. Commit, tag `vX.Y.Z` and push the tag; the release workflow makes a draft release with the zip.
