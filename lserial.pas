{$mode delphi}
unit lserial;
interface
uses 
  lcore;
  
type
  tlserial=class(tlasio)
  public 
    device: string;
	baudrate: longint;
    procedure open;
  end;
  
  
implementation
uses
  baseunix,
  unix,
  unixutil,
  termio, // despite the name the fpc termio unit seems to be an interface to termios
  sysutils;
procedure tlserial.open;
var
  fd : longint;
  config : termios;
  baudrateos : longint;
begin
  fd := fpopen(device,O_RDWR or O_NOCTTY or O_NONBLOCK);
  
  if isatty(fd)=0 then begin
    writeln('not a tty');
    halt(1);
  end;

  fillchar(config,sizeof(config),#0);
  config.c_cflag := CLOCAL or CREAD;
  cfmakeraw(config);
  case baudrate of
    50:     baudrateos := B50;
	75:     baudrateos := B75;
	110:    baudrateos := B110;
	134:    baudrateos := B134;
	150:    baudrateos := B150;
	200:    baudrateos := B200;
	300:    baudrateos := B300;
	600:    baudrateos := B600;
	1200:   baudrateos := B1200;
	1800:   baudrateos := B1800;
	2400:   baudrateos := B2400;
	4800:   baudrateos := B4800;
	9600:   baudrateos := B9600;
	19200:  baudrateos := B19200;
	38400:  baudrateos := B38400;
	57600:  baudrateos := B57600;
	115200: baudrateos := B115200;
	230400: baudrateos := B230400; 
	else raise exception.create('unrecognised baudrate');
  end;
  cfsetispeed(config,baudrateos);
  cfsetospeed(config,baudrateos);
  config.c_cc[VMIN]  := 1;
  config.c_cc[VTIME] := 0;
  if   tcsetattr(fd,TCSAFLUSH,config) <0 then begin
    writeln('could not set termios attributes');
    halt(3);
  end;
  dup(fd);
  closehandles := true;
end;
end.
