Program SynMind;
{-----------------------------
SynthMinder: see and change the HDD Synth and IDE Synth Bay from DOS

  SYNMIND           find the Bay and open SynthMinder
  SYNMIND /DEMO     a pretend Bay and synth, to try it out
  SYNMIND /STATUS   print what the Bay and synth say, and exit
  SYNMIND /V        print the version

and for batch files (OPTIONS.PAS):

  SYNMIND /DISC=QUAKE.ISO /PACK=3 /VOL=60 /BAL=50 /Q

The Bay is found on the IDE bus and answers through its own
command (docs/protocol.md); it passes the synth's sentences on
over the Synth Link.
------------------------------}
uses
    FpuFix, { First: see FPUFIX.PAS }
    Crt,
    Dos,
    Sentence,
    Model,
    Ide,
    Link,
    Options,
    Screen;

{$I VERSION.INC}

const
  ApplicationName = 'SynthMinder v' + AppVersion;

  MenuSynth = 0;
  MenuBay = 1;
  MenuSettings = 2;
  MenuRefresh = 3;
  MenuExit = 4;
  MenuCount = 5;
  MenuCaptions: array[0..MenuCount - 1] of string[8] = ('Synth', 'Bay', 'Settings', 'Refresh', 'Exit');
  MenuHints: array[0..MenuCount - 1] of string[78] = (
    'The HDD Synth: its sample pack, volume and balance',
    'The Bay''s SD card: change the CD, or the hard disk for the next power-on',
    'The Bay''s settings: changes take effect from the next power-on',
    'Ask the Bay and the synth again',
    'Exit to DOS');

  { The Settings tab's rows: a heading (no key), or a setting the Bay lists
    with $SBQ,1,SETTINGS }
  SettingRowCount = 10;
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
    (Key:'sd_high_speed'; Caption:'SD card speed'));
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

  MaxChoices = MaxFiles + 2;

  { Rows of the Bay's list that aren't files }
  RowHardDisks = -1;
  RowCdRoms = -2;

