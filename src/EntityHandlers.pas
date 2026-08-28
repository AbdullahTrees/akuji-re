{ EntityHandlers - the per-type entity update handlers.

  Entity_UpdateAll @ 0x004608BC switches on EF_TYPE into one handler per type.
  This unit accumulates them, translated one at a time straight from the
  disassembly - see CLAUDE.md section 3a for why that ordering is the rule
  rather than a preference.

  Each handler carries the address it came from. That address is not decoration:
  tools/coverage.py reads it, and it is the thing to re-decompile against when
  auditing this file.

  Handlers translated so far:

      0x004615A8  Entity_UpdateDying - the shared guard, not a handler
      0x0045A3E0  type 14  animated pickup
      0x0045A43C  type 24  bobbing pickup, sixteen variants
      0x0045A4F0  type 25  static scenery - the smallest handler in the game

  And the dispatcher they hang off:

      0x004608BC  Entity_UpdateAll

  The other ~49 created handlers are named in notes/game_functions.txt but
  their bodies have not been read. A name there asserts only which switch arm
  reaches the function, never what it does. }

unit EntityHandlers;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils, Entities, GameState, SoundTable, PlayerState, Player, Directions;

const
  { --- Four adjacent sprite tables, and a correction ---------------------

    THE TYPE 14 TABLE WAS RECORDED AS SIXTEEN ROWS AND IT IS TWO. The mistake
    is kept in view because the evidence for sixteen was real and simply
    attached to the wrong type: the shipped data does place something with the
    ParamA 'A' argument running 0..15, and it is TYPE 24, whose sprite table is
    a different one starting 32 bytes further on. Type 14's own 122 placements
    use A = 1 and nothing else.

    What settles an extent here is the LAYOUT, not the data. This whole region
    is a run of small const arrays laid end to end, each reached through its own
    pointer global, so a table ends where the next one begins:

      ptr         base        ints  used by
      0x0046CBA0  0x0046BDA0     8  type 14, as 2 rows of 4 frames (stride 16)
      0x0046D0E4  0x0046BDC0    16  type 24, FLAT - one sprite per variant
      0x0046D32C  0x0046BE00     2  type 24 variant 8's two-frame animation
      0x0046CF00  0x0046BE08     3  type 25, flat

    Every one of those four pointers has exactly ONE reader in the whole binary
    - the handler named beside it - so no second type could need more rows. And
    two of the four are flush with their use in both directions: type 24 is
    placed exactly sixteen times with A = 0..15, one of each, and type 25 uses
    A = 0, 1, 2 and nothing else.

    The lesson for the self-test: reading N values out of akuji.exe and finding
    they match proves the VALUES and says nothing about N - especially when N is
    the constant under test, which is what the old check did. The extent is now
    checked against the neighbouring pointer instead. }

  ITEM_VARIANTS = 2;
  ITEM_FRAMES   = 4;
  ITEM_SPRITE_TABLE_ADDR = $0046BDA0;
  ITEM_SPRITE_TABLE_PTR  = $0046CBA0;
  ITEM_SPRITES: array[0..ITEM_VARIANTS - 1, 0..ITEM_FRAMES - 1] of Integer = (
    ( 71,  72,  73,  72),
    (118, 119, 120, 119));

  { --- Type 24 @ 0x0045A43C, a bobbing pickup ---------------------------
    Sixteen variants, one sprite each, in a FLAT table - stride 4, not 16; this
    one has no frames.

    It bobs. Every play frame it adds DirVelY(EF_FACING) to its Y and advances
    EF_FACING one step of 64, so over 64 frames it traces one full period of the
    direction table's vertical component - a sine just over a second long. That
    is a reuse of EF_FACING as a PHASE rather than a heading, and it is the only
    place so far that does it.

    Variant 8 is special twice over: its sprite comes from a two-frame table
    instead, and it plays kodou.wav - Japanese for HEARTBEAT - every 61 frames.
    A thing that bobs, pulses and beats about once a second. }
  ITEM24_VARIANTS   = 16;
  ITEM24_TABLE_ADDR = $0046BDC0;
  ITEM24_TABLE_PTR  = $0046D0E4;
  ITEM24_SPRITES: array[0..ITEM24_VARIANTS - 1] of Integer = (
     74,  75,  76,  77,  78,  79,  80,  81,
    480, 482, 483, 484, 485, 486, 487, 488);

  ITEM24_BEAT_VARIANT = 8;
  ITEM24_BEAT_ADDR    = $0046BE00;
  ITEM24_BEAT_PTR     = $0046D32C;
  ITEM24_BEAT_FRAMES  = 2;
  ITEM24_BEAT_SPRITES: array[0..ITEM24_BEAT_FRAMES - 1] of Integer = (480, 481);
  ITEM24_BEAT_TICKS   = $3C;   { 60; the sound fires when the count EXCEEDS it }

  { --- Type 25 @ 0x0045A4F0 ---------------------------------------------
    Twenty-eight bytes: one table lookup and nothing else. Three variants, one
    sprite each, and the shipped data uses A = 0, 1 and 2 - flush again.

    Type 25 is the most-placed entity in the game, 160 records spread across all
    65 stages, and it does not move, animate or react to anything. It is
    scenery. The compiler left a `GameState - 60` in EAX on the way out, the
    remains of a comparison with an empty body; the caller ignores it. }
  ITEM25_VARIANTS   = 3;
  ITEM25_TABLE_ADDR = $0046BE08;
  ITEM25_TABLE_PTR  = $0046CF00;
  ITEM25_SPRITES: array[0..ITEM25_VARIANTS - 1] of Integer = (82, 104, 105);

  { The one-shot drop applied on the first update, in 1/32 pixel - five pixels.
    Events place things on a tile boundary and this settles them onto it. }
  ITEM_SETTLE_DROP = $A0;
  ITEM_FRAME_TICKS = 4;   { advance when the timer EXCEEDS this, so every 5 }

  { Slots this handler uses. int 5 is the drawn sprite id, the same slot
    Player_Update writes - it is entity-wide, not the player's. int 6 is the
    variant. Both sit outside the two 10-int blocks. }
  EF_ANIM_ID = $05;
  EF_VARIANT = $06;

  { --- Entity_UpdateDying ------------------------------------------------- }
  DEATH_CLASS_SMALL  = 1;
  DEATH_CLASS_BIG    = 2;
  DEATH_CLASS_DEBRIS = 6;
  EMITTER_TYPE       = $20;   { type 32, the invisible spawner }
  SND_BOM03          = $22;   { 34 }


