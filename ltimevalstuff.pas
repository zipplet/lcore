{ Copyright (C) 2005 Bas Steendijk and Peter Green
  For conditions of distribution and use, see copyright notice in zlib_license.txt
  which is included in the package
  ----------------------------------------------------------------------------- }

{$ifdef fpc}
  {$mode delphi}
{$endif}

unit ltimevalstuff;
interface

{$ifdef mswindows}
  type
    ttimeval = record
      tv_sec : longint; 
      tv_usec : longint; 
    end;
{$else}
  {$ifdef ver1_0}
    uses linux;
  {$else}
    uses baseunix,unix,unixutil,sockets;
  {$endif}
{$endif}
                                

procedure tv_add(var tv:ttimeval;msec:integer);
function tv_compare(const tv1,tv2:ttimeval):boolean;
procedure tv_subtract(var tv:ttimeval;const tv2:ttimeval);
procedure msectotimeval(var tv:ttimeval;msec:integer);

//tv_invalidtimebig will always compare as greater than any valid timeval
//unfortunately unixstuff.inc hasn't worked it's magic yet so we
//have to ifdef this manually.
const
  {$ifdef ver1_0}
    tv_invalidtimebig : ttimeval = (sec:maxlongint;usec:maxlongint);
  {$else}
    tv_invalidtimebig : ttimeval = (tv_sec:maxlongint;tv_usec:maxlongint);
  {$endif}
implementation

{$i unixstuff.inc}

{add nn msec to tv}
procedure tv_add(var tv:ttimeval;msec:integer);
begin
  inc(tv.tv_usec,msec*1000);
  inc(tv.tv_sec,tv.tv_usec div 1000000);
  tv.tv_usec := tv.tv_usec mod 1000000;
end;

{tv1 >= tv2}
function tv_compare(const tv1,tv2:ttimeval):boolean;
begin
  if tv1.tv_sec = tv2.tv_sec then begin
    result := tv1.tv_usec >= tv2.tv_usec;
  end else result := tv1.tv_sec > tv2.tv_sec;
end;

procedure tv_subtract(var tv:ttimeval;const tv2:ttimeval);
begin
  dec(tv.tv_usec,tv2.tv_usec);
  if tv.tv_usec < 0 then begin
    inc(tv.tv_usec,1000000);
    dec(tv.tv_sec)
  end;
  dec(tv.tv_sec,tv2.tv_sec);
end;

procedure msectotimeval(var tv:ttimeval;msec:integer);
begin
  tv.tv_sec := msec div 1000;
  tv.tv_usec := (msec mod 1000)*1000;
end;

end.