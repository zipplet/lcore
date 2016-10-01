{ Copyright (C) 2005 Bas Steendijk and Peter Green
  For conditions of distribution and use, see copyright notice in zlib_license.txt
  which is included in the package
  ----------------------------------------------------------------------------- }
{
this unit returns unix timestamp with seconds and microseconds (as float)
works on windows/delphi, and on freepascal on unix.
}


unit btime;

interface

{$ifdef mswindows}
uses
  ltimevalstuff;
{$endif}  

type
  float=extended;
  tunixtimeint={$ifdef ver100}longint;{$else}int64;{$endif}

const
  colorburst=39375000/11;  {3579545.4545....}

var
  timezone:integer;
  timezonestr:string;
  irctime,unixtime:tunixtimeint;
  tickcount:integer;
  settimebias:tunixtimeint;
  performancecountfreq:extended;

function irctimefloat:float;
function irctimeint:tunixtimeint;

//unix timestamp (UTC) float seconds
function unixtimefloat:float;
function unixtimeint:tunixtimeint;

//monotonic float seconds
function monotimefloat:float;

//monotonic (alias, old function name)
function wintimefloat:float;

procedure settime(newtime:tunixtimeint);
procedure gettimezone;
procedure timehandler;
procedure init;

function timestring(i:tunixtimeint):string;      // Wednesday August 15 2012 -- 16:21:09 +02:00
function timestrshort(i:tunixtimeint):string;    // Wed Aug 15 16:21:09 2012
function timestriso(i:tunixtimeint):string;      // 2012-08-15 16:21:09
function timestrisoutc(i:float):string;          // 2012-08-15T14:21:09.255553Z

{$ifdef mswindows}
function unixtimefloat_systemtime:float;
{$endif}

function oletounixfloat(t:float):float;
function oletounix(t:tdatetime):tunixtimeint;
function unixtoole(i:float):tdatetime;

{$ifdef mswindows}
function mmtimefloat:float;
function qpctimefloat:float;
{$endif}

{$ifdef mswindows}
procedure gettimeofday(var tv:ttimeval);
{$endif}


const
  mmtime_driftavgsize=32;
  mmtime_warmupnum=4;
  mmtime_warmupcyclelength=15;
var
  //this flag is to be set when btime has been running long enough to stabilise
  warmup_finished:boolean;

  timefloatbias:float;
  ticks_freq:float=0;
  ticks_freq2:float=0;
  ticks_freq_known:boolean=false;
  lastunixtimefloat:float=0;
  lastsynctime:float=0;
  lastsyncbias:float=0;

  mmtime_last:integer=0;
  mmtime_wrapadd:float;
  mmtime_lastsyncmm:float=0;
  mmtime_lastsyncqpc:float=0;
  mmtime_drift:float=1;
  mmtime_lastresult:float;
  mmtime_nextdriftcorrection:float;
  mmtime_driftavg:array[0..mmtime_driftavgsize] of float;
  mmtime_synchedqpc:boolean;

  mmtime_prev_drift:float;
  mmtime_prev_lastsyncmm:float;
  mmtime_prev_lastsyncqpc:float;

implementation

{$ifdef fpc}
  {$mode delphi}
{$endif}

uses
  {$ifdef UNIX}
    {$ifdef VER1_0}
      linux,
    {$else}
      baseunix,unix,unixutil,sockets, {unixutil and sockets needed by unixstuff.inc on some compiler versions}
    {$endif}
    {$ifdef linux}
      dl,
    {$endif}
  {$else}
    windows,unitsettc,mmsystem,
  {$endif}
  sysutils;

  {$include unixstuff.inc}


const
  daysdifference=25569;

function oletounixfloat(t:float):float;
begin
  t := (t - daysdifference) * 86400;
  result := t;
end;

function oletounix(t:tdatetime):tunixtimeint;
begin
  result := round(oletounixfloat(t));
end;

function unixtoole(i:float):tdatetime;
begin
  result := ((i)/86400)+daysdifference;
end;

const
  highdwordconst=65536.0 * 65536.0;

