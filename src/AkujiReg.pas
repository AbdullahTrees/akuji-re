{ AkujiReg - design-time registration for the Akuji component classes.

  The runtime units call RegisterClass in their initialization sections, which
  is what lets the shipping binary stream GmMain.lfm. The Lazarus IDE is a
  separate process and never links those units, so the form designer cannot
  resolve TDDDD / TDDIDEX / TDDSD / TKbgmPlayer without this.

  Install: Package > Open Package File > akuji_components.lpk > Compile > Use >
  Install. The IDE rebuilds itself and restarts.

  Kept separate from the runtime units so design-time code never ends up linked
  into the game. }

unit AkujiReg;

{$MODE DELPHI}{$H+}

interface

uses
  Classes,
  DDDDComponent, DDIDComponent, DDSDComponent, KbgmPlayer;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('Akuji', [TDDDD, TDDIDEX, TDDSD, TKbgmPlayer]);
end;

end.
