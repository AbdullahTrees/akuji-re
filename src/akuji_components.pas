{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit akuji_components;

{$warn 5023 off : no warning about unused units}
interface

uses
  DDDDComponent, DDIDComponent, DDSDComponent, KbgmPlayer, AkujiReg, 
  LazarusPackageIntf;

implementation

procedure Register;
begin
  RegisterUnit('AkujiReg', @AkujiReg.Register);
end;

initialization
  RegisterPackage('akuji_components', @Register);
end.
