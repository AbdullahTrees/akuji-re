{ EntityHandlers - the per-type entity update handlers.

  Entity_UpdateAll @ 0x004608BC switches on EF_TYPE into one handler per type.
  This unit accumulates them, translated one at a time straight from the
  disassembly - see CLAUDE.md section 3a for why that ordering is the rule
  rather than a preference.

  Each handler carries the address it came from. That address is not decoration:
  tools/coverage.py reads it, and it is the thing to re-decompile against when
  auditing this file.

  Handlers translated so far:

      0x0045A3E0  type 14  animated pickup

  The other ~49 created handlers are named in notes/game_functions.txt but
  their bodies have not been read. A name there asserts only which switch arm
  reaches the function, never what it does. }

unit EntityHandlers;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils, Entities, GameState;

const
  { --- Type 14's sprite table @ 0x0046BDA0 -------------------------------
    Sixteen variants of four frames, indexed [Variant][Frame] with the variant
    coming from the entity's int 6 - which is exactly what ParamA's 'A' letter
    writes when the event places it. So `0024-A-0004` places a type 24 using
    variant 4, and the A argument is an ART SELECTOR, not a quantity.

    That ties three things together that were decoded separately: the ParamA
    grammar, the entity record, and this table. The A argument's observed range
    across the shipped data is 0..15, and the table has exactly 16 rows - flush,
    the same fit that pinned ENTITY_TYPE_COUNT at 81.

    Rows 0..3 are the plain ping-pong shape A-B-C-B; later rows are arbitrary
    four-frame sequences, and several reuse frames from their neighbours. }
  ITEM_VARIANTS = 16;
  ITEM_FRAMES   = 4;
  ITEM_SPRITE_TABLE_ADDR = $0046BDA0;
  ITEM_SPRITES: array[0..ITEM_VARIANTS - 1, 0..ITEM_FRAMES - 1] of Integer = (
    ( 71,  72,  73,  72),
    (118, 119, 120, 119),
    ( 74,  75,  76,  77),
    ( 78,  79,  80,  81),
    (480, 482, 483, 484),
    (485, 486, 487, 488),
    (480, 481,  82, 104),
    (105,  83,  99, 102),
    (103,  84,  85, 279),
    (280, 281, 282,  93),
    ( 94,  95,  96,  97),
    ( 98, 100, 101, 222),
    (223, 224, 225, 226),
    (222,  54,  61,  62),
    ( 59,  60,  63,  87),
    ( 86,  88,  86,  89));

  { The one-shot drop applied on the first update, in 1/32 pixel - five pixels.
    Events place things on a tile boundary and this settles them onto it. }
  ITEM_SETTLE_DROP = $A0;
  ITEM_FRAME_TICKS = 4;   { advance when the timer EXCEEDS this, so every 5 }

  { Slots this handler uses. int 5 is the drawn sprite id, the same slot
    Player_Update writes - it is entity-wide, not the player's. int 6 is the
    variant. Both sit outside the two 10-int blocks. }
  EF_ANIM_ID = $05;
  EF_VARIANT = $06;

{ 0x0045A3E0. An animated pickup: four frames on a five-frame cycle, and a
  one-shot settle downward the first time it updates.

  It animates ONLY while GameState is GS_PLAY, so items freeze during an event
  script or a pause rather than continuing behind the dialogue box. It does not
  call Entity_UpdateDying and has no touch handling of its own - what happens
  when the player walks into it is decided by EF_TOUCH_KIND from the type table,
  in Entity_PlayerTouch. }
procedure EntityUpdate_Type14(var E: TEntity; AGameState: Integer);

implementation

procedure EntityUpdate_Type14(var E: TEntity; AGameState: Integer);
var
  Variant, Frame: Integer;
begin
  Variant := E.Raw[EF_VARIANT];
  Frame := E.Raw[EF_FLAG1C];
  { The original indexes without bounds checks and would read past the table on
    a bad variant. Clamping instead of faulting is the one deviation here, and
    it cannot change behaviour for any shipped placement: the data's range is
    0..15 and the table is 16 rows. }
  if (Variant < 0) or (Variant >= ITEM_VARIANTS) then
    Variant := 0;
  if (Frame < 0) or (Frame >= ITEM_FRAMES) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := ITEM_SPRITES[Variant][Frame];

  if E.Raw[EF_STATE] = 0 then
  begin
    E.Raw[EF_STATE] := 1;
    E.Raw[EF_POS_Y] := E.Raw[EF_POS_Y] + ITEM_SETTLE_DROP;
  end;

  if AGameState <> GS_PLAY then
    Exit;

  Inc(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] > ITEM_FRAME_TICKS then
  begin
    E.Raw[EF_BLOCK_B] := 0;
    E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod ITEM_FRAMES;
  end;
end;

end.
