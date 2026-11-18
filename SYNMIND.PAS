Program SynMind;
{-----------------------------
SynthMinder: see and change the HDD Synth, IDE Synth Bay and FDD
Synth Duo from DOS

  SYNMIND           find the Bay and open SynthMinder
  SYNMIND /DEMO     a pretend Bay and synth, to try it out
  SYNMIND /STATUS   print what the Bay and synth say, and exit
  SYNMIND /V        print the version

and for batch files (OPTIONS.PAS):

  SYNMIND /DISC=QUAKE.ISO /PACK=3 /VOL=60 /BAL=50 /Q
  SYNMIND /FDA=GAMES.IMG /FDVOL=60 /Q

The Bay is found on the IDE bus and answers through its own
command (docs/protocol.md); it passes the synth's sentences on
over the Synth Link. The FDD Synth Duo is found on the floppy
drives and answers through its mailbox at cylinder 82
(FLOPPY.PAS).
------------------------------}
uses
    FpuFix, { First: see FPUFIX.PAS }
    Crt,
    Dos,
    Sentence,
    Model,
    Ide,
    Floppy,
    Link,
    Options,
    Screen;

{$I VERSION.INC}

const
  ApplicationName = 'SynthMinder v' + AppVersion;

  MenuSynth = 0;
  MenuBay = 1;
  MenuFloppy = 2;
  MenuSettings = 3;
  MenuRefresh = 4;
  MenuExit = 5;
  MenuCount = 6;
  MenuCaptions: array[0..MenuCount - 1] of string[8] = ('Synth', 'Bay', 'Floppy', 'Settings', 'Refresh', 'Exit');
  MenuHints: array[0..MenuCount - 1] of string[78] = (
    'The HDD Synth: its sample pack, volume and balance',
    'The Bay''s SD card: change the CD, or the hard disk for the next power-on',
    'The FDD Synth Duo: its disks and its sound',
    'The Bay''s and the Duo''s settings: changes take effect from the next power-on',
    'Ask the Bay, the synth and the Duo again',
    'Exit to DOS');

  { The Settings tab's rows: a heading (no key), or a setting the Bay lists
    with $SBQ,1,SETTINGS, or (fd:) the Duo with $FDQ,1,SETTINGS. The Bay's
    show when it lists settings, the Duo's when it does }
  SettingRowCount = 19;
  ShownFirstRow = 11;  { The bus's: shown only, as the Bay gives them (0.36.0-dev.2) }
  DuoFirstRow = 16;
  SettingRows: array[1..SettingRowCount] of record
    Key: string[13];
    Caption: string[16];
  end = (
    (Key:''; Caption:'Second drive'),
    (Key:'device1'; Caption:'Device 1'),
    (Key:'cdrom'; Caption:'CD at power-on'),
    (Key:''; Caption:'HDD Synth'),
    (Key:'seek_timing'; Caption:'Seek timing'),
    (Key:'activity_link'; Caption:'Synth Link'),
    (Key:''; Caption:'Speed and safety'),
    (Key:'write_behind'; Caption:'Write-behind'),
    (Key:'read_ahead'; Caption:'Read-ahead'),
    (Key:'sd_high_speed'; Caption:'SD card speed'),
    (Key:''; Caption:'The bus, shown only'),
    (Key:'bus'; Caption:'Bus program'),
    (Key:'dma'; Caption:'DMA'),
    (Key:'mode'; Caption:'Mode'),
    (Key:'geometry'; Caption:'Geometry'),
    (Key:''; Caption:'FDD Synth Duo'),
    (Key:'fd:drive'; Caption:'Drives'),
    (Key:'fd:device0'; Caption:'Start disk A:'),
    (Key:'fd:device1'; Caption:'Start disk B:'));
  ChChanged = #249;  { A setting whose next value differs from now }

  { The seek timings, for the chooser }
  SeekCount = 6;
  SeekValues: array[1..SeekCount] of string[9] = ('off', 'synth', 'stepper85', 'voice91', 'voice97', 'fdb05');
  SeekWords: array[1..SeekCount] of string[38] = (
    'as fast as the card allows',
    'the drive the HDD Synth is playing',
    'a 1985 stepper drive, 3600 rpm',
    'a 1991 voice coil drive, 3600 rpm',
    'a 1997 drive, 5400 rpm',
    'a 2005 drive, 7200 rpm, 2 MB cache');

  MaxChoices = MaxDuoFiles + 2;

  { Rows of the Bay's list that aren't files }
  RowHardDisks = -1;
  RowCdRoms = -2;

  { Rows of the Floppy tab's list that aren't images: headings, and the
    packs (RowFirstPack - index) }
  Row35 = -1;
  Row525 = -2;
  RowOther = -3;
  RowPacks = -4;
  RowFirstPack = -10;

var
  menuIndex:integer;
  tab:integer;              { MenuSynth, MenuBay or MenuSettings: what the panels show }
  setSel:integer;           { The Settings tab's row, 1..SettingRowCount, never a heading }
  choiceValue:array[1..MaxChoices] of string[47];  { The chooser's choices }
  choiceWords:array[1..MaxChoices] of string[40];
  choiceCount:integer;
  packSel,packTop:integer;
  bayRows:array[0..MaxFiles + 1] of integer; { File index, or RowHardDisks/RowCdRoms }
  bayRowCount:integer;
  baySel,bayTop:integer;
  fdRows:array[0..MaxDuoFiles + MaxDuoPacks + 3] of integer; { Image index, a heading, or a pack }
  fdRowCount:integer;
  fdSel,fdTop:integer;
  note:string;              { The result of the last change, in the bottom of the frame }
  noteGood:boolean;
  quit:boolean;

{ ////////////////// Words ////////////////// }

function StateText(state:string):string;
begin
  if ( state = 'RUN' ) then StateText := 'Running'
  else if ( state = 'STANDBY' ) then StateText := 'Standby (spun down)'
  else if ( state = 'SPINUP' ) then StateText := 'Spinning up'
  else if ( state = 'BOOT' ) then StateText := 'Starting'
  else if ( state = 'JINGLE' ) then StateText := 'Playing its jingle'
  else if ( state = 'WAIT_POWER' ) then StateText := 'Waiting for power'
  else if ( state = 'HALTED' ) then StateText := 'Stopped'
  else if ( pos('SPINDOWN', state) > 0 ) then StateText := 'Spinning down'
  else StateText := state;
end;

function KindText(kind:char):string;
begin
  case kind of
    'M': KindText := 'modelled';
    'R': KindText := 'recorded';
  else
    KindText := '';
  end;
end;

{ e.g. 48 MB, or 640 KB }
function SizeText(kb:longint):string;
begin
  if ( kb >= 1024 ) then SizeText := IntToStr(( kb + 512 ) div 1024) + ' MB'
  else SizeText := IntToStr(kb) + ' KB';
end;

function Repeated(ch:char; count:integer):string;
var
  s:string;
begin
  s := '';
  while ( length(s) < count ) do s := s + ch;
  Repeated := s;
end;

{ ████████░░░░ 60 }
function VolumeBar(volume:integer):string;
var
  filled:integer;
begin
  filled := ( volume + 2 ) div 5;
  VolumeBar := Repeated(ChBlock, filled) + Repeated(ChShade, 20 - filled) + ' ' + IntToStr(volume);
end;

{ L ────■──── R 55 }
function BalanceBar(balance:integer):string;
var
  s:string;
  at:integer;
begin
  s := Repeated(ChLine, 17);
  at := ( balance * 16 + 50 ) div 100 + 1;
  s[at] := ChMarker;
  BalanceBar := 'L ' + s + ' R ' + IntToStr(balance);
end;

{ ////////////////// Panels ////////////////// }

procedure LeftLine(y:byte; text:string; fore, back:byte);
begin
  WriteAt(LeftX, y, ' ' + PadRight(text, LeftWidth - 1), fore, back);
end;

{ Text on the left with something at the right, e.g. a pack and its kind }
procedure LeftRow(y:byte; text, right:string; fore, back:byte);
begin
  LeftLine(y, PadRight(text, LeftWidth - 2 - length(right)) + right, fore, back);
end;

procedure RightLine(y:byte; text:string; fore, back:byte);
begin
  WriteAt(RightX, y, ' ' + PadRight(text, RightWidth - 1), fore, back);
end;

procedure RightHeading(var y:byte; text:string);
begin
  RightLine(y, text, ColorHeadingText, ColorHeadingBack);
  inc(y);
end;

procedure RightField(var y:byte; name, value:string);
begin
  if ( y >= FrameBottom ) then exit;
  RightLine(y, PadRight(name, 12) + value, ColorText, ColorBackground);
  inc(y);
end;

procedure RightGap(var y:byte);
begin
  if ( y >= FrameBottom ) then exit;
  RightLine(y, '', ColorText, ColorBackground);
  inc(y);
end;

procedure ClearRight(y:byte);
begin
  while ( y < FrameBottom ) do begin
    RightLine(y, '', ColorText, ColorBackground);
    inc(y);
  end;
end;

procedure ClearLeft(y, last:byte);
begin
  while ( y <= last ) do begin
    LeftLine(y, '', ColorText, ColorBackground);
    inc(y);
  end;
end;

{ The Bay's device 1, in words }
function Device1Text:string;
var
  device1,disc:string;
begin
  device1 := BayValue('device1');
  disc := BayValue('disc');
  if ( device1 = 'cdrom' ) then begin
    if ( length(disc) = 0 ) or ( disc = '-' ) then Device1Text := 'CD-ROM, no disc'
    else Device1Text := 'CD-ROM: ' + disc;
  end
  else if ( length(device1) = 0 ) or ( device1 = 'none' ) then Device1Text := 'none'
  else Device1Text := device1;
end;

procedure BayFields(var y:byte);
var
  firmware:string;
  i:integer;
  key:string;
begin
  firmware := BayValue('firmware');
  if ( length(BayValue('build')) > 0 ) then firmware := firmware + ' (' + BayValue('build') + ')';
  RightField(y, 'Firmware', firmware);
  if ( Backend = bkIde ) then RightField(y, 'Found as', DriveName(BayDrive));
  if ( length(BayValue('device0')) > 0 ) then RightField(y, 'Device 0', BayValue('device0'));
  if ( length(BayValue('device0_next')) > 0 ) then RightField(y, 'Next boot', BayValue('device0_next'));
  RightField(y, 'Device 1', Device1Text);
  if ( length(BayValue('bus')) > 0 ) then RightField(y, 'Bus', BayValue('bus'));
  if ( length(BayValue('seek_timing')) > 0 ) then RightField(y, 'Seek timing', BayValue('seek_timing'));
  if ( length(BayValue('card')) > 0 ) then RightField(y, 'SD card', BayValue('card'));
  if ( length(BayValue('link')) > 0 ) then RightField(y, 'Synth Link', BayValue('link'));

  { Anything newer firmware sends that this version doesn't know }
  for i := 1 to Bay.ValueCount do begin
    key := Bay.Values[i].Key;
    if ( key <> 'firmware' ) and ( key <> 'build' ) and ( key <> 'device0' ) and ( key <> 'device0_next' )
       and ( key <> 'device1' ) and ( key <> 'disc' ) and ( key <> 'bus' ) and ( key <> 'seek_timing' )
       and ( key <> 'card' ) and ( key <> 'link' ) then
      RightField(y, key, Bay.Values[i].Value);
  end;
end;

{ ////////////////// Synth tab ////////////////// }

function PackRows:integer;
begin
  PackRows := FrameBottom - 3 - ( PanelTop + 1 ); { Leaves room for the key to the marks }
end;

procedure KeepPackVisible;
begin
  if ( packSel >= Synth.PacksKnown ) then packSel := Synth.PacksKnown - 1;
  if ( packSel < 0 ) then packSel := 0;
  if ( packSel < packTop ) then packTop := packSel;
  if ( packSel >= packTop + PackRows ) then packTop := packSel - PackRows + 1;
  if ( packTop < 0 ) then packTop := 0;
end;

procedure DrawSynthLeft;
var
  y:byte;
  i:integer;
  mark,kind:string;
begin
  LeftRow(PanelTop, 'Sample packs', IntToStr(Synth.PacksKnown), ColorHeadingText, ColorHeadingBack);
  y := PanelTop + 1;
  if not Synth.Present then begin
    LeftLine(y, '', ColorText, ColorBackground);
    LeftLine(y + 1, 'No packs: the synth isn''t', ColorText, ColorBackground);
    LeftLine(y + 2, 'answering', ColorText, ColorBackground);
    ClearLeft(y + 3, FrameBottom - 1);
    exit;
  end;

  KeepPackVisible;
  for i := packTop to packTop + PackRows - 1 do begin
    if ( i < Synth.PacksKnown ) then begin
      if ( i = Synth.PackIndex ) then mark := ChPlaying + ' ' else mark := '  ';
      if ( Synth.Packs[i].Kind in ['M', 'R'] ) then kind := Synth.Packs[i].Kind else kind := '';
      if ( i = packSel ) and ( tab = menuIndex ) then
        LeftRow(y, mark + PackName(i), kind, ColorHighlightText, ColorHighlightBack)
      else
        LeftRow(y, mark + PackName(i), kind, ColorText, ColorBackground);
    end
    else
      LeftLine(y, '', ColorText, ColorBackground);
    inc(y);
  end;
  ClearLeft(y, FrameBottom - 3);
  LeftLine(FrameBottom - 2, ChPlaying + ' playing now', ColorNote, ColorBackground);
  LeftLine(FrameBottom - 1, 'M modelled   R recorded', ColorNote, ColorBackground);
end;

procedure DrawSynthRight;
var
  y:byte;
begin
  y := PanelTop;
  RightHeading(y, 'HDD Synth');
  if Synth.Present then begin
    RightField(y, 'Firmware', Synth.Firmware);
    RightField(y, 'State', StateText(Synth.State));
    RightField(y, 'Pack', PackName(Synth.PackIndex));
    RightField(y, 'Volume', VolumeBar(Synth.Volume));
    RightField(y, 'Balance', BalanceBar(Synth.Balance));
    RightField(y, 'Supercap', SupercapText);
  end
  else begin
    RightField(y, 'Not answering', '');
    if ( LastAck.Reason = 'nosynth' ) then
      RightField(y, '', 'Is the Synth Link connected?');
  end;
  RightGap(y);
  RightHeading(y, 'IDE Synth Bay');
  BayFields(y);
  ClearRight(y);
end;

{ ////////////////// Bay tab ////////////////// }

procedure BuildBayRows;
var
  i:integer;
  hasHard,hasCd:boolean;
begin
  bayRowCount := 0;
  hasHard := false;
  hasCd := false;
  for i := 0 to Bay.FileCount - 1 do begin
    if ( Bay.Files[i].Kind = KindHardDisk ) then hasHard := true;
    if ( Bay.Files[i].Kind = KindCdRom ) then hasCd := true;
  end;
  if hasHard then begin
    bayRows[bayRowCount] := RowHardDisks;
    inc(bayRowCount);
    for i := 0 to Bay.FileCount - 1 do
      if ( Bay.Files[i].Kind = KindHardDisk ) then begin
        bayRows[bayRowCount] := i;
        inc(bayRowCount);
      end;
  end;
  if hasCd then begin
    bayRows[bayRowCount] := RowCdRoms;
    inc(bayRowCount);
    for i := 0 to Bay.FileCount - 1 do
      if ( Bay.Files[i].Kind = KindCdRom ) then begin
        bayRows[bayRowCount] := i;
        inc(bayRowCount);
      end;
  end;
end;

function BayListRows:integer;
begin
  BayListRows := FrameBottom - 2 - PanelTop;
end;

{ Move the selection by a step, skipping the headings }
procedure MoveBaySel(step:integer);
var
  next:integer;
begin
  if ( bayRowCount = 0 ) then exit;
  next := baySel;
  repeat
    next := next + step;
    if ( next < 0 ) or ( next >= bayRowCount ) then exit;
  until bayRows[next] >= 0;
  baySel := next;
end;

procedure KeepBayVisible;
begin
  if ( baySel >= bayRowCount ) then baySel := bayRowCount - 1;
  if ( baySel < 0 ) then baySel := 0;
  if ( bayRowCount > 0 ) and ( bayRows[baySel] < 0 ) then MoveBaySel(1);
  if ( baySel < bayTop ) then bayTop := baySel;
  { Show a heading above the first file under it }
  if ( bayTop > 0 ) and ( bayRows[bayTop - 1] < 0 ) and ( baySel = bayTop ) then dec(bayTop);
  if ( baySel >= bayTop + BayListRows ) then bayTop := baySel - BayListRows + 1;
  if ( bayTop < 0 ) then bayTop := 0;
end;

function SelectedFile:integer;
begin
  SelectedFile := -1;
  if ( baySel >= 0 ) and ( baySel < bayRowCount ) then SelectedFile := bayRows[baySel];
end;

{ 0 or 1 for a file in device 0 or the CD-ROM drive now, '' otherwise }
function InUseMark(index:integer):string;
begin
  InUseMark := '  ';
  if ( Bay.Files[index].Name = BayValue('device0') ) then InUseMark := '0 '
  else if ( Bay.Files[index].Name = BayValue('disc') ) and ( BayValue('device1') = 'cdrom' ) then InUseMark := '1 ';
end;

procedure DrawBayLeft;
var
  y:byte;
  i,row,count,kindCount:integer;
  fore:byte;
  heading:string;
begin
  BuildBayRows;
  KeepBayVisible;
  y := PanelTop;
  if ( bayRowCount = 0 ) then begin
    LeftLine(y, 'SD card', ColorHeadingText, ColorHeadingBack);
    LeftLine(y + 1, '', ColorText, ColorBackground);
    LeftLine(y + 2, 'No images on the card, or the', ColorText, ColorBackground);
    LeftLine(y + 3, 'Bay didn''t list them', ColorText, ColorBackground);
    ClearLeft(y + 4, FrameBottom - 1);
    exit;
  end;

  for row := bayTop to bayTop + BayListRows - 1 do begin
    if ( row >= bayRowCount ) then
      LeftLine(y, '', ColorText, ColorBackground)
    else if ( bayRows[row] < 0 ) then begin
      if ( bayRows[row] = RowHardDisks ) then heading := 'Hard disk images' else heading := 'CD-ROM images';
      kindCount := 0;
      for i := 0 to Bay.FileCount - 1 do
        if ( ( bayRows[row] = RowHardDisks ) and ( Bay.Files[i].Kind = KindHardDisk ) )
           or ( ( bayRows[row] = RowCdRoms ) and ( Bay.Files[i].Kind = KindCdRom ) ) then inc(kindCount);
      LeftRow(y, heading, IntToStr(kindCount), ColorHeadingText, ColorHeadingBack);
    end
    else begin
      i := bayRows[row];
      if ( row = baySel ) and ( tab = menuIndex ) then
        LeftRow(y, InUseMark(i) + Bay.Files[i].Name, SizeText(Bay.Files[i].SizeKB),
                ColorHighlightText, ColorHighlightBack)
      else begin
        if ( InUseMark(i) <> '  ' ) then fore := ColorHighlightText else fore := ColorText;
        LeftRow(y, InUseMark(i) + Bay.Files[i].Name, SizeText(Bay.Files[i].SizeKB), fore, ColorBackground);
      end;
    end;
    inc(y);
  end;
  ClearLeft(y, FrameBottom - 2);
  LeftLine(FrameBottom - 1, '0 / 1 in device 0 / 1 now', ColorNote, ColorBackground);
end;

procedure DrawBayRight;
var
  y:byte;
  i:integer;
  inUse:string;
begin
  y := PanelTop;
  i := SelectedFile;
  if ( i >= 0 ) then begin
    RightHeading(y, Bay.Files[i].Name);
    if ( Bay.Files[i].Kind = KindCdRom ) then RightField(y, 'Kind', 'CD-ROM image')
    else RightField(y, 'Kind', 'Hard disk image');
    RightField(y, 'Size', SizeText(Bay.Files[i].SizeKB));
    inUse := InUseMark(i);
    if ( inUse = '0 ' ) then RightField(y, 'Now in', 'device 0, the hard disk')
    else if ( inUse = '1 ' ) then RightField(y, 'Now in', 'the CD-ROM drive')
    else RightField(y, 'Now in', 'nothing');
    if ( Bay.Files[i].Name = BayValue('device0_next') ) then RightField(y, 'Next boot', 'device 0');
    RightGap(y);
    if ( Bay.Files[i].Kind = KindCdRom ) then begin
      RightLine(y, 'Enter puts it in the CD-ROM drive now,', ColorNote, ColorBackground); inc(y);
      RightLine(y, 'as if you changed the disc.', ColorNote, ColorBackground); inc(y);
    end
    else begin
      RightLine(y, 'Enter makes it the hard disk from the', ColorNote, ColorBackground); inc(y);
      RightLine(y, 'next power-on. Until then DOS keeps', ColorNote, ColorBackground); inc(y);
      RightLine(y, 'running from ' + BayValue('device0') + '.', ColorNote, ColorBackground); inc(y);
    end;
    RightGap(y);
  end;
  RightHeading(y, 'IDE Synth Bay');
  BayFields(y);
  ClearRight(y);
end;

{ ////////////////// Floppy tab ////////////////// }

{ As floppies are sized: 1.44 MB, 1.2 MB, 720 KB }
function FloppySize(kb:longint):string;
var
  s:string;
begin
  if ( kb < 1000 ) then begin
    FloppySize := IntToStr(kb) + ' KB';
    exit;
  end;
  s := IntToStr(( kb mod 1000 ) div 10);
  if ( length(s) < 2 ) then s := '0' + s;
  if ( s[2] = '0' ) then s[0] := #1;
  FloppySize := IntToStr(kb div 1000) + '.' + s + ' MB';
end;

{ e.g. 0.4 s }
function SecondsText(ms:longint):string;
begin
  SecondsText := IntToStr(ms div 1000) + '.' + IntToStr(( ms mod 1000 ) div 100) + ' s';
end;

function UpperText(s:string):string;
var
  i:integer;
begin
  for i := 1 to length(s) do s[i] := UpCase(s[i]);
  UpperText := s;
end;

{ The Duo's drive letters: 'A', 'AB' or 'B' }
function DuoLetters:string;
begin
  DuoLetters := DuoValue('drives');
end;

function TwoDuoDrives:boolean;
begin
  TwoDuoDrives := length(DuoLetters) >= 2;
end;

{ The image in drive `letter`, '' if none }
function DuoDisk(letter:char):string;
var
  disk:string;
begin
  disk := DuoValue(chr(ord(UpCase(letter)) + 32) + '_disk');
  if ( disk = '-' ) then disk := '';
  DuoDisk := disk;
end;

function DuoDiskText(disk:string):string;
begin
  if ( length(disk) = 0 ) then DuoDiskText := 'none'
  else if ( disk = 'welcome' ) then DuoDiskText := 'the welcome disk'
  else if ( disk = 'generated' ) then DuoDiskText := 'the test disk'
  else DuoDiskText := disk;
end;

{ The drive an image is in, or ' ' }
function DriveOfImage(i:integer):char;
var
  k:integer;
  letters:string;
begin
  DriveOfImage := ' ';
  letters := DuoLetters;
  for k := 1 to length(letters) do
    if ( UpperText(DuoDisk(letters[k])) = UpperText(Duo.Files[i].Name) ) then DriveOfImage := letters[k];
end;

function DuoVolume:integer;
var
  v:longint;
begin
  if FieldToInt(DuoValue('volume'), v) then DuoVolume := v else DuoVolume := 0;
end;

function DuoPackIndex:integer;
var
  v:longint;
begin
  if FieldToInt(DuoValue('pack_index'), v) then DuoPackIndex := v else DuoPackIndex := -1;
end;

{ The heading an image goes under: by its kind and size }
function DuoGroup(i:integer):integer;
begin
  with Duo.Files[i] do
    if ( Kind = DuoFlux ) then DuoGroup := Row35
    else if ( Kind <> DuoImage ) then DuoGroup := RowOther
    else if ( SizeKB = 160 ) or ( SizeKB = 180 ) or ( SizeKB = 320 ) or ( SizeKB = 360 ) or ( SizeKB = 1200 ) then
      DuoGroup := Row525
    else if ( SizeKB = 720 ) or ( SizeKB = 1440 ) or ( SizeKB = 1680 ) or ( SizeKB = 1722 ) or ( SizeKB = 2880 ) then
      DuoGroup := Row35
    else DuoGroup := RowOther;
end;

function IsFdHeading(code:integer):boolean;
begin
  IsFdHeading := ( code < 0 ) and ( code > RowFirstPack );
end;

procedure BuildFdRows;
const
  Groups: array[1..3] of integer = (Row35, Row525, RowOther);
var
  g,i:integer;
  any:boolean;
begin
  fdRowCount := 0;
  for g := 1 to 3 do begin
    any := false;
    for i := 0 to Duo.FileCount - 1 do
      if ( DuoGroup(i) = Groups[g] ) then begin
        if not any then begin
          fdRows[fdRowCount] := Groups[g];
          inc(fdRowCount);
          any := true;
        end;
        fdRows[fdRowCount] := i;
        inc(fdRowCount);
      end;
  end;
  if ( Duo.PackCount > 0 ) then begin
    fdRows[fdRowCount] := RowPacks;
    inc(fdRowCount);
    for i := 0 to Duo.PackCount - 1 do begin
      fdRows[fdRowCount] := RowFirstPack - i;
      inc(fdRowCount);
    end;
  end;
end;

function FdListRows:integer;
begin
  FdListRows := FrameBottom - 2 - PanelTop;
end;

procedure MoveFdSel(step:integer);
var
  next:integer;
begin
  if ( fdRowCount = 0 ) then exit;
  next := fdSel;
  repeat
    next := next + step;
    if ( next < 0 ) or ( next >= fdRowCount ) then exit;
  until not IsFdHeading(fdRows[next]);
  fdSel := next;
end;

procedure KeepFdVisible;
begin
  if ( fdSel >= fdRowCount ) then fdSel := fdRowCount - 1;
  if ( fdSel < 0 ) then fdSel := 0;
  if ( fdRowCount > 0 ) and IsFdHeading(fdRows[fdSel]) then MoveFdSel(1);
  if ( fdSel < fdTop ) then fdTop := fdSel;
  if ( fdTop > 0 ) and IsFdHeading(fdRows[fdTop - 1]) and ( fdSel = fdTop ) then dec(fdTop);
  if ( fdSel >= fdTop + FdListRows ) then fdTop := fdSel - FdListRows + 1;
  if ( fdTop < 0 ) then fdTop := 0;
end;

{ The highlighted row: an image (>= 0), a pack (<= RowFirstPack), or a heading }
function FdSelected:integer;
begin
  FdSelected := Row35;
  if ( fdSel >= 0 ) and ( fdSel < fdRowCount ) then FdSelected := fdRows[fdSel];
end;

procedure DrawFloppyLeft;
var
  y,fore:byte;
  row,code,i,count:integer;
  text,right,heading:string;
  inUse:boolean;
  letters:string;
begin
  y := PanelTop;
  if not Duo.Present then begin
    LeftLine(y, 'Disks', ColorHeadingText, ColorHeadingBack);
    LeftLine(y + 1, '', ColorText, ColorBackground);
    LeftLine(y + 2, 'Nothing to list: no Duo answered', ColorDim, ColorBackground);
    ClearLeft(y + 3, FrameBottom - 1);
    exit;
  end;
  BuildFdRows;
  KeepFdVisible;
  for row := fdTop to fdTop + FdListRows - 1 do begin
    if ( row >= fdRowCount ) then
      LeftLine(y, '', ColorText, ColorBackground)
    else begin
      code := fdRows[row];
      if IsFdHeading(code) then begin
        count := 0;
        case code of
          Row35: heading := '3.5in disks';
          Row525: heading := '5.25in disks';
          RowOther: heading := 'Other disks';
        else
          heading := 'Sound packs';
        end;
        if ( code = RowPacks ) then count := Duo.PackCount
        else for i := 0 to Duo.FileCount - 1 do if ( DuoGroup(i) = code ) then inc(count);
        LeftRow(y, heading, IntToStr(count), ColorHeadingText, ColorHeadingBack);
      end
      else begin
        if ( code <= RowFirstPack ) then begin
          i := RowFirstPack - code;
          inUse := i = DuoPackIndex;
          if inUse then text := ChPlaying + '  ' + Duo.Packs[i] else text := '   ' + Duo.Packs[i];
          right := '';
        end
        else begin
          inUse := DriveOfImage(code) <> ' ';
          text := DriveOfImage(code) + '  ' + copy(Duo.Files[code].Name, 1, 25);
          if ( Duo.Files[code].Kind = DuoFlux ) then right := 'flux' else right := FloppySize(Duo.Files[code].SizeKB);
        end;
        if ( row = fdSel ) and ( tab = menuIndex ) then
          LeftRow(y, text, right, ColorHighlightText, ColorHighlightBack)
        else begin
          if inUse then fore := ColorHighlightText else fore := ColorText;
          LeftRow(y, text, right, fore, ColorBackground);
        end;
      end;
    end;
    inc(y);
  end;
  ClearLeft(y, FrameBottom - 2);
  letters := DuoLetters;
  if TwoDuoDrives then text := 'A/B in drive A:/B:'
  else if ( length(letters) = 1 ) then text := letters + ' in drive ' + letters + ':'
  else text := '';
  LeftLine(FrameBottom - 1, text + '   ' + ChPlaying + ' playing now', ColorNote, ColorBackground);
end;

procedure RightNote(var y:byte; text:string);
begin
  if ( y >= FrameBottom ) then exit;
  RightLine(y, text, ColorNote, ColorBackground);
  inc(y);
end;

{ Why there's no Duo: what was found on each drive }
procedure NoDuoFields(var y:byte);
var
  d:integer;
  l:string;
begin
  RightLine(y, 'Not found', ColorBad, ColorBackground);
  inc(y);
  RightGap(y);
  if not DuoLooked then begin
    RightNote(y, 'Not looked for yet: R looks on the');
    RightNote(y, 'floppy drives (a second or two)');
    exit;
  end;
  RightLine(y, 'Looked for its mailbox at cylinder 82:', ColorText, ColorBackground);
  inc(y);
  for d := 0 to MaxFloppies - 1 do begin
    l := DriveLetter(d) + ':';
    case ProbeResult[d] of
      -1: RightField(y, ' ' + l, 'not set up in the BIOS');
      FxNoDisk: RightField(y, ' ' + l, 'not ready: no disk in?');
      FxRefused: RightField(y, ' ' + l, 'the BIOS refused cylinder 82');
    else
      RightField(y, ' ' + l, 'no answer: a real drive?');
    end;
  end;
  RightGap(y);
  RightNote(y, 'The Duo answers from its firmware');
  RightNote(y, '0.25.0 (its USB console''s h says),');
  RightNote(y, 'with a PC disk in the drive.');
end;

procedure DuoFields(var y:byte);
var
  letters:string;
begin
  if not Duo.Present then begin
    NoDuoFields(y);
    exit;
  end;
  letters := DuoLetters;
  RightField(y, 'Firmware', DuoValue('firmware'));
  if TwoDuoDrives then RightField(y, 'Drives', 'A: and B:')
  else RightField(y, 'Drives', letters + ': (one drive)');
  RightField(y, 'Mailbox', DuoValue('mailbox') + ':, cylinder 82');
  if ( DuoBackend = dbFloppy ) and ( ExchangeMs > 0 ) then RightField(y, 'Exchange', SecondsText(ExchangeMs));
  RightField(y, 'Volume', VolumeBar(DuoVolume));
  RightField(y, 'Pack', DuoValue('pack'));
end;

procedure DuoDriveFields(var y:byte; letter:char; full:boolean);
var
  k,disk:string;
begin
  if ( y + 2 >= FrameBottom ) then exit;
  RightGap(y);
  RightHeading(y, 'Drive ' + letter + ':');
  k := chr(ord(letter) + 32) + '_';
  disk := DuoDisk(letter);
  RightField(y, 'Disk', DuoDiskText(disk));
  if ( length(disk) = 0 ) then exit;
  RightField(y, 'Format', DuoValue(k + 'format'));
  if full then RightField(y, 'Head', 'cylinder ' + DuoValue(k + 'cylinder'));
  RightField(y, 'Motor', DuoValue(k + 'motor'));
  if full then begin
    if ( DuoValue(k + 'protect') = 'on' ) then RightField(y, 'Write', 'protected')
    else RightField(y, 'Write', 'allowed');
  end;
end;

procedure DrawFloppyRight;
var
  y:byte;
  code,k:integer;
  letters:string;
begin
  y := PanelTop;
  RightHeading(y, 'FDD Synth Duo');
  DuoFields(y);
  if Duo.Present then begin
    letters := DuoLetters;
    for k := 1 to length(letters) do DuoDriveFields(y, letters[k], not TwoDuoDrives);
    code := FdSelected;
    if ( code >= 0 ) and ( y + 3 < FrameBottom ) then begin
      RightGap(y);
      RightHeading(y, copy(Duo.Files[code].Name, 1, RightWidth - 2));
      case Duo.Files[code].Kind of
        DuoFlux: RightField(y, 'Kind', 'a flux image (HFE)');
        DuoAmiga: RightField(y, 'Kind', 'an Amiga disk');
      else
        RightField(y, 'Size', FloppySize(Duo.Files[code].SizeKB));
      end;
      if TwoDuoDrives then begin
        RightNote(y, 'Enter, or A or B, puts it in a drive');
        RightNote(y, 'now: DOS sees the disk change');
      end
      else begin
        RightNote(y, 'Enter puts it in ' + letters + ': now: DOS sees');
        RightNote(y, 'the disk change, as with a real drive');
      end;
    end
    else if ( code <= RowFirstPack ) and ( y + 2 < FrameBottom ) then begin
      RightGap(y);
      RightNote(y, 'Enter plays this sample pack');
    end;
  end;
  ClearRight(y);
end;

{ ////////////////// Settings tab ////////////////// }

{ A setting's value in words }
function SettingText(key, value:string):string;
begin
  if ( key = 'bus' ) then begin
    if ( value = 'early' ) then SettingText := 'early answers'
    else if ( value = 'lane' ) then SettingText := 'data lane'
    else if ( value = 'table' ) then SettingText := 'register table'
    else if ( value = 'noiordy' ) then SettingText := 'no IORDY'
    else SettingText := value;
  end
  else if ( ( key = 'dma' ) or ( key = 'mode' ) ) and ( length(value) > 3 )
          and ( ( copy(value, 1, 3) = 'pio' ) or ( copy(value, 1, 3) = 'mdm' ) or ( copy(value, 1, 3) = 'udm' ) ) then
    SettingText := UpperText(copy(value, 1, length(value) - 1)) + ' ' + value[length(value)]
  else if ( key = 'fd:drive' ) then begin
    if ( value = 'a_b' ) or ( value = 'a,b' ) then SettingText := 'A: and B:'
    else if ( value = 'b' ) then SettingText := 'B: only'
    else if ( value = 'a' ) then SettingText := 'A: only'
    else SettingText := value;
  end
  else if ( ( key = 'fd:device0' ) or ( key = 'fd:device1' ) ) and ( ( value = '-' ) or ( value = '' ) ) then
    SettingText := 'the last one in'
  else if ( key = 'device1' ) and ( value = 'cdrom' ) then SettingText := 'CD-ROM drive'
  else if ( key = 'sd_high_speed' ) and ( value = 'on' ) then SettingText := 'high'
  else if ( key = 'sd_high_speed' ) and ( value = 'off' ) then SettingText := 'normal'
  else SettingText := value;
end;

function IsDuoRow(row:integer):boolean;
begin
  IsDuoRow := row >= DuoFirstRow;
end;

{ Shown only: SET refuses these, HDDSYNTH.INI sets them }
function IsShownOnlyRow(row:integer):boolean;
begin
  IsShownOnlyRow := ( row >= ShownFirstRow ) and ( row < DuoFirstRow );
end;

{ The Bay's rows show when it lists its settings (the bus's when it lists
  them too), the Duo's when it does }
function RowShown(row:integer):boolean;
begin
  if IsDuoRow(row) then RowShown := Duo.SettingCount > 0
  else if IsShownOnlyRow(row) then RowShown := SettingIndex('bus') > 0
  else RowShown := Bay.SettingCount > 0;
end;

{ A row's setting as the Bay or the Duo gives it: false if it didn't }
function RowSetting(row:integer; var next, now:string):boolean;
var
  i:integer;
  key:string;
begin
  RowSetting := false;
  key := SettingRows[row].Key;
  if IsDuoRow(row) then begin
    i := DuoSettingIndex(copy(key, 4, 20));
    if ( i = 0 ) then exit;
    next := Duo.Settings[i].Next;
    now := Duo.Settings[i].Now;
  end
  else begin
    i := SettingIndex(key);
    if ( i = 0 ) then exit;
    next := Bay.Settings[i].Next;
    now := Bay.Settings[i].Now;
  end;
  RowSetting := true;
end;

{ Move the Settings tab's selection by a step, skipping headings and rows not shown }
procedure MoveSetSel(step:integer);
var
  next:integer;
begin
  next := setSel;
  repeat
    next := next + step;
    if ( next < 1 ) or ( next > SettingRowCount ) then exit;
  until ( length(SettingRows[next].Key) > 0 ) and RowShown(next);
  setSel := next;
end;

procedure DrawSettingsLeft;
var
  y,fore,back:byte;
  row:integer;
  mark,text,next,now:string;
begin
  y := PanelTop;
  if ( Bay.SettingCount = 0 ) and ( Duo.SettingCount = 0 ) then begin
    LeftLine(y, 'Settings', ColorHeadingText, ColorHeadingBack);
    LeftLine(y + 1, '', ColorText, ColorBackground);
    LeftLine(y + 2, 'This Bay''s firmware can''t show its', ColorText, ColorBackground);
    LeftLine(y + 3, 'settings: IDE Synth Bay 0.36.0 or', ColorText, ColorBackground);
    LeftLine(y + 4, 'later can.', ColorText, ColorBackground);
    ClearLeft(y + 5, FrameBottom - 1);
    exit;
  end;
  if ( setSel < 1 ) or ( setSel > SettingRowCount ) or ( length(SettingRows[setSel].Key) = 0 )
     or not RowShown(setSel) then begin
    setSel := 0;
    MoveSetSel(1);
  end;
  for row := 1 to SettingRowCount do begin
    if not RowShown(row) then
      { not this one's }
    else if ( length(SettingRows[row].Key) = 0 ) then begin
      LeftLine(y, SettingRows[row].Caption, ColorHeadingText, ColorHeadingBack);
      inc(y);
    end
    else begin
      mark := ' ';
      text := '  ' + PadRight(SettingRows[row].Caption, 17);
      if RowSetting(row, next, now) and IsShownOnlyRow(row) then
        text := text + SettingText(SettingRows[row].Key, now)  { What runs: the file may say auto }
      else if RowSetting(row, next, now) then begin
        text := text + SettingText(SettingRows[row].Key, next);
        if ( next <> now ) then mark := ChChanged;
      end
      else
        text := text + '-';
      fore := ColorText;
      back := ColorBackground;
      if ( row = setSel ) and ( tab = menuIndex ) then begin
        fore := ColorHighlightText;
        back := ColorHighlightBack;
      end;
      LeftRow(y, text, mark, fore, back);
      inc(y);
    end;
  end;
  ClearLeft(y, FrameBottom - 2);
  LeftLine(FrameBottom - 1, ChChanged + ' changed: from the next power-on', ColorNote, ColorBackground);
end;

{ What a setting does, in a few lines for the right panel }
procedure SettingWords(var y:byte; key:string);

  procedure Say(text:string);
  begin
    if ( y >= FrameBottom ) then exit;
    RightLine(y, text, ColorText, ColorBackground);
    inc(y);
  end;

begin
  if ( key = 'device1' ) then begin
    Say('The second drive on the cable: a');
    Say('CD-ROM drive, a disk image, or none.');
    Say('With a CD-ROM drive the Bay keeps to');
    Say('its plain bus program, and DMA needs');
    Say('dma = on in HDDSYNTH.INI.');
  end
  else if ( key = 'cdrom' ) then begin
    Say('The disc in the CD-ROM drive when the');
    Say('PC starts. To change the disc now, use');
    Say('the Bay tab.');
  end
  else if ( key = 'seek_timing' ) then begin
    Say('Hold each disk command for as long as');
    Say('a real drive would take: the seek,');
    Say('the platter coming round, the');
    Say('transfer. synth follows the drive the');
    Say('HDD Synth is playing.');
  end
  else if ( key = 'activity_link' ) then begin
    Say('Tell the HDD Synth what the drive is');
    Say('doing and where its head goes, so the');
    Say('synth''s sounds follow the PC.');
  end
  else if ( key = 'write_behind' ) then begin
    Say('Take each write while it''s still being');
    Say('stored: writes about a third faster.');
    Say('A power cut mid-write can lose that');
    Say('sector.');
  end
  else if ( key = 'read_ahead' ) then begin
    Say('Fetch the next sector while the PC');
    Say('reads this one: faster reads.');
  end
  else if ( key = 'bus' ) then begin
    Say('How the Bay answers the IDE bus: early');
    Say('answers, the data lane (faster), plain');
    Say('ide_bus, or the register table. auto');
    Say('learns the PC at each reset.');
  end
  else if ( key = 'dma' ) then begin
    Say('Multiword DMA, offered to the PC: auto');
    Say('offers it once the Bay has learned the');
    Say('PC can take it.');
  end
  else if ( key = 'mode' ) then begin
    Say('The fastest PIO (or DMA) mode IDENTIFY');
    Say('offers the PC.');
  end
  else if ( key = 'geometry' ) then begin
    Say('The cylinders, heads and sectors the');
    Say('BIOS sees: from the image''s partition');
    Say('table, or set for an old drive''s image.');
  end
  else if ( key = 'fd:drive' ) then begin
    Say('The FDD Synth Duo answers as drive A:,');
    Say('or as A: and B: with a disk in each.');
    Say('For B:, the PC''s BIOS setup must have');
    Say('a drive B: (3.5in, 1.44 MB), and each');
    Say('image can be up to 3 MB (4.5 MB alone).');
  end
  else if ( key = 'fd:device0' ) or ( key = 'fd:device1' ) then begin
    Say('The disk in the drive when the Duo');
    Say('starts, every time. The last one in:');
    Say('it starts with the disk it had when');
    Say('it was switched off, as a GoTek does.');
  end
  else if ( key = 'sd_high_speed' ) then begin
    Say('Read the SD card at 40 MHz instead of');
    Say('20 (the PCB). The Bay checks the card');
    Say('at every start, and goes back to the');
    Say('normal speed by itself if it must.');
  end;
end;

procedure DrawSettingsRight;
var
  y:byte;
  key,next,now:string;
  duoRow:boolean;
begin
  y := PanelTop;
  duoRow := false;
  if ( setSel >= 1 ) and ( setSel <= SettingRowCount ) and RowShown(setSel)
     and ( length(SettingRows[setSel].Key) > 0 ) then begin
    key := SettingRows[setSel].Key;
    duoRow := IsDuoRow(setSel);
    if duoRow then RightHeading(y, SettingRows[setSel].Caption + ' (FDD Synth Duo)')
    else RightHeading(y, SettingRows[setSel].Caption);
    RightGap(y);
    SettingWords(y, key);
    RightGap(y);
    if RowSetting(setSel, next, now) and IsShownOnlyRow(setSel) then begin
      RightField(y, 'Now', SettingText(key, now));
      RightField(y, 'The file', SettingText(key, next));
    end
    else if RowSetting(setSel, next, now) then begin
      RightField(y, 'Now', SettingText(key, now));
      RightField(y, 'Next start', SettingText(key, next));
    end;
    RightGap(y);
    if IsShownOnlyRow(setSel) then begin
      RightNote(y, 'Shown only: the PC must be right for');
      RightNote(y, 'it, so it''s set in HDDSYNTH.INI.');
    end
    else if duoRow then begin
      RightNote(y, 'Enter changes it: the Duo reads it when');
      RightNote(y, 'it starts, the next time the PC is on.');
    end
    else begin
      RightNote(y, 'Enter changes it, from the next');
      RightNote(y, 'power-on: the PC runs from the Bay.');
    end;
    RightGap(y);
  end;
  if duoRow then begin
    RightHeading(y, 'FDD Synth Duo');
    DuoFields(y);
  end
  else begin
    RightHeading(y, 'IDE Synth Bay');
    BayFields(y);
  end;
  ClearRight(y);
end;

{ ////////////////// Screen ////////////////// }

procedure DrawMenu;
var
  i:integer;
begin
  GotoXY(1, 1);
  TextBackground(ColorBackground);
  write(PadRight('', Columns));
  GotoXY(1, 1);
  for i := 0 to MenuCount - 1 do begin
    if ( i = menuIndex ) then begin
      TextColor(ColorMenuHighlightText);
      TextBackground(ColorMenuHighlightBack);
    end
    else begin
      TextColor(ColorMenuText);
      TextBackground(ColorBackground);
    end;
    write(MenuCaptions[i]);
    TextBackground(ColorBackground);
    write('  ');
  end;
  WriteAt(Columns - length(ApplicationName) + 1, 1, ApplicationName, ColorMenuHighlightText, ColorMenuHighlightBack);
  WriteAt(1, 2, PadRight(MenuHints[menuIndex], Columns), ColorText, ColorBackground);
end;

procedure DrawFooterKeys;
begin
  if ( tab = MenuSynth ) then
    DrawFooter(' [F1] Help  [Enter] Play pack  [+/-] Volume  [</>] Balance  [R] Refresh  [Esc] Exit')
  else if ( tab = MenuSettings ) then
    DrawFooter(' [F1] Help  [Enter] Change  [R] Refresh  [Esc] Exit')
  else if ( tab = MenuFloppy ) and not Duo.Present then
    DrawFooter(' [F1] Help  [R] Look again  [Esc] Exit')
  else if ( tab = MenuFloppy ) and TwoDuoDrives then
    DrawFooter(' [F1] Help  [Enter] Insert  [A]/[B] Into A:/B:  [E] Eject  [+/-] Volume  [Esc] Exit')
  else if ( tab = MenuFloppy ) then
    DrawFooter(' [F1] Help  [Enter] Insert  [E] Eject  [+/-] Volume  [R] Refresh  [Esc] Exit')
  else
    DrawFooter(' [F1] Help  [Enter] Insert/Boot  [E] Eject disc  [R] Refresh  [Esc] Exit');
end;

procedure DrawAll;
var
  where:string;
begin
  TextBackground(ColorBackground);
  DrawMenu;
  DrawFrame;
  if ( tab = MenuSynth ) then begin
    DrawSynthLeft;
    DrawSynthRight;
  end
  else if ( tab = MenuSettings ) then begin
    DrawSettingsLeft;
    DrawSettingsRight;
  end
  else if ( tab = MenuFloppy ) then begin
    DrawFloppyLeft;
    DrawFloppyRight;
  end
  else begin
    DrawBayLeft;
    DrawBayRight;
  end;

  if ( tab = MenuFloppy ) then begin
    if ( DuoBackend = dbDemo ) then where := 'Demo: a pretend Duo'
    else if ( DuoBackend = dbFloppy ) and TwoDuoDrives then where := 'Duo on drives A: and B: (cylinder 82)'
    else if ( DuoBackend = dbFloppy ) then where := 'Duo on drive ' + DriveLetter(DuoDrive) + ': (cylinder 82)'
    else where := 'No Duo on A: or B:';
  end
  else if ( Backend = bkDemo ) then where := 'Demo: a pretend Bay and synth'
  else if ( Backend = bkNone ) then where := 'No IDE Synth Bay found'
  else where := 'Bay on the ' + DriveName(BayDrive);
  FrameNote(4, where);
  if ( length(note) > 0 ) then begin
    if ( length(note) > Columns - 12 - length(where) ) then note[0] := chr(Columns - 12 - length(where));
    FrameNote(length(where) + 10, note);
  end;
  DrawFooterKeys;
end;

{ ////////////////// Dialogs ////////////////// }

{ A question with Yes and No. Enter or Y for yes; Esc or N for no }
function Confirm(title, line1, line2, yesCaption:string):boolean;
const
  Width = 60;
var
  x1,y1:byte;
  yes,done:boolean;
  key:char;

  procedure Buttons;
  var
    fore,back:byte;
  begin
    if yes then begin fore := White; back := Green; end else begin fore := Black; back := LightGray; end;
    WriteAt(x1 + 14, y1 + 5, ' ' + yesCaption + ' ', fore, back);
    if not yes then begin fore := White; back := Green; end else begin fore := Black; back := LightGray; end;
    WriteAt(x1 + Width - 24, y1 + 5, ' Cancel ', fore, back);
  end;

begin
  x1 := ( Columns - Width ) div 2;
  y1 := 9;
  DrawBox(x1, y1, x1 + Width, y1 + 7, title);
  WriteAt(x1 + 3, y1 + 2, PadRight(line1, Width - 5), Black, LightGray);
  WriteAt(x1 + 3, y1 + 3, PadRight(line2, Width - 5), Black, LightGray);
  yes := true;
  done := false;
  repeat
    Buttons;
    key := ReadKey;
    case key of
      #0: begin
        key := ReadKey;
        if ( key = #75 ) or ( key = #77 ) then yes := not yes;
      end;
      #9: yes := not yes;
      #13: done := true;
      #27, 'n', 'N': begin yes := false; done := true; end;
      'y', 'Y': begin yes := true; done := true; end;
    end;
  until done;
  Confirm := yes;
end;

procedure Help;
const
  Width = 64;
  Lines = 18;
  HelpText: array[1..Lines] of string[60] = (
    'Left/Right  the menu: Synth, Bay, Floppy, Settings...',
    'Up/Down     move through the list',
    'Enter       on Synth: play the highlighted pack',
    '            on Bay: put a CD image in the CD-ROM drive, or',
    '            make a disk image the hard disk at next power-on',
    '            on Floppy: put the disk in the Duo''s drive now,',
    '            or play its sample pack',
    '            on Settings: change the highlighted setting',
    'A B         on Floppy: put the disk in A: or B:',
    '+ -         volume (on Floppy: the Duo''s); < > balance',
    'E           take out the CD (on Floppy: the floppy)',
    'R           ask the Bay, the synth and the Duo again',
    'Esc         exit to DOS',
    '',
    'The Bay''s hard disk can''t change while DOS runs from it,',
    'so a new one waits for the next power-on. A floppy changes',
    'at once; each change to the Duo takes a second or so, as',
    'it goes through the disk (cylinder 82, past the end).');
var
  x1,y1:byte;
  i:integer;
begin
  x1 := ( Columns - Width ) div 2;
  y1 := 4;
  DrawBox(x1, y1, x1 + Width, y1 + Lines + 3, 'Help');
  for i := 1 to Lines do
    WriteAt(x1 + 3, y1 + 1 + i, PadRight(HelpText[i], Width - 5), Black, LightGray);
  WriteAt(x1 + Width div 2 - 8, y1 + Lines + 2, ' Press any key ', Blue, LightGray);
  if ( ReadKey = #0 ) then ReadKey;
end;

{ Choose one of choiceValue[1..choiceCount] (choiceWords beside each),
  starting at `start`: its index, or 0 for Esc }
function Choose(title:string; start:integer):integer;
const
  Width = 60;
  Shown = 10;
var
  x1,y1:byte;
  sel,top,i:integer;
  key:char;
  done:boolean;
  fore,back:byte;
begin
  Choose := 0;
  if ( choiceCount = 0 ) then exit;
  x1 := ( Columns - Width ) div 2;
  y1 := 5;
  DrawBox(x1, y1, x1 + Width, y1 + Shown + 4, title);
  WriteAt(x1 + 14, y1 + Shown + 3, ' Enter Choose   Esc Leave it ', Blue, LightGray);
  sel := start;
  if ( sel < 1 ) or ( sel > choiceCount ) then sel := 1;
  top := 1;
  done := false;
  repeat
    if ( sel < top ) then top := sel;
    if ( sel >= top + Shown ) then top := sel - Shown + 1;
    for i := top to top + Shown - 1 do begin
      if ( i = sel ) then begin fore := White; back := Green; end else begin fore := Black; back := LightGray; end;
      if ( i <= choiceCount ) then
        WriteAt(x1 + 2, y1 + 2 + i - top, ' ' + PadRight(choiceValue[i], 13) + PadRight(choiceWords[i], Width - 18),
                fore, back)
      else
        WriteAt(x1 + 2, y1 + 2 + i - top, PadRight('', Width - 3), Black, LightGray);
    end;
    key := ReadKey;
    case key of
      #0: begin
        key := ReadKey;
        case key of
          #72: if ( sel > 1 ) then dec(sel);
          #80: if ( sel < choiceCount ) then inc(sel);
          #73: begin sel := sel - Shown; if ( sel < 1 ) then sel := 1; end;
          #81: begin sel := sel + Shown; if ( sel > choiceCount ) then sel := choiceCount; end;
          #71: sel := 1;
          #79: sel := choiceCount;
        end;
      end;
      #13: begin Choose := sel; done := true; end;
      #27: done := true;
    end;
  until done;
end;

procedure AddChoice(value, words:string);
begin
  if ( choiceCount >= MaxChoices ) then exit;
  inc(choiceCount);
  choiceValue[choiceCount] := value;
  choiceWords[choiceCount] := words;
end;

{ ////////////////// Changes ////////////////// }

procedure Done(ok:boolean; message:string);
begin
  note := message;
  noteGood := ok;
end;

procedure SetVolume(volume:integer);
var
  message:string;
begin
  if not Synth.Present then exit;
  if ( volume < 0 ) then volume := 0;
  if ( volume > 100 ) then volume := 100;
  if Command('HDC,1,VOL,' + IntToStr(volume), message) then begin
    Request('HDQ,1,STATUS');
    Done(true, 'Volume ' + IntToStr(Synth.Volume));
  end
  else Done(false, message);
end;

procedure SetBalance(balance:integer);
var
  message:string;
begin
  if not Synth.Present then exit;
  if ( balance < 0 ) then balance := 0;
  if ( balance > 100 ) then balance := 100;
  if Command('HDC,1,BAL,' + IntToStr(balance), message) then begin
    Request('HDQ,1,STATUS');
    Done(true, 'Balance ' + IntToStr(Synth.Balance));
  end
  else Done(false, message);
end;

procedure PlayPack;
var
  message:string;
begin
  if not Synth.Present or ( packSel >= Synth.PacksKnown ) then exit;
  if ( packSel = Synth.PackIndex ) then begin
    Done(true, 'Already playing');
    exit;
  end;
  if Command('HDC,1,PACK,' + IntToStr(packSel), message) then begin
    Request('HDQ,1,STATUS');
    Done(true, 'Playing ' + PackName(packSel));
  end
  else Done(false, message);
end;

procedure InsertOrBoot;
var
  i:integer;
  message,name:string;
begin
  i := SelectedFile;
  if ( i < 0 ) then exit;
  name := Bay.Files[i].Name;
  if ( Bay.Files[i].Kind = KindCdRom ) then begin
    if ( BayValue('device1') <> 'cdrom' ) then begin
      Done(false, 'The Bay has no CD-ROM drive set up');
      exit;
    end;
    if ( name = BayValue('disc') ) then begin
      Done(true, 'Already in the drive');
      exit;
    end;
    if not Confirm('Change disc', 'Put ' + name + ' in the CD-ROM drive?',
                   'Programs using the CD-ROM see the disc change.', 'Insert') then exit;
    if Command('SBC,1,DISC,' + name, message) then Done(true, name + ' is in the drive')
    else Done(false, message);
  end
  else begin
    if ( name = BayValue('device0') ) and ( length(BayValue('device0_next')) = 0 ) then begin
      Done(true, 'Already the hard disk');
      exit;
    end;
    if not Confirm('Next boot''s hard disk', 'Make ' + name + ' the hard disk from the next power-on?',
                   'DOS keeps running from ' + BayValue('device0') + ' until then.', 'Use it') then exit;
    if Command('SBC,1,SET,device0,' + name, message) then Done(true, name + ' from the next power-on')
    else Done(false, message);
  end;
  RefreshBay;
end;

procedure Eject;
var
  message:string;
begin
  if ( BayValue('device1') <> 'cdrom' ) or ( BayValue('disc') = '-' ) or ( length(BayValue('disc')) = 0 ) then begin
    Done(true, 'No disc to take out');
    exit;
  end;
  if not Confirm('Eject', 'Take ' + BayValue('disc') + ' out of the CD-ROM drive?', '', 'Eject') then exit;
  if Command('SBC,1,DISC,-', message) then Done(true, 'The CD-ROM drive is empty')
  else Done(false, message);
  RefreshBay;
end;

{ ////////////////// The Duo's changes ////////////////// }

{ Waits `ticks` of the BIOS's clock, 18.2 a second }
procedure WaitTicks(ticks:longint);
var
  start:longint;
begin
  start := MemL[$40:$6C];
  repeat until ( MemL[$40:$6C] - start >= ticks ) or ( MemL[$40:$6C] < start );
end;

{ The drive SynthMinder runs from, if it's a floppy: 'A', 'B', or ' ' }
function RunDrive:char;
var
  path:string;
begin
  path := ParamStr(0);
  RunDrive := ' ';
  if ( length(path) > 1 ) and ( path[2] = ':' ) and ( UpCase(path[1]) in ['A', 'B'] ) then RunDrive := UpCase(path[1]);
end;

{ After an insert or eject: the disk is out for half a second, then goes in
  once the Duo has it in memory. Waits for that and asks again: true once
  `letter` holds `name` ('' for none). DOS is then told the disk changed }
function AwaitSwap(letter:char; name:string):boolean;
var
  tries:integer;
  other:char;
begin
  AwaitSwap := false;
  { With two drives, talk through the other while this one swaps }
  if ( DuoBackend = dbFloppy ) and TwoDuoDrives and ( letter = DriveLetter(DuoDrive) ) then begin
    if ( letter = 'A' ) then other := 'B' else other := 'A';
    if ( length(DuoDisk(other)) > 0 ) then DuoDrive := ord(other) - ord('A');
  end;
  for tries := 1 to 4 do begin
    if ( DuoBackend = dbFloppy ) then WaitTicks(18);
    RefreshDuo;
    if Duo.Present and ( UpperText(DuoDisk(letter)) = UpperText(name) ) then begin
      AwaitSwap := true;
      if ( DuoBackend = dbFloppy ) and ( length(name) > 0 ) then TellDos(ord(letter) - ord('A'));
      exit;
    end;
  end;
end;

{ A drive for an image: the only one, or the one chosen. ' ' for Esc }
function ChooseDrive(title:string):char;
var
  letters,disk:string;
  k,pick:integer;
begin
  letters := DuoLetters;
  ChooseDrive := ' ';
  if ( length(letters) = 0 ) then exit;
  if ( length(letters) = 1 ) then begin
    ChooseDrive := letters[1];
    exit;
  end;
  choiceCount := 0;
  for k := 1 to length(letters) do begin
    disk := DuoDisk(letters[k]);
    if ( length(disk) = 0 ) then AddChoice(letters[k] + ':', 'empty')
    else AddChoice(letters[k] + ':', DuoDiskText(disk) + ' comes out');
  end;
  pick := Choose(title, 1);
  if ( pick > 0 ) then ChooseDrive := choiceValue[pick][1];
end;

procedure InsertFloppy(i:integer; letter:char);
var
  name,message,inThere:string;
begin
  name := Duo.Files[i].Name;
  if ( pos(letter, DuoLetters) = 0 ) then begin
    Done(false, 'The Duo has no drive ' + letter + ':');
    exit;
  end;
  inThere := DuoDisk(letter);
  if ( UpperText(inThere) = UpperText(name) ) then begin
    Done(true, name + ' is in ' + letter + ': already');
    exit;
  end;
  if ( RunDrive = letter ) and ( length(inThere) > 0 ) then
    if not Confirm('Swap the disk in ' + letter + ':?', 'SynthMinder is running from ' + letter + ': ('
                   + DuoDiskText(inThere) + '). DOS may', 'not find the rest. Put ' + name + ' in anyway?',
                   'Swap') then exit;
  if ( DuoBackend = dbFloppy ) then FlushDos;  { Anything DOS holds for the old disk, onto it }
  if not Command('FDC,1,INSERT,' + letter + ',' + name, message) then begin
    Done(false, message);
    exit;
  end;
  if AwaitSwap(letter, name) then begin
    if ( DuoBackend = dbFloppy ) then
      Done(true, 'Put ' + name + ' in ' + letter + ': (' + SecondsText(ExchangeMs) + ')')
    else Done(true, 'Put ' + name + ' in ' + letter + ':');
  end
  else Done(true, name + ' is going into ' + letter + ': (R to see)');
end;

procedure FloppyInto(letter:char);
var
  code:integer;
begin
  if not Duo.Present then exit;
  code := FdSelected;
  if ( code >= 0 ) then InsertFloppy(code, letter);
end;

procedure PlayDuoPack(i:integer);
var
  message:string;
begin
  if ( i = DuoPackIndex ) then begin
    Done(true, 'Already playing');
    exit;
  end;
  if Command('FDC,1,PACK,' + IntToStr(i), message) then begin
    ApplyReply(MakeSentence('FDV,1,pack_index,' + IntToStr(i)));
    ApplyReply(MakeSentence('FDV,1,pack,' + Duo.Packs[i]));
    Done(true, 'The Duo plays ' + Duo.Packs[i]);
  end
  else Done(false, message);
end;

procedure FloppyEnter;
var
  code:integer;
  letter:char;
begin
  if not Duo.Present then exit;
  code := FdSelected;
  if ( code <= RowFirstPack ) then PlayDuoPack(RowFirstPack - code)
  else if ( code >= 0 ) then begin
    letter := ChooseDrive('Insert ' + copy(Duo.Files[code].Name, 1, 30));
    if ( letter <> ' ' ) then InsertFloppy(code, letter);
  end;
end;

procedure SetDuoVolume(volume:integer);
var
  message:string;
begin
  if not Duo.Present then exit;
  if ( volume < 0 ) then volume := 0;
  if ( volume > 100 ) then volume := 100;
  if Command('FDC,1,VOL,' + IntToStr(volume), message) then begin
    ApplyReply(MakeSentence('FDV,1,volume,' + IntToStr(volume)));  { As the Duo now has it }
    Done(true, 'Duo volume ' + IntToStr(volume));
  end
  else Done(false, message);
end;

procedure EjectFloppy;
var
  code,k:integer;
  letter:char;
  letters,disk,message:string;
begin
  if not Duo.Present then exit;
  letter := ' ';
  code := FdSelected;
  if ( code >= 0 ) then letter := DriveOfImage(code);
  if ( letter = ' ' ) then begin
    letters := DuoLetters;
    choiceCount := 0;
    for k := 1 to length(letters) do
      if ( length(DuoDisk(letters[k])) > 0 ) then AddChoice(letters[k] + ':', DuoDiskText(DuoDisk(letters[k])));
    if ( choiceCount = 0 ) then begin
      Done(true, 'No disk to take out');
      exit;
    end;
    if ( choiceCount = 1 ) then k := 1 else k := Choose('Eject which drive?', 1);
    if ( k = 0 ) then exit;
    letter := choiceValue[k][1];
  end;
  disk := DuoDisk(letter);
  { The Duo's mailbox still answers with the drive empty (at cylinder 82 only) }
  if not Confirm('Eject', 'Take ' + DuoDiskText(disk) + ' out of ' + letter + ':?', '', 'Eject') then exit;
  if ( DuoBackend = dbFloppy ) then FlushDos;
  if not Command('FDC,1,EJECT,' + letter, message) then begin
    Done(false, message);
    exit;
  end;
  if AwaitSwap(letter, '') then Done(true, letter + ': is empty')
  else Done(true, 'Taking ' + DuoDiskText(disk) + ' out of ' + letter + ':');
end;

{ Enter on one of the Duo's settings }
procedure ChangeDuoSetting;
var
  key,caption,current,now,value,message:string;
  i,pick,start:integer;
begin
  if not RowSetting(setSel, current, now) then exit;
  key := copy(SettingRows[setSel].Key, 4, 20);
  caption := SettingRows[setSel].Caption;
  for i := 1 to length(current) do if ( current[i] = '_' ) then current[i] := ',';
  choiceCount := 0;
  if ( key = 'drive' ) then begin
    AddChoice('a', 'drive A: only');
    AddChoice('a,b', 'drives A: and B:, a disk in each');
    AddChoice('b', 'drive B: only');
  end
  else begin
    AddChoice('-', 'the last disk in, as when it stopped');
    for i := 0 to Duo.FileCount - 1 do
      if ( Duo.Files[i].Kind = DuoFlux ) then AddChoice(Duo.Files[i].Name, 'a flux image')
      else AddChoice(Duo.Files[i].Name, FloppySize(Duo.Files[i].SizeKB));
  end;
  start := 1;
  for i := 1 to choiceCount do
    if ( choiceValue[i] = current ) then start := i;
  pick := Choose(caption, start);
  if ( pick = 0 ) then exit;
  value := choiceValue[pick];
  if ( value = current ) then begin
    Done(true, caption + ' is already ' + SettingText('fd:' + key, value));
    exit;
  end;
  if Command('FDC,1,SET,' + key + ',' + value, message) then begin
    Request('FDQ,1,SETTINGS');
    Done(true, caption + ': ' + SettingText('fd:' + key, value) + ' at next start');
  end
  else Done(false, message);
end;

{ What turning an on/off setting to `value` trades, for its question }
function SettingWarning(key, value:string):string;
begin
  SettingWarning := '';
  if ( key = 'write_behind' ) and ( value = 'on' ) then SettingWarning := 'A power cut mid-write can lose that sector.'
  else if ( key = 'write_behind' ) then SettingWarning := 'Writes get about a third slower.'
  else if ( key = 'read_ahead' ) and ( value = 'off' ) then SettingWarning := 'Reads get slower.'
  else if ( key = 'activity_link' ) and ( value = 'off' ) then
    SettingWarning := 'The HDD Synth goes back to its activity LED.';
end;

{ Enter on the Settings tab: choose a value for the highlighted setting
  and save it, from the next power-on }
procedure ChangeSetting;
var
  key,caption,current,value,message,turn:string;
  i,pick,start:integer;
begin
  if ( setSel >= 1 ) and ( setSel <= SettingRowCount ) and IsDuoRow(setSel) then begin
    ChangeDuoSetting;
    exit;
  end;
  if ( setSel >= 1 ) and ( setSel <= SettingRowCount ) and IsShownOnlyRow(setSel) then begin
    Done(true, SettingRows[setSel].Caption + ' is shown only: HDDSYNTH.INI sets it');
    exit;
  end;
  if ( Bay.SettingCount = 0 ) or ( setSel < 1 ) or ( setSel > SettingRowCount ) then exit;
  key := SettingRows[setSel].Key;
  caption := SettingRows[setSel].Caption;
  i := SettingIndex(key);
  if ( i = 0 ) then exit;
  current := Bay.Settings[i].Next;
  value := '';
  choiceCount := 0;

  if ( key = 'seek_timing' ) then begin
    for i := 1 to SeekCount do AddChoice(SeekValues[i], SeekWords[i]);
  end
  else if ( key = 'device1' ) then begin
    AddChoice('none', 'no second drive');
    AddChoice('cdrom', 'a CD-ROM drive');
    for i := 0 to Bay.FileCount - 1 do
      if ( Bay.Files[i].Kind = KindHardDisk ) then AddChoice(Bay.Files[i].Name, 'a hard disk image')
      else AddChoice(Bay.Files[i].Name, 'a CD-ROM drive with this disc');
  end
  else if ( key = 'cdrom' ) then begin
    for i := 0 to Bay.FileCount - 1 do
      if ( Bay.Files[i].Kind = KindCdRom ) then AddChoice(Bay.Files[i].Name, SizeText(Bay.Files[i].SizeKB));
  end;

  if ( choiceCount > 0 ) then begin
    start := 1;
    for i := 1 to choiceCount do
      if ( choiceValue[i] = current ) then start := i;
    pick := Choose(caption, start);
    if ( pick = 0 ) then exit;
    value := choiceValue[pick];
  end
  else begin
    { On or off: a question, with what it trades }
    if ( current = 'on' ) then value := 'off' else value := 'on';
    if ( key = 'sd_high_speed' ) then begin
      if ( value = 'on' ) then turn := 'Read the card at high speed' else turn := 'Read the card at normal speed';
    end
    else if ( value = 'on' ) then turn := 'Turn ' + caption + ' on'
    else turn := 'Turn ' + caption + ' off';
    if not Confirm(caption, turn + ' from the next power-on?', SettingWarning(key, value), 'Change') then exit;
  end;

  if ( value = current ) then begin
    Done(true, caption + ' is already ' + SettingText(key, value));
    exit;
  end;
  if Command('SBC,1,SET,' + key + ',' + value, message) then begin
    Request('SBQ,1,SETTINGS');
    Done(true, caption + ': ' + SettingText(key, value) + ' at next boot');  { Short: the frame's edge }
  end
  else Done(false, message);
end;

procedure RefreshNow;
begin
  if ( DuoBackend = dbNone ) then DuoLooked := false;  { Look again: a disk may be in now }
  LookForDuo;
  RefreshAll;
  if ( length(LinkProblem) > 0 ) then Done(false, LinkProblem) else Done(true, 'Up to date');
end;

{ ////////////////// Keys ////////////////// }

procedure MoveList(step:integer);
begin
  if ( tab = MenuSettings ) then begin
    while ( step < 0 ) do begin MoveSetSel(-1); inc(step); end;
    while ( step > 0 ) do begin MoveSetSel(1); dec(step); end;
  end
  else if ( tab = MenuFloppy ) then begin
    while ( step < 0 ) do begin MoveFdSel(-1); inc(step); end;
    while ( step > 0 ) do begin MoveFdSel(1); dec(step); end;
  end
  else if ( tab = MenuSynth ) then begin
    packSel := packSel + step;
    if ( packSel < 0 ) then packSel := 0;
    if ( packSel >= Synth.PacksKnown ) then packSel := Synth.PacksKnown - 1;
  end
  else if ( step < -1 ) or ( step > 1 ) then begin
    while ( step < 0 ) do begin MoveBaySel(-1); inc(step); end;
    while ( step > 0 ) do begin MoveBaySel(1); dec(step); end;
  end
  else MoveBaySel(step);
end;

procedure MoveMenu(step:integer);
begin
  menuIndex := ( menuIndex + step + MenuCount ) mod MenuCount;
  if ( menuIndex in [MenuSynth, MenuBay, MenuFloppy, MenuSettings] ) then tab := menuIndex;
end;

procedure HandleKey;
var
  key:char;
begin
  key := ReadKey;
  note := '';
  case key of
    #0: begin
      key := ReadKey;
      case key of
        #59: Help;                       { F1 }
        #72: MoveList(-1);               { Up }
        #80: MoveList(1);                { Down }
        #73: MoveList(-10);              { Page Up }
        #81: MoveList(10);               { Page Down }
        #71: MoveList(-MaxFiles - MaxPacks); { Home }
        #79: MoveList(MaxFiles + MaxPacks);  { End }
        #75: MoveMenu(-1);               { Left }
        #77: MoveMenu(1);                { Right }
      end;
    end;
    #9: begin { Tab: Synth, Bay, Floppy, Settings in turn }
      if ( tab = MenuSynth ) then tab := MenuBay
      else if ( tab = MenuBay ) then tab := MenuFloppy
      else if ( tab = MenuFloppy ) then tab := MenuSettings
      else tab := MenuSynth;
      menuIndex := tab;
    end;
    #13: case menuIndex of
      MenuSynth: PlayPack;
      MenuBay: InsertOrBoot;
      MenuFloppy: FloppyEnter;
      MenuSettings: ChangeSetting;
      MenuRefresh: RefreshNow;
      MenuExit: quit := true;
    end;
    #27: quit := true;
    '+', '=': if ( tab = MenuFloppy ) then SetDuoVolume(DuoVolume + 5) else SetVolume(Synth.Volume + 5);
    '-', '_': if ( tab = MenuFloppy ) then SetDuoVolume(DuoVolume - 5) else SetVolume(Synth.Volume - 5);
    '<', ',': SetBalance(Synth.Balance - 5);
    '>', '.': SetBalance(Synth.Balance + 5);
    'r', 'R': RefreshNow;
    'e', 'E': if ( tab = MenuFloppy ) then EjectFloppy else Eject;
    'a', 'A': if ( tab = MenuFloppy ) then FloppyInto('A');
    'b', 'B': if ( tab = MenuFloppy ) then FloppyInto('B');
  end;
end;

{ The Floppy tab the first time: look for the Duo (a second or two) }
procedure LookOnFirstVisit;
begin
  if ( tab <> MenuFloppy ) or DuoLooked or ( DuoBackend <> dbNone ) then exit;
  Done(true, 'Looking for the FDD Synth Duo on the floppy drives...');
  DrawAll;
  if LookForDuo then begin
    RefreshDuo;
    Done(true, 'Found the Duo on ' + DriveLetter(DuoDrive) + ':');
  end
  else Done(false, 'No FDD Synth Duo on the floppy drives');
end;

{ ////////////////// Without the screen ////////////////// }

procedure PrintStatus;
var
  i:integer;
begin
  writeln(ApplicationName);
  if ( Backend = bkDemo ) then writeln('Demo: a pretend Bay and synth')
  else if ( Backend = bkNone ) then writeln('No IDE Synth Bay found')
  else writeln('Bay on the ', DriveName(BayDrive), ': ', BayDrive.Model, ' ', BayDrive.Firmware);
  writeln;
  writeln('IDE Synth Bay');
  for i := 1 to Bay.ValueCount do
    writeln('  ', PadRight(Bay.Values[i].Key, 14), Bay.Values[i].Value);
  for i := 0 to Bay.FileCount - 1 do
    writeln('  file          ', PadRight(Bay.Files[i].Name, 13),
            PadRight(SizeText(Bay.Files[i].SizeKB), 8), Bay.Files[i].Kind);
  writeln;
  writeln('HDD Synth');
  if not Synth.Present then
    writeln('  not answering')
  else begin
    writeln('  firmware      ', Synth.Firmware);
    writeln('  state         ', Synth.State);
    writeln('  pack          ', Synth.PackIndex, ' ', PackName(Synth.PackIndex));
    writeln('  volume        ', Synth.Volume);
    writeln('  balance       ', Synth.Balance);
    writeln('  supercap      ', SupercapText);
    for i := 0 to Synth.PacksKnown - 1 do
      writeln('  pack ', i:2, '       ', PadRight(PackName(i), 33), Synth.Packs[i].Kind);
  end;
  writeln;
  writeln('FDD Synth Duo');
  if not Duo.Present then
    writeln('  not found on the floppy drives')
  else begin
    if ( DuoBackend = dbFloppy ) then
      writeln('  found on      ', DriveLetter(DuoDrive), ': (cylinder 82, ', SecondsText(ExchangeMs), ' an exchange)');
    for i := 1 to Duo.ValueCount do
      writeln('  ', PadRight(Duo.Values[i].Key, 14), Duo.Values[i].Value);
    for i := 0 to Duo.FileCount - 1 do
      writeln('  image         ', PadRight(Duo.Files[i].Name, 25), PadRight(FloppySize(Duo.Files[i].SizeKB), 9),
              Duo.Files[i].Kind);
    for i := 0 to Duo.PackCount - 1 do
      writeln('  pack ', i:2, '       ', Duo.Packs[i]);
    for i := 1 to Duo.SettingCount do
      writeln('  setting       ', PadRight(Duo.Settings[i].Key, 10), PadRight(Duo.Settings[i].Next, 26),
              Duo.Settings[i].Now);
  end;
end;

procedure Usage;
begin
  writeln(ApplicationName, ': the HDD Synth, IDE Synth Bay and FDD Synth Duo from DOS');
  writeln;
  writeln('  SYNMIND           find the Bay and open SynthMinder');
  writeln('  SYNMIND /DEMO     try it with a pretend Bay and synth');
  writeln('  SYNMIND /STATUS   print what the Bay and synth say, and exit');
  writeln('  SYNMIND /V        print the version');
  writeln;
  writeln('For batch files, in the order given:');
  writeln('  /DISC=QUAKE.ISO   put a CD image in the Bay''s CD-ROM drive (/DISC=- takes it out)');
  writeln('  /PACK=3           play a sample pack, by number, folder or name');
  writeln('  /VOL=60 /BAL=50   the synth''s volume and balance, 0-100');
  writeln('  /FDA=GAMES.IMG    a disk image into the FDD Synth Duo''s A: (/FDB= into its B:)');
  writeln('  /FDEJECT=A        take the disk out of the Duo''s A: (or B)');
  writeln('  /FDPACK=2         the Duo''s sample pack, by number or name');
  writeln('  /FDVOL=60         the Duo''s volume, 0-100');
  writeln('  /Q                no messages, just the ERRORLEVEL:');
  writeln('                    0 done, 1 a bad option, 2 no Bay, 3 refused, 4 no synth, 5 no Duo');
end;

{ ////////////////// Batch files ////////////////// }

var
  actions:array[1..MaxActions] of TAction;
  actionCount:integer;
  quiet:boolean;

procedure Say(text:string);
begin
  if not quiet then writeln('SynthMinder: ', text);
end;

{ How a refused command ends: no synth (4), or refused (3) }
function RefusedCode:integer;
begin
  if ( LastAck.Reason = 'nosynth' ) then RefusedCode := ExitNoSynth else RefusedCode := ExitRefused;
end;

{ Run one /FDA, /FDB, /FDEJECT, /FDPACK or /FDVOL: its ERRORLEVEL }
function RunDuoAction(var a:TAction):integer;
var
  message,name:string;
  letter:char;
  i:integer;
begin
  RunDuoAction := ExitDone;
  if not Duo.Present then begin
    Say(ActionName(a.Kind) + ': no FDD Synth Duo found on the floppy drives');
    RunDuoAction := ExitNoDuo;
    exit;
  end;
  case a.Kind of
    akFdA, akFdB: begin
      if ( a.Kind = akFdA ) then letter := 'A' else letter := 'B';
      i := FindDuoFile(a.Text);
      if ( i < 0 ) then begin
        Say(ActionName(a.Kind) + '=' + a.Text + ': not on the Duo''s card');
        RunDuoAction := ExitRefused;
        exit;
      end;
      name := Duo.Files[i].Name;
      if ( UpperText(DuoDisk(letter)) = UpperText(name) ) then begin
        Say(name + ' is in ' + letter + ': already');
        exit;
      end;
      if ( DuoBackend = dbFloppy ) then FlushDos;
      if not Command('FDC,1,INSERT,' + letter + ',' + name, message) then begin
        Say(ActionName(a.Kind) + '=' + a.Text + ': ' + message);
        RunDuoAction := ExitRefused;
      end
      { A batch file may use the drive next: it waits for the disk to be in }
      else if AwaitSwap(letter, name) then Say('put ' + name + ' in ' + letter + ':')
      else Say(name + ' is going into ' + letter + ':');
    end;
    akFdEject: begin
      letter := a.Text[1];
      if ( DuoBackend = dbFloppy ) then FlushDos;
      if Command('FDC,1,EJECT,' + letter, message) then Say(letter + ': is empty')
      else begin
        Say('/FDEJECT=' + a.Text + ': ' + message);
        RunDuoAction := ExitRefused;
      end;
    end;
    akFdPack: begin
      i := FindDuoPack(a.Text);
      if ( i < 0 ) then begin
        Say('/FDPACK=' + a.Text + ': the Duo has no such sample pack');
        RunDuoAction := ExitRefused;
      end
      else if Command('FDC,1,PACK,' + IntToStr(i), message) then Say('the Duo plays ' + Duo.Packs[i])
      else begin
        Say('/FDPACK=' + a.Text + ': ' + message);
        RunDuoAction := ExitRefused;
      end;
    end;
    akFdVolume: begin
      if Command('FDC,1,VOL,' + IntToStr(a.Number), message) then Say('Duo volume ' + IntToStr(a.Number))
      else begin
        Say('/FDVOL: ' + message);
        RunDuoAction := ExitRefused;
      end;
    end;
  end;
end;

{ Run one /DISC, /PACK, /VOL or /BAL: its ERRORLEVEL }
function RunAction(var a:TAction):integer;
var
  message:string;
  i:integer;
begin
  RunAction := ExitDone;
  if ( a.Kind in [akFdA, akFdB, akFdEject, akFdPack, akFdVolume] ) then begin
    RunAction := RunDuoAction(a);
    exit;
  end;
  if ( Backend = bkNone ) then begin
    Say(ActionName(a.Kind) + ': no IDE Synth Bay found');
    RunAction := ExitNoBay;
    exit;
  end;
  if ( a.Kind <> akDisc ) and not Synth.Present then begin
    Say(ActionName(a.Kind) + ': no HDD Synth is answering on the Synth Link');
    RunAction := ExitNoSynth;
    exit;
  end;
  case a.Kind of
    akDisc: begin
      if ( BayValue('device1') <> 'cdrom' ) then begin
        Say('/DISC: the Bay has no CD-ROM drive set up');
        RunAction := ExitRefused;
      end
      else if Command('SBC,1,DISC,' + a.Text, message) then begin
        if ( a.Text = '-' ) then Say('the CD-ROM drive is empty') else Say(a.Text + ' is in the CD-ROM drive');
      end
      else begin
        Say('/DISC=' + a.Text + ': ' + message);
        RunAction := RefusedCode;
      end;
    end;
    akPack: begin
      i := FindPack(a.Text);
      if ( i < 0 ) then begin
        Say('/PACK=' + a.Text + ': the synth has no such sample pack');
        RunAction := ExitRefused;
      end
      else if Command('HDC,1,PACK,' + IntToStr(i), message) then Say('playing ' + PackName(i))
      else begin
        Say('/PACK=' + a.Text + ': ' + message);
        RunAction := RefusedCode;
      end;
    end;
    akVolume, akBalance: begin
      if ( a.Kind = akVolume ) then message := 'VOL' else message := 'BAL';
      if Command('HDC,1,' + message + ',' + IntToStr(a.Number), message) then begin
        if ( a.Kind = akVolume ) then Say('volume ' + IntToStr(a.Number))
        else Say('balance ' + IntToStr(a.Number));
      end
      else begin
        Say(ActionName(a.Kind) + ': ' + message);
        RunAction := RefusedCode;
      end;
    end;
  end;
end;

{ Every action in turn; the first that fails ends it, with its ERRORLEVEL }
procedure RunActions;
var
  i,code:integer;
begin
  for i := 1 to actionCount do begin
    code := RunAction(actions[i]);
    if ( code <> ExitDone ) then halt(code);
  end;
  halt(ExitDone);
end;

{ A floppy option was given: the Duo is wanted at start }
function NeedsDuo:boolean;
var
  i:integer;
begin
  NeedsDuo := false;
  for i := 1 to actionCount do
    if ( actions[i].Kind in [akFdA, akFdB, akFdEject, akFdPack, akFdVolume] ) then NeedsDuo := true;
end;

{ ////////////////// Start ////////////////// }

{ For tests: save the text screen (character and colour for each cell,
  4,000 bytes) to SCREEN.BIN. scripts/screen.py shows it }
procedure SaveScreen;
var
  f:file;
begin
  Assign(f, 'SCREEN.BIN');
  Rewrite(f, 1);
  BlockWrite(f, Mem[$B800:0], 4000);
  Close(f);
end;

{ /DUMP=SYNTH, BAY, FLOPPY or SETTINGS: draw that tab, save it and exit }
procedure DumpScreen(which:string);
begin
  if ( which = 'BAY' ) then menuIndex := MenuBay
  else if ( which = 'FLOPPY' ) then menuIndex := MenuFloppy
  else if ( which = 'SETTINGS' ) then menuIndex := MenuSettings
  else menuIndex := MenuSynth;
  tab := menuIndex;
  StartScreen;
  ClrScr;
  DrawAll;
  SaveScreen;
  EndScreen;
end;

var
  i,j:integer;
  arg,problem:string;
  demoMode,statusOnly:boolean;
  dumpTab:string[10];
  action:TAction;
begin
  UseDosOutput;
  demoMode := false;
  statusOnly := false;
  dumpTab := '';
  actionCount := 0;
  quiet := false;
  for i := 1 to ParamCount do begin
    arg := ParamStr(i);
    for j := 1 to length(arg) do arg[j] := UpCase(arg[j]);
    if ( arg[1] = '-' ) then arg[1] := '/';
    if ParseAction(arg, action, problem) then begin
      if ( length(problem) > 0 ) then begin
        writeln('SynthMinder: ', problem);
        halt(ExitBadOption);
      end;
      if ( actionCount >= MaxActions ) then begin
        writeln('SynthMinder: at most ', MaxActions, ' changes at once');
        halt(ExitBadOption);
      end;
      inc(actionCount);
      actions[actionCount] := action;
    end
    else if ( arg = '/Q' ) then quiet := true
    else if ( arg = '/DEMO' ) then demoMode := true
    else if ( arg = '/STATUS' ) then statusOnly := true
    else if ( copy(arg, 1, 6) = '/DUMP=' ) then dumpTab := copy(arg, 7, 10)
    else if ( arg = '/V' ) then begin
      writeln(ApplicationName);
      halt(0);
    end
    else begin
      Usage;
      if ( arg = '/?' ) or ( arg = '/H' ) then halt(ExitDone) else halt(ExitBadOption);
    end;
  end;

  if demoMode then begin
    Backend := bkDemo;
    DuoBackend := dbDemo;
  end
  else begin
    if FindBay then Backend := bkIde else Backend := bkNone;
    { The floppy drives take a second or two to look at: only when there's
      no Bay, or the Duo is wanted now. The Floppy tab looks otherwise }
    if ( Backend = bkNone ) or statusOnly or NeedsDuo then LookForDuo;
    if ( Backend = bkNone ) and ( DuoBackend = dbNone ) then begin
      if not quiet then begin
        writeln('SynthMinder: no IDE Synth Bay found on the primary or secondary IDE channel,');
        writeln('and no FDD Synth Duo on the floppy drives.');
        writeln('To try SynthMinder without them: SYNMIND /DEMO');
      end;
      if NeedsDuo then halt(ExitNoDuo) else halt(ExitNoBay);
    end;
  end;

  RefreshAll;
  if ( Backend = bkIde ) and not Bay.Present and ( DuoBackend = dbNone ) then begin
    if not quiet then begin
      writeln('SynthMinder found the IDE Synth Bay (', BayDrive.Model, ', firmware ', BayDrive.Firmware, ')');
      writeln('on the ', DriveName(BayDrive), ', but couldn''t talk to it:');
      writeln(LinkProblem, '.');
    end;
    halt(ExitNoBay);
  end;

  if ( actionCount > 0 ) then RunActions;

  if statusOnly then begin
    PrintStatus;
    halt(0);
  end;

  if ( Backend = bkNone ) then menuIndex := MenuFloppy else menuIndex := MenuSynth;
  tab := menuIndex;
  fdSel := 0;
  fdTop := 0;
  packSel := Synth.PackIndex;
  if ( packSel < 0 ) then packSel := 0;
  packTop := 0;
  baySel := 0;
  bayTop := 0;
  setSel := 0;
  note := '';
  quit := false;

  if ( length(dumpTab) > 0 ) and ( dumpTab <> 'EXIT' ) then begin
    DumpScreen(dumpTab);
    halt(0);
  end;

  StartScreen;
  ClrScr;
  repeat
    DrawAll;
    HandleKey;
    LookOnFirstVisit;
  until quit;
  { /DUMP=EXIT: the screen as it was when Esc was pressed, for scripted tests }
  if ( dumpTab = 'EXIT' ) then begin
    DrawAll;
    SaveScreen;
  end;
  EndScreen;
end.