{ 0x004615A8. The death guard, called from THIRTY sites - the top of nearly
  every per-type handler. Returns True when it has taken over, and the caller
  must then skip its normal update.

  It only engages for EF_CLASS 1, 2 and 6. The original writes that test as an
  UNSIGNED (class - 1) compared against 2 and 5, which is the compiler's way of
  saying "class in [1, 2, 6]" - not three separate comparisons.

  The per-class setup was recorded as "spawns an effect entity" before this was
  read. It is more specific than that: classes 1 and 2 both spawn a TYPE 32
  emitter - the invisible spawner whose configuration lives in its block A -
  and seed four of its block-A slots with different numbers, which is how one
  emitter type produces two different death effects.

      class 1   death timer  30, timer  60, emitter A[1..4] = 8, 2, 1, 2
      class 2   death timer 180, timer 240, emitter A[1..4] = 4, 32, 4, 1
      class 6   death timer   0, and Entity_SpawnDebris(e, 1) instead

  Class 6 zeroing its death timer means it is destroyed on the same frame it
  starts dying; 1 and 2 linger for their timer first. Class 2 also plays sound
  34 (bom03) as it goes. }
function EntityUpdateDying(var E: TEntity; AGameState: Integer;
                           World: TEntityWorld): Boolean;

{ 0x0045A3E0. An animated pickup: four frames on a five-frame cycle, and a
  one-shot settle downward the first time it updates.

  It animates ONLY while GameState is GS_PLAY, so items freeze during an event
  script or a pause rather than continuing behind the dialogue box. It does not
  call Entity_UpdateDying and has no touch handling of its own - what happens
  when the player walks into it is decided by EF_TOUCH_KIND from the type table,
  in Entity_PlayerTouch. }