function utrunc(f:float):integer;
{converts float to integer, in 32 bits unsigned range}
begin
  if f >= (highdwordconst/2) then f := f - highdwordconst;
  result := trunc(f);
end;

function uinttofloat(i:integer):float;
{converts 32 bits unsigned integer to float}
begin
  result := i;
  if result < 0 then result := result + highdwordconst;
end;

{$ifdef unix}
{-----------------------------------------*nix/freepascal code to read time }

function unixtimefloat:float;
var
  tv:ttimeval;
begin
  gettimeofday(tv);
  result := tv.tv_sec+(tv.tv_usec/1000000);
end;

{$ifdef linux}
  {$define monotimefloat_implemented}
  const
    CLOCK_MONOTONIC = 1;
  type 
    ptimeval = ^ttimeval;
    tclock_gettime = function(clk_id: integer; tp: ptimeval): integer; cdecl;

  var
    librt_handle:pointer;
    librt_inited:boolean;
    clock_gettime: tclock_gettime;

  function monotimefloat:float;
  var
    ts: ttimeval;
  begin
    if not librt_inited then begin
      librt_inited := true;
      clock_gettime := nil;
      librt_handle := dlopen('librt.so', RTLD_LAZY);
      if assigned(librt_handle) then begin
        clock_gettime := dlsym(librt_handle, 'clock_gettime');
      end;
    end;
    if assigned(clock_gettime) then begin
      if clock_gettime(CLOCK_MONOTONIC, @ts) = 0 then begin
        //note this really returns nanoseconds
        result := ts.tv_sec + ts.tv_usec / 1000000000.0;
        exit;
      end;
    end;
    //fallback
    result := unixtimefloat;
  end;


{$endif} {linux}

{$ifdef darwin} {mac OS X}
{$define monotimefloat_implemented}

  type
    tmach_timebase_info = packed record
      numer: longint;
      denom: longint;
    end;
    pmach_timebase_info = ^tmach_timebase_info;
     
    function mach_absolute_time: int64; cdecl; external;
    function mach_timebase_info(info: pmach_timebase_info): integer; cdecl; external;

  var
    timebase_info: tmach_timebase_info;

  function monotimefloat:float;
  var
    i:int64;
  begin
    if timebase_info.denom = 0 then begin
      mach_timebase_info(@timebase_info);
    end;
    i := mach_absolute_time;
    result := (i * timebase_info.numer div timebase_info.denom) / 1000000000.0;
  end;

{$endif} {darwin, mac OS X}


{$ifndef monotimefloat_implemented} {fallback}
  
  function monotimefloat:extended;
  begin
    result := unixtimefloat;
  end;

{$endif} {monotimefloat fallback}


function unixtimeint:tunixtimeint;
var
  tv:ttimeval;
begin
  gettimeofday(tv);
  result := tv.tv_sec;
end;

{------------------------------ end of *nix/freepascal section}

{$else} {delphi 3}
{------------------------------ windows/delphi code to read time}


{simulate gettimeofday on windows so one can always use gettimeofday if preferred}

procedure gettimeofday(var tv:ttimeval);
var
  e:extended;
begin
  e := unixtimefloat;
  tv.tv_sec := round(int(e));
  tv.tv_usec := trunc(frac(e)*1000000);
  {just in case}
  if (tv.tv_usec < 0) then tv.tv_usec := 0;
  if (tv.tv_usec > 999999) then tv.tv_usec := 999999;
end;


{
time float: gettickcount
resolution: 9x: ~55 ms NT: 1/64th of a second
guarantees: continuous without any jumps
frequency base: same as system clock.
epoch: system boot
note: if called more than once per 49.7 days, 32 bits wrapping is compensated for and it keeps going on.
note: i handle the timestamp as signed integer, but with the wrap compensation that works as well, and is faster
}

function mmtimefloat:float;
const
  wrapduration=highdwordconst * 0.001;
var
  i:integer;
  temp:float;
