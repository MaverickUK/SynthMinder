Unit Sentence;
{-----------------------------
Sentences, as the HDD Synth and IDE Synth Bay exchange them

  $HDC,1,VOL,55*07

A '$', the body (fields separated by commas), a '*' and the
checksum: the XOR of the body's characters, as two hex digits.
The same format as the HDD Synth's companion app protocol.

No screen or ports, so it's unit tested on any OS.
------------------------------}

{ --------- interface -------- }
interface

const
  MaxFields = 12;
  MaxLines = 48;     { Sentences in one reply }

type
  TField = string[63];
  TFields = array[1..MaxFields] of TField;

  TLine = string[127];
  TLines = record
    Count: integer;
    Line: array[1..MaxLines] of TLine;
  end;

function Checksum(body:string):byte;
function HexByte(value:byte):string;
function MakeSentence(body:string):string;
function ParseSentence(line:string; var fields:TFields; var count:integer):boolean;
function FieldToInt(field:string; var value:longint):boolean;
function IntToStr(value:longint):string;
procedure ClearLines(var lines:TLines);
procedure AddLine(var lines:TLines; line:string);

{ --------- implementation --------- }
implementation

const
  HexDigits: string[16] = '0123456789ABCDEF';

{ XOR of every character of the body }
function Checksum(body:string):byte;
var
  i:integer;
  sum:byte;
begin
  sum := 0;
  for i := 1 to length(body) do
    sum := sum xor ord(body[i]);
  Checksum := sum;
end;

function HexByte(value:byte):string;
begin
  HexByte := HexDigits[value shr 4 + 1] + HexDigits[value and $0F + 1];
end;

{ e.g. MakeSentence('HDQ,1,STATUS') = '$HDQ,1,STATUS*78' }
function MakeSentence(body:string):string;
begin
  MakeSentence := '$' + body + '*' + HexByte(Checksum(body));
end;

{ Split a sentence into its fields, checking its checksum. Line ends and
  spaces around it are ignored. False if it isn't a valid sentence }
function ParseSentence(line:string; var fields:TFields; var count:integer):boolean;
var
  star,i:integer;
  body:string;
begin
  ParseSentence := false;
  count := 0;

  { Trim spaces and line ends }
  while ( length(line) > 0 ) and ( line[length(line)] in [#13, #10, ' '] ) do
    dec(line[0]);
  while ( length(line) > 0 ) and ( line[1] in [#13, #10, ' '] ) do
    delete(line, 1, 1);

  if ( length(line) < 5 ) or ( line[1] <> '$' ) then exit;
  star := pos('*', line);
  if ( star = 0 ) or ( star <> length(line) - 2 ) then exit;

  body := copy(line, 2, star - 2);
  if ( UpCase(line[star + 1]) + UpCase(line[star + 2]) <> HexByte(Checksum(body)) ) then exit;

  count := 1;
  fields[1] := '';
  for i := 1 to length(body) do begin
    if ( body[i] = ',' ) then begin
      if ( count = MaxFields ) then exit; { Too many fields }
      inc(count);
      fields[count] := '';
    end
    else
      fields[count] := fields[count] + body[i];
  end;

  ParseSentence := true;
end;

{ A field as a whole number, false if it isn't one }
function FieldToInt(field:string; var value:longint):boolean;
var
  code:integer;
begin
  FieldToInt := false;
  if ( length(field) = 0 ) then exit;
  Val(field, value, code);
  FieldToInt := code = 0;
end;

function IntToStr(value:longint):string;
var
  s:string;
begin
  Str(value, s);
  IntToStr := s;
end;

procedure ClearLines(var lines:TLines);
begin
  lines.Count := 0;
end;

procedure AddLine(var lines:TLines; line:string);
begin
  if ( lines.Count >= MaxLines ) then exit;
  inc(lines.Count);
  lines.Line[lines.Count] := line;
end;

end.
