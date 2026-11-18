Unit Link;
{-----------------------------
Sending requests to the Bay, the FDD Synth Duo (or the demo) and
taking in the replies

Everything SynthMinder asks or changes goes through Request, so
the screen code doesn't care whether it's talking to a real Bay.
$FD... requests go to the Duo, over the floppy cable (FLOPPY.PAS);
the rest to the Bay, over IDE.
------------------------------}

{ --------- interface -------- }
interface

type
  TBackend = (bkNone, bkDemo, bkIde);
  TDuoBackend = (dbNone, dbDemo, dbFloppy);

var
  Backend: TBackend;
  DuoBackend: TDuoBackend;
  DuoLooked: boolean;      { LookForDuo has looked on the floppy drives }
  LinkProblem: string[60]; { Why the last request failed, '' if it worked }

function Request(body:string):boolean;
function Command(body:string; var message:string):boolean;
procedure RefreshAll;
procedure RefreshSynth;
procedure RefreshBay;
procedure RefreshDuo;
{ Looks for the Duo on the floppy drives, once (it takes a second or so):
  true if it's there }
function LookForDuo:boolean;

{ --------- implementation --------- }
implementation
uses
    Sentence,
    Model,
    Demo,
    Ide,
    Floppy;

var
  replies:TLines; { Here rather than on the stack: it's 6 KB }

{ One request to the Duo: false, with LinkProblem, if it failed }
function DuoRequest(body:string):boolean;
var
  result:integer;
begin
  DuoRequest := false;
  case DuoBackend of
    dbDemo: begin
      DemoHandle(MakeSentence(body), replies);
      result := FxOk;
    end;
    dbFloppy: begin
      result := DuoExchange(MakeSentence(body), replies);
      { A swap of the mailbox's own drive waits for the head to leave cylinder 82 }
      if ( copy(body, 1, 10) = 'FDC,1,INSE' ) or ( copy(body, 1, 10) = 'FDC,1,EJEC' ) then DuoPark;
    end;
  else
    begin
      LinkProblem := 'No FDD Synth Duo found';
      exit;
    end;
  end;
  case result of
    FxOk: DuoRequest := true;
    FxNoDuo: LinkProblem := 'The Duo isn''t answering at cylinder 82';
    FxNoDisk: LinkProblem := 'Drive ' + DriveLetter(DuoDrive) + ': isn''t ready: no disk in?';
    FxTimeout: LinkProblem := 'No answer from the Duo in time';
    FxRefused: LinkProblem := 'The BIOS won''t go to cylinder 82';
  else
    LinkProblem := 'The Duo''s reply didn''t make sense';
  end;
end;

{ Send one request and take in every sentence of the reply }
function Request(body:string):boolean;
var
  i,result:integer;
begin
  Request := false;
  LinkProblem := '';
  ClearLines(replies);

  if ( copy(body, 1, 2) = 'FD' ) then begin
    if not DuoRequest(body) then exit;
  end
  else begin
  case Backend of
    bkDemo: begin
      DemoHandle(MakeSentence(body), replies);
      result := ExOk;
    end;
    bkIde: result := BayExchange(MakeSentence(body), replies);
  else
    result := ExNoBay;
  end;

  case result of
    ExOk: ;
    ExNoBay: LinkProblem := 'The Bay isn''t answering';
    ExRefused: LinkProblem := 'The Bay''s firmware doesn''t support SynthMinder';
    ExTimeout: LinkProblem := 'No answer from the Bay in time';
  else
    LinkProblem := 'The Bay''s reply didn''t make sense';
  end;
  if ( result <> ExOk ) then exit;
  end;

  for i := 1 to replies.Count do
    ApplyReply(replies.Line[i]);
  Request := true;
end;

{ A reply's reason in words }
function ReasonText(reason:string):string;
begin
  if ( reason = 'busy' ) then ReasonText := 'it''s busy (starting or changing pack)'
  else if ( reason = 'demo' ) then ReasonText := 'it''s in demo mode'
  else if ( reason = 'range' ) then ReasonText := 'that value is out of range'
  else if ( reason = 'nosynth' ) then ReasonText := 'no HDD Synth is answering on the Synth Link'
  else if ( reason = 'notfound' ) then ReasonText := 'that file isn''t on the card'
  else if ( reason = 'nocdrom' ) then ReasonText := 'the Bay has no CD-ROM drive set up'
  else if ( reason = 'unknown' ) then ReasonText := 'the firmware doesn''t know that command'
  else if ( reason = 'key' ) then ReasonText := 'the Bay can''t change that setting'
  else if ( reason = 'value' ) then ReasonText := 'the Bay doesn''t take that value'
  else if ( reason = 'card' ) then ReasonText := 'the Bay couldn''t write HDDSYNTH.INI on its card'
  else ReasonText := reason;
end;

{ Send a command and say how it went: true if it was done }
function Command(body:string; var message:string):boolean;
var
  acks:integer;
begin
  Command := false;
  acks := AckCount;
  if not Request(body) then begin
    message := LinkProblem;
    exit;
  end;
  if ( AckCount = acks ) then begin
    message := 'No reply to the command';
    exit;
  end;
  if not LastAck.Ok then begin
    message := 'Not done: ' + ReasonText(LastAck.Reason);
    exit;
  end;
  message := '';
  Command := true;
end;

procedure RefreshSynth;
begin
  ClearSynth;
  if not Request('HDQ,1,STATUS') then exit;
  if Synth.Present then Request('HDQ,1,PACKS');
end;

procedure RefreshBay;
begin
  ClearBay;
  if not Request('SBQ,1,STATUS') then exit;
  Request('SBQ,1,FILES');
  { Firmware before 0.36.0 answers SETTINGS with ERR: Bay.SettingCount stays 0 }
  Request('SBQ,1,SETTINGS');
end;

function LookForDuo:boolean;
begin
  if not DuoLooked and ( DuoBackend = dbNone ) then begin
    DuoLooked := true;
    if FindDuo then DuoBackend := dbFloppy;
  end;
  LookForDuo := DuoBackend <> dbNone;
end;

procedure RefreshDuo;
var
  pages:integer;
  before:integer;
begin
  ClearDuo;
  if ( DuoBackend = dbNone ) then exit;
  if not Request('FDQ,1,STATUS') then exit;
  { The images, a page at a time }
  pages := 0;
  repeat
    inc(pages);
    before := Duo.FileCount;
    if not Request('FDQ,1,FILES,' + IntToStr(Duo.FileCount)) then exit;
  until ( Duo.FileCount >= Duo.FilesTotal ) or ( Duo.FileCount = before ) or ( pages >= 8 );
  Request('FDQ,1,PACKS');
  Request('FDQ,1,SETTINGS');
end;

procedure RefreshAll;
begin
  if ( Backend <> bkNone ) then begin  { A PC may have a Duo and no Bay }
    RefreshBay;
    RefreshSynth;
  end;
  RefreshDuo;
end;

begin
  Backend := bkNone;
  DuoBackend := dbNone;
  DuoLooked := false;
  LinkProblem := '';
end.
