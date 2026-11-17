Unit Demo;
{-----------------------------
A pretend IDE Synth Bay with an HDD Synth behind it, for SYNMIND /DEMO

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

var
  volume,balance,pack:integer;
  disc,device0,device0Next:string[12];

procedure DemoReset;
begin
  volume := 60;
  balance := 55;
  pack := 5;
  disc := 'DOOM_SE.ISO';
  device0 := 'ICL386MB.IMG';
  device0Next := '';
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
  else
    Ack(replies, 'SBK', f[3], 'unknown');
end;

procedure DemoHandle(request:string; var replies:TLines);
var
  f:TFields;
  n:integer;
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
  else if ( f[1] = 'SBC' ) then BayCommand(f, n, replies)
  else Ack(replies, 'SBK', f[1], 'unknown');
end;

begin
  DemoReset;
end.
