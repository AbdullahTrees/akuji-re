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

  { The bias expressed in whole pixels. Entity_UpdateAll converts a position to
    a screen coordinate by shifting FIRST and subtracting the bias afterwards -
    `(Raw div 32) - 2048` rather than `(Raw - $10000) div 32`. The two agree
    because $10000 is an exact multiple of 32; the order is kept because it is
    the order the original emits. }
  POSITION_BIAS_PIXELS = POSITION_BIAS shr POSITION_SHIFT;   { 2048 }

  { What Entity_TileCollideX/Y subtract from a tile index before looking it up.

    It is 128 rather than 64, and that is the interesting part. The tile index
    is built from OriginPixel(layer origin) + OriginPixel(entity position), and
    BOTH of those carry POSITION_BIAS - 2048 pixels each, 4096 together, which
    is 128 tiles of 32. So the constant is independent evidence that the layer
    origin is biased the same way an entity position is, which until now rested
    only on the +31 rounding idiom looking identical in both.

    Like every other tile calculation in the game it assumes 32-pixel tiles.
    Every shipped map is 32. }
  TILE_BIAS_TILES = $80;   { 128 }

  TILE_NONE = -1;          { Entity_TileCollide*'s "nothing solid that way" }

  { --- Delphi's Random, from 0x00402AC4 ---------------------------------
    Two instructions and a multiply:

        RandSeed := RandSeed * $08088405 + 1
        Result   := (N * RandSeed) shr 32

    a linear congruential generator whose high bits are scaled into 0..N-1
    without a division. It matters far more than an RTL detail normally would:
    the game's debris, its scatter and its item drops all run off it, so
    reproducing it exactly is what makes any of that replayable. The seed lives
    at 0x0046E040. }
  RANDOM_MULT = $08088405;
  RANDOM_SEED_ADDR = $0046E040;

  { --- Entity_SpawnDebris @ 0x00461874 ----------------------------------
    Five particles of type 13, fanned upward at fixed speeds and scattered
    horizontally at random. The impact sound depends on the KIND, and kind 0
    asks the terrain - which is where terrain 3 and 4 turn out to mean water. }
  DEBRIS_SPLASH   = 0;    { the sound comes from the terrain }
  DEBRIS_IMPACT   = 1;
  DEBRIS_SHATTER  = 2;
  DEBRIS_LIFT     = 8;    { particle i leaves at (i + 4) * -8 }
  DEBRIS_DEPTH    = 6;
  DEBRIS_SPEED_MAX = 3;   { RandomBelow(3) + 1, so 1..3 }

  { --- Entity_MaybeDropItem @ 0x004617FC --------------------------------
    One roll of Random(256) decides everything. The item drops when the roll
    EXCEEDS 179, which is 76 of 256 - a shade under 30% - and the same roll,
    compared against 245, picks between two variants: 10 of 256 outright, so
    about 13% of the drops that happen.

    Rolling ONCE for both is worth noticing. The variant is not independent of
    the drop: it is the top of the same distribution, so the rare item can only
    ever appear on a roll that was already going to drop something. }
  DROP_ROLL      = $100;  { Random(256) }
  DROP_THRESHOLD = $B3;   { 179; drops when the roll is GREATER }
  DROP_RARE      = $F5;   { 245; the same roll, higher up }
  DROP_TYPE      = $24;   { 36 - EntityUpdate_Type36_FallingItem }
  DROP_TIMER     = 30;
  DROP_LIFT      = -96;   { EF_VEL_Y, so it pops upward before falling }

  { --- Entity_Destroy @ 0x00461400 --------------------------------------
    Far more than "mark the slot free". It settles debts in four directions,
    and two of them corroborate fixes made elsewhere from the other side:

      class 4  decrements Entities[ THIS ENTITY'S int 1 ].int $15. Int 1 is
               the owner slot and $15 is that owner's live shot count - which
               is exactly what the Player.pas audit concluded when it moved
               PF_OWNER from $04 to $01 and put the projectile lifetime in
               $14. A projectile dying gives its owner a shot back.

      class 5  destroys its two children, EF_CHILD_A and EF_CHILD_B, which is
               what those fields were named for before this function was read.

      class 7  scatters a kind-2 debris burst, but only on a loot-bearing
               destroy.

    The loot itself is gated on type table column 8 being zero, so that column
    is a NO DROP flag.

    Then the event bookkeeping, which matches what EventScripts.pas worked out
    from the data: opcode 7 fires the event, opcode 5 sets the progress flag
    named by ParamB's first four characters, and either way the event's "an
    entity for this exists" byte is cleared so it can spawn again. }
  DESTROY_CLASS_PROJECTILE = 4;
  DESTROY_CLASS_PARENT     = 5;
  DESTROY_CLASS_SHATTER    = 7;
  EF_NO_DROP  = $37;   { type table column 8; non-zero means never drop }
  EF_OWNER    = $01;   { the slot that fired this }
  EF_SHOTS    = $15;   { on an OWNER: how many of its shots are alive }
  EVENT_OPCODE_DESTROY = 7;
  EVENT_OPCODE_FLAG    = 5;
  EVENT_BEGIN_FROM_DESTROY = 4;

  { --- Entity_SolidCollideX/Y @ 0x00456B4C / 0x00456E0C -----------------
    Entity-versus-entity blocking, and the pair is NOT symmetric.

    SOFTNESS IS PER AXIS. With SkipSoft set, the X sweep ignores EF_SOLID
    kind 1 and the Y sweep ignores kind 2 - so kind 1 blocks vertically only
    and kind 2 horizontally only, which is what "EF_SOLID is a kind" meant.
    With SkipSoft clear both kinds block on both axes.

    Y HAS NO ZERO-DELTA GUARD. The X sweep does nothing when Delta is 0; the
    Y sweep runs anyway, which is how an entity standing still on a platform
    keeps being told it is standing on one.

    LANDING ON TOP ALSO SETS PushX. When the subject comes down onto a solid
    within SOLID_TOP_TOLERANCE, the Y sweep writes the horizontal offset
    between the two - INCLUDING this frame's layer scroll - into PushX as well
    as the vertical push. That is the riding mechanic: it is what carries a
    rider along with a moving platform, and it is the reason PushX is read
    after a Y collision at all.

    The air dash phases through anything whose EF_VULN_KIND is $5C, which is
    the same fact Player_UpdateAirDash was written from - the two agree from
    opposite directions.

    Only slot 0 - the player - can fire the push-against events, opcode 2
    while holding the axis into the solid and opcode 3 on confirm. The X sweep
    reads the X axis for that and the Y sweep reads the Y axis. }
  SOLID_SOFT_IN_X = 1;   { skipped by the X sweep when SkipSoft }
  SOLID_SOFT_IN_Y = 2;   { skipped by the Y sweep when SkipSoft }
  SOLID_PHASE_VULN = $5C;    { the air dash goes through these }
  SOLID_STATE_AIRDASH = 7;
  EVENT_OPCODE_PUSH = 2;
  EVENT_OPCODE_PUSH_CONFIRM = 3;
  TERRAIN_WATER_A = 3;
  TERRAIN_WATER_B = 4;
  SND_WATER01 = 31;  SND_WATER02 = 40;
  SND_BOM02   = 22;  SND_BOM04   = 48;
  SCREEN_W       = $140;      { 320 }
  SCREEN_H       = $F0;       { 240 }

  { Field positions as INT indices into TEntity.Raw. Named only where the use
    is established; the rest keep their index. }
  EF_SLOT        = $00;   { the slot's own number }
  EF_ALIVE       = $02;   { byte; zero means the slot is free }
  EF_TYPE        = $03;   { index into ENTITY_TYPES }
  EF_SPRITE      = $04;   { sprite-pool handle, -1 when the type has no sprite }
  SPRITE_NONE    = -1;    { EF_SPRITE's empty value }
  { The drawn sprite id, which Entity_UpdateAll copies onto the sprite object
    every frame, and the placement variant the ParamA 'A' letter writes. Both
    sit outside the two 10-int blocks. }
  EF_ANIM_ID     = $05;
  EF_VARIANT     = $06;
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
  EF_VEL_X       = $20;   { zeroed on spawn }
  EF_VEL_Y       = $21;   { AUDIT: the -96 that Entity_MaybeDropItem writes
                            was recorded against EF_VEL_X above. It is this
                            one - the original writes +0x84, not +0x80 - so a
                            dropped item is launched UPWARD, not sideways. }
  EF_FACING      = $22;   { direction 0..63, see Directions.pas }
  { Type table column 2. Entity_UpdateAll copies it to the sprite's draw-order
    key, so this is the DRAW LAYER - except that -1 means "sort by screen Y",
    clamped to 1..SCREEN_H. No shipped type is -1 (column 2 runs 0..8 across all
    81 rows) and a byte scan of the code section finds no instruction writing -1
    into +0x8C either, so the Y-sorting branch is present and never taken. That
    is recorded rather than dropped: it is the original's dead branch, not a
    misreading of it.

    Entity_PlayerTouch reads the same field as `PosY + arg - 2 * [$23]`, i.e. as
    a vertical inset, which is why the provenance name is kept alongside the
    decoded one. }
  EF_TYPEF_08    = $23;   { <- type table +0x08, column 2 }
  EF_DEPTH       = EF_TYPEF_08;
  DEPTH_BY_SCREEN_Y = -1;
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
  { Not stored: Entity_UpdateAll refreshes both every frame from the sprite's
    CURRENT frame, through 0x0044CF1C and 0x0044CF68, and only while the sprite
    is visible. So an entity's extent is its art's size, and one whose animation
    changes size gets a collision box that follows it. }
  EF_EXTENT_X    = $26;   { +0x98, sprite width }
  EF_EXTENT_Y    = $27;   { +0x9C, sprite height }
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

  { --- Where all four of those come from: Entity_UpdateAll @ 0x004608BC -----

    Neither EF_BOX_OFS_* nor EF_HITBOX_INSET_* is a stored constant. All four
    are RECOMPUTED every frame, while the game state is GS_PLAY, from the
    sprite's current size and four PERCENTAGES held in the type table:

        EF_BOX_OFS_X      := Round(HalfExtent(EF_EXTENT_X) * col11 / 100)
        EF_BOX_OFS_Y      := Round(HalfExtent(EF_EXTENT_Y) * col12 / 100)
        EF_HITBOX_INSET_X := Round(HalfExtent(EF_EXTENT_X) * col13 / 100)
        EF_HITBOX_INSET_Y := Round(HalfExtent(EF_EXTENT_Y) * col14 / 100)

    The divisor is a Single 100.0 at 0x004610C0 and the rounding is the x87's
    round-half-to-even. Reproducing it is NOT a matter of writing Round instead
    of Trunc: the original runs at 64-bit significands and no float type on
    x86-64 does, so EntityHandlers.ScaleByPercent does the whole thing in
    integers. See its header for why, and for how far the difference reaches.

    Reading those columns as percentages does not rest on the divisor alone.
    Across all 81 rows the four columns only ever hold 0, 5, 10, 20, 30, 33, 40,
    50, 60, 70, 75 and 80, and nothing exceeds 100. The 33 and the 75 - exactly
    one third and three quarters - are what no other reading of the columns
    produces.

    So a type does not carry a hitbox measured in pixels. It carries the
    FRACTION of its own art that the box covers. }
  EF_BOX_PCT_X   = $3A;   { +0xE8, type table column 11 }
  EF_BOX_PCT_Y   = $3B;   { +0xEC, column 12 }
  EF_INSET_PCT_X = $3C;   { +0xF0, column 13 }
  EF_INSET_PCT_Y = $3D;   { +0xF4, column 14 }
  BOX_PERCENT_DIVISOR: Single = 100.0;   { the Single at 0x004610C0 }
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
  TYPE_COL_DEPTH       = 2;   { -> [$23], the draw layer }
  TYPE_COL_BOX_PCT_X   = 11;  { -> [$3A] }
  TYPE_COL_BOX_PCT_Y   = 12;  { -> [$3B] }
  TYPE_COL_INSET_PCT_X = 13;  { -> [$3C] }
  TYPE_COL_INSET_PCT_Y = 14;  { -> [$3D] }

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
      A[3] $0B  scatter radius              B[2] $14  countdown to next sound
      A[4] $0C  frames between sounds

    AUDIT: the radius was recorded as being "in tiles" and it is not. The
    offset is Random(r * 16) - r * 8 PIXELS, so it spans plus or minus r * 8 -
    quarter-tile units at the game's 32-pixel tiles. Reading it as tiles
    overstates every burst by a factor of four.

    When B[1] passes A[2] it destroys itself - and note the test is a strict
    `A[2] < B[1]` after the increment, so an emitter configured for N actually
    spawns N + 1 times. That is the pattern to expect
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
  { p_LayerInfo @ 0x00483BF4. A plain global struct, not a pointer - the
    original indexes it directly.

    Origin is in the same biased 1/32-pixel units as an entity position, so
    PixelOf applies to it unchanged. Delta is what the layer moved THIS frame,
    in 1/32 pixel, and exists so the parallax and the riding code can follow a
    scroll they did not cause. }
  TLayerInfo = record
    OriginX:    Integer;   // +0x00
    OriginY:    Integer;   // +0x04
    DeltaX:     Integer;   // +0x08
    DeltaY:     Integer;   // +0x0C
    TileW:      Integer;   // +0x10
    TileH:      Integer;   // +0x14
    MapTilesX:  Integer;   // +0x18
    MapTilesY:  Integer;   // +0x1C
  end;

type
  { Kept as a raw int array for the same reason TStageRecord is: the layout is
    known exactly but most field meanings are not, and inventing names for them
    would make guesses look like decodes. }
  TEntity = record
    Raw: array[0..ENTITY_INTS - 1] of Integer;
  end;
  PEntity = ^TEntity;

  { Everything an entity handler needs that it does not own: the tilemap, the
    pool, the sound device. A test supplies a flat world; the game will supply
    the real one.

    This started as the player controller's private interface and was lifted
    here the moment a second thing needed it. The surface is deliberately the
    ORIGINAL's shape rather than a tidier one.

    TileAt returns the tile index an entity would hit moving by Delta on that
    axis, exactly as Entity_TileCollideX/Y do - the caller compares it against
    SolidThreshold rather than being told yes or no, because the original does.
    EdgeDist returns how far it may actually move.

    SolidCollide* answer "did we hit a blocking entity"; how far to push out
    comes back through PushX/PushY, and OnTopOfSolid says the hit was a
    landing. That is the original's shape - three globals rather than out
    parameters - and it is kept because the callers read them in that order. }
  { Declared ahead of TEntityWorld because Entity_Destroy reaches other
    entities by slot, and the pool is defined further down. }
  TEntityPool = class;

  { A collision box in screen pixels, in the order the original stores it: four
    consecutive ints passed by pointer to Rect_Overlap. }
  TBox = record L, T, R, B: Integer; end;

  { The tilemap, as the collision code sees it.

    TileMap_Get @ 0x0044DB5C is one line - `Data[X + Y * Width]`, a Word, with
    NO bounds check of any kind. That is not the same as returning 0 off the
    map, and the difference is reachable: an X outside 0..Width-1 simply indexes
    into the NEIGHBOURING ROW, so the map wraps horizontally for anything that
    walks off the side. An implementation is expected to reproduce that. Only an
    index outside the array altogether cannot be reproduced.

    The original also takes a LAYER INDEX and resolves both p_LayerInfo[layer]
    and p_TileMaps[layer] from it - p_LayerInfo is an array of these records,
    stride 0x20, which is one independent confirmation that TLayerInfo is
    exactly eight ints. Here the caller resolves the layer instead and passes
    the two directly. }
  TTileSource = class
  public
    function TileAt(TileX, TileY: Integer): Integer; virtual; abstract;
  end;

  { The sprite pool, as Entity_UpdateAll sees it.

    The original keeps sprites in a Delphi TList at 0x0046D35C and EF_SPRITE is
    the index into it - FUN_0044CFB8 is nothing but TList.Get. The update loop
    touches exactly five fields on a sprite and no methods, so only those are
    here; anything more would be inventing a renderer rather than recording one.

        +0x1C  animation base, written from EF_ANIM_ID
        +0x20  frame within the animation, not touched here
        +0x2C  screen X          +0x30  screen Y
        +0x34  draw-order key    +0x3D  visible, a byte

    These are plain field stores in the original, not property setters: the
    depth step reads +0x30 straight back after writing it and gets exactly what
    it wrote. This interface passes the value along instead, which is the same
    thing and one fewer method to stub. }
  TSpriteSink = class
  public
    procedure SetVisible(Handle: Integer; Visible: Boolean); virtual; abstract;
    function  GetVisible(Handle: Integer): Boolean; virtual; abstract;
    procedure SetAnim(Handle, AnimId: Integer); virtual; abstract;
    function  Width(Handle: Integer): Integer; virtual; abstract;
    function  Height(Handle: Integer): Integer; virtual; abstract;
    procedure SetPos(Handle, X, Y: Integer); virtual; abstract;
    procedure SetDepth(Handle, Depth: Integer); virtual; abstract;
  end;

  TEntityWorld = class
  public
    PushX, PushY: Integer;       { 0x00484FAC / 0x00484FB0 }
    OnTopOfSolid: Boolean;       { 0x00484FB4 }
    SolidThreshold: Integer;     { 0x00484EF4, set per terrain }
    Fading: Boolean;             { suppresses the soft landing sound }

    { The layer the entities live on, and the stage's terrain id. Both are
      globals in the original - p_LayerInfo and the stage record's last int -
      and both are read by code that has no other way to reach them. }
    Layer: TLayerInfo;
    TerrainId: Integer;

    { The pool itself, when the world has one. Entity_Destroy reaches other
      entities by slot - its owner, its children - and cannot do that through
      Spawn alone. Nil is a legitimate configuration: a world with no pool
      simply has no cross-entity bookkeeping to settle. }
    Pool: TEntityPool;

    { The sprite pool, so a destroyed entity can hide and release its sprite.
      Nil when the world does not draw. }
    Sprites: TSpriteSink;

    { The tilemap. Nil is a world with no terrain, where every tile query
      answers TILE_NONE - which is what the player trace's flat room wants. }
    Tiles: TTileSource;

    { Scrolling is an INPUT to the tile query, not just a consequence of it:
      Entity_TileCollideX/Y take it as their fifth argument, because when the
      layer moves instead of the entity the tile under the entity differs. }
    { These four were abstract while the functions behind them were only
      described. They are real now - Entity_TileCollideX/Y and
      Entity_TileEdgeDistX/Y - and stay virtual only so a test can supply a
      room without a tilemap. }
    function TileAtX(const E: TEntity; Delta: Integer;
                     Scrolling: Boolean): Integer; virtual;
    function TileAtY(const E: TEntity; Delta: Integer;
                     Scrolling: Boolean): Integer; virtual;
    function EdgeDistX(const E: TEntity; Delta: Integer): Integer; virtual;
    function EdgeDistY(const E: TEntity; Delta: Integer): Integer; virtual;

    { 0x00456B4C / 0x00456E0C. Real, not abstract. AgainstPlayer swaps the
      scan from the minor slots to slot 0 alone, which is how a moving solid
      asks whether it would push the player rather than the other way round. }
    function SolidCollideX(const E: TEntity; Delta: Integer;
                           SkipSoft: Boolean;
                           AgainstPlayer: Boolean = False): Boolean; virtual;
    function SolidCollideY(const E: TEntity; Delta: Integer;
                           SkipSoft: Boolean;
                           AgainstPlayer: Boolean = False): Boolean; virtual;

    { What the push-against events need. Neutral by default - a world with no
      input attached simply never fires them. }
    function FindBlockingSolid(const E: TEntity; const Box: TBox;
                              SoftKind: Integer; SkipSoft,
                              AgainstPlayer: Boolean;
                              out Other: TBox): Integer;
    procedure MaybePushEvent(Slot, Blocker, Axis: Integer);
    function AxisX: Integer; virtual;
    function AxisY: Integer; virtual;
    function ConfirmPressed: Boolean; virtual;

    function Spawn(Kind, TypeId, X, Y: Integer): Integer; virtual; abstract;
    { 0x00461400. Real, not abstract. }
    procedure DestroyEntity(var E: TEntity; DropLoot: Boolean); virtual;

    { What Entity_Destroy needs from the event system, which it reaches
      through globals in the original. The defaults are "no event table
      wired" - EventOpcode returning -1 means every event test is skipped -
      which is a real configuration, not a stub: the player trace runs that
      way on purpose. }
    function EventOpcode(EventId: Integer): Integer; virtual;
    function EventProgressIndex(EventId: Integer): Integer; virtual;
    procedure BeginEvent(EventId, Arg: Integer); virtual;
    procedure ClearEventEntity(EventId: Integer); virtual;
    procedure SetProgress(Index: Integer); virtual;
    procedure SetSpawnField(Slot, IntIndex, Value: Integer); virtual; abstract;
    { 0x00461874. Real, not abstract: this is the whole function. }
    procedure SpawnDebris(const E: TEntity; Kind: Integer); virtual;

    { 0x004617FC. A ~30% chance of dropping a type 36. }
    procedure MaybeDropItem(const E: TEntity); virtual;
    procedure PlaySound(Id: Integer); virtual; abstract;
    { Delphi's Random(N), which the original's behaviour genuinely depends
      on. Overridable only so a test can make a trace repeatable. }
    function RandomBelow(N: Integer): Integer; virtual;
  end;

  { NOTE: no `type` keyword here on purpose. TEntityPool is forward-declared
    above so TEntityWorld can hold one, and Pascal requires a forward class and
    its definition to sit in the SAME type block. }



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
    { The slot itself. Entity_UpdateAll walks the pool by pointer and hands
      each entity to a handler that takes it by reference. }
    function Entity(Slot: Integer): PEntity;
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

{ The layer origin's pixel value. Rounds with a bare +31 for negatives and does
  NOT remove POSITION_BIAS, unlike an entity position. }
function OriginPixel(Raw: Integer): Integer;

{ 0x00457150 / 0x00457228. How far the entity may move on that axis before it
  is flush against the tile boundary it is heading for, in 1/32 pixel. The
  callers use it to land exactly on an edge after Entity_TileCollide* has said
  something is in the way.

  The two are an exact pair: every field the X one reads at offset N, the Y one
  reads at N+4, and they take LayerInfo +0x00/+0x10 against +0x04/+0x14. That
  pairing over six independent fields is what established EF_EXTENT_*,
  EF_BOX_OFS_* and EF_TILE_OFS_* in the first place.

  TWO THINGS THAT LOOK WRONG AND ARE NOT.

  The entity position is converted with a bare +31 for negatives, WITHOUT
  removing POSITION_BIAS - unlike everywhere else. The bias survives into the
  world coordinate, but 0x10000 in 1/32 pixel is 2048 pixels, and 2048 is
  exactly 64 tiles of 32, so it shifts the coordinate by a whole number of
  tiles and the distance to a tile edge is unchanged. It would stop being true
  for any tile width that does not divide 2048; every shipped map is 32.

  DELTA = 0 RETURNS RUBBISH. The original initialises its result to the entity
  POINTER and only overwrites it in the Delta < 0 and Delta > 0 branches, so a
  zero delta returns an address cast to an integer. Callers reach it only after
  a collision was reported, which normally implies a non-zero delta - but
  Entity_TileCollide* can report one for an entity already inside a solid tile,
  and then the original assigns a pointer to a velocity. Reproducing that is
  neither possible nor desirable here; this returns 0. }
function TileEdgeDistX(const E: TEntity; const L: TLayerInfo;
                       Delta: Integer): Integer;
function TileEdgeDistY(const E: TEntity; const L: TLayerInfo;
                       Delta: Integer): Integer;

{ 0x0045117C. Move V toward zero by Step without ever crossing it. Used for
  friction - the air dash bleeds off through this - and called from several
  places rather than inlined. }
procedure ApproachZero(var V: Integer; Step: Integer);

{ 0x00457300 / 0x004574DC. The tile an entity would run into moving DeltaMain
  along this axis, or TILE_NONE if nothing solid is in the way. The caller
  compares the answer against the terrain's solid threshold - and so does this,
  because the original stops at the FIRST tile at or above it rather than
  returning the whole span.

  It does not test one tile. It sweeps the entity's LEADING EDGE across every
  tile the box spans on the other axis, so a tall entity is stopped by a wall
  that only meets its feet. DeltaCross shifts that span, which is how a caller
  asks "if I move this way AND that way, what stops me horizontally".

  DELTA OF ZERO RETURNS TILE_NONE. The whole body sits inside `if Delta <> 0`,
  so an entity that is not moving is never blocked - it can rest inside a solid
  tile indefinitely and only the next non-zero velocity notices. That is why
  Player_Update can ask about EF_VEL_X unconditionally.

  SCROLLING is finer than it looks. It decides whether Delta is added to the
  LAYER ORIGIN or to the ENTITY POSITION - but both land in the same sum, so it
  changes no tile except through ROUNDING: each term is converted to pixels
  separately, so which of the two carries the 1/32-pixel remainder decides
  whether the sum crosses a pixel. It matters exactly when the two fractions
  straddle a boundary, and not otherwise.

  The two write their working tile coordinate to globals at 0x00484FA4 and
  0x00484FA8. Those are NOT outputs: nothing outside these two functions
  references either address, so they are locals the compiler happened to spill
  to fixed storage. They are locals here. }
function EntityTileCollideX(const E: TEntity; const L: TLayerInfo;
                            Tiles: TTileSource; SolidThreshold: Integer;
                            DeltaX, DeltaY: Integer;
                            Scrolling: Boolean): Integer;
function EntityTileCollideY(const E: TEntity; const L: TLayerInfo;
                            Tiles: TTileSource; SolidThreshold: Integer;
                            DeltaY, DeltaX: Integer;
                            Scrolling: Boolean): Integer;

{ 0x00457F98. The entity-versus-entity hit test: build both boxes and hand
  them to Rect_Overlap.

  The box is the one EF_HITBOX_INSET_* describes - the +0xA8/+0xAC pair, not
  the +0xA0/+0xA4 pair tile collision uses. Getting those two the wrong way
  round would be silent and wrong.

  TWO THINGS THE EARLIER WRITE-UP DID NOT HAVE.

  The SECOND entity's extents are multiplied by ScaleX and ScaleY before the
  box is built, so a caller can test against a deliberately enlarged or shrunk
  version of it. The first entity is always used at its own size, which is the
  same as passing 1.

  And the pixel conversion here does NOT remove POSITION_BIAS. Everywhere else
  an entity position becomes pixels by subtracting the bias first; this uses the
  bare `if negative then +31, then shift` form, so both boxes carry the same
  +2048 pixel offset and it cancels in the comparison. Reproduced rather than
  tidied, because tidying it would be a real change: the bias only cancels
  because BOTH sides carry it. }
function EntityBox(const E: TEntity; ScaleX, ScaleY: Integer): TBox;
function EntitiesOverlap(const A, B: TEntity;
                         ScaleX, ScaleY: Integer): Boolean;

{ 0x00451354. Axis-aligned overlap of two boxes given as (L, T, R, B), with a
  per-axis margin that shrinks the test. The original writes it as
  separation-versus-width rather than the usual four edge comparisons; this is
  the same predicate, kept in the original's form. }
function RectOverlap(const A, B: TBox; ShrinkX, ShrinkY: Integer): Boolean;

{ An entity position to pixels, with POSITION_BIAS removed and the rounding
  toward zero the original uses. Exported because the event spawn walk needs
  the same conversion for the layer origin. }
function PixelOf(Raw: Integer): Integer;

{ 0x0045114C. The three-way compare the game uses wherever it wants a sign:
  -1 when B < A, 1 when A < B, 0 when equal. Called as Compare(0, X), which is
  Sign(X). Differential-tested against the original over 25 cases. }
function Compare(A, B: Integer): Integer;

{ E.Raw[Extent] div 2, rounded toward zero the way the original's shift-and-
  correct does it. Exported because Entity_UpdateAll halves an extent four times
  over and must halve it identically. }
function HalfExtent(V: Integer): Integer;

{ 0x00402AC4. Delphi's Random(N) - the generator the game's behaviour
  actually depends on, reproduced exactly so a run can be replayed. }
function DelphiRandom(N: Integer): Integer;

var
  { 0x0046E040. Delphi's RandSeed. Set it to replay a sequence. }
  RandomSeed: Cardinal = 0;

  { 0x0046D20C and 0x0046D210. Entity_UpdateAll clears both at the top and
    counts as it goes: every live slot, and every live slot that also holds a
    sprite. Nothing inside the update loop reads them back. }
  EntitiesLive:  Integer = 0;
  EntitiesDrawn: Integer = 0;

implementation


{ The original rounds the layer origin with `if x < 0 then x := x + 31` and no
  bias subtraction, where an entity position gets the biased form. The bias
  cancels in the subtraction that follows it, so this is not a discrepancy -
  but it is why this is written out rather than reusing PixelOf. }
function OriginPixel(Raw: Integer): Integer;
begin
  if Raw < 0 then
    Result := (Raw + 31) shr POSITION_SHIFT
  else
    Result := Raw shr POSITION_SHIFT;
end;


{ E.Raw[Extent] div 2, rounded toward zero the way the original's
  shift-and-correct does it. }
function HalfExtent(V: Integer): Integer;
begin
  Result := V div 2;
end;

function Compare(A, B: Integer): Integer;
begin
  Result := 0;
  if B < A then
    Result := -1;
  if A < B then
    Result := 1;
end;

function TileEdgeDistX(const E: TEntity; const L: TLayerInfo;
                       Delta: Integer): Integer;
var
  CamPx, TileW, EntPx, Half, World: Integer;
begin
  Result := 0;                          { see the header: Delta = 0 }
  if Delta = 0 then
    Exit;
  CamPx := OriginPixel(L.OriginX);
  TileW := L.TileW;
  if TileW = 0 then
    Exit;
  EntPx := OriginPixel(E.Raw[EF_POS_X]);
  Half := HalfExtent(E.Raw[EF_EXTENT_X]);
  if Delta < 0 then
  begin
    World := (CamPx mod TileW) + (EntPx - Half)
             + E.Raw[EF_BOX_OFS_X] + E.Raw[EF_TILE_OFS_X];
    Result := ((World div TileW) * TileW - World) shl POSITION_SHIFT;
  end
  else
  begin
    World := (CamPx mod TileW) + ((EntPx + Half) - E.Raw[EF_BOX_OFS_X])
             + E.Raw[EF_TILE_OFS_X] - 1;
    Result := (((World div TileW + 1) * TileW - 1) - World) shl POSITION_SHIFT;
  end;
end;

function TileEdgeDistY(const E: TEntity; const L: TLayerInfo;
                       Delta: Integer): Integer;
var
  CamPx, TileH, EntPx, Half, World: Integer;
begin
  Result := 0;
  if Delta = 0 then
    Exit;
  CamPx := OriginPixel(L.OriginY);
  TileH := L.TileH;
  if TileH = 0 then
    Exit;
  EntPx := OriginPixel(E.Raw[EF_POS_Y]);
  Half := HalfExtent(E.Raw[EF_EXTENT_Y]);
  if Delta < 0 then
  begin
    World := (CamPx mod TileH) + (EntPx - Half)
             + E.Raw[EF_BOX_OFS_Y] + E.Raw[EF_TILE_OFS_Y];
    Result := ((World div TileH) * TileH - World) shl POSITION_SHIFT;
  end
  else
  begin
    World := (CamPx mod TileH) + ((EntPx + Half) - E.Raw[EF_BOX_OFS_Y])
             + E.Raw[EF_TILE_OFS_Y] - 1;
    Result := (((World div TileH + 1) * TileH - 1) - World) shl POSITION_SHIFT;
  end;
end;

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

function EntityTileCollideX(const E: TEntity; const L: TLayerInfo;
                            Tiles: TTileSource; SolidThreshold: Integer;
                            DeltaX, DeltaY: Integer;
                            Scrolling: Boolean): Integer;
var
  Edge, MoveLayer, MoveEnt, Cross, Row, LastRow, Col, Tile: Integer;
begin
  Result := TILE_NONE;
  if (DeltaX = 0) or (L.TileW = 0) or (L.TileH = 0) then
    Exit;

  { The leading edge, as a pixel offset from the entity's centre. The two arms
    are not symmetric: the right edge carries a -1 because it is the last pixel
    INSIDE the box, not the first one past it. }
  if DeltaX < 0 then
    Edge := E.Raw[EF_BOX_OFS_X] - HalfExtent(E.Raw[EF_EXTENT_X])
            + E.Raw[EF_TILE_OFS_X]
  else
    Edge := HalfExtent(E.Raw[EF_EXTENT_X]) - E.Raw[EF_BOX_OFS_X]
            + E.Raw[EF_TILE_OFS_X] - 1;

  if Scrolling then
  begin
    MoveLayer := DeltaX;
    MoveEnt   := 0;
  end
  else
  begin
    MoveLayer := 0;
    MoveEnt   := DeltaX;
  end;

  { The rows the box spans, with DeltaCross applied. Each term is converted to
    pixels on its own - not summed first - which is what makes Scrolling a
    rounding decision. }
  Cross := OriginPixel(L.OriginY) + OriginPixel(E.Raw[EF_POS_Y] + DeltaY);
  Row := (Cross - HalfExtent(E.Raw[EF_EXTENT_Y])
          + E.Raw[EF_BOX_OFS_Y] + E.Raw[EF_TILE_OFS_Y]) div L.TileH;
  LastRow := (Cross + HalfExtent(E.Raw[EF_EXTENT_Y])
              - E.Raw[EF_BOX_OFS_Y] + E.Raw[EF_TILE_OFS_Y] - 1) div L.TileH;

  Col := (OriginPixel(L.OriginX + MoveLayer)
          + OriginPixel(E.Raw[EF_POS_X] + MoveEnt) + Edge) div L.TileW
         - TILE_BIAS_TILES;

  while Row <= LastRow do
  begin
    Tile := Tiles.TileAt(Col, Row - TILE_BIAS_TILES);
    if Tile >= SolidThreshold then
      Exit(Tile);
    Inc(Row);
  end;
end;

function EntityTileCollideY(const E: TEntity; const L: TLayerInfo;
                            Tiles: TTileSource; SolidThreshold: Integer;
                            DeltaY, DeltaX: Integer;
                            Scrolling: Boolean): Integer;
var
  Edge, MoveLayer, MoveEnt, Cross, Col, LastCol, Row, Tile: Integer;
begin
  Result := TILE_NONE;
  if (DeltaY = 0) or (L.TileW = 0) or (L.TileH = 0) then
    Exit;

  if DeltaY < 0 then
    Edge := E.Raw[EF_BOX_OFS_Y] - HalfExtent(E.Raw[EF_EXTENT_Y])
            + E.Raw[EF_TILE_OFS_Y]
  else
    Edge := HalfExtent(E.Raw[EF_EXTENT_Y]) - E.Raw[EF_BOX_OFS_Y]
            + E.Raw[EF_TILE_OFS_Y] - 1;

  if Scrolling then
  begin
    MoveLayer := DeltaY;
    MoveEnt   := 0;
  end
  else
  begin
    MoveLayer := 0;
    MoveEnt   := DeltaY;
  end;

  Cross := OriginPixel(L.OriginX) + OriginPixel(E.Raw[EF_POS_X] + DeltaX);
  Col := (Cross - HalfExtent(E.Raw[EF_EXTENT_X])
          + E.Raw[EF_BOX_OFS_X] + E.Raw[EF_TILE_OFS_X]) div L.TileW;
  LastCol := (Cross + HalfExtent(E.Raw[EF_EXTENT_X])
              - E.Raw[EF_BOX_OFS_X] + E.Raw[EF_TILE_OFS_X] - 1) div L.TileW;

  Row := (OriginPixel(L.OriginY + MoveLayer)
          + OriginPixel(E.Raw[EF_POS_Y] + MoveEnt) + Edge) div L.TileH
         - TILE_BIAS_TILES;

  while Col <= LastCol do
  begin
    Tile := Tiles.TileAt(Col - TILE_BIAS_TILES, Row);
    if Tile >= SolidThreshold then
      Exit(Tile);
    Inc(Col);
  end;
end;

{ 0x00402AC4. Delphi's Random(N). }
function DelphiRandom(N: Integer): Integer;
begin
  RandomSeed := Cardinal(RandomSeed * RANDOM_MULT + 1);
  Result := Integer(Cardinal((UInt64(Cardinal(N)) * UInt64(RandomSeed)) shr 32));
end;

function TEntityWorld.RandomBelow(N: Integer): Integer;
begin
  Result := DelphiRandom(N);
end;

function TEntityWorld.TileAtX(const E: TEntity; Delta: Integer;
                             Scrolling: Boolean): Integer;
begin
  if Tiles = nil then
    Exit(TILE_NONE);
  Result := EntityTileCollideX(E, Layer, Tiles, SolidThreshold, Delta, 0,
                               Scrolling);
end;

function TEntityWorld.TileAtY(const E: TEntity; Delta: Integer;
                             Scrolling: Boolean): Integer;
begin
  if Tiles = nil then
    Exit(TILE_NONE);
  Result := EntityTileCollideY(E, Layer, Tiles, SolidThreshold, Delta, 0,
                               Scrolling);
end;

function TEntityWorld.EdgeDistX(const E: TEntity; Delta: Integer): Integer;
begin
  Result := TileEdgeDistX(E, Layer, Delta);
end;

function TEntityWorld.EdgeDistY(const E: TEntity; Delta: Integer): Integer;
begin
  Result := TileEdgeDistY(E, Layer, Delta);
end;

function TEntityWorld.AxisX: Integer;
begin
  Result := 0;
end;

function TEntityWorld.AxisY: Integer;
begin
  Result := 0;
end;

function TEntityWorld.ConfirmPressed: Boolean;
begin
  Result := False;
end;

{ The scan both sweeps share: the first live, solid, non-self entity whose box
  overlaps Box. Returns its slot, or SLOT_NONE. }
function TEntityWorld.FindBlockingSolid(const E: TEntity; const Box: TBox;
                                        SoftKind: Integer; SkipSoft,
                                        AgainstPlayer: Boolean;
                                        out Other: TBox): Integer;
var
  First, Last, Slot, Mine: Integer;
  O: PEntity;
begin
  Result := SLOT_NONE;
  if Pool = nil then
    Exit;
  Mine := E.Raw[EF_SLOT];
  if AgainstPlayer then
  begin
    First := 0;
    Last := 0;
  end
  else
  begin
    First := SOLID_SCAN_FIRST;
    Last := SOLID_SCAN_LAST;
  end;

  for Slot := First to Last do
  begin
    if Slot = Mine then
      Continue;
    O := Pool.Entity(Slot);
    if (O^.Raw[EF_ALIVE] and $FF) = 0 then
      Continue;
    if O^.Raw[EF_SOLID] = 0 then
      Continue;
    { The air dash goes through a particular kind of solid. }
    if (E.Raw[EF_STATE] = SOLID_STATE_AIRDASH)
       and (O^.Raw[EF_VULN_KIND] = SOLID_PHASE_VULN) then
      Continue;
    if (O^.Raw[EF_SOLID] = SoftKind) and SkipSoft then
      Continue;

    Other := EntityBox(O^, 1, 1);
    if RectOverlap(Box, Other, 0, 0) then
      Exit(Slot);
  end;
end;

{ Both sweeps end the same way: only the player fires a push-against event,
  and each axis reads its own input. }
procedure TEntityWorld.MaybePushEvent(Slot, Blocker, Axis: Integer);
var
  EventId, Op: Integer;
begin
  if Slot <> 0 then
    Exit;
  EventId := Pool.Entity(Blocker)^.Raw[EF_EVENT_ID];
  Op := EventOpcode(EventId);
  if ((Op = EVENT_OPCODE_PUSH) and (Axis <> 0))
  or ((Op = EVENT_OPCODE_PUSH_CONFIRM) and ConfirmPressed) then
    BeginEvent(EventId, EVENT_BEGIN_FROM_DESTROY);
end;

{ Entity_SolidCollideX @ 0x00456B4C. }
function TEntityWorld.SolidCollideX(const E: TEntity; Delta: Integer;
                                    SkipSoft: Boolean;
                                    AgainstPlayer: Boolean): Boolean;
var
  Mine, Other: TBox;
  Moved: TEntity;
  Blocker: Integer;
begin
  Result := False;
  if ((E.Raw[EF_ALIVE] and $FF) = 0) or (Delta = 0) then
    Exit;

  { The box is built from the entity as it WOULD be after the move on this
    axis only; the other axis stays where it is. }
  Moved := E;
  Inc(Moved.Raw[EF_POS_X], Delta);
  Mine := EntityBox(Moved, 1, 1);

  Blocker := FindBlockingSolid(E, Mine, SOLID_SOFT_IN_X, SkipSoft,
                               AgainstPlayer, Other);
  if Blocker = SLOT_NONE then
    Exit;

  if Mine.L < Other.L then
    PushX := -Abs(Mine.R - Other.L) shl POSITION_SHIFT
  else
    PushX := Abs(Mine.L - Other.R) shl POSITION_SHIFT;
  Result := True;

  MaybePushEvent(E.Raw[EF_SLOT], Blocker, AxisX);
end;

{ Entity_SolidCollideY @ 0x00456E0C. }
function TEntityWorld.SolidCollideY(const E: TEntity; Delta: Integer;
                                    SkipSoft: Boolean;
                                    AgainstPlayer: Boolean): Boolean;
var
  Mine, Other: TBox;
  Moved: TEntity;
  Blocker, Gap: Integer;
  O: PEntity;
begin
  OnTopOfSolid := False;
  Result := False;
  { NOTE: no `Delta = 0` guard, unlike the X sweep. That is in the original
    and it is what keeps an entity resting on a platform aware of it. }
  if (E.Raw[EF_ALIVE] and $FF) = 0 then
    Exit;

  Moved := E;
  Inc(Moved.Raw[EF_POS_Y], Delta);
  Mine := EntityBox(Moved, 1, 1);

  Blocker := FindBlockingSolid(E, Mine, SOLID_SOFT_IN_Y, SkipSoft,
                               AgainstPlayer, Other);
  if Blocker = SLOT_NONE then
    Exit;

  if Mine.T < Other.T then
  begin
    { Coming down onto it. }
    Gap := Abs(Mine.B - Other.T);
    if Gap < SOLID_TOP_TOLERANCE then
    begin
      OnTopOfSolid := True;
      Pool.SetField(Blocker, EF_RIDDEN, 1);
    end;

    { Riding: the horizontal offset between the two, WITH this frame's layer
      scroll folded in, so a rider is carried along by a moving platform. }
    O := Pool.Entity(Blocker);
    PushX := ((OriginPixel(O^.Raw[EF_POS_X] + Layer.DeltaX)
               - HalfExtent(O^.Raw[EF_EXTENT_X]))
              - (OriginPixel(E.Raw[EF_POS_X])
                 - HalfExtent(E.Raw[EF_EXTENT_X]))) shl POSITION_SHIFT;

    PushY := -Gap shl POSITION_SHIFT;
  end
  else
    PushY := Abs(Mine.T - Other.B) shl POSITION_SHIFT;
  Result := True;

  MaybePushEvent(E.Raw[EF_SLOT], Blocker, AxisY);
end;

function TEntityWorld.EventOpcode(EventId: Integer): Integer;
begin
  Result := -1;                    { no event table attached }
end;

function TEntityWorld.EventProgressIndex(EventId: Integer): Integer;
begin
  Result := -1;
end;

procedure TEntityWorld.BeginEvent(EventId, Arg: Integer);
begin
end;

procedure TEntityWorld.ClearEventEntity(EventId: Integer);
begin
end;

procedure TEntityWorld.SetProgress(Index: Integer);
begin
end;

{ Entity_Destroy @ 0x00461400. }
procedure TEntityWorld.DestroyEntity(var E: TEntity; DropLoot: Boolean);
var
  Owner, Child, EventId, Op, Flag: Integer;
begin
  { A dying projectile hands a shot back to whoever fired it. }
  if (E.Raw[EF_CLASS] = DESTROY_CLASS_PROJECTILE) and (Pool <> nil) then
  begin
    Owner := E.Raw[EF_OWNER];
    Pool.SetField(Owner, EF_SHOTS, Pool.Field(Owner, EF_SHOTS) - 1);
  end;

  { A parent takes its children with it. Recursive, and deliberately WITHOUT
    loot - the children were never separately earned. }
  if (E.Raw[EF_CLASS] = DESTROY_CLASS_PARENT) and (Pool <> nil) then
  begin
    Child := E.Raw[EF_CHILD_A];
    if Child <> 0 then
      DestroyEntity(Pool.Entity(Child)^, False);
    Child := E.Raw[EF_CHILD_B];
    if Child <> 0 then
      DestroyEntity(Pool.Entity(Child)^, False);
  end;

  if DropLoot then
  begin
    if E.Raw[EF_NO_DROP] = 0 then
      MaybeDropItem(E);
    if E.Raw[EF_CLASS] = DESTROY_CLASS_SHATTER then
      SpawnDebris(E, DEBRIS_SHATTER);
  end;

  EventId := E.Raw[EF_EVENT_ID];
  if EventId <> -1 then
  begin
    Op := EventOpcode(EventId);
    if (Op = EVENT_OPCODE_DESTROY) and DropLoot then
      BeginEvent(EventId, EVENT_BEGIN_FROM_DESTROY);
    if (Op = EVENT_OPCODE_FLAG) and DropLoot then
    begin
      Flag := EventProgressIndex(EventId);
      if Flag >= 0 then
        SetProgress(Flag);
    end;
    { Cleared whatever the opcode was, and whether or not loot was dropped,
      so the event can place another entity next time the camera comes near. }
    ClearEventEntity(EventId);
  end;

  E.Raw[EF_ALIVE] := 0;
  E.Raw[EF_DEPTH] := 0;
  E.Raw[EF_HP] := 0;

  if E.Raw[EF_SPRITE] <> SPRITE_NONE then
  begin
    if Sprites <> nil then
    begin
      Sprites.SetVisible(E.Raw[EF_SPRITE], False);
      Sprites.SetDepth(E.Raw[EF_SPRITE], 0);
    end;
    E.Raw[EF_SPRITE] := SPRITE_NONE;
  end
  else
    E.Raw[EF_SPRITE] := SPRITE_NONE;
end;

{ Entity_MaybeDropItem @ 0x004617FC. }
procedure TEntityWorld.MaybeDropItem(const E: TEntity);
var
  Roll, Slot: Integer;
begin
  Roll := RandomBelow(DROP_ROLL);
  if Roll <= DROP_THRESHOLD then
    Exit;

  { No layer delta here, unlike Entity_SpawnDebris - the drop is placed at the
    parent's position exactly. Whether that is deliberate or an oversight in
    the original cannot be told from the code; it is reproduced either way. }
  Slot := Spawn(EKIND_MINOR, DROP_TYPE,
                E.Raw[EF_POS_X] - POSITION_BIAS,
                E.Raw[EF_POS_Y] - POSITION_BIAS);
  if Slot = SLOT_NONE then
    Exit;                        { the original does not check; see SpawnDebris }

  SetSpawnField(Slot, EF_TIMER, DROP_TIMER);
  SetSpawnField(Slot, EF_VEL_Y, DROP_LIFT);
  SetSpawnField(Slot, EF_FLAG1C, Ord(Roll > DROP_RARE));
end;

{ Entity_SpawnDebris @ 0x00461874. }
procedure TEntityWorld.SpawnDebris(const E: TEntity; Kind: Integer);
var
  I, Slot, Dir, Speed: Integer;
begin
  { The sound. Only kind 0 consults the terrain, and only two terrains say
    anything - which is what identifies 3 and 4 as the water areas. }
  if Kind = DEBRIS_SPLASH then
  begin
    if TerrainId = TERRAIN_WATER_A then
      PlaySound(SND_WATER01)
    else if TerrainId = TERRAIN_WATER_B then
      PlaySound(SND_WATER02);
  end
  else if Kind = DEBRIS_IMPACT then
    PlaySound(SND_BOM02)
  else if Kind = DEBRIS_SHATTER then
    PlaySound(SND_BOM04);

  for I := 0 to EF_DEBRIS_SPEEDS - 1 do
  begin
    { The layer delta is SUBTRACTED from the spawn position. The particle is
      created after this frame's scroll has been applied to its parent but
      before Entity_UpdateAll carries it along too, so taking the delta back
      out is what stops it being scrolled twice on its first frame. }
    Slot := Spawn(EKIND_MINOR, EF_DEBRIS_TYPE,
                  E.Raw[EF_POS_X] - POSITION_BIAS - Layer.DeltaX,
                  E.Raw[EF_POS_Y] - POSITION_BIAS - Layer.DeltaY);

    { The original does NOT check this. On a full pool Entity_Spawn returns -1
      and it writes the five particles at Entities[-1], i.e. over whatever sits
      before the pool. Not reproduced - there is nothing to reproduce it INTO -
      and the difference only shows on a pool that is already full. }
    if Slot = SLOT_NONE then
      Continue;

    SetSpawnField(Slot, EF_STATE, Kind + 1);

    Dir := HalfExtent(DirVelX(RandomBelow(DIR_COUNT)));
    Speed := RandomBelow(DEBRIS_SPEED_MAX) + 1;
    SetSpawnField(Slot, EF_VEL_X, Dir * Speed);
    SetSpawnField(Slot, EF_VEL_Y, (I + 4) * -DEBRIS_LIFT);

    SetSpawnField(Slot, EF_SCREEN_SPACE, 0);
    SetSpawnField(Slot, EF_DEPTH, DEBRIS_DEPTH);

    { The two effect kinds pick their frame differently: one at random, one
      by position in the burst, so a shatter fans through its frames in order. }
    if Kind = DEBRIS_IMPACT then
      SetSpawnField(Slot, EF_FLAG1C, RandomBelow(2))
    else if Kind = DEBRIS_SHATTER then
      SetSpawnField(Slot, EF_FLAG1C, I);
  end;
end;

function EntityBox(const E: TEntity; ScaleX, ScaleY: Integer): TBox;
var
  W, H: Integer;
begin
  W := E.Raw[EF_EXTENT_X] * ScaleX;
  H := E.Raw[EF_EXTENT_Y] * ScaleY;
  { OriginPixel, not EntityPixelX - see the header: the bias stays in. }
  Result.L := OriginPixel(E.Raw[EF_POS_X]) - HalfExtent(W)
              + E.Raw[EF_HITBOX_INSET_X];
  Result.T := OriginPixel(E.Raw[EF_POS_Y]) - HalfExtent(H)
              + E.Raw[EF_HITBOX_INSET_Y];
  Result.R := Result.L + W - 2 * E.Raw[EF_HITBOX_INSET_X];
  Result.B := Result.T + H - 2 * E.Raw[EF_HITBOX_INSET_Y];
end;

function EntitiesOverlap(const A, B: TEntity;
                         ScaleX, ScaleY: Integer): Boolean;
var
  BoxA, BoxB: TBox;
begin
  BoxA := EntityBox(A, 1, 1);
  BoxB := EntityBox(B, ScaleX, ScaleY);
  Result := RectOverlap(BoxA, BoxB, 0, 0);
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

function TEntityPool.Entity(Slot: Integer): PEntity;
begin
  if (Slot < 0) or (Slot >= ENTITY_COUNT) then
    raise Exception.CreateFmt('Entity: slot %d out of range', [Slot]);
  Result := @FSlots[Slot];
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