begin
  i := gettickcount; {timegettime}
  if i < mmtime_last then begin
    mmtime_wrapadd := mmtime_wrapadd + wrapduration;
  end;
  mmtime_last := i;
  result := mmtime_wrapadd + i * 0.001;

  if (ticks_freq <> 0) and ticks_freq_known then begin
    {the value we get is rounded to 1 ms, but the ticks are not a multiple of 1 ms
    this makes the value noisy. use the known ticks frequency to restore the original value}
    temp := int((result / ticks_freq)+0.5) * ticks_freq;

    {if the known ticks freq is wrong (can happen), disable the un-rounding behavior
    this will be a bit less accurate but it prevents problems}
    if abs(temp - result) > 0.002 then begin
      ticks_freq := 0;
    end else result := temp;
  end;
end;

procedure measure_ticks_freq;
var
  f,g:float;
  o:tosversioninfo;
  isnt:boolean;
{  is9x:boolean;}
  adjust1,adjust2:cardinal;
  adjustbool:longbool;
begin
  if (performancecountfreq = 0) then qpctimefloat;
  ticks_freq_known := false;
  settc;
  f := mmtimefloat;
  repeat g := mmtimefloat until g > f;
  unsettc;
  f := g - f;
  fillchar(o,sizeof(o),0);
  o.dwOSVersionInfoSize := sizeof(o);
  getversionex(o);
  isnt := o.dwPlatformId = VER_PLATFORM_WIN32_NT;
{  is9x := o.dwPlatformId = VER_PLATFORM_WIN32_WINDOWS;}

  ticks_freq2 := f;
  mmtime_synchedqpc := false;

  if (isnt and (o.dwMajorVersion >= 5)) then begin
    {windows 2000 and later: query tick rate from OS in 100 ns units
    typical rates: XP: 156250 or 100144, windows 7: 156001}
    if GetSystemTimeAdjustment(adjust1,adjust2,adjustbool) then begin
      ticks_freq := adjust1 / 10000000.0;
      ticks_freq_known := true;
      mmtime_synchedqpc := false;
    end;
  end;

  {9x}
  if (performancecountfreq = 1193182) and (f >= 0.050) and (f <= 0.060) then begin
    ticks_freq_known := true;
    ticks_freq := 65536 / (colorburst / 3);
    mmtime_synchedqpc := true;
  end;
  ticks_freq_known := true;
  if ticks_freq <> 0 then ticks_freq2 := ticks_freq;
//  writeln(formatfloat('0.000000',ticks_freq));
end;

{
time float: QueryPerformanceCounter
resolution: <1us
guarantees: can have forward jumps depending on hardware. can have forward and backwards jitter on dual core.
frequency base: on NT, not the system clock, drifts compared to it.
epoch: system boot
}
function qpctimefloat:extended;
var
  p:packed record
    lowpart:longint;
    highpart:longint
  end;
  p2:tlargeinteger absolute p;
  e:extended;
begin
  if performancecountfreq = 0 then begin
    QueryPerformancefrequency(p2);
    e := p.lowpart;
    if e < 0 then e := e + highdwordconst;
    performancecountfreq := ((p.highpart*highdwordconst)+e);
  end;
  queryperformancecounter(p2);
  e := p.lowpart;
  if e < 0 then e := e + highdwordconst;

  result := ((p.highpart*highdwordconst)+e)/performancecountfreq;
end;

{
time float: QPC locked to gettickcount
resolution: <1us
guarantees: continuous without any jumps
frequency base: same as system clock.
epoch: system boot
}

function mmqpctimefloat:float;
const
  maxretries=5;
  margin=0.002;
var
{  jump:float;}
  mm,f,qpc,newdrift:float;
  qpcjumped:boolean;
  a,b:integer;
{  retrycount:integer;}
begin
  if not ticks_freq_known then measure_ticks_freq;
{  retrycount := maxretries;}

  qpc := qpctimefloat;
  mm := mmtimefloat;
  f := (qpc - mmtime_lastsyncqpc) * mmtime_drift + mmtime_lastsyncmm;
  //writeln('XXXX ',formatfloat('0.000000',qpc-mm));
  qpcjumped := ((f-mm) > ticks_freq2+margin) or ((f-mm) < -margin);
