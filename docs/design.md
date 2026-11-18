# SynthMinder's design

SynthMinder shows how the HDD Synth, the IDE Synth Bay and the FDD Synth Duo are set up, and changes what can be changed, from the DOS PC they're fitted to. It's GameMinder's sibling: the same PathMinder-style screen, the same Classic colours, Turbo Pascal 7 and Free Pascal.

The mock-ups that chose the style (and the two that weren't chosen, Commander and Setup) are on the [design canvas](https://claude.ai/artifact/KtBFvDVx1h6BGm6M7ZV3gx).

## The screen

```
Synth  Bay  Refresh  Exit                               SynthMinder v0.1.0
The HDD Synth: its sample pack, volume and balance
╒══════════════════════════════════════╤═══════════════════════════════════════╕
│ Sample packs                       6 │ HDD Synth                             │
│   Desktop 3.5in 1993               R │ Firmware    v0.24.0                   │
│   Stepper 1985                     M │ State       Running                   │
│ ♫ Voice coil 1997                  M │ Volume      ████████████░░░░░░░░ 60   │
│                                      │ Balance     L ─────────■─────── R 55  │
│                                      │ IDE Synth Bay                         │
│                                      │ Device 0    ICL386MB.IMG              │
│ ♫ playing now                        │ Device 1    CD-ROM: DOOM_SE.ISO       │
│ M modelled   R recorded              │ Synth Link  up                        │
╘══╡ Bay on the primary master ╞═══════╧═══════════════════════════════════════╛
 F1 Help  Enter Play pack  +/- Volume  </> Balance  R Refresh  Esc Exit
```

- **Row 1** is the menu: Left and Right choose. **Synth** and **Bay** are tabs: they choose what the panels show. **Refresh** and **Exit** act on Enter.
- **The left panel** is a list: the synth's packs, or the images on the Bay's card (hard disk images, then CD-ROM images, each under a heading). Enter acts on the highlighted one.
- **The right panel** shows the details: the synth and the Bay on the Synth tab; the highlighted image, then the Bay, on the Bay tab. Values the Bay sends that this version doesn't know are shown as they come.
- **The bottom of the frame** says where the Bay was found (or *Demo*), and how the last change went.
- **The last row** lists the keys for the tab.

## What can change, and when

| What | How | When |
|---|---|---|
| Synth volume | `+` `-` (5 at a time) | at once; the synth remembers it as if its knob had turned |
| Synth balance | `<` `>` | at once |
| Synth pack | Enter on a pack | at once (the synth spins the new pack up: about a second) |
| CD-ROM disc | Enter on a CD image; `E` ejects | at once, as if the disc had been changed; with a confirmation |
| The hard disk (device 0) | Enter on a disk image | **from the next power-on**, with a confirmation: DOS is running from the current one, so it can't change underneath it. SynthMinder shows it as *Next boot* until then |
| The Bay's other settings | not in version 1 | they all apply at a restart, and most need knowing the PC (the bus program, DMA): later, with care |

SynthMinder never restarts the Bay: the PC is running from it.

## The Floppy tab: the FDD Synth Duo

The mock-ups are on the [Floppy tab canvas](https://claude.ai/artifact/B5nTmhbA4wwChe4Vxqzz7z).

```
Synth  Bay  Floppy  Settings  Refresh  Exit                     SynthMinder v0.3.0
The FDD Synth Duo: its disks and its sound
╒══════════════════════════════════════╤═══════════════════════════════════════╕
│ 3.5in disks                        6 │ FDD Synth Duo                         │
│ A  GAMES.IMG                 1.44 MB │ Firmware    0.25.0                    │
│    MONKEY1.IMG                720 KB │ Drives      A: (one drive)            │
│ 5.25in disks                       2 │ Mailbox     A:, cylinder 82           │
│    ELITE.IMG                  360 KB │ Exchange    0.4 s                     │
│ Sound packs                        2 │ Volume      ███████████████░░░░░ 75   │
│ ♫  Recorded                          │ Drive A:                              │
│    Placeholder                       │ Disk        GAMES.IMG                 │
│ A in drive A:   ♫ playing now        │ Format      1440 KB MFM 300 rpm       │
╘══╡ Duo on drive A: (cylinder 82) ╞═══╧═══════════════════════════════════════╛
 F1 Help  Enter Insert  E Eject  +/- Volume  R Refresh  Esc Exit
```

- **The left panel** lists the images on the Duo's card under 3.5in, 5.25in and Other (by size and kind), then its sample packs. A letter marks the drive an image is in; ♫ the pack playing.
- **The right panel** shows the Duo, each of its drives, and the highlighted image.
- **Enter** puts the disk in at once: a floppy is removable, so unlike the Bay's hard disk there's no waiting for the next boot. With two drives it asks which, and `A` or `B` pick one straight away. Swapping the disk SynthMinder itself runs from asks first. `E` takes a disk out; Enter on a pack plays it; `+` `-` set the Duo's volume.
- **Each change takes a second or so:** the request goes through the disk, and SynthMinder waits for the swap, then asks again. Before the swap DOS writes out its buffers; after it, DOS is told to read the disk afresh.
- **Looking for the Duo** takes a second or two, so with a Bay SynthMinder looks only when the Floppy tab is first opened. With no Bay it looks at start, and opens on the Floppy tab.
- **The Duo needs a disk in to be found:** a BIOS won't read a drive whose disk it hasn't recognised (the Evesham's recalibrates and reads at cylinder 0 first), so an empty Duo can't be reached through it. The Floppy tab says to put one in from the Duo's panel, and ejecting the disk SynthMinder talks through warns first. Doing the exchange with the floppy controller and DMA directly, without the BIOS, would lift this (the roadmap).
- The Settings tab gains the Duo's drives and the disk each starts with, from the next power-on.

## Without a Bay

- `SYNMIND` with no Bay found looks for the Duo; with neither it says so and suggests `/DEMO`.
- A Bay whose firmware doesn't know the command says which Bay it found (model and firmware from IDENTIFY) and that it needs newer firmware.
- A Bay with no synth answering shows the Bay, and *Not answering* for the synth.
- `SYNMIND /DEMO` runs against a pretend Bay and synth (`DEMO.PAS`), which answer with the same sentences the real ones do. Changes last until SynthMinder exits.

## Units

| Unit | |
|---|---|
| `SYNMIND.PAS` | the program: command line, the tabs, dialogs, keys |
| `SCREEN.PAS` | the frame, footer, dialog boxes, cursor; the Classic colours |
| `LINK.PAS` | sends requests to the Bay, the Duo or the demo and takes in the replies |
| `IDE.PAS` | the IDE ports: finding the Bay (IDENTIFY), the SynthMinder command |
| `FLOPPY.PAS` | the floppy drives, through the BIOS: finding the Duo (reading its hello), the mailbox at cylinder 82, telling DOS a disk changed |
| `MODEL.PAS` | what's known about the synth, the Bay and the Duo, from their sentences |
| `SENTENCE.PAS` | making and checking sentences |
| `DEMO.PAS` | the pretend Bay, synth and Duo |
| `FPUFIX.PAS` | Free Pascal on PCs without an FPU (from GameMinder) |

`SENTENCE`, `MODEL` and `DEMO` don't use the screen or the ports, so they're unit tested on any OS.

## Later

- **Themes** from GameMinder's `THEMES.TXT`, and 43/50-line screens.
- **Command-line changes** for batch files: `SYNMIND /VOL=60`, `/PACK=3`, `/DISC=QUAKE.ISO`.
- **More of the Bay's settings**, read-only first.
