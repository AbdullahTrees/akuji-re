{ Checks binary record sizes and field offsets with ordinary comparisons,
  because assertions are compiled out without -Sa and this project does not
  pass it. tools/layout_lock.py requires every annotated field to have a
  corresponding check here. }

unit LayoutTests;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, TypInfo,
  QdaArchive, SoundTable, WaveFile, AudioMixer, AudioOut, MidiFile, KbgmPlayer,
  Directions, Entities, EventScripts, EventCommands, PlayerState, GameState,
  Stages, Camera, TileMaps, Player, EntityHandlers, EventRunner, GameSession,
  SpritePool, Sprites, Dialogue, BgAnime, UnitInit, Title, Ending, Opening,
  GameFont, DDDDComponent, Surfaces;

function SelfTestLayouts(Log: TStrings): Integer;

implementation

{ --selftest-layouts checks binary record sizes and field offsets with ordinary
  comparisons because assertions may be disabled. Sizes come from external
  strides or I/O lengths; tools/layout_lock.py requires every annotated field
  to have a corresponding offset check. }
function SelfTestLayouts(Log: TStrings): Integer;
var
  Bad: Integer;
  P: TPlayerState;
  I: TInputState;
  G: TGameSettings;
  E: TEntity;

  procedure Size(const Rec: string; Got, Want: Integer; const Pin: string);
  begin
    if Got <> Want then
    begin
      Log.Add(Format('FAILED: SizeOf(%s) is %d, want %d - %s',
                     [Rec, Got, Want, Pin]));
      Inc(Bad);
    end;
  end;

  procedure Off(const What: string; Got, Want: PtrUInt);
  begin
    if Got <> Want then
    begin
      Log.Add(Format('FAILED: %s sits at +0x%x, want +0x%x - a field moved '
        + 'inside the record and every later one moved with it',
        [What, Int64(Got), Int64(Want)]));
      Inc(Bad);
    end;
  end;