//  if qpcjumped then writeln('qpc jumped ',(f-mm));
  if ((qpc > mmtime_nextdriftcorrection) and not mmtime_synchedqpc) or qpcjumped then begin

    mmtime_nextdriftcorrection := qpc + 1;
    repeat
      mmtime_prev_drift := mmtime_drift;
      mmtime_prev_lastsyncmm := mmtime_lastsyncmm;
      mmtime_prev_lastsyncqpc := mmtime_lastsyncqpc;

      mm := mmtimefloat;
    {  dec(retrycount);}
      settc;
      result := qpctimefloat;
      f := mmtimefloat;
      repeat
        if f = mm then result := qpctimefloat;
        f := mmtimefloat
      until f > mm;
      qpc := qpctimefloat;

      unsettc;
      if (qpc > result + 0.0001) then begin
        continue;
      end;
      mm := f;

      if (mmtime_lastsyncqpc <> 0) and not qpcjumped then begin
        newdrift := (mm - mmtime_lastsyncmm) / (qpc - mmtime_lastsyncqpc);
        mmtime_drift := newdrift;
     {   writeln('raw drift: ',formatfloat('0.00000000',mmtime_drift));}
        move(mmtime_driftavg[0],mmtime_driftavg[1],sizeof(mmtime_driftavg[0])*high(mmtime_driftavg));
        mmtime_driftavg[0] := mmtime_drift;

{        write('averaging drift ',formatfloat('0.00000000',mmtime_drift),' -> ');}
{        mmtime_drift := 0;}
        b := 0;
        for a := 0 to high(mmtime_driftavg) do begin
          if mmtime_driftavg[a] <> 0 then inc(b);
{          mmtime_drift := mmtime_drift + mmtime_driftavg[a];}
        end;
{        mmtime_drift := mmtime_drift / b;}
        a := 5;
        if (b = 1) then a := 5 else if (b = 2) then a := 15 else if (b = 3) then a := 30 else if (b = 4) then a := 60 else if (b = 5) then a := 120 else if (b >= 5) then a := 120;
        mmtime_nextdriftcorrection := qpc + a;
        if (b >= 2) then warmup_finished := true;
{        writeln(formatfloat('0.00000000',mmtime_drift));}
       if mmtime_synchedqpc then mmtime_drift := 1;
      end;

      mmtime_lastsyncqpc := qpc;
      mmtime_lastsyncmm := mm;
  {   writeln(formatfloat('0.00000000',mmtime_drift));}
      break;
    until false;


    qpc := qpctimefloat;

    result := (qpc - mmtime_lastsyncqpc) * mmtime_drift + mmtime_lastsyncmm;

    {f := (qpc - mmtime_prev_lastsyncqpc) * mmtime_prev_drift + mmtime_prev_lastsyncmm;
    jump := result-f;
    writeln('jump ',formatfloat('0.000000',jump),'   drift ',formatfloat('0.00000000',mmtime_drift),' duration ',formatfloat('0.000',(mmtime_lastsyncqpc-mmtime_prev_lastsyncqpc)),' ',formatfloat('0.00000000',jump/(mmtime_lastsyncqpc-mmtime_prev_lastsyncqpc)));}

    f := result;
  end;

  result := f;

  if (result < mmtime_lastresult) then result := mmtime_lastresult;
  mmtime_lastresult := result;
end;

{ free pascals tsystemtime is incompatible with windows api calls
 so we declare it ourselves - plugwash
}
{$ifdef fpc}
type
  TSystemTime = record
     wYear: Word;
     wMonth: Word;
     wDayOfWeek: Word;
     wDay: Word;
     wHour: Word;
     wMinute: Word;
     wSecond: Word;
     wMilliseconds: Word;
  end;
 {$endif}
function Date_utc: extended;
var
  SystemTime: TSystemTime;
begin
  {$ifdef fpc}
    GetsystemTime(@SystemTime);
  {$else}
    GetsystemTime(SystemTime);
  {$endif}
  with SystemTime do Result := EncodeDate(wYear, wMonth, wDay);
end;

function Time_utc: extended;
var
  SystemTime: TSystemTime;
