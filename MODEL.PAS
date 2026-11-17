Unit Model;
{-----------------------------
What SynthMinder knows about the HDD Synth and the IDE Synth Bay

Filled from the sentences they reply with (docs/protocol.md):

  $HDS  the synth's status        $SBV  one of the Bay's values
  $HDP  one of the synth's packs  $SBF  one file on the Bay's card
  $HDK  the synth's reply to a    $SBK  the Bay's reply to a command
        command

No screen or ports, so it's unit tested on any OS.
------------------------------}

{ --------- interface -------- }
interface

const
  MaxPacks = 32;
  MaxFiles = 48;
  MaxValues = 20;

  { File kinds on the Bay's card }
  KindHardDisk = 'H';
  KindCdRom = 'C';

type
  TPack = record
    Folder: string[32];
    Name: string[32];
    Kind: char;         { M modelled (drive.json), R recorded (WAVs), ? not said }
  end;

  TSynth = record
    Present: boolean;   { Has answered }
    Firmware: string[16];
    State: string[16];  { e.g. RUN, STANDBY }
    PackIndex: integer; { The pack playing, from 0; -1 if none }
    PackCount: integer;
    Volume: integer;    { 0-100 }
    Balance: integer;   { 0-100, 50 is the middle }
    SupercapMv: longint;
    Packs: array[0..MaxPacks - 1] of TPack;
    PacksKnown: integer; { How many of Packs are filled in }
  end;

  TBayFile = record
    Name: string[12];   { 8.3 }
    SizeKB: longint;
    Kind: char;         { KindHardDisk or KindCdRom }
  end;

  TBayValue = record
    Key: string[16];
    Value: string[48];
  end;

  TBay = record
    Present: boolean;   { Found on the IDE bus, or the demo }
    Values: array[1..MaxValues] of TBayValue;
    ValueCount: integer;
    Files: array[0..MaxFiles - 1] of TBayFile;
    FileCount: integer;
  end;

  TAck = record
    Source: string[3];  { HDK or SBK }
    What: string[16];
    Ok: boolean;
    Reason: string[32];
  end;

var
  Synth: TSynth;
  Bay: TBay;
  LastAck: TAck;      { The last reply to a command }
  AckCount: integer;  { Goes up with each reply to a command }

procedure ClearSynth;
procedure ClearBay;
function ApplyReply(line:string):boolean;
function BayValue(key:string):string;
procedure SetBayValue(key:string; value:string);
function PackName(index:integer):string;
function SupercapText:string;

{ --------- implementation --------- }
implementation
uses
    Sentence;

procedure ClearSynth;
begin
  FillChar(Synth, SizeOf(Synth), 0);
  Synth.PackIndex := -1;
end;

procedure ClearBay;
begin
  FillChar(Bay, SizeOf(Bay), 0);
end;

{ One of the Bay's values by key, e.g. 'device0'; '' if it didn't send it }
function BayValue(key:string):string;
var
  i:integer;
begin
  BayValue := '';
  for i := 1 to Bay.ValueCount do
    if ( Bay.Values[i].Key = key ) then begin
      BayValue := Bay.Values[i].Value;
      exit;
    end;
end;

procedure SetBayValue(key:string; value:string);
var
  i:integer;
begin
  for i := 1 to Bay.ValueCount do
    if ( Bay.Values[i].Key = key ) then begin
      Bay.Values[i].Value := value;
      exit;
    end;
  if ( Bay.ValueCount >= MaxValues ) then exit;
  inc(Bay.ValueCount);
  Bay.Values[Bay.ValueCount].Key := key;
  Bay.Values[Bay.ValueCount].Value := value;
end;

{ A pack's name, or its folder when it has no name of its own }
function PackName(index:integer):string;
begin
  PackName := '';
  if ( index < 0 ) or ( index >= Synth.PacksKnown ) then exit;
  if ( length(Synth.Packs[index].Name) > 0 ) then
    PackName := Synth.Packs[index].Name
  else
    PackName := Synth.Packs[index].Folder;
end;

{ e.g. 5.08 V }
function SupercapText:string;
var
  hundredths:longint;
  s:string;
begin
  hundredths := ( Synth.SupercapMv + 5 ) div 10;
  s := IntToStr(hundredths mod 100);
  if ( length(s) < 2 ) then s := '0' + s;
  SupercapText := IntToStr(hundredths div 100) + '.' + s + ' V';
end;

{ $HDS,1,<firmware>,<state>,<packIndex>,<packCount>,<volume>,<balance>,<supercapMv> }
function ApplyStatus(var f:TFields; n:integer):boolean;
var
  packIndex,packCount,volume,balance,mv:longint;
begin
  ApplyStatus := false;
  if ( n < 9 ) then exit;
  if not ( FieldToInt(f[5], packIndex) and FieldToInt(f[6], packCount) and FieldToInt(f[7], volume)
           and FieldToInt(f[8], balance) and FieldToInt(f[9], mv) ) then exit;
  Synth.Present := true;
  Synth.Firmware := f[3];
  Synth.State := f[4];
  Synth.PackIndex := packIndex;
  Synth.PackCount := packCount;
  Synth.Volume := volume;
  Synth.Balance := balance;
  Synth.SupercapMv := mv;
  ApplyStatus := true;
end;

{ $HDP,1,<index>,<count>,<folder>,<name>[,<kind>] - kind from synth v0.24.0 }
function ApplyPack(var f:TFields; n:integer):boolean;
var
  index,count:longint;
begin
  ApplyPack := false;
  if ( n < 6 ) then exit;
  if not ( FieldToInt(f[3], index) and FieldToInt(f[4], count) ) then exit;
  if ( index < 0 ) or ( index >= MaxPacks ) then exit;
  with Synth.Packs[index] do begin
    Folder := f[5];
    Name := f[6];
    if ( n >= 7 ) and ( length(f[7]) = 1 ) then Kind := f[7][1] else Kind := '?';
  end;
  if ( index + 1 > Synth.PacksKnown ) then Synth.PacksKnown := index + 1;
  if ( count > MaxPacks ) then count := MaxPacks;
  if ( Synth.PacksKnown > count ) then Synth.PacksKnown := count;
  Synth.Present := true;
  ApplyPack := true;
end;

{ $HDK or $SBK: ,1,<what>,<OK|ERR>,<reason> }
function ApplyAck(var f:TFields; n:integer):boolean;
begin
  ApplyAck := false;
  if ( n < 4 ) then exit;
  LastAck.Source := f[1];
  LastAck.What := f[3];
  LastAck.Ok := f[4] = 'OK';
  if ( n >= 5 ) then LastAck.Reason := f[5] else LastAck.Reason := '';
  inc(AckCount);
  ApplyAck := true;
end;

{ $SBV,1,<key>,<value> }
function ApplyValue(var f:TFields; n:integer):boolean;
begin
  ApplyValue := false;
  if ( n < 4 ) or ( length(f[3]) = 0 ) then exit;
  SetBayValue(f[3], f[4]);
  Bay.Present := true;
  ApplyValue := true;
end;

{ $SBF,1,<index>,<count>,<name>,<sizeKB>,<kind> }
function ApplyFile(var f:TFields; n:integer):boolean;
var
  index,count,size:longint;
begin
  ApplyFile := false;
  if ( n < 7 ) or ( length(f[7]) <> 1 ) then exit;
  if not ( FieldToInt(f[3], index) and FieldToInt(f[4], count) and FieldToInt(f[6], size) ) then exit;
  if ( index < 0 ) or ( index >= MaxFiles ) then exit;
  with Bay.Files[index] do begin
    Name := f[5];
    SizeKB := size;
    Kind := f[7][1];
  end;
  if ( index + 1 > Bay.FileCount ) then Bay.FileCount := index + 1;
  if ( count > MaxFiles ) then count := MaxFiles;
  if ( Bay.FileCount > count ) then Bay.FileCount := count;
  ApplyFile := true;
end;

{ Take in one sentence of a reply. False if it isn't valid or understood }
function ApplyReply(line:string):boolean;
var
  f:TFields;
  n:integer;
begin
  ApplyReply := false;
  if not ParseSentence(line, f, n) then exit;
  if ( n < 2 ) or ( f[2] <> '1' ) then exit; { Only version 1 }

  if ( f[1] = 'HDS' ) then ApplyReply := ApplyStatus(f, n)
  else if ( f[1] = 'HDP' ) then ApplyReply := ApplyPack(f, n)
  else if ( f[1] = 'HDK' ) or ( f[1] = 'SBK' ) then ApplyReply := ApplyAck(f, n)
  else if ( f[1] = 'SBV' ) then ApplyReply := ApplyValue(f, n)
  else if ( f[1] = 'SBF' ) then ApplyReply := ApplyFile(f, n);
end;

begin
  ClearSynth;
  ClearBay;
  AckCount := 0;
end.