procedure EntityUpdate_Type14(var E: TEntity; AGameState: Integer);

{ 0x0045A43C. See ITEM24_SPRITES above. World is needed only for the heartbeat,
  which only variant 8 has. }
procedure EntityUpdate_Type24(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045A4F0. One table lookup. It takes no game state because it does not read
  any - it is the only handler that runs identically whatever the game is doing. }
procedure EntityUpdate_Type25(var E: TEntity);

{ ==========================================================================
  Entity_UpdateAll @ 0x004608BC - the per-frame loop over the entity pool.
  ========================================================================== }

const
  { Every arm of the switch, by type; 0 means the type has NO arm. Types 0, 18
    and 20 are the only three without one, which is exactly what an earlier
    reading of the switch predicted from the other side.

    This is data, not commentary. The addresses are all distinct and all land
    inside 0x004585A8..0x00460880, and --selftest-entities checks both - a
    transcription slip in 78 hand-copied addresses would otherwise be invisible.

    Only the two named below are translated; HANDLER_ADDR is what says where to
    re-decompile for the rest. }
  HANDLER_ADDR: array[0..ENTITY_TYPE_COUNT - 1] of Cardinal = (
    $00000000, $004585A8, $00459A0C, $00459EB4,   { 0..3 }
    $00459F1C, $00459F6C, $0045A020, $0045A08C,   { 4..7 }
    $0045A0E4, $0045A120, $0045A184, $0045A1C0,   { 8..11 }
    $0045A20C, $0045A24C, $0045A3E0, $0045A95C,   { 12..15 }
    $0045A944, $0045A9D4, $00000000, $0045A9D0,   { 16..19 }
    $00000000, $0045AA10, $0045AA60, $0045AA78,   { 20..23 }
    $0045A43C, $0045A4F0, $0045A50C, $0045A540,   { 24..27 }
    $0045A580, $0045AB64, $0045ABD8, $0045AC94,   { 28..31 }
    $0045A5D4, $0045A698, $0045AF2C, $0045AFA8,   { 32..35 }
    $0045A7BC, $0045A848, $0045B0CC, $0045B260,   { 36..39 }
    $0045B3EC, $0045B62C, $0045B7C4, $0045BBD8,   { 40..43 }
    $0045BC00, $0045BCC4, $0045BD9C, $0045BF58,   { 44..47 }
    $0045C0F4, $0045C250, $0045C430, $0045C608,   { 48..51 }
    $0045C678, $0045CA28, $0045CAD8, $0045CC98,   { 52..55 }
    $0045CE78, $0045D00C, $0045D598, $0045D670,   { 56..59 }
    $0045D7D8, $0045DA28, $0045DC84, $0045DDF4,   { 60..63 }
    $0045E030, $0045E25C, $0045E4EC, $0045E714,   { 64..67 }
    $0045EA40, $0045EB1C, $0045EC4C, $0045ED88,   { 68..71 }
    $0045EFC8, $0045F218, $0045F498, $0045F668,   { 72..75 }
    $0045F744, $0045F85C, $0046023C, $004603B4,   { 76..79 }
    $004607E8    { 80..80 });

  HANDLER_NONE = 0;

  { What --selftest-entities needs to read the switch back out of akuji.exe.
    The compiler did not emit a compare chain: at 0x00460917 it emits
    `JMP dword ptr [EAX*4 + 0x00460924]`, so the binary carries the whole table.
    Entries pointing at HANDLER_NO_ARM_TARGET are the types with no arm - that
    is the same address the range check jumps to for a type above 0x50. }
  CODE_VA_BIAS          = $00400C00;   { VA = file offset + this, CODE section }
  HANDLER_JUMP_TABLE    = $00460924;
  HANDLER_NO_ARM_TARGET = $00460DE1;

  { Type 68 gets an extra Entity_PlayerTouch, outside the slot range that
    normally gets one, whenever its EF_STATE is 3. What type 68 IS has not been
    read yet; that it is singled out here has. An entity of type 68 sitting in a
    minor slot in state 3 therefore gets touch-tested TWICE in one frame, and
    that is the original's behaviour rather than a slip in the transcription. }
  TYPE_TOUCH_IN_STATE_3 = $44;   { 68 }

type
  { Entity_PlayerTouch @ 0x00457880 and Entity_TakeProjectileHits @ 0x00457AB4
    are not translated yet. The call sites stay where the original has them and
    dispatch through these, which are nil until the functions exist.

    Leaving the calls in place rather than omitting them is what keeps the
    omission visible - and it also makes the dispatcher testable on its own: a
    counting stub installed here is how --selftest-entities checks the slot
    boundary and the type-68 special case without needing either function. }
  TEntityCallback = procedure(var E: TEntity; World: TEntityWorld);

var
  EntityPlayerTouch:        TEntityCallback = nil;
  EntityTakeProjectileHits: TEntityCallback = nil;

{ 0x004608BC. Walks slots 0..$FF - not the whole pool, see ENTITY_UPDATE_COUNT -
  and for each live one: carries it along with the scroll unless it is
  screen-space, runs its per-type handler, pushes its state onto its sprite,
  ticks its two timers, rebuilds its collision boxes from the sprite size, and
  finally offers it to the touch and projectile passes before culling it if it
  has left the screen.

  AGameState is var because it is READ FRESH at four points and a handler can
  change it mid-loop. That is not defensive: the last of those four reads exists
  precisely so that a touch which starts an event script abandons the rest of
  the frame's entities. }
procedure EntityUpdateAll(Pool: TEntityPool; World: TEntityWorld;
                          Sprites: TSpriteSink;
                          var P: TPlayerState; var L: TLayerInfo;
                          var Inp: TInputState; var AGameState: Integer);

{ Half * Percent / 100, rounded the way the original's FPU rounds it.

  The original computes this on the x87 stack, where Delphi runs with precision
  control set to 64-bit significands. FPC on x86-64 has no such type - Extended
  is an alias for Double there, 8 bytes, which was checked rather than assumed -
  so NO floating-point expression can reproduce the original on this target.
  Nor is the difference theoretical: over half-extents 0..1024 and percentages
  0..100 the 80-bit and 64-bit answers differ in 118 of 103,525 cases, and three
  of those are reachable from the shipped type table with a sprite no wider than
  the screen.

  So this is done in integers, which is exact on every architecture. The model
  it reproduces is the three roundings the original performs:

      d := RN64(Percent / 100)     the FDIV, one rounding
      m := RN64(Half * d)          the FMULP, a second
      result := RNint(m)           the store, round half to even

  Away from a tie the exact value sits at least 1/100 from a .5 boundary while
  the FPU's relative error is about 1e-19, so neither rounding can move the
  answer and plain integer division gives it. EVERY case where the original
  disagrees with exact arithmetic is a tie - Half * Percent = 50 (mod 100) - and
  the whole tail of this function is about which way the hardware breaks it.

  Checked against an independent exact-rational simulation of the x87 sequence
  over all 103,525 cases: no disagreement. --selftest-entities re-checks the
  part of that which can be stated without the simulation. }
function ScaleByPercent(Half, Percent: Integer): Integer;


implementation


function EntityUpdateDying(var E: TEntity; AGameState: Integer;
                           World: TEntityWorld): Boolean;
var
  Slot: Integer;
begin
  { Outside play the guard reports True without doing anything, so every
    handler stops dead during an event script or the game-over screen. }
  if AGameState <> GS_PLAY then
    Exit(True);

  Result := False;
  if E.Raw[EF_HP] >= 1 then
    Exit;
  if not (E.Raw[EF_CLASS] in [DEATH_CLASS_SMALL, DEATH_CLASS_BIG,
                              DEATH_CLASS_DEBRIS]) then
    Exit;

  if E.Raw[EF_DYING] = 0 then
  begin
    E.Raw[EF_DYING] := 1;
    case E.Raw[EF_CLASS] of
      DEATH_CLASS_SMALL:
        begin
          E.Raw[EF_DEATH_TIMER] := 30;
          E.Raw[EF_TIMER] := 60;
          Slot := World.Spawn(2, EMITTER_TYPE,
                              E.Raw[EF_POS_X] - POSITION_BIAS,
                              E.Raw[EF_POS_Y] - POSITION_BIAS - $20);
          World.SetSpawnField(Slot, EF_BLOCK_A + 1, 8);
          World.SetSpawnField(Slot, EF_BLOCK_A + 2, 2);
          World.SetSpawnField(Slot, EF_BLOCK_A + 3, 1);
          World.SetSpawnField(Slot, EF_BLOCK_A + 4, 2);
        end;
      DEATH_CLASS_BIG:
        begin
          E.Raw[EF_DEATH_TIMER] := 180;
          E.Raw[EF_TIMER] := 240;
          Slot := World.Spawn(2, EMITTER_TYPE,
                              E.Raw[EF_POS_X] - POSITION_BIAS,
                              E.Raw[EF_POS_Y] - POSITION_BIAS - $20);
          World.SetSpawnField(Slot, EF_BLOCK_A + 1, 4);
          World.SetSpawnField(Slot, EF_BLOCK_A + 2, $20);
          World.SetSpawnField(Slot, EF_BLOCK_A + 3, 4);
          World.SetSpawnField(Slot, EF_BLOCK_A + 4, 1);
        end;
      DEATH_CLASS_DEBRIS:
        begin
          E.Raw[EF_DEATH_TIMER] := 0;
          World.SpawnDebris(E, 1);
        end;
    end;
  end;

  if E.Raw[EF_DEATH_TIMER] = 0 then
  begin
    if E.Raw[EF_CLASS] = DEATH_CLASS_BIG then
      World.PlaySound(SND_BOM03);
    World.Destroy(E, True);
  end;

  Result := True;
end;

procedure EntityUpdate_Type24(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Variant, Frame: Integer;
begin
  Variant := E.Raw[EF_VARIANT];
  Frame   := E.Raw[EF_FLAG1C];
  { The original indexes both tables unchecked. Clamping is the one deviation,
    and it cannot change behaviour for any shipped placement - the data's range
    is 0..15 and the table has sixteen entries. }
  if (Variant < 0) or (Variant >= ITEM24_VARIANTS) then
    Variant := 0;
  if (Frame < 0) or (Frame >= ITEM24_BEAT_FRAMES) then
    Frame := 0;

  if E.Raw[EF_VARIANT] <> ITEM24_BEAT_VARIANT then
    E.Raw[EF_ANIM_ID] := ITEM24_SPRITES[Variant]
  else
    E.Raw[EF_ANIM_ID] := ITEM24_BEAT_SPRITES[Frame];

  if AGameState <> GS_PLAY then
    Exit;

  { The bob. EF_FACING is a phase here, not a heading: one step of 64 per frame
    through the direction table's Y column is one full sine period. }
  Inc(E.Raw[EF_POS_Y], DirVelY(WrapDir(E.Raw[EF_FACING])));
  { `mod` and not `and`: the original writes AND 0x8000003F with the usual sign
    fixup, which is a SIGNED mod 64. The two agree for every value this field
    actually holds, but the faithful one costs nothing. }
  E.Raw[EF_FACING] := (E.Raw[EF_FACING] + 1) mod DIR_COUNT;

  if E.Raw[EF_VARIANT] <> ITEM24_BEAT_VARIANT then
    Exit;

  { The frame counter is compared against ZERO, so it resets on the very frame
    it is incremented and the two frames alternate every frame. The counter is
    vestigial rather than a speed control - that is what the original does, and
    it is why this reads as a flicker rather than an animation. }
  Inc(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] > 0 then
  begin
    E.Raw[EF_BLOCK_B] := 0;
    E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod ITEM24_BEAT_FRAMES;
  end;

  Inc(E.Raw[EF_BLOCK_B + 1]);
  if E.Raw[EF_BLOCK_B + 1] > ITEM24_BEAT_TICKS then
  begin
    E.Raw[EF_BLOCK_B + 1] := 0;
    World.PlaySound(SND_KODOU);
  end;
end;

procedure EntityUpdate_Type25(var E: TEntity);
var
  Variant: Integer;
begin
  Variant := E.Raw[EF_VARIANT];
  if (Variant < 0) or (Variant >= ITEM25_VARIANTS) then
    Variant := 0;
  E.Raw[EF_ANIM_ID] := ITEM25_SPRITES[Variant];
end;

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


{ The original compares the LOW BYTE of +0x08 against 1, not the int against 0.
  Only 0 and 1 are ever stored there, so the two agree - but the loop is written
  the original's way because the difference is free to keep. }
function IsAlive(const E: TEntity): Boolean;
begin
  Result := (E.Raw[EF_ALIVE] and $FF) = 1;
end;

function ScaleByPercent(Half, Percent: Integer): Integer;
var
  Sign, K, S, I, M, G, T, EV, X: Integer;
  N, Q, R, R200, V2, Lhs, Rhs: Int64;
begin
  Sign := 1;
  if Half < 0 then
  begin
    Sign := -1;
    Half := -Half;
  end;
  if Percent < 0 then
  begin
    Sign := -Sign;
    Percent := -Percent;
  end;
  if (Half = 0) or (Percent = 0) then
    Exit(0);

  N := Int64(Half) * Percent;
  Q := N div 100;
  R := N mod 100;
  if R > 50 then
    Exit(Sign * Integer(Q + 1));
  if R < 50 then
    Exit(Sign * Integer(Q));

  { --- a tie, and the only case where the FPU's own error decides -----------
    S is the shift that normalises Percent/100 to a 64-bit significand: the K
    with 100 <= Percent * 2^K < 200, then S = 63 + K. }
  K := 0;
  if Percent < 100 then
    while (Int64(Percent) shl K) < 100 do Inc(K)
  else
    while (Int64(Percent) shr (-K)) >= 200 do Dec(K);
  S := 63 + K;

  { T = D*100 - Percent*2^S, the rounding error of the divide scaled up. It is
    at most 50 in magnitude, and it is obtainable from Percent*2^S mod 200
    alone - which is why none of this needs a 128-bit product. The mod 200
    rather than mod 100 is what carries the parity needed for a tie inside the
    tie. }
  M := 1;
  for I := 1 to S do
    M := (M * 2) mod 200;
  R200 := (Int64(Percent) * M) mod 200;
  G := Integer(R200 mod 100);
  if G < 50 then
    T := -G
  else if G > 50 then
    T := 100 - G
  else if R200 >= 100 then
    T := 50
  else
    T := -50;

  if T <> 0 then
  begin
    { Compare |Half * T| / (100 * 2^S) against half an ulp of V = Q + 1/2,
      which is 2^(EV - 64). Both sides scale to integers well inside Int64. }
    V2 := 2 * Q + 1;
    EV := -1;
    while (Int64(1) shl (EV + 2)) <= V2 do
      Inc(EV);
    X := S + EV - 64;
    Lhs := Abs(Int64(Half) * T);
    if X >= 0 then
      Rhs := Int64(100) shl X
    else
    begin
      Lhs := Lhs shl (-X);
      Rhs := 100;
    end;
    { Lhs = Rhs - the product landing exactly half an ulp off the tie - happens
      five times in the domain the self-test sweeps, and falls through to the
      round-half-even below because RN64 breaks ITS tie toward the even
      significand, which V always has. Writing >= here instead changes no answer
      anywhere in that domain, so the mutation suite cannot tell the two apart;
      the > is right by derivation, not by test, and that is worth saying rather
      than leaving it to look covered. }
    if Lhs > Rhs then
    begin
      { The product landed off the tie, and the sign of the error decides. }
      if T > 0 then
        Exit(Sign * Integer(Q + 1))
      else
        Exit(Sign * Integer(Q));
    end;
  end;

  { The second rounding pulled the product back onto the tie exactly, so the
    final store rounds half to even. }
  if Q mod 2 = 0 then
    Result := Sign * Integer(Q)
  else
    Result := Sign * Integer(Q + 1);
end;

procedure EntityUpdateAll(Pool: TEntityPool; World: TEntityWorld;
                          Sprites: TSpriteSink;
                          var P: TPlayerState; var L: TLayerInfo;
                          var Inp: TInputState; var AGameState: Integer);
var
  Slot, Handle, ScreenX, ScreenY, Depth, HalfW, HalfH: Integer;
  E: PEntity;
begin
  EntitiesDrawn := 0;
  EntitiesLive  := 0;

  for Slot := 0 to ENTITY_UPDATE_COUNT - 1 do
  begin
    E := Pool.Entity(Slot);
    if not IsAlive(E^) then
      Continue;
    Inc(EntitiesLive);

    { Carried along by the scroll unless the type is screen-space. This is why
      a HUD element placed as an entity stays put while the map moves under it. }
    if E^.Raw[EF_SCREEN_SPACE] = 0 then
    begin
      Inc(E^.Raw[EF_POS_X], L.DeltaX);
      Inc(E^.Raw[EF_POS_Y], L.DeltaY);
    end;

    case E^.Raw[EF_TYPE] of
      1:  PlayerUpdate(E^, P, L, Inp, World, AGameState);
      14: EntityUpdate_Type14(E^, AGameState);
      24: EntityUpdate_Type24(E^, AGameState, World);
      25: EntityUpdate_Type25(E^);
      { the other 74 arms are in HANDLER_ADDR, untranslated }
    end;

    { --- push the entity onto its sprite ---------------------------------
      Skipped entirely for a type with no sprite, and re-tests aliveness
      because the handler above may have destroyed the entity. }
    Handle := E^.Raw[EF_SPRITE];
    if (Handle <> SPRITE_NONE) and IsAlive(E^) then
    begin
      Inc(EntitiesDrawn);

      { The death timer doubles as the damage flicker: while it is ODD the
        sprite is hidden, so an entity blinks for as long as it is counting
        down. On even frames the sprite takes EF_BYTE94 verbatim - a byte copy,
        so it is that field and not a normalised boolean that decides
        visibility. }
      if E^.Raw[EF_DEATH_TIMER] mod 2 = 0 then
        Sprites.SetVisible(Handle, (E^.Raw[EF_BYTE94] and $FF) <> 0)
      else
        Sprites.SetVisible(Handle, False);

      Sprites.SetAnim(Handle, E^.Raw[EF_ANIM_ID]);

      { Extents refresh only while visible, so a hidden entity keeps the size it
        had when it was last drawn - and keeps colliding at that size. }
      if Sprites.GetVisible(Handle) then
      begin
        E^.Raw[EF_EXTENT_X] := Sprites.Width(Handle);
        E^.Raw[EF_EXTENT_Y] := Sprites.Height(Handle);
      end;

      { The sprite is placed by its top-left, the entity by its CENTRE: half the
        sprite comes off each axis. That is what fixes an entity position as a
        centre point rather than a corner. }
      ScreenX := OriginPixel(E^.Raw[EF_POS_X]) - POSITION_BIAS_PIXELS
                 - HalfExtent(E^.Raw[EF_EXTENT_X]);
      ScreenY := OriginPixel(E^.Raw[EF_POS_Y]) - POSITION_BIAS_PIXELS
                 - HalfExtent(E^.Raw[EF_EXTENT_Y]);
      Sprites.SetPos(Handle, ScreenX, ScreenY);

      Depth := E^.Raw[EF_DEPTH];
      if Depth = DEPTH_BY_SCREEN_Y then
      begin
        Depth := ScreenY;
        if Depth < 1 then Depth := 1;
        if Depth > SCREEN_H then Depth := SCREEN_H;
      end;
      Sprites.SetDepth(Handle, Depth);
    end;

    { --- the two timers -------------------------------------------------
      Frozen during the pause menu and during state 140, which is what makes a
      paused invulnerability or a paused death animation hold. }
    if (AGameState <> GS_PAUSE) and (AGameState <> GS_STATE_140) then
    begin
      if E^.Raw[EF_TIMER] <> 0 then
        Dec(E^.Raw[EF_TIMER]);
      if E^.Raw[EF_DEATH_TIMER] <> 0 then
        Dec(E^.Raw[EF_DEATH_TIMER]);
    end;

    if AGameState <> GS_PLAY then
      Continue;

    { --- collision boxes, rebuilt from the sprite size ------------------- }
    HalfW := HalfExtent(E^.Raw[EF_EXTENT_X]);
    HalfH := HalfExtent(E^.Raw[EF_EXTENT_Y]);
    E^.Raw[EF_BOX_OFS_X]      := ScaleByPercent(HalfW, E^.Raw[EF_BOX_PCT_X]);
    E^.Raw[EF_BOX_OFS_Y]      := ScaleByPercent(HalfH, E^.Raw[EF_BOX_PCT_Y]);
    E^.Raw[EF_HITBOX_INSET_X] := ScaleByPercent(HalfW, E^.Raw[EF_INSET_PCT_X]);
    E^.Raw[EF_HITBOX_INSET_Y] := ScaleByPercent(HalfH, E^.Raw[EF_INSET_PCT_Y]);

    { Only the minor slots are touch-tested and shot-tested. The player and the
      actors below SLOT_MINOR_FIRST are not, which is the same boundary
      Entity_TakeProjectileHits scans up to from the other side. }
    if (Slot >= SLOT_MINOR_FIRST) and IsAlive(E^) then
    begin
      if Assigned(EntityPlayerTouch) then
        EntityPlayerTouch(E^, World);
      if Assigned(EntityTakeProjectileHits) then
        EntityTakeProjectileHits(E^, World);
    end;

    if (E^.Raw[EF_TYPE] = TYPE_TOUCH_IN_STATE_3) and (E^.Raw[EF_STATE] = 3)
       and IsAlive(E^) then
      if Assigned(EntityPlayerTouch) then
        EntityPlayerTouch(E^, World);

    { A touch can change the game state - start an event script, kill the
      player - and when it does the original ABANDONS the rest of the pool for
      this frame. It is a real early return: the branch target is the function
      epilogue, not the loop tail, and the loop tail is four instructions away.
      Reachable only through the two calls above, since the state was GS_PLAY a
      dozen lines up. }
    if (AGameState <> GS_PLAY) and (AGameState <> GS_STATE_140) then
      Exit;

    if IsAlive(E^) and (E^.Raw[EF_CULL_OFFSCREEN] = 1)
       and IsOffScreen(E^, CULL_MARGIN) then
      World.Destroy(E^, False);
  end;
end;


end.
