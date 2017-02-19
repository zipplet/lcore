{ Copyright (C) 2005 Bas Steendijk and Peter Green
  For conditions of distribution and use, see copyright notice in zlib_license.txt
  which is included in the package
  ----------------------------------------------------------------------------- }
  
{actually a hashtable. it was a tree in earlier versions}

unit bsearchtree;

interface

uses blinklist;

const
  hashtable_size=$4000;

type
  thashitem=class(tlinklist)
    hash:integer;
    s:ansistring;
    p:pointer;
  end;
  thashtable=array[0..hashtable_size-1] of thashitem;
  phashtable=^thashtable;

{adds "item" to the tree for name "s". the name must not exist (no checking done)}
procedure addtree(t:phashtable;s:ansistring;item:pointer);

{removes name "s" from the tree. the name must exist (no checking done)}
procedure deltree(t:phashtable;s:ansistring);

{returns the item pointer for s, or nil if not found}
function findtree(t:phashtable;s:ansistring):pointer;

{clear a hashtable, deallocating all used resources}
procedure cleartree(t:phashtable);

implementation

//FNV-1a hash function
function makehash(s:ansistring):integer;
const
  shifter=6;
var
  a,b:integer;
  h:longword;
begin
  result := 0;
  b := length(s);
  h := 216613626;
  for a := 1 to b do begin
    h := (h xor byte(s[a])) * 16777619;
  end;
  result := h and (hashtable_size-1);
end;

procedure addtree(t:phashtable;s:ansistring;item:pointer);
var
  hash:integer;
  p:thashitem;
begin
  hash := makehash(s);
  p := thashitem.create;
  p.hash := hash;
  p.s := s;
  p.p := item;
  linklistadd(tlinklist(t[hash]),tlinklist(p));
end;

procedure deltree(t:phashtable;s:ansistring);
var
  p,p2:thashitem;
  hash:integer;
begin
  hash := makehash(s);
  p := t[hash];
  p2 := nil;
  while p <> nil do begin
    if p.s = s then begin
      p2 := p;
      break;
    end;
    p := thashitem(p.next);
  end;
  linklistdel(tlinklist(t[hash]),tlinklist(p2));
  p2.destroy;
end;


function findtree(t:phashtable;s:ansistring):pointer;
var
  p:thashitem;
  hash:integer;
begin
  result := nil;
  hash := makehash(s);
  p := t[hash];
  while p <> nil do begin
    if p.s = s then begin
      result := p.p;
      exit;
    end;
    p := thashitem(p.next);
  end;
end;

procedure cleartree(t:phashtable);
var
  hash:integer;
  p,p2:thashitem;
begin
  for hash := 0 to hashtable_size-1 do begin
    p := t[hash];
    while p <> nil do begin
      p2 := thashitem(p.next);
      linklistdel(tlinklist(t[hash]),tlinklist(p));
      p.destroy;
      p := thashitem(p2);
    end;
  end;
end;

end.