begin
  Bad := 0;
  Log.Add('');
  Log.Add('=== binary layouts ===');

  Size('TPlayerState', SizeOf(TPlayerState), PLAYER_STATE_SIZE,
       'save.dat is read and written as exactly this many bytes');
  Size('TEntity', SizeOf(TEntity), ENTITY_BYTES,
       'the original indexes the pool as base + index * 0x104');
  Size('TEntityType', SizeOf(TEntityType), $48,
       'the type table steps 0x48 bytes per entry');
  Size('TGameSettings', SizeOf(TGameSettings), $38,
       'data/system.dat is a raw image of this record');

  if Length(E.Raw) * SizeOf(Integer) <> ENTITY_BYTES then
  begin
    Log.Add(Format('FAILED: TEntity.Raw holds %d ints = %d bytes, want %d',
      [Length(E.Raw), Length(E.Raw) * SizeOf(Integer), ENTITY_BYTES]));
    Inc(Bad);
  end;

  { TPlayerState }
  Off('TPlayerState.Head', PtrUInt(@P.Head) - PtrUInt(@P), $0);
  Off('TPlayerState.Progress', PtrUInt(@P.Progress) - PtrUInt(@P), $A);
  Off('TPlayerState.Pad119F', PtrUInt(@P.Pad119F) - PtrUInt(@P), $119F);
  Off('TPlayerState.SavedStage', PtrUInt(@P.SavedStage) - PtrUInt(@P), $11A0);
  Off('TPlayerState.SpawnX', PtrUInt(@P.SpawnX) - PtrUInt(@P), $11A4);
  Off('TPlayerState.SpawnY', PtrUInt(@P.SpawnY) - PtrUInt(@P), $11A8);
  Off('TPlayerState.ScrollX', PtrUInt(@P.ScrollX) - PtrUInt(@P), $11AC);
  Off('TPlayerState.ScrollY', PtrUInt(@P.ScrollY) - PtrUInt(@P), $11B0);
  Off('TPlayerState.Lives', PtrUInt(@P.Lives) - PtrUInt(@P), $11B4);
  Off('TPlayerState.MaxLives', PtrUInt(@P.MaxLives) - PtrUInt(@P), $11B8);
  Off('TPlayerState.ElapsedSec', PtrUInt(@P.ElapsedSec) - PtrUInt(@P), $11BC);
  Off('TPlayerState.Field11C0', PtrUInt(@P.Field11C0) - PtrUInt(@P), $11C0);
  Off('TPlayerState.Counter', PtrUInt(@P.Counter) - PtrUInt(@P), $11C4);
  Off('TPlayerState.EventCounter', PtrUInt(@P.EventCounter) - PtrUInt(@P), $11C8);
  Off('TPlayerState.Weapon', PtrUInt(@P.Weapon) - PtrUInt(@P), $11CC);
  Off('TPlayerState.JumpStrength', PtrUInt(@P.JumpStrength) - PtrUInt(@P), $11D0);
  Off('TPlayerState.MusicTrack', PtrUInt(@P.MusicTrack) - PtrUInt(@P), $11D4);
  Off('TPlayerState.SpawnFacing', PtrUInt(@P.SpawnFacing) - PtrUInt(@P), $11D8);
  Off('TPlayerState.TargetIndex', PtrUInt(@P.TargetIndex) - PtrUInt(@P), $11DC);
  Off('TPlayerState.Difficulty', PtrUInt(@P.Difficulty) - PtrUInt(@P), $11E0);

  { TInputState }
  Off('TInputState.AxisX', PtrUInt(@I.AxisX) - PtrUInt(@I), $0);
  Off('TInputState.AxisY', PtrUInt(@I.AxisY) - PtrUInt(@I), $4);
  Off('TInputState.HeldX', PtrUInt(@I.HeldX) - PtrUInt(@I), $8);
  Off('TInputState.HeldY', PtrUInt(@I.HeldY) - PtrUInt(@I), $C);
  Off('TInputState.Moving', PtrUInt(@I.Moving) - PtrUInt(@I), $10);
  Off('TInputState.AxisYNegative', PtrUInt(@I.AxisYNegative) - PtrUInt(@I), $11);
  Off('TInputState.RepeatTimer', PtrUInt(@I.RepeatTimer) - PtrUInt(@I), $14);
  Off('TInputState.HoldTimer', PtrUInt(@I.HoldTimer) - PtrUInt(@I), $18);
  Off('TInputState.Button', PtrUInt(@I.Button) - PtrUInt(@I), $1C);
  Off('TInputState.ButtonLatch', PtrUInt(@I.ButtonLatch) - PtrUInt(@I), $20);
  Off('TInputState.ButtonRepeat', PtrUInt(@I.ButtonRepeat) - PtrUInt(@I), $24);
  Off('TInputState.AnyPressed', PtrUInt(@I.AnyPressed) - PtrUInt(@I), $34);

  { TGameSettings }
  Off('TGameSettings.CurrentStage', PtrUInt(@G.CurrentStage) - PtrUInt(@G), $0);
  Off('TGameSettings.GameLevel', PtrUInt(@G.GameLevel) - PtrUInt(@G), $4);
  Off('TGameSettings.KeyMap', PtrUInt(@G.KeyMap) - PtrUInt(@G), $8);
  Off('TGameSettings.SoftwareVsyncFlag', PtrUInt(@G.SoftwareVsyncFlag) - PtrUInt(@G), $18);
  Off('TGameSettings.WaitOnFlag', PtrUInt(@G.WaitOnFlag) - PtrUInt(@G), $19);
  Off('TGameSettings.FullScreenFlag', PtrUInt(@G.FullScreenFlag) - PtrUInt(@G), $1A);
  Off('TGameSettings.DebugLogFlag', PtrUInt(@G.DebugLogFlag) - PtrUInt(@G), $1B);
  Off('TGameSettings.ExtraDoor1', PtrUInt(@G.ExtraDoor1) - PtrUInt(@G), $1C);
  Off('TGameSettings.ExtraDoor2', PtrUInt(@G.ExtraDoor2) - PtrUInt(@G), $1D);
  Off('TGameSettings.Unknown1E', PtrUInt(@G.Unknown1E) - PtrUInt(@G), $1E);
  Off('TGameSettings.Volume', PtrUInt(@G.Volume) - PtrUInt(@G), $24);
  Off('TGameSettings.GallerySel', PtrUInt(@G.GallerySel) - PtrUInt(@G), $28);
  Off('TGameSettings.GalleryUnlocked', PtrUInt(@G.GalleryUnlocked) - PtrUInt(@G), $2C);
  Off('TGameSettings.InputDevice', PtrUInt(@G.InputDevice) - PtrUInt(@G), $34);

  Log.Add('46 field offsets and 4 record sizes checked');
  Result := Bad;
  if Bad = 0 then
    Log.Add('OK - every record matches the offsets read out of the binary')
  else
    Log.Add('FAILED');
end;

end.
