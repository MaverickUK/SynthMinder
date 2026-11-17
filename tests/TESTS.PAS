Program Tests;
{-----------------------------
SynthMinder unit tests

Covers the units that don't use the screen or the ports
(Sentence, Model, Demo), so they run with Free Pascal on any OS:

  fpc -Mtp -Fu. -FUbuild -obuild/tests tests/TESTS.PAS
  build/tests

or in DOS with Turbo Pascal 7 (scripts/build.sh runs them in DOSBox-X).
------------------------------}
uses
    Sentence,
    Model,
    Demo;

var
  Passes,Failures:integer;
  replies:TLines;

{ ////////////////// Assertions ////////////////// }

procedure Fail(name:string; expected:string; actual:string);
begin
  inc(Failures);
  writeln('FAIL: ', name);
  writeln('  expected: "', expected, '"');
  writeln('  actual:   "', actual, '"');
end;

procedure CheckStr(name:string; expected:string; actual:string);
begin
  if ( expected = actual ) then inc(Passes) else Fail(name, expected, actual);
end;

procedure CheckInt(name:string; expected:longint; actual:longint);
begin
  if ( expected = actual ) then inc(Passes) else Fail(name, IntToStr(expected), IntToStr(actual));
end;

procedure CheckBool(name:string; expected:boolean; actual:boolean);
const
  BoolStr: array[boolean] of string[5] = ('false', 'true');
begin
  if ( expected = actual ) then inc(Passes) else Fail(name, BoolStr[expected], BoolStr[actual]);
end;

{ Send a request to the demo and take in its reply, as Link does }
procedure Ask(body:string);
var
  i:integer;
begin
  DemoHandle(MakeSentence(body), replies);
  for i := 1 to replies.Count do
    CheckBool('reply understood: ' + replies.Line[i], true, ApplyReply(replies.Line[i]));
end;

{ ////////////////// Sentence ////////////////// }

procedure TestSentence;
var
  f:TFields;
  n:integer;
  value:longint;
begin
  { Known answers from the HDD Synth's README }
  CheckStr('status query', '$HDQ,1,STATUS*78', MakeSentence('HDQ,1,STATUS'));
  CheckStr('volume command', '$HDC,1,VOL,55*07', MakeSentence('HDC,1,VOL,55'));
  CheckStr('activity', '$HDA,1,1,S,R*4C', MakeSentence('HDA,1,1,S,R'));

  CheckBool('parses', true, ParseSentence('$HDC,1,VOL,55*07', f, n));
  CheckInt('field count', 4, n);
  CheckStr('field 1', 'HDC', f[1]);
  CheckStr('field 4', '55', f[4]);
  CheckBool('line ends ignored', true, ParseSentence('  $HDC,1,VOL,55*07'#13#10, f, n));
  CheckBool('lower case checksum', true, ParseSentence('$HDA,1,1,S,R*4c', f, n));
  CheckBool('bad checksum', false, ParseSentence('$HDC,1,VOL,56*07', f, n));
  CheckBool('no dollar', false, ParseSentence('HDC,1,VOL,55*07', f, n));
  CheckBool('no checksum', false, ParseSentence('$HDC,1,VOL,55', f, n));
  CheckBool('empty', false, ParseSentence('', f, n));

  CheckBool('empty fields', true, ParseSentence(MakeSentence('SBK,1,DISC,OK,'), f, n));
  CheckInt('empty last field counted', 5, n);
  CheckStr('empty last field', '', f[5]);

  CheckBool('number', true, FieldToInt('5080', value));
  CheckInt('number value', 5080, value);
  CheckBool('negative', true, FieldToInt('-1', value));
  CheckInt('negative value', -1, value);
  CheckBool('not a number', false, FieldToInt('5a', value));
  CheckBool('empty number', false, FieldToInt('', value));
end;

{ ////////////////// Model ////////////////// }

procedure TestModel;
begin
  ClearSynth;
  ClearBay;

  CheckBool('status', true, ApplyReply(MakeSentence('HDS,1,v0.24.0,RUN,2,6,55,50,5080')));
  CheckBool('synth present', true, Synth.Present);
  CheckStr('firmware', 'v0.24.0', Synth.Firmware);
  CheckStr('state', 'RUN', Synth.State);
  CheckInt('pack index', 2, Synth.PackIndex);
  CheckInt('pack count', 6, Synth.PackCount);
  CheckInt('volume', 55, Synth.Volume);
  CheckInt('balance', 50, Synth.Balance);
  CheckStr('supercap', '5.08 V', SupercapText);
  CheckBool('status too short', false, ApplyReply(MakeSentence('HDS,1,v0.24.0,RUN,2')));
  CheckBool('version 2 ignored', false, ApplyReply(MakeSentence('HDS,2,v0.24.0,RUN,2,6,55,50,5080')));

  { Packs, with and without the kind (before synth v0.24.0) }
  CheckBool('pack', true, ApplyReply(MakeSentence('HDP,1,0,2,voice97,Voice coil 1997,M')));
  CheckBool('pack without kind', true, ApplyReply(MakeSentence('HDP,1,1,2,mydrive,,')));
  CheckInt('packs known', 2, Synth.PacksKnown);
  CheckStr('pack name', 'Voice coil 1997', PackName(0));
  CheckStr('pack kind', 'M', Synth.Packs[0].Kind);
  CheckStr('pack name falls back to folder', 'mydrive', PackName(1));
  CheckStr('no such pack', '', PackName(5));

  CheckBool('ack', true, ApplyReply(MakeSentence('HDK,1,PACK,ERR,busy')));
  CheckStr('ack what', 'PACK', LastAck.What);
  CheckBool('ack not ok', false, LastAck.Ok);
  CheckStr('ack reason', 'busy', LastAck.Reason);

  CheckBool('bay value', true, ApplyReply(MakeSentence('SBV,1,device0,ICL386MB.IMG')));
  CheckBool('bay present', true, Bay.Present);
  CheckStr('bay value read', 'ICL386MB.IMG', BayValue('device0'));
  CheckBool('bay value replaced', true, ApplyReply(MakeSentence('SBV,1,device0,DOS.IMG')));
  CheckStr('bay value replaced read', 'DOS.IMG', BayValue('device0'));
  CheckInt('bay value not repeated', 1, Bay.ValueCount);
  CheckStr('missing bay value', '', BayValue('nothing'));

  CheckBool('bay file', true, ApplyReply(MakeSentence('SBF,1,0,1,QUAKE.ISO,305152,C')));
  CheckInt('bay files', 1, Bay.FileCount);
  CheckStr('bay file name', 'QUAKE.ISO', Bay.Files[0].Name);
  CheckInt('bay file size', 305152, Bay.Files[0].SizeKB);
  CheckStr('bay file kind', 'C', Bay.Files[0].Kind);

  CheckBool('unknown sentence', false, ApplyReply(MakeSentence('HDX,1,what')));
  CheckBool('activity is not a reply', false, ApplyReply('$HDA,1,1,S,R*4C'));
end;

{ ////////////////// Demo ////////////////// }

procedure TestDemo;
var
  acks:integer;
begin
  DemoReset;
  ClearSynth;
  ClearBay;

  Ask('HDQ,1,STATUS');
  Ask('HDQ,1,PACKS');
  CheckInt('demo packs', 6, Synth.PacksKnown);
  CheckStr('demo playing', 'Voice coil 1997', PackName(Synth.PackIndex));

  acks := AckCount;
  Ask('HDC,1,VOL,75');
  CheckInt('volume acked', acks + 1, AckCount);
  CheckBool('volume ok', true, LastAck.Ok);
  Ask('HDQ,1,STATUS');
  CheckInt('volume changed', 75, Synth.Volume);
  Ask('HDC,1,VOL,101');
  CheckBool('volume out of range', false, LastAck.Ok);
  CheckStr('volume out of range reason', 'range', LastAck.Reason);
  Ask('HDC,1,PACK,6');
  CheckBool('pack out of range', false, LastAck.Ok);
  Ask('HDC,1,PACK,3');
  Ask('HDQ,1,STATUS');
  CheckStr('pack changed', 'Stepper 1985', PackName(Synth.PackIndex));

  Ask('SBQ,1,STATUS');
  Ask('SBQ,1,FILES');
  CheckStr('demo device 0', 'ICL386MB.IMG', BayValue('device0'));
  CheckStr('demo disc', 'DOOM_SE.ISO', BayValue('disc'));
  CheckInt('demo files', 8, Bay.FileCount);

  Ask('SBC,1,DISC,QUAKE.ISO');
  CheckBool('disc ok', true, LastAck.Ok);
  Ask('SBQ,1,STATUS');
  CheckStr('disc changed', 'QUAKE.ISO', BayValue('disc'));
  Ask('SBC,1,DISC,ICL386MB.IMG');
  CheckStr('a disk image isn''t a disc', 'notfound', LastAck.Reason);
  Ask('SBC,1,DISC,-');
  Ask('SBQ,1,STATUS');
  CheckStr('ejected', '-', BayValue('disc'));

  Ask('SBC,1,SET,device0,DOSBENCH.IMG');
  CheckBool('next boot ok', true, LastAck.Ok);
  Ask('SBQ,1,STATUS');
  CheckStr('next boot', 'DOSBENCH.IMG', BayValue('device0_next'));
  CheckStr('device 0 unchanged until then', 'ICL386MB.IMG', BayValue('device0'));

  Ask('SBC,1,REBOOT');
  CheckStr('unknown command', 'unknown', LastAck.Reason);
  DemoHandle('$HDQ,1,STATUS*00', replies);
  CheckInt('bad checksum answered', 1, replies.Count);
  ApplyReply(replies.Line[1]);
  CheckStr('bad checksum refused', 'invalid', LastAck.Reason);
end;

begin
  Passes := 0;
  Failures := 0;
  TestSentence;
  TestModel;
  TestDemo;
  writeln(Passes, ' passed, ', Failures, ' failed');
  if ( Failures > 0 ) then halt(1);
end.
