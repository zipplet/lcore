{ Copyright (C) 2005 Bas Steendijk and Peter Green
  For conditions of distribution and use, see copyright notice in zlib_license.txt
  which is included in the package
  ----------------------------------------------------------------------------- }

{
unit to get various local system config


- get IP addresses assigned to local interfaces.
both IPv4 and IPv6, or one address family in isolation.
works on both windows and linux.

tested on:

- windows XP
- windows vista
- linux (2.6)
- mac OS X (probably works on freeBSD too)

notes:

- localhost IPs (127.0.0.1, ::1) may be returned, the app must not expect them to be in or not in.
  (typically, they're returned on linux and not on windows)

- normal behavior is to return all v6 IPs, including link local (fe80::).
  an app that doesn't want link local IPs has to filter them out.
  windows XP returns only one, global scope, v6 IP, due to shortcomings.



- get system DNS servers

- get system hostname (if not on windows, use freepascal's "unix")

}

unit lcorelocalips;

interface

uses binipstuff,pgtypes;

{$include lcoreconfig.inc}

function getlocalips:tbiniplist;
function getv4localips:tbiniplist;
{$ifdef ipv6}
function getv6localips:tbiniplist;
{$endif}

function getsystemdnsservers:tbiniplist;

{$ifdef mswindows}
function gethostname:ansistring;
{$endif}

implementation

{$ifdef unix}

uses
  baseunix,sockets,sysutils;


function getlocalips_internal(wantfamily:integer):tbiniplist;
const
  IF_NAMESIZE=16;
  
  {$ifdef linux}SIOCGIFCONF=$8912;{$endif}
  {$ifdef bsd}{$ifdef cpu386}SIOCGIFCONF=$C0086924;{$endif}{$endif}
  
  {amd64: mac OS X: $C00C6924; freeBSD: $c0106924}
type
  tifconf=packed record
    ifc_len:longint;
    ifcu_rec:pointer;
  end;

  tifrec=packed record
    ifr_ifrn:array [0..IF_NAMESIZE-1] of char;
    ifru_addr:TSockAddr;
  end;

var
  s:integer;
  ifc:tifconf;
  ifr,ifr2,ifrmax:^tifrec;
  lastlen,len:integer;
  ip:tbinip;
  ad:^TinetSockAddrV;
begin
  result := biniplist_new;

  {must create a socket for this}
  s := fpsocket(AF_INET,SOCK_DGRAM,0);
  if (s < 0) then raise exception.create('getv4localips unable to create socket');

  fillchar(ifc,sizeof(ifc),0);


  ifr := nil;

  len := 2*sizeof(tifrec);
  lastlen := 0;
  repeat
    reallocmem(ifr,len);
    ifc.ifc_len := len;
    ifc.ifcu_rec := ifr;
    {get IP record list}
    if (fpioctl(s,SIOCGIFCONF,@ifc) < 0) then begin
      raise exception.create('getv4localips ioctl failed');
    end;
    if (lastlen = ifc.ifc_len) then break; 
    lastlen := ifc.ifc_len;
    len := len * 2;
  until false;
  
  ifr2 := ifr;
  ifrmax := pointer(taddrint(ifr) + ifc.ifc_len);
  while (ifr2 < ifrmax) do begin
    lastlen := taddrint(ifrmax) - taddrint(ifr2);
    if (lastlen < sizeof(tifrec)) then break; {not enough left}
    {calculate len}
    ad := @ifr2.ifru_addr;

    {$ifdef bsd}
    len := ad.inaddr.len + IF_NAMESIZE;
    if (len < sizeof(tifrec)) then 
    {$endif}
    len := sizeof(tifrec);

    if (len < sizeof(tifrec)) then break; {not enough left}

    ip := inaddrvtobinip(ad^);
    if (ip.family <> 0) and ((ip.family = wantfamily) or (wantfamily = 0)) then biniplist_add(result,ip);
    inc(taddrint(ifr2),len);
  end;

  freemem(ifr);
  FileClose(s);
end;

{$ifdef ipv6}
function getv6localips:tbiniplist;
var
  t:textfile;
  s,s2:ansistring;
  ip:tbinip;
  a:integer;
begin
  result := biniplist_new;

  assignfile(t,'/proc/net/if_inet6');
  {$i-}reset(t);{$i+}
  if ioresult <> 0 then begin
    {not on linux, try if this OS uses the other way to return v6 addresses}
    result := getlocalips_internal(AF_INET6);
    exit;
  end;
  while not eof(t) do begin
    readln(t,s);
    s2 := '';
    for a := 0 to 7 do begin
      if (s2 <> '') then s2 := s2 + ':';
      s2 := s2 + copy(s,(a shl 2)+1,4);
    end;
    ipstrtobin(s2,ip);
    if ip.family <> 0 then biniplist_add(result,ip);
  end;
  closefile(t);
end;
{$endif}

function getv4localips:tbiniplist;
begin
  result := getlocalips_internal(AF_INET);
end;

function getlocalips:tbiniplist;
begin
  result := getv4localips;
  {$ifdef ipv6}
  biniplist_addlist(result,getv6localips);
  {$endif}
end;

{$else}

uses
  sysutils,windows,winsock,dnswin;

{the following code's purpose is to determine what IP windows would come from, to reach an IP
it can be abused to find if there's any global v6 IPs on a local interface}
const
  SIO_ROUTING_INTERFACE_QUERY = $c8000014;
  function WSAIoctl(s: TSocket; code:integer; const Buf; len: Integer; var output; outlen:integer; var outreturned: Integer; overlapped:pointer; completion: pointer): Integer; stdcall; external 'ws2_32.dll' name 'WSAIoctl';

function getlocalipforip(const ip:tbinip):tbinip;
var
  handle:integer;
  a,b:integer;
  inaddrv,inaddrv2:tinetsockaddrv;
  srcx:winsock.tsockaddr absolute inaddrv2;
begin
  makeinaddrv(ip,'0',inaddrv);
  handle := Socket(inaddrv.inaddr.family,SOCK_DGRAM,IPPROTO_UDP);
  if (handle < 0) then begin
    {this happens on XP without an IPv6 stack
    i can either fail with an exception, or with a "null result". an exception is annoying in the IDE}
    {fillchar(result,sizeof(result),0);
    exit; }
    raise exception.create('getlocalipforip: can''t create socket');
  end;
  if WSAIoctl(handle, SIO_ROUTING_INTERFACE_QUERY, inaddrv, sizeof(inaddrv), inaddrv2, sizeof(inaddrv2), a, nil, nil) <> 0
  then raise exception.create('getlocalipforip failed with error: '+inttostr(wsagetlasterror));
  result := inaddrvtobinip(inaddrv2);
  closesocket(handle);
end;


function getv4localips:tbiniplist;
var
  templist:tbiniplist;
  biniptemp:tbinip;
  a:integer;
begin
  result := biniplist_new;

  templist := getlocalips;
  for a := biniplist_getcount(templist)-1 downto 0 do begin
    biniptemp := biniplist_get(templist,a);
    if biniptemp.family = AF_INET then biniplist_add(result,biniptemp);
  end;
end;

{$ifdef ipv6}
function getv6localips:tbiniplist;
var
  templist:tbiniplist;
  biniptemp:tbinip;
  a:integer;
begin
  result := biniplist_new;

  templist := getlocalips;
  for a := biniplist_getcount(templist)-1 downto 0 do begin
    biniptemp := biniplist_get(templist,a);
    if biniptemp.family = AF_INET6 then biniplist_add(result,biniptemp);
  end;
end;
{$endif}

function getlocalips:tbiniplist;
var
  a:integer;
  ip:tbinip;
  usewindnstemp:boolean;
  error:integer;
begin
  result := winforwardlookuplist('',0,error);

  {$ifdef ipv6}

  {windows XP doesn't add v6 IPs
  if we find no v6 IPs in the list, add one using a hack}
  for a := biniplist_getcount(result)-1 downto 0 do begin
    ip := biniplist_get(result,a);
    if ip.family = AF_INET6 then exit;
  end;

  try
    ip := getlocalipforip(ipstrtobinf('2001:200::'));
    if (ip.family = AF_INET6) then biniplist_add(result,ip);
  except
  end;
  {$endif}

end;

{$endif}





{$ifdef mswindows}
  const
    MAX_HOSTNAME_LEN = 132;
    MAX_DOMAIN_NAME_LEN = 132;
    MAX_SCOPE_ID_LEN = 260    ;
    MAX_ADAPTER_NAME_LENGTH = 260;
    MAX_ADAPTER_ADDRESS_LENGTH = 8;
    MAX_ADAPTER_DESCRIPTION_LENGTH = 132;
    ERROR_BUFFER_OVERFLOW = 111;
    MIB_IF_TYPE_ETHERNET = 6;
    MIB_IF_TYPE_TOKENRING = 9;
    MIB_IF_TYPE_FDDI = 15;
    MIB_IF_TYPE_PPP = 23;
    MIB_IF_TYPE_LOOPBACK = 24;
    MIB_IF_TYPE_SLIP = 28;


  type
    tip_addr_string=packed record
      Next :pointer;
      IpAddress : array[0..15] of ansichar;
      ipmask    : array[0..15] of ansichar;
      context   : dword;
    end;
    pip_addr_string=^tip_addr_string;
    tFIXED_INFO=packed record
       HostName         : array[0..MAX_HOSTNAME_LEN-1] of ansichar;
       DomainName       : array[0..MAX_DOMAIN_NAME_LEN-1] of ansichar;
       currentdnsserver : pip_addr_string;
       dnsserverlist    : tip_addr_string;
       nodetype         : longint;
       ScopeId          : array[0..MAX_SCOPE_ID_LEN + 4] of ansichar;
       enablerouting    : longbool;
       enableproxy      : longbool;
       enabledns        : longbool;
    end;
    pFIXED_INFO=^tFIXED_INFO;

  var
    iphlpapi : thandle;
    getnetworkparams : function(pFixedInfo : PFIXED_INFO;OutBufLen : plongint) : longint;stdcall;

function callGetNetworkParams:pFIXED_INFO;
var
    fixed_info : pfixed_info;
    fixed_info_len : longint;
begin
  result := nil;
  if iphlpapi=0 then iphlpapi := loadlibrary('iphlpapi.dll');
    if not assigned(getnetworkparams) then @getnetworkparams := getprocaddress(iphlpapi,'GetNetworkParams');
    if not assigned(getnetworkparams) then exit;
    fixed_info_len := 0;
    if GetNetworkParams(nil,@fixed_info_len)<>ERROR_BUFFER_OVERFLOW then exit;
    //fixed_info_len :=sizeof(tfixed_info);
    getmem(fixed_info,fixed_info_len);
    if GetNetworkParams(fixed_info,@fixed_info_len)<>0 then begin
      freemem(fixed_info);
      exit;
    end;
    result := fixed_info;
end;

{$endif}

function getsystemdnsservers:tbiniplist;
var
  {$ifdef mswindows}
    fixed_info : pfixed_info;
    currentdnsserver : pip_addr_string;
  {$else}
    t:textfile;
    s:ansistring;
    a:integer;
  {$endif}
  ip:tbinip;
begin
  //result := '';

  result := biniplist_new;

  {$ifdef mswindows}
    fixed_info := callgetnetworkparams;
    if fixed_info = nil then exit;

    currentdnsserver := @(fixed_info.dnsserverlist);
    while assigned(currentdnsserver) do begin
      ip := ipstrtobinf(currentdnsserver.IpAddress);
      if (ip.family <> 0) then biniplist_add(result,ip);
      currentdnsserver := currentdnsserver.next;
    end;
    freemem(fixed_info);
  {$else}
    filemode := 0;
    assignfile(t,'/etc/resolv.conf');
    {$i-}reset(t);{$i+}
    if ioresult <> 0 then exit;

    while not eof(t) do begin
      readln(t,s);
      if not (copy(s,1,10) = 'nameserver') then continue;
      s := copy(s,11,500);
      while s <> '' do begin
        if (s[1] = #32) or (s[1] = #9) then s := copy(s,2,500) else break;
      end;
      a := pos(' ',s);
      if a <> 0 then s := copy(s,1,a-1);
      a := pos(#9,s);
      if a <> 0 then s := copy(s,1,a-1);

      ip := ipstrtobinf(s);
      if (ip.family <> 0) then biniplist_add(result,ip);
    end;
    closefile(t);
  {$endif}
end;

{$ifdef mswindows}
function gethostname:ansistring;
var
    fixed_info : pfixed_info;
begin
  result := '';
    fixed_info := callgetnetworkparams;
    if fixed_info = nil then exit;

    result := fixed_info.hostname;
    if fixed_info.domainname <> '' then result := result + '.'+fixed_info.domainname;

    freemem(fixed_info);
end;
{$endif}

end.
