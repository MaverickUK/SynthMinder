Unit Floppy;
{-----------------------------
Talking to the FDD Synth Duo through the BIOS's floppy functions

The floppy cable carries no commands, so the Duo keeps a mailbox
at cylinder 82, head 0, past the end of an 80-track disk
(FDDSynthPro's docs/synthminder.md):

  1. SynthMinder writes the request to sector 1 (INT 13h, AH=03h):
     the same SMND sector as the IDE command.
  2. The Duo answers as it decodes the write, into sectors 5-9.
  3. SynthMinder reads sectors 5-9 (AH=02h). If they still carry
     the last sequence number, it reads them again: the next
     revolution.

Through the BIOS, not DOS files, so DOS's buffers can't get in the
way; SMARTDRV, which caches the BIOS's floppy reads too, is told to
forget them before each read of a reply.

SynthMinder never writes to a drive it hasn't found to be a Duo:
the Duo's reply sectors hold a hello from power-on, so finding it
(ProbeDuo) only reads. A real drive's disk has no track 82.

Disk changes: the BIOS reports a changed disk (06h) to whoever asks
first, and the change line clears when the head steps. If that's
SynthMinder, DOS would never hear of it, so SynthMinder then tells
DOS to read the disk afresh (TellDos).
------------------------------}

{ --------- interface -------- }
interface
uses
    Sentence;

const
  { Exchange results }
  FxOk = 0;
  FxNoDuo = 1;      { Nothing at cylinder 82: a real drive, or the Duo with a disk it can't serve the mailbox on }
  FxNoDisk = 2;     { The drive isn't ready: no disk in it, or no drive }
  FxTimeout = 3;    { The Duo didn't answer in time }
  FxBadReply = 4;
  FxRefused = 5;    { The BIOS wouldn't go to cylinder 82 }

  MaxFloppies = 2;

var
  DuoDrive: byte;          { The BIOS's drive the mailbox is on: 0 for A:, 1 for B: }
  ExchangeMs: longint;     { How long the last exchange took }
  FdcLog: string;          { What the last FdcSeekMailbox saw }
  { What FindDuo found on each drive: FxOk (the Duo), another Fx, or -1 (no drive) }
  ProbeResult: array[0..MaxFloppies - 1] of integer;

{ How many floppy drives the BIOS knows, from its equipment list }
function FloppyCount:integer;
{ Is the Duo on that drive? Only reads. FxOk if so }
function ProbeDuo(drive:byte):integer;
{ Looks on A: then B:, and sets DuoDrive. True if found }
function FindDuo:boolean;
function DuoExchange(request:string; var replies:TLines):integer;
{ Takes the head back to cylinder 0: the Duo swaps a disk it was asked
  to through the mailbox once the head has left it }
procedure DuoPark;
{ The head to cylinder 82 by the controller itself (see the implementation);
  FdcLog says how it went, for SYNMIND /FDSEEK }
procedure FdcSeekMailbox(drive:byte);
{ DOS writes out what it holds for the disks: before a disk is swapped }
procedure FlushDos;
{ DOS reads that drive's disk afresh: after a swap, or a change
  SynthMinder saw first. Only with a disk in: 0 for A:, 1 for B: }
procedure TellDos(drive:byte);
function DriveLetter(drive:byte):char;

{ --------- implementation --------- }
implementation
uses
    Dos;

const
  Cylinder = 82;
  RequestSector = 1;
  FirstReply = 5;
  ReplySectors = 5;
  SectorBytes = 512;
  ReplyBytes = ReplySectors * SectorBytes;
  HeaderSize = 16;
  TextMax = SectorBytes - HeaderSize;
  FlagMore = $01;
  ProtocolVersion = 1;
  ReadTries = 6;            { Revolutions to wait for the reply: 1.2 s at 300 rpm }

  { The floppy controller's ports (a uPD765 or a clone of it) }
  FdcDor = $3F2;    { digital output: motors, select, reset }
  FdcMsr = $3F4;    { main status }
  FdcData = $3F5;
  FdcSeek = $0F;
  FdcSenseInterrupt = $08;

  { BIOS status codes (AH after INT 13h) }
  BsBadCommand = $01;
  BsChanged = $06;
  BsTimeout = $80;

type
  TBuffer = array[0..ReplyBytes - 1] of byte;
  PBuffer = ^TBuffer;

var
  sequence:word;
  { The BIOS reads and writes by DMA, which can't cross a 64 KB boundary:
    the buffer is the part of this that doesn't }
  area:array[0..2 * ReplyBytes + 15] of byte;
  buf:PBuffer;
  bufSeg,bufOfs:word;
  changed:array[0..MaxFloppies - 1] of boolean; { The BIOS told us of a disk change DOS hasn't heard of }

function Ticks:longint;
begin
  Ticks := MemL[$40:$6C];
end;

function DriveLetter(drive:byte):char;
begin
  DriveLetter := chr(ord('A') + drive);
end;

procedure PlaceBuffer;
var
  start:longint;
begin
  start := longint(Seg(area)) * 16 + Ofs(area);
  if ( ( start and $FFFF ) + ReplyBytes > $10000 ) then start := ( start or $FFFF ) + 1;
  bufSeg := word(start shr 4);
  bufOfs := word(start and 15);
  buf := Ptr(bufSeg, bufOfs);
end;

{ ////////////////// The BIOS ////////////////// }

function FloppyCount:integer;
var
  regs:Registers;
begin
  Intr($11, regs);
  if ( regs.AX and 1 ) = 0 then FloppyCount := 0
  else FloppyCount := ( ( regs.AX shr 6 ) and 3 ) + 1;
end;

procedure ResetDrive(drive:byte);
var
  regs:Registers;
begin
  regs.AH := $00;
  regs.DL := drive;
  Intr($13, regs);
end;

{ One INT 13h read (AH=02h) or write (AH=03h) of `count` sectors from
  `sector` at the mailbox cylinder: the BIOS's status, 0 if it worked }
function BiosOnce(fn:byte; drive:byte; sector, count:byte):byte;
var
  regs:Registers;
begin
  regs.AH := fn;
  regs.AL := count;
  regs.CH := Cylinder;
  regs.CL := sector;
  regs.DH := 0;
  regs.DL := drive;
  regs.ES := bufSeg;
  regs.BX := bufOfs;
  Intr($13, regs);
  if ( regs.Flags and FCarry ) = 0 then BiosOnce := 0
  else if ( regs.AH = 0 ) then BiosOnce := $FF
  else BiosOnce := regs.AH;
end;

{ The head to the mailbox cylinder (INT 13h, AH=0Ch) }
procedure SeekMailbox(drive:byte);
var
  regs:Registers;
begin
  regs.AH := $0C;
  regs.CH := Cylinder;
  regs.CL := 1;
  regs.DH := 0;
  regs.DL := drive;
  Intr($13, regs);
end;

{ ////////////////// The controller, directly ////////////////// }

procedure WaitTicks(n:longint);
var
  start:longint;
begin
  start := Ticks;
  repeat until ( Ticks - start >= n ) or ( Ticks < start );
end;

{ A byte to the controller once it's ready for one. False after about 0.2 s }
function FdcWrite(b:byte):boolean;
var
  start:longint;
begin
  FdcWrite := false;
  start := Ticks;
  repeat
    if ( Port[FdcMsr] and $C0 ) = $80 then begin
      Port[FdcData] := b;
      FdcWrite := true;
      exit;
    end;
  until ( Ticks - start > 3 ) or ( Ticks < start );
end;

function FdcRead(var b:byte):boolean;
var
  start:longint;
begin
  FdcRead := false;
  start := Ticks;
  repeat
    if ( Port[FdcMsr] and $C0 ) = $C0 then begin
      b := Port[FdcData];
      FdcRead := true;
      exit;
    end;
  until ( Ticks - start > 3 ) or ( Ticks < start );
end;

{ The head to cylinder 82 by the controller itself, for a Duo with no disk
  in: a BIOS may not seek a drive whose disk it hasn't recognised (the
  Evesham's tries to make the disk out where the head is, finds nothing, and
  reports the drive not ready without moving the head). At cylinder 82 the
  Duo answers as if a disk were in, so then the BIOS recognises the mailbox's
  track. The motor on as the BIOS does it, and the BIOS told so; the seek's
  interrupt waited for (the BIOS's handler sets bit 7 of 40:3E) and cleared
  with Sense Interrupt Status, so the BIOS's next command starts clean }
procedure Note(s:string);
begin
  if ( length(FdcLog) + length(s) < 250 ) then FdcLog := FdcLog + s + ' ';
end;

function Hex2(b:byte):string;
const
  Digits: string[16] = '0123456789ABCDEF';
begin
  Hex2 := Digits[b shr 4 + 1] + Digits[b and 15 + 1];
end;

procedure FdcSeekMailbox(drive:byte);
var
  start:longint;
  b,st0,pcn:byte;
  n:integer;
  busy:boolean;
begin
  FdcLog := '';
  if ( drive > 1 ) then exit;
  { The BIOS resets the controller first: out of reset, with its step rate
    set (Specify) and the reset's interrupts taken. A BIOS that gave up on
    a drive may have left it reset, or holding an interrupt, and then a
    Seek is ignored (the Evesham's, 18 Nov) }
  ResetDrive(drive);
  Note('reset msr=' + Hex2(Port[FdcMsr]));
  Port[FdcDor] := $0C or drive or ( $10 shl drive );  { not reset, DMA and interrupts on, this drive's motor }
  Mem[$40:$3F] := Mem[$40:$3F] or ( 1 shl drive );   { the BIOS's motor bits: running }
  Mem[$40:$40] := $FF;                                { and its count to turning it off: about 14 s }
  WaitTicks(9);                                       { spin-up: half a second }
  { Anything the controller still has to say, then any interrupt it holds }
  n := 0;
  while ( ( Port[FdcMsr] and $D0 ) = $D0 ) and ( n < 16 ) do begin
    b := Port[FdcData];
    inc(n);
  end;
  if ( n > 0 ) then Note('drained=' + IntToStr(n));
  Mem[$40:$3E] := Mem[$40:$3E] and $7F;
  if FdcWrite(FdcSenseInterrupt) and FdcRead(st0) then begin
    Note('sense st0=' + Hex2(st0));
    if ( st0 <> $80 ) and FdcRead(pcn) then Note('pcn=' + IntToStr(pcn));
  end;
  Note('msr=' + Hex2(Port[FdcMsr]));
  if not FdcWrite(FdcSeek) then begin
    Note('seek refused');
    exit;
  end;
  if not ( FdcWrite(drive) and FdcWrite(Cylinder) ) then begin
    Note('seek args refused');
    exit;
  end;
  Note('seek sent msr=' + Hex2(Port[FdcMsr]));
  { Done when the controller interrupts (the BIOS's handler sets 40:3E bit 7);
    the drive's busy bit in the main status shows the seek running }
  start := Ticks;
  busy := false;
  repeat
    if ( Port[FdcMsr] and ( 1 shl drive ) ) <> 0 then busy := true;
  until ( ( Mem[$40:$3E] and $80 ) <> 0 ) or ( Ticks - start > 27 ) or ( Ticks < start );
  if ( Mem[$40:$3E] and $80 ) <> 0 then Note('irq') else Note('no irq');
  if busy then Note('busy seen');
  Mem[$40:$3E] := Mem[$40:$3E] and $7F;
  if FdcWrite(FdcSenseInterrupt) and FdcRead(st0) then begin
    Note('st0=' + Hex2(st0));
    if FdcRead(pcn) then Note('pcn=' + IntToStr(pcn));
  end;
  Mem[$40:$94 + drive] := Cylinder;  { the BIOS's record of where the head is }
  WaitTicks(3);                      { the head settles }
end;

{ With the BIOS's usual retries: three tries, a reset between them (a
  motor still spinning up fails the first). A disk change is noted and
  tried again. A drive that isn't ready is tried once more with the head
  at cylinder 82 first: a Duo with no disk in answers only there, and a
  BIOS may look at the disk change line before it seeks; if the BIOS still
  won't move the head, the controller moves it (FdcSeekMailbox). Each
  not-ready waits seconds, so no more than that }
function Bios(fn:byte; drive:byte; sector, count:byte):byte;
var
  tries:integer;
  status:byte;
  sought:boolean;
begin
  tries := 0;
  sought := false;
  repeat
    inc(tries);
    status := BiosOnce(fn, drive, sector, count);
    if ( status = BsChanged ) and ( drive < MaxFloppies ) then changed[drive] := true;
    if ( status = BsTimeout ) and not sought then begin
      sought := true;
      SeekMailbox(drive);
      status := BiosOnce(fn, drive, sector, count);
      if ( status = BsChanged ) and ( drive < MaxFloppies ) then changed[drive] := true;
      { Still not ready: the BIOS wouldn't move the head. The controller moves it }
      if ( status = BsTimeout ) then begin
        FdcSeekMailbox(drive);
        status := BiosOnce(fn, drive, sector, count);
        if ( status = BsChanged ) and ( drive < MaxFloppies ) then changed[drive] := true;
      end;
    end;
    if ( status = 0 ) or ( status = BsTimeout ) or ( status = BsBadCommand ) then begin
      Bios := status;
      exit;
    end;
    if ( status <> BsChanged ) then ResetDrive(drive);
  until tries >= 4;
  Bios := status;
end;

function ResultOf(status:byte):integer;
begin
  case status of
    0: ResultOf := FxOk;
    BsTimeout: ResultOf := FxNoDisk;
    BsBadCommand: ResultOf := FxRefused;
  else
    ResultOf := FxNoDuo;  { Sector not found, no address mark, a CRC error: nothing of the Duo's there }
  end;
end;

{ ////////////////// Disk caches and DOS ////////////////// }

{ SMARTDRV (or a cache that answers like it): 1 writes out what it holds,
  2 writes it out and forgets it. Harmless without one }
procedure DiskCache(what:word);
var
  regs:Registers;
begin
  regs.AX := $4A10;
  regs.BX := what;
  Intr($2F, regs);
end;

procedure FlushDos;
var
  regs:Registers;
begin
  regs.AH := $0D;
  MsDos(regs);
  DiskCache(1);
end;

procedure TellDos(drive:byte);
var
  regs:Registers;
  major:byte;
  flag:word;
begin
  if ( drive >= MaxFloppies ) then exit;
  changed[drive] := false;
  regs.AH := $30;
  MsDos(regs);
  major := regs.AL;
  { The drive's parameter block (INT 21h, AH=32h): DOS checks the disk as
    it finds it, and its flag byte set to FFh makes DOS rebuild it at the
    next access: offset 18h from DOS 4, 17h before }
  regs.AH := $32;
  regs.DL := drive + 1;
  MsDos(regs);
  if ( regs.AL <> 0 ) then exit;
  if ( major >= 4 ) then flag := $18 else flag := $17;
  Mem[regs.DS:regs.BX + flag] := $FF;
end;

{ ////////////////// The mailbox ////////////////// }

function IsReply(seq:word):boolean;
begin
  IsReply := ( buf^[0] = ord('S') ) and ( buf^[1] = ord('M') ) and ( buf^[2] = ord('N') ) and ( buf^[3] = ord('D') )
             and ( buf^[4] = ProtocolVersion ) and ( buf^[6] = Lo(seq) ) and ( buf^[7] = Hi(seq) );
end;

function ProbeDuo(drive:byte):integer;
var
  status:byte;
begin
  status := Bios($02, drive, FirstReply, ReplySectors);
  if ( status <> 0 ) then begin
    ProbeDuo := ResultOf(status);
    exit;
  end;
  if ( buf^[0] = ord('S') ) and ( buf^[1] = ord('M') ) and ( buf^[2] = ord('N') ) and ( buf^[3] = ord('D') )
     and ( buf^[4] = ProtocolVersion ) then begin
    ProbeDuo := FxOk;
    { Carry on from the last request's number, so the next can't look like an answer already given }
    sequence := buf^[6] or ( buf^[7] shl 8 );
  end
  else ProbeDuo := FxNoDuo;
end;

function FindDuo:boolean;
var
  d,count:integer;
begin
  FindDuo := false;
  count := FloppyCount;
  for d := 0 to MaxFloppies - 1 do ProbeResult[d] := -1;
  for d := 0 to count - 1 do begin
    if ( d >= MaxFloppies ) then exit;
    ProbeResult[d] := ProbeDuo(d);
    if ( ProbeResult[d] = FxOk ) then begin
      DuoDrive := d;
      FindDuo := true;
      if changed[d] then TellDos(d);
      exit;
    end;
  end;
end;

procedure TakeLines(var replies:TLines);
var
  s,i,len:integer;
  more:boolean;
  line:string;
begin
  s := 0;
  repeat
    more := ( buf^[s * SectorBytes + 5] and FlagMore ) <> 0;
    len := buf^[s * SectorBytes + 8] or ( buf^[s * SectorBytes + 9] shl 8 );
    if ( len > TextMax ) then len := TextMax;
    line := '';
    for i := s * SectorBytes + HeaderSize to s * SectorBytes + HeaderSize + len - 1 do
      if ( buf^[i] = 10 ) then begin
        if ( length(line) > 0 ) then AddLine(replies, line);
        line := '';
      end
      else if ( buf^[i] <> 13 ) and ( length(line) < 255 ) then
        line := line + chr(buf^[i]);
    if ( length(line) > 0 ) then AddLine(replies, line);
    inc(s);
  until not more or ( s >= ReplySectors );
end;

function DuoExchange(request:string; var replies:TLines):integer;
var
  status:byte;
  tries:integer;
  started:longint;
  len:word;
begin
  ClearLines(replies);
  started := Ticks;
  DuoExchange := FxBadReply;
  if ( length(request) > TextMax - 2 ) then exit;

  inc(sequence);
  if ( sequence = 0 ) then sequence := 1;  { 0 is the hello's }
  FillChar(buf^, SectorBytes, 0);
  buf^[0] := ord('S');
  buf^[1] := ord('M');
  buf^[2] := ord('N');
  buf^[3] := ord('D');
  buf^[4] := ProtocolVersion;
  buf^[6] := Lo(sequence);
  buf^[7] := Hi(sequence);
  len := length(request) + 1;
  buf^[8] := Lo(len);
  buf^[9] := Hi(len);
  Move(request[1], buf^[HeaderSize], length(request));
  buf^[HeaderSize + length(request)] := 10;

  DiskCache(1);
  status := Bios($03, DuoDrive, RequestSector, 1);
  if ( status <> 0 ) then begin
    DuoExchange := ResultOf(status);
    exit;
  end;

  tries := 0;
  repeat
    inc(tries);
    DiskCache(2);  { Not a cached copy of an old reply }
    status := Bios($02, DuoDrive, FirstReply, ReplySectors);
    if ( status <> 0 ) then begin
      DuoExchange := ResultOf(status);
      exit;
    end;
  until IsReply(sequence) or ( tries >= ReadTries );
  ExchangeMs := ( Ticks - started ) * 55;
  if not IsReply(sequence) then begin
    DuoExchange := FxTimeout;
    exit;
  end;
  TakeLines(replies);
  if changed[DuoDrive] then TellDos(DuoDrive);
  DuoExchange := FxOk;
end;

procedure DuoPark;
var
  regs:Registers;
begin
  regs.AH := $0C;
  regs.CH := 0;
  regs.CL := 1;
  regs.DH := 0;
  regs.DL := DuoDrive;
  Intr($13, regs);
end;

var
  d:integer;
begin
  sequence := 0;
  DuoDrive := 0;
  ExchangeMs := 0;
  for d := 0 to MaxFloppies - 1 do begin
    ProbeResult[d] := -1;
    changed[d] := false;
  end;
  PlaceBuffer;
end.
