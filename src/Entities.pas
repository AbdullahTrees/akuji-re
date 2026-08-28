{ Entities - the entity pool, its record layout, and the static type table.

  All of this is recovered from Entity_Spawn @ 0x004610C4, which is the only
  place an entity is created, plus the callers that fill in the fields it
  leaves at zero.

  ## The pool

  One flat array at p_Entities (0x0046CB68 -> 0x0046EB58), stride 0x104 bytes
  = 65 ints. The spawn function picks a free slot by scanning a RANGE chosen by
  its first argument, so the array is partitioned:

      kind 0 -> slot 0 only
      kind 1 -> slots 1 .. 0x20      (32 slots)
      kind 2 -> slots 0x21 .. 0x120  (256 slots)

  289 slots in total. Kind 0 owning exactly one slot is why slot 0 is taken to
  be the player; nothing else read so far names it, so that is an inference,
  not a decode.

  A slot is free when the byte at +0x08 is zero. Spawn returns the slot index,
  or -1 when the range is full - so a full pool silently drops the spawn, which
  is worth remembering when something fails to appear.

  ## Positions are BIASED, not fixed point

  Spawn stores param + $10000 into +0x78 and +0x7C, which looks like 16.16
  fixed point until you read a caller. FUN_004617FC passes

      Entity_Spawn(2, $24, e^[$78] - $10000, e^[$7C] - $10000)

  - it subtracts exactly what spawn adds back. So $10000 is a constant bias on
  the stored value and cancels out completely; the logical coordinate is plain
  integer pixels. The bias keeps the stored field positive for negative
  coordinates, which lets truncating division by a tile size behave the same on
  both sides of the origin.

  ## The type table

  81 entries of 18 ints at 0x0046909C, statically initialised in DATA rather
  than loaded from a file - which is why there is no entity data file in data/.
  The count is not a guess: entry 81 would start at 0x0046A764, and that is
  where the DirectX interface GUIDs begin.

  Column +0x1C is zero in all 81 rows and is never read by the spawn function;
  it is padding. Everything else is copied into the new entity. What the
  columns MEAN is mostly not established - only the ones traced to a use are
  named below, and the rest are deliberately left as raw indices rather than
  given speculative names. }

unit Entities;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, Directions;

