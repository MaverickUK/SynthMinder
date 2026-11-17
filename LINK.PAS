Unit Link;
{-----------------------------
Sending requests to the Bay (or the demo) and taking in the replies

Everything SynthMinder asks or changes goes through Request, so
the screen code doesn't care whether it's talking to a real Bay.
------------------------------}

{ --------- interface -------- }
interface

type
  TBackend = (bkNone, bkDemo, bkIde);

var
  Backend: TBackend;
  LinkProblem: string[60]; { Why the last request failed, '' if it worked }

function Request(body:string):boolean;
function Command(body:string; var message:string):boolean;
procedure RefreshAll;
procedure RefreshSynth;
procedure RefreshBay;

{ --------- implementation --------- }
implementation
uses
    Sentence,
    Model,
    Demo,
    Ide;

var
  replies:TLines; { Here rather than on the stack: it's 6 KB }

{ Send one request and take in every sentence of the reply }
function Request(body:string):boolean;
var
  i,result:integer;
begin
  Request := false;
  LinkProblem := '';
  ClearLines(replies);

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
end;

procedure RefreshAll;
begin
  RefreshBay;
  RefreshSynth;
end;

begin
  Backend := bkNone;
  LinkProblem := '';
end.
