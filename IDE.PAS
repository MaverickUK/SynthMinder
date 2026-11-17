Unit Ide;
{-----------------------------
Talking to the IDE Synth Bay through the PC's IDE ports

Finds the Bay by asking each drive on the primary and secondary
channels for its IDENTIFY data, then exchanges sentences with it
through its SynthMinder command (docs/protocol.md): one sector
out with the request, sectors back with the reply.

Direct port access works in plain DOS. Under Windows, its own disk
driver owns the ports, so run SynthMinder from DOS.
------------------------------}

{ --------- interface -------- }
interface
uses
    Sentence;

const
  { Exchange results }
  ExOk = 0;
  ExNoBay = 1;      { No Bay found, or it stopped answering }
  ExRefused = 2;    { The Bay aborted the command: firmware without SynthMinder support }
  ExTimeout = 3;
  ExBadReply = 4;

type
  TDriveInfo = record
    Found: boolean;
    Base: word;       { $1F0 or $170 }
    Control: word;    { $3F6 or $376 }
    Device: byte;     { 0 master, 1 slave }
    Atapi: boolean;
    Model: string[40];
    Firmware: string[8];
  end;

var
  BayDrive: TDriveInfo;

function FindBay:boolean;
function IdentifyDrive(base, control:word; device:byte; var info:TDriveInfo):boolean;
function DriveName(var info:TDriveInfo):string;
function BayExchange(request:string; var replies:TLines):integer;
procedure FlushDiskCache;

{ --------- implementation --------- }
implementation
uses
    Dos;