begin
  {$ifdef fpc}
    GetsystemTime(@SystemTime);
  {$else}
    GetsystemTime(SystemTime);
  {$endif}
  with SystemTime do
    Result := EncodeTime(wHour, wMinute, wSecond, wMilliSeconds);
end;

function Now_utc: extended;
begin
  Result := round(Date_utc) + Time_utc;
end;

function unixtimefloat_systemtime:float;
begin
  {result := oletounixfloat(now_utc);}

  {this method gives exactly the same result with extended precision, but is less sensitive to float rounding in theory}
  result := oletounixfloat(int(date_utc+0.5))+time_utc*86400;
end;

function monotimefloat:extended;
begin
  result := mmqpctimefloat;
end;



var
  GetSystemTimePreciseAsFileTime:procedure(var v:tfiletime); stdcall;
  win8inited:boolean;

procedure initwin8;
var
  dllhandle:thandle;

begin
  win8inited := true;
  dllhandle := loadlibrary('kernel32.dll');
  if (dllhandle <> 0) then begin
    GetSystemTimePreciseAsFileTime := getprocaddress(dllhandle,'GetSystemTimePreciseAsFileTime');
  end;
end;


function unixtimefloat_win8:float;
var
  ft:tfiletime;
  i:int64 absolute ft;
begin
  GetSystemTimePreciseAsFileTime(ft);
  {change from windows 1601-01-01 to unix 1970-01-01.
  use integer math for this, to preserve precision}
  dec(i, 116444736000000000);
  result := (i / 10000000);
end;



function unixtimefloat:float;
const
  margin = 0.0012;
var
  f,g,h:float;
begin
  if not win8inited then initwin8;
  if assigned(@GetSystemTimePreciseAsFileTime) then begin
    result := unixtimefloat_win8;
    exit;
  end;

  result := monotimefloat+timefloatbias;
  f := result-unixtimefloat_systemtime;
  if ((f > ticks_freq2+margin) or (f < -margin)) or (timefloatbias = 0) then begin
//    writeln('unixtimefloat init');
    f := unixtimefloat_systemtime;
    settc;
    repeat g := unixtimefloat_systemtime; h := monotimefloat until g > f;
    unsettc;
    timefloatbias := g-h;
    result := unixtimefloat;
  end;

  {for small changes backwards, guarantee no steps backwards}
  if (result <= lastunixtimefloat) and (result > lastunixtimefloat-1.5) then result := lastunixtimefloat + 0.0000001;
  lastunixtimefloat := result;
end;

function unixtimeint:tunixtimeint;
begin
  result := trunc(unixtimefloat);
end;

{$endif}
{-----------------------------------------------end of platform specific}

function wintimefloat:float;
begin
  result := monotimefloat;
end;

function irctimefloat:float;
begin
  result := unixtimefloat+settimebias;
end;

function irctimeint:tunixtimeint;
begin
  result := unixtimeint+settimebias;
end;


procedure settime(newtime:tunixtimeint);
var
  a:tunixtimeint;
begin
  a := irctimeint-settimebias;
  if newtime = 0 then settimebias := 0 else settimebias := newtime-a;

  irctime := irctimeint;
end;

procedure timehandler;
begin
  if unixtime = 0 then init;
  unixtime := unixtimeint;
  irctime := irctimeint;
  if unixtime and 63 = 0 then begin
    {update everything, apply timezone changes, clock changes, etc}
    gettimezone;
    timefloatbias := 0;
    unixtime := unixtimeint;
    irctime := irctimeint;
  end;
end;


procedure gettimezone;
var
  {$ifdef UNIX}
    {$ifndef ver1_9_4}
      {$ifndef ver1_0}
        {$define above194}
      {$endif}
    {$endif}
    {$ifndef above194}
      hh,mm,ss:word;
    {$endif}
  {$endif}
  l:integer;
begin
  {$ifdef UNIX}
    {$ifdef above194}
      timezone := tzseconds;
    {$else}
      gettime(hh,mm,ss);
      timezone := (longint(hh) * 3600 + mm * 60 + ss) - (unixtimeint mod 86400);
    {$endif}
  {$else}
  timezone := round((now-now_utc)*86400);
  {$endif}

  while timezone > 43200 do dec(timezone,86400);
  while timezone < -43200 do inc(timezone,86400);

  if timezone >= 0 then timezonestr := '+' else timezonestr := '-';
  l := abs(timezone) div 60;
  timezonestr := timezonestr + char(l div 600 mod 10+48)+char(l div 60 mod 10+48)+':'+char(l div 10 mod 6+48)+char(l mod 10+48);
