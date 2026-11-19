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

  { The tabs, one for each thing that changes, the drives in DOS's order (A:, C:, D:) }
  MenuSound = 0;
  MenuFloppy = 1;
  MenuHardDisk = 2;
  MenuCdRom = 3;
  MenuSettings = 4;
  MenuExit = 5;
  MenuCount = 6;
  MenuCaptions: array[0..MenuCount - 1] of string[9] = ('Sound', 'Floppy', 'Hard disk', 'CD-ROM', 'Settings', 'Exit');
  MenuHints: array[0..MenuCount - 1] of string[78] = (
    'The synths'' sound: the HDD Synth''s and the Duo''s sample packs and volume',
    'The FDD Synth Duo''s drives: change a disk now, as if by hand',
    'The Bay''s hard disk: choose the image the PC starts from at its next reset',
    'The Bay''s CD-ROM drive: change its disc now, as if by hand',
    'Each device''s settings and details: changes take effect from the next power-on',
    'Exit to DOS');
  { /DUMP= names for the tabs }
  TabNames: array[0..MenuExit - 1] of string[8] = ('SOUND', 'FLOPPY', 'HARDDISK', 'CDROM', 'SETTINGS');

  { The Settings tab's rows: a heading (no key; a sub-heading starts with a
    space), or a setting the Bay lists with $SBQ,1,SETTINGS, or (fd:) the
    Duo with $FDQ,1,SETTINGS. Grouped by device: the HDD Synth's (which the
    Bay keeps), the Bay's, the Duo's. The Bay's show when it lists
    settings, the Duo's when it does }
  SettingRowCount = 18;
  SynthLastRow = 3;    { The HDD Synth's rows: 1 to here }
  ShownFirstRow = 10;  { The bus's: shown only, as the Bay gives them (0.36.0-dev.2) }
  DuoFirstRow = 15;
  SettingRows: array[1..SettingRowCount] of record
    Key: string[13];
    Caption: string[20];
  end = (
    (Key:''; Caption:'HDD Synth'),
    (Key:'seek_timing'; Caption:'Seek timing'),
    (Key:'activity_link'; Caption:'Synth Link'),
    (Key:''; Caption:'IDE Synth Bay'),
    (Key:'device1'; Caption:'Device 1'),
    (Key:'cdrom'; Caption:'CD at power-on'),
    (Key:'write_behind'; Caption:'Write-behind'),
    (Key:'read_ahead'; Caption:'Read-ahead'),
    (Key:'sd_high_speed'; Caption:'SD card speed'),
    (Key:''; Caption:' The bus, shown only'),
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

  { A list's rows are codes: an item (0 and up, a pack's or an image's
    index), the second kind of item (RowSecond - index: the Duo's packs on
    the Sound tab), or a heading or note (-1 to -9), which the highlight
    passes over }
  MaxListRows = MaxDuoFiles + 4;  { The longest: the Duo's images and their headings }
  RowSecond = -10;
  RowNone = -9;        { No item highlighted }

  { The Sound tab's headings and notes }
  RowSynthHeading = -1;
  RowDuoHeading = -2;
  RowGap = -3;
  RowNoSynth = -4;
  RowNoDuo = -5;

  { The Floppy tab's headings }
  Row35 = -1;
  Row525 = -2;
  RowOther = -3;

  { The Hard disk and CD-ROM tabs' headings }
  RowHardDisks = -1;
  RowCdRoms = -2;

type
  TList = record
    Rows: array[0..MaxListRows - 1] of integer;
    Count: integer;
    Sel: integer;      { The highlighted row }
    Top: integer;      { The first row shown }
  end;
  PList = ^TList;
  TRowStyle = (rsHeading, rsNote, rsItem, rsInUse);

var
  menuIndex:integer;
  tab:integer;              { MenuSound to MenuSettings: what the panels show }
  setSel:integer;           { The Settings tab's row, 1..SettingRowCount, never a heading }
  choiceValue:array[1..MaxChoices] of string[47];  { The chooser's choices }
  choiceWords:array[1..MaxChoices] of string[40];
  choiceCount:integer;
  soundList,fdList,hdList,cdList:TList;
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

{ A field whose value stands out, e.g. the hard disk waiting for the reset }
procedure RightValue(var y:byte; name, value:string; fore:byte);
begin
  if ( y >= FrameBottom ) then exit;
  RightLine(y, PadRight(name, 12) + value, ColorText, ColorBackground);
  WriteAt(RightX + 13, y, value, fore, ColorBackground);
  inc(y);
end;

procedure RightNote(var y:byte; text:string);
begin
  if ( y >= FrameBottom ) then exit;
  RightLine(y, text, ColorNote, ColorBackground);
  inc(y);
end;

{ The left panel with nothing to list: a heading and why }
procedure LeftMessage(heading, line1, line2:string);
begin
  LeftLine(PanelTop, heading, ColorHeadingText, ColorHeadingBack);
  LeftLine(PanelTop + 1, '', ColorText, ColorBackground);
  LeftLine(PanelTop + 2, line1, ColorDim, ColorBackground);
  LeftLine(PanelTop + 3, line2, ColorDim, ColorBackground);
  ClearLeft(PanelTop + 4, FrameBottom - 1);
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
  if ( length(BayValue('device0_next')) > 0 ) then RightField(y, 'Next reset', BayValue('device0_next'));
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

{ ////////////////// Lists ////////////////// }

{ The rows a list shows: the panel's height }
function ListRows:integer;
begin
  ListRows := FrameBottom - PanelTop;
end;

function Selectable(code:integer):boolean;
begin
  Selectable := ( code >= 0 ) or ( code <= RowSecond );
end;

procedure ListAdd(var list:TList; code:integer);
begin
  if ( list.Count >= MaxListRows ) then exit;
  list.Rows[list.Count] := code;
  inc(list.Count);
end;

{ Move the highlight by `step` items, passing over headings and notes }
procedure ListMove(var list:TList; step:integer);
var
  next,dir:integer;
begin
  if ( step < 0 ) then dir := -1 else dir := 1;
  while ( step <> 0 ) do begin
    next := list.Sel;
    repeat
      next := next + dir;
      if ( next < 0 ) or ( next >= list.Count ) then exit;
    until Selectable(list.Rows[next]);
    list.Sel := next;
    step := step - dir;
  end;
end;

{ The highlight on an item, and the first row shown keeping it in view }
procedure ListKeepVisible(var list:TList);
begin
  if ( list.Sel >= list.Count ) then list.Sel := list.Count - 1;
  if ( list.Sel < 0 ) then list.Sel := 0;
  if ( list.Count > 0 ) and not Selectable(list.Rows[list.Sel]) then ListMove(list, 1);
  if ( list.Sel < list.Top ) then list.Top := list.Sel;
  { Show a heading above the first item under it }
  if ( list.Top > 0 ) and ( list.Sel = list.Top ) and not Selectable(list.Rows[list.Top - 1]) then dec(list.Top);
  if ( list.Sel >= list.Top + ListRows ) then list.Top := list.Sel - ListRows + 1;
  if ( list.Top < 0 ) then list.Top := 0;
end;

{ The highlighted item's code, or RowNone }
function ListSelected(var list:TList):integer;
begin
  ListSelected := RowNone;
  if ( list.Sel >= 0 ) and ( list.Sel < list.Count ) then
    if Selectable(list.Rows[list.Sel]) then ListSelected := list.Rows[list.Sel];
end;

{ Highlight the item `code`, if the list has it }
procedure ListFind(var list:TList; code:integer);
var
  row:integer;
begin
  if not Selectable(code) then exit;
  for row := 0 to list.Count - 1 do
    if ( list.Rows[row] = code ) then list.Sel := row;
end;

{ ////////////////// Words for the Duo ////////////////// }

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

{ ////////////////// The lists' rows ////////////////// }

{ The mark before an item: the one in use now (playing, in the drive) }
function UseMark(inUse:boolean):string;
begin
  if inUse then UseMark := ChInUse + ' ' else UseMark := '  ';
end;

{ The Sound tab: the HDD Synth's packs, then the Duo's }
procedure BuildSoundRows;
var
  i:integer;
begin
  soundList.Count := 0;
  ListAdd(soundList, RowSynthHeading);
  if Synth.Present then
    for i := 0 to Synth.PacksKnown - 1 do ListAdd(soundList, i)
  else ListAdd(soundList, RowNoSynth);
  ListAdd(soundList, RowGap);
  ListAdd(soundList, RowDuoHeading);
  if Duo.Present then
    for i := 0 to Duo.PackCount - 1 do ListAdd(soundList, RowSecond - i)
  else ListAdd(soundList, RowNoDuo);
end;

procedure SoundRow(code:integer; var text, right:string; var style:TRowStyle);
var
  i:integer;
begin
  case code of
    RowSynthHeading: begin
      text := 'HDD Synth packs';
      if Synth.Present then right := IntToStr(Synth.PacksKnown);
      style := rsHeading;
    end;
    RowDuoHeading: begin
      text := 'FDD Synth Duo packs';
      if Duo.Present then right := IntToStr(Duo.PackCount);
      style := rsHeading;
    end;
    RowGap: style := rsNote;
    RowNoSynth: begin
      if ( Backend = bkNone ) then text := '  No IDE Synth Bay found' else text := '  Not answering';
      style := rsNote;
    end;
    RowNoDuo: begin
      if DuoLooked then text := '  Not found' else text := '  Not looked for yet: R looks';
      style := rsNote;
    end;
  else
    if ( code >= 0 ) then begin
      if ( code = Synth.PackIndex ) then style := rsInUse;
      text := UseMark(style = rsInUse) + PackName(code);
      right := KindText(Synth.Packs[code].Kind);
    end
    else begin
      i := RowSecond - code;
      if ( i = DuoPackIndex ) then style := rsInUse;
      text := UseMark(style = rsInUse) + Duo.Packs[i];
    end;
  end;
end;

{ The Floppy tab: the Duo's images, under 3.5in, 5.25in and Other }
procedure BuildFloppyRows;
const
  Groups: array[1..3] of integer = (Row35, Row525, RowOther);
var
  g,i:integer;
  any:boolean;
begin
  fdList.Count := 0;
  for g := 1 to 3 do begin
    any := false;
    for i := 0 to Duo.FileCount - 1 do
      if ( DuoGroup(i) = Groups[g] ) then begin
        if not any then ListAdd(fdList, Groups[g]);
        any := true;
        ListAdd(fdList, i);
      end;
  end;
end;

{ An image's mark is the drive it's in: there may be two }
procedure FloppyRow(code:integer; var text, right:string; var style:TRowStyle);
var
  i,count:integer;
  letter:char;
begin
  if ( code < 0 ) then begin
    case code of
      Row35: text := '3.5in disks';
      Row525: text := '5.25in disks';
    else
      text := 'Other disks';
    end;
    count := 0;
    for i := 0 to Duo.FileCount - 1 do
      if ( DuoGroup(i) = code ) then inc(count);
    right := IntToStr(count);
    style := rsHeading;
    exit;
  end;
  letter := DriveOfImage(code);
  if ( letter <> ' ' ) then style := rsInUse;
  text := letter + ' ' + copy(Duo.Files[code].Name, 1, 26);
  if ( Duo.Files[code].Kind = DuoFlux ) then right := 'flux' else right := FloppySize(Duo.Files[code].SizeKB);
end;

{ The Hard disk and CD-ROM tabs: a heading, then the card's images of one kind }
procedure BuildImageRows(var list:TList; kind:char; heading:integer);
var
  i:integer;
begin
  list.Count := 0;
  ListAdd(list, heading);
  for i := 0 to Bay.FileCount - 1 do
    if ( Bay.Files[i].Kind = kind ) then ListAdd(list, i);
end;

{ The Bay's image `name`'s index, or -1 }
function BayFileIndex(name:string):integer;
var
  i:integer;
begin
  BayFileIndex := -1;
  if ( length(name) = 0 ) then exit;
  for i := 0 to Bay.FileCount - 1 do
    if ( Bay.Files[i].Name = name ) then BayFileIndex := i;
end;

{ The image is the hard disk now, or the disc in the CD-ROM drive }
function InDrive(i:integer):boolean;
begin
  if ( Bay.Files[i].Kind = KindCdRom ) then
    InDrive := ( BayValue('device1') = 'cdrom' ) and ( Bay.Files[i].Name = BayValue('disc') )
  else InDrive := Bay.Files[i].Name = BayValue('device0');
end;

procedure ImageRow(code:integer; var text, right:string; var style:TRowStyle);
var
  i,count:integer;
  kind:char;
begin
  if ( code < 0 ) then begin
    if ( code = RowHardDisks ) then begin
      text := 'Hard disk images';
      kind := KindHardDisk;
    end
    else begin
      text := 'CD-ROM images';
      kind := KindCdRom;
    end;
    count := 0;
    for i := 0 to Bay.FileCount - 1 do
      if ( Bay.Files[i].Kind = kind ) then inc(count);
    right := IntToStr(count);
    style := rsHeading;
    exit;
  end;
  if InDrive(code) then style := rsInUse;
  text := UseMark(style = rsInUse) + Bay.Files[code].Name;
  right := SizeText(Bay.Files[code].SizeKB);
end;

{ A row of the tab's list, in words }
procedure RowParts(code:integer; var text, right:string; var style:TRowStyle);
begin
  text := '';
  right := '';
  style := rsItem;
  case tab of
    MenuSound: SoundRow(code, text, right, style);
    MenuFloppy: FloppyRow(code, text, right, style);
  else
    ImageRow(code, text, right, style);
  end;
end;

{ The left panel: the tab's list, the highlight on one item }
procedure DrawList(var list:TList);
var
  y:byte;
  row:integer;
  text,right:string;
  style:TRowStyle;
begin
  ListKeepVisible(list);
  y := PanelTop;
  for row := list.Top to list.Top + ListRows - 1 do begin
    if ( row >= list.Count ) then
      LeftLine(y, '', ColorText, ColorBackground)
    else begin
      RowParts(list.Rows[row], text, right, style);
      if ( style = rsHeading ) then LeftRow(y, text, right, ColorHeadingText, ColorHeadingBack)
      else if ( style = rsNote ) then LeftRow(y, text, right, ColorDim, ColorBackground)
      else if ( row = list.Sel ) and ( tab = menuIndex ) then
        LeftRow(y, text, right, ColorHighlightText, ColorHighlightBack)
      else if ( style = rsInUse ) then LeftRow(y, text, right, ColorHighlightText, ColorBackground)
      else LeftRow(y, text, right, ColorText, ColorBackground);
    end;
    inc(y);
  end;
end;

{ The list the tab shows }
function CurrentList:PList;
begin
  case tab of
    MenuFloppy: CurrentList := @fdList;
    MenuHardDisk: CurrentList := @hdList;
    MenuCdRom: CurrentList := @cdList;
  else
    CurrentList := @soundList;
  end;
end;

{ ////////////////// Sound tab ////////////////// }

procedure NoSynthFields(var y:byte);
begin
  if ( Backend = bkNone ) then begin
    RightField(y, 'Not found', '');
    RightNote(y, 'It answers through the IDE Synth Bay.');
  end
  else begin
    RightField(y, 'Not answering', '');
    if ( LastAck.Reason = 'nosynth' ) then RightNote(y, 'Is the Synth Link connected?');
  end;
end;

{ The synth's details, for the Settings tab }
procedure SynthFields(var y:byte);
begin
  if not Synth.Present then begin
    NoSynthFields(y);
    exit;
  end;
  RightField(y, 'Firmware', Synth.Firmware);
  RightField(y, 'State', StateText(Synth.State));
  RightField(y, 'Supercap', SupercapText);
  if ( length(BayValue('link')) > 0 ) then RightField(y, 'Synth Link', BayValue('link'));
end;

{ Each synth's pack and volume, then the highlighted pack }
procedure DrawSoundRight;
var
  y:byte;
  code:integer;
begin
  y := PanelTop;
  RightHeading(y, 'HDD Synth');
  if Synth.Present then begin
    RightField(y, 'Playing', PackName(Synth.PackIndex));
    RightField(y, 'Volume', VolumeBar(Synth.Volume));
    RightField(y, 'Balance', BalanceBar(Synth.Balance));
    RightField(y, 'State', StateText(Synth.State));
  end
  else NoSynthFields(y);
  RightGap(y);
  RightHeading(y, 'FDD Synth Duo');
  if Duo.Present then begin
    RightField(y, 'Playing', DuoValue('pack'));
    RightField(y, 'Volume', VolumeBar(DuoVolume));
  end
  else if DuoLooked then RightNote(y, 'Not found: the Floppy tab says why')
  else begin
    RightNote(y, 'Not looked for yet: R looks on the');
    RightNote(y, 'floppy drives (a second or two)');
  end;

  code := ListSelected(soundList);
  if ( code >= 0 ) then begin
    RightGap(y);
    RightHeading(y, PackName(code));
    if ( length(KindText(Synth.Packs[code].Kind)) > 0 ) then RightField(y, 'Sound', KindText(Synth.Packs[code].Kind));
    RightGap(y);
    if ( code = Synth.PackIndex ) then RightNote(y, 'Playing now.')
    else begin
      RightNote(y, 'Enter plays it on the HDD Synth now:');
      RightNote(y, 'it spins up in about a second.');
    end;
  end
  else if ( code <= RowSecond ) then begin
    RightGap(y);
    RightHeading(y, Duo.Packs[RowSecond - code]);
    RightGap(y);
    if ( RowSecond - code = DuoPackIndex ) then RightNote(y, 'Playing now.')
    else RightNote(y, 'Enter plays it on the Duo now.');
    RightNote(y, '+ - set the Duo''s volume.');
  end;
  ClearRight(y);
end;

{ ////////////////// Floppy tab ////////////////// }

procedure DrawFloppyLeft;
begin
  if not Duo.Present then begin
    LeftMessage('Disks', 'Nothing to list: no Duo answered', '');
    exit;
  end;
  BuildFloppyRows;
  if ( fdList.Count = 0 ) then LeftMessage('Disks', 'No disk images on the Duo''s card', '')
  else DrawList(fdList);
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
  RightNote(y, 'The Duo needs a disk in to be found:');
  RightNote(y, 'put one in from its panel, then R.');
  RightNote(y, 'It answers from its firmware 0.25.0.');
end;

{ The Duo's details, for the Settings tab }
procedure DuoFields(var y:byte);
begin
  if not Duo.Present then begin
    NoDuoFields(y);
    exit;
  end;
  RightField(y, 'Firmware', DuoValue('firmware'));
  if TwoDuoDrives then RightField(y, 'Drives', 'A: and B:')
  else RightField(y, 'Drives', DuoLetters + ': (one drive)');
  RightField(y, 'Mailbox', DuoValue('mailbox') + ':, cylinder 82');
  if ( DuoBackend = dbFloppy ) and ( ExchangeMs > 0 ) then RightField(y, 'Exchange', SecondsText(ExchangeMs));
end;

procedure DuoDriveFields(var y:byte; letter:char; full:boolean);
var
  k,disk:string;
begin
  if ( y + 2 >= FrameBottom ) then exit;
  if ( y > PanelTop ) then RightGap(y);
  RightHeading(y, 'Drive ' + letter + ':');
  k := chr(ord(letter) + 32) + '_';
  disk := DuoDisk(letter);
  if ( length(disk) = 0 ) then begin
    RightField(y, 'Disk', 'none');
    exit;
  end;
  RightValue(y, 'Disk', DuoDiskText(disk), ColorHighlightText);
  RightField(y, 'Format', DuoValue(k + 'format'));
  if full then RightField(y, 'Head', 'cylinder ' + DuoValue(k + 'cylinder'));
  RightField(y, 'Motor', DuoValue(k + 'motor'));
  if full then begin
    if ( DuoValue(k + 'protect') = 'on' ) then RightField(y, 'Write', 'protected')
    else RightField(y, 'Write', 'allowed');
  end;
end;

{ Each drive and its disk, then the highlighted image }
procedure DrawFloppyRight;
var
  y:byte;
  code,k:integer;
  letters:string;
  letter:char;
begin
  y := PanelTop;
  if not Duo.Present then begin
    RightHeading(y, 'FDD Synth Duo');
    NoDuoFields(y);
    ClearRight(y);
    exit;
  end;
  letters := DuoLetters;
  for k := 1 to length(letters) do DuoDriveFields(y, letters[k], not TwoDuoDrives);
  code := ListSelected(fdList);
  if ( code >= 0 ) and ( y + 3 < FrameBottom ) then begin
    RightGap(y);
    RightHeading(y, copy(Duo.Files[code].Name, 1, RightWidth - 2));
    case Duo.Files[code].Kind of
      DuoFlux: RightField(y, 'Kind', 'a flux image (HFE)');
      DuoAmiga: RightField(y, 'Kind', 'an Amiga disk');
    else
      RightField(y, 'Size', FloppySize(Duo.Files[code].SizeKB));
    end;
    RightGap(y);
    letter := DriveOfImage(code);
    if ( letter <> ' ' ) then RightNote(y, 'In ' + letter + ': now.')
    else if TwoDuoDrives then begin
      RightNote(y, 'Enter, or A or B, puts it in a drive');
      RightNote(y, 'now: DOS sees the disk change.');
    end
    else begin
      RightNote(y, 'Enter puts it in ' + letters + ': now: DOS sees');
      RightNote(y, 'the disk change, as with a real drive.');
    end;
  end;
  ClearRight(y);
end;

{ ////////////////// Hard disk and CD-ROM tabs ////////////////// }

procedure DrawImageLeft(var list:TList; kind:char; heading:integer; caption:string);
begin
  BuildImageRows(list, kind, heading);
  if ( Backend = bkNone ) then LeftMessage(caption, 'No IDE Synth Bay found', '')
  else if ( list.Count <= 1 ) then LeftMessage(caption, 'None on the card, or the Bay didn''t', 'list them')
  else DrawList(list);
end;

{ The disk DOS runs from, the one waiting for the reset, then the highlighted image }
procedure DrawHardDiskRight;
var
  y:byte;
  i:integer;
  name,running,next:string;
begin
  y := PanelTop;
  running := BayValue('device0');
  next := BayValue('device0_next');
  RightHeading(y, 'The hard disk');
  if ( length(running) > 0 ) then RightField(y, 'Running', running);
  if ( length(next) > 0 ) then RightValue(y, 'Next reset', next, ColorHighlightText);
  i := ListSelected(hdList);
  if ( i >= 0 ) then begin
    name := Bay.Files[i].Name;
    RightGap(y);
    RightHeading(y, name);
    RightField(y, 'Size', SizeText(Bay.Files[i].SizeKB));
    RightGap(y);
    if ( name = next ) then begin
      RightNote(y, 'The PC starts from it at its next');
      RightNote(y, 'reset.');
    end
    else if ( name = running ) and ( length(next) = 0 ) then RightNote(y, 'DOS is running from it now.')
    else begin
      RightNote(y, 'Enter makes it the hard disk from the');
      RightNote(y, 'PC''s next reset: DOS can''t change');
      RightNote(y, 'disk while it''s running from one.');
    end;
  end;
  ClearRight(y);
end;

{ The disc in the drive, then the highlighted image }
procedure DrawCdRomRight;
var
  y:byte;
  i:integer;
  disc:string;
  hasDrive:boolean;
begin
  y := PanelTop;
  hasDrive := BayValue('device1') = 'cdrom';
  disc := BayValue('disc');
  if ( disc = '-' ) then disc := '';
  RightHeading(y, 'In the drive');
  if not hasDrive then begin
    RightField(y, 'Disc', 'no CD-ROM drive');
    RightGap(y);
    RightNote(y, 'The Bay''s second drive isn''t a CD-ROM');
    RightNote(y, 'drive: Device 1, on the Settings tab,');
    RightNote(y, 'changes it from the next power-on.');
  end
  else if ( length(disc) = 0 ) then RightField(y, 'Disc', 'none')
  else begin
    RightValue(y, 'Disc', disc, ColorHighlightText);
    i := BayFileIndex(disc);
    if ( i >= 0 ) then RightField(y, 'Size', SizeText(Bay.Files[i].SizeKB));
  end;
  i := ListSelected(cdList);
  if ( i >= 0 ) then begin
    RightGap(y);
    RightHeading(y, Bay.Files[i].Name);
    RightField(y, 'Size', SizeText(Bay.Files[i].SizeKB));
    RightGap(y);
    if InDrive(i) then RightNote(y, 'In the drive now.')
    else if hasDrive then begin
      RightNote(y, 'Enter puts it in the drive now:');
      RightNote(y, 'programs using the CD-ROM see the');
      RightNote(y, 'disc change.');
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
      if ( SettingRows[row].Caption[1] = ' ' ) then LeftLine(y, SettingRows[row].Caption, ColorNote, ColorBackground)
      else LeftLine(y, SettingRows[row].Caption, ColorHeadingText, ColorHeadingBack);
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
      if IsShownOnlyRow(row) then fore := ColorDim else fore := ColorText;
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
    Say('the CD-ROM tab.');
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

{ The highlighted setting, then the details of the device it belongs to:
  the HDD Synth, the Bay or the Duo. With no setting to highlight, the
  synth's and the Bay's }
procedure DrawSettingsRight;
var
  y:byte;
  key,next,now:string;
  selected:boolean;
begin
  y := PanelTop;
  selected := ( setSel >= 1 ) and ( setSel <= SettingRowCount ) and RowShown(setSel)
              and ( length(SettingRows[setSel].Key) > 0 );
  if selected then begin
    key := SettingRows[setSel].Key;
    RightHeading(y, SettingRows[setSel].Caption);
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
    else if IsDuoRow(setSel) then begin
      RightNote(y, 'Enter changes it. The Duo reads it as');
      RightNote(y, 'it starts, the next time the PC is on.');
    end
    else begin
      RightNote(y, 'Enter changes it, from the next');
      RightNote(y, 'power-on: the PC runs from the Bay.');
    end;
    RightGap(y);
  end;
  if selected and IsDuoRow(setSel) then begin
    RightHeading(y, 'FDD Synth Duo');
    DuoFields(y);
  end
  else if selected and ( setSel > SynthLastRow ) then begin
    RightHeading(y, 'IDE Synth Bay');
    BayFields(y);
  end
  else begin
    RightHeading(y, 'HDD Synth');
    SynthFields(y);
    if not selected then begin
      RightGap(y);
      RightHeading(y, 'IDE Synth Bay');
      BayFields(y);
    end;
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

{ The keys for the tab, and on Sound for the synth whose pack is highlighted }
procedure DrawFooterKeys;
begin
  case tab of
    MenuSound:
      if ( ListSelected(soundList) <= RowSecond ) then
        DrawFooter(' [F1] Help  [Enter] Play  [+/-] Duo volume  [Esc] Exit')
      else
        DrawFooter(' [F1] Help  [Enter] Play  [+/-] Volume  [</>] Balance  [Esc] Exit');
    MenuFloppy:
      if not Duo.Present then DrawFooter(' [F1] Help  [R] Look again  [Esc] Exit')
      else if TwoDuoDrives then DrawFooter(' [F1] Help  [Enter] Insert  [A]/[B] Into A:/B:  [E] Eject  [Esc] Exit')
      else DrawFooter(' [F1] Help  [Enter] Insert  [E] Eject  [Esc] Exit');
    MenuHardDisk: DrawFooter(' [F1] Help  [Enter] Use from the next reset  [Esc] Exit');
    MenuCdRom: DrawFooter(' [F1] Help  [Enter] Insert  [E] Eject  [Esc] Exit');
  else
    DrawFooter(' [F1] Help  [Enter] Change  [Esc] Exit');
  end;
end;

procedure DrawAll;
var
  where:string;
begin
  TextBackground(ColorBackground);
  DrawMenu;
  DrawFrame;
  case tab of
    MenuSound: begin
      BuildSoundRows;
      DrawList(soundList);
      DrawSoundRight;
    end;
    MenuFloppy: begin
      DrawFloppyLeft;
      DrawFloppyRight;
    end;
    MenuHardDisk: begin
      DrawImageLeft(hdList, KindHardDisk, RowHardDisks, 'Hard disk images');
      DrawHardDiskRight;
    end;
    MenuCdRom: begin
      DrawImageLeft(cdList, KindCdRom, RowCdRoms, 'CD-ROM images');
      DrawCdRomRight;
    end;
  else
    DrawSettingsLeft;
    DrawSettingsRight;
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
  Lines = 15;
  HelpText: array[1..Lines] of string[60] = (
    'Left/Right  the tabs: Sound, Floppy, Hard disk, CD-ROM,',
    '            Settings (Tab goes round them too)',
    'Up/Down     move through the list',
    'Enter       use the highlighted one: play the pack, put in',
    '            the disk or disc, or change the setting',
    'A B         on Floppy: put the disk in A: or B:',
    'E           take the disk or disc out',
    '+ - < >     on Sound: volume and balance of the synth',
    '            whose pack is highlighted',
    'R           ask the Bay, the synth and the Duo again',
    'Esc         exit to DOS',
    '',
    'Sound, Floppy and CD-ROM change at once (the Duo in a',
    'second or so). The hard disk waits for the PC''s reset,',
    'and Settings for the next power-on.');
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

procedure PlayPack(i:integer);
var
  message:string;
begin
  if not Synth.Present or ( i < 0 ) or ( i >= Synth.PacksKnown ) then exit;
  if ( i = Synth.PackIndex ) then begin
    Done(true, 'Already playing');
    exit;
  end;
  if Command('HDC,1,PACK,' + IntToStr(i), message) then begin
    Request('HDQ,1,STATUS');
    Done(true, 'Playing ' + PackName(i));
  end
  else Done(false, message);
end;

{ Enter on the CD-ROM tab: the highlighted image into the drive }
procedure InsertDisc;
var
  i:integer;
  message,name:string;
begin
  i := ListSelected(cdList);
  if ( i < 0 ) then exit;
  name := Bay.Files[i].Name;
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
  RefreshBay;
end;

{ Enter on the Hard disk tab: the highlighted image as the hard disk from
  the PC's next reset }
procedure UseHardDisk;
var
  i:integer;
  message,name:string;
begin
  i := ListSelected(hdList);
  if ( i < 0 ) then exit;
  name := Bay.Files[i].Name;
  if ( name = BayValue('device0') ) and ( length(BayValue('device0_next')) = 0 ) then begin
    Done(true, 'Already the hard disk');
    exit;
  end;
  if ( name = BayValue('device0_next') ) then begin
    Done(true, 'Already the hard disk from the next reset');
    exit;
  end;
  if not Confirm('Next boot''s hard disk', 'Make ' + name + ' the hard disk from the next reset?',
                 'DOS keeps running from ' + BayValue('device0') + ' until then.', 'Use it') then exit;
  if Command('SBC,1,SET,device0,' + name, message) then Done(true, name + ' from the next reset')
  else Done(false, message);
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
  code := ListSelected(fdList);
  if ( code >= 0 ) then InsertFloppy(code, letter);
end;

procedure PlayDuoPack(i:integer);
var
  message:string;
begin
  if not Duo.Present or ( i < 0 ) or ( i >= Duo.PackCount ) then exit;
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

{ Enter on the Floppy tab: the highlighted image into a drive (which, with two) }
procedure FloppyEnter;
var
  code:integer;
  letter:char;
begin
  if not Duo.Present then exit;
  code := ListSelected(fdList);
  if ( code < 0 ) then exit;
  letter := ChooseDrive('Insert ' + copy(Duo.Files[code].Name, 1, 30));
  if ( letter <> ' ' ) then InsertFloppy(code, letter);
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

{ ////////////////// The Sound tab's keys ////////////////// }

{ Each acts on the synth whose pack is highlighted }

procedure SoundEnter;
var
  code:integer;
begin
  code := ListSelected(soundList);
  if ( code >= 0 ) then PlayPack(code)
  else if ( code <= RowSecond ) then PlayDuoPack(RowSecond - code);
end;

procedure SoundVolume(step:integer);
begin
  if ( ListSelected(soundList) <= RowSecond ) then SetDuoVolume(DuoVolume + step)
  else SetVolume(Synth.Volume + step);
end;

procedure SoundBalance(step:integer);
begin
  if ( ListSelected(soundList) <= RowSecond ) then Done(true, 'Only the HDD Synth has a balance')
  else SetBalance(Synth.Balance + step);
end;

procedure EjectFloppy;
var
  code,k:integer;
  letter:char;
  letters,disk,message,line2:string;
  mailbox:boolean;
begin
  if not Duo.Present then exit;
  letter := ' ';
  code := ListSelected(fdList);
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
  { The BIOS won't read a drive with no disk in, so SynthMinder loses the Duo
    when the disk it talks through comes out (unless the other drive has one) }
  mailbox := ( DuoBackend = dbFloppy ) and ( letter = DriveLetter(DuoDrive) )
             and not ( TwoDuoDrives and ( length(DuoDisk(chr(ord('A') + ord('B') - ord(letter)))) > 0 ) );
  if mailbox then line2 := 'SynthMinder then loses the Duo until a disk is in.' else line2 := '';
  if not Confirm('Eject', 'Take ' + DuoDiskText(disk) + ' out of ' + letter + ':?', line2, 'Eject') then exit;
  if ( DuoBackend = dbFloppy ) then FlushDos;
  if not Command('FDC,1,EJECT,' + letter, message) then begin
    Done(false, message);
    exit;
  end;
  if mailbox then begin
    ProbeResult[DuoDrive] := FxNoDisk;
    DuoBackend := dbNone;
    DuoLooked := true;
    ClearDuo;
    Done(true, letter + ': is empty: put a disk in from the Duo''s panel, then R');
  end
  else if AwaitSwap(letter, '') then Done(true, letter + ': is empty')
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
  else ListMove(CurrentList^, step);
end;

procedure MoveMenu(step:integer);
begin
  menuIndex := ( menuIndex + step + MenuCount ) mod MenuCount;
  if ( menuIndex <> MenuExit ) then tab := menuIndex;
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
        #71: MoveList(-MaxListRows);     { Home }
        #79: MoveList(MaxListRows);      { End }
        #75: MoveMenu(-1);               { Left }
        #77: MoveMenu(1);                { Right }
      end;
    end;
    #9: begin { Tab: the tabs in turn }
      tab := ( tab + 1 ) mod MenuExit;
      menuIndex := tab;
    end;
    #13: case menuIndex of
      MenuSound: SoundEnter;
      MenuFloppy: FloppyEnter;
      MenuHardDisk: UseHardDisk;
      MenuCdRom: InsertDisc;
      MenuSettings: ChangeSetting;
      MenuExit: quit := true;
    end;
    #27: quit := true;
    '+', '=': if ( tab = MenuSound ) then SoundVolume(5);
    '-', '_': if ( tab = MenuSound ) then SoundVolume(-5);
    '<', ',': if ( tab = MenuSound ) then SoundBalance(-5);
    '>', '.': if ( tab = MenuSound ) then SoundBalance(5);
    'r', 'R': RefreshNow;
    'e', 'E': if ( tab = MenuFloppy ) then EjectFloppy else if ( tab = MenuCdRom ) then Eject;
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
  4,000 bytes) to a file. scripts/screen.py shows it }
procedure SaveScreen(name:string);
var
  f:file;
begin
  Assign(f, name);
  Rewrite(f, 1);
  BlockWrite(f, Mem[$B800:0], 4000);
  Close(f);
end;

{ /DUMP=SOUND, FLOPPY, HARDDISK, CDROM or SETTINGS: draw that tab, save it
  to SCREEN.BIN and exit }
procedure DumpScreen(which:string);
var
  t:integer;
begin
  menuIndex := MenuSound;
  for t := 0 to MenuExit - 1 do
    if ( which = TabNames[t] ) then menuIndex := t;
  tab := menuIndex;
  StartScreen;
  ClrScr;
  DrawAll;
  SaveScreen('SCREEN.BIN');
  EndScreen;
end;

{ /DUMP=EXIT, after a scripted session: the screen as it was left
  (SCREEN.BIN), then each tab (KEYS1.BIN, Sound, to KEYS5.BIN, Settings) }
procedure DumpEveryTab;
var
  t:integer;
begin
  DrawAll;
  SaveScreen('SCREEN.BIN');
  note := '';
  for t := 0 to MenuExit - 1 do begin
    tab := t;
    menuIndex := t;
    DrawAll;
    SaveScreen('KEYS' + IntToStr(t + 1) + '.BIN');
  end;
end;

var
  i,j:integer;
  arg,problem:string;
  demoMode,statusOnly:boolean;
  dumpTab:string[10];
  fdSeek:char;     { /FDSEEK=A: a diagnostic, the controller's seek to cylinder 82 }
  action:TAction;
begin
  UseDosOutput;
  demoMode := false;
  statusOnly := false;
  dumpTab := '';
  fdSeek := ' ';
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
    else if ( copy(arg, 1, 8) = '/FDSEEK=' ) and ( length(arg) = 9 ) and ( arg[9] in ['A', 'B'] ) then fdSeek := arg[9]
    else if ( arg = '/V' ) then begin
      writeln(ApplicationName);
      halt(0);
    end
    else begin
      Usage;
      if ( arg = '/?' ) or ( arg = '/H' ) then halt(ExitDone) else halt(ExitBadOption);
    end;
  end;

  { /FDSEEK=A: the head to cylinder 82 by the controller, what it said at each
    step, and whether the Duo answers there (reads only) }
  if ( fdSeek <> ' ' ) then begin
    i := ord(fdSeek) - ord('A');
    writeln('BIOS before: motors ', Mem[$40:$3F], ', media ', Mem[$40:$90 + i], ', cylinder ', Mem[$40:$94 + i]);
    FdcSeekMailbox(i);
    writeln('FDC: ', FdcLog);
    writeln('BIOS after:  motors ', Mem[$40:$3F], ', media ', Mem[$40:$90 + i], ', cylinder ', Mem[$40:$94 + i]);
    j := ProbeDuo(i);
    case j of
      FxOk: writeln('The Duo answered at cylinder 82');
      FxNoDisk: writeln('Not ready (no disk, or the head isn''t at 82)');
      FxRefused: writeln('The BIOS refused cylinder 82');
    else
      writeln('No answer at cylinder 82 (', j, ')');
    end;
    halt(0);
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

  if ( Backend = bkNone ) then menuIndex := MenuFloppy else menuIndex := MenuSound;
  tab := menuIndex;
  { Each list starts on what's in use: the pack playing, the disk DOS runs
    from, the disc in the drive }
  FillChar(soundList, SizeOf(soundList), 0);
  FillChar(fdList, SizeOf(fdList), 0);
  FillChar(hdList, SizeOf(hdList), 0);
  FillChar(cdList, SizeOf(cdList), 0);
  BuildSoundRows;
  ListFind(soundList, Synth.PackIndex);
  BuildImageRows(hdList, KindHardDisk, RowHardDisks);
  ListFind(hdList, BayFileIndex(BayValue('device0')));
  BuildImageRows(cdList, KindCdRom, RowCdRoms);
  ListFind(cdList, BayFileIndex(BayValue('disc')));
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
  if ( dumpTab = 'EXIT' ) then DumpEveryTab;
  EndScreen;
end.
