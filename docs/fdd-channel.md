# Talking to the FDD Synth Duo over the floppy cable: ideas

**Status: ideas, for later.** Nothing is built. To design with [FDDSynthPro](https://github.com/MaverickUK/FDDSynthPro) (the FDD Synth Duo) before SynthMinder grows its third tab.

## The problem

SynthMinder talks to the IDE Synth Bay with a command of its own (ATA command 8Dh): an IDE drive is a small computer that takes commands, so a private one costs nothing. A floppy drive takes none. The PC's floppy controller (a uPD765 or one of its clones) holds the commands; the cable carries only pulses and levels:

- PC to drive: drive select, motor on, step, direction, side, density, write gate, write data.
- Drive to PC: index, track 0, write protect, disk change (or ready), read data.

So there's no vendor command to borrow. What does reach the drive is **sector data**: the FDD Synth Duo already decodes the PC's writes to update its images, and builds the read data itself.

## A mailbox in sectors

As the HxC and FlashFloppy emulators let a utility on the PC choose disk images:

1. SynthMinder writes a request sector: a signature (like IDE's `SMND` header), a sequence number, the sentences (the same `$HDQ`/`$HDC` for the synth, and `$FDQ`/`$FDC`-style ones for the drive).
2. The Duo recognises it as it decodes the write, acts on it, and puts its reply in a sector there.
3. SynthMinder reads the reply back, checking the sequence number so a stale reply isn't taken for a new one.

Through the BIOS (INT 13h, functions 02h and 03h) directly, not DOS files, so DOS's buffers and disk caches can't get in the way.

## Where the mailbox lives

- **A reserved cylinder, on whichever drive the Duo serves (the general answer).** Past the end of the disk, say cylinder 82 on an 80-track disk. The Duo emulates the head, so it knows when the PC is there, and it answers reads and writes at that cylinder itself, never passing them to the image. It works with one drive or two, as A or B, whatever image is inserted, and never touches the user's disk.
- **A virtual control drive in the free slot (a convenience).** The Duo can answer as two drives at once; when it serves only one disk, drive B could be a tiny disk that is only the mailbox. Works with no disk in drive A. But a PC's cable carries only two drives: with the Duo serving two real disks there is no slot left, so this can't be the only way.

## To settle when designing it

- **No disk inserted.** A real drive with no disk gives no index pulses, so the controller times out before reading. The Duo could keep the mailbox working by answering at the reserved cylinder even when empty: with care, so DOS doesn't conclude a disk has appeared (the disk change line).
- **BIOSes that check the cylinder.** Most pass a cylinder past the disk's size straight to the controller; some may check it against their drive table and refuse. If so, SynthMinder could program the controller itself for those exchanges (its ports at 3F0h-3F7h, and DMA channel 2), which is more work but sidesteps the BIOS.
- **The signature and the sequence**, as on IDE, so a stray write there (a disk tool scanning every cylinder) is ignored, and a reply is told apart from the last.
- **Which cylinder, per disk type**: 82 suits 80-track disks; a 40-track 5.25-inch disk would use 42 or so.
- **Two Duos, or a Duo beside a real drive**: how SynthMinder finds the Duo (a probe read of the reserved cylinder on A and on B).

## The cost: speed

Every exchange waits for the disk to come round: a revolution is 200 ms at 300 rpm, plus the motor's spin-up if it was off. A write and a read make an exchange of a few tenths of a second: fine for a settings screen, nothing like IDE's milliseconds.

## Other ways, and why not first

- **Through the Bay.** In a PC with both, the Bay already talks to SynthMinder and could pass messages to the Duo over a UART like the Synth Link. Fast, but only with a Bay fitted and an extra cable.
- **The control lines** (patterns of step and direction pulses one way; track 0, write protect or disk change read back through the controller's Sense Drive Status). Possible in theory; needs low-level programming of the controller, is very slow, and differs from controller to controller.
- **A Synth Link of its own.** Only if the Duo should drive a separate HDD Synth; with its synth built in, it doesn't need one for its sounds.
