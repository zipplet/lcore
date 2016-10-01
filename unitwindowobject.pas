{ Copyright (C) 2005 Bas Steendijk and Peter Green
  For conditions of distribution and use, see copyright notice in zlib_license.txt
  which is included in the package
  ----------------------------------------------------------------------------- }

unit unitwindowobject;

interface

uses
  classes,
  {$ifdef mswindows}
    windows,messages,wmessages,
  {$else}
    lmessages,
    {$macro on}
    {$define windows := lmessages}
  {$endif}
  sysutils,
  pgtypes;

type
  twindowobjectbase=class(tobject)
    hwndmain:hwnd;
    onmsg:function(msg,wparam,lparam:taddrint):boolean of object;
    exitloopflag:boolean;
    exstyle,style:integer;
    docreatewindow:boolean;
    function windowprocaddr:pointer; virtual;
    procedure init_window(dwexstyle,dwstyle:cardinal);
    procedure init; virtual;
    procedure initinvisible;
    function settimer(id,timeout:taddrint):integer;
    function killtimer(id:taddrint):boolean;
    procedure postmessage(msg,wparam,lparam:taddrint);
    procedure messageloop;
    {$ifdef mswindows}
      procedure processmessages; virtual;
      function processmessage:boolean;
    {$endif}  
    constructor create; virtual;
    destructor destroy; override;
  end;

  {this type exists for compatibility with the original one in bewarehttpd,
  therefore it inits on create}
  twindowobject=class(twindowobjectbase)
    constructor create; override;
  end;

function WindowProc_windowobjectbase(ahWnd:HWND; auMsg:Integer; awParam:WPARAM; alParam:LPARAM):Integer; stdcall;

var
  twindowobject_Class : TWndClass = (style:0; lpfnWndProc:nil;
  cbClsExtra:0; cbWndExtra:sizeof(pointer); hInstance:thinstance(0); hIcon:hicon(0); hCursor:hcursor(0);
  hbrBackground:hbrush(0);lpszMenuName:nil; lpszClassName:'twindowobject_class');


implementation

//uses safewriteln;

{------------------------------------------------------------------------------}

function WindowProc_windowobjectbase(ahWnd:HWND; auMsg:Integer; awParam:WPARAM; alParam:LPARAM):Integer; stdcall;
var
  i:taddrint;
begin
  ////swriteln('in unitwindowobject.windowproc');
  Result := 0;  // This means we handled the message
  if ahwnd <> hwnd(0) then i := getwindowlongptr(ahwnd,0) else i := 0;
  if i <> 0 then begin
    if assigned(twindowobjectbase(i).onmsg) then begin
      if not twindowobjectbase(i).onmsg(aumsg,awparam,alparam) then i := 0;
    end else i := 0
  end;
  if i = 0 then Result := DefWindowProc(ahWnd, auMsg, awParam, alParam)
end;


function twindowobjectbase.windowprocaddr;
begin
  result := @WindowProc_windowobjectbase;
end;

procedure twindowobjectbase.initinvisible;
begin
  init_window(WS_EX_TOOLWINDOW,WS_POPUP);
end;

procedure twindowobjectbase.init;
begin
  //
end;

function twindowobjectbase.settimer;
begin
  result := windows.settimer(hwndmain,id,timeout,nil);
end;

function twindowobjectbase.killtimer;
begin
  result := windows.killtimer(hwndmain,id);
end;



procedure twindowobjectbase.init_window;
begin
    //swriteln('in twindowobject.create, about to call registerclass');
  twindowobject_Class.lpfnWndProc := windowprocaddr;
  Windows.RegisterClass(twindowobject_Class);
  //swriteln('about to call createwindowex');

  style := dwstyle;
  exstyle := dwexstyle;
  hWndMain := CreateWindowEx(dwexstyle, twindowobject_Class.lpszClassName,
    '', dwstyle, CW_USEDEFAULT, CW_USEDEFAULT,100, 100, hwnd(0), 0, HInstance, nil);
  //swriteln('about to check result of createwindowex');
  if hWndMain = hwnd(0) then raise exception.create('CreateWindowEx failed');
  //swriteln('about to store reference to self in extra window memory');
  setwindowlongptr(hwndmain,0,taddrint(self));
  //swriteln('finished twindowobject.create , hwndmain='+inttohex(taddrint(hwndmain),16));
end;


constructor twindowobjectbase.create;
begin
  inherited;

end;

destructor twindowobjectbase.destroy;
begin
  if hWndMain <> hwnd(0) then DestroyWindow(hwndmain);
  inherited;
end;

procedure twindowobjectbase.postmessage;
begin
  windows.postmessage(hwndmain,msg,wparam,lparam);
end;

{$ifdef mswindows}
function twindowobjectbase.ProcessMessage : Boolean;
var
    MsgRec : TMsg;
begin
    Result := FALSE;
    if PeekMessage(MsgRec, 0, 0, 0, PM_REMOVE) then begin
      Result := TRUE;
      TranslateMessage(MsgRec);
      DispatchMessage(MsgRec);
    end;
end;

procedure twindowobjectbase.processmessages;
begin
  while processmessage do;
end;
{$endif}

procedure twindowobjectbase.messageloop;
var
  MsgRec : TMsg;
begin
  while GetMessage(MsgRec, hwnd(0), 0, 0) do begin
    {$ifdef mswindows}
    TranslateMessage(MsgRec);
    {$endif}
    DispatchMessage(MsgRec);
    if exitloopflag then exit;
    {if not peekmessage(msgrec,0,0,0,PM_NOREMOVE) then onidle}
  end;
end;


{------------------------------------------------------------------------------}

constructor twindowobject.create;
begin
  inherited;
  initinvisible;
end;

{------------------------------------------------------------------------------}


end.
