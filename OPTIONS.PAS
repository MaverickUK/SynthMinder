Unit Options;
{-----------------------------
SynthMinder's command-line changes, for batch files

  SYNMIND /DISC=QUAKE.ISO    put a CD image in the Bay's CD-ROM drive
  SYNMIND /DISC=-            take the disc out
  SYNMIND /PACK=3            play sample pack 3, or by its folder or name
  SYNMIND /VOL=60 /BAL=50    the synth's volume and balance, 0-100
  SYNMIND /Q ...             no messages, just the ERRORLEVEL

They run in the order given. The ERRORLEVEL says how it went (Exit...).

No screen or ports, so it's unit tested on any OS.
------------------------------}

{ --------- interface -------- }
interface

const
  MaxActions = 8;

  { ERRORLEVELs }
  ExitDone = 0;
  ExitBadOption = 1;
  ExitNoBay = 2;     { No Bay found, or it didn't answer }
  ExitRefused = 3;   { The Bay or synth said no: not on the card, no CD-ROM drive, out of range }
  ExitNoSynth = 4;   { No HDD Synth answering on the Synth Link }

type
  TActionKind = (akDisc, akPack, akVolume, akBalance);
  TAction = record
    Kind: TActionKind;
    Text: string[32];   { /DISC: the image, '-' to eject; /PACK: a number, folder or name }
    Number: longint;    { /VOL, /BAL: 0-100 }
  end;

{ One argument, upper case, '/' or '-' first: true if it's one of the
  options above, filling `action`; `problem` says what's wrong with one
  that's meant to be but isn't right. False with an empty problem: not
  one of these (another option) }
function ParseAction(arg:string; var action:TAction; var problem:string):boolean;
function ActionName(kind:TActionKind):string;

{ --------- implementation --------- }
implementation
uses
    Sentence;

function ActionName(kind:TActionKind):string;
begin
  case kind of
    akDisc: ActionName := '/DISC';
    akPack: ActionName := '/PACK';
    akVolume: ActionName := '/VOL';
    akBalance: ActionName := '/BAL';
  end;
end;

function ParseAction(arg:string; var action:TAction; var problem:string):boolean;
var
  name,value:string;
  eq:integer;
  number:longint;
begin
  ParseAction := false;
  problem := '';
  if ( length(arg) > 0 ) and ( arg[1] = '-' ) then arg[1] := '/';
  eq := pos('=', arg);
  if ( eq = 0 ) then exit;
  name := copy(arg, 1, eq - 1);
  value := copy(arg, eq + 1, 255);
  if ( name = '/DISC' ) then action.Kind := akDisc
  else if ( name = '/PACK' ) then action.Kind := akPack
  else if ( name = '/VOL' ) then action.Kind := akVolume
  else if ( name = '/BAL' ) then action.Kind := akBalance
  else exit;
  ParseAction := true;
  action.Text := '';
  action.Number := 0;
  if ( length(value) = 0 ) then begin
    problem := name + '= needs a value';
    exit;
  end;
  if ( length(value) > 32 ) then begin
    problem := name + '=' + value + ' is too long';
    exit;
  end;
  case action.Kind of
    akDisc, akPack: action.Text := value;
    akVolume, akBalance:
      if not FieldToInt(value, number) or ( number < 0 ) or ( number > 100 ) then
        problem := name + '= takes 0 to 100'
      else
        action.Number := number;
  end;
end;

end.
