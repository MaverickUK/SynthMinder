Unit Demo;
{-----------------------------
A pretend IDE Synth Bay with an HDD Synth behind it, and a pretend
FDD Synth Duo serving drives A: and B:, for SYNMIND /DEMO

It answers requests with the same sentences the real ones send
(docs/protocol.md), so the demo runs the code a real Bay does,
and the unit tests can hold the protocol to it.

No screen or ports, so it's unit tested on any OS.
------------------------------}

{ --------- interface -------- }
interface
uses
    Sentence;

procedure DemoReset;
procedure DemoHandle(request:string; var replies:TLines);

{ --------- implementation --------- }
implementation

const
  PackCount = 6;
  Packs: array[0..PackCount - 1] of record
    Folder: string[16];
    Name: string[24];
    Kind: char;
  end = (
    (Folder:'desk93'; Name:'Desktop 3.5in 1993'; Kind:'R'),
    (Folder:'laptop96'; Name:'Laptop 2.5in 1996'; Kind:'R'),
    (Folder:'scsi95'; Name:'Server SCSI 1995'; Kind:'R'),
    (Folder:'stepper85'; Name:'Stepper 1985'; Kind:'M'),
    (Folder:'voice91'; Name:'Voice coil 1991'; Kind:'M'),
    (Folder:'voice97'; Name:'Voice coil 1997'; Kind:'M'));

  FileCount = 8;
  Files: array[0..FileCount - 1] of record
    Name: string[12];
    SizeKB: longint;
    Kind: char;
  end = (
    (Name:'A1200DH0.IMG'; SizeKB:262144; Kind:'H'),
    (Name:'DOSBENCH.IMG'; SizeKB:65536; Kind:'H'),
    (Name:'HDDBENCH.IMG'; SizeKB:65536; Kind:'H'),
    (Name:'HDDSYNTH.IMG'; SizeKB:65536; Kind:'H'),
    (Name:'ICL386MB.IMG'; SizeKB:122880; Kind:'H'),
    (Name:'DESCENT.CUE'; SizeKB:421888; Kind:'C'),
    (Name:'DOOM_SE.ISO'; SizeKB:49152; Kind:'C'),
    (Name:'QUAKE.ISO'; SizeKB:305152; Kind:'C'));

  { The settings SET can change, in the order the Bay gives them, and what
    the pretend Bay runs with (SettingNow); SET changes SettingNext only }
  SettingCount = 7;
  SettingKeys: array[1..SettingCount] of string[13] = (
    'device1', 'cdrom', 'seek_timing', 'activity_link', 'write_behind', 'read_ahead', 'sd_high_speed');
  SettingNow: array[1..SettingCount] of string[12] = (
    'cdrom', 'DOOM_SE.ISO', 'synth', 'on', 'on', 'on', 'on');

  { The Duo's card }
  DuoFileCount = 9;
  DuoFiles: array[0..DuoFileCount - 1] of record
    Name: string[12];
    SizeKB: longint;
    Kind: char;
  end = (
    (Name:'DOS622_1.IMG'; SizeKB:1440; Kind:'I'),
    (Name:'DOS622_2.IMG'; SizeKB:1440; Kind:'I'),
    (Name:'ELITE.IMG'; SizeKB:360; Kind:'I'),
    (Name:'GAMES.IMG'; SizeKB:1440; Kind:'I'),
    (Name:'LEMMINGS.HFE'; SizeKB:2014; Kind:'H'),
    (Name:'MONKEY1.IMG'; SizeKB:720; Kind:'I'),
    (Name:'WB13.ADF'; SizeKB:880; Kind:'A'),
    (Name:'WORKS.IMG'; SizeKB:1440; Kind:'I'),
    (Name:'ZORK1.IMG'; SizeKB:360; Kind:'I'));
  DuoPackCount = 2;
  DuoPacks: array[0..DuoPackCount - 1] of string[12] = ('Recorded', 'Placeholder');

var
  volume,balance,pack:integer;
  disc,device0,device0Next:string[12];
  settingNext:array[1..SettingCount] of string[12];
  duoVolume,duoPack:integer;
  duoDisk:array[0..1] of string[12];  { '' for no disk }
  duoDrivesNext,duoStart0,duoStart1:string[12];

procedure DemoReset;
var
  i:integer;
begin
  volume := 60;
  balance := 55;
  pack := 5;
  disc := 'DOOM_SE.ISO';
  device0 := 'ICL386MB.IMG';
  device0Next := '';
  for i := 1 to SettingCount do settingNext[i] := SettingNow[i];
  duoVolume := 75;
  duoPack := 0;
  duoDisk[0] := 'GAMES.IMG';
  duoDisk[1] := '';
  duoDrivesNext := 'a,b';
  duoStart0 := '';
  duoStart1 := '';
end;

{ ////////////////// Replies ////////////////// }

procedure Reply(var replies:TLines; body:string);
begin
  AddLine(replies, MakeSentence(body));
end;

procedure Ack(var replies:TLines; source:string; what:string; reason:string);
var
  result:string[3];
begin
  if ( length(reason) = 0 ) then result := 'OK' else result := 'ERR';
  Reply(replies, source + ',1,' + what + ',' + result + ',' + reason);
end;

procedure SynthStatus(var replies:TLines);
begin
  Reply(replies, 'HDS,1,v0.24.0,RUN,' + IntToStr(pack) + ',' + IntToStr(PackCount) + ','
                 + IntToStr(volume) + ',' + IntToStr(balance) + ',5080');
end;

procedure SynthPacks(var replies:TLines);
var
  i:integer;
begin
  for i := 0 to PackCount - 1 do
    Reply(replies, 'HDP,1,' + IntToStr(i) + ',' + IntToStr(PackCount) + ','
                   + Packs[i].Folder + ',' + Packs[i].Name + ',' + Packs[i].Kind);
end;

procedure BayStatus(var replies:TLines);
begin
  Reply(replies, 'SBV,1,firmware,0.35.0');
  Reply(replies, 'SBV,1,build,pcb_drive');
  Reply(replies, 'SBV,1,device0,' + device0);
  if ( length(device0Next) > 0 ) then Reply(replies, 'SBV,1,device0_next,' + device0Next);
  Reply(replies, 'SBV,1,device1,cdrom');
  if ( length(disc) > 0 ) then Reply(replies, 'SBV,1,disc,' + disc) else Reply(replies, 'SBV,1,disc,-');
  Reply(replies, 'SBV,1,bus,PIO 3 data lane');
  Reply(replies, 'SBV,1,seek_timing,synth 5400 rpm');
  Reply(replies, 'SBV,1,link,up');
  Reply(replies, 'SBV,1,card,SDIO high speed');
end;

procedure BayFiles(var replies:TLines);
var
  i:integer;
begin
  for i := 0 to FileCount - 1 do
    Reply(replies, 'SBF,1,' + IntToStr(i) + ',' + IntToStr(FileCount) + ','
                   + Files[i].Name + ',' + IntToStr(Files[i].SizeKB) + ',' + Files[i].Kind);
end;

procedure BaySettings(var replies:TLines);
var
  i:integer;
begin
  for i := 1 to SettingCount do
    Reply(replies, 'SBS,1,' + SettingKeys[i] + ',' + settingNext[i] + ',' + SettingNow[i]);
end;

{ The kind of a file on the pretend card, or ' ' if it isn't there }
function FileKind(name:string):char;
var
  i:integer;
begin
  FileKind := ' ';
  for i := 0 to FileCount - 1 do
    if ( Files[i].Name = name ) then FileKind := Files[i].Kind;
end;

{ ////////////////// Requests ////////////////// }

procedure SynthCommand(var f:TFields; n:integer; var replies:TLines);
var
  value:longint;
begin
  if ( n < 4 ) or not FieldToInt(f[4], value) then begin
    Ack(replies, 'HDK', f[3], 'range');
    exit;
  end;
  if ( f[3] = 'VOL' ) or ( f[3] = 'BAL' ) then begin
    if ( value < 0 ) or ( value > 100 ) then begin
      Ack(replies, 'HDK', f[3], 'range');
      exit;
    end;
    if ( f[3] = 'VOL' ) then volume := value else balance := value;
    Ack(replies, 'HDK', f[3], '');
  end
  else if ( f[3] = 'PACK' ) then begin
    if ( value < 0 ) or ( value >= PackCount ) then
      Ack(replies, 'HDK', f[3], 'range')
    else begin
      pack := value;
      Ack(replies, 'HDK', f[3], '');
    end;
  end
  else
    Ack(replies, 'HDK', f[3], 'unknown');
end;

{ SET for a setting SETTINGS lists: '' if the value can be right for the
  key and is on the card where it has to be, else the reason, as the Bay
  checks it }
function CheckSetting(key, value:string):string;
var
  kind:char;
begin
  CheckSetting := 'value';
  kind := FileKind(value);
  if ( key = 'device1' ) then begin
    if ( value = 'none' ) or ( value = 'cdrom' ) or ( kind in ['H', 'C'] ) then CheckSetting := ''
    else if ( pos('.', value) > 0 ) then CheckSetting := 'notfound';
  end
  else if ( key = 'cdrom' ) then begin
    if ( kind = 'C' ) then CheckSetting := ''
    else if ( pos('.ISO', value) > 0 ) or ( pos('.CUE', value) > 0 ) then CheckSetting := 'notfound';
  end
  else if ( key = 'seek_timing' ) then begin
    if ( value = 'off' ) or ( value = 'synth' ) or ( value = 'stepper85' ) or ( value = 'voice91' )
       or ( value = 'voice97' ) or ( value = 'fdb05' ) then CheckSetting := '';
  end
  else if ( value = 'on' ) or ( value = 'off' ) then CheckSetting := '';
end;

procedure SetSetting(key, value:string; var replies:TLines);
var
  i,found:integer;
  reason:string;
begin
  found := 0;
  for i := 1 to SettingCount do
    if ( SettingKeys[i] = key ) then found := i;
  if ( found = 0 ) then begin
    Ack(replies, 'SBK', 'SET', 'key');
    exit;
  end;
  reason := CheckSetting(key, value);
  if ( length(reason) = 0 ) then settingNext[found] := value;
  Ack(replies, 'SBK', 'SET', reason);
end;

procedure BayCommand(var f:TFields; n:integer; var replies:TLines);
begin
  if ( f[3] = 'DISC' ) and ( n >= 4 ) then begin
    if ( f[4] = '-' ) then begin
      disc := '';
      Ack(replies, 'SBK', 'DISC', '');
    end
    else if ( FileKind(f[4]) <> 'C' ) then
      Ack(replies, 'SBK', 'DISC', 'notfound')
    else begin
      disc := f[4];
      Ack(replies, 'SBK', 'DISC', '');
    end;
  end
  else if ( f[3] = 'SET' ) and ( n >= 5 ) and ( f[4] = 'device0' ) then begin
    if ( FileKind(f[5]) <> 'H' ) then
      Ack(replies, 'SBK', 'SET', 'notfound')
    else begin
      if ( f[5] = device0 ) then device0Next := '' else device0Next := f[5];
      Ack(replies, 'SBK', 'SET', '');
    end;
  end
  else if ( f[3] = 'SET' ) and ( n >= 5 ) then
    SetSetting(f[4], f[5], replies)
  else
    Ack(replies, 'SBK', f[3], 'unknown');
end;

{ ////////////////// The FDD Synth Duo ////////////////// }

function DuoFileIndex(name:string):integer;
var
  i,j:integer;
begin
  DuoFileIndex := -1;
  for j := 1 to length(name) do name[j] := UpCase(name[j]);
  for i := 0 to DuoFileCount - 1 do
    if ( DuoFiles[i].Name = name ) then DuoFileIndex := i;
end;

{ As the firmware's describe() }
function DuoFormat(i:integer):string;
begin
  case DuoFiles[i].Kind of
    'H': DuoFormat := 'flux 300 rpm';
    'A': DuoFormat := 'Amiga DD';
  else
    DuoFormat := IntToStr(DuoFiles[i].SizeKB) + ' KB MFM 300 rpm';
  end;
end;

procedure DuoStatus(var replies:TLines);
var
  d,i:integer;
  k:char;
begin
  Reply(replies, 'FDV,1,firmware,0.25.0');
  Reply(replies, 'FDV,1,drives,AB');
  Reply(replies, 'FDV,1,mailbox,A');
  Reply(replies, 'FDV,1,volume,' + IntToStr(duoVolume));
  Reply(replies, 'FDV,1,pack,' + DuoPacks[duoPack]);
  Reply(replies, 'FDV,1,pack_index,' + IntToStr(duoPack));
  for d := 0 to 1 do begin
    k := chr(ord('a') + d);
    i := DuoFileIndex(duoDisk[d]);
    if ( i < 0 ) then
      Reply(replies, 'FDV,1,' + k + '_disk,-')
    else begin
      Reply(replies, 'FDV,1,' + k + '_disk,' + duoDisk[d]);
      Reply(replies, 'FDV,1,' + k + '_kb,' + IntToStr(DuoFiles[i].SizeKB));
      Reply(replies, 'FDV,1,' + k + '_format,' + DuoFormat(i));
      Reply(replies, 'FDV,1,' + k + '_cylinder,0');
      Reply(replies, 'FDV,1,' + k + '_motor,off');
      Reply(replies, 'FDV,1,' + k + '_protect,off');
    end;
  end;
end;

{ From image `from`, as the firmware's FILES pages them }
procedure DuoList(from:longint; var replies:TLines);
var
  i:integer;
begin
  if ( from >= DuoFileCount ) then begin
    Reply(replies, 'FDF,1,' + IntToStr(DuoFileCount) + ',' + IntToStr(DuoFileCount) + ',-,0,-');
    exit;
  end;
  for i := from to DuoFileCount - 1 do
    Reply(replies, 'FDF,1,' + IntToStr(i) + ',' + IntToStr(DuoFileCount) + ',' + DuoFiles[i].Name + ','
                   + IntToStr(DuoFiles[i].SizeKB) + ',' + DuoFiles[i].Kind);
end;

procedure DuoSettings(var replies:TLines);

  function Shown(value:string):string;
  var
    i:integer;
  begin
    if ( length(value) = 0 ) then value := '-';
    for i := 1 to length(value) do if ( value[i] = ',' ) then value[i] := '_';
    Shown := value;
  end;

begin
  Reply(replies, 'FDS,1,drive,' + Shown(duoDrivesNext) + ',a_b');
  Reply(replies, 'FDS,1,device0,' + Shown(duoStart0) + ',-');
  Reply(replies, 'FDS,1,device1,' + Shown(duoStart1) + ',-');
end;

{ A or B (any case) to 0 or 1, or -1 }
function DuoDrive(letter:string):integer;
begin
  DuoDrive := -1;
  if ( length(letter) <> 1 ) then exit;
  case UpCase(letter[1]) of
    'A': DuoDrive := 0;
    'B': DuoDrive := 1;
  end;
end;

procedure DuoCommand(var f:TFields; n:integer; var replies:TLines);
var
  d,i:integer;
  value:longint;
  joined:string;
begin
  if ( f[3] = 'INSERT' ) and ( n >= 5 ) then begin
    d := DuoDrive(f[4]);
    i := DuoFileIndex(f[5]);
    if ( d < 0 ) then Ack(replies, 'FDK', 'INSERT', 'nodrive')
    else if ( i < 0 ) then Ack(replies, 'FDK', 'INSERT', 'notfound')
    else begin
      duoDisk[d] := DuoFiles[i].Name;
      Ack(replies, 'FDK', 'INSERT', '');
    end;
  end
  else if ( f[3] = 'EJECT' ) and ( n >= 4 ) then begin
    d := DuoDrive(f[4]);
    if ( d < 0 ) then Ack(replies, 'FDK', 'EJECT', 'nodrive')
    else if ( length(duoDisk[d]) = 0 ) then Ack(replies, 'FDK', 'EJECT', 'empty')
    else begin
      duoDisk[d] := '';
      Ack(replies, 'FDK', 'EJECT', '');
    end;
  end
  else if ( ( f[3] = 'VOL' ) or ( f[3] = 'PACK' ) ) and ( n >= 4 ) then begin
    if not FieldToInt(f[4], value) then Ack(replies, 'FDK', f[3], 'range')
    else if ( f[3] = 'VOL' ) and ( value >= 0 ) and ( value <= 100 ) then begin
      duoVolume := value;
      Ack(replies, 'FDK', 'VOL', '');
    end
    else if ( f[3] = 'PACK' ) and ( value >= 0 ) and ( value < DuoPackCount ) then begin
      duoPack := value;
      Ack(replies, 'FDK', 'PACK', '');
    end
    else Ack(replies, 'FDK', f[3], 'range');
  end
  else if ( f[3] = 'SET' ) and ( n >= 5 ) then begin
    joined := f[5];
    for i := 6 to n do joined := joined + ',' + f[i];
    if ( f[4] = 'drive' ) then begin
      if ( joined = 'a' ) or ( joined = 'b' ) or ( joined = 'a,b' ) then begin
        duoDrivesNext := joined;
        Ack(replies, 'FDK', 'SET', '');
      end
      else Ack(replies, 'FDK', 'SET', 'value');
    end
    else if ( f[4] = 'device0' ) or ( f[4] = 'device1' ) then begin
      if ( joined <> '-' ) and ( DuoFileIndex(joined) < 0 ) then Ack(replies, 'FDK', 'SET', 'value')
      else begin
        if ( joined = '-' ) then joined := '';
        if ( f[4] = 'device0' ) then duoStart0 := joined else duoStart1 := joined;
        Ack(replies, 'FDK', 'SET', '');
      end;
    end
    else Ack(replies, 'FDK', 'SET', 'key');
  end
  else
    Ack(replies, 'FDK', f[3], 'unknown');
end;

procedure DemoHandle(request:string; var replies:TLines);
var
  f:TFields;
  n,i:integer;
  from:longint;
begin
  ClearLines(replies);
  if not ParseSentence(request, f, n) or ( n < 3 ) or ( f[2] <> '1' ) then begin
    Ack(replies, 'SBK', 'REQUEST', 'invalid');
    exit;
  end;

  if ( f[1] = 'HDQ' ) and ( f[3] = 'STATUS' ) then SynthStatus(replies)
  else if ( f[1] = 'HDQ' ) and ( f[3] = 'PACKS' ) then SynthPacks(replies)
  else if ( f[1] = 'HDC' ) then SynthCommand(f, n, replies)
  else if ( f[1] = 'SBQ' ) and ( f[3] = 'STATUS' ) then BayStatus(replies)
  else if ( f[1] = 'SBQ' ) and ( f[3] = 'FILES' ) then BayFiles(replies)
  else if ( f[1] = 'SBQ' ) and ( f[3] = 'SETTINGS' ) then BaySettings(replies)
  else if ( f[1] = 'SBC' ) then BayCommand(f, n, replies)
  else if ( f[1] = 'FDQ' ) and ( f[3] = 'STATUS' ) then DuoStatus(replies)
  else if ( f[1] = 'FDQ' ) and ( f[3] = 'FILES' ) then begin
    if ( n < 4 ) or not FieldToInt(f[4], from) then from := 0;
    DuoList(from, replies);
  end
  else if ( f[1] = 'FDQ' ) and ( f[3] = 'PACKS' ) then begin
    for i := 0 to DuoPackCount - 1 do
      Reply(replies, 'FDP,1,' + IntToStr(i) + ',' + IntToStr(DuoPackCount) + ',' + DuoPacks[i]);
  end
  else if ( f[1] = 'FDQ' ) and ( f[3] = 'SETTINGS' ) then DuoSettings(replies)
  else if ( f[1] = 'FDC' ) then DuoCommand(f, n, replies)
  else if ( copy(f[1], 1, 2) = 'FD' ) then Ack(replies, 'FDK', f[3], 'unknown')
  else Ack(replies, 'SBK', f[1], 'unknown');
end;

begin
  DemoReset;
end.