var
  menuIndex:integer;
  tab:integer;              { MenuSynth, MenuBay or MenuSettings: what the panels show }
  setSel:integer;           { The Settings tab's row, 1..SettingRowCount, never a heading }
  choiceValue:array[1..MaxChoices] of string[12];  { The chooser's choices }
  choiceWords:array[1..MaxChoices] of string[40];
  choiceCount:integer;
  packSel,packTop:integer;
  bayRows:array[0..MaxFiles + 1] of integer; { File index, or RowHardDisks/RowCdRoms }
  bayRowCount:integer;
  baySel,bayTop:integer;
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

{ ////////////////// Settings tab ////////////////// }

{ A setting's value in words }
function SettingText(key, value:string):string;
begin
  if ( key = 'device1' ) and ( value = 'cdrom' ) then SettingText := 'CD-ROM drive'
  else if ( key = 'sd_high_speed' ) and ( value = 'on' ) then SettingText := 'high'
  else if ( key = 'sd_high_speed' ) and ( value = 'off' ) then SettingText := 'normal'
  else SettingText := value;
end;

{ Move the Settings tab's selection by a step, skipping the headings }
procedure MoveSetSel(step:integer);
var
  next:integer;
begin
  next := setSel;
  repeat
    next := next + step;
    if ( next < 1 ) or ( next > SettingRowCount ) then exit;
  until length(SettingRows[next].Key) > 0;
  setSel := next;
end;

procedure DrawSettingsLeft;
var
  y,fore,back:byte;
  row,i:integer;
  mark,text:string;
begin
  y := PanelTop;
  if ( Bay.SettingCount = 0 ) then begin
    LeftLine(y, 'Settings', ColorHeadingText, ColorHeadingBack);
    LeftLine(y + 1, '', ColorText, ColorBackground);
    LeftLine(y + 2, 'This Bay''s firmware can''t show its', ColorText, ColorBackground);
    LeftLine(y + 3, 'settings: IDE Synth Bay 0.36.0 or', ColorText, ColorBackground);
    LeftLine(y + 4, 'later can.', ColorText, ColorBackground);
    ClearLeft(y + 5, FrameBottom - 1);
    exit;
  end;
  if ( setSel < 1 ) or ( length(SettingRows[setSel].Key) = 0 ) then begin
    setSel := 1;
    MoveSetSel(1);
  end;
  for row := 1 to SettingRowCount do begin
    if ( length(SettingRows[row].Key) = 0 ) then
      LeftLine(y, SettingRows[row].Caption, ColorHeadingText, ColorHeadingBack)
    else begin
      i := SettingIndex(SettingRows[row].Key);
      mark := ' ';
      text := '  ' + PadRight(SettingRows[row].Caption, 17);
      if ( i > 0 ) then begin
        text := text + SettingText(SettingRows[row].Key, Bay.Settings[i].Next);
        if ( Bay.Settings[i].Next <> Bay.Settings[i].Now ) then mark := ChChanged;
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
    end;
    inc(y);
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
  i:integer;
  key:string;
begin
  y := PanelTop;
  if ( Bay.SettingCount > 0 ) and ( setSel >= 1 ) and ( setSel <= SettingRowCount ) then begin
    key := SettingRows[setSel].Key;
    RightHeading(y, SettingRows[setSel].Caption);
    RightGap(y);
    SettingWords(y, key);
    RightGap(y);
    i := SettingIndex(key);
    if ( i > 0 ) then begin
      RightField(y, 'Now', SettingText(key, Bay.Settings[i].Now));
      RightField(y, 'Next start', SettingText(key, Bay.Settings[i].Next));
    end;
    RightGap(y);
    RightLine(y, 'Enter changes it, from the next', ColorNote, ColorBackground); inc(y);
    RightLine(y, 'power-on: the PC runs from the Bay.', ColorNote, ColorBackground); inc(y);
    RightGap(y);
  end;
  RightHeading(y, 'IDE Synth Bay');
  BayFields(y);
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
  else begin
    DrawBayLeft;
    DrawBayRight;
  end;

  if ( Backend = bkDemo ) then where := 'Demo: a pretend Bay and synth'
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
  Lines = 16;
  HelpText: array[1..Lines] of string[60] = (
    'Left/Right  the menu: Synth, Bay, Settings, Refresh, Exit',
    'Up/Down     move through the list',
    'Enter       on Synth: play the highlighted pack',
    '            on Bay: put a CD image in the CD-ROM drive, or',
    '            make a disk image the hard disk at next power-on',
    '            on Settings: change the highlighted setting',
    '+ -         synth volume up or down',
    '< >         synth balance left or right',
    'E           take the disc out of the CD-ROM drive',
    'R           ask the Bay and the synth again',
    'Esc         exit to DOS',
    '',
    'The synth keeps volume, balance and pack, as if you had',
    'turned its knob. The Bay''s hard disk can''t change while',
    'DOS runs from it, so a new one waits for the next power-on.',
    '');
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
  if ( menuIndex in [MenuSynth, MenuBay, MenuSettings] ) then tab := menuIndex;
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
    #9: begin { Tab: Synth, Bay, Settings in turn }
      if ( tab = MenuSynth ) then tab := MenuBay
      else if ( tab = MenuBay ) then tab := MenuSettings
      else tab := MenuSynth;
      menuIndex := tab;
    end;
    #13: case menuIndex of
      MenuSynth: PlayPack;
      MenuBay: InsertOrBoot;
      MenuSettings: ChangeSetting;
      MenuRefresh: RefreshNow;
      MenuExit: quit := true;
    end;
    #27: quit := true;
    '+', '=': SetVolume(Synth.Volume + 5);
    '-', '_': SetVolume(Synth.Volume - 5);
    '<', ',': SetBalance(Synth.Balance - 5);
    '>', '.': SetBalance(Synth.Balance + 5);
    'r', 'R': RefreshNow;
    'e', 'E': Eject;
  end;
end;

{ ////////////////// Without the screen ////////////////// }

procedure PrintStatus;
var
  i:integer;
begin
  writeln(ApplicationName);
  if ( Backend = bkDemo ) then writeln('Demo: a pretend Bay and synth')
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
end;

procedure Usage;
begin
  writeln(ApplicationName, ': the HDD Synth and IDE Synth Bay from DOS');
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
  writeln('  /Q                no messages, just the ERRORLEVEL:');
  writeln('                    0 done, 1 a bad option, 2 no Bay, 3 refused, 4 no synth');
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

{ Run one /DISC, /PACK, /VOL or /BAL: its ERRORLEVEL }
function RunAction(var a:TAction):integer;
var
  message:string;
  i:integer;
begin
  RunAction := ExitDone;
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

{ /DUMP=SYNTH or BAY: draw that tab, save it and exit }
procedure DumpScreen(which:string);
begin
  if ( which = 'BAY' ) then menuIndex := MenuBay
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

  if demoMode then
    Backend := bkDemo
  else begin
    if not FindBay then begin
      if not quiet then begin
        writeln('SynthMinder: no IDE Synth Bay found on the primary or secondary IDE channel.');
        writeln('To try SynthMinder without one: SYNMIND /DEMO');
      end;
      halt(ExitNoBay);
    end;
    Backend := bkIde;
  end;

  RefreshAll;
  if ( Backend = bkIde ) and not Bay.Present then begin
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

  menuIndex := MenuSynth;
  tab := MenuSynth;
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
  until quit;
  { /DUMP=EXIT: the screen as it was when Esc was pressed, for scripted tests }
  if ( dumpTab = 'EXIT' ) then begin
    DrawAll;
    SaveScreen;
  end;
  EndScreen;
end.