end;

function timestrshort(i:tunixtimeint):string;
const
  weekday:array[0..6] of string[4]=('Thu','Fri','Sat','Sun','Mon','Tue','Wed');
  month:array[0..11] of string[4]=('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec');
var
  y,m,d,h,min,sec,ms:word;
  t:tdatetime;
begin
  t := unixtoole(i+timezone);
  decodedate(t,y,m,d);
  decodetime(t,h,min,sec,ms);
  result := weekday[(i+timezone) div 86400 mod 7]+' '+month[m-1]+' '+inttostr(d)+' '+
  inttostr(h div 10)+inttostr(h mod 10)+':'+inttostr(min div 10)+inttostr(min mod 10)+':'+inttostr(sec div 10)+inttostr(sec mod 10)+' '+
  inttostr(y);
end;

function timestring(i:tunixtimeint):string;
const
  weekday:array[0..6] of string[10]=('Thursday','Friday','Saturday','Sunday','Monday','Tuesday','Wednesday');
  month:array[0..11] of string[10]=('January','February','March','April','May','June','July','August','September','October','November','December');
var
  y,m,d,h,min,sec,ms:word;
  t:tdatetime;
begin
  t := unixtoole(i+timezone);
  decodedate(t,y,m,d);
  decodetime(t,h,min,sec,ms);
  result := weekday[(i+timezone) div 86400 mod 7]+' '+month[m-1]+' '+inttostr(d)+' '+inttostr(y)+' -- '+
  inttostr(h div 10)+inttostr(h mod 10)+':'+inttostr(min div 10)+inttostr(min mod 10)+':'+inttostr(sec div 10)+inttostr(sec mod 10)+' '+
  timezonestr;
end;

function timestriso(i:tunixtimeint):string;
var
  y,m,d,h,min,sec,ms:word;
  t:tdatetime;
begin
  t := unixtoole(i+timezone);
  decodedate(t,y,m,d);
  decodetime(t,h,min,sec,ms);
  result := inttostr(y)+'-'+inttostr(m div 10)+inttostr(m mod 10)+'-'+inttostr(d div 10)+inttostr(d mod 10)+' '+inttostr(h div 10)+inttostr(h mod 10)+':'+inttostr(min div 10)+inttostr(min mod 10)+':'+inttostr(sec div 10)+inttostr(sec mod 10);
end;

function timestrisoutc(i:float):string;
var
  y,m,d,h,min,sec,ms:word;
  t:tdatetime;
  fr:float;
begin
  t := unixtoole(i);
  decodedate(t,y,m,d);
  decodetime(t,h,min,sec,ms);
  result := inttostr(y)+'-'+inttostr(m div 10)+inttostr(m mod 10)+'-'+inttostr(d div 10)+inttostr(d mod 10)+'T'+inttostr(h div 10)+inttostr(h mod 10)+':'+inttostr(min div 10)+inttostr(min mod 10)+':'+inttostr(sec div 10)+inttostr(sec mod 10);
  fr := frac(i);

  result := result + '.'+
  inttostr(trunc(fr*10) mod 10)+
  inttostr(trunc(fr*100) mod 10)+
  inttostr(trunc(fr*1000) mod 10)+
  inttostr(trunc(fr*10000) mod 10)+
  inttostr(trunc(fr*100000) mod 10)+
  inttostr(trunc(fr*1000000) mod 10)+'Z';

end;


procedure init;
begin
  {$ifdef mswindows}timebeginperiod(1);{$endif} //ensure stable unchanging clock
  fillchar(mmtime_driftavg,sizeof(mmtime_driftavg),0);
  settimebias := 0;
  gettimezone;
  unixtime := unixtimeint;
  irctime := irctimeint;
end;

initialization init;

end.
