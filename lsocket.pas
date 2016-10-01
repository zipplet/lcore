{lsocket.pas}

{socket code by plugwash}

{ Copyright (C) 2005 Bas Steendijk and Peter Green
  For conditions of distribution and use, see copyright notice in zlib_license.txt
  which is included in the package
  ----------------------------------------------------------------------------- }
{
changes by plugwash (20030728)
* created handlefdtrigger virtual method in tlasio (overridden in tlsocket) and moved a lot of code from messageloop into it
* changed tlasio to tlasio
* split fdhandle into fdhandlein and fdhandleout
* i now use fdsrmaster and fdswmaster instead of rebuilding the lists every loop
* split lsocket.pas into lsocket.pas and lcore.pas


changes by beware (20030903)
* added getxaddr, getxport (local addr, port, as string)
* added getpeername, remote addr+port as binary
* added htons and htonl functions (endian swap, same interface as windows API)

beware (20030905)
* if connect failed (conn refused) set state to connected and call internalclose, to get closed handler (instead of fdclose)
* (lcore) if closing the fd's in internalclose, set fds to -1 because closing an fd makes it invalid

beware (20030927)
* fixed: on connect failed, tried to close fdhandle's which were already set to -1, added check

beware (20031017)
* added getpeeraddr, getpeerport, remote addr+port as string
}


unit lsocket;
{$ifdef fpc}
  {$mode delphi}
{$endif}

{$include lcoreconfig.inc}

interface
  uses
    sysutils,
    {$ifdef mswindows}
      windows,winsock,
    {$else}

      {$ifdef VER1_0}
        linux,
      {$else}
        baseunix,unix,unixutil,
      {$endif}
      sockets,
    {$endif}
    classes,{pgdebugout,}pgtypes,lcore,fd_utils,binipstuff,dnssync;

{$ifdef ipv6}
const
  v4listendefault:boolean=false;
{$endif}


type
  sunB = packed record
    s_b1, s_b2, s_b3, s_b4: byte;
  end;

  SunW = packed record
    s_w1, s_w2: word;
  end;

  TInAddr = packed record
    case integer of
      0: (S_un_b: SunB);
      1: (S_un_w: SunW);
      2: (S_addr: cardinal);
  end;

  type
    TLsocket = class(tlasio)
    public
      //a: string;

      inAddr             : TInetSockAddrV;

      biniplist:tbiniplist;
      trymoreips:boolean;
      currentip:integer;
      connecttimeout:tltimer;

{      inAddrSize:integer;}

      //host               : THostentry      ;

      //mainthread         : boolean         ; //for debugging only
      addr:thostname;
      port:ansistring;
      localaddr:thostname;
      localport:ansistring;
      proto:ansistring;
      udp,dgram:boolean;
      listenqueue:integer;

      onconnecttryip:procedure(sender:tobject; const ip:tbinip) of object;

      {$ifdef secondlistener}
      secondlistener:tlsocket;
      lastsessionfromsecond:boolean;
      procedure secondaccepthandler(sender:tobject;error:word);
      procedure internalclose(error:word);override;
      {$endif}
      function getaddrsize:integer;
      procedure connect; virtual;
      procedure realconnect;
      procedure bindsocket;
      procedure listen;
      function accept : longint;
      function sendto(dest:TInetSockAddrV;destlen:integer;data:pointer;len:integer):integer; virtual;
      function receivefrom(data:pointer;len:integer;var src:TInetSockAddrV;var srclen:integer):integer; virtual;

      procedure handlefdtrigger(readtrigger,writetrigger:boolean); override;
      function send(data:pointer;len:integer):integer;override;
      procedure sendstr(const str : tbufferstring);override;
      function Receive(Buf:Pointer;BufSize:integer):integer; override;
      function getpeername(var addr:tsockaddrin;addrlen:integer):integer; virtual;
      procedure getXaddrbin(var binip:tbinip); virtual;
      procedure getpeeraddrbin(var binip:tbinip); virtual;
      function getXaddr:thostname; virtual;
      function getpeeraddr:thostname; virtual;
      function getXport:ansistring; virtual;
      function getpeerport:ansistring; virtual;
      constructor Create(AOwner: TComponent); override;

      //this one has to be kept public for now because lcorewsaasyncselect calls it
      procedure connectionfailedhandler(error:word);

      {public in tlasio, and can't be private in both places, so should be public here. 
      fixes delphi warning --beware}
      {$ifdef mswindows}
        procedure myfdclose(fd : integer); override;
        function myfdwrite(fd: LongInt;const buf;size: LongInt):LongInt; override;
        function myfdread(fd: LongInt;var buf;size: LongInt):LongInt; override;
      {$endif}

    private
      {$ifdef ipv6}
        isv6socket : boolean; //identifies if the socket is v6, set by bindsocket
      {$endif}
      procedure taskcallconnectionfailedhandler(wparam,lparam : longint);

      procedure connecttimeouthandler(sender:tobject);
      procedure connectsuccesshandler;
    end;
    tsocket=longint; // for compatibility with twsocket

  twsocket=tlsocket; {easy}


const
  TCP_NODELAY=1;
  IPPROTO_TCP=6;

implementation
{$include unixstuff.inc}


function tlsocket.getaddrsize:integer;
begin
  result := inaddrsize(inaddr);
end;

//I used to use the system versions of these from within lsocket (which has
//functions whose name clashes with them) by using sockets.* and but I can't do
//that anymore since in some cases connect is now provided by unixstuff.inc
//hence these wrapper functions --plugwash
{$ifndef mswindows}
  function system_Connect(Sock: LongInt;const Addr;Addrlen: LongInt):Boolean;
  begin
    result := connect(sock,addr,addrlen);
  end;
  function system_SendTo(Sock: LongInt; const Buf;BufLen: LongInt;Flags: LongInt;var Addr;AddrLen: LongInt):LongInt;
  begin
    result := sendto(sock,buf,buflen,flags,addr,addrlen);
  end;
  function system_getpeername(Sock: LongInt;var Addr;var Addrlen: LongInt):LongInt;
  begin
    result := getpeername(sock,addr,addrlen);
  end;
  function system_listen(Sock: LongInt; MaxConnect: LongInt):Boolean;
  begin
    result := listen(sock,maxconnect);
  end;
  function system_Accept(Sock: LongInt;var Addr;var Addrlen: LongInt):LongInt;
  begin
    result := accept(sock,addr,addrlen);
  end;
{$endif}

procedure tlsocket.realconnect;
var
  a,b:integer;
  iptemp:tbinip;
begin
  iptemp := biniplist_get(biniplist,currentip);
  //writeln('trying to connect to ',ipbintostr(biniplist_get(biniplist,currentip)),'#',port);
  if assigned(onconnecttryip) then onconnecttryip(self,iptemp);
  makeinaddrv(iptemp,port,inaddr);
  inc(currentip);
  if (currentip >= biniplist_getcount(biniplist)) then trymoreips := false;

  udp := false;
  if (uppercase(proto) = 'UDP') then begin
    b := IPPROTO_UDP;
    a := SOCK_DGRAM;
    udp := true;
    dgram := true;
  end else if (uppercase(proto) = 'TCP') or (uppercase(proto) = '') then begin
    b := IPPROTO_TCP;
    a := SOCK_STREAM;
    dgram := false;
  end else if (uppercase(proto) = 'ICMP') or (strtointdef(proto,256) < 256) then begin
    b := strtointdef(proto,IPPROTO_ICMP);
    a := SOCK_RAW;
    dgram := true;
  end else begin
    raise ESocketException.create('unrecognised protocol');
  end;

  a := Socket(inaddr.inaddr.family,a,b);
  //writeln(ord(inaddr.inaddr.family));
  if a = -1 then begin
    //unable to create socket, fire an error event (better to use an error event
    //to avoid poor interaction with multilistener stuff.
    //a socket value of -2 is a special value to say there is no socket but
    //we want internalclose to act as if there was
    fdhandlein := -2;
    fdhandleout := -2;
    tltask.create(taskcallconnectionfailedhandler,self,{$ifdef mswindows}wsagetlasterror{$else}socketerror{$endif},0);
    exit;
  end;
  try
    dup(a);
    bindsocket;
    if dgram then begin
      {$ifndef mswindows}
        SetSocketOptions(fdhandleout, SOL_SOCKET, SO_BROADCAST, 'TRUE', Length('TRUE'));
      {$else}
        SetSockOpt(fdhandleout, SOL_SOCKET, SO_BROADCAST, 'TRUE', Length('TRUE'));
      {$endif}
      state := wsconnected;
      if assigned(onsessionconnected) then onsessionconnected(self,0);

      eventcore.rmasterset(fdhandlein,false);
      eventcore.wmasterclr(fdhandleout);
    end else begin
      state :=wsconnecting;
      {$ifdef mswindows}
        //writeln(inaddr.inaddr.port);
        winsock.Connect(fdhandlein,winsock.psockaddr(@inADDR)^,getaddrsize);
      {$else}
        system_Connect(fdhandlein,inADDR,getaddrsize);
      {$endif}
      eventcore.rmasterset(fdhandlein,false);
      eventcore.wmasterset(fdhandleout);
      if trymoreips then connecttimeout.enabled := true;
    end;
    //sendq := '';
  except
    on e: exception do begin
      fdcleanup;
      raise; //reraise the exception
    end;
  end;

end;

procedure tlsocket.connecttimeouthandler(sender:tobject);
begin
  connecttimeout.enabled := false;
  destroying := true; //hack to not cause handler to trigger
  internalclose(0);
  destroying := false;
  realconnect;
end;




procedure tlsocket.connect;
begin
  if state <> wsclosed then close;
  //prevtime := 0;
  if isbiniplist(addr) then biniplist := addr else biniplist := forwardlookuplist(addr,0);
  if biniplist_getcount(biniplist) = 0 then raise exception.create('unable to resolve '+addr);

  //makeinaddrv(addr,port,inaddr);

  currentip := 0;
  if not assigned(connecttimeout) then begin
    connecttimeout := tltimer.create(self);
    connecttimeout.ontimer := connecttimeouthandler;
    connecttimeout.interval := 5000;
    connecttimeout.enabled := false;
  end;
  realconnect;
end;

procedure tlsocket.sendstr(const str : tbufferstring);
begin
  if dgram then begin
    send(@str[1],length(str))
  end else begin
    inherited sendstr(str);
  end;
end;

function tlsocket.send(data:pointer;len:integer):integer;
begin
  if dgram then begin
//    writeln('sending to '+ipbintostr(inaddrvtobinip(inaddr)),' ',htons(inaddr.inaddr.port),' ',len,' bytes');
    result := sendto(inaddr,getaddrsize,data,len);

//    writeln('send result ',result);
//    writeln('errno',errno);
  end else begin
    result := inherited send(data,len);
  end;
end;


function tlsocket.receive(Buf:Pointer;BufSize:integer):integer;
begin
  if dgram then begin
    {$ifdef secondlistener}
    if lastsessionfromsecond then begin
      result := secondlistener.receive(buf,bufsize);
      lastsessionfromsecond := false;
    end else
    {$endif}
      result := myfdread(self.fdhandlein,buf^,bufsize);
  end else begin
    result := inherited receive(buf,bufsize);
  end;
end;

procedure tlsocket.bindsocket;
var
  inAddrtemp:TInetSockAddrV;
  inAddrtempx:{$ifdef mswindows}winsock.TSockaddr{$else}TInetSockAddrV{$endif} absolute inaddrtemp;
  inaddrtempsize:integer;
begin
  try
    if (localaddr <> '') or (localport <> '') then begin
      if localaddr = '' then begin
        {$ifdef ipv6}
        if inaddr.inaddr.family = AF_INET6 then localaddr := '::' else
        {$endif}
        localaddr := '0.0.0.0';
      end;
      //gethostbyname(localaddr,host);
      inaddrtempsize := makeinaddrv(forwardlookup(localaddr,0),localport,inaddrtemp);
      {$ifdef ipv6}
        isv6socket := (inaddrtemp.inaddr.family = AF_INET6);
      {$endif}
      If Bind(fdhandlein,inaddrtempx,inaddrtempsize)<> {$ifdef mswindows}0{$else}true{$endif} Then begin
        state := wsclosed;
        lasterror := {$ifdef mswindows}getlasterror{$else}socketerror{$endif};
        raise ESocketException.create('unable to bind on address '+localaddr+'#'+localport+', error '+inttostr(lasterror));
      end;
      state := wsbound;
    end;
  except
    on e: exception do begin
      fdcleanup;
      raise; //reraise the exception
    end;
  end;
end;

procedure tlsocket.listen;
var
  {$ifndef mswindows}
  yes,no:longint;
  {$endif}
  socktype:integer;
  biniptemp:tbinip;
  origaddr:thostname;
begin
  if state <> wsclosed then close;
  udp := uppercase(proto) = 'UDP';
  if udp then begin
    socktype := SOCK_DGRAM;
    dgram := true;
  end else socktype := SOCK_STREAM;
  origaddr := addr;

  if addr = '' then begin
    {$ifdef ipv6}
    //writeln('ipv6 is defined');
    if not v4listendefault then begin
      //writeln('setting addr to ::');
      addr := '::';
    end else
    {$endif}
    addr := '0.0.0.0';
  end;
  if isbiniplist(addr) then biniptemp := biniplist_get(addr,0) else biniptemp := forwardlookup(addr,10);
  addr := ipbintostr(biniptemp);
  //writeln('after ipbintostr call addr =',addr);
  //writeln('biniptemp.family =',biniptemp.family);
  //writeln('AF_INET6=',AF_INET6);
  //writeln('PF_INET6=',PF_INET6);
  //writeln('AF_INET=',AF_INET);
  //writeln('PF_INET=',PF_INET);
  
  fdhandlein := socket(biniptemp.family,socktype,0);
  {$ifdef ipv6}
  if (addr = '::') and (origaddr = '') and (fdhandlein < 0) then begin
    {writeln('failed to create an IPV6 socket with error ',socketerror,'. trying to create an IPV4 one instead');}
    addr := '0.0.0.0';
    biniptemp := ipstrtobinf(addr);
    fdhandlein := socket(PF_INET,socktype,0);
  end;
  {$endif}

  if fdhandlein = -1 then raise ESocketException.create('unable to create socket'{$ifdef mswindows}+' error='+inttostr(wsagetlasterror){$endif});
  dupnowatch(fdhandlein); // sets up maxs and copies handle to fdhandleout among other things
  //eventcore.setfdreverse(fdhandlein,self); //already taken care of by dup
  state := wsclosed; // then set this back as it was an undesired side effect of dup

  try
    {$ifndef mswindows}
      yes := $01010101;  {Copied this from existing code. Value is empiric,
                    but works. (yes=true<>0) }
      no := 0;

      if SetSocketOptions(fdhandlein, SOL_SOCKET, SO_REUSEADDR,yes,sizeof(yes))=-1 then begin
        raise ESocketException.create('unable to set SO_REUSEADDR socket option');
      end;
      //writeln('addr=',addr);
      //writeln('setting IPV6_V6ONLY option to 0');
      //allow v4 connections on v6 sockets
      if biniptemp.family = af_inet6 then begin
        if SetSocketOptions(fdhandlein, IPPROTO_IPV6,IPV6_V6ONLY,no,sizeof(no))=-1 then begin
          writeln(IPPROTO_IPV6);
          writeln(IPV6_V6ONLY);
          raise ESocketException.create('unable to set IPV6_V6ONLY socket option error='+inttostr(socketerror));
          
        end;
      end;
    {$else}
      SetSockOpt(fdhandlein, SOL_SOCKET, SO_REUSEADDR, 'TRUE', Length('TRUE'));

    {$endif}
    localaddr := addr;
    localport := port;
    bindsocket;

    if not udp then begin
      {!!! allow custom queue length? default 5}
      if listenqueue = 0 then listenqueue := 5;
      If {$ifdef mswindows}winsock.listen{$else}system_listen{$endif}(fdhandlein,listenqueue)<>{$ifdef mswindows}0{$else}true{$endif} Then raise
esocketexception.create('unable to listen');
      state := wsListening;
    end else begin
      {$ifndef mswindows}
        SetSocketOptions(fdhandleout, SOL_SOCKET, SO_BROADCAST, 'TRUE', Length('TRUE'));
      {$else}
        SetSockOpt(fdhandleout, SOL_SOCKET, SO_BROADCAST, 'TRUE', Length('TRUE'));
      {$endif}
      state := wsconnected;
    end;

    {$ifdef secondlistener}
    //listening on ::. try to listen on 0.0.0.0 as well for platforms which don't already do that
    if addr = '::' then begin
      secondlistener := tlsocket.create(nil);
      secondlistener.proto := proto;
      secondlistener.addr := '0.0.0.0';
      secondlistener.port := port;
      if udp then begin
        secondlistener.ondataavailable := secondaccepthandler;
      end else begin
        secondlistener.onsessionAvailable := secondaccepthandler;
      end;
      try
        secondlistener.listen;
      except
        secondlistener.destroy;
        secondlistener := nil;
      end;
    end;
    {$endif}
  finally
    if state = wsclosed then begin
      if fdhandlein >= 0 then begin
        {one *can* get here without fd -beware}
        eventcore.rmasterclr(fdhandlein);
        myfdclose(fdhandlein); // we musnt leak file descriptors
        eventcore.setfdreverse(fdhandlein,nil);
        fdhandlein := -1;
      end;
    end else begin
      eventcore.rmasterset(fdhandlein,not udp);
    end;
    if fdhandleout >= 0 then eventcore.wmasterclr(fdhandleout);
  end;
  //writeln('listened on addr '+addr+':'+port+' '+proto+' using socket number ',fdhandlein);
end;

{$ifdef secondlistener}
procedure tlsocket.internalclose(error:word);
begin
  if assigned(secondlistener) then begin
    secondlistener.destroy;
    secondlistener := nil;
  end;
  inherited internalclose(error);
end;

procedure tlsocket.secondaccepthandler;
begin
  lastsessionfromsecond := true;
  if udp then begin
    ondataavailable(self,error);
  end else begin
    if assigned(onsessionavailable) then onsessionavailable(self,error);
  end;
end;
{$endif}

function tlsocket.accept : longint;
var
  FromAddrSize     : LongInt;        // i don't really know what to do with these at this
  FromAddr         : TInetSockAddrV;  // at this point time will tell :)
  a,acceptlasterror:integer;
begin
  {$ifdef secondlistener}
  if (lastsessionfromsecond) then begin
    lastsessionfromsecond := false;
    result := secondlistener.accept;
    exit;
  end;
  {$endif}

  FromAddrSize := Sizeof(FromAddr);
  {$ifdef mswindows}
    result := winsock.accept(fdhandlein,@fromaddr,@fromaddrsize);
  {$else}
    result := system_accept(fdhandlein,fromaddr,fromaddrsize);
  {$endif}

  if (result = -1) then acceptlasterror := {$ifdef mswindows}getlasterror{$else}socketerror{$endif} else acceptlasterror := 0;

  //now we have accepted one request start monitoring for more again
  eventcore.rmasterset(fdhandlein,true);

  if result = -1 then begin
    raise esocketexception.create('error '+inttostr(acceptlasterror)+' while accepting');
  end;
  if result > absolutemaxs then begin
    myfdclose(result);
    a := result;
{    result := -1;}
    raise esocketexception.create('file descriptor out of range: '+inttostr(a));
  end;
end;


function tlsocket.sendto(dest:TInetSockAddrV;destlen:integer;data:pointer;len:integer):integer;
var
  {$ifdef ipv6}
    realdest : tinetsockaddrv;
    biniptemp : tbinip;
  {$endif}
  destx : {$ifdef mswindows}winsock.pSockAddr{$else}pInetSockAddrV{$endif};

begin
  {$ifdef secondlistener}
    if assigned(secondlistener) then if (dest.inaddr.family = AF_INET) then begin
      result := secondlistener.sendto(dest,destlen,data,len);
      exit;
    end;
  {$endif}
  {$ifdef ipv6}
    if isv6socket then begin
      biniptemp := inaddrvtobinip(dest);
      converttov6(biniptemp);
      destlen := makeinaddrv(biniptemp,inttostr(ntohs(dest.InAddr.port)),realdest);
      destx := {$ifdef mswindows}winsock.pSockAddr{$else}pInetSockAddrV{$endif}(@realdest)
    end else begin
      destx := {$ifdef mswindows}winsock.pSockAddr{$else}pInetSockAddrV{$endif}(@dest)
    end;
  {$else}
    destx := {$ifdef mswindows}winsock.pSockAddr{$else}pInetSockAddrV{$endif}(@dest);
  {$endif}

  result := {$ifdef mswindows}winsock.sendto{$else}system_sendto{$endif}(self.fdhandleout,data^,len,0,destx^,destlen);
end;


function tlsocket.receivefrom(data:pointer;len:integer;var src:TInetSockAddrV;var srclen:integer):integer;
var
  tempsrc:TInetSockAddrV;
  tempsrclen:integer;
  srcx : {$ifdef mswindows}winsock.TSockAddr{$else}TInetSockAddrV{$endif} absolute tempsrc;
  biniptemp:tbinip;
begin
  {$ifdef secondlistener}
  if assigned(secondlistener) then if lastsessionfromsecond then begin
    lastsessionfromsecond := false;
    result := secondlistener.receivefrom(data,len,src,srclen);
    exit;
  end;
  {$endif}
  tempsrclen := sizeof(tempsrc);
  result := recvfrom(self.fdhandlein,data^,len,0,srcx,tempsrclen);

  {$ifdef ipv6}
  biniptemp := inaddrvtobinip(tempsrc);
  if needconverttov4(biniptemp) then begin
    converttov4(biniptemp);
    tempsrclen := makeinaddrv(biniptemp,inttostr(ntohs(tempsrc.InAddr.port)),tempsrc);
  end;
  {$endif}

  move(tempsrc,src,srclen);
  srclen := tempsrclen;
end;

procedure tlsocket.taskcallconnectionfailedhandler(wparam,lparam : longint);
begin
  connectionfailedhandler(wparam);
end;

procedure tlsocket.connectionfailedhandler(error:word);
begin
   if trymoreips then begin
//     writeln('failed with error ',error);
     connecttimeout.enabled := false;
     destroying := true;
     state := wsconnected;
     self.internalclose(0);
     destroying := false;
     realconnect;
   end else begin
     state := wsconnected;
     if assigned(onsessionconnected) then onsessionconnected(self,error);
     self.internalclose(0);
     recvq.del(maxlongint);
   end;
end;

procedure tlsocket.connectsuccesshandler;
begin
   trymoreips := false;
   connecttimeout.enabled := false;
   if assigned(onsessionconnected) then onsessionconnected(self,0);
end;


procedure tlsocket.handlefdtrigger(readtrigger,writetrigger:boolean);
var
  tempbuf:array[0..receivebufsize-1] of byte;
begin
//  writeln('got a fd trigger, readtrigger=',readtrigger,' writetrigger=',writetrigger,' state=',integer(state));
  if (state =wslistening) and readtrigger then begin
{    debugout('listening socket triggered on read');}
    eventcore.rmasterclr(fdhandlein);
    if assigned(onsessionAvailable) then onsessionAvailable(self,0);
  end;
  if dgram and readtrigger then begin
    if assigned(ondataAvailable) then ondataAvailable(self,0);
    {!!!test}
    exit;
  end;
  if (state =wsconnecting) and writetrigger then begin
    // code for dealing with the results of a non-blocking connect is
    // rather complex
    // if just write is triggered it means connect succeeded
    // if both read and write are triggered it can mean 2 things
    // 1: connect ok and data available
    // 2: connect fail
    // to find out which you must read from the socket and look for errors
    // there if we read successfully we drop through into the code for firing
    // the read event
    if not readtrigger then begin
      state := wsconnected;
      connectsuccesshandler;
    end else begin
      numread := myfdread(fdhandlein,tempbuf,sizeof(tempbuf));
      if numread <> -1 then begin
        state := wsconnected;
        connectsuccesshandler;
        //connectread := true;
        recvq.add(@tempbuf,numread);
      end else begin
        connectionfailedhandler({$ifdef mswindows}wsagetlasterror{$else}linuxerror{$endif});
        exit;
      end;
      // if things went well here we are now in the state wsconnected with data sitting in our receive buffer
      // so we drop down into the processing for data available
    end;
    if fdhandlein >= 0 then begin
      if state = wsconnected then begin
        eventcore.rmasterset(fdhandlein,false);
      end else begin
        eventcore.rmasterclr(fdhandlein);
      end;
    end;
    if fdhandleout >= 0 then begin
      if sendq.size = 0 then begin
        //don't clear the bit in fdswmaster if data is in the sendq
        eventcore.wmasterclr(fdhandleout);
      end;
    end;

  end;
  inherited handlefdtrigger(readtrigger,writetrigger);
