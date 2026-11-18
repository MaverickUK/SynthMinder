# The SynthMinder protocol

**Status: version 1, implemented by the firmware (host-tested; not yet run on a PC).** The reference copy is now HDDSynthPro's [`docs/synthminder-protocol.md`](https://github.com/MaverickUK/HDDSynthPro/blob/main/docs/synthminder-protocol.md) (IDE Synth Bay 0.36.0-dev.1, with HDD Synth firmware 0.25.0), which also says where the firmware differs from this draft in the details. This copy stays in step, since `DEMO.PAS` and `tests/TESTS.PAS` follow it.

```
SYNMIND.EXE ──IDE: command 8Dh──▶ IDE Synth Bay ──Synth Link (UART)──▶ HDD Synth
            ◀── reply sectors ───               ◀── $HDS $HDP $HDK ───
```

SynthMinder talks to the Bay through a vendor-specific ATA command. Each request is one **sentence** in the HDD Synth's format (`$BODY*CS`, CS the XOR of BODY's characters in hex), and so is each line of the reply:

- **`$HD…` sentences** go to the synth: the Bay sends them on over the Synth Link unchanged, and returns what the synth answers. They are exactly the HDD Synth companion app's (`$HDQ`, `$HDC` → `$HDS`, `$HDP`, `$HDK`; HDDSynth_Native's README), so the synth has one protocol for both.
- **`$SB…` sentences** (Synth Bay) are for the Bay itself.

## The ATA command

| Register | SEND | RECEIVE |
|---|---|---|
| Features | `01h` | `02h` |
| Sector Count | `1` | `1` |
| LBA Low | `53h` (`S`) | `53h` |
| LBA Mid | `4Dh` (`M`) | `4Dh` |
| LBA High | protocol version, `1` | `1` |
| Device | either of the Bay's devices (`A0h` or `B0h`) | the same |
| Command | `8Dh` | `8Dh` |
| Protocol | PIO data-out, one sector | PIO data-in, one sector |

- `8Dh` is in ATA's vendor-specific range (80h-8Fh). The `S` `M` in LBA Low and Mid mark it as SynthMinder's: the Bay aborts (`ABRT`) an `8Dh` without them, any other Features value or version, so a stray `8Dh` from some other program does nothing. Firmware without SynthMinder support aborts it as an unknown command, which is how SynthMinder knows to say so.
- **SEND**: the Bay shows DRQ, SynthMinder writes the request sector, and the Bay shows BSY while it checks it and starts it (sends it to the synth, or runs it).
- **RECEIVE**: the Bay shows **BSY until the reply is ready**, then DRQ, and SynthMinder reads one sector. A reply that doesn't fit in one sector has the *more* flag set: SynthMinder sends RECEIVE again for the rest, up to 16 sectors. The Bay never holds IORDY for this: like a read, the wait is BSY.
- **How long:** the Bay answers within 1 s, whatever happens. A relayed request that the synth doesn't answer in 500 ms gets `$SBK,1,RELAY,ERR,nosynth`.
- RECEIVE with no request waiting answers `$SBK,1,REQUEST,ERR,none`.
- **Interrupts:** SynthMinder sets nIEN while it runs the command and clears it after, so the BIOS's IRQ 14 handler sees nothing it didn't ask for. The Bay raises INTRQ as for any command when nIEN is clear.
- **Disk caches:** SynthMinder asks SMARTDRV to write its cache out before each exchange (INT 2Fh, AX=4A10h, BX=1), so the cache can't start a write between its register writes.

### The sector

Both ways, 512 bytes:

| Offset | Size | |
|---|---|---|
| 0 | 4 | `SMND` |
| 4 | 1 | protocol version: `1` |
| 5 | 1 | flags: bit 0 *more* (a reply continues in the next RECEIVE) |
| 6 | 2 | sequence number, little-endian: SynthMinder counts its requests; a reply carries its request's |
| 8 | 2 | text length in bytes, little-endian, up to 496 |
| 10 | 6 | zero |
| 16 | 496 | text: sentences, each ending in a line feed (`0Ah`; a CR before it is ignored). A sentence is never split between sectors. |

A request holds one sentence (version 1). A reply holds as many as the answer needs.

## Sentences for the synth (relayed)

As the HDD Synth's companion protocol, version 1, unchanged:

| Request | Reply |
|---|---|
| `$HDQ,1,STATUS` | `$HDS,1,<firmware>,<state>,<packIndex>,<packCount>,<volume>,<balance>,<supercapMv>` |
| `$HDQ,1,PACKS` | `$HDP,1,<index>,<count>,<folder>,<name>,<kind>` for each pack (kind `M` modelled, `R` recorded; left out before synth v0.24.0) |
| `$HDQ,1,MODEL` | `$HDM,2,...` (the modelled drive) |
| `$HDC,1,VOL,<0-100>` | `$HDK,1,VOL,OK,` or `ERR,<reason>` |
| `$HDC,1,BAL,<0-100>` | `$HDK,1,BAL,...` |
| `$HDC,1,PACK,<index>` | `$HDK,1,PACK,...` (reasons `busy`, `demo`, `range`) |

The Bay knows how many lines each answer has (`STATUS` one, `PACKS` as many as `<count>`, a command one `$HDK`), so it doesn't wait out a timeout after the last one.

## Sentences for the Bay

### `$SBQ,1,STATUS`: how the Bay is set up

One `$SBV,1,<key>,<value>` per value. SynthMinder shows the keys it knows by name and any others as they come, so later firmware can add keys without a new version.

| Key | Value |
|---|---|
| `firmware` | e.g. `0.35.0` |
| `build` | `bb48_drive` or `pcb_drive` |
| `device0` | the hard disk image served, e.g. `ICL386MB.IMG`; `cdrom` with `device0 = cdrom`; `generated` or `welcome` |
| `device0_next` | the image `HDDSYNTH.INI` names, when it differs from `device0` (it's served from the next start) |
| `device1` | `none`, `cdrom`, or the image or folder |
| `disc` | the CD-ROM's disc, `-` for none |
| `bus` | the bus program and mode, in words, e.g. `PIO 3 data lane` |
| `seek_timing` | e.g. `off`, `synth 5400 rpm` |
| `card` | e.g. `SDIO high speed` |
| `link` | the Synth Link: `up`, `lost` or `off` |

### `$SBQ,1,FILES`: the images on the card

One `$SBF,1,<index>,<count>,<name>,<sizeKB>,<kind>` per file in the card's root that the Bay could serve: kind `H` for a hard disk image (`.IMG`), `C` for a CD-ROM image (`.ISO`, `.CUE`). Names are 8.3, in alphabetical order.

### `$SBQ,1,SETTINGS`: the settings SET can change

One `$SBS,1,<key>,<next>,<now>` per setting: `device1`, `cdrom`, `seek_timing`, `activity_link`, `write_behind`, `read_ahead`, `sd_high_speed`. `<next>` is what `HDDSYNTH.INI` says (from the next start), `<now>` what the Bay runs with. Firmware before IDE Synth Bay 0.36.0 answers `ERR,unknown`, and the Settings tab says so. The values each takes: the reference copy (HDDSynthPro's `docs/synthminder-protocol.md`).

Since IDE Synth Bay 0.36.0-dev.2 the list ends with four **shown only**: `bus`, `dma`, `mode` and `geometry` (SET refuses them with `key`: the PC must be right for each, so they're set in `HDDSYNTH.INI`). For them `<now>` is what runs: the bus program (`early`, `lane`, `ide_bus`, `table`), the DMA and PIO modes offered (`mdma2`, `pio3`), the CHS geometry IDENTIFY reports.

### `$SBC,1,DISC,<name>`: change the CD-ROM's disc

As console `M`: the drive reports the disc changing (removal, new media, unit attention), as if the disc had been swapped. `-` ejects. Reply `$SBK,1,DISC,OK,` or `ERR,` with `nocdrom` (no CD-ROM drive set up), `notfound`, `busy`.

### `$SBC,1,SET,<key>,<value>`: change a setting in `HDDSYNTH.INI`

As console `E`: the file is rewritten with that one setting changed, and it takes effect at the next start, never at once (the PC is running from the disk). `device0` (an image on the card), and since IDE Synth Bay 0.36.0 every key SETTINGS lists; reply `$SBK,1,SET,OK,` or `ERR,` with `key` (not allowed), `value` (not a value it takes), `notfound`, `card`.

### Errors

A request that isn't a valid sentence: `$SBK,1,REQUEST,ERR,invalid`. One the Bay doesn't know: `$SBK,1,<its first field>,ERR,unknown`. Values never contain `,`, `*` or `$`: the Bay replaces them with `_`, as the synth does in pack names.

## The FDD Synth Duo: sentences over the floppy cable

*Built: FDD Synth Duo 0.25.0-dev.1 (FDDSynthPro, branch `synthminder-mailbox`). The reference is its [`docs/synthminder.md`](https://github.com/MaverickUK/FDDSynthPro/blob/synthminder-mailbox/docs/synthminder.md).*

The Duo takes no command: SynthMinder goes through its **mailbox at cylinder 82**, head 0, with the BIOS (`FLOPPY.PAS`). It writes the request to sector 1 (INT 13h, AH=03h) and reads the reply from sectors 5-9 (AH=02h), again until they carry the request's sequence number. The sectors are the same 512-byte SMND sectors as the IDE command's, but a reply has up to five of them in one read.
- **Finding it only reads.** The reply sectors hold `$FDK,1,HELLO,OK,` (sequence 0) from power-on. A real drive's disk has no track 82, so SynthMinder never writes to one.
- **SMARTDRV** caches the BIOS's floppy reads too, so SynthMinder has it forget them (INT 2Fh, AX=4A10h, BX=2) before each read of a reply.
- **Disk changes:** before a swap, DOS writes out its buffers (INT 21h, AH=0Dh). After one, or when SynthMinder's own INT 13h call was the first to hear of a change (status 06h), DOS is told to rebuild the drive's parameter block (INT 21h, AH=32h, its flag byte set to FFh), so it reads the new disk.

| Request | Reply |
|---|---|
| `$FDQ,1,STATUS` | `$FDV,1,<key>,<value>`: `firmware`, `drives` (`A`, `AB`), `mailbox`, `volume`, `pack`, `pack_index`, and per drive (`a_`, `b_`) `disk` (`-` for none), `kb`, `format`, `cylinder`, `motor`, `protect` |
| `$FDQ,1,FILES,<from>` | `$FDF,1,<index>,<count>,<name>,<KB>,<kind>` from image `<from>`, as many as fit; SynthMinder asks again from the next. Kind `I` sectors, `H` flux (HFE), `A` Amiga |
| `$FDQ,1,PACKS` | `$FDP,1,<index>,<count>,<name>` |
| `$FDQ,1,SETTINGS` | `$FDS,1,<key>,<next>,<now>`: `drive`, `device0`, `device1` |
| `$FDC,1,INSERT,<A\|B>,<name>` | `$FDK,1,INSERT,OK,`; the swap of the mailbox's own drive waits until the head leaves cylinder 82 (SynthMinder seeks to cylinder 0 after it) |
| `$FDC,1,EJECT,<A\|B>` | `$FDK,1,EJECT,OK,` |
| `$FDC,1,PACK,<index>`, `$FDC,1,VOL,<0-100>` | `$FDK,1,PACK,...`, `$FDK,1,VOL,...` |
| `$FDC,1,SET,<key>,<value>` | `$FDK,1,SET,...`: `drive` (`a`, `b`, `a,b`), `device0`, `device1` (an image, or `-`) |

Reasons for `ERR`: `notfound`, `nodrive`, `busy`, `empty`, `range`, `key`, `value`, `card`; `$FDK,1,REQUEST,ERR,invalid` and `$FDK,1,<first word>,ERR,unknown` as the Bay's.

## What the firmware needed

*Built: IDE Synth Bay 0.36.0-dev.1 (HDDSynthPro, branch `synthminder`) and HDD Synth 0.25.0 (HDDSynth_Native, branch `synthminder-link`). The firmware's limits and differences from this draft are in the reference copy. In short: a CD-ROM alone (`device0 = cdrom`) refuses 8Dh; a reply holds up to about 34 packs; SET can also answer `card`.*

**IDE Synth Bay** (HDDSynthPro):
- `ata_device`: command `8Dh` with the checks above; SEND as a PIO data-out of one sector, RECEIVE as a PIO data-in, each handed to core 0 like a `Fetch` (a new kind), BSY meanwhile. Core 1 does nothing slow, holds no IORDY, and nothing in it needs to be more than a few instructions. On every bus program that serves PIO; check the register table's data blocks and the data lane.
- Core 0: parse the request, answer `$SB…` itself (`STATUS` from what `S` prints; `FILES` by listing the card's root once and caching it; `DISC` as `M`; `SET` as `E`), relay `$HD…` over the link's TX, between `$HDA`/`$HDE` sentences, and collect the synth's replies from RX beside the `$HDM` it already reads.
- A rig test: the sentences through the adapter's pass-through on the Mac (no ATA pass-through) or Windows (`IOCTL_ATA_PASS_THROUGH`), and SynthMinder on the Evesham.

**HDD Synth** (HDDSynth_Native): answer `$HDQ` and `$HDC` arriving on the link UART (J6) as it does on USB, with the replies sent back on the link's TX (J6 pin 4, the wire that carries `$HDM`). Today `runHostCommand` replies only through `usbhost::send`.

**FDD Synth Duo** (FDDSynthPro): the mailbox at cylinder 82 above, built in 0.25.0-dev.1 (branch `synthminder-mailbox`), host-tested with a virtual PC; not yet tried on a PC.
