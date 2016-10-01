{io core originally for linux bworld}

{ Copyright (C) 2005 Bas Steendijk and Peter Green
  For conditions of distribution and use, see copyright notice in zlib_license.txt
  which is included in the package
  ----------------------------------------------------------------------------- }

unit pgtypes;
interface

{$include pgtypes.inc}

  type
    {$ifdef i386}
      taddrint=longint;
    {$else}
      taddrint=sizeint;
    {$endif}
    paddrint=^taddrint;

    { string type for storing hostnames or IP addresses as strings }
    thostname = ansistring;
    { string type for storing data (bytes) }
    tbufferstring = ansistring;
    
    {another name for a string with bytes, not implying it's to be used for a buffer}
    bytestring = tbufferstring;

    {a char that is always one byte}
    bytechar = ansichar;

implementation
end.
