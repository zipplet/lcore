{$apptype console}

{ Copyright (C) 2009 Bas Steendijk and Peter Green
  For conditions of distribution and use, see copyright notice in zlib_license.txt
  which is included in the package
  ----------------------------------------------------------------------------- }


program testreadtxt2;
uses readtxt2, classes;

var
  t: treadtxt;
  f: file;
procedure writestring(var f: file; s : string);
begin
  blockwrite(f,s[1],length(s));
end;

begin
  assignfile(f,'mixed.txt');
  rewrite(f,1);
  writestring(f,'DOS'#13#10);
  writestring(f,'UNIX'#10);
  writestring(f,'MAC'#13);
  writestring(f,'UNIX'#10);
  writestring(f,'NONE');
  closefile(f);
  
  writeln('reading test file in default mode (all line endings treated as line endings)');
  t := treadtxt.createf('mixed.txt');
  if t.readline = 'DOS' then writeln('DOS success') else writeln('DOS fail');
  if t.readline = 'UNIX' then writeln('UNIX success') else writeln('UNIX fail');
  if t.readline = 'MAC' then writeln('MAC success') else writeln('MAC fail');
  if t.readline = 'UNIX' then writeln('UNIX success') else writeln('UNIX fail');
  if t.readline = 'NONE' then writeln('NONE success') else writeln('NONE fail');
  t.destroy;
  
  writeln('reading test file with only CR treated as a line ending');
  t := treadtxt.createf('mixed.txt');
  t.allowedeol := eoltype_cr;
  if t.readline = 'DOS' then writeln('DOS success') else writeln('DOS fail');
  if t.readline = #10'UNIX'#10'MAC' then writeln('LF+UNIX+LF+MAC success') else writeln('LF+UNIX+LF+MAC fail');
  if t.readline = 'UNIX'#10'NONE' then writeln('UNIX+LF+NONE success') else writeln('UNIX+LF+NONE fail');
  t.destroy;

  writeln('reading test file with only LF treated as a line ending');
  t := treadtxt.createf('mixed.txt');
  t.allowedeol := eoltype_lf;
  if t.readline = 'DOS'#13 then writeln('DOS+CR success') else writeln('DOS+CR fail');
  if t.readline = 'UNIX' then writeln('UNIX success') else writeln('UNIX fail');
  if t.readline = 'MAC'#13'UNIX' then writeln('MAC+CR+UNIX success') else writeln('MAC+CR+UNIX fail');
  if t.readline = 'NONE' then writeln('NONE success') else writeln('NONE fail');
  t.destroy;

  writeln('reading test file with only CRLF treated as a line ending');
  t := treadtxt.createf('mixed.txt');
  t.allowedeol := eoltype_crlf;
  if t.readline = 'DOS' then writeln('DOS success') else writeln('DOS fail');
  if t.readline = 'UNIX'#10'MAC'#13'UNIX'#10'NONE' then writeln('UNIX+LF+MAC+CR+UNIX+LF+NONE success') else writeln('UNIX+LF+MAC+CR+UNIX+LF+NONE fail');
  t.destroy;

  
  {$ifdef mswindows}
    //make things a little easier to test in the delphi GUI
    readln;
  {$endif}
end.
