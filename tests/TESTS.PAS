Program Tests;
{-----------------------------
SynthMinder unit tests

Covers the units that don't use the screen or the ports
(Sentence, Model, Demo, Options), so they run with Free Pascal on any OS:

  fpc -Mtp -Fu. -FUbuild -obuild/tests tests/TESTS.PAS
  build/tests

or in DOS with Turbo Pascal 7 (scripts/build.sh runs them in DOSBox-X).
------------------------------}
uses
    Sentence,
    Model,
    Demo,
    Options;

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

{ ////////////////// Settings ////////////////// }

procedure TestSettings;
var
  i:integer;
begin
  ClearBay;
  CheckBool('setting', true, ApplyReply(MakeSentence('SBS,1,seek_timing,synth,off')));
  CheckInt('settings', 1, Bay.SettingCount);
  i := SettingIndex('seek_timing');
  CheckInt('setting found', 1, i);
  CheckStr('setting next', 'synth', Bay.Settings[i].Next);
  CheckStr('setting now', 'off', Bay.Settings[i].Now);
  CheckBool('setting replaced', true, ApplyReply(MakeSentence('SBS,1,seek_timing,fdb05,off')));
  CheckInt('setting not repeated', 1, Bay.SettingCount);
  CheckStr('setting next replaced', 'fdb05', Bay.Settings[1].Next);
  CheckBool('setting too short', false, ApplyReply(MakeSentence('SBS,1,seek_timing,synth')));
  CheckInt('no such setting', 0, SettingIndex('bus'));

  { The demo, as the Bay answers }
  DemoReset;
  ClearBay;
  Ask('SBQ,1,SETTINGS');
  CheckInt('demo settings', 7, Bay.SettingCount);
  CheckStr('demo first setting', 'device1', Bay.Settings[1].Key);
  CheckStr('demo device 1', 'cdrom', Bay.Settings[SettingIndex('device1')].Now);
  Ask('SBC,1,SET,seek_timing,fdb05');
  CheckBool('seek timing set', true, LastAck.Ok);
  Ask('SBQ,1,SETTINGS');
  CheckStr('seek timing next', 'fdb05', Bay.Settings[SettingIndex('seek_timing')].Next);
  CheckStr('seek timing still running as it was', 'synth', Bay.Settings[SettingIndex('seek_timing')].Now);
  Ask('SBC,1,SET,write_behind,maybe');
  CheckStr('not a value it takes', 'value', LastAck.Reason);
  Ask('SBC,1,SET,device1,NOWHERE.IMG');
  CheckStr('device 1 not on the card', 'notfound', LastAck.Reason);
  Ask('SBC,1,SET,device1,DOSBENCH.IMG');
  CheckBool('device 1 an image', true, LastAck.Ok);
  Ask('SBC,1,SET,cdrom,QUAKE.ISO');
  CheckBool('the CD at power-on', true, LastAck.Ok);
  Ask('SBC,1,SET,cdrom,ICL386MB.IMG');
  CheckStr('a disk image isn''t a CD', 'value', LastAck.Reason);
  Ask('SBC,1,SET,bus,lane');
  CheckStr('not a setting SET changes', 'key', LastAck.Reason);
end;

{ ////////////////// Command line ////////////////// }

procedure TestOptions;
var
  a:TAction;
  problem:string;
begin
  CheckBool('disc', true, ParseAction('/DISC=QUAKE.ISO', a, problem));
  CheckStr('disc problem', '', problem);
  CheckStr('disc name', 'QUAKE.ISO', a.Text);
  CheckBool('disc kind', true, a.Kind = akDisc);
  CheckBool('eject', true, ParseAction('-DISC=-', a, problem));
  CheckStr('eject name', '-', a.Text);
  CheckBool('volume', true, ParseAction('/VOL=60', a, problem));
  CheckInt('volume value', 60, a.Number);
  CheckBool('volume out of range', true, ParseAction('/VOL=101', a, problem));
  CheckStr('volume out of range problem', '/VOL= takes 0 to 100', problem);
  CheckBool('balance not a number', true, ParseAction('/BAL=LOUD', a, problem));
  CheckStr('balance problem', '/BAL= takes 0 to 100', problem);
  CheckBool('pack', true, ParseAction('/PACK=FDB05', a, problem));
  CheckStr('pack text', 'FDB05', a.Text);
  CheckBool('empty value', true, ParseAction('/PACK=', a, problem));
  CheckStr('empty value problem', '/PACK= needs a value', problem);
  CheckBool('another option', false, ParseAction('/DEMO', a, problem));
  CheckStr('another option no problem', '', problem);
  CheckBool('another option with a value', false, ParseAction('/DUMP=BAY', a, problem));

  { Packs by number, folder or name }
  DemoReset;
  ClearSynth;
  Ask('HDQ,1,STATUS');
  Ask('HDQ,1,PACKS');
  CheckInt('pack by number', 3, FindPack('3'));
  CheckInt('pack by folder', 4, FindPack('VOICE91'));
  CheckInt('pack by name', 0, FindPack('desktop 3.5in 1993'));
  CheckInt('pack out of range', -1, FindPack('6'));
  CheckInt('no such pack', -1, FindPack('FLOPPY'));
end;

begin
  Passes := 0;
  Failures := 0;
  TestSentence;
  TestModel;
  TestDemo;
  TestSettings;
  TestOptions;
  writeln(Passes, ' passed, ', Failures, ' failed');
  if ( Failures > 0 ) then halt(1);
end.