end;

constructor tlsocket.Create(AOwner: TComponent);
begin
  inherited create(aowner);
  closehandles := true;
  trymoreips := true;
end;



function tlsocket.getpeername(var addr:tsockaddrin;addrlen:integer):integer;
var
  addrx : {$ifdef mswindows}winsock.tsockaddr{$else}tsockaddrin{$endif} absolute addr;
begin
  result := {$ifdef mswindows}winsock.getpeername{$else}system_getpeername{$endif}(self.fdhandlein,addrx,addrlen);
end;

procedure tlsocket.getxaddrbin(var binip:tbinip);
var
  addr:tinetsockaddrv;
  i:integer;
begin
  i := sizeof(addr);
  fillchar(addr,sizeof(addr),0);

  {$ifdef mswindows}
    winsock.getsockname(self.fdhandlein,psockaddr(@addr)^,i);
  {$else}
    getsocketname(self.fdhandlein,addr,i);
  {$endif}
  binip := inaddrvtobinip(addr);
  converttov4(binip);
end;

procedure tlsocket.getpeeraddrbin(var binip:tbinip);
var
  addr:tinetsockaddrv;
  i:integer;
begin
  i := sizeof(addr);
  fillchar(addr,sizeof(addr),0);
  {$ifdef mswindows}
    winsock.getpeername(self.fdhandlein,psockaddr(@addr)^,i);
  {$else}
    system_getpeername(self.fdhandlein,addr,i);
  {$endif}

  binip := inaddrvtobinip(addr);
  converttov4(binip);
end;

function tlsocket.getXaddr:thostname;
var
  biniptemp:tbinip;
begin
  getxaddrbin(biniptemp);
  result := ipbintostr(biniptemp);
  if result = '' then result := 'error';
end;

function tlsocket.getpeeraddr:thostname;
var
  biniptemp:tbinip;
begin
  getpeeraddrbin(biniptemp);
  result := ipbintostr(biniptemp);
  if result = '' then result := 'error';
end;

function tlsocket.getXport:ansistring;
var
  addr:tinetsockaddrv;
  i:integer;
begin
  i := sizeof(addr);
  {$ifdef mswindows}
    winsock.getsockname(self.fdhandlein,psockaddrin(@addr)^,i);

  {$else}
    getsocketname(self.fdhandlein,addr,i);

  {$endif}
  result := inttostr(htons(addr.InAddr.port));
end;

function tlsocket.getpeerport:ansistring;
var
  addr:tinetsockaddrv;
  i:integer;
begin
  i := sizeof(addr);
  {$ifdef mswindows}
    winsock.getpeername(self.fdhandlein,psockaddrin(@addr)^,i);

  {$else}
    system_getpeername(self.fdhandlein,addr,i);

  {$endif}
  result := inttostr(htons(addr.InAddr.port));
end;

{$ifdef mswindows}
  procedure tlsocket.myfdclose(fd : integer);
  begin
    closesocket(fd);
  end;
  function tlsocket.myfdwrite(fd: LongInt;const buf;size: LongInt):LongInt;
  begin
    result := winsock.send(fd,(@buf)^,size,0);
  end;
  function tlsocket.myfdread(fd: LongInt;var buf;size: LongInt):LongInt;
  begin
    result := winsock.recv(fd,buf,size,0);
  end;
{$endif}

end.

