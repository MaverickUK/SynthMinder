# SynthMinder's design

SynthMinder shows how the HDD Synth, the IDE Synth Bay and the FDD Synth Duo are set up, and changes what can be changed, from the DOS PC they're fitted to. It's GameMinder's sibling: the same PathMinder-style screen, the same Classic colours, Turbo Pascal 7 and Free Pascal.

The mock-ups that chose the style (and the two that weren't chosen, Commander and Setup), and the ones that chose the tabs (a tab for each thing that changes, over one screen with pop-ups, or the Synth and Bay tabs tidied), are on the [design canvas](https://claude.ai/artifact/KtBFvDVx1h6BGm6M7ZV3gx).

## The screen

```
Sound  Floppy  Hard disk  CD-ROM  Settings  Exit              SynthMinder v0.2.0
The synths' sound: the HDD Synth's and the Duo's sample packs and volume
╒══════════════════════════════════════╤═══════════════════════════════════════╕
│ HDD Synth packs                    6 │ HDD Synth                             │
│   Desktop 3.5in 1993        recorded │ Playing     Voice coil 1997           │
│   Stepper 1985              modelled │ Volume      ████████████░░░░░░░░ 60   │
│   Voice coil 1991           modelled │ Balance     L ─────────■─────── R 55  │
│ ► Voice coil 1997           modelled │ State       Running                   │
│                                      │                                       │
│ FDD Synth Duo packs                2 │ FDD Synth Duo                         │
│ ► Recorded                           │ Playing     Recorded                  │
│   Placeholder                        │ Volume      ███████████████░░░░░ 75   │
│                                      │                                       │
│                                      │ Voice coil 1991                       │
│                                      │ Sound       modelled                  │
│                                      │ Enter plays it on the HDD Synth now   │
╘══╡ Bay on the primary master ╞═══════╧═══════════════════════════════════════╛
 F1 Help  Enter Play  +/- Volume  </> Balance  Esc Exit
```

- **Row 1** is the menu: Left and Right choose (Tab goes round the tabs too). There's a tab for each thing that changes, the drives in DOS's order:

  | Tab | The list | Enter |
  |---|---|---|
  | **Sound** | the HDD Synth's sample packs, then the Duo's | plays the pack, on its synth |
  | **Floppy** | the Duo's disk images: 3.5in, 5.25in, other | puts it in a drive, now |
  | **Hard disk** | the Bay's hard disk images | makes it the hard disk, from the PC's next reset |
  | **CD-ROM** | the Bay's CD-ROM images | puts it in the drive, now |
  | **Settings** | each device's settings, grouped by device | changes it, from the next power-on |

- **The left panel** is the tab's list. `►` marks what's in use now: the pack playing, the disk DOS runs from, the disc in the drive. On Floppy, the drive letter marks the drive a disk is in, as there may be two.
- **The right panel** reads the same way on each tab: what's in use now (each synth's pack and volume; each floppy drive's disk; the hard disk and the one waiting for the reset; the disc), then the highlighted item and what Enter does to it. On Settings, the highlighted setting, then the details of its device: firmware, state and the rest. Values a device sends that this version doesn't know are shown there as they come.
- **Each device's things are in one place:** no tab repeats another's. Firmware, the bus, the SD card, the supercap and the Synth Link are on Settings, away from the everyday tabs.
- **The bottom of the frame** says where the Bay was found (the Duo, on Floppy), or *Demo*, and how the last change went.
- **The last row** lists the tab's keys. On Sound they're for the synth whose pack is highlighted: with a Duo pack, `+` `-` are the Duo's volume (it has no balance).
- **`R` asks everything again**, and looks for the Duo if it hasn't been found. It's listed in help, not on the menu.

## What can change, and when

| What | How | When |
|---|---|---|
| A synth's volume | Sound: `+` `-` (5 at a time), with one of its packs highlighted | at once; the HDD Synth remembers it as if its knob had turned |
| The HDD Synth's balance | Sound: `<` `>` | at once |
| A synth's pack | Sound: Enter on a pack | at once (the HDD Synth spins the new pack up: about a second) |
| A floppy | Floppy: Enter on an image (`A` or `B` for a drive); `E` ejects | at once, as if the disk had been changed: a second or so, through the disk |
| CD-ROM disc | CD-ROM: Enter on an image; `E` ejects | at once, as if the disc had been changed; with a confirmation |
| The hard disk (device 0) | Hard disk: Enter on an image | **from the PC's next reset** (the reset button or power-on; IDE Synth Bay 0.36.0-dev.4: older firmware, the Bay's next start), with a confirmation: DOS is running from the current one, so it can't change underneath it. SynthMinder shows it as *Next reset* until then |
| The Bay's and the Duo's settings | Settings: Enter on a setting | from the next power-on. The bus's (the bus program, DMA, the mode, the geometry) are shown only: the PC must be right for them, so HDDSYNTH.INI sets them |

