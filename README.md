# SynthMinder

## See and change your HDD Synth and IDE Synth Bay from DOS

SynthMinder runs on the DOS PC an [IDE Synth Bay](https://github.com/MaverickUK/HDDSynthPro) is fitted to. It shows how the Bay and the [HDD Synth](https://github.com/MaverickUK/HDDSynth_Native) behind it are set up (the synth's sample packs, volume and balance, the Bay's disk and CD-ROM images), and changes what can be changed: the synth's pack, volume and balance, the CD in the Bay's CD-ROM drive, and the Bay's hard disk for the next power-on.

It's [GameMinder](https://github.com/MaverickUK/GameMinder)'s sibling: the same PathMinder-style screen and colours.

```
Synth  Bay  Refresh  Exit                               SynthMinder v0.1.0-dev.1
The HDD Synth: its sample pack, volume and balance
╒══════════════════════════════════════╤═══════════════════════════════════════╕
│ Sample packs                       6 │ HDD Synth                             │
│   Desktop 3.5in 1993               R │ Firmware    v0.24.0                   │
│   Laptop 2.5in 1996                R │ State       Running                   │
│   Server SCSI 1995                 R │ Pack        Voice coil 1997           │
│   Stepper 1985                     M │ Volume      ████████████░░░░░░░░ 60   │
│   Voice coil 1991                  M │ Balance     L ─────────■─────── R 55  │
│ ♫ Voice coil 1997                  M │ Supercap    5.08 V                    │
│                                      │                                       │
│                                      │ IDE Synth Bay                         │
│                                      │ Firmware    0.35.0 (pcb_drive)        │
│                                      │ Device 0    ICL386MB.IMG              │
│                                      │ Device 1    CD-ROM: DOOM_SE.ISO       │
│                                      │ Bus         PIO 3 data lane           │
│                                      │ Seek timing synth 5400 rpm            │
│                                      │ SD card     SDIO high speed           │
│                                      │ Synth Link  up                        │
│                                      │                                       │
│                                      │                                       │
│ ♫ playing now                        │                                       │
│ M modelled   R recorded              │                                       │
╘══╡ Demo: a pretend Bay and synth ╞═══╧═══════════════════════════════════════╛
 F1 Help  Enter Play pack  +/- Volume  </> Balance  R Refresh  Esc Exit
```

**Status: 0.1.0 in development.** The screens work against a pretend Bay and synth (`SYNMIND /DEMO`). The Bay's firmware doesn't answer SynthMinder yet: that's the next step ([ROADMAP.md](ROADMAP.md)).

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

| Key | |
|---|---|
| Left, Right | the menu: **Synth**, **Bay**, Refresh, Exit |
| Up, Down, PgUp, PgDn | the list |
| Enter | Synth: play the highlighted pack. Bay: put a CD image in the CD-ROM drive, or make a disk image the hard disk from the next power-on |
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
