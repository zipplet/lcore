{ Copyright (C) 2005 Bas Steendijk
  For conditions of distribution and use, see copyright notice in zlib_license.txt
  which is included in the package
  ----------------------------------------------------------------------------- }
unit blinklist;

{$ifdef fpc}
  {$mode delphi}
{$endif}


interface

type
  tlinklist=class(tobject)
    next:tlinklist;
    prev:tlinklist;
    constructor create;
    destructor destroy; override;
  end;

  {linklist with 2 links}
  tlinklist2=class(tlinklist)
    next2:tlinklist2;
    prev2:tlinklist2;
  end;

  {linklist with one pointer}
  tplinklist=class(tlinklist)
    p:pointer
  end;

  tstringlinklist=class(tlinklist)
    s:ansistring;
  end;

  tthing=class(tlinklist)
    name:ansistring;      {name/nick}
    hashname:integer; {hash of name}
  end;

{
adding new block to list (baseptr)
}
procedure linklistadd(var baseptr:tlinklist;newptr:tlinklist);
procedure linklistdel(var baseptr:tlinklist;item:tlinklist);


procedure linklist2add(var baseptr,newptr:tlinklist2);
procedure linklist2del(var baseptr:tlinklist2;item:tlinklist2);

var
  linklistdebug:integer;

implementation

uses sysutils;

procedure linklistadd(var baseptr:tlinklist;newptr:tlinklist);
var
  p:tlinklist;
begin
  if (newptr=baseptr) or assigned(newptr.prev) then raise exception.create('linklist double insertion detected');
  p := baseptr;
  baseptr := newptr;
  baseptr.prev := nil;
  baseptr.next := p;
  if p <> nil then p.prev := baseptr;
end;

procedure linklistdel(var baseptr:tlinklist;item:tlinklist);
begin
  if item = baseptr then baseptr := item.next;
  if item.prev <> nil then item.prev.next := item.next;
  if item.next <> nil then item.next.prev := item.prev;
  item.prev := nil;
  item.next := nil;
end;

procedure linklist2add(var baseptr,newptr:tlinklist2);
var
  p:tlinklist2;
begin
  if (newptr=baseptr) or assigned(newptr.prev2) then raise exception.create('linklist2 double insertion detected');
  p := baseptr;
  baseptr := newptr;
  baseptr.prev2 := nil;
  baseptr.next2 := p;
  if p <> nil then p.prev2 := baseptr;
end;

procedure linklist2del(var baseptr:tlinklist2;item:tlinklist2);
begin
  if item = baseptr then baseptr := item.next2;
  if item.prev2 <> nil then item.prev2.next2 := item.next2;
  if item.next2 <> nil then item.next2.prev2 := item.prev2;
  item.prev2 := nil;
  item.next2 := nil;
end;

constructor tlinklist.create;
begin
  inherited create;
  inc(linklistdebug);
end;

destructor tlinklist.destroy;
begin
  dec(linklistdebug);
  inherited destroy;
end;

end.
