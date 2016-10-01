{$ifdef UNIX}
  {$macro on}
  {$ifdef VER1_0}
    {$define tv_sec := sec}
    {$define tv_usec := usec}
    function dup(const original:integer):integer;inline;
    begin
      linux.dup(original,result);
    end;
    {$define gettimeofdaysec := gettimeofday}
    const
      IPPROTO_UDP=17;
      IPPROTO_ICMP=1;
    function ntohs(invalue:word):word;inline;
    var
      invaluebytes : array[0..1] of byte absolute invalue;
      resultbytes : array[0..1] of byte absolute result;
    begin
      {$ifdef endian_little}
	resultbytes[0] := invaluebytes[1];
	resultbytes[1] := invaluebytes[0];
      {$else}
	result := invalue;
      {$endif}
    end; 
    {$define need_v6constants}
  {$else}
    
    {$define sigprocmask := fpsigprocmask}
    {$define sigaction   := fpsigaction}
    {$define fdclose     := fpclose}
    {$define fcntl       := fpfcntl}
    {$define fdwrite     := fpwrite}
    {$define fdread      := fpread}
    {$define fdopen      := fpopen}
    {$define select      := fpselect}
    {$define linuxerror  := fpgeterrno}
    {$define fork        := fpfork}
    {$define getpid      := fpgetpid}
    {$define getenv      := fpgetenv}
    {$define chmod       := fpchmod}
    {$define dup2        := fpdup2}
    {$ifndef ver1_9_2}
      {$define flock     := fpflock}
      {$ifndef ver1_9_4}
        procedure Execl(Todo:string);inline;
	var
	  p : ppchar;
	begin
	  p := unixutil.StringToPPChar(Todo,0);
	  if (p=nil) or (p^=nil) then exit;
	  fpexecv(p^,p);
	end;
	function SendTo(Sock: LongInt; const Buf;BufLen: LongInt;Flags: LongInt;var Addr;AddrLen: LongInt):LongInt;
	begin
	  result := fpsendto(sock,@buf,buflen,flags,@addr,addrlen);
	end;
	function RecvFrom(Sock: LongInt;var Buf;Buflen: LongInt;Flags: LongInt;var Addr;var addrlen: Longint):LongInt;
	begin
	  result := fprecvfrom(sock,@buf,buflen,flags,@addr,@addrlen);
	end;
	{$define socket := fpsocket}
	function Bind(Sock: LongInt;const Addr;AddrLen: LongInt):Boolean;
	begin
	  result := fpbind(sock,@addr,addrlen) = 0;
	end;
	function SetSocketOptions(Sock: LongInt;Level: LongInt;OptName: LongInt;const OptVal;optlen: LongInt):LongInt;
	begin
	  result := fpsetsockopt(sock,level,optname,@optval,optlen);
	end;
	function Connect(Sock: LongInt;const Addr;Addrlen: LongInt):Boolean;
	begin
	  result := fpconnect(sock,@addr,addrlen) >= 0;
	end;
        function listen(Sock: LongInt;MaxConnect: LongInt):Boolean;
        begin
          result := fplisten(sock,maxconnect) = 0;
        end; 
        function GetPeerName(Sock: LongInt; var Addr;var Addrlen: LongInt):LongInt;
        begin
          result := fpgetpeername(sock,@addr,@addrlen);
        end;
        function GetSocketName(Sock: LongInt; var Addr;var Addrlen: LongInt):LongInt;
        begin
          result := fpgetsockname(sock,@addr,@addrlen);
        end;
        function Accept(Sock: LongInt; var Addr; var Addrlen: LongInt):LongInt;
        begin
          result := fpaccept(sock,@addr,@addrlen);
        end;
      {$endif}
    {$endif}
    {$ifdef ver2_0}
      const
        IPPROTO_UDP=17;
        IPPROTO_ICMP=1;
      {$define need_v6constants}
    {$endif}
    {$ifdef ver1_9}
      const
        IPPROTO_UDP=17;
        IPPROTO_ICMP=1;
      function ntohs(invalue:word):word;inline;
      var
        invaluebytes : array[0..1] of byte absolute invalue;
	resultbytes : array[0..1] of byte absolute result;
      begin
        {$ifdef endian_little}
	  resultbytes[0] := invaluebytes[1];
	  resultbytes[1] := invaluebytes[0];
	{$else}
	  result := invalue;
	{$endif}
      end;
      {$define need_v6constants}
    {$endif}
    procedure gettimeofday(var tv:ttimeval);inline;
    begin
      fpgettimeofday(@tv,nil);    
    end;
    function gettimeofdaysec : longint;
    var
      tv:ttimeval;
    begin
      gettimeofday(tv);
      result := tv.tv_sec;
    end;

    //a function is used here rather than a define to prevent issues with tlasio.dup
    function dup(const original:integer):integer;inline;
    begin
      result := fpdup(original);
    end;
    function octal(invalue:longint):longint;
    var
      a : integer;
      i : integer;
    begin
      i := 0;
      result := 0;
      while invalue <> 0 do begin
        a := invalue mod 10;
        result := result + (a shl (i*3));

        invalue := invalue div 10;
        inc(i);
      end;
    end;
    const
      sys_eintr=esyseintr;

  {$endif}
  {$ifdef need_v6constants}
    {$ifdef linux} 
      //the below values are only known correct on linux, I don't support 
      //1.0.x on any other unix platform atm anyway --plugwash
      const 
        IPPROTO_IPV6 = 41;
        IPV6_V6ONLY         = 26;
    {$endif}
  {$endif}
  {$ifdef freebsd}
    //freepascal doesn't seem to define IPV6_V6ONLY on freebsd, the definition
    //here is taken from the include files of a freebsd 8 system
    const
      IPV6_V6ONLY = 27;
  {$endif}

{$endif}

    
