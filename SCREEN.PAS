Unit Screen;
{-----------------------------
Drawing: the frame with its two panels, the footer, dialog boxes

The layout and the Classic colours follow GameMinder's, which
follow PathMinder's:

  row 1      menu, with SynthMinder's name on the right
  row 2      what the highlighted menu option does
  rows 3-24  the frame: a list on the left, details on the right
  row 25     the keys
------------------------------}

{ --------- interface -------- }
interface

const
  Columns = 80;
  FrameTop = 3;
  SplitColumn = 40;          { The frame's middle line }
  LeftX = 2;                 { First column of the left panel }
  LeftWidth = SplitColumn - LeftX;
  RightX = SplitColumn + 1;  { First column of the right panel }
  RightWidth = Columns - RightX;
  PanelTop = FrameTop + 1;

  { Characters, code page 437 }
  ChBlock = #219;
  ChShade = #176;
  ChLine = #196;
  ChMarker = #254;
  ChInUse = #16;     { In a list: the pack playing, the disc in the drive, the disk DOS runs from }

var
  ScreenRows:byte;
  { Classic colours }
  ColorBackground, ColorText, ColorFrame, ColorHeadingText, ColorHeadingBack,
  ColorHighlightText, ColorHighlightBack, ColorMenuText, ColorMenuHighlightText,
  ColorMenuHighlightBack, ColorNote, ColorGood, ColorBad, ColorDim:byte;

procedure UseDosOutput;
procedure StartScreen;
procedure EndScreen;
function FrameBottom:byte;
function PadRight(s:string; width:integer):string;
procedure WriteAt(x, y:byte; text:string; fore, back:byte);
procedure DrawFrame;
procedure FrameNote(x:byte; text:string);
procedure DrawFooter(text:string);
procedure DrawBox(x1, y1, x2, y2:byte; title:string);
procedure HideCursor;
procedure ShowCursor;

{ --------- implementation --------- }
implementation
uses
    Crt,
    Dos;

var
  startupMode:word;
  modeChanged:boolean;
  originalCursorShape:word;

{ 25 lines of colour text, as SynthMinder is laid out for }
procedure StartScreen;
begin
  { Writes go straight to the screen through Crt from here on }
  AssignCrt(Output);
  Rewrite(Output);
  startupMode := LastMode;
  modeChanged := false;
  if ( Hi(WindMax) + 1 <> 25 ) then begin
    TextMode(LastMode and $FF);
    modeChanged := true;
  end;
  ScreenRows := Hi(WindMax) + 1;
  HideCursor;
end;

{ Back to how the screen was, cleared, for the DOS prompt }
procedure EndScreen;
begin
  if modeChanged then TextMode(startupMode);
  TextColor(LightGray);
  TextBackground(Black);
  ClrScr;
  ShowCursor;
  UseDosOutput;
end;

{ Writes through DOS, so they can be redirected to a file (Crt takes them
  over when it starts) }
procedure UseDosOutput;
begin
  Assign(Output, '');
  Rewrite(Output);
end;

{ The last row is the footer }
function FrameBottom:byte;
begin
  FrameBottom := ScreenRows - 1;
end;

function PadRight(s:string; width:integer):string;
begin
  if ( width < 0 ) then width := 0;
  if ( length(s) > width ) then s[0] := chr(width);
  while ( length(s) < width ) do s := s + ' ';
  PadRight := s;
end;

procedure WriteAt(x, y:byte; text:string; fore, back:byte);
begin
  GotoXY(x, y);
  TextColor(fore);
  TextBackground(back);
  write(text);
end;

{ ╒═══╤═══╕ with a single line down the middle }
procedure DrawFrame;
var
  y:byte;
  horizontal:string;
begin
  horizontal := '';
  while ( length(horizontal) < Columns - 2 ) do horizontal := horizontal + #205;

  TextColor(ColorFrame);
  TextBackground(ColorBackground);
  GotoXY(1, FrameTop);
  write(#213, horizontal, #184);
  GotoXY(1, FrameBottom);
  write(#212, horizontal, #190);
  for y := FrameTop + 1 to FrameBottom - 1 do begin
    GotoXY(1, y); write(#179);
    GotoXY(SplitColumn, y); write(#179);
    GotoXY(Columns, y); write(#179);
  end;
  GotoXY(SplitColumn, FrameTop); write(#209);
  GotoXY(SplitColumn, FrameBottom); write(#207);
end;

{ A note set into the bottom of the frame, e.g. ╡ Demo ╞ }
procedure FrameNote(x:byte; text:string);
begin
  WriteAt(x, FrameBottom, #181 + ' ' + text + ' ' + #198, ColorFrame, ColorBackground);
end;

{ The keys along the bottom row. Text in [brackets] is a key, drawn in the
  heading colour. All but the last character go through Crt: writing the
  last one with Crt would scroll the screen }
procedure DrawFooter(text:string);
var
  i,column:integer;
  inKey:boolean;
  regs:Registers;
begin
  GotoXY(1, ScreenRows);
  TextBackground(ColorBackground);
  TextColor(ColorText);
  column := 1;
  inKey := false;
  for i := 1 to length(text) do begin
    if ( text[i] = '[' ) then begin
      inKey := true;
      TextColor(ColorHeadingText);
    end
    else if ( text[i] = ']' ) then begin
      inKey := false;
      TextColor(ColorText);
    end
    else if ( column < Columns ) then begin
      write(text[i]);
      inc(column);
    end;
  end;
  TextColor(ColorText);
  while ( column < Columns ) do begin
    write(' ');
    inc(column);
  end;

  { The last character through the video BIOS, which doesn't scroll }
  regs.AH := $02;
  regs.BH := 0;
  regs.DH := ScreenRows - 1;
  regs.DL := Columns - 1;
  Intr($10, regs);
  regs.AH := $09;
  regs.AL := ord(' ');
  regs.BH := 0;
  regs.BL := ( ColorBackground shl 4 ) or ( ColorText and $0F );
  regs.CX := 1;
  Intr($10, regs);
end;

{ A dialog box: grey, a double frame, its title in the top edge and a black
  shadow below and to the right }
procedure DrawBox(x1, y1, x2, y2:byte; title:string);
var
  y:byte;
  inside,horizontal:string;
begin
  horizontal := '';
  while ( length(horizontal) < x2 - x1 - 1 ) do horizontal := horizontal + #205;
  inside := PadRight('', x2 - x1 - 1);

  TextColor(White);
  TextBackground(LightGray);
  GotoXY(x1, y1); write(#201, horizontal, #187);
  for y := y1 + 1 to y2 - 1 do begin
    GotoXY(x1, y); write(#186, inside, #186);
  end;
  GotoXY(x1, y2); write(#200, horizontal, #188);
  if ( length(title) > 0 ) then
    WriteAt(x1 + ( x2 - x1 - length(title) ) div 2 - 1, y1, ' ' + title + ' ', Blue, LightGray);

  { Shadow }
  TextBackground(Black);
  for y := y1 + 1 to y2 + 1 do
    if ( y < ScreenRows ) and ( x2 + 2 <= Columns ) then begin
      GotoXY(x2 + 1, y); write('  ');
    end;
  if ( y2 + 1 < ScreenRows ) then begin
    GotoXY(x1 + 2, y2 + 1); write(PadRight('', x2 - x1));
  end;
end;

{ ////////////////// Cursor ////////////////// }

{ Hide the text cursor through the video BIOS: CGA, EGA, VGA and MDA }
procedure HideCursor;
var
  regs:Registers;
begin
  regs.AH := $03;
  regs.BH := 0;
  Intr($10, regs);
  if ( regs.CX and $2000 ) = 0 then originalCursorShape := regs.CX;
  regs.AH := $01;
  regs.CX := $2000;
  Intr($10, regs);
end;

procedure ShowCursor;
var
  regs:Registers;
begin
  regs.AH := $01;
  regs.CX := originalCursorShape;
  Intr($10, regs);
end;

begin
  originalCursorShape := $0607;
  ScreenRows := 25;
  modeChanged := false;

  ColorBackground := Blue;
  ColorText := White;
  ColorFrame := White;
  ColorHeadingText := Yellow;
  ColorHeadingBack := Red;
  ColorHighlightText := Yellow;
  ColorHighlightBack := Green;
  ColorMenuText := White;
  ColorMenuHighlightText := Blue;
  ColorMenuHighlightBack := LightGray;
  ColorNote := LightCyan;
  ColorGood := LightGreen;
  ColorBad := LightRed;
  ColorDim := LightGray;
end.