const
  ENTITY_INTS   = $41;      { 65 ints = 0x104 bytes, the array stride }
  ENTITY_BYTES  = $104;

  { Slot partitioning, from the three-way branch at the top of Entity_Spawn. }
  EKIND_SINGLE  = 0;        { slot 0 only - the player }
  EKIND_ACTOR   = 1;        { slots 1..0x20 }
  EKIND_MINOR   = 2;        { slots 0x21..0x120 }

  SLOT_SINGLE_FIRST = $00;  SLOT_SINGLE_LAST = $00;
  SLOT_ACTOR_FIRST  = $01;  SLOT_ACTOR_LAST  = $20;
  SLOT_MINOR_FIRST  = $21;  SLOT_MINOR_LAST  = $120;
  ENTITY_COUNT      = SLOT_MINOR_LAST + 1;   { 289 }

  SLOT_NONE = -1;           { Entity_Spawn's failure return }

  { Positions are biased by POSITION_BIAS and held in 1/32 pixel units. The
    bias cancels in any difference of two positions, which is why it looked
    like it could be ignored - but converting to pixels needs it removed, and
    Entity_IsOffScreen @ 0x004580BC shows the exact idiom the game uses:

        p := Raw[EF_POS_X] - POSITION_BIAS;
        if p < 0 then p := Raw[EF_POS_X] - (POSITION_BIAS - 31);
        pixels := p shr 5;

    The second line is round-toward-zero: an arithmetic shift floors, so 31 is
    added back first for negatives. The same idiom appears in
    EventScript_Execute, so it is the house style rather than a one-off.

    Entity_IsOffScreen then compares against 0x140 and 0xF0 - 320 x 240, the
    form size from the DFM. That is what fixes the unit as pixels. }
  POSITION_BIAS  = $10000;
  POSITION_SHIFT = 5;         { 1/32 pixel }
  POSITION_ROUND = $10000 - 31;
  SCREEN_W       = $140;      { 320 }
  SCREEN_H       = $F0;       { 240 }

  { Field positions as INT indices into TEntity.Raw. Named only where the use
    is established; the rest keep their index. }
  EF_SLOT        = $00;   { the slot's own number }
  EF_ALIVE       = $02;   { byte; zero means the slot is free }
  EF_TYPE        = $03;   { index into ENTITY_TYPES }
  EF_SPRITE      = $04;   { sprite-pool handle, -1 when the type has no sprite }
  EF_FLAG1C      = $07;   { set to 0 or 1 by FUN_004617FC }
  EF_BLOCK_A     = $08;   { 10 ints, zeroed on spawn }
  { Block B is a bank of 10 COUNTDOWN TIMERS. Steer (0x00461738) decrements one
    of them and only acts when it reaches zero, then reloads it - which is how
    the original rate-limits per-entity behaviour without a scheduler. }
  EF_BLOCK_B     = $12;   { 10 ints at +0x48, contiguous with A }
  EF_TIMER_COUNT = 10;
  EF_TIMER       = $1C;   { +0x70. One slot with several uses, all timers:
                            Entity_MaybeDropItem seeds it with 30, the death
                            sequence uses it as a countdown, and a hit sets it
                            and EF_DEATH_TIMER to 8 as invulnerability. }
  EF_POS_X       = $1E;   { biased; use PosX }
  EF_POS_Y       = $1F;
  EF_VEL_X       = $20;   { zeroed on spawn, written as -96 by FUN_004617FC }
  EF_VEL_Y       = $21;
  EF_FACING      = $22;   { direction 0..63, see Directions.pas }
  EF_TYPEF_08    = $23;   { <- type table +0x08 }
  EF_HP          = $24;   { type table col 1. On a target this is HIT POINTS;
                            on a projectile the SAME slot is its damage. One
                            field, two roles by role - see the note below. }
  EF_TYPEF_04    = EF_HP; { the old provenance name, kept for the spawn code }
  EF_BYTE94      = $25;   { byte, set to 1 on spawn }
  EF_EVENT_ID    = $2E;   { +0xB8. The event record this entity came from, or
                            -1 when it came from nowhere. Entity_SolidCollideX
                            and ...Y index p_EventTable by it (stride 0x24) to
                            fire push-against triggers, and event sub-ops 8 and
                            16 go the other way, from the event to the entity
                            it spawned. -1 on spawn is what named this. }
  { --- The type table's 18 columns, exactly as Entity_Spawn copies them -----

        col   0        -> int $05   the drawn sprite id
        col   1        -> int $24   EF_HP
        col   2        -> int $23
        col   3 ..  6  -> int $32 .. $35
        col   7        -> NOWHERE. Never copied, and zero in all 81 rows.
        col   8 .. 17  -> int $37 .. $40

    Read straight off Entity_Spawn @ 0x004610C4, so the gap at column 7 is the
    original's own and not a mis-transcription. Note the crossover: column 1
    goes to $24 and column 2 to $23, the other way round from the obvious
    reading. }
  EF_TYPEF_0C    = $32;   { <- type table col 3, the first of the $32..$35 run }
  EF_TYPEF_20    = $37;   { <- type table col 8, the first of the $37..$40 run }

  { --- The bounding box and its tile-grid offsets ---------------------------

    From Entity_TileEdgeDistX / Entity_TileEdgeDistY @ 0x00457150 / 0x00457228,
    which are an exact X/Y pair: every field below appears in one at offset N
    and in the other at N+4, with the X one reading p_LayerInfo+0x00/+0x10 and
    the Y one p_LayerInfo+0x04/+0x14.

    That pairing is the evidence. A misread would not produce two functions
    identical except for a consistent +4 on six independent fields.

    EF_EXTENT_* is halved before use (shr 1), so it is a full width/height and
    the box is centred on the position. }
  EF_EXTENT_X    = $26;   { +0x98 }
  EF_EXTENT_Y    = $27;   { +0x9C }
  EF_BOX_OFS_X   = $28;   { +0xA0, added going one way and subtracted the other }
  EF_BOX_OFS_Y   = $29;   { +0xA4 }
  EF_TILE_OFS_X  = $3F;   { +0xFC }
  EF_TILE_OFS_Y  = $40;   { +0x100 - the LAST int in the record }

  { --- Entity-versus-entity collision, from Entity_SolidCollideX / ...Y
        @ 0x00456B4C / 0x00456E0C -------------------------------------------

    A SECOND box, not the tile one above. Both functions build

        L := PixelX - EF_EXTENT_X div 2 + EF_HITBOX_INSET_X
        R := L + EF_EXTENT_X - 2 * EF_HITBOX_INSET_X

    so the inset shrinks the extent symmetrically on both sides. EF_EXTENT_* is
    shared with the tile box; the OFFSETS are not - $28/$29 belong to the tile
    path and $2A/$2B to this one. Two separate pairs, easily conflated.

    EF_SOLID is what makes an entity block at all, and it is a KIND, not a
    flag. Both functions take a "this is the player" argument, and when it is
    set the X one skips kind 1 and the Y one skips kind 2:

        0   not solid, skipped entirely
        1   blocks the player in Y only - a floor you can walk through sideways
        2   blocks the player in X only - a wall you can pass vertically
        3+  blocks both

    Anything that is not the player is blocked by every kind. }
  EF_HITBOX_INSET_X = $2A;  { +0xA8 }
  EF_HITBOX_INSET_Y = $2B;  { +0xAC }
  EF_SOLID          = $3E;  { +0xF8, the kind above. It comes from TYPE TABLE
                              COLUMN 15, which the mapping above pins exactly,
                              and the shipped table corroborates the reading:
                              76 of 81 types are 0, four are kind 1 (types 17,
                              19, 21, 45 - platforms, passable sideways) and
                              exactly one is kind 2 (type 43 - a wall, passable
                              vertically). NOTHING is 3 or more, so "blocks
                              both" is a case the code supports and this game
                              never uses. Pinned by --selftest-dir. }
  EF_RIDDEN         = $0A;  { +0x28, block A[2]. Entity_SolidCollideY sets it
                              on the SOLID when something lands on top of it. }

  { The three globals the solid collision answers through. It returns only
    "something was hit"; how far to push out comes back here. }
  SOLID_PUSH_X_ADDR   = $00484FAC;
  SOLID_PUSH_Y_ADDR   = $00484FB0;
  SOLID_ON_TOP_ADDR   = $00484FB4;

  { Landing counts as "on top" only if the overlap is under this many pixels,
    which is what stops a deep overlap being read as a landing. }
  SOLID_TOP_TOLERANCE = 8;

  { Entities 1..32 are never scanned as solids: both functions sweep 33..255,
    or slot 0 alone when asked to collide against the player only. }
  SOLID_SCAN_FIRST = $21;
  SOLID_SCAN_LAST  = $FF;

  { --- The death sequence, from Entity_UpdateDying @ 0x004615A8 -------------

    That function is called from THIRTY distinct sites - more than any other in
    the game layer - which is why these fields are worth naming even though
    only part of the state machine is understood.

    It is a guard, run at the top of an entity's update:

        if GameState <> GS_PLAY then Exit(True);
        if (e^.Raw[EF_HP] < 1) and (e^.Raw[EF_CLASS] in [1, 2, 6]) then
        begin
          if e^.Raw[EF_DYING] = 0 then          // latch, runs once
          begin
            e^.Raw[EF_DYING] := 1;
            ... per-class setup, spawning an effect entity ...
          end;
          if e^.Raw[EF_DEATH_TIMER] = 0 then
          begin
            if e^.Raw[EF_CLASS] = 2 then Play(SND_BOM03);
            Entity_Destroy(e, True);
          end;
          Result := True;                        // caller skips normal update
        end; }
  EF_DEATH_TIMER = $1D;   { +0x74, counts down; 0 destroys the entity }
  EF_DYING       = $11;   { +0x44, one-shot latch for the setup above }
  EF_CLASS       = $33;   { +0xCC }

  { EF_CLASS is the entity's broad kind, NOT its type index - EF_TYPE is that.
    Values seen so far, and where:

        1, 2, 6   Entity_UpdateDying   each with its own death effect
        4, 5, 7   Entity_Destroy       4 decrements a counter on its owner,
                                       5 recursively destroys two child slots
                                       at +0x4C and +0x50, 7 is checked before
                                       calling 0x00461874

    Class 2's death plays sound 34, which SoundTable independently gives as
    bom03.wav - an explosion. That is unrelated evidence for the reading. }
  EF_CHILD_A     = $13;   { +0x4C, destroyed with the parent when EF_CLASS = 5 }
  EF_CHILD_B     = $14;   { +0x50 }

  { --- Fields confirmed by Entity_SpawnDebris @ 0x00461874 ------------------

    That function spawns five particles and sets each one's fields directly, so
    it names them by use rather than by inference. It writes +0x80 and +0x84 as
    the velocity pair, +0x78/+0x7C as the position pair, +0x1C and +0x20 as
    per-particle variation - all of which already carried those names here,
    from other evidence. Nothing below is new; it is corroboration, recorded
    because agreement from an unrelated function is what the naming rules ask
    for.

    Its X velocity is DIR_COS[Random(64)] div 2, times Random(3)+1, which is
    also what ties Directions.pas to the entity system for the first time. Y is
    (i + 4) * -8 for particle i, so the five fan upward at fixed speeds - screen
    Y grows downward, so negative is up. }
  EF_DEBRIS_SPEEDS = 5;   { the burst is always five particles }
  EF_DEBRIS_TYPE   = $0D; { the type they are spawned as }

  { --- The type table's 18 columns, from Entity_Spawn @ 0x004610C4 ----------

    Entity_Spawn copies the type's row into the new entity field by field, so
    the destination of every column is now known. This is the mapping; what
    most of them MEAN is still open, but knowing where a column lands is what
    lets a later function name it.

        col  type+   entity int      col  type+   entity int
        ---  -----   ----------      ---  -----   ----------
         0   +0x00   [$05]            9   +0x24   [$38]
         1   +0x04   [$24]           10   +0x28   [$39]
         2   +0x08   [$23]           11   +0x2C   [$3A]
         3   +0x0C   [$32]           12   +0x30   [$3B]
         4   +0x10   [$33]           13   +0x34   [$3C]
         5   +0x14   [$34]           14   +0x38   [$3D]
         6   +0x18   [$35]           15   +0x3C   [$3E]
         7   +0x1C   NOT COPIED      16   +0x40   [$3F]
         8   +0x20   [$37]           17   +0x44   [$40]

    Note columns 1 and 2 cross over - col 1 goes to [$24] and col 2 to [$23].
    That is in the original, not a transcription slip.

    Column 7 is never copied at all, and an earlier survey of the shipped table
    found +0x1C to be zero for all 81 types. Those two facts explain each other:
    it is a dead column, not a field whose use has yet to be found.

    Two of the columns are now decoded outright, both booleans, and both agree
    with the survey's finding that they only ever hold 0 or 1:

      col 5  -> [$34]  Entity_UpdateAll adds the layer scroll to the position
                       only when this is 0, so 1 means SCREEN-SPACE - the entity
                       does not scroll with the map. The survey found it set
                       only for types 0..13, which are the ones spawned by code
                       rather than placed in a stage.
      col 10 -> [$39]  when 1, Entity_UpdateAll destroys the entity once
                       Entity_IsOffScreen(e, 4) is true. So it is CULL WHEN
                       OFF SCREEN.

    Columns 16 and 17 land on EF_TILE_OFS_X/Y above, which is why those two are
    zero throughout the table - they are runtime offsets starting at 0. }
  TYPE_COL_SCREEN_SPACE = 5;    { -> [$34] }
  TYPE_COL_CULL_OFFSCREEN = 10; { -> [$39] }
  TYPE_COL_UNUSED = 7;   { never copied, zero for all 81 types }
  TYPE_COL_SOLID  = 15;  { -> int $3E, EF_SOLID }

  EF_SCREEN_SPACE   = $34;
  EF_CULL_OFFSCREEN = $39;
  CULL_MARGIN       = 4;        { Entity_IsOffScreen's argument in the update loop }

  { --- The update loop, from Entity_UpdateAll @ 0x004608BC ------------------

    One switch on EF_TYPE with 80 arms, types 1..80, each its own handler. That
    is the shape of the whole 0x456000-0x45FFFF block: it is one update
    procedure per entity type.

    Types 0, 18 and 20 have NO arm. Cross-checking against the type table, 18
    and 20 are also two of the three rows whose column 0 is -1, i.e. that need
    no sprite object - so they are inert markers. The third such row, type 32,
    DOES have an arm: it updates but draws nothing. The two facts nearly
    coincide but not exactly, which is worth stating plainly rather than
    rounding off.

    Entities.Alive is a BYTE at +0x08, read as such both here and in
    Entity_Spawn - it is not an integer.

    Slots above SLOT_ACTOR_LAST get two extra calls per frame (0x00457880 and
    0x00457AB4) that the player and the actors do not, which is independent
    confirmation of where that boundary sits. }

  { --- A real asymmetry in the original, reproduced ------------------------

    Entity_Spawn allocates across three ranges: slot 0 for kind 0, 1..$20 for
    kind 1, and $21..$120 for kind 2. So the pool genuinely is ENTITY_COUNT
    slots and SLOT_MINOR_LAST is right.

    But Entity_UpdateAll iterates slots 0..$FF only - it returns after 256
    iterations. Slots $100..$120 can therefore be spawned into and will never
    be updated, drawn or culled.

    That is not a misreading and it is not corrected here. Entity_Spawn's own
    sprite search also stops at 256, so an entity in one of those slots could
    not obtain a sprite either; the 33 extra slots are vestigial. }
  ENTITY_UPDATE_COUNT = $100;   { what Entity_UpdateAll actually walks }

  { --- What the two 10-int blocks are for ----------------------------------

    Entity_Spawn zeroes ints $08..$11 and $12..$1B, ten each. Reading two
    handlers shows what the split is:

      Block A ($08..$11)  mostly PARAMETERS, set when the entity is placed
      Block B ($12..$1B)  RUNTIME COUNTERS, ticked by the handler

    With one correction, recorded because the first reading was too tidy:
    A[0] itself is NOT a parameter. Three separate places use it as per-type
    runtime state - EntityUpdate_Type36_FallingItem as a "has landed" flag,
    Entity_SpawnDebris writing kind+1 into it on each particle, and
    Entity_UpdateAll testing it against 3 for type $44. So the clean split
    holds from A[1] upward, and A[0] is a general per-type state slot.

    EntityUpdate_Type32_Emitter @ 0x0045A5D4 is the clearest case. It is an
    invisible spawner - type 32 is one of the three rows with no sprite - and it
    reads its whole configuration out of block A while keeping its state in
    block B:

      A[1] $09  frames between spawns      B[0] $12  countdown to next spawn
      A[2] $0A  how many to spawn in all   B[1] $13  how many spawned so far
      A[3] $0B  scatter radius, in tiles   B[2] $14  countdown to next sound
      A[4] $0C  frames between sounds

    When B[1] passes A[2] it destroys itself. That is the pattern to expect
    from the other handlers: block A is the stage author's configuration and
    block B is the handler's scratch. }
  EF_BLOCK_LEN = 10;
  EF_STATE     = $08;   { block A[0]: per-type state, not a parameter }

  { --- Gravity, from EntityUpdate_Type36_FallingItem @ 0x0045A7BC -----------

    Type 36 is what Entity_MaybeDropItem drops, and its handler is the whole
    falling-and-landing pattern in one place:

        if Raw[EF_STATE] = 0 then           // still in the air
        begin
          Inc(Raw[EF_VEL_Y], GRAVITY);
          if Raw[EF_VEL_Y] > TERMINAL_VELOCITY then
            Raw[EF_VEL_Y] := TERMINAL_VELOCITY;
        end;
        Tile := Entity_TileCollideY(e, 0, Raw[EF_VEL_Y], 0, False);
        if (Tile >= SolidTileMin) and (Raw[EF_VEL_Y] > 0) then
        begin
          Raw[EF_VEL_Y] := Entity_TileEdgeDistY(e, Raw[EF_VEL_Y]);
          Raw[EF_STATE] := 1;               // landed
        end;
        Inc(Raw[EF_POS_Y], Raw[EF_VEL_Y]);

    That is worth having for its own sake, but it also settles two earlier
    names. Entity_TileCollideY is used exactly as "what tile would I hit moving
    this far", compared against the terrain's solid threshold; and
    Entity_TileEdgeDistY is used exactly as "how far may I actually move", to
    land flush on the tile boundary instead of overlapping it. Both were named
    from their internals alone, before any caller had been read. }
  GRAVITY           = 8;      { added to EF_VEL_Y each frame, in 1/32 pixel }
  TERMINAL_VELOCITY = $200;   { 512, i.e. 16 pixels per frame }

  { --- Touching the player, from Entity_PlayerTouch @ 0x00457880 ------------

    Called once per frame for every slot above SLOT_ACTOR_LAST. It builds the
    PLAYER's hitbox - slot 0, read straight off the array base - and this
    entity's, using the +0xA8/+0xAC inset pair that Entity_BoxesOverlap also
    uses, and tests them for overlap.

    On overlap it switches on EF_TOUCH_KIND, which Entity_Spawn fills from type
    table column 3. That is a DIFFERENT field from EF_CLASS, which comes from
    column 4 - the two sit next to each other at +0xC8 and +0xCC and are easy
    to conflate:

        EF_TOUCH_KIND  $32  +0xC8  type col 3  what touching the player does
        EF_CLASS       $33  +0xCC  type col 4  how the entity dies

    Touch kinds seen: 1 and 7 call 0x00458138 with 1 and 2; 2, 4 and 5 call
    their own handlers; 6 sets EF_BLOCK_A := 2 but only while the player's
    EF_VEL_Y is positive, i.e. while falling onto it. }
  EF_TOUCH_KIND = $32;

  { --- CORRECTION: +0x90 is hit points, not hit-stun -------------------------

    It was first named EF_HITSTUN from Entity_UpdateDying alone, where all that
    is visible is a guard requiring it to be < 1 before the entity may die. That
    reading fits a stun counter just as well as a health one, and the wrong one
    was picked.

    Entity_TakeProjectileHits @ 0x00457AB4 settles it. On a hit it does

        e^.Raw[EF_HP] := e^.Raw[EF_HP] - projectile^.Raw[EF_HP];
        if e^.Raw[EF_HP] < 1 then
          begin  e^.Raw[EF_HP] := 0;  e^.Raw[EF_DYING] := 0  end
        else
          Play(SND_HIT01);

    Subtracting a per-projectile amount and clamping at zero is health. The
    sound it plays when the entity SURVIVES is index 17, which SoundTable gives
    independently as hit01.wav.

    The genuine stun is the +0x70/+0x74 pair, set to 8 on every hit - the same
    two fields the death sequence reuses as its countdown. }

  { --- Being hit, from Entity_TakeProjectileHits @ 0x00457AB4 ---------------

    Runs for every entity above SLOT_ACTOR_LAST and scans slots 1..$20 - the
    actor range - for projectiles overlapping it. That the scan bound is
    exactly SLOT_ACTOR_LAST is more evidence for where that boundary sits.

    EF_VULN_KIND decides what a hit does, and it is a wide switch: kinds 2, 4,
    5, 6, 7 and $5A..$5D each behave differently, several of them gated on the
    projectile's own EF_BLOCK_A, which acts as its power or element. Only the
    common path is translated here. }
  EF_VULN_KIND  = $35;   { +0xD4, from type table column 6 }
  EF_HIT_SOUND  = $38;   { +0xE0, from type column 9; indexes a table at 0x46CC48 }
  HIT_STUN_FRAMES = 8;

  { Two things fall out of where these land.

    EF_TILE_OFS_Y at int 64 is exactly the final slot of the 65-int record - an
    independent check on ENTITY_INTS, since a wrong stride would have put it
    outside.

    And EF_TILE_OFS_X/Y are $3F/$40, i.e. EF_TYPEF_20 + 8 and + 9, so they ALIAS
    the last two slots that Entity_Spawn fills from the type table (columns 8..17
    -> ints $37..$40). Those two columns are type table +0x40 and +0x44, which a
    separate survey found to be ZERO for all 81 types. That is consistent rather
    than contradictory: they are runtime offsets whose initial value is 0, which
    is also why the survey saw a dead column there. Do not treat them as two
    different fields. }   { <- type table +0x20 .. +0x44 land at $37..$40 }

  ENTITY_TYPE_COUNT  = 81;
  ENTITY_TYPE_FIELDS = 18;

type
  { A collision box in screen pixels, in the order the original stores it: four
    consecutive ints passed by pointer to Rect_Overlap. }
  TBox = record L, T, R, B: Integer; end;

  { Kept as a raw int array for the same reason TStageRecord is: the layout is
    known exactly but most field meanings are not, and inventing names for them
    would make guesses look like decodes. }
  TEntity = record
    Raw: array[0..ENTITY_INTS - 1] of Integer;
  end;
  PEntity = ^TEntity;

  TEntityType = record
    Raw: array[0..ENTITY_TYPE_FIELDS - 1] of Integer;
  end;

  TEntityPool = class
  private
    FSlots: array[0..ENTITY_COUNT - 1] of TEntity;
    function GetAlive(Index: Integer): Boolean;
  public
    procedure Clear;

    { Entity_Spawn @ 0x004610C4. X and Y are logical pixels; the bias is
      applied here. Returns the slot index, or SLOT_NONE if the kind's range is
      full - the original drops the spawn in that case and so does this. }
    function Spawn(Kind, TypeId, X, Y: Integer): Integer;
    procedure Kill(Slot: Integer);

    function PosX(Slot: Integer): Integer;
    function PosY(Slot: Integer): Integer;
    procedure SetPos(Slot, X, Y: Integer);
    function Field(Slot, IntIndex: Integer): Integer;
    procedure SetField(Slot, IntIndex, Value: Integer);

    function LiveCount: Integer;

    { Steer @ 0x00461738. Ticks timer TimerSlot; when it runs out, reloads it
      with Reload, turns one step toward the PLAYER, and rewrites the velocity
      from the direction table. Velocity is rewritten on every call, not only
      on the tick, so an entity keeps moving between turns.

      This is what establishes that slot 0 is the player: the original homes on
      p_Entities[0] with no indirection at all, reading +0x78/+0x7C straight
      off the array's base pointer. }
    procedure Steer(Slot, TimerSlot, Reload: Integer);

    property Alive[Index: Integer]: Boolean read GetAlive;
  end;

const
  { Verbatim from 0x0046909C. Columns are, in order:
      +00 +04 +08 +0C +10 +14 +18 +1C +20 +24 +28 +2C +30 +34 +38 +3C +40 +44
    +00 is -1 for the three types that need no sprite object. }
  ENTITY_TYPES: array[0..ENTITY_TYPE_COUNT - 1] of TEntityType = (
    {  0 } (Raw: (    0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    {  1 } (Raw: (    0,     0,     4,     0,     0,     1,     0,     0,     0,     0,     0,    30,    20,    30,    30,     0,     0,     0)),
    {  2 } (Raw: (    0,     0,     5,     0,     4,     0,     0,     0,     0,     0,     1,    60,    60,    60,    60,     0,     0,     0)),
    {  3 } (Raw: (    0,     0,     5,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    {  4 } (Raw: (    0,     0,     3,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    {  5 } (Raw: (    0,     0,     3,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    {  6 } (Raw: (    0,     0,     5,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    {  7 } (Raw: (    0,     0,     5,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    {  8 } (Raw: (    0,     0,     6,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    {  9 } (Raw: (    0,     0,     7,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    { 10 } (Raw: (    0,     0,     6,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    { 11 } (Raw: (    0,     0,     6,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    { 12 } (Raw: (    0,     0,     3,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    { 13 } (Raw: (    0,     0,     8,     0,     0,     1,     0,     0,     0,     0,     1,     0,     0,     0,     0,     0,     0,     0)),
    { 14 } (Raw: (    0,     0,     1,     2,     0,     0,     0,     0,     0,     0,     0,     0,     0,    70,    70,     0,     0,     0)),
    { 15 } (Raw: (    0,     0,     1,     3,     0,     0,     0,     0,     0,     0,     1,     0,     0,    30,    30,     0,     0,     0)),
    { 16 } (Raw: (    0,     0,     1,     3,     0,     0,     0,     0,     0,     0,     1,     0,     0,    30,    30,     0,     0,     0)),
    { 17 } (Raw: (    0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     1,     0,     0,     0,     0,     1,     0,     0)),
    { 18 } (Raw: (   -1,     0,     0,     3,     0,     0,     0,     0,     0,     0,     1,     0,     0,     0,     0,     0,     0,     0)),
    { 19 } (Raw: (    0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     1,     0,     0,     0,     0,     1,     0,     0)),
    { 20 } (Raw: (   -1,     0,     0,     0,     0,     0,     0,     0,     0,     0,     1,     0,     0,     0,     0,     0,     0,     0)),
    { 21 } (Raw: (    0,     0,     2,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,    30,     0,     1,     0,     0)),
    { 22 } (Raw: (    0,     1,     2,     1,     0,     0,     2,     0,     0,     0,     1,     0,     0,    50,    50,     0,     0,     0)),
    { 23 } (Raw: (    0,     1,     1,     0,     5,     0,     2,     0,     0,     1,     1,     0,     0,    50,    30,     0,     0,     0)),
    { 24 } (Raw: (    0,     0,     2,     3,     0,     0,     0,     0,     0,     0,     0,     0,     0,    70,    70,     0,     0,     0)),
    { 25 } (Raw: (    0,     0,     1,     3,     0,     0,     0,     0,     0,     0,     0,     0,     0,    70,    70,     0,     0,     0)),
    { 26 } (Raw: (    0,     0,     6,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    { 27 } (Raw: (    0,     0,     2,     3,     0,     0,     0,     0,     0,     0,     0,     0,     0,    30,    30,     0,     0,     0)),
    { 28 } (Raw: (    0,     0,     2,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    { 29 } (Raw: (    0,     1,     3,     1,     1,     0,     1,     0,     0,     0,     1,     0,     0,    60,    60,     0,     0,     0)),
    { 30 } (Raw: (    0,     2,     3,     1,     1,     0,     1,     0,     0,     0,     0,     0,     0,    60,    60,     0,     0,     0)),
    { 31 } (Raw: (    0,    30,     3,     1,     2,     0,     1,     0,     1,     0,     0,     0,     0,    30,    80,     0,     0,     0)),
    { 32 } (Raw: (   -1,     0,     6,     0,     0,     0,     0,     0,     1,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    { 33 } (Raw: (    0,     0,     6,     0,     0,     0,     0,     0,     1,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    { 34 } (Raw: (    0,     0,     4,     1,     0,     0,     0,     0,     1,     0,     0,     0,     0,    60,    60,     0,     0,     0)),
    { 35 } (Raw: (    0,     0,     4,     1,     0,     0,     0,     0,     1,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    { 36 } (Raw: (    0,     0,     4,     4,     0,     0,     0,     0,     0,     0,     0,    30,    30,    70,    70,     0,     0,     0)),
    { 37 } (Raw: (    0,     0,     2,     5,     0,     0,     0,     0,     0,     0,     0,     0,     0,    70,    70,     0,     0,     0)),
    { 38 } (Raw: (    0,     4,     3,     1,     1,     0,     1,     0,     0,     0,     0,     0,     0,    60,    60,     0,     0,     0)),
    { 39 } (Raw: (    0,     0,     4,     1,     0,     0,     0,     0,     0,     0,     0,    50,    50,    50,    50,     0,     0,     0)),
    { 40 } (Raw: (    0,     1,     3,     6,     1,     0,     0,     0,     0,     0,     1,     0,     0,    60,    60,     0,     0,     0)),
    { 41 } (Raw: (    0,     2,     3,     1,     1,     0,     1,     0,     0,     0,     0,    50,    10,    60,    60,     0,     0,     0)),
    { 42 } (Raw: (    0,    70,     3,     1,     2,     0,     1,     0,     1,     0,     0,    20,    33,    40,    40,     0,     0,     0)),
    { 43 } (Raw: (    0,     4,     3,     0,     6,     0,     0,     0,     1,     0,     1,     0,     0,     0,     0,     2,     0,     0)),
    { 44 } (Raw: (    0,     1,     4,     1,     6,     0,     1,     0,     1,     0,     1,     0,     0,    80,    80,     0,     0,     0)),
    { 45 } (Raw: (    0,     0,     2,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,    30,     0,     1,     0,     0)),
    { 46 } (Raw: (    0,     2,     3,     1,     1,     0,     1,     0,     0,     0,     0,    60,    60,    60,    60,     0,     0,     0)),
    { 47 } (Raw: (    0,     6,     3,     1,     1,     0,     1,     0,     0,     0,     1,     0,     0,    60,    60,     0,     0,     0)),
    { 48 } (Raw: (    0,     1,     2,     1,     1,     0,     1,     0,     1,     0,     1,    40,    40,    40,    40,     0,     0,     0)),
    { 49 } (Raw: (    0,     3,     3,     1,     1,     0,     1,     0,     0,     0,     1,     0,     0,    60,    60,     0,     0,     0)),
    { 50 } (Raw: (    0,     4,     3,     1,     1,     0,     2,     0,     0,     0,     0,     0,     0,    60,    60,     0,     0,     0)),
    { 51 } (Raw: (    0,     1,     3,     1,     1,     0,     0,     0,     0,     0,     0,     0,     0,    60,    60,     0,     0,     0)),
    { 52 } (Raw: (    0,   120,     3,     1,     2,     0,     1,     0,     1,     0,     0,    20,    80,    50,    20,     0,     0,     0)),
    { 53 } (Raw: (    0,     0,     4,     1,     0,     0,     0,     0,     0,     0,     0,    50,    50,    50,    50,     0,     0,     0)),
    { 54 } (Raw: (    0,    80,     3,     1,     2,     0,     1,     0,     1,     0,     0,     0,     0,    60,    40,     0,     0,     0)),
    { 55 } (Raw: (    0,     1,     4,     1,     1,     0,     6,     0,     1,     2,     1,     0,     0,    80,    80,     0,     0,     0)),
    { 56 } (Raw: (    0,   100,     3,     1,     1,     0,     1,     0,     0,     0,     1,     0,     0,    60,    60,     0,     0,     0)),
    { 57 } (Raw: (    0,     1,     3,     1,     1,     0,     0,     0,     0,     0,     1,     0,     0,    60,    60,     0,     0,     0)),
    { 58 } (Raw: (    0,     1,     3,     1,     1,     0,     1,     0,     0,     0,     1,     0,     0,    60,    60,     0,     0,     0)),
    { 59 } (Raw: (    0,     1,     3,     1,     1,     0,     1,     0,     0,     0,     1,     0,     0,    60,    60,     0,     0,     0)),
    { 60 } (Raw: (    0,    13,     3,     1,     1,     0,     1,     0,     0,     0,     0,    40,    40,    60,    60,     0,     0,     0)),
    { 61 } (Raw: (    0,     1,     3,     0,     1,     0,     2,     0,     0,     0,     1,     0,     0,    80,    80,     0,     0,     0)),
    { 62 } (Raw: (    0,     4,     4,     1,     1,     0,     1,     0,     0,     0,     0,    40,    40,    60,    60,     0,     0,     0)),
    { 63 } (Raw: (    0,     4,     4,     1,     1,     0,     1,     0,     0,     0,     0,    40,    40,    60,    60,     0,     0,     0)),
    { 64 } (Raw: (    0,     1,     2,     7,     0,     0,     2,     0,     0,     0,     0,     0,     0,    50,    50,     0,     0,     0)),
    { 65 } (Raw: (    0,     2,     3,     1,     1,     0,     1,     0,     0,     0,     0,     0,     0,    60,    60,     0,     0,     0)),
    { 66 } (Raw: (    0,     1,     3,     7,     0,     0,     2,     0,     0,     0,     0,     0,     0,    50,    50,     0,     0,     0)),
    { 67 } (Raw: (    0,     4,     4,     1,     1,     0,     1,     0,     0,     0,     0,    40,    40,    60,    60,     0,     0,     0)),
    { 68 } (Raw: (    0,     1,     3,     0,     7,     0,     0,     0,     1,     0,     0,    40,    40,    60,    60,     0,     0,     0)),
    { 69 } (Raw: (    0,     1,     2,     0,     0,     0,     5,     0,     0,     3,     0,     0,     0,    50,    50,     0,     0,     0)),
    { 70 } (Raw: (    0,   100,     3,     1,     1,     0,     4,     0,     0,     0,     0,     0,     0,    60,    60,     0,     0,     0)),
    { 71 } (Raw: (    0,     4,     4,     1,     1,     0,     7,     0,     0,     2,     0,    40,    40,    60,    60,     0,     0,     0)),
    { 72 } (Raw: (    0,     1,     3,     1,     1,     0,     0,     0,     1,     0,     1,     0,     0,    60,    60,     0,     0,     0)),
    { 73 } (Raw: (    0,    80,     3,     1,     2,     0,     1,     0,     1,     0,     0,     0,     0,    30,    75,     0,     0,     0)),
    { 74 } (Raw: (    0,     0,     4,     1,     0,     0,     0,     0,     1,     0,     1,     0,     0,    60,    60,     0,     0,     0)),
    { 75 } (Raw: (    0,     0,     4,     1,     0,     0,     0,     0,     1,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    { 76 } (Raw: (    0,     1,     2,     7,     0,     0,     2,     0,     0,     0,     0,     0,     0,    50,    50,     0,     0,     0)),
    { 77 } (Raw: (    0,  1000,     3,     1,     2,     0,     1,     0,     1,     0,     0,     5,     5,    60,    60,     0,     0,     0)),
    { 78 } (Raw: (    0,     4,     2,     1,     1,     0,     2,     0,     1,     0,     0,     0,     0,    60,    60,     0,     0,     0)),
    { 79 } (Raw: (    0,     4,     4,     1,     1,     0,     0,     0,     1,     0,     0,     0,     0,    50,    50,     0,     0,     0)),
    { 80 } (Raw: (    0,     0,     2,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0))
  );

{ Bounds-checked accessor; an out-of-range id yields an all-zero record rather
  than reading past the table, which the original would happily do. }
function EntityType(Id: Integer): TEntityType;

{ Pixel position of an entity, with the bias removed and rounded toward zero
  exactly as the original does. }
function EntityPixelX(const E: TEntity): Integer;
function EntityPixelY(const E: TEntity): Integer;

{ Entity_IsOffScreen @ 0x004580BC. Margin is multiplied by the entity's own
  extent, so a bigger sprite gets a proportionally bigger margin. }
function IsOffScreen(const E: TEntity; Margin: Integer): Boolean;

{ 0x0045117C. Move V toward zero by Step without ever crossing it. Used for
  friction - the air dash bleeds off through this - and called from several
  places rather than inlined. }
procedure ApproachZero(var V: Integer; Step: Integer);

{ 0x00451354. Axis-aligned overlap of two boxes given as (L, T, R, B), with a
  per-axis margin that shrinks the test. The original writes it as
  separation-versus-width rather than the usual four edge comparisons; this is
  the same predicate, kept in the original's form. }
function RectOverlap(const A, B: TBox; ShrinkX, ShrinkY: Integer): Boolean;

implementation


procedure ApproachZero(var V: Integer; Step: Integer);
begin
  if V < 0 then
  begin
    V := V + Step;
    if V > 0 then
      V := 0;
  end
  else if V > 0 then
  begin
    V := V - Step;
    if V < 0 then
      V := 0;
  end;
end;

function RectOverlap(const A, B: TBox; ShrinkX, ShrinkY: Integer): Boolean;
begin
  Result := (A.L - B.L < (B.R - B.L) - ShrinkX) and
            (B.L - A.L < (A.R - A.L) - ShrinkX) and
            (A.T - B.T < (B.B - B.T) - ShrinkY) and
            (B.T - A.T < (A.B - A.T) - ShrinkY);
end;

function EntityType(Id: Integer): TEntityType;
var
  I: Integer;
begin
  if (Id < 0) or (Id >= ENTITY_TYPE_COUNT) then
  begin
    for I := 0 to ENTITY_TYPE_FIELDS - 1 do
      Result.Raw[I] := 0;
    Exit;
  end;
  Result := ENTITY_TYPES[Id];
end;

procedure TEntityPool.Clear;
begin
  FillChar(FSlots, SizeOf(FSlots), 0);
end;

function TEntityPool.GetAlive(Index: Integer): Boolean;
begin
  Result := (Index >= 0) and (Index < ENTITY_COUNT) and
            (FSlots[Index].Raw[EF_ALIVE] <> 0);
end;

function TEntityPool.Field(Slot, IntIndex: Integer): Integer;
begin
  if (Slot < 0) or (Slot >= ENTITY_COUNT) or
     (IntIndex < 0) or (IntIndex >= ENTITY_INTS) then
    Exit(0);
  Result := FSlots[Slot].Raw[IntIndex];
end;

procedure TEntityPool.SetField(Slot, IntIndex, Value: Integer);
begin
  if (Slot < 0) or (Slot >= ENTITY_COUNT) or
     (IntIndex < 0) or (IntIndex >= ENTITY_INTS) then
    Exit;
  FSlots[Slot].Raw[IntIndex] := Value;
end;

function TEntityPool.PosX(Slot: Integer): Integer;
begin
  Result := Field(Slot, EF_POS_X) - POSITION_BIAS;
end;

function TEntityPool.PosY(Slot: Integer): Integer;
begin
  Result := Field(Slot, EF_POS_Y) - POSITION_BIAS;
end;

procedure TEntityPool.SetPos(Slot, X, Y: Integer);
begin
  SetField(Slot, EF_POS_X, X + POSITION_BIAS);
  SetField(Slot, EF_POS_Y, Y + POSITION_BIAS);
end;

function TEntityPool.LiveCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to ENTITY_COUNT - 1 do
    if FSlots[I].Raw[EF_ALIVE] <> 0 then
      Inc(Result);
end;

procedure TEntityPool.Kill(Slot: Integer);
begin
  SetField(Slot, EF_ALIVE, 0);
end;

procedure TEntityPool.Steer(Slot, TimerSlot, Reload: Integer);
var
  E: PEntity;
  Facing, Target: Integer;
begin
  if (Slot < 0) or (Slot >= ENTITY_COUNT) then
    Exit;
  if (TimerSlot < 0) or (TimerSlot >= EF_TIMER_COUNT) then
    Exit;
  E := @FSlots[Slot];

  Dec(E^.Raw[EF_BLOCK_B + TimerSlot]);
  if E^.Raw[EF_BLOCK_B + TimerSlot] < 1 then
  begin
    E^.Raw[EF_BLOCK_B + TimerSlot] := Reload;
    { Both positions are read in their BIASED form. The bias is identical on
      each, so it cancels in the subtraction inside AngleBetween - which is why
      the original can pass the raw fields straight through. }
    Target := AngleBetween(E^.Raw[EF_POS_X], E^.Raw[EF_POS_Y],
                           FSlots[0].Raw[EF_POS_X], FSlots[0].Raw[EF_POS_Y]);
    Facing := E^.Raw[EF_FACING];
    TurnToward(Facing, Target);
    E^.Raw[EF_FACING] := Facing;
  end;

  E^.Raw[EF_VEL_X] := DirVelX(E^.Raw[EF_FACING]);
  E^.Raw[EF_VEL_Y] := DirVelY(E^.Raw[EF_FACING]);
end;

function TEntityPool.Spawn(Kind, TypeId, X, Y: Integer): Integer;
var
  First, Last, Slot, I: Integer;
  T: TEntityType;
  E: PEntity;
begin
  Result := SLOT_NONE;

  case Kind of
    EKIND_SINGLE: begin First := SLOT_SINGLE_FIRST; Last := SLOT_SINGLE_LAST; end;
    EKIND_ACTOR:  begin First := SLOT_ACTOR_FIRST;  Last := SLOT_ACTOR_LAST;  end;
    EKIND_MINOR:  begin First := SLOT_MINOR_FIRST;  Last := SLOT_MINOR_LAST;  end;
  else
    { The original leaves its range registers uninitialised for any other value
      and scans from whatever happened to be in them. Refusing is the one place
      this deliberately does NOT reproduce the original, because reproducing it
      means reading uninitialised memory. }
    Exit;
  end;

  Slot := -1;
  for I := First to Last do
    if FSlots[I].Raw[EF_ALIVE] = 0 then
    begin
      Slot := I;
      Break;
    end;
  if Slot < 0 then
    Exit;                       { range full - the spawn is dropped }

  E := @FSlots[Slot];
  E^.Raw[EF_SLOT]  := Slot;
  E^.Raw[1]        := 0;
  E^.Raw[EF_ALIVE] := 1;
  E^.Raw[EF_TYPE]  := TypeId;

  { Two loops of ten in the original, over a contiguous 20-int span - so the
    real record almost certainly has two array[0..9] fields here. }
  for I := 0 to 9 do
  begin
    E^.Raw[EF_BLOCK_A + I] := 0;
    E^.Raw[EF_BLOCK_B + I] := 0;
  end;

  E^.Raw[5] := 0;
  E^.Raw[6] := 0;
  E^.Raw[7] := 0;
  E^.Raw[EF_SPRITE]    := -1;
  E^.Raw[EF_EVENT_ID]  := -1;
  E^.Raw[EF_POS_X]     := X + POSITION_BIAS;
  E^.Raw[EF_POS_Y]     := Y + POSITION_BIAS;
  E^.Raw[EF_VEL_X]     := 0;
  E^.Raw[EF_VEL_Y]     := 0;
  E^.Raw[EF_TYPEF_08]  := 1;
  E^.Raw[EF_TYPEF_04]  := 1;
  E^.Raw[EF_FACING]    := 0;
  E^.Raw[EF_BYTE94]    := 1;
  E^.Raw[EF_TIMER]     := 0;
  E^.Raw[$1D]          := 0;
  E^.Raw[$2C]          := 0;
  E^.Raw[$2D]          := 0;
  E^.Raw[$26]          := 0;
  E^.Raw[$27]          := 0;

  { Then the type table is copied over those defaults. }
  T := EntityType(TypeId);
  E^.Raw[5]           := T.Raw[0];
  E^.Raw[EF_TYPEF_04] := T.Raw[1];
  E^.Raw[EF_TYPEF_08] := T.Raw[2];
  for I := 0 to 3 do
    E^.Raw[EF_TYPEF_0C + I] := T.Raw[3 + I];
  { Table index 7 (+0x1C) is skipped - padding, zero in all 81 rows. }
  for I := 0 to 9 do
    E^.Raw[EF_TYPEF_20 + I] := T.Raw[8 + I];

  { The original allocates a sprite-pool object here unless the type's first
    column is -1, and FAILS THE WHOLE SPAWN if the 256-object pool is full,
    clearing the alive flag again. That pool belongs to the DirectX component
    layer and is not modelled yet, so the allocation is skipped and the slot is
    kept - a divergence that matters only once sprites are drawn from it. }

  Result := Slot;
end;

function PixelOf(Raw: Integer): Integer;
begin
  { The original's round-toward-zero idiom, kept literally. }
  if Raw - POSITION_BIAS < 0 then
    Result := (Raw - POSITION_ROUND) shr POSITION_SHIFT
  else
    Result := (Raw - POSITION_BIAS) shr POSITION_SHIFT;
end;

function EntityPixelX(const E: TEntity): Integer;
begin
  Result := PixelOf(E.Raw[EF_POS_X]);
end;

function EntityPixelY(const E: TEntity): Integer;
begin
  Result := PixelOf(E.Raw[EF_POS_Y]);
end;

function IsOffScreen(const E: TEntity; Margin: Integer): Boolean;
var
  X, Y, W, H: Integer;
begin
  X := EntityPixelX(E);
  Y := EntityPixelY(E);
  W := E.Raw[EF_EXTENT_X] * Margin;
  H := E.Raw[EF_EXTENT_Y] * Margin;
  Result := (X < -W) or (X > W + SCREEN_W) or (Y < -H) or (Y > H + SCREEN_H);
end;

initialization
  { The stride is not a design choice, it is what the original's
    `base + index * 0x104` requires. A layout slip here silently misaligns
    every slot after the first, so fail loudly at startup - the same guard
    TPlayerState uses against save.dat drifting. }
  Assert(SizeOf(TEntity) = ENTITY_BYTES,
         'TEntity must be exactly 0x104 bytes to match the original stride');
  Assert(SizeOf(TEntityType) = $48,
         'TEntityType must be exactly 0x48 bytes to match the type table');

end.
