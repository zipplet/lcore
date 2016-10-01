{$ifdef cpu386}
  {$define i386}
  {$define cpux86}
{$endif}

{$ifdef cpuamd64}
  {$define cpux64}
{$endif}
 

{$ifdef i386}
{$define ENDIAN_LITTLE}
{$ifdef fpc}{$asmmode intel}{$endif}
{$endif}

{$ifdef cpux64}
{$define ENDIAN_LITTLE}
{$ifdef fpc}{$asmmode intel}{$endif}
{$endif}

