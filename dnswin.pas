unit dnswin;

interface

uses binipstuff,classes,lcore,pgtypes;

{$include lcoreconfig.inc}

//on failure a null string or zeroed out binip will be retuned and error will be
//set to a windows error code (error will be left untouched under non error
//conditions).
function winforwardlookuplist(name : thostname;familyhint:integer;var error : integer) : tbiniplist;
function winreverselookup(ip:tbinip;var error:integer):thostname;


type
  //do not call destroy on a tdnswinasync instead call release and the
  //dnswinasync will be freed when appropriate. Calling destroy will block
  //the calling thread until the dns lookup completes.
  //release should only be called from the main thread
  tdnswinasync=class(tthread)
  private
    freverse : boolean;
    freewhendone : boolean;
    hadevent : boolean;
  protected
    procedure execute; override;
  public
    onrequestdone:tsocketevent;
    name : thostname;
    iplist : tbiniplist;

    procedure forwardlookup(name:thostname);
    procedure reverselookup(ip:tbinip);
    destructor destroy; override;
    procedure release;
    constructor create;
    property reverse : boolean read freverse;

  end;

procedure init;

implementation
uses
  { zipplet: moved pgtypes to interface because it's needed for the string definitions }
  lsocket,sysutils,winsock,windows,messages;

type
  //taddrinfo = record; //forward declaration
  paddrinfo = ^taddrinfo;
  taddrinfo = packed record
    ai_flags : longint;
    ai_family : longint;
    ai_socktype : longint;
    ai_protocol : longint;
    ai_addrlen : taddrint;
    ai_canonname : pansichar;
    ai_addr : pinetsockaddrv;
    ai_next : paddrinfo;
  end;
  ppaddrinfo = ^paddrinfo;
  tgetaddrinfo = function(nodename : pansichar; servname : pansichar; hints : paddrinfo;res : ppaddrinfo) : longint; stdcall;
  tfreeaddrinfo = procedure(ai : paddrinfo); stdcall;
  tgetnameinfo = function(sa:Pinetsockaddrv;salen : longint; host:pansichar;hostlen : longint;serv:pansichar;servlen:longint;flags:longint) : longint;stdcall;
var
  getaddrinfo : tgetaddrinfo;
  freeaddrinfo : tfreeaddrinfo;
  getnameinfo : tgetnameinfo;
procedure v4onlyfreeaddrinfo(ai : paddrinfo); stdcall;
var
  next:paddrinfo;
begin
  while assigned(ai) do begin
    freemem(ai.ai_addr);
    next := ai.ai_next;
    freemem(ai);
    ai := next;
  end;
end;

type
  plongint = ^longint;
  pplongint = ^plongint;

function v4onlygetaddrinfo(nodename : pansichar; servname : pansichar; hints : paddrinfo;res : ppaddrinfo) : longint; stdcall;
var
  output,prev,first : paddrinfo;
  hostent : phostent;
  addrlist:^pointer;
begin
  output := nil;
  if hints.ai_family <> af_inet6 then begin
    result := 0;


    hostent := gethostbyname(nodename);
    if hostent = nil then begin
      result := wsagetlasterror;
      v4onlyfreeaddrinfo(output);
      exit;
    end;
    addrlist := pointer(hostent.h_addr_list);

    //ipint := pplongint(hostent.h_addr_list)^^;
    prev := nil;
    first := nil;
    repeat
      if not assigned(addrlist^) then break;

      getmem(output,sizeof(taddrinfo));
      if assigned(prev) then prev.ai_next := output;
      getmem(output.ai_addr,sizeof(tinetsockaddr));
      if servname <> nil then output.ai_addr.InAddr.port := htons(strtoint(servname)) else output.ai_addr.InAddr.port := 0;
      output.ai_addr.InAddr.addr := longint(addrlist^^);
      inc(integer(addrlist),4);
      output.ai_flags := 0;
      output.ai_family := af_inet;
      output.ai_socktype := 0;
      output.ai_protocol := 0;
      output.ai_addrlen := sizeof(tinetsockaddr);
      output.ai_canonname := nil;
      output.ai_next := nil;
      prev := output;
      if not assigned(first) then first := output;
    until false;
    res^ := first;
  end else begin
    result := WSANO_RECOVERY;
  end;
end;

function min(a,b : integer):integer;
begin
  if a<b then result := a else result := b;
end;

function v4onlygetnameinfo(sa:Pinetsockaddrv;salen : longint; host:pansichar;hostlen : longint;serv:pansichar;servlen:longint;flags:longint) : longint;stdcall;
var
  hostent : phostent;
  bytestocopy : integer;
begin
  if sa.InAddr.family = af_inet then begin
    result := 0;
    hostent := gethostbyaddr(@(sa.inaddr.addr),4,AF_INET);
    if hostent = nil then begin
      result := wsagetlasterror;
      exit;
    end;
    bytestocopy := min(strlen(hostent.h_name)+1,hostlen);
    move((hostent.h_name)^,host^,bytestocopy);


  end else begin
    result := WSANO_RECOVERY;
  end;
end;


procedure populateprocvars;
var
  libraryhandle : hmodule;
  i : integer;
  dllname : ansistring;

begin
  if assigned(getaddrinfo) then exit; //procvars already populated
  for i := 0 to 1 do begin
    if i=0 then dllname := 'Ws2_32.dll' else dllname := 'Wship6.dll';
    libraryhandle := LoadLibraryA(pansichar(dllname));
    getaddrinfo := getprocaddress(libraryhandle,'getaddrinfo');
    freeaddrinfo := getprocaddress(libraryhandle,'freeaddrinfo');
    getnameinfo := getprocaddress(libraryhandle,'getnameinfo');
    if assigned(getaddrinfo) and assigned(freeaddrinfo) and assigned(getnameinfo) then begin
      //writeln('found getaddrinfo and freeaddrinfo in'+dllname);
      exit; //success
    end;

  end;
  //writeln('could not find getaddrinfo and freeaddrinfo, falling back to ipv4 only lookup');
  getaddrinfo := v4onlygetaddrinfo;
  freeaddrinfo := v4onlyfreeaddrinfo;
  getnameinfo := v4onlygetnameinfo;
end;


function winforwardlookuplist(name : thostname;familyhint:integer;var error : integer) : tbiniplist;
var
  hints: taddrinfo;
  res0,res : paddrinfo;
  getaddrinforesult : integer;
  biniptemp:tbinip;
begin
  populateprocvars;

  hints.ai_flags := 0;
  hints.ai_family := familyhint;
  hints.ai_socktype := 0;
  hints.ai_protocol := 0;
  hints.ai_addrlen := 0;
  hints.ai_canonname := nil;
  hints.ai_addr := nil;
  hints.ai_next := nil;
  getaddrinforesult := getaddrinfo(pansichar(name),'1',@hints,@res);
  res0 := res;
  result := biniplist_new;
  if getaddrinforesult = 0 then begin

    while assigned(res) do begin
      if res.ai_family = af_inet then begin
        biniptemp.family := af_inet;
        biniptemp.ip := res.ai_addr.InAddr.addr;
        biniplist_add(result,biniptemp);
      {$ifdef ipv6}
      end else if res.ai_family = af_inet6 then begin
        biniptemp.family := af_inet6;
        biniptemp.ip6 := res.ai_addr.InAddr6.sin6_addr;
        biniplist_add(result,biniptemp);
      {$endif}
      end;
      res := res.ai_next;
    end;
    freeaddrinfo(res0);
    exit;
  end;

  if getaddrinforesult <> 0 then begin
    fillchar(result,0,sizeof(result));
    error := getaddrinforesult;
  end;
end;

function winreverselookup(ip:tbinip;var error : integer):thostname;
var
  sa : tinetsockaddrv;
  getnameinforesult : integer;
begin

  makeinaddrv(ip,'1',sa);
  populateprocvars;
  setlength(result,1025);
  getnameinforesult := getnameinfo(@sa,sizeof(tinetsockaddrv),pansichar(result),length(result),nil,0,0);
  if getnameinforesult <> 0 then begin
    error := getnameinforesult;
    result := '';
    exit;
  end;
  if pos(#0,result) >= 0 then begin
    setlength(result,pos(#0,result)-1);
  end;
end;

var
  hwnddnswin : hwnd;

function MyWindowProc(
    ahWnd   : HWND;
    auMsg   : Integer;
    awParam : WPARAM;
    alParam : LPARAM): Integer; stdcall;
var
  dwas : tdnswinasync;
begin
  if (ahwnd=hwnddnswin) and (aumsg=wm_user) then begin
    Dwas := tdnswinasync(alparam);
    if assigned (dwas.onrequestdone) then dwas.onrequestdone(dwas,awparam);
    dwas.hadevent := true;
    if dwas.freewhendone then dwas.free;
    result := 0; {added returning 0 when handling --beware}
  end else begin
    //not passing unknown messages on to defwindowproc will cause window
    //creation to fail! --plugwash
    Result := DefWindowProc(ahWnd, auMsg, awParam, alParam)
  end;
end;

procedure tdnswinasync.forwardlookup(name:thostname);
begin
  self.name := name;
  freverse := false;
  resume;
end;
procedure tdnswinasync.reverselookup(ip:tbinip);
begin
  iplist := biniplist_new;
  biniplist_add(iplist,ip);
  freverse := true;
  resume;
end;

procedure tdnswinasync.execute;
var
  error : integer;

begin
  error := 0;
  if reverse then begin
    name := winreverselookup(biniplist_get(iplist,0),error);
  end else begin
    iplist := winforwardlookuplist(name,0,error);

  end;
  postmessage(hwnddnswin,wm_user,error,taddrint(self));
end;

destructor tdnswinasync.destroy;
begin
  WaitFor;
  inherited destroy;
end;
procedure tdnswinasync.release;
begin
  if hadevent then destroy else begin
    onrequestdone := nil;
    freewhendone := true;
  end;
end;

constructor tdnswinasync.create;
begin
  inherited create(true);
end;

var
  MyWindowClass : TWndClass = (style         : 0;
                                 lpfnWndProc   : @MyWindowProc;
                                 cbClsExtra    : 0;
                                 cbWndExtra    : 0;
                                 hInstance     : 0;
                                 hIcon         : 0;
                                 hCursor       : 0;
                                 hbrBackground : 0;
                                 lpszMenuName  : nil;
                                 lpszClassName : 'dnswinClass');
procedure init;
begin

    if Windows.RegisterClass(MyWindowClass) = 0 then halt;
  //writeln('about to create lcore handle, hinstance=',hinstance);
  hwnddnswin := CreateWindowEx(WS_EX_TOOLWINDOW,
                               MyWindowClass.lpszClassName,
                               '',        { Window name   }
                               WS_POPUP,  { Window Style  }
                               0, 0,      { X, Y          }
                               0, 0,      { Width, Height }
                               0,         { hWndParent    }
                               0,         { hMenu         }
                               HInstance, { hInstance     }
                               nil);      { CreateParam   }
  //writeln('dnswin hwnd is ',hwnddnswin);
  //writeln('last error is ',GetLastError);
end;


end.