const
  { Task file registers, from the channel's base port }
  RegData = 0;
  RegFeatures = 1;  { Error when read }
  RegCount = 2;
  RegLbaLow = 3;
  RegLbaMid = 4;
  RegLbaHigh = 5;
  RegDevice = 6;
  RegCommand = 7;   { Status when read }

  { Status bits }
  StBsy = $80;
  StDrdy = $40;
  StDrq = $08;
  StErr = $01;

  CmdIdentify = $EC;
  CmdIdentifyPacket = $A1;
  CmdSynthMinder = $8D;  { In ATA's vendor-specific range, 80h-8Fh }
  SubSend = $01;
  SubReceive = $02;

  { The model the Bay gives in IDENTIFY: 'HDDSYNTH PROTO' for a hard disk,
    'HDDSYNTH PRO CD-ROM' for a CD-ROM drive }
  BayModelPrefix = 'HDDSYNTH PRO';

  ProtocolVersion = 1;
  HeaderSize = 16;
  TextMax = 512 - HeaderSize;
  FlagMore = $01;
  MaxReceives = 16;

type
  TSector = array[0..511] of byte;

var
  sequence:word;

{ ////////////////// Timing ////////////////// }

{ The BIOS's tick count, 18.2 a second }
function Ticks:longint;
begin
  Ticks := MemL[$40:$6C];
end;

{ About 400 ns, for the drive's status to settle: four reads of
  the alternate status register, as ATA suggests }
procedure Settle(control:word);
var
  i:byte;
  b:byte;
begin
  for i := 1 to 4 do b := Port[control];
end;

{ Wait for BSY to clear. False if it hasn't within the given ticks, or the
  channel reads as nothing there ($FF: a floating bus) }
function WaitNotBusy(base:word; timeoutTicks:longint; var status:byte):boolean;
var
  start:longint;
begin
  WaitNotBusy := false;
  start := Ticks;
  repeat
    status := Port[base + RegCommand];
    if ( status = $FF ) then exit;
    if ( status and StBsy ) = 0 then begin
      WaitNotBusy := true;
      exit;
    end;
  until ( Ticks - start > timeoutTicks ) or ( Ticks < start );
end;

{ ////////////////// Disk caches ////////////////// }

{ Ask SMARTDRV (or a cache that answers like it) to write out what it holds,
  so it doesn't start a write between our register writes. Harmless without one }
procedure FlushDiskCache;
var
  regs:Registers;
begin
  regs.AX := $4A10;
  regs.BX := $0001; { Commit the cache }
  Intr($2F, regs);
end;

{ ////////////////// Commands ////////////////// }

{ Select a drive and wait for it to be ready for a command }
function SelectDrive(base, control:word; device:byte):boolean;
var
  status:byte;
begin
  SelectDrive := false;
  if not WaitNotBusy(base, 18, status) then exit;
  Port[control] := $02; { nIEN: no interrupt for our commands; the BIOS's handler isn't expecting one }
  Port[base + RegDevice] := $A0 or ( device shl 4 );
  Settle(control);
  if not WaitNotBusy(base, 18, status) then exit;
  { 0 means nothing answers as that device }
  SelectDrive := status <> 0;
end;

procedure ReleaseChannel(control:word);
begin
  Port[control] := $00; { Interrupts back on, as the BIOS expects }
end;

procedure ReadSector(base:word; var sector:TSector);
var
  i:integer;
  w:word;
begin
  for i := 0 to 255 do begin
    w := PortW[base + RegData];
    sector[i * 2] := Lo(w);
    sector[i * 2 + 1] := Hi(w);
  end;
end;

procedure WriteSector(base:word; var sector:TSector);
var
  i:integer;
begin
  for i := 0 to 255 do
    PortW[base + RegData] := sector[i * 2] or ( word(sector[i * 2 + 1]) shl 8 );
end;

{ An ATA string from IDENTIFY: each word holds two characters, high byte first }
function AtaString(var sector:TSector; firstWord, words:integer):string;
var
  s:string;
  i:integer;
begin
  s := '';
  for i := firstWord to firstWord + words - 1 do
    s := s + chr(sector[i * 2 + 1]) + chr(sector[i * 2]);
  while ( length(s) > 0 ) and ( s[length(s)] in [' ', #0] ) do dec(s[0]);
  AtaString := s;
end;

{ Run a PIO data-in command that returns one sector: IDENTIFY or
  IDENTIFY PACKET DEVICE }
function DataInCommand(base, control:word; command:byte; var sector:TSector):boolean;
var
  status:byte;
begin
  DataInCommand := false;
  Port[base + RegCommand] := command;
  Settle(control);
  if not WaitNotBusy(base, 37, status) then exit; { 2 s }
  if ( status and StErr ) <> 0 then exit;
  if ( status and StDrq ) = 0 then exit;
  ReadSector(base, sector);
  DataInCommand := true;
end;

{ IDENTIFY one drive. False if nothing answers there }
function IdentifyDrive(base, control:word; device:byte; var info:TDriveInfo):boolean;
var
  sector:TSector;
  ok:boolean;
begin
  IdentifyDrive := false;
  FillChar(info, SizeOf(info), 0);
  info.Base := base;
  info.Control := control;
  info.Device := device;
  if not SelectDrive(base, control, device) then begin
    ReleaseChannel(control);
    exit;
  end;

  ok := DataInCommand(base, control, CmdIdentify, sector);
  { A CD-ROM drive aborts IDENTIFY and shows the ATAPI signature }
  if not ok and ( Port[base + RegLbaMid] = $14 ) and ( Port[base + RegLbaHigh] = $EB ) then begin
    info.Atapi := true;
    ok := DataInCommand(base, control, CmdIdentifyPacket, sector);
  end;
  ReleaseChannel(control);
  if not ok then exit;

  info.Found := true;
  info.Firmware := AtaString(sector, 23, 4);
  info.Model := AtaString(sector, 27, 20);
  IdentifyDrive := true;
end;

{ e.g. 'primary master' }
function DriveName(var info:TDriveInfo):string;
var
  s:string;
begin
  if ( info.Base = $1F0 ) then s := 'primary ' else s := 'secondary ';
  if ( info.Device = 0 ) then s := s + 'master' else s := s + 'slave';
  DriveName := s;
end;

{ Look for the Bay on both channels. A hard disk it serves is preferred
  over its CD-ROM drive, though either answers SynthMinder's command }
function FindBay:boolean;
const
  Bases: array[0..1] of word = ($1F0, $170);
  Controls: array[0..1] of word = ($3F6, $376);
var
  channel,device:byte;
  info:TDriveInfo;
begin
  FindBay := false;
  FillChar(BayDrive, SizeOf(BayDrive), 0);
  FlushDiskCache;
  for channel := 0 to 1 do
    for device := 0 to 1 do
      if IdentifyDrive(Bases[channel], Controls[channel], device, info) then
        if ( copy(info.Model, 1, length(BayModelPrefix)) = BayModelPrefix ) then
          if not BayDrive.Found or ( BayDrive.Atapi and not info.Atapi ) then
            BayDrive := info;
  FindBay := BayDrive.Found;
end;

{ ////////////////// Exchanging sentences ////////////////// }

{ Start the SynthMinder command. 'S' 'M' in LBA low and mid mark it as
  ours, so a stray 8Dh from another program is refused }
function StartCommand(subcommand:byte; var status:byte):boolean;
begin
  StartCommand := false;
  with BayDrive do begin
    if not SelectDrive(Base, Control, Device) then exit;
    Port[Base + RegFeatures] := subcommand;
    Port[Base + RegCount] := 1;
    Port[Base + RegLbaLow] := ord('S');
    Port[Base + RegLbaMid] := ord('M');
    Port[Base + RegLbaHigh] := ProtocolVersion;
    Port[Base + RegCommand] := CmdSynthMinder;
    Settle(Control);
    { The Bay may wait for the synth's answer while busy: up to a second }
    if not WaitNotBusy(Base, 37, status) then exit;
  end;
  StartCommand := true;
end;

{ Send one request and collect the reply, which may take several sectors }
function BayExchange(request:string; var replies:TLines):integer;
var
  sector:TSector;
  status:byte;
  i,len,start,receives:integer;
  line:string;
  more:boolean;
begin
  ClearLines(replies);
  BayExchange := ExNoBay;
  if not BayDrive.Found then exit;
  if ( length(request) > TextMax - 2 ) then begin
    BayExchange := ExBadReply;
    exit;
  end;
  inc(sequence);

  { The request: header, then the sentence and a line feed }
  FillChar(sector, SizeOf(sector), 0);
  sector[0] := ord('S'); sector[1] := ord('M'); sector[2] := ord('N'); sector[3] := ord('D');
  sector[4] := ProtocolVersion;
  sector[6] := Lo(sequence);
  sector[7] := Hi(sequence);
  len := length(request) + 1;
  sector[8] := Lo(len);
  sector[9] := Hi(len);
  Move(request[1], sector[HeaderSize], length(request));
  sector[HeaderSize + length(request)] := 10;

  FlushDiskCache;
  if not StartCommand(SubSend, status) then begin
    ReleaseChannel(BayDrive.Control);
    BayExchange := ExTimeout;
    exit;
  end;
  if ( status and StErr ) <> 0 then begin
    ReleaseChannel(BayDrive.Control);
    BayExchange := ExRefused;
    exit;
  end;
  if ( status and StDrq ) = 0 then begin
    ReleaseChannel(BayDrive.Control);
    BayExchange := ExBadReply;
    exit;
  end;
  WriteSector(BayDrive.Base, sector);
  Settle(BayDrive.Control);
  { The Bay checks the request, and passes it to the synth }
  if not WaitNotBusy(BayDrive.Base, 37, status) or ( ( status and StErr ) <> 0 ) then begin
    ReleaseChannel(BayDrive.Control);
    BayExchange := ExTimeout;
    exit;
  end;

  { The reply, a sector at a time while the Bay says there's more }
  receives := 0;
  repeat
    inc(receives);
    if not StartCommand(SubReceive, status) then begin
      ReleaseChannel(BayDrive.Control);
      BayExchange := ExTimeout;
      exit;
    end;
    if ( ( status and StErr ) <> 0 ) or ( ( status and StDrq ) = 0 ) then begin
      ReleaseChannel(BayDrive.Control);
      BayExchange := ExBadReply;
      exit;
    end;
    ReadSector(BayDrive.Base, sector);

    if ( sector[0] <> ord('S') ) or ( sector[1] <> ord('M') ) or ( sector[2] <> ord('N') )
       or ( sector[3] <> ord('D') ) or ( sector[6] <> Lo(sequence) ) or ( sector[7] <> Hi(sequence) ) then begin
      ReleaseChannel(BayDrive.Control);
      BayExchange := ExBadReply;
      exit;
    end;
    more := ( sector[5] and FlagMore ) <> 0;
    len := sector[8] or ( sector[9] shl 8 );
    if ( len > TextMax ) then len := TextMax;

    { Lines, each ending in a line feed }
    line := '';
    for i := HeaderSize to HeaderSize + len - 1 do
      if ( sector[i] = 10 ) then begin
        if ( length(line) > 0 ) then AddLine(replies, line);
        line := '';
      end
      else if ( sector[i] <> 13 ) and ( length(line) < 255 ) then
        line := line + chr(sector[i]);
    if ( length(line) > 0 ) then AddLine(replies, line);
  until not more or ( receives >= MaxReceives );

  ReleaseChannel(BayDrive.Control);
  BayExchange := ExOk;
end;

begin
  sequence := 0;
  FillChar(BayDrive, SizeOf(BayDrive), 0);
end.
