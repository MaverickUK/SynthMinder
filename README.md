# SynthMinder

[![CI](https://github.com/MaverickUK/SynthMinder/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/MaverickUK/SynthMinder/actions/workflows/ci.yml)
[![Version](https://img.shields.io/github/v/tag/MaverickUK/SynthMinder?include_prereleases&sort=semver&label=version)](https://github.com/MaverickUK/SynthMinder/tags)

## See and change your HDD Synth and IDE Synth Bay from DOS

SynthMinder runs on the DOS PC an [IDE Synth Bay](https://github.com/MaverickUK/HDDSynthPro) is fitted to. It shows how the Bay and the [HDD Synth](https://github.com/MaverickUK/HDDSynth_Native) behind it are set up (the synth's sample packs, volume and balance, the Bay's disk and CD-ROM images), and changes what can be changed: the synth's pack, volume and balance, the CD in the Bay's CD-ROM drive, and the Bay's hard disk for the next power-on.

It's [GameMinder](https://github.com/MaverickUK/GameMinder)'s sibling: the same PathMinder-style screen and colours.

[![SynthMinder demo: choosing a sample pack, the volume and balance, help, putting a CD image in the IDE Synth Bay's CD-ROM drive, and changing its settings](docs/synthminder-demo.gif)](docs/synthminder-demo.mp4)

*SynthMinder in DOSBox-X, against its pretend Bay and synth (`SYNMIND /DEMO`): playing another sample pack, turning the volume up and the balance right, help, the Bay tab (`QUAKE.ISO` put in the CD-ROM drive and taken out again), then the Settings tab: seek timing set to a 2005 drive's from the next boot, and write-behind's question, left as it was. [Watch as MP4](docs/synthminder-demo.mp4). Recorded by `scripts/record-demo.sh`.*

**Status: in development.** It runs against IDE Synth Bay firmware from its `synthminder` branch (0.36.0-dev) and the HDD Synth from its `synthminder-link` branch (0.25.0), and against a pretend Bay and synth (`SYNMIND /DEMO`). What's next: [ROADMAP.md](ROADMAP.md).

## How it works

SynthMinder finds the Bay on the PC's IDE bus and talks to it through a command of its own. The Bay answers for itself, and passes the synth's part on over the Synth Link, the wire between the two. The messages are the same ones the HDD Synth's USB companion app uses. Details: [docs/protocol.md](docs/protocol.md).

It needs plain DOS: under Windows, Windows' own disk driver owns the IDE ports. Boot to the command prompt first.

## Using it

```
SYNMIND           find the Bay and open SynthMinder
SYNMIND /DEMO     try it with a pretend Bay and synth
SYNMIND /STATUS   print what the Bay and synth say, and exit
SYNMIND /V        print the version
```

And for batch files, run in the order given, with no screen:

```
SYNMIND /DISC=QUAKE.ISO      put a CD image in the Bay's CD-ROM drive (/DISC=- takes it out)
SYNMIND /PACK=3              play a sample pack, by number, folder or name (/PACK=fdb05)
SYNMIND /VOL=60 /BAL=50      the synth's volume and balance, 0-100
SYNMIND /Q ...               no messages, just the ERRORLEVEL
```

The ERRORLEVEL: 0 done, 1 a bad option, 2 no Bay found (or it didn't answer), 3 refused (no such image or pack, no CD-ROM drive set up), 4 no HDD Synth on the Synth Link. A game's batch file can start with `SYNMIND /DISC=QUAKE.ISO /Q`, so the right CD is in the drive before the game asks for it.

| Key | |
|---|---|
| Left, Right | the menu: **Synth**, **Bay**, **Settings**, Refresh, Exit |
| Tab | the next of Synth, Bay and Settings |
| Up, Down, PgUp, PgDn | the list |
| Enter | Synth: play the highlighted pack. Bay: put a CD image in the CD-ROM drive, or make a disk image the hard disk from the next power-on. Settings: change the highlighted setting, from the next power-on |
| `+` `-` | synth volume |
| `<` `>` | synth balance |
| `E` | take the disc out of the CD-ROM drive |
| `R` | ask again |
| F1 | help |
| Esc | exit |

## More

- [Design](docs/design.md): the screen, and what changes when
- [Protocol](docs/protocol.md): SynthMinder, the Bay and the synth
- [Building and testing](BUILD.md)
- [Roadmap](ROADMAP.md) and [changelog](CHANGELOG.md)

SynthMinder follows [Semantic Versioning](https://semver.org). GPL-3.0, as GameMinder.