SynthMinder never restarts the Bay: the PC is running from it.

## The FDD Synth Duo

The mock-ups that first drew it, as a Floppy tab holding its sound too, are on the [Floppy tab canvas](https://claude.ai/artifact/B5nTmhbA4wwChe4Vxqzz7z). Its sound is now on the Sound tab, beside the HDD Synth's, and its details on Settings.

```
Sound  Floppy  Hard disk  CD-ROM  Settings  Exit              SynthMinder v0.2.0
The FDD Synth Duo's drives: change a disk now, as if by hand
╒══════════════════════════════════════╤═══════════════════════════════════════╕
│ 3.5in disks                        6 │ Drive A:                              │
│   DOS622_1.IMG               1.44 MB │ Disk        GAMES.IMG                 │
│ A GAMES.IMG                  1.44 MB │ Format      1440 KB MFM 300 rpm       │
│   MONKEY1.IMG                 720 KB │ Motor       off                       │
│ 5.25in disks                       2 │                                       │
│   ELITE.IMG                   360 KB │ Drive B:                              │
│ Other disks                        1 │ Disk        none                      │
│   WB13.ADF                    880 KB │                                       │
│                                      │ DOS622_1.IMG                          │
│                                      │ Size        1.44 MB                   │
│                                      │ Enter, or A or B, puts it in a drive  │
╘══╡ Duo on drives A: and B: (cylinder 82) ╞═════════════════════════════════════╛
 F1 Help  Enter Insert  A/B Into A:/B:  E Eject  Esc Exit
```

- **The left panel** lists the images on the Duo's card under 3.5in, 5.25in and Other (by size and kind). A letter marks the drive an image is in.
- **The right panel** shows each of the Duo's drives, and the highlighted image.
- **Enter** puts the disk in at once: a floppy is removable, so unlike the Bay's hard disk there's no waiting for the next boot. With two drives it asks which, and `A` or `B` pick one straight away. Swapping the disk SynthMinder itself runs from asks first. `E` takes a disk out.
- **Each change takes a second or so:** the request goes through the disk, and SynthMinder waits for the swap, then asks again. Before the swap DOS writes out its buffers; after it, DOS is told to read the disk afresh.
- **Looking for the Duo** takes a second or two, so with a Bay SynthMinder looks only when the Floppy tab is first opened, or on `R`. Until then the Sound tab says it hasn't looked. With no Bay it looks at start, and opens on the Floppy tab.
- **The Duo needs a disk in to be found:** a BIOS won't read a drive whose disk it hasn't recognised (the Evesham's recalibrates and reads at cylinder 0 first), so an empty Duo can't be reached through it. The Floppy tab says to put one in from the Duo's panel, and ejecting the disk SynthMinder talks through warns first. Doing the exchange with the floppy controller and DMA directly, without the BIOS, would lift this (the roadmap).
- The Settings tab has the Duo's drives and the disk each starts with, from the next power-on, and its firmware, mailbox and exchange time.

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
