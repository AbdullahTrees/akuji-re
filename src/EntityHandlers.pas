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
      0x0045A540  type 27  the save point
      0x00458274  Entity_TouchPickup - the Mana Stone
      0x00458490  Entity_TouchHeal
      0x00458404  Entity_TouchLife
      0x00458138  Player_TakeDamage
      0x00457880  Entity_PlayerTouch - the dispatcher over all seven kinds
      0x00457AB4  Entity_TakeProjectileHits
      0x0045A5D4  type 32  the invisible emitter
      0x0045A698  type 33  the explosion it spawns
      0x0045A7BC  type 36  the falling item a kill drops
      0x0045A944  type 16  the sign
      0x0045AA60  type 22  a one-sprite entity that can die
      0x0045A0E4  type 8   the four-frame puff a move leaves behind
      0x0045A50C  type 26  the pickup's rising GET
      0x00459EB4  type 3   a moving three-frame puff, sprite row by heading
      0x00459F1C  type 4   two frames, then gone
      0x00459F6C  type 5   an effect that hangs off another entity
      0x0045A020  type 6   the explosion's spark
      0x0045A08C  type 7   four frames in one of two rows
      0x0045A120  type 9   a particle that circles
      0x0045A184  type 10  six frames, then gone
      0x0045A1C0  type 11  a four-frame loop that never ends
      0x0045A20C  type 12  the same, slower
      0x0045A24C  type 13  debris - four states, four motions
      0x0045A95C  type 15  a switch, thrown once
      0x0045A9D4  type 17  nothing at all
      0x0045A9D0  type 19  nothing at all
      0x0045AA10  type 21  an oscillating platform
      0x0045AA78  type 23  a torch, and the two flames it holds
      0x0045A580  type 28  four frames, gated on its variant
      0x0045AB64  type 29  an idle that speeds up when the player is close
      0x0045ABD8  type 30  a patroller, and the first thing that reads
                           DIFFICULTY
      0x0045AC94  type 31  a floating attacker with a six-state machine
      0x0045A848  type 37  something that drops, lands and lies there
      0x0045AF2C  type 34  type 31's shot
      0x0045AFA8  type 35  type 31's telegraph - and what moves it to state 4
      0x00459A0C  type 2   the PLAYER'S SHOT
      0x0045B0CC  type 38  a turret, and the second thing to use a child as
                           its own state machine
      0x0045B260  type 39  its shot, which charges before it flies
      0x0045B3EC  type 40  a springboard - the first thing that writes to the
                           PLAYER
      0x0045B62C  type 41  a hopper
      0x0045B7C4  type 42  a boss - six states, five difficulty tables
      0x0045BBD8  type 43  armour, chosen by variant
      0x0045BC00  type 44  type 42's shot

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

  { --- Type 27 @ 0x0045A540, the save point -----------------------------
    Two frames alternating on a nine-frame cycle, and nothing else. The handler
    does not know it is a save point - what makes it one is the EVENT, and the
    data says so about as loudly as data can: type 27 appears exactly ONCE in
    each of 43 stages, always with opcode 1 (touch plus a button), always with
    no ParamA argument, and with a ParamB that is byte-identical in all 43:

        0000-03-0000 / 0003-13 / 0003-03-0001

    which is: say line 0; then if flag 3 is set, sub-op 13 - SAVE; then say
    line 1. Forty-three stages, one save point each, the same script every time.

    Its table has one reader and two entries, and the handler cycles the frame
    mod 2, so the extent is flush from both directions. }
  SAVE_POINT_FRAMES = 2;
  SAVE_POINT_ADDR   = $0046BE24;
  SAVE_POINT_PTR    = $0046D18C;
  SAVE_POINT_SPRITES: array[0..SAVE_POINT_FRAMES - 1] of Integer = (84, 85);
  SAVE_POINT_TICKS  = 8;   { advance when the count EXCEEDS it, so every 9 }

  { The one-shot drop applied on the first update, in 1/32 pixel - five pixels.
    Events place things on a tile boundary and this settles them onto it. }
  ITEM_SETTLE_DROP = $A0;
  ITEM_FRAME_TICKS = 4;   { advance when the timer EXCEEDS this, so every 5 }

  { Slots this handler uses. int 5 is the drawn sprite id, the same slot
    Player_Update writes - it is entity-wide, not the player's. int 6 is the
    variant. Both sit outside the two 10-int blocks. }
  { EF_ANIM_ID and EF_VARIANT moved to Entities.pas - they are core entity
    fields, not handler-local ones, and the event spawn walk needs them too. }

  { --- The two touch handlers @ 0x00458274 and 0x00458490 ---------------
    Both are what EF_TOUCH_KIND 2 and 5 reach, and both follow the same shape:
    change the player's state, set the progress flag named by the event's
    ParamB, put a type 26 effect where the entity was, and destroy themselves.
    The effect's VARIANT is how one entity type shows three different pickups.

    The Mana Stone's variant is also its value: 0 adds one, 1 adds ten. }
  PICKUP_EFFECT_TYPE = $1A;   { 26 }
  MANA_SMALL = 1;
  MANA_LARGE = 10;
  PICKUP_FX_NORMAL  = 0;
  PICKUP_FX_LEVELUP = 1;
  PICKUP_FX_HEAL    = 3;

  { --- Entity_PlayerTouch @ 0x00457880 ----------------------------------
    Seven touch kinds, dispatched after one box test. Three guards come first
    and all three matter:

      the player must not be invulnerable, UNLESS the kind is 3 - so kind 3
        reaches through invulnerability where nothing else does
      the entity's own EF_TIMER must be 0
      a kind of 0 is not a touch at all

    Opcode 1 - "walk up and press" - needs the player STANDING (EF_VEL_Y = 0),
    Up held, and Inp.AxisYNegative still clear, which is the edge. The latch is
    set on the frame after, so holding Up does not retrigger.

    The original's return value is a local that is never assigned, so callers
    read whatever was on the stack. Entity_UpdateAll ignores it, and this is a
    procedure. }
  TOUCH_KIND_HURT       = 1;
  TOUCH_KIND_MANA       = 2;
  TOUCH_KIND_THRU_INVULN = 3;
  TOUCH_KIND_LIFE       = 4;
  TOUCH_KIND_HEAL       = 5;
  TOUCH_KIND_STOMP      = 6;
  TOUCH_KIND_HURT_HARD  = 7;

  { --- Player_TakeDamage @ 0x00458138 -----------------------------------
    Ninety frames of invulnerability, knocked into state 8, thrown up and
    away from whichever way it is facing.

    The lost-life particles spawn at the HUD LIFE ICON, not at the player:
    x = Lives * 16 + 20 pixels, y = 16. They are type 13, which the type table
    marks screen-space, so they do not scroll - the icon is visibly knocked off
    the display. Three per life lost, and the loop stops early if lives run
    out before the damage does. }
  PLAYER_HIT_INVULN = $5A;    { 90 frames, in BOTH timers }
  PLAYER_HIT_STATE  = 8;      { knockback }
  PLAYER_HIT_LIFT   = -$40;
  PLAYER_HIT_PUSH   = $40;
  PLAYER_HIT_FX     = 8;      { spawned only out of a glide or air dash }
  SOULS_PER_LIFE    = 3;
  HUD_LIFE_X0       = 20;     { pixels }
  HUD_LIFE_STEP     = 16;
  HUD_LIFE_Y        = 16;

  { --- Type 36, the falling item @ 0x0045A7BC ---------------------------
    What Entity_MaybeDropItem drops. Gravity while airborne, then a snap onto
    the tile edge it lands on - the pattern Entities.pas already quoted from
    this function, and every line of it checks out.

    Its two sprites are chosen by EF_FLAG1C, which is the field
    Entity_MaybeDropItem writes its rarity roll into: the same flag that makes
    Entity_TouchLife give a full refill instead of one life also picks which
    of the two sprites the thing wears on the way down. Two entries, one
    reader, and exactly two values written - flush three ways.

    After landing the velocity keeps being added, but Entity_TileCollideY's
    zero-delta guard is what settles it: once the snap leaves the velocity at
    0 the query stops reporting a collision and the item sits still. }
  DROP_SPRITE_COUNT = 2;
  DROP_TABLE_ADDR   = $0046BE54;
  DROP_TABLE_PTR    = $0046CE18;
  DROP_SPRITES: array[0..DROP_SPRITE_COUNT - 1] of Integer = (100, 101);

  { --- The effect family, types 3..13 -----------------------------------
    Eleven handlers built from the same four moves: write a sprite from a
    table indexed by a frame counter, tick that counter every N frames,
    optionally move, and destroy at the end. What differs is which of those
    each one does, and it is worth having them side by side because the
    differences are the only content.

        type  frames  ticks  motion                     ends
          3      3      5    POS_X += VEL_X             yes
          4      2      3    none                       yes
          5      4      5    follows its OWNER          yes
          6      4      9    POS += VEL                 yes
          7      4      5    none                       yes
          9      1      -    circles, one step a frame  no
         10      6      3    none                       yes
         11      4      3    none                       NO - it loops
         12      4      4    none                       NO - it loops
         13    varies       four states, see below      3 of 4

    Types 11 and 12 never call Entity_Destroy at all. They are not leaks: an
    entity that leaves the screen is culled by Entity_UpdateAll, which is a
    different mechanism from an effect timing out, and these two rely on it.

    Types 9 and 13 are the only two that also run in GS_PLAY_ALT (100) rather
    than GS_PLAY alone.

    THE SPRITE TABLES all sit in one run at 0x0046BC5C and their extents come
    from the next table's start, which is the discipline tools/table_bounds.py
    exists to enforce - see the 16-versus-2 error it was written after. Two of
    them are two ROWS rather than a flat list, indexed by a second field with
    a stride of four:

        type 6   row from block A[1], which the explosion sets when it spawns
                 the spark - so the same table serves two burst colours
        type 7   row from the VARIANT }
  T3_FRAMES = 3;  T3_TICKS = 4;   { advance when the count EXCEEDS, so every 5 }
  T3_TABLE_ADDR = $0046BC5C;
  T3_SPRITES: array[0..1, 0..T3_FRAMES - 1] of Integer =
    ((20, 21, 22),      { moving left  }
     (23, 24, 25));     { moving right }

  T4_FRAMES = 2;  T4_TICKS = 2;
  T4_TABLE_ADDR = $0046BC74;
  T4_SPRITES: array[0..T4_FRAMES - 1] of Integer = (26, 27);

  T5_FRAMES = 4;  T5_TICKS = 4;
  T5_TABLE_ADDR = $0046BC7C;
  T5_SPRITES: array[0..T5_FRAMES - 1] of Integer = (200, 201, 202, 203);

  T6_FRAMES = 4;  T6_TICKS = 8;   { every 9 - the slowest of the family }
  T6_ROWS = 2;
  T6_TABLE_ADDR = $0046BC8C;
  T6_SPRITES: array[0..T6_ROWS - 1, 0..T6_FRAMES - 1] of Integer =
    ((204, 205, 206, 207), (208, 209, 210, 211));

  T7_FRAMES = 4;  T7_TICKS = 4;
  T7_ROWS = 2;
  T7_TABLE_ADDR = $0046BCAC;
  T7_SPRITES: array[0..T7_ROWS - 1, 0..T7_FRAMES - 1] of Integer =
    ((40, 41, 42, 43), (233, 234, 235, 236));

  T9_TABLE_ADDR = $0046BCDC;
  T9_SPRITE = 212;

  T10_FRAMES = 6;  T10_TICKS = 2;
  T10_TABLE_ADDR = $0046BCE0;
  T10_SPRITES: array[0..T10_FRAMES - 1] of Integer =
    (213, 214, 215, 216, 217, 218);

  T11_FRAMES = 4;  T11_TICKS = 2;
  T11_TABLE_ADDR = $0046BCF8;
  T11_SPRITES: array[0..T11_FRAMES - 1] of Integer = (64, 65, 66, 65);
  T11_DEATH_TIMER = 2;

  T12_FRAMES = 4;  T12_TICKS = 3;
  T12_TABLE_ADDR = $0046BD08;
  T12_SPRITES: array[0..T12_FRAMES - 1] of Integer = (67, 68, 69, 70);

  { The one-shot latch types 4, 5, 6 and 7 all set on their first play frame.
    EF_STATE marks it done and the death timer is what actually removes them
    if their animation somehow does not. }
  EFFECT_LATCH_TIMER = $F0;

  { --- Type 13, the debris ----------------------------------------------
    Four states, and the state is set by whoever spawns it - see
    Entity_SpawnDebris's DEBRIS_* kinds in Entities.pas.

      0  a splash: rises against a growing downward pull, three frames at
         nine ticks, then gone
      1  a shard: gravity, twelve frames at five ticks, then gone. Its sprite
         table depends on the STAGE TERRAIN - one for terrain 3 and another
         for terrain 4, and no write at all for any other terrain, which
         leaves whatever sprite it already had
      2  and 3: gravity and drift, no animation and NO end. Like types 11 and
         12 they rely on being culled off-screen

    Two things reproduced rather than tidied. States 1, 2 and 3 add VEL_Y to
    POS_Y TWICE in the same frame - the original really does write
    `POS_Y += VEL_Y` on two separate lines - so debris falls at double the
    rate its velocity says. And the gravity is applied BEFORE the first add,
    so the first frame already moves. }
  T13_STATE_SPLASH = 0;
  T13_STATE_SHARD  = 1;
  T13_SPLASH_FRAMES = 3;  T13_SPLASH_TICKS = 8;
  T13_SHARD_FRAMES = 12;  T13_SHARD_TICKS  = 4;
  T13_GRAVITY = 2;
  T13_TERMINAL = $200;
  T13_SPLASH_TABLE_ADDR = $0046BD18;
  T13_SHARD3_TABLE_ADDR = $0046BD24;
  T13_SHARD4_TABLE_ADDR = $0046BD5C;
  T13_STATE2_TABLE_ADDR = $0046BD54;
  T13_STATE3_TABLE_ADDR = $0046BD8C;
  T13_SPLASH_SPRITES: array[0..T13_SPLASH_FRAMES - 1] of Integer =
    (219, 220, 221);
  T13_SHARD3_SPRITES: array[0..T13_SHARD_FRAMES - 1] of Integer =
    (240, 241, 240, 241, 242, 243, 242, 243, 244, 245, 244, 245);
  T13_SHARD4_SPRITES: array[0..T13_SHARD_FRAMES - 1] of Integer =
    (256, 257, 256, 257, 258, 259, 258, 259, 260, 261, 260, 261);
  { States 2 and 3 never advance their frame counter, so only element 0 of
    each is ever read. The rest of both tables is unreachable from here. }
  T13_STATE2_SPRITE = 231;
  T13_STATE3_SPRITE = 283;
  T13_TERRAIN_SHARD3 = 3;
  T13_TERRAIN_SHARD4 = 4;

  { --- Types 15, 21, 23, 28 and 29, the furniture -----------------------
    Five things that sit in a room rather than fly through it, and two more -
    17 and 19 - whose handlers are a single RET. Those two are not missing:
    the switch has an arm for them and the arm returns immediately, which is
    a different fact from having no arm at all, and HANDLER_ADDR distinguishes
    them from types 0, 18 and 20.

    TYPE 15 is a switch, and it is the only handler that writes to the EVENT
    TABLE. Thrown, it plays a sound, changes to its second sprite, and sets
    its own event's opcode to 9 - which triggers nothing - so a switch stays
    thrown without needing a progress flag.

    TYPE 21 oscillates. EF_FACING is not a direction index here, it is a
    signed SPEED, and it is negated every block-A[1] frames; EF_STATE picks
    the axis, 0 for vertical and 1 for horizontal. That is exactly what
    ParamA's 'R' letter configures - it sets EF_FACING and block A[1] - so a
    placement carries the speed and the half-period of the swing.

    TYPE 23 is a torch. On state 1 it spawns TWO children, types 11 and 12,
    16 and 22 pixels above itself, and remembers them in EF_CHILD_A and
    EF_CHILD_B; on state 3 it destroys them both. That is why types 11 and 12
    loop for ever with no Entity_Destroy of their own - they are the flame,
    and the torch owns their lifetime.

    Both spawns subtract the LAYER DELTA from the position. The children are
    placed after Entity_UpdateAll has already carried this frame's scroll into
    the parent, so without it they would be carried twice and lag the torch by
    one frame's scroll.

    TYPE 28 does nothing at all unless its variant is 0 - both the sprite and
    the animation are inside that test - so a variant-1 placement is inert.

    TYPE 29 animates at two speeds: ten ticks a frame normally, four when the
    player's box overlaps its own, tested at three times width and one times
    height. It also drops itself 2 pixels on its very first frame. }
  T15_TABLE_ADDR = $0046BE78;
  T15_SPRITES: array[0..1] of Integer = (61, 62);
  T15_SOUND = $0E;
  T15_THROWN_OPCODE = 9;

  T21_TABLE_ADDR = $0046BE80;
  T21_SPRITE = 59;
  T21_AXIS_VERTICAL   = 0;
  T21_AXIS_HORIZONTAL = 1;

  T23_TABLE_ADDR = $0046BE88;
  T23_SPRITE = 63;
  T23_FLAME_LOW_TYPE  = 11;
  T23_FLAME_HIGH_TYPE = 12;
  T23_FLAME_LOW_LIFT  = $200;    { 16 px above the torch }
  T23_FLAME_HIGH_LIFT = $2C0;    { 22 px }

  T28_FRAMES = 4;  T28_TICKS = 8;
  T28_TABLE_ADDR = $0046BE2C;
  T28_SPRITES: array[0..T28_FRAMES - 1] of Integer = (279, 280, 281, 282);
  T28_DEATH_TIMER = 2;

  T29_FRAMES = 4;
  T29_TICKS_IDLE  = 10;
  T29_TICKS_CLOSE = 4;
  T29_TABLE_ADDR = $0046BE8C;
  T29_SPRITES: array[0..T29_FRAMES - 1] of Integer = (87, 86, 88, 86);
  T29_SETTLE = $40;              { 2 px, once, on its first frame }
  T29_NEAR_SCALE_X = 3;
  T29_NEAR_SCALE_Y = 1;

  { --- Types 30, 31 and 37 ----------------------------------------------
    The first handlers that read the player's DIFFICULTY, and they read it
    through tables indexed by it rather than by branching on it.

    TYPE 30 patrols. On its first frame, and only on difficulty 2, it DOUBLES
    its speed and HALVES its turn period - so on hard it covers four times the
    ground between turns. Its sprite row comes from the sign of that speed,
    the same two-ifs-no-else shape type 3 has.

    TYPE 31 floats, circles and attacks on a six-state machine, and three
    separate difficulty tables drive it: how much HP it gains over the base,
    how long it waits before attacking, and how fast it fires while attacking.
    All three are (easy, normal, hard) triples.

      state 0  spawn: add the HP bonus, rise 4 px and left 1 px, go to 1
      state 1  drift in a circle, one heading step a frame, moving by HALF the
               X component only; count up and go to state 2 after
               wait[diff] * HP + 20 frames
      state 2  spawn a type-35 child in mode 0 pointing at itself, go to 3
      state 3  held - nothing here moves it; the child does
      state 4  the attack: for 180 frames, every eighth frame past
               rate[diff], play sound 0x17 and spawn a type-34 shot along
               block A[1]'s heading
      state 5  spawn a type-35 child in mode 1 and go to 6, which is inert

    Reaching state 4 is not this handler's doing - nothing here sets it. The
    type-35 child does, which is why state 3 looks like a dead end and is not.
    Losing all HP forces the sprite to frame 4 wherever it is.

    TYPE 37 drops. It puffs on arrival, falls at gravity 4 to a terminal 0x200,
    lands on the first solid tile with sound 0x1B, and animates a five-frame
    loop throughout. Its frame counter wraps with a div AND a mod, and the
    quotient is left in EAX and returned - dead, like type 16's. }
  T30_FRAMES = 2;  T30_TICKS = 8;
  T30_TABLE_ADDR = $0046BE9C;
  T30_SPRITES: array[0..1, 0..T30_FRAMES - 1] of Integer =
    ((89, 90),      { moving left  }
     (91, 92));     { moving right }
  T30_SETTLE = $40;
  T30_HARD = 2;

  T31_FRAMES = 4;
  T31_HURT_FRAME = 4;
  T31_TICKS = 8;
  T31_TABLE_ADDR = $0046BEDC;
  T31_SPRITES: array[0..T31_HURT_FRAME] of Integer = (500, 501, 502, 501, 503);
  T31_HP_BONUS_ADDR = $0046BED0;
  T31_WAIT_ADDR     = $0046BEC4;
  T31_RATE_ADDR     = $0046BEB8;
  T31_HP_BONUS: array[0..2] of Integer = (0, 10, 20);
  T31_WAIT:     array[0..2] of Integer = (8, 6, 4);
  T31_RATE:     array[0..2] of Integer = (60, 30, 10);
  T31_WAIT_BASE   = $14;    { added to wait[diff] * HP }
  T31_ATTACK_LEN  = $B4;    { 180 frames of firing }
  T31_FIRE_EVERY  = 8;
  T31_FIRE_SOUND  = $17;
  T31_MARKER_TYPE = $23;    { 35 - the child that drives the state machine }
  T31_SHOT_TYPE   = $22;    { 34 }
  T31_RISE  = $100;         { 8 px up on spawn }
  T31_DRIFT = $80;          { 4 px left }

  T37_FRAMES = 5;  T37_TICKS = 6;
  T37_TABLE_ADDR = $0046BE5C;
  T37_SPRITES: array[0..T37_FRAMES - 1] of Integer = (222, 223, 224, 225, 226);
  T37_PUFF_TYPE = 8;
  T37_DROP      = $100;     { 8 px, once, on arrival }
  T37_TIMERS    = $3C;      { both timers armed to 60 }
  T37_GRAVITY   = 4;
  T37_TERMINAL  = $200;
  T37_LAND_SOUND = $1B;

  { --- Types 34 and 35, type 31's two children --------------------------
    Between them these close the thread type 31 left open. Nothing in type 31
    sets its own state 4; type 35 does.

    TYPE 35 is the telegraph - eight frames at five ticks, played FORWARDS in
    mode 0 and BACKWARDS in mode 1, off the same eight-entry table read as
    `table[7 - frame]`. It watches its owner and destroys itself the moment
    the owner's HP reaches 0, so a parent killed mid-wind-up takes its
    telegraph with it.

    When the forward run finishes it does three things to its OWNER: plays
    sound 0x18, sets the owner's state to 4 - the attack - and writes
    Angle_Between(owner, PLAYER) into the owner's block A[1]. That is the aim,
    taken once at the end of the telegraph rather than tracked, which is why
    type 31's shots all leave along one heading however the player moves.

    The backward run just puts the owner back to state 1.

    TYPE 34 is the shot. It moves at DOUBLE the direction table's step on both
    axes, and its five frames advance on a DIFFICULTY-KEYED divisor of 8, 10
    or 12 - so the shot animates FASTER on easy, and since it dies at the end
    of its animation it also has a shorter range there. That is backwards from
    what the other difficulty tables do and it is what the binary says.

    Its frame test is `count mod rate = 0`, not a countdown, so the counter
    runs on and the frames land on multiples. The division's quotient is left
    in EAX and returned - dead, like type 16's and type 37's. }
  T34_FRAMES = 5;
  T34_TABLE_ADDR = $0046BEF0;
  T34_SPRITES: array[0..T34_FRAMES - 1] of Integer = (512, 513, 514, 515, 516);
  T34_RATE_ADDR = $0046BEAC;
  T34_RATE: array[0..2] of Integer = (8, 10, 12);
  T34_SPEED = 2;

  T35_FRAMES = 8;  T35_TICKS = 4;
  T35_TABLE_ADDR = $0046BF04;
  T35_SPRITES: array[0..T35_FRAMES - 1] of Integer =
    (504, 505, 506, 507, 508, 509, 510, 511);
  T35_MODE_WIND_UP   = 0;
  T35_MODE_WIND_DOWN = 1;
  T35_SOUND = $18;
  T35_OWNER_ATTACK = 4;
  T35_OWNER_IDLE   = 1;

  { --- Type 2, the player's shot ----------------------------------------
    What Player_Update fires, and the state it carries is the weapon: 0 and 1
    for the two ordinary shots and 2 for the charge, which is Player.pas's
    WEAPONS table column ProjState arriving here.

    Its sprite table is three rows of four, and each row is TWO frames going
    right followed by TWO going left - so the row index is the state and the
    half is the sign of the velocity, the same two-ifs-no-else shape types 3
    and 30 have.

    Only the charge does anything extra: it ACCELERATES, adding four in
    whatever direction it is already going, and it drops a type-7 trail every
    fifth frame.

    Its lifetime is a countdown in EF_CHILD_B rather than a frame limit, and
    running out is a soft end - it leaves one last type-7 puff. Hitting a wall
    is the loud one: SIX type-6 sparks, each with a random heading out of 64
    and a random speed of one or two half-steps per axis, drawn separately so
    the scatter is an ellipse. The sparks' block A[1] carries 1 for a charge
    shot and 0 otherwise, which is what selects between type 6's two sprite
    rows - so a charged impact throws different-coloured sparks.

    Note the speed multiplier is Random(2) + 1, one or two. The explosion at
    type 33 uses Random(3) + 1 for the same idiom, so these are not the same
    burst and the difference is deliberate. }
  T2_STATES = 3;
  T2_FRAMES = 2;  T2_TICKS = 4;
  T2_TABLE_ADDR = $0046BC2C;
  { [state][0..1] going right, [state][2..3] going left. }
  T2_SPRITES: array[0..T2_STATES - 1, 0..3] of Integer =
    ((28, 29, 30, 31), (32, 33, 34, 35), (36, 37, 38, 39));
  T2_CHARGE_STATE = 2;
  T2_CHARGE_ACCEL = 4;
  T2_TRAIL_EVERY  = 4;    { every fifth frame - the test is `> 4` }
  T2_TRAIL_TYPE   = 7;
  T2_TRAIL_LIFT   = $80;  { 4 px above the shot }
  T2_SPARK_TYPE   = 6;
  T2_SPARKS       = 6;
  T2_SPARK_SPEED_MAX = 2; { Random(2) + 1, so 1..2 - NOT type 33's 1..3 }

  { --- Types 38 and 39, a turret and its shot ---------------------------
    The same division of labour types 31 and 35 have, and seeing it twice is
    what makes it a pattern rather than a quirk: the parent holds a state it
    cannot leave on its own, and the CHILD is what moves it on.

    TYPE 38 faces by its VARIANT - facing is variant shifted left five, so 0
    is heading 0 and 1 is heading 32, the two opposite directions - and the
    variant is also its sprite row. Five states:

      0  settle 1 px and take the facing from the variant
      1  wait, but ONLY while on screen. Entity_IsOffScreen(self, 2) gates the
         counter, so a turret you cannot see never counts down and never
         fires. The wait itself is difficulty-keyed: 120, 60 or 30 frames
      2  wind up, four frames at five ticks
      3  after 30 more frames, spawn the shot eight direction-steps ahead and
         0xC0 above, hand it this entity as its owner and its own heading as
         the shot's velocity, then go to 4
      4  held. Nothing here leaves it - the shot does
      5  wind the animation back down and return to 1

    TYPE 39 charges before it flies. In state 0 it plays four frames at a
    difficulty-keyed rate of 4, 2 or 1 ticks - so on hard it charges four
    times as fast - and at the end it plays sound 0x19 and, IF ITS OWN HP IS
    ZERO, puts its owner into state 5. That condition is the interesting one:
    a shot that still has HP leaves its parent stuck in state 4.

    In state 1 it flies at a difficulty-keyed multiple of its velocity - 2, 2
    or 3 - looping frames 4..9, and ends either on a wall or after 60 frames.
    Either way it leaves a type-7 puff with VARIANT 1, which is that type's
    second sprite row. }
  T38_VARIANTS = 2;
  T38_FRAMES = 4;  T38_TICKS = 4;
  T38_TABLE_ADDR = $0046BF24;
  T38_SPRITES: array[0..T38_VARIANTS - 1, 0..T38_FRAMES - 1] of Integer =
    ((110, 111, 112, 113), (106, 107, 108, 109));
  T38_WAIT_ADDR = $0046BF44;
  T38_WAIT: array[0..2] of Integer = (120, 60, 30);
  T38_SETTLE = $20;
  T38_FACING_SHIFT = 5;      { variant 0 -> heading 0, variant 1 -> heading 32 }
  T38_OFFSCREEN_MARGIN = 2;
  T38_FIRE_DELAY = $1E;      { 30 frames after the wind-up }
  T38_SHOT_TYPE = $27;       { 39 }
  T38_SHOT_AHEAD = 8;        { direction steps in front }
  T38_SHOT_LIFT = $C0;

  T39_FRAMES = 10;
  T39_CHARGE_FRAMES = 4;
  T39_FLIGHT_FIRST = 4;      { the flight loop is 4..9 }
  T39_FLIGHT_TICKS = 2;
  T39_TABLE_ADDR = $0046BF50;
  T39_SPRITES: array[0..T39_FRAMES - 1] of Integer =
    (227, 228, 229, 230, 246, 247, 248, 249, 250, 251);
  T39_WIND_ADDR  = $0046BF84;
  T39_SPEED_ADDR = $0046BF78;
  T39_WIND:  array[0..2] of Integer = (4, 2, 1);
  T39_SPEED: array[0..2] of Integer = (2, 2, 3);
  T39_LAUNCH_SOUND = $19;
  T39_OWNER_WIND_DOWN = 5;
  T39_RANGE = $3C;           { 60 frames }
  T39_PUFF_TYPE = 7;
  T39_PUFF_VARIANT = 1;

  { --- Type 40, the springboard -----------------------------------------
    Two entities in one, by variant, and the first handler that reaches into
    the PLAYER'S ENTITY and rewrites it.

    VARIANT 1 is a shooter. It only acts while on screen, counts a cooldown
    down to zero, and then fires - but only if the player's box overlaps its
    own at EIGHT times width and two times height, which is a very wide, flat
    trigger area rather than a touch. The shot is a type 39 with its HP set to
    1, which is what stops it releasing this parent the way type 38's does -
    see type 39, where only a zero-HP shot writes to its owner. So the same
    shot type serves two parents with different lifetimes.

    Its aim is Compare(self.x, player.x) shifted left five - a direction, not
    an angle - and a zero is corrected to 0x20, so a shot fired at a player
    standing exactly in line still goes somewhere.

    STATE 2 is the launch, and it is worth reading in full because everything
    it touches belongs to somebody else:

        player.EF_VEL_Y   := -0xD0
        player.EF_CHILD_A := abs(player.EF_VEL_X) * input.AxisX, if any
        player.EF_STATE   := 2
        player.block A[1] := 1
        player.EF_RIDDEN  := 0
        player.block A[8] := 1

    The horizontal one is the interesting line: the player keeps the SPEED it
    arrived with but takes the DIRECTION from whatever is being held at the
    moment of the launch, so you can turn round on the spring. With no input
    the field is left alone entirely.

    Nothing here sets state 2. The touch handler does. }
  T40_VARIANTS = 2;
  T40_FRAMES = 4;
  T40_TABLE_ADDR = $0046BF90;
  T40_SPRITES: array[0..T40_VARIANTS - 1, 0..T40_FRAMES - 1] of Integer =
    ((123, 124, 125, 124), (192, 193, 194, 193));
  T40_COOLDOWN_ADDR = $0046BFB0;
  T40_COOLDOWN: array[0..2] of Integer = (240, 180, 180);
  T40_SETTLE = $40;
  T40_SHOOTER_VARIANT = 1;
  T40_OFFSCREEN_MARGIN = 2;
  T40_TRIGGER_SCALE_X = 8;   { a wide, flat trigger - not a touch }
  T40_TRIGGER_SCALE_Y = 2;
  T40_SHOT_TYPE = $27;       { 39, but with HP 1 so it never frees this parent }
  T40_SHOT_LIFT = $A0;
  T40_AIM_SHIFT = 5;
  T40_AIM_ZERO = $20;        { a shot straight at the player still goes right }
  T40_LAUNCH_VY = -$D0;
  T40_LAUNCH_SOUND = $1A;
  T40_BOUNCE_FRAMES = 3;  T40_BOUNCE_TICKS = 4;  T40_BOUNCE_CYCLES = 4;
  T40_BOUNCE_TIMER = $78;

  { --- Type 41, the hopper ----------------------------------------------
    Crouches, springs, and turns round every so many landings.

      0  settle 1 px, and on HARD ONLY double its speed - the same one-line
         scaling type 30 has, and the second instance of it
      1  idle, and ONLY while on screen: a four-frame loop and a countdown of
         30, 20 or 10 frames by difficulty. At the end, sound 0x21, jump
         velocity -0x60, and frame 4
      2  five ticks of anticipation, then frame 5
      3  airborne: drift by its speed, gravity 4 to a terminal 0x200, and on
         landing snap flush to the tile edge, go back to 1, and count the
         landing. After block A[1] landings it reverses

    The turn counter is EF_CHILD_B and the landing test uses the same
    edge-distance snap the falling item does. Like type 38, the idle counts
    only while visible - so a hopper off screen is frozen mid-crouch rather
    than hopping in place. }
  T41_FRAMES = 4;  T41_TICKS = 6;
  T41_TABLE_ADDR = $0046BFBC;
  T41_SPRITES: array[0..5] of Integer = (126, 127, 128, 127, 129, 130);
  T41_WAIT_ADDR = $0046BFD4;
  T41_WAIT: array[0..2] of Integer = (30, 20, 10);
  T41_SETTLE = $20;
  T41_HARD = 2;
  T41_OFFSCREEN_MARGIN = 2;
  T41_JUMP_SOUND = $21;
  T41_JUMP_VY = -$60;
  T41_CROUCH_FRAME = 4;
  T41_AIR_FRAME = 5;
  T41_CROUCH_TICKS = 4;
  T41_GRAVITY = 4;
  T41_TERMINAL = $200;

  { --- Type 42, a boss --------------------------------------------------
    The largest handler so far, and the first whose timings scale with its own
    HP as well as with the difficulty - so a boss that has taken damage acts
    faster, which is a difficulty curve inside a single fight.

      0  spawn: add an HP bonus of 0, 20 or 40 by difficulty, drop 8 px and
         start moving right at 0x20
      1  patrol: bounce off walls by negating its speed, and bob vertically by
         stepping one heading every four frames and taking the Y component as
         the velocity. Leaves after HP * 10 + 120 frames with sound 0x23
      2  rise: step the heading every frame - so it climbs in a tightening
         curve - for 120, 60 or 30 frames by difficulty, then drop
      3  fall: gravity 4 to a terminal 0x200. On landing, sound 4, snap flush,
         and FIRE A FAN of shots: count + 1 type-44s, each taking its heading
         from a shared angle table (-1, 1, -2, 2, -3, 3) shifted left five.
         The count is 1, 3 or 5 by difficulty, so easy gets two shots and hard
         gets six
      4  recover: hold, re-snapping to the floor each frame, and go back up
         after (HP / 10) * (1, 3 or 5) + 30 frames. Every third recovery it
         goes to state 5 instead
      5  retreat: rise 1 px a frame for 60 frames, then back to patrol

    EF_CHILD_B is a free-running frame counter that every state resets, and
    EF_SHOTS - normally an owner's live-shot count - is reused here as the
    recovery counter. }
  T42_FRAMES = 4;  T42_TICKS = 8;
  T42_TABLE_ADDR = $0046C010;
  T42_SPRITES: array[0..6] of Integer = (500, 501, 502, 501, 502, 503, 504);
  T42_HP_BONUS_ADDR = $0046C004;
  T42_HP_BONUS: array[0..2] of Integer = (0, 20, 40);
  T42_RISE_LEN_ADDR = $0046BFE0;
  T42_RISE_LEN: array[0..2] of Integer = (120, 60, 30);
  T42_SHOTS_ADDR = $0046BFF8;
  T42_SHOTS: array[0..2] of Integer = (1, 3, 5);   { plus one - so 2, 4 or 6 }
  T42_ANGLES_ADDR = $0046C05C;
  T42_ANGLES: array[0..5] of Integer = (-1, 1, -2, 2, -3, 3);
  T42_RECOVER_ADDR = $0046BFEC;
  T42_RECOVER: array[0..2] of Integer = (30, 20, 10);
  T42_DROP = $100;
  T42_SPEED = $20;
  T42_BOB_EVERY = 4;
  T42_PATROL_BASE = $78;      { HP * 10 + this }
  T42_PATROL_SOUND = $23;
  T42_LAND_SOUND = 4;
  T42_RISE_VY = -$C0;
  T42_RETREAT_VY = -$A0;
  T42_GRAVITY = 4;
  T42_TERMINAL = $200;
  T42_SHOT_TYPE = $2C;        { 44 }
  T42_SHOT_LIFT = $400;
  T42_ANGLE_SHIFT = 5;
  T42_FALL_FRAME = 4;
  T42_LAND_FRAME = 5;
  T42_LAND_LAST  = 6;
  T42_RECOVER_BASE = $1E;
  T42_RECOVERIES = 2;         { every third one retreats }
  T42_RETREAT_STEP = $20;
  T42_RETREAT_LEN = $3C;

  { --- Types 43 and 44 --------------------------------------------------
    TYPE 43 is four instructions and one of them is the point:

        EF_VULN_KIND := variant + 0x5A

    which lands exactly on the armour block Entity_TakeProjectileHits already
    knows - VULN_ARMOUR_1 is 0x5A, VULN_ARMOUR_2 0x5B, VULN_IMMUNE_ALT 0x5C
    and VULN_ONLY_POWER3 0x5D. So one entity type covers all four armours and
    the placement's variant picks which, which is why those four constants sit
    contiguously rather than being scattered like the other vulnerability
    kinds. Written EVERY frame, not once, so nothing can leave it armoured
    differently.

    TYPE 44 is type 42's shot: an eight-frame loop at three ticks, thrown
    upward at -0xB0 and pulled down at gravity 2 while drifting by whatever
    horizontal velocity it was spawned with. It has no Entity_Destroy at all -
    like types 9, 11 and 12 it relies on being culled off screen. }
  T43_VARIANTS = 4;
  T43_TABLE_ADDR = $0046C02C;
  T43_SPRITES: array[0..T43_VARIANTS - 1] of Integer = (121, 122, 179, 442);
  T43_VULN_BASE = $5A;      { VULN_ARMOUR_1 - see the block above }

  T44_FRAMES = 8;  T44_TICKS = 2;
  T44_TABLE_ADDR = $0046C03C;
  T44_SPRITES: array[0..T44_FRAMES - 1] of Integer =
    (505, 506, 507, 508, 509, 510, 511, 512);
  T44_LAUNCH_VY = -$B0;
  T44_GRAVITY = 2;
  T44_TERMINAL = $200;

  { --- Types 8 and 26, the two self-destructing effects -----------------
    Both are spawned by something else, play a short animation, and call
    Entity_Destroy on themselves. Between them they are why the screen filled
    up with copies of Akuji: an effect whose handler does not exist never
    reaches its Entity_Destroy, so it stays alive for ever wearing the anim id
    Entity_Spawn gave it - column 0 of the type table, which is 0 for all 81
    types, and sprite 0 is Akuji standing.

    Nothing was leaking. The entities were simply immortal.

    Type 8 is the puff the player's glide and air dash leave behind -
    Player.pas spawns it at 0x004585A8's two Spawn(2, 8, ...) calls. Four
    frames, five ticks each.

    Type 26 is the "GET" that rises out of a collected Mana Stone.
    Entity_TouchPickup spawns it and sets its VARIANT to say which kind of
    pickup it was: 0 for an ordinary stone, 1 when the stone completed a
    target and the player gained a life. So the two sprites are the two
    messages, and the variant is the whole difference.

    Note the index in each is unchecked in the original and cannot overflow
    anyway: the frame that would run off the end is the frame that destroys
    the entity, and the sprite is written before that. The clamps below are
    unreachable rather than corrective - the same situation type 33 is in. }
  TYPE8_FRAMES      = 4;
  TYPE8_TICKS       = 4;    { advance when the count EXCEEDS it, so every 5 }
  TYPE8_TABLE_ADDR  = $0046BCCC;
  TYPE8_SPRITES: array[0..TYPE8_FRAMES - 1] of Integer = (50, 51, 52, 53);

  TYPE26_LIFT       = $10;  { 16 sub-pixels a frame, straight up }
  TYPE26_LIFETIME   = $1E;  { destroyed when the count EXCEEDS 30 }
  TYPE26_TABLE_ADDR = $0046BE14;
  TYPE26_VARIANTS   = 2;    { only 0 and 1 are ever spawned }
  TYPE26_SPRITES: array[0..TYPE26_VARIANTS - 1] of Integer = (83, 99);

  { --- Types 16 and 22, the one-sprite entities -------------------------
    Two of the shortest handlers in the game. Each writes ONE anim id and
    stops; neither animates, and neither reads its own state.

    Their sprite is not a literal - it is the first int of a table, reached
    through a pointer, exactly as the animated types' tables are. Both tables
    sit in the same run at 0x0046BE3C onwards:

        0x0046BE74  54   type 16, the sign
        0x0046BE84  60   type 22

    Only element 0 is ever read, because the handler indexes nothing. That
    makes the extent of these two tables unknowable from their readers, and
    unimportant: a single unconditional read cannot run off the end. Recorded
    rather than guessed at - see tools/table_bounds.py on why a length that
    nothing pins is not a length. }
  SIGN_SPRITE       = 54;
  SIGN_SPRITE_ADDR  = $0046BE74;
  TYPE22_SPRITE     = 60;
  TYPE22_SPRITE_ADDR = $0046BE84;

  { --- Type 33, the explosion @ 0x0045A698 ------------------------------
    Six frames of sprite on a seven-tick cycle, and on its FIRST update it
    throws out six sparks of type 6.

    Each spark takes one random heading of 64 and is given a velocity from
    BOTH direction tables at that same index - which is what makes the burst
    radial rather than axis-aligned, and is the detail an earlier reading of
    this function already had. The two speed multipliers are drawn
    SEPARATELY though, so a spark's X and Y speeds are independent: the
    scatter is an ellipse of random eccentricity, not a circle.

    Its sprite table is six consecutive ids with one reader, and the handler
    cycles exactly six frames - flush from both directions. }
  BOOM_FRAMES     = 6;
  BOOM_TICKS      = 6;    { advance when the count EXCEEDS it, so every 7 }
  BOOM_TABLE_ADDR = $0046BE3C;
  BOOM_TABLE_PTR  = $0046CE30;
  BOOM_SPRITES: array[0..BOOM_FRAMES - 1] of Integer = (93, 94, 95, 96, 97, 98);
  BOOM_SPARK_TYPE = 6;
  BOOM_SPARKS     = 6;
  BOOM_SPEED_MAX  = 3;    { RandomBelow(3) + 1, so 1..3, per axis }

  { --- Type 32, the emitter @ 0x0045A5D4 --------------------------------
    An invisible spawner - one of the three types with no sprite - that reads
    its whole configuration out of block A and keeps its state in block B.
    Every one of those seven slots is now confirmed by the code:

      A[1] $09  frames between spawns    B[0] $12  countdown to the next
      A[2] $0A  how many in all          B[1] $13  how many so far
      A[3] $0B  scatter radius           B[2] $14  countdown to the next sound
      A[4] $0C  frames between sounds

    It spawns type 33 explosions scattered by Random(r * 16) - r * 8 PIXELS on
    each axis, so plus or minus r * 8 - quarter tiles, not tiles.

    Entity_UpdateDying seeds it two ways, which is how one emitter type gives
    two different deaths: class 1 gets 8, 2, 1, 2 - a small pair close in - and
    class 2 gets 4, 32, 4, 1 - a long wide barrage with a sound every frame.

    The exhaustion test is `A[2] < B[1]` AFTER the increment, so an emitter
    configured for N spawns N + 1 times. Reproduced. }
  EMIT_EVERY       = $09;   { A[1] }
  EMIT_TOTAL       = $0A;   { A[2] }
  EMIT_RADIUS      = $0B;   { A[3] }
  EMIT_SOUND_EVERY = $0C;   { A[4] }
  EMIT_NEXT        = $12;   { B[0] }
  EMIT_COUNT       = $13;   { B[1] }
  EMIT_SOUND_NEXT  = $14;   { B[2] }
  EMIT_SPAWN_TYPE  = $21;   { 33, the explosion }
  EMIT_RADIUS_SHIFT = 4;    { Random(r shl 4), centred by r * 8 }

  { --- Entity_TakeProjectileHits @ 0x00457AB4 ---------------------------
    A wide switch on the TARGET's EF_VULN_KIND, and the projectile's own
    EF_STATE is its POWER. Three of the arms do something other than damage:

      7  REFLECTS the shot. It spawns a fresh type 2 travelling the other way,
         with the same power, a 600-frame life, and a touch kind that makes it
         hostile - 7 for power 2, otherwise 1. It also sizes the new shot's
         collision box: all four percentage columns to 30 for power 2 and 60
         otherwise, which is the only place in the game seen writing those at
         runtime.
      6  SPINS the target a fifth of a turn (24 of 64) and sets int $15.
      5  SHOVES it sideways at the shot's direction times 64 and steps its
         frame, wrapping 0..3.

    The rest are immunity, and several are CONDITIONAL ON THE SHOT'S POWER,
    which is what makes them armour rather than invulnerability:

      2, $5C   immune outright
      $5A      immune to power below 1
      $5B      immune to power below 2
      $5D      immune UNLESS the power is exactly 3
      4        immune unless the power is exactly 4

    A shot of power 3 is skipped entirely unless the target's kind is $5D, so
    that power exists to open exactly one kind of door.

    On a real hit the target loses the shot's EF_HP - the same slot being
    damage on a projectile and hit points on a target - and gets 8 frames in
    both timers. Powers 2 and 3 PIERCE: they are not destroyed and can hit
    again. Power 4 is destroyed WITH loot.

    Only the special arms return early; an ordinary hit carries on scanning,
    so several shots can land in one pass until the target's HP reaches 0. }
  VULN_IMMUNE        = 2;
  VULN_ONLY_POWER4   = 4;
  VULN_SHOVE         = 5;
  VULN_SPIN          = 6;
  VULN_REFLECT       = 7;
  VULN_ARMOUR_1      = $5A;   { immune below power 1 }
  VULN_ARMOUR_2      = $5B;   { immune below power 2 }
  VULN_IMMUNE_ALT    = $5C;
  VULN_ONLY_POWER3   = $5D;

  HIT_SPARK_TYPE = 10;
  REFLECT_TYPE   = 2;
  REFLECT_LIFE   = 600;
  REFLECT_BOX_STRONG = $1E;   { the four percentage columns, power 2 }
  REFLECT_BOX_WEAK   = $3C;
  SPIN_MARK      = $EC;       { 236, into int $15 }
  SPIN_TURN      = $18;       { 24 of 64 }
  SHOVE_SPEED_SHIFT = 6;      { direction shl 6 }
  SHOVE_FRAMES   = 4;         { the frame wraps 0..3 }
  HIT_INVULN     = 8;
  PIERCING_POWER_A = 2;       { these are not consumed by the hit }
  PIERCING_POWER_B = 3;
  LOOT_POWER       = 4;       { this one is destroyed WITH loot }

  { The per-target hit sound, at 0x00468E34 through the pointer 0x0046CC48.
    Four entries, four readers, all of them in this one function. }
  HIT_SOUND_COUNT = 4;
  HIT_SOUND_ADDR  = $00468E34;
  HIT_SOUND_PTR   = $0046CC48;
  HIT_SOUNDS: array[0..HIT_SOUND_COUNT - 1] of Integer =
    (SND_KIN01, SND_SHOT01, SND_PI02, SND_MOVE01);

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

{ 0x00458274. The Mana Stone. The counter climbs by the entity's variant, and
  when it reaches MANA_TARGETS[TargetIndex] the player gains a life of maximum
  AND is refilled - which is what tk001.dat describes in words. }
procedure EntityTouchPickup(var E: TEntity; var P: TPlayerState;
                            World: TEntityWorld);

{ 0x00458490. A full heal, and nothing else. }
procedure EntityTouchHeal(var E: TEntity; var P: TPlayerState;
                          World: TEntityWorld);

{ 0x00458404. The life pickup. Its variant comes from EF_FLAG1C, which is the
  very field Entity_MaybeDropItem sets from its rarity roll - so a dropped
  item's rare flag is what decides +1 life against a full refill. }
procedure EntityTouchLife(var E: TEntity; var P: TPlayerState;
                          World: TEntityWorld);

{ 0x00458138. The player takes a hit. }
procedure PlayerTakeDamage(var Player: TEntity; var P: TPlayerState;
                           Damage: Integer; World: TEntityWorld);

{ 0x00457880. The touch dispatcher. }
procedure PlayerTouch(var E, Player: TEntity; var P: TPlayerState;
                      var Inp: TInputState; World: TEntityWorld);

{ 0x00457AB4. Everything the actor slots have thrown at this entity. }
procedure TakeProjectileHits(var E: TEntity; World: TEntityWorld);

{ 0x0045A43C. See ITEM24_SPRITES above. World is needed only for the heartbeat,
  which only variant 8 has. }
procedure EntityUpdate_Type24(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045A7BC. The falling item. See DROP_SPRITES above. }
procedure EntityUpdate_Type36_FallingItem(var E: TEntity; AGameState: Integer;
                                          World: TEntityWorld);

{ 0x0045B3EC. A springboard, and a shooter, by variant. See the T40_ block -
  its launch rewrites six fields of the player's entity. }
procedure EntityUpdate_Type40(var E: TEntity; AGameState: Integer;
                              var Inp: TInputState; World: TEntityWorld);

{ 0x0045BBD8. Armour. Its VARIANT selects which of the four armour
  vulnerability kinds it has - see the T43_ block. }
procedure EntityUpdate_Type43(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045BC00. Type 42's shot: thrown up, pulled down, culled off screen. }
procedure EntityUpdate_Type44(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045B7C4. A boss. Six states, and its timings scale with its own HP as
  well as with the difficulty - see the T42_ block. }
procedure EntityUpdate_Type42(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045B62C. A hopper. See the T41_ block. }
procedure EntityUpdate_Type41(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045B0CC. A turret. Waits only while on screen, then fires a type 39. }
procedure EntityUpdate_Type38(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045B260. Type 38's shot: charges, then flies. }
procedure EntityUpdate_Type39(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x00459A0C. The player's shot. See the T2_ block above. }
procedure EntityUpdate_Type02(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045AF2C. Type 31's shot. Double speed, difficulty-keyed animation. }
procedure EntityUpdate_Type34(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045AFA8. Type 31's telegraph, and the thing that puts its owner into the
  attack state. See the T35_ block. }
procedure EntityUpdate_Type35(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045ABD8. A patroller that gets meaner on hard - see the T30_ block. }
procedure EntityUpdate_Type30(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045AC94. A floating attacker. Six states, three difficulty tables, and
  a child entity that drives the transition this handler cannot make itself. }
procedure EntityUpdate_Type31(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045A848. Drops, lands, and lies there animating. }
procedure EntityUpdate_Type37(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045A95C. A switch. The only handler that writes to the event table. }
procedure EntityUpdate_Type15(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045A9D4 and 0x0045A9D0. Both are a single RET. The switch HAS an arm for
  these two types and the arm does nothing, which is not the same as types 0,
  18 and 20, which have no arm at all. Written out so the difference survives
  in code rather than only in HANDLER_ADDR. }
procedure EntityUpdate_Type17(var E: TEntity);
procedure EntityUpdate_Type19(var E: TEntity);

{ 0x0045AA10. An oscillating platform - see the T21_ block above for why
  EF_FACING is a speed here and not a heading. }
procedure EntityUpdate_Type21(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045AA78. A torch: it owns the two flame entities above it. }
procedure EntityUpdate_Type23(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045A580. Four frames, and inert unless its variant is 0. }
procedure EntityUpdate_Type28(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045AB64. An idle that animates faster when the player is close. }
procedure EntityUpdate_Type29(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x00459EB4. A moving puff whose sprite row is chosen by which way it is
  going - and by the SIGN of its velocity, so a puff with no horizontal speed
  at all keeps whatever sprite it had. }
procedure EntityUpdate_Type03(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x00459F1C. Two frames and gone. }
procedure EntityUpdate_Type04(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x00459F6C. An effect that hangs off another entity: its position is its
  OWNER's plus an offset, and the offset shrinks toward zero along its heading
  every frame, so it retracts into whatever fired it. }
procedure EntityUpdate_Type05(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045A020. The spark the explosion throws out. Its sprite ROW comes from
  block A[1], which EntityUpdate_Type33_Explosion sets when it spawns one. }
procedure EntityUpdate_Type06(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045A08C. Four frames in one of two rows, chosen by the variant. }
procedure EntityUpdate_Type07(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045A120. A particle that circles: one direction step a frame, moving by
  the full X component and HALF the Y, which is what makes the path an ellipse
  rather than a circle. It never destroys itself - it leaves the screen. }
procedure EntityUpdate_Type09(var E: TEntity; AGameState: Integer);

{ 0x0045A184. Six frames and gone. }
procedure EntityUpdate_Type10(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045A1C0. A four-frame loop with no end, and a death timer it keeps
  topping back up. }
procedure EntityUpdate_Type11(var E: TEntity; AGameState: Integer);

{ 0x0045A20C. The same loop one tick slower, without the timer. }
procedure EntityUpdate_Type12(var E: TEntity; AGameState: Integer);

{ 0x0045A24C. The debris. Four states - see the T13_ block above. }
procedure EntityUpdate_Type13(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045A0E4. The four-frame puff. See TYPE8_SPRITES above. }
procedure EntityUpdate_Type08(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045A50C. The rising GET a collected Mana Stone leaves. Its VARIANT says
  which of the two messages to show, and Entity_TouchPickup sets it. }
procedure EntityUpdate_Type26(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045A944. The sign - what the player reads. Two instructions of
  substance, and no game-state guard at all: it writes its sprite whether the
  game is playing, paused or running a script.

  It then computes GameState - GS_PLAY into EAX and returns, which nothing
  reads - the dispatcher calls every arm as a procedure. That is the tail of a
  comparison whose branch is gone, and it is left as a comment rather than
  written as code, the same way Entity_CheckKillTiles's constant False is.

  Until this existed the sign kept the anim id Entity_Spawn gave it, which is
  the type table's column 0 - and that column is 0 for every type in the game,
  so an untranslated entity wears sprite 0. Sprite 0 is Akuji standing, which
  is why the signs looked like the player. }
procedure EntityUpdate_Type16_Sign(var E: TEntity);

{ 0x0045AA60. One sprite, and it can die - the only difference from the sign
  is the Entity_UpdateDying call, whose result this one also discards. }
procedure EntityUpdate_Type22(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045A698. The explosion. See BOOM_SPRITES above. }
procedure EntityUpdate_Type33_Explosion(var E: TEntity; AGameState: Integer;
                                        World: TEntityWorld);

{ 0x0045A5D4. The invisible emitter. See EMIT_EVERY above for the block-A
  configuration it runs off. }
procedure EntityUpdate_Type32_Emitter(var E: TEntity; AGameState: Integer;
                                      World: TEntityWorld);

{ 0x0045A4F0. One table lookup. It takes no game state because it does not read
  any - it is the only handler that runs identically whatever the game is doing. }
procedure EntityUpdate_Type25(var E: TEntity);

{ 0x0045A540. The save point's idle animation. See SAVE_POINT_SPRITES for why
  it is the save point, which is not visible from this function at all. }
procedure EntityUpdate_Type27(var E: TEntity; AGameState: Integer);

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
  { The touch pass. This is a variable rather than a direct call for one
    reason: --selftest-entities swaps a counting stub in to check the slot
    boundary and the type-68 special case in isolation. It is NOT a
    placeholder any more - the initialization section points it at the real
    PlayerTouch. }
  TTouchProc = procedure(var E, Player: TEntity; var P: TPlayerState;
                         var Inp: TInputState; World: TEntityWorld);

  { The projectile pass, a variable for the same reason as the touch pass:
    so a test can count calls without needing the real thing. }
  TEntityCallback = procedure(var E: TEntity; World: TEntityWorld);

var
  EntityPlayerTouch:        TTouchProc = nil;
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
    World.DestroyEntity(E, True);
  end;

  Result := True;
end;

{ Both handlers set the progress flag their event names, spawn the same
  effect, and destroy themselves; only the middle differs. }
function PickupCommon(var E: TEntity; World: TEntityWorld): Integer;
var
  Flag: Integer;
begin
  Flag := World.EventProgressIndex(E.Raw[EF_EVENT_ID]);
  if Flag >= 0 then
    World.SetProgress(Flag);
  Result := World.Spawn(EKIND_MINOR, PICKUP_EFFECT_TYPE,
                        E.Raw[EF_POS_X] - POSITION_BIAS,
                        E.Raw[EF_POS_Y] - POSITION_BIAS);
end;

procedure EntityTouchPickup(var E: TEntity; var P: TPlayerState;
                            World: TEntityWorld);
var
  Slot: Integer;
begin
  case E.Raw[EF_VARIANT] of
    0: Inc(P.Counter, MANA_SMALL);
    1: Inc(P.Counter, MANA_LARGE);
  end;

  Slot := PickupCommon(E, World);

  { The comparison happens AFTER the counter has already gone up, so a stone
    that takes you exactly to the target counts as reaching it. }
  if P.Counter < ManaTarget(P.TargetIndex) then
  begin
    if E.Raw[EF_VARIANT] = 0 then
      World.PlaySound(SND_GET01)
    else if E.Raw[EF_VARIANT] = 1 then
      World.PlaySound(SND_GET02);
    World.SetSpawnField(Slot, EF_VARIANT, PICKUP_FX_NORMAL);
  end
  else
  begin
    Inc(P.TargetIndex);
    Inc(P.MaxLives);
    P.Lives := P.MaxLives;
    World.PlaySound(SND_POWER02);
    World.SetSpawnField(Slot, EF_VARIANT, PICKUP_FX_LEVELUP);
  end;

  World.DestroyEntity(E, False);
end;

procedure EntityTouchHeal(var E: TEntity; var P: TPlayerState;
                          World: TEntityWorld);
var
  Slot: Integer;
begin
  World.PlaySound(SND_KACHI02);
  P.Lives := P.MaxLives;
  Slot := PickupCommon(E, World);
  World.SetSpawnField(Slot, EF_VARIANT, PICKUP_FX_HEAL);
  World.DestroyEntity(E, False);
end;

procedure EntityTouchLife(var E: TEntity; var P: TPlayerState;
                          World: TEntityWorld);
var
  Slot, Variant: Integer;
begin
  { EF_FLAG1C, not EF_VARIANT - the field a dropped item carries its rarity in. }
  Variant := E.Raw[EF_FLAG1C];
  if Variant = 0 then
    Inc(P.Lives)
  else if Variant = 1 then
    P.Lives := P.MaxLives;
  { Note there is no clamp on the +1 path. Lives can exceed MaxLives here and
    the original does not stop it; whatever bounds it does so elsewhere. }
  World.PlaySound(SND_GET01);
  Slot := PickupCommon(E, World);
  World.SetSpawnField(Slot, EF_VARIANT, Variant + 2);
  World.DestroyEntity(E, False);
end;

procedure PlayerTakeDamage(var Player: TEntity; var P: TPlayerState;
                           Damage: Integer; World: TEntityWorld);
var
  Left, I, Slot: Integer;
begin
  { Being hit out of a glide or an air dash leaves a puff behind. }
  if (Player.Raw[EF_STATE] = 6) or (Player.Raw[EF_STATE] = 7) then
    World.Spawn(EKIND_MINOR, PLAYER_HIT_FX,
                Player.Raw[EF_POS_X] - POSITION_BIAS,
                Player.Raw[EF_POS_Y] - POSITION_BIAS);

  World.PlaySound(SND_VOICE01);
  Player.Raw[EF_TIMER] := PLAYER_HIT_INVULN;
  Player.Raw[EF_DEATH_TIMER] := PLAYER_HIT_INVULN;
  Player.Raw[EF_STATE] := PLAYER_HIT_STATE;
  Player.Raw[EF_VEL_Y] := PLAYER_HIT_LIFT;
  { Thrown backwards relative to the way it faces. }
  if Player.Raw[EF_FACING] = 0 then
    Player.Raw[EF_VEL_X] := -PLAYER_HIT_PUSH
  else
    Player.Raw[EF_VEL_X] := PLAYER_HIT_PUSH;

  if Damage <= 0 then
    Exit;
  Left := Damage;
  repeat
    for I := 0 to SOULS_PER_LIFE - 1 do
    begin
      { At the HUD icon, in screen space - the life being knocked off. }
      Slot := World.Spawn(EKIND_MINOR, EF_DEBRIS_TYPE,
                          (P.Lives * HUD_LIFE_STEP + HUD_LIFE_X0) * 32,
                          HUD_LIFE_Y * 32);
      World.SetSpawnField(Slot, EF_FACING,
                          World.RandomBelow(4) + I * 8 + 8);
      World.SetSpawnField(Slot, EF_VEL_Y,
                          World.RandomBelow($10) + Abs(1 - I) * $10 - $20);
    end;
    Dec(P.Lives);
    Dec(Left);
  until (P.Lives = 0) or (Left = 0);
end;

procedure PlayerTouch(var E, Player: TEntity; var P: TPlayerState;
                      var Inp: TInputState; World: TEntityWorld);
var
  Kind, EventId, Op: Integer;
begin
  Kind := E.Raw[EF_TOUCH_KIND];
  if (Player.Raw[EF_ALIVE] and $FF) = 0 then
    Exit;
  { Invulnerability blocks everything except kind 3. }
  if (Player.Raw[EF_TIMER] <> 0) and (Kind <> TOUCH_KIND_THRU_INVULN) then
    Exit;
  if Kind = 0 then
    Exit;
  if E.Raw[EF_TIMER] <> 0 then
    Exit;

  if not EntitiesOverlap(Player, E, 1, 1) then
    Exit;

  EventId := E.Raw[EF_EVENT_ID];
  if EventId <> -1 then
  begin
    Op := World.EventOpcode(EventId);
    if (Op = 0)
    or ((Op = 1) and (Player.Raw[EF_VEL_Y] = 0)
        and (Inp.AxisY < 0) and (not Inp.AxisYNegative)) then
      World.BeginEvent(EventId, EVENT_BEGIN_FROM_DESTROY);
  end;

  case Kind of
    TOUCH_KIND_HURT:      PlayerTakeDamage(Player, P, 1, World);
    TOUCH_KIND_MANA:      EntityTouchPickup(E, P, World);
    TOUCH_KIND_LIFE:      EntityTouchLife(E, P, World);
    TOUCH_KIND_HEAL:      EntityTouchHeal(E, P, World);
    TOUCH_KIND_STOMP:
      { Only while coming DOWN on it - the stomp. }
      if Player.Raw[EF_VEL_Y] > 0 then
        E.Raw[EF_STATE] := 2;
    TOUCH_KIND_HURT_HARD: PlayerTakeDamage(Player, P, 2, World);
  end;
end;

function HitSound(const E: TEntity): Integer;
var
  I: Integer;
begin
  I := E.Raw[EF_HIT_SOUND];
  if (I < 0) or (I >= HIT_SOUND_COUNT) then
    I := 0;                     { the original indexes this unchecked }
  Result := HIT_SOUNDS[I];
end;

procedure TakeProjectileHits(var E: TEntity; World: TEntityWorld);
var
  Slot, Vuln, Power, Dir, NewSlot, EventId, Box: Integer;
  Target, Shot: TBox;
  S: PEntity;
begin
  Vuln := E.Raw[EF_VULN_KIND];
  if (Vuln = 0) or (E.Raw[EF_TIMER] <> 0) or (World.Pool = nil) then
    Exit;

  Target := EntityBox(E, 1, 1);

  for Slot := SLOT_ACTOR_FIRST to SLOT_ACTOR_LAST do
  begin
    S := World.Pool.Entity(Slot);
    Power := S^.Raw[EF_STATE];

    { A power-3 shot is invisible to everything except kind $5D. }
    if not ((Vuln = VULN_ONLY_POWER3) or (Power <> 3)) then
      Continue;
    if (S^.Raw[EF_ALIVE] and $FF) = 0 then
      Continue;
    if S^.Raw[EF_HP] = 0 then          { no damage means not a projectile }
      Continue;
    if (E.Raw[EF_ALIVE] and $FF) = 0 then
      Continue;
    if E.Raw[EF_HP] = 0 then
      Continue;

    Shot := EntityBox(S^, 1, 1);
    if not RectOverlap(Shot, Target, 0, 0) then
      Continue;

    World.Spawn(EKIND_MINOR, HIT_SPARK_TYPE,
                S^.Raw[EF_POS_X] - POSITION_BIAS,
                S^.Raw[EF_POS_Y] - POSITION_BIAS);

    EventId := E.Raw[EF_EVENT_ID];
    if (EventId <> -1) and (World.EventOpcode(EventId) = 6) then
      World.BeginEvent(EventId, EVENT_BEGIN_FROM_DESTROY);

    if Vuln = VULN_REFLECT then
    begin
      NewSlot := World.Spawn(EKIND_MINOR, REFLECT_TYPE,
                             S^.Raw[EF_POS_X] - POSITION_BIAS,
                             S^.Raw[EF_POS_Y] - POSITION_BIAS);
      World.SetSpawnField(NewSlot, EF_VEL_X, -S^.Raw[EF_VEL_X]);
      World.SetSpawnField(NewSlot, EF_STATE, Power);
      World.SetSpawnField(NewSlot, EF_CHILD_B, REFLECT_LIFE);
      World.SetSpawnField(NewSlot, EF_CLASS, 0);
      if Power = PIERCING_POWER_A then
      begin
        World.SetSpawnField(NewSlot, EF_TOUCH_KIND, TOUCH_KIND_HURT_HARD);
        Box := REFLECT_BOX_STRONG;
      end
      else
      begin
        World.SetSpawnField(NewSlot, EF_TOUCH_KIND, TOUCH_KIND_HURT);
        Box := REFLECT_BOX_WEAK;
      end;
      World.SetSpawnField(NewSlot, EF_BOX_PCT_X, Box);
      World.SetSpawnField(NewSlot, EF_BOX_PCT_Y, Box);
      World.SetSpawnField(NewSlot, EF_INSET_PCT_X, Box);
      World.SetSpawnField(NewSlot, EF_INSET_PCT_Y, Box);
      World.PlaySound(HitSound(E));
      World.DestroyEntity(S^, False);
      Exit;
    end;

    if Vuln = VULN_SPIN then
    begin
      E.Raw[EF_SHOTS] := SPIN_MARK;
      Inc(E.Raw[EF_FACING], SPIN_TURN);
      if E.Raw[EF_FACING] > DIR_COUNT - 1 then
        Dec(E.Raw[EF_FACING], DIR_COUNT);
      World.PlaySound(HitSound(E));
      World.DestroyEntity(S^, False);
      Exit;
    end;

    if Vuln = VULN_SHOVE then
    begin
      { Compare(0, X) is how the original spells Sign(X). }
      Dir := Compare(0, S^.Raw[EF_VEL_X]);
      E.Raw[EF_VEL_X] := Dir shl SHOVE_SPEED_SHIFT;
      Inc(E.Raw[EF_FLAG1C], Compare(0, E.Raw[EF_VEL_X]));
      if E.Raw[EF_FLAG1C] > SHOVE_FRAMES - 1 then
        E.Raw[EF_FLAG1C] := 0;
      if E.Raw[EF_FLAG1C] < 0 then
        E.Raw[EF_FLAG1C] := SHOVE_FRAMES - 1;
      World.PlaySound(HitSound(E));
      World.DestroyEntity(S^, False);
      Exit;
    end;

    { Immunity, some of it conditional on the shot's power. }
    if (Vuln = VULN_IMMUNE) or (Vuln = VULN_IMMUNE_ALT)
    or ((Vuln = VULN_ARMOUR_1) and (Power < 1))
    or ((Vuln = VULN_ARMOUR_2) and (Power < 2))
    or ((Vuln = VULN_ONLY_POWER3) and (Power <> 3))
    or ((Vuln = VULN_ONLY_POWER4) and (Power <> LOOT_POWER)) then
    begin
      World.PlaySound(HitSound(E));
      World.DestroyEntity(S^, Power = LOOT_POWER);
      Exit;
    end;

    { A real hit. The projectile's EF_HP is its DAMAGE - the same slot that
      holds hit points on a target. }
    Dec(E.Raw[EF_HP], S^.Raw[EF_HP]);

    { Powers 2 and 3 pierce and are not consumed. }
    if (Power <> PIERCING_POWER_A) and (Power <> PIERCING_POWER_B) then
      World.DestroyEntity(S^, Power = LOOT_POWER);

    E.Raw[EF_TIMER] := HIT_INVULN;
    E.Raw[EF_DEATH_TIMER] := HIT_INVULN;

    if E.Raw[EF_HP] < 1 then
    begin
      E.Raw[EF_HP] := 0;
      E.Raw[EF_DYING] := 0;      { let Entity_UpdateDying run its setup }
    end
    else
      World.PlaySound(SND_HIT01);
    { NOTE: no Exit here. Only the special arms above stop the scan, so
      several shots can land in one pass until the target's HP reaches 0. }
  end;
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

procedure EntityUpdate_Type36_FallingItem(var E: TEntity; AGameState: Integer;
                                          World: TEntityWorld);
var
  Frame: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= DROP_SPRITE_COUNT) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := DROP_SPRITES[Frame];

  if AGameState <> GS_PLAY then
    Exit;

  { Gravity only while still in the air. }
  if E.Raw[EF_STATE] = 0 then
  begin
    Inc(E.Raw[EF_VEL_Y], GRAVITY);
    if E.Raw[EF_VEL_Y] > TERMINAL_VELOCITY then
      E.Raw[EF_VEL_Y] := TERMINAL_VELOCITY;
  end;

  { The collision query and the move happen either way, landed or not. }
  if (World.TileAtY(E, E.Raw[EF_VEL_Y], False) >= World.SolidThreshold)
     and (E.Raw[EF_VEL_Y] > 0) then
  begin
    E.Raw[EF_VEL_Y] := World.EdgeDistY(E, E.Raw[EF_VEL_Y]);
    E.Raw[EF_STATE] := 1;
  end;

  Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);
end;

procedure EntityUpdate_Type43(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Variant: Integer;
begin
  Variant := E.Raw[EF_VARIANT];
  if (Variant < 0) or (Variant >= T43_VARIANTS) then
    Variant := 0;
  E.Raw[EF_ANIM_ID] := T43_SPRITES[Variant];

  { Every frame, not once - so nothing can leave it armoured differently. }
  E.Raw[EF_VULN_KIND] := E.Raw[EF_VARIANT] + T43_VULN_BASE;

  { The result is discarded: this type has nothing to do while dying. }
  EntityUpdateDying(E, AGameState, World);
end;

procedure EntityUpdate_Type44(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T44_FRAMES) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T44_SPRITES[Frame];

  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  Inc(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] > T44_TICKS then
  begin
    E.Raw[EF_BLOCK_B] := 0;
    E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T44_FRAMES;
  end;

  if E.Raw[EF_STATE] = 0 then
  begin
    E.Raw[EF_STATE] := 1;
    E.Raw[EF_VEL_Y] := T44_LAUNCH_VY;
  end;

  if E.Raw[EF_STATE] = 1 then
  begin
    Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);
    Inc(E.Raw[EF_VEL_Y], T44_GRAVITY);
    if E.Raw[EF_VEL_Y] > T44_TERMINAL then
      E.Raw[EF_VEL_Y] := T44_TERMINAL;
    Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);
  end;
end;

procedure EntityUpdate_Type42(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, D, I, N, Slot: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame > High(T42_SPRITES)) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T42_SPRITES[Frame];

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;

  if E.Raw[EF_STATE] = 0 then
  begin
    Inc(E.Raw[EF_HP], T42_HP_BONUS[D]);
    E.Raw[EF_STATE] := 1;
    Inc(E.Raw[EF_POS_Y], T42_DROP);
    E.Raw[EF_VEL_X] := T42_SPEED;
  end;

  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  { Free-running, and every state reset clears it. }
  Inc(E.Raw[EF_CHILD_B]);

  { States 1 and 5 share the slow four-frame loop. }
  if (E.Raw[EF_STATE] = 1) or (E.Raw[EF_STATE] = 5) then
  begin
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T42_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T42_FRAMES;
    end;
  end;

  if E.Raw[EF_STATE] = 1 then
  begin
    if World.TileAtX(E, E.Raw[EF_VEL_X], False) >= World.SolidThreshold then
      E.Raw[EF_VEL_X] := -E.Raw[EF_VEL_X];

    { The bob: one heading step every four frames, and the Y component of that
      heading becomes the vertical velocity. }
    Dec(E.Raw[EF_CHILD_A]);
    if E.Raw[EF_CHILD_A] < 1 then
    begin
      E.Raw[EF_CHILD_A] := T42_BOB_EVERY;
      E.Raw[EF_VEL_Y] := DirVelY(E.Raw[EF_FACING]);
      E.Raw[EF_FACING] := (E.Raw[EF_FACING] + 1) mod DIR_COUNT;
    end;
    Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);
    Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);

    { Scales with its OWN HP, so a damaged boss patrols for less time. }
    if E.Raw[EF_CHILD_B] > E.Raw[EF_HP] * 10 + T42_PATROL_BASE then
    begin
      World.PlaySound(T42_PATROL_SOUND);
      E.Raw[EF_STATE] := 2;
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_CHILD_A] := 0;
      E.Raw[EF_CHILD_B] := 0;
      E.Raw[EF_FACING] := 0;
    end;
  end;

  if E.Raw[EF_STATE] = 2 then
  begin
    { A heading step EVERY frame now, so the climb tightens. }
    Dec(E.Raw[EF_CHILD_A]);
    if E.Raw[EF_CHILD_A] < 1 then
    begin
      E.Raw[EF_CHILD_A] := 1;
      E.Raw[EF_FACING] := (E.Raw[EF_FACING] + 1) mod DIR_COUNT;
      E.Raw[EF_VEL_Y] := DirVelY(E.Raw[EF_FACING]);
    end;
    Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);

    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > 2 then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T42_FRAMES;
    end;

    if E.Raw[EF_CHILD_B] > T42_RISE_LEN[D] then
    begin
      E.Raw[EF_STATE] := 3;
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_CHILD_A] := 0;
      E.Raw[EF_CHILD_B] := 0;
      E.Raw[EF_VEL_Y] := T42_RISE_VY;
    end;
  end;

  if E.Raw[EF_STATE] = 3 then
  begin
    E.Raw[EF_FLAG1C] := T42_FALL_FRAME;
    Inc(E.Raw[EF_VEL_Y], T42_GRAVITY);
    if E.Raw[EF_VEL_Y] > T42_TERMINAL then
      E.Raw[EF_VEL_Y] := T42_TERMINAL;

    if World.TileAtY(E, E.Raw[EF_VEL_Y], False) >= World.SolidThreshold then
    begin
      World.PlaySound(T42_LAND_SOUND);
      E.Raw[EF_VEL_Y] := World.EdgeDistY(E, E.Raw[EF_VEL_Y]);
      E.Raw[EF_STATE] := 4;
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_CHILD_A] := 0;
      E.Raw[EF_CHILD_B] := 0;
      E.Raw[EF_FLAG1C] := T42_LAND_FRAME;

      { The fan. Count + 1 shots, each off the shared angle table. }
      N := T42_SHOTS[D];
      if N >= 0 then
        for I := 0 to N do
        begin
          Slot := World.Spawn(EKIND_MINOR, T42_SHOT_TYPE,
                              E.Raw[EF_POS_X] - POSITION_BIAS
                                - World.Layer.DeltaX,
                              E.Raw[EF_POS_Y] - World.Layer.DeltaY
                                - POSITION_BIAS + T42_SHOT_LIFT);
          if I <= High(T42_ANGLES) then
            World.SetSpawnField(Slot, EF_VEL_X,
                                T42_ANGLES[I] shl T42_ANGLE_SHIFT);
        end;
    end;

    Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);
  end;

  if E.Raw[EF_STATE] = 4 then
  begin
    { Re-snaps to the floor every frame it is down. }
    if World.TileAtY(E, E.Raw[EF_VEL_Y], False) >= World.SolidThreshold then
    begin
      World.PlaySound(T42_LAND_SOUND);
      E.Raw[EF_VEL_Y] := World.EdgeDistY(E, E.Raw[EF_VEL_Y]);
    end;

    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T42_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      Inc(E.Raw[EF_FLAG1C]);
      if E.Raw[EF_FLAG1C] > T42_LAND_LAST then
        E.Raw[EF_FLAG1C] := T42_LAND_FRAME;
    end;

    if E.Raw[EF_CHILD_B] >
       (E.Raw[EF_HP] div 10) * T42_RECOVER[D] + T42_RECOVER_BASE then
    begin
      E.Raw[EF_STATE] := 3;
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_CHILD_A] := 0;
      E.Raw[EF_CHILD_B] := 0;
      E.Raw[EF_FLAG1C] := 0;
      E.Raw[EF_VEL_Y] := T42_RETREAT_VY;
      { Every third recovery it retreats instead of attacking again. }
      Inc(E.Raw[EF_SHOTS]);
      if E.Raw[EF_SHOTS] > T42_RECOVERIES then
      begin
        E.Raw[EF_SHOTS] := 0;
        E.Raw[EF_STATE] := 5;
      end;
    end;
  end;

  if E.Raw[EF_STATE] = 5 then
  begin
    Dec(E.Raw[EF_POS_Y], T42_RETREAT_STEP);
    if E.Raw[EF_CHILD_B] > T42_RETREAT_LEN then
    begin
      E.Raw[EF_STATE] := 1;
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_CHILD_A] := 0;
      E.Raw[EF_CHILD_B] := 0;
      E.Raw[EF_FACING] := 0;
    end;
  end;
end;

procedure EntityUpdate_Type41(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, D: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame > High(T41_SPRITES)) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T41_SPRITES[Frame];

  if E.Raw[EF_STATE] = 0 then
  begin
    E.Raw[EF_STATE] := 1;
    Inc(E.Raw[EF_POS_Y], T41_SETTLE);
    if World.PlayerDifficulty = T41_HARD then
      E.Raw[EF_FACING] := E.Raw[EF_FACING] * 2;
  end;

  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;

  { Off screen it does not even count - frozen mid-crouch, not hopping in
    place. Same gate type 38 uses. }
  if (E.Raw[EF_STATE] = 1) and (not IsOffScreen(E, T41_OFFSCREEN_MARGIN)) then
  begin
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T41_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T41_FRAMES;
    end;

    Inc(E.Raw[EF_CHILD_A]);
    if E.Raw[EF_CHILD_A] > T41_WAIT[D] then
    begin
      World.PlaySound(T41_JUMP_SOUND);
      E.Raw[EF_STATE] := 2;
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_CHILD_A] := 0;
      E.Raw[EF_FLAG1C] := T41_CROUCH_FRAME;
      E.Raw[EF_VEL_Y] := T41_JUMP_VY;
    end;
  end;

  if E.Raw[EF_STATE] = 2 then
  begin
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T41_CROUCH_TICKS then
    begin
      E.Raw[EF_STATE] := 3;
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_FLAG1C] := T41_AIR_FRAME;
    end;
  end;

  if E.Raw[EF_STATE] = 3 then
  begin
    Inc(E.Raw[EF_POS_X], E.Raw[EF_FACING]);
    Inc(E.Raw[EF_VEL_Y], T41_GRAVITY);
    if E.Raw[EF_VEL_Y] > T41_TERMINAL then
      E.Raw[EF_VEL_Y] := T41_TERMINAL;

    if World.TileAtY(E, E.Raw[EF_VEL_Y], False) >= World.SolidThreshold then
    begin
      E.Raw[EF_VEL_Y] := World.EdgeDistY(E, E.Raw[EF_VEL_Y]);
      E.Raw[EF_STATE] := 1;
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_CHILD_A] := 0;
      E.Raw[EF_FLAG1C] := 0;
      { Turns round after block A[1] landings. }
      Inc(E.Raw[EF_CHILD_B]);
      if E.Raw[EF_CHILD_B] > E.Raw[EF_BLOCK_A + 1] then
      begin
        E.Raw[EF_CHILD_B] := 0;
        E.Raw[EF_FACING] := -E.Raw[EF_FACING];
      end;
    end;

    Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);
  end;
end;

procedure EntityUpdate_Type40(var E: TEntity; AGameState: Integer;
                              var Inp: TInputState; World: TEntityWorld);
var
  Frame, Row, D, Slot, Aim: Integer;
  Player: PEntity;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T40_FRAMES) then
    Frame := 0;
  Row := E.Raw[EF_VARIANT];
  if (Row < 0) or (Row >= T40_VARIANTS) then
    Row := 0;
  E.Raw[EF_ANIM_ID] := T40_SPRITES[Row][Frame];

  if E.Raw[EF_STATE] = 0 then
  begin
    E.Raw[EF_STATE] := 1;
    Inc(E.Raw[EF_POS_Y], T40_SETTLE);
    if E.Raw[EF_VARIANT] = T40_SHOOTER_VARIANT then
    begin
      E.Raw[EF_VULN_KIND] := 1;
      E.Raw[EF_CULL_OFFSCREEN] := 0;
    end;
  end;

  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;

  if (E.Raw[EF_STATE] = 1) and (E.Raw[EF_VARIANT] = T40_SHOOTER_VARIANT)
     and (not IsOffScreen(E, T40_OFFSCREEN_MARGIN)) and (World.Pool <> nil) then
  begin
    if E.Raw[EF_CHILD_B] > 0 then
      Dec(E.Raw[EF_CHILD_B]);
    if E.Raw[EF_CHILD_B] = 0 then
    begin
      Player := World.Pool.Entity(SLOT_SINGLE_FIRST);
      if EntitiesOverlap(E, Player^, T40_TRIGGER_SCALE_X,
                         T40_TRIGGER_SCALE_Y) then
      begin
        E.Raw[EF_CHILD_B] := T40_COOLDOWN[D];
        Slot := World.Spawn(EKIND_MINOR, T40_SHOT_TYPE,
                            E.Raw[EF_POS_X] - POSITION_BIAS
                              - World.Layer.DeltaX,
                            E.Raw[EF_POS_Y] - World.Layer.DeltaY
                              - POSITION_BIAS + T40_SHOT_LIFT);
        World.SetSpawnField(Slot, EF_OWNER, E.Raw[EF_SLOT]);
        { HP 1 - so this shot never writes back to its parent. }
        World.SetSpawnField(Slot, EF_HP, 1);
        Aim := Compare(E.Raw[EF_POS_X], Player^.Raw[EF_POS_X]) shl T40_AIM_SHIFT;
        if Aim = 0 then
          Aim := T40_AIM_ZERO;
        World.SetSpawnField(Slot, EF_VEL_X, Aim);
      end;
    end;
  end;

  { The launch. Nothing here sets state 2 - the touch handler does. }
  if (E.Raw[EF_STATE] = 2) and (World.Pool <> nil) then
  begin
    E.Raw[EF_STATE] := 3;
    E.Raw[EF_BLOCK_B] := 0;
    E.Raw[EF_CHILD_A] := 0;
    E.Raw[EF_TIMER] := T40_BOUNCE_TIMER;
    E.Raw[EF_FLAG1C] := 0;

    Player := World.Pool.Entity(SLOT_SINGLE_FIRST);
    Player^.Raw[EF_VEL_Y] := T40_LAUNCH_VY;
    { Keeps the SPEED it arrived with, takes the DIRECTION from what is held
      now - so you can turn round on the spring. With no input, untouched. }
    if Inp.AxisX <> 0 then
      Player^.Raw[EF_CHILD_A] := Abs(Player^.Raw[EF_VEL_X]) * Inp.AxisX;
    Player^.Raw[EF_STATE] := 2;
    Player^.Raw[EF_BLOCK_A + 1] := 1;
    Player^.Raw[EF_RIDDEN] := 0;
    Player^.Raw[EF_BLOCK_A + 8] := 1;
    World.PlaySound(T40_LAUNCH_SOUND);
  end;

  if E.Raw[EF_STATE] = 3 then
  begin
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T40_BOUNCE_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      Inc(E.Raw[EF_FLAG1C]);
      if E.Raw[EF_FLAG1C] > T40_BOUNCE_FRAMES - 1 then
      begin
        E.Raw[EF_FLAG1C] := 0;
        Inc(E.Raw[EF_CHILD_A]);
        if E.Raw[EF_CHILD_A] > T40_BOUNCE_CYCLES then
          E.Raw[EF_STATE] := 1;
      end;
    end;
  end;
end;

procedure EntityUpdate_Type38(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, Row, D, Slot: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T38_FRAMES) then
    Frame := 0;
  Row := E.Raw[EF_VARIANT];
  if (Row < 0) or (Row >= T38_VARIANTS) then
    Row := 0;
  E.Raw[EF_ANIM_ID] := T38_SPRITES[Row][Frame];

  if E.Raw[EF_STATE] = 0 then
  begin
    E.Raw[EF_STATE] := 1;
    Inc(E.Raw[EF_POS_Y], T38_SETTLE);
    { The variant is both the sprite row and the direction. }
    E.Raw[EF_FACING] := E.Raw[EF_VARIANT] shl T38_FACING_SHIFT;
  end;

  if EntityUpdateDying(E, AGameState, World) then
    Exit;
  if AGameState <> GS_PLAY then
    Exit;

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;

  if E.Raw[EF_STATE] = 1 then
  begin
    { OFF SCREEN, NO COUNTDOWN. A turret you cannot see never fires. }
    if not IsOffScreen(E, T38_OFFSCREEN_MARGIN) then
    begin
      Inc(E.Raw[EF_CHILD_A]);
      if E.Raw[EF_CHILD_A] > T38_WAIT[D] then
      begin
        E.Raw[EF_BLOCK_B] := 0;
        E.Raw[EF_CHILD_A] := 0;
        E.Raw[EF_STATE] := 2;
        E.Raw[EF_FLAG1C] := 0;
      end;
    end;
  end;

  if E.Raw[EF_STATE] = 2 then
  begin
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T38_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      Inc(E.Raw[EF_FLAG1C]);
    end;
    if E.Raw[EF_FLAG1C] > T38_FRAMES - 1 then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_STATE] := 3;
      E.Raw[EF_FLAG1C] := T38_FRAMES - 1;
    end;
  end;

  if E.Raw[EF_STATE] = 3 then
  begin
    Inc(E.Raw[EF_CHILD_A]);
    if E.Raw[EF_CHILD_A] > T38_FIRE_DELAY then
    begin
      Slot := World.Spawn(EKIND_MINOR, T38_SHOT_TYPE,
                          E.Raw[EF_POS_X] - POSITION_BIAS - World.Layer.DeltaX
                            + DirVelX(E.Raw[EF_FACING]) * T38_SHOT_AHEAD,
                          E.Raw[EF_POS_Y] - World.Layer.DeltaY - POSITION_BIAS
                            - T38_SHOT_LIFT);
      World.SetSpawnField(Slot, EF_OWNER, E.Raw[EF_SLOT]);
      { The shot's velocity is one direction step, and the speed multiplier is
        applied at the far end by type 39 itself. }
      World.SetSpawnField(Slot, EF_VEL_X, DirVelX(E.Raw[EF_FACING]));
      E.Raw[EF_CHILD_A] := 0;
      E.Raw[EF_STATE] := 4;
    end;
  end;

  { State 4 is a hold. Type 39 is what leaves it. }

  if E.Raw[EF_STATE] = 5 then
  begin
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T38_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      Dec(E.Raw[EF_FLAG1C]);
    end;
    if E.Raw[EF_FLAG1C] < 1 then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_STATE] := 1;
    end;
  end;
end;

procedure EntityUpdate_Type39(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, D, Slot: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T39_FRAMES) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T39_SPRITES[Frame];

  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;

  if E.Raw[EF_STATE] = 0 then
  begin
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T39_WIND[D] then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      Inc(E.Raw[EF_FLAG1C]);
      if E.Raw[EF_FLAG1C] > T39_CHARGE_FRAMES - 1 then
      begin
        { ONLY a shot with no HP releases its parent. One with HP left leaves
          the turret stuck in state 4. }
        if (E.Raw[EF_HP] = 0) and (World.Pool <> nil) then
          World.Pool.SetField(E.Raw[EF_OWNER], EF_STATE, T39_OWNER_WIND_DOWN);
        E.Raw[EF_STATE] := 1;
        World.PlaySound(T39_LAUNCH_SOUND);
      end;
    end;
  end;

  if E.Raw[EF_STATE] = 1 then
  begin
    Inc(E.Raw[EF_BLOCK_B]);
    Inc(E.Raw[EF_CHILD_A]);
    if E.Raw[EF_BLOCK_B] > T39_FLIGHT_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      Inc(E.Raw[EF_FLAG1C]);
      if E.Raw[EF_FLAG1C] > T39_FRAMES - 1 then
        E.Raw[EF_FLAG1C] := T39_FLIGHT_FIRST;
    end;

    Inc(E.Raw[EF_POS_X], T39_SPEED[D] * E.Raw[EF_VEL_X]);
    Inc(E.Raw[EF_POS_Y], T39_SPEED[D] * E.Raw[EF_VEL_Y]);

    if (World.TileAtX(E, E.Raw[EF_VEL_X], False) >= World.SolidThreshold)
       or (E.Raw[EF_CHILD_A] > T39_RANGE) then
    begin
      Slot := World.Spawn(EKIND_MINOR, T39_PUFF_TYPE,
                          E.Raw[EF_POS_X] - POSITION_BIAS,
                          E.Raw[EF_POS_Y] - POSITION_BIAS);
      World.SetSpawnField(Slot, EF_VARIANT, T39_PUFF_VARIANT);
      World.DestroyEntity(E, False);
    end;
  end;
end;

procedure EntityUpdate_Type02(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, Row, I, Slot, Facing, SparkRow: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T2_FRAMES) then
    Frame := 0;
  Row := E.Raw[EF_STATE];
  if (Row < 0) or (Row >= T2_STATES) then
    Row := 0;
  { Right half then left half, by the SIGN, two ifs and no else. }
  if E.Raw[EF_VEL_X] > 0 then
    E.Raw[EF_ANIM_ID] := T2_SPRITES[Row][Frame];
  if E.Raw[EF_VEL_X] < 0 then
    E.Raw[EF_ANIM_ID] := T2_SPRITES[Row][Frame + T2_FRAMES];

  if AGameState <> GS_PLAY then
    Exit;

  Inc(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] > T2_TICKS then
  begin
    E.Raw[EF_BLOCK_B] := 0;
    Inc(E.Raw[EF_FLAG1C]);
    if E.Raw[EF_FLAG1C] > T2_FRAMES - 1 then
      E.Raw[EF_FLAG1C] := 0;
  end;

  SparkRow := 0;
  if E.Raw[EF_STATE] = T2_CHARGE_STATE then
  begin
    SparkRow := 1;
    { Accelerates along whatever direction it already has - Compare(0, v) is
      the sign, so this never reverses a shot. }
    Inc(E.Raw[EF_VEL_X], Compare(0, E.Raw[EF_VEL_X]) * T2_CHARGE_ACCEL);
    Inc(E.Raw[EF_CHILD_A]);
    if E.Raw[EF_CHILD_A] > T2_TRAIL_EVERY then
    begin
      E.Raw[EF_CHILD_A] := 0;
      World.Spawn(EKIND_MINOR, T2_TRAIL_TYPE,
                  E.Raw[EF_POS_X] - POSITION_BIAS,
                  E.Raw[EF_POS_Y] - POSITION_BIAS - T2_TRAIL_LIFT);
    end;
  end;

  if World.TileAtX(E, E.Raw[EF_VEL_X], False) < World.SolidThreshold then
  begin
    Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);
    { The lifetime is a countdown, and running out is the quiet end. }
    Dec(E.Raw[EF_CHILD_B]);
    if E.Raw[EF_CHILD_B] < 0 then
    begin
      World.Spawn(EKIND_MINOR, T2_TRAIL_TYPE,
                  E.Raw[EF_POS_X] - POSITION_BIAS,
                  E.Raw[EF_POS_Y] - POSITION_BIAS - T2_TRAIL_LIFT);
      World.DestroyEntity(E, False);
    end;
  end
  else
  begin
    { A wall. Six sparks, each with its own heading and its own two speeds. }
    for I := 1 to T2_SPARKS do
    begin
      Slot := World.Spawn(EKIND_MINOR, T2_SPARK_TYPE,
                          E.Raw[EF_POS_X] - POSITION_BIAS,
                          E.Raw[EF_POS_Y] - POSITION_BIAS);
      { Block A[1] is type 6's sprite ROW, so a charged impact throws a
        different-coloured burst. }
      World.SetSpawnField(Slot, EF_BLOCK_A + 1, SparkRow);
      Facing := World.RandomBelow(DIR_COUNT);
      World.SetSpawnField(Slot, EF_FACING, Facing);
      World.SetSpawnField(Slot, EF_VEL_X,
        (World.RandomBelow(T2_SPARK_SPEED_MAX) + 1) * HalfExtent(DirVelX(Facing)));
      World.SetSpawnField(Slot, EF_VEL_Y,
        (World.RandomBelow(T2_SPARK_SPEED_MAX) + 1) * HalfExtent(DirVelY(Facing)));
    end;
    World.DestroyEntity(E, False);
  end;
end;

procedure EntityUpdate_Type34(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, D, Rate: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T34_FRAMES) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T34_SPRITES[Frame];

  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  Inc(E.Raw[EF_POS_X], DirVelX(E.Raw[EF_FACING]) * T34_SPEED);
  Inc(E.Raw[EF_POS_Y], DirVelY(E.Raw[EF_FACING]) * T34_SPEED);

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;
  Rate := T34_RATE[D];

  { A modulo test rather than a countdown - the counter is never reset, so the
    frames land on multiples of the rate. }
  Inc(E.Raw[EF_BLOCK_B]);
  if (Rate <> 0) and (E.Raw[EF_BLOCK_B] mod Rate = 0) then
  begin
    Inc(E.Raw[EF_FLAG1C]);
    if E.Raw[EF_FLAG1C] > T34_FRAMES - 1 then
      World.DestroyEntity(E, False);
  end;
end;

procedure EntityUpdate_Type35(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, Owner, Aim: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T35_FRAMES) then
    Frame := 0;
  { The same table both ways round: forwards while winding up, backwards while
    winding down. }
  if E.Raw[EF_STATE] = T35_MODE_WIND_UP then
    E.Raw[EF_ANIM_ID] := T35_SPRITES[Frame];
  if E.Raw[EF_STATE] = T35_MODE_WIND_DOWN then
    E.Raw[EF_ANIM_ID] := T35_SPRITES[T35_FRAMES - 1 - Frame];

  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  Owner := E.Raw[EF_OWNER];
  if World.Pool = nil then
    Exit;

  { An owner with no HP left takes its telegraph with it. }
  if World.Pool.Field(Owner, EF_HP) = 0 then
  begin
    World.DestroyEntity(E, False);
    Exit;
  end;

  Inc(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] <= T35_TICKS then
    Exit;

  E.Raw[EF_BLOCK_B] := 0;
  Inc(E.Raw[EF_FLAG1C]);
  if E.Raw[EF_FLAG1C] <= T35_FRAMES - 1 then
    Exit;

  if E.Raw[EF_STATE] = T35_MODE_WIND_UP then
  begin
    World.PlaySound(T35_SOUND);
    World.Pool.SetField(Owner, EF_STATE, T35_OWNER_ATTACK);
    { The aim, taken ONCE here rather than tracked - which is why the shots
      that follow all leave along one heading however the player moves. }
    Aim := AngleBetween(World.Pool.Field(Owner, EF_POS_X),
                        World.Pool.Field(Owner, EF_POS_Y),
                        World.Pool.Field(SLOT_SINGLE_FIRST, EF_POS_X),
                        World.Pool.Field(SLOT_SINGLE_FIRST, EF_POS_Y));
    World.Pool.SetField(Owner, EF_BLOCK_A + 1, Aim);
  end;
  if E.Raw[EF_STATE] = T35_MODE_WIND_DOWN then
    World.Pool.SetField(Owner, EF_STATE, T35_OWNER_IDLE);

  World.DestroyEntity(E, False);
end;

procedure EntityUpdate_Type30(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T30_FRAMES) then
    Frame := 0;
  { By the SIGN of the speed, two ifs and no else - a stationary one keeps
    whatever sprite it had. }
  if E.Raw[EF_FACING] < 0 then
    E.Raw[EF_ANIM_ID] := T30_SPRITES[0][Frame];
  if E.Raw[EF_FACING] > 0 then
    E.Raw[EF_ANIM_ID] := T30_SPRITES[1][Frame];

  if E.Raw[EF_STATE] = 0 then
  begin
    E.Raw[EF_STATE] := 1;
    Inc(E.Raw[EF_POS_Y], T30_SETTLE);
    { HARD ONLY: twice the speed and half the turn period, so four times the
      ground between turns. This is the whole of its difficulty scaling and it
      happens once, on the first frame. }
    if World.PlayerDifficulty = T30_HARD then
    begin
      E.Raw[EF_FACING] := E.Raw[EF_FACING] * 2;
      E.Raw[EF_BLOCK_A + 1] := HalfExtent(E.Raw[EF_BLOCK_A + 1]);
    end;
  end;

  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  Inc(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] > T30_TICKS then
  begin
    E.Raw[EF_BLOCK_B] := 0;
    E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T30_FRAMES;
  end;

  { A SECOND counter, in EF_CHILD_A, for the turn - the frame counter above is
    already using EF_BLOCK_B. }
  Inc(E.Raw[EF_CHILD_A]);
  if E.Raw[EF_CHILD_A] > E.Raw[EF_BLOCK_A + 1] then
  begin
    E.Raw[EF_CHILD_A] := 0;
    E.Raw[EF_FACING] := -E.Raw[EF_FACING];
  end;

  Inc(E.Raw[EF_POS_X], E.Raw[EF_FACING]);
end;

procedure EntityUpdate_Type31(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, D, Slot: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame > T31_HURT_FRAME) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T31_SPRITES[Frame];
  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;

  if E.Raw[EF_STATE] = 0 then
  begin
    Inc(E.Raw[EF_HP], T31_HP_BONUS[D]);
    E.Raw[EF_STATE] := 1;
    Dec(E.Raw[EF_POS_X], T31_RISE);
    Dec(E.Raw[EF_POS_Y], T31_DRIFT);
  end;

  { Out of HP: forced onto the hurt frame wherever it is, and this is OUTSIDE
    the dying guard so it keeps happening. }
  if E.Raw[EF_HP] = 0 then
    E.Raw[EF_FLAG1C] := T31_HURT_FRAME;

  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  if E.Raw[EF_STATE] = 1 then
  begin
    { HALF the X component and nothing on Y, so it drifts sideways in a slow
      sine rather than circling. }
    Inc(E.Raw[EF_POS_X], HalfExtent(DirVelX(E.Raw[EF_FACING])));
    E.Raw[EF_FACING] := (E.Raw[EF_FACING] + 1) mod DIR_COUNT;

    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T31_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T31_FRAMES;
    end;

    { The tougher it is, the LONGER it waits - the wait is proportional to its
      own HP as well as to the difficulty. }
    Inc(E.Raw[EF_CHILD_A]);
    if E.Raw[EF_CHILD_A] > T31_WAIT[D] * E.Raw[EF_HP] + T31_WAIT_BASE then
    begin
      E.Raw[EF_STATE] := 2;
      E.Raw[EF_CHILD_A] := 0;
    end;
  end;

  if E.Raw[EF_STATE] = 2 then
  begin
    E.Raw[EF_STATE] := 3;
    E.Raw[EF_CHILD_A] := 0;
    E.Raw[EF_FLAG1C] := 0;
    Slot := World.Spawn(EKIND_MINOR, T31_MARKER_TYPE,
                        E.Raw[EF_POS_X] - World.Layer.DeltaX - POSITION_BIAS
                          - $400,
                        E.Raw[EF_POS_Y] - World.Layer.DeltaY - POSITION_BIAS
                          + $40);
    World.SetSpawnField(Slot, EF_STATE, 0);
    { The child is told which entity it belongs to, by SLOT. }
    World.SetSpawnField(Slot, EF_OWNER, E.Raw[EF_SLOT]);
  end;

  { State 3 does nothing here. The type-35 child is what advances it to 4. }

  if E.Raw[EF_STATE] = 4 then
  begin
    E.Raw[EF_FLAG1C] := T31_HURT_FRAME;
    Inc(E.Raw[EF_CHILD_A]);
    if E.Raw[EF_CHILD_A] > T31_ATTACK_LEN then
    begin
      E.Raw[EF_CHILD_A] := 0;
      E.Raw[EF_CHILD_B] := 0;
      E.Raw[EF_STATE] := 5;
    end;

    Inc(E.Raw[EF_CHILD_B]);
    if (E.Raw[EF_CHILD_B] mod T31_FIRE_EVERY = 0)
       and (E.Raw[EF_CHILD_A] > T31_RATE[D]) then
    begin
      World.PlaySound(T31_FIRE_SOUND);
      Slot := World.Spawn(EKIND_MINOR, T31_SHOT_TYPE,
                          E.Raw[EF_POS_X] - World.Layer.DeltaX - POSITION_BIAS
                            - $480,
                          E.Raw[EF_POS_Y] - World.Layer.DeltaY - POSITION_BIAS
                            + $80);
      { The shot's heading is block A[1], not the parent's facing. }
      World.SetSpawnField(Slot, EF_FACING, E.Raw[EF_BLOCK_A + 1]);
    end;
  end;

  if E.Raw[EF_STATE] = 5 then
  begin
    E.Raw[EF_STATE] := 6;
    E.Raw[EF_FLAG1C] := 0;
    Slot := World.Spawn(EKIND_MINOR, T31_MARKER_TYPE,
                        E.Raw[EF_POS_X] - World.Layer.DeltaX - POSITION_BIAS
                          - $400,
                        E.Raw[EF_POS_Y] - World.Layer.DeltaY - POSITION_BIAS
                          + $40);
    World.SetSpawnField(Slot, EF_STATE, 1);
    World.SetSpawnField(Slot, EF_OWNER, E.Raw[EF_SLOT]);
  end;
end;

procedure EntityUpdate_Type37(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T37_FRAMES) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T37_SPRITES[Frame];

  { Arrival, and it happens whatever the game state is. }
  if E.Raw[EF_STATE] = 0 then
  begin
    World.Spawn(EKIND_MINOR, T37_PUFF_TYPE,
                E.Raw[EF_POS_X] - POSITION_BIAS,
                E.Raw[EF_POS_Y] - POSITION_BIAS);
    E.Raw[EF_STATE] := 1;
    Inc(E.Raw[EF_POS_Y], T37_DROP);
    E.Raw[EF_TIMER] := T37_TIMERS;
    E.Raw[EF_DEATH_TIMER] := T37_TIMERS;
  end;

  if AGameState <> GS_PLAY then
    Exit;

  if E.Raw[EF_STATE] = 1 then
  begin
    Inc(E.Raw[EF_VEL_Y], T37_GRAVITY);
    if E.Raw[EF_VEL_Y] > T37_TERMINAL then
      E.Raw[EF_VEL_Y] := T37_TERMINAL;

    if World.TileAtY(E, E.Raw[EF_VEL_Y], False) >= World.SolidThreshold then
    begin
      World.PlaySound(T37_LAND_SOUND);
      E.Raw[EF_VEL_Y] := World.EdgeDistY(E, E.Raw[EF_VEL_Y]);
      E.Raw[EF_STATE] := 2;
    end;
    Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);
  end;

  Inc(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] > T37_TICKS then
  begin
    E.Raw[EF_BLOCK_B] := 0;
    { The original divides AND takes the remainder, leaving the quotient in
      EAX as a dead result - see type 16 for the same shape. }
    E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T37_FRAMES;
  end;
end;

procedure EntityUpdate_Type15(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame > 1) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T15_SPRITES[Frame];

  if AGameState <> GS_PLAY then
    Exit;

  { Two states in sequence, in two separate ifs - so the frame that sets
    state 2 also runs the state-2 arm. One throw, one frame. }
  if E.Raw[EF_STATE] = 1 then
  begin
    World.PlaySound(T15_SOUND);
    E.Raw[EF_STATE] := 2;
  end;
  if E.Raw[EF_STATE] = 2 then
  begin
    E.Raw[EF_STATE] := 3;
    E.Raw[EF_FLAG1C] := 1;
    World.SetEventOpcode(E.Raw[EF_EVENT_ID], T15_THROWN_OPCODE);
  end;
end;

procedure EntityUpdate_Type17(var E: TEntity);
begin
end;

procedure EntityUpdate_Type19(var E: TEntity);
begin
end;

procedure EntityUpdate_Type21(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
begin
  E.Raw[EF_ANIM_ID] := T21_SPRITE;
  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  Inc(E.Raw[EF_BLOCK_B]);
  { The half-period is block A[1], which ParamA's 'R' letter sets. }
  if E.Raw[EF_BLOCK_B] > E.Raw[EF_BLOCK_A + 1] then
  begin
    E.Raw[EF_BLOCK_B] := 0;
    E.Raw[EF_FACING] := -E.Raw[EF_FACING];
  end;

  if E.Raw[EF_STATE] = T21_AXIS_VERTICAL then
    Inc(E.Raw[EF_POS_Y], E.Raw[EF_FACING])
  else if E.Raw[EF_STATE] = T21_AXIS_HORIZONTAL then
    Inc(E.Raw[EF_POS_X], E.Raw[EF_FACING]);
end;

procedure EntityUpdate_Type23(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Slot: Integer;
begin
  E.Raw[EF_ANIM_ID] := T23_SPRITE;
  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  if E.Raw[EF_STATE] = 1 then
  begin
    { Minus the layer delta: this frame's scroll has already been carried into
      the torch, and a child placed from its position would otherwise take it
      a second time. }
    Slot := World.Spawn(EKIND_MINOR, T23_FLAME_LOW_TYPE,
                        E.Raw[EF_POS_X] - POSITION_BIAS - World.Layer.DeltaX,
                        E.Raw[EF_POS_Y] - POSITION_BIAS - World.Layer.DeltaY
                          - T23_FLAME_LOW_LIFT);
    E.Raw[EF_CHILD_A] := Slot;
    Slot := World.Spawn(EKIND_MINOR, T23_FLAME_HIGH_TYPE,
                        E.Raw[EF_POS_X] - POSITION_BIAS - World.Layer.DeltaX,
                        E.Raw[EF_POS_Y] - POSITION_BIAS - World.Layer.DeltaY
                          - T23_FLAME_HIGH_LIFT);
    E.Raw[EF_CHILD_B] := Slot;
    E.Raw[EF_STATE] := 2;
  end;

  if E.Raw[EF_STATE] = 3 then
  begin
    { Slot 0 counts as "none" here, which is the original's test - and slot 0
      is the player, so a child can never legitimately be there. }
    if (E.Raw[EF_CHILD_A] <> 0) and (World.Pool <> nil) then
    begin
      World.DestroyEntity(World.Pool.Entity(E.Raw[EF_CHILD_A])^, False);
      E.Raw[EF_CHILD_A] := 0;
    end;
    if (E.Raw[EF_CHILD_B] <> 0) and (World.Pool <> nil) then
    begin
      World.DestroyEntity(World.Pool.Entity(E.Raw[EF_CHILD_B])^, False);
      E.Raw[EF_CHILD_B] := 0;
    end;
    E.Raw[EF_STATE] := 0;
  end;
end;

procedure EntityUpdate_Type28(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame: Integer;
begin
  { Everything, including the sprite, is inside the variant test. A variant
    other than 0 makes this entity completely inert. }
  if E.Raw[EF_VARIANT] <> 0 then
    Exit;

  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T28_FRAMES) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T28_SPRITES[Frame];

  if AGameState <> GS_PLAY then
    Exit;

  if E.Raw[EF_DEATH_TIMER] = 0 then
    E.Raw[EF_DEATH_TIMER] := T28_DEATH_TIMER;

  Inc(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] > T28_TICKS then
  begin
    E.Raw[EF_BLOCK_B] := 0;
    Inc(E.Raw[EF_FLAG1C]);
    if E.Raw[EF_FLAG1C] > T28_FRAMES - 1 then
      World.DestroyEntity(E, False);
  end;
end;

procedure EntityUpdate_Type29(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, Ticks: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T29_FRAMES) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T29_SPRITES[Frame];

  { Settles two pixels on its first frame, and this happens whatever the game
    state is - it is outside the guard below. }
  if E.Raw[EF_STATE] = 0 then
  begin
    E.Raw[EF_STATE] := 1;
    Inc(E.Raw[EF_POS_Y], T29_SETTLE);
  end;

  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  Ticks := T29_TICKS_IDLE;
  if (World.Pool <> nil)
     and EntitiesOverlap(E, World.Pool.Entity(SLOT_SINGLE_FIRST)^,
                         T29_NEAR_SCALE_X, T29_NEAR_SCALE_Y) then
    Ticks := T29_TICKS_CLOSE;

  Inc(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] > Ticks then
  begin
    E.Raw[EF_BLOCK_B] := 0;
    E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T29_FRAMES;
  end;
end;

{ The one-shot latch types 4..7 share: mark it done and arm the death timer.
  Written once here because it is literally the same three lines in each. }
procedure EffectLatch(var E: TEntity);
begin
  if E.Raw[EF_STATE] = 0 then
  begin
    E.Raw[EF_STATE] := 1;
    E.Raw[EF_DEATH_TIMER] := EFFECT_LATCH_TIMER;
  end;
end;

procedure EntityUpdate_Type03(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T3_FRAMES) then
    Frame := 0;
  { By the SIGN, and zero writes nothing at all - the original has two
    separate ifs with no else, so a puff standing still keeps its sprite. }
  if E.Raw[EF_VEL_X] < 0 then
    E.Raw[EF_ANIM_ID] := T3_SPRITES[0][Frame];
  if E.Raw[EF_VEL_X] > 0 then
    E.Raw[EF_ANIM_ID] := T3_SPRITES[1][Frame];

  if AGameState <> GS_PLAY then
    Exit;

  Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);
  Inc(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] > T3_TICKS then
  begin
    E.Raw[EF_BLOCK_B] := 0;
    Inc(E.Raw[EF_FLAG1C]);
  end;
  if E.Raw[EF_FLAG1C] > T3_FRAMES - 1 then
    World.DestroyEntity(E, False);
end;

procedure EntityUpdate_Type04(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T4_FRAMES) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T4_SPRITES[Frame];

  if AGameState <> GS_PLAY then
    Exit;

  EffectLatch(E);
  Inc(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] > T4_TICKS then
  begin
    E.Raw[EF_BLOCK_B] := 0;
    Inc(E.Raw[EF_FLAG1C]);
  end;
  if E.Raw[EF_FLAG1C] > T4_FRAMES - 1 then
    World.DestroyEntity(E, False);
end;

procedure EntityUpdate_Type05(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, Owner: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T5_FRAMES) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T5_SPRITES[Frame];

  { Its position is not its own: it is the owner's plus the offset held in the
    velocity fields. Written EVERY frame including outside play, so it stays
    pinned to its owner through a dialogue box. }
  Owner := E.Raw[EF_OWNER];
  if (World.Pool <> nil) and (Owner >= 0) and (Owner < ENTITY_COUNT) then
  begin
    E.Raw[EF_POS_X] := World.Pool.Field(Owner, EF_POS_X) + E.Raw[EF_VEL_X];
    E.Raw[EF_POS_Y] := World.Pool.Field(Owner, EF_POS_Y) + E.Raw[EF_VEL_Y];
  end;

  if AGameState <> GS_PLAY then
    Exit;

  { The offset shrinks along the heading, so it retracts into the owner. }
  Dec(E.Raw[EF_VEL_X], DirVelX(E.Raw[EF_FACING]));
  Dec(E.Raw[EF_VEL_Y], DirVelY(E.Raw[EF_FACING]));

  EffectLatch(E);
  Inc(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] > T5_TICKS then
  begin
    E.Raw[EF_BLOCK_B] := 0;
    Inc(E.Raw[EF_FLAG1C]);
  end;
  if E.Raw[EF_FLAG1C] > T5_FRAMES - 1 then
    World.DestroyEntity(E, False);
end;

procedure EntityUpdate_Type06(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, Row: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T6_FRAMES) then
    Frame := 0;
  Row := E.Raw[EF_BLOCK_A + 1];
  if (Row < 0) or (Row >= T6_ROWS) then
    Row := 0;
  E.Raw[EF_ANIM_ID] := T6_SPRITES[Row][Frame];

  if AGameState <> GS_PLAY then
    Exit;

  Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);
  Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);

  EffectLatch(E);
  Inc(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] > T6_TICKS then
  begin
    E.Raw[EF_BLOCK_B] := 0;
    Inc(E.Raw[EF_FLAG1C]);
  end;
  if E.Raw[EF_FLAG1C] > T6_FRAMES - 1 then
    World.DestroyEntity(E, False);
end;

procedure EntityUpdate_Type07(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, Row: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T7_FRAMES) then
    Frame := 0;
  Row := E.Raw[EF_VARIANT];
  if (Row < 0) or (Row >= T7_ROWS) then
    Row := 0;
  E.Raw[EF_ANIM_ID] := T7_SPRITES[Row][Frame];

  if AGameState <> GS_PLAY then
    Exit;

  EffectLatch(E);
  Inc(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] > T7_TICKS then
  begin
    E.Raw[EF_BLOCK_B] := 0;
    Inc(E.Raw[EF_FLAG1C]);
  end;
  if E.Raw[EF_FLAG1C] > T7_FRAMES - 1 then
    World.DestroyEntity(E, False);
end;

procedure EntityUpdate_Type09(var E: TEntity; AGameState: Integer);
begin
  E.Raw[EF_ANIM_ID] := T9_SPRITE;

  { One of only two handlers that also run in GS_PLAY_ALT. }
  if (AGameState <> GS_PLAY) and (AGameState <> GS_PLAY_ALT) then
    Exit;

  { Full X, HALF Y - so the path is an ellipse, not a circle. }
  Inc(E.Raw[EF_POS_X], DirVelX(E.Raw[EF_FACING]));
  Inc(E.Raw[EF_POS_Y], HalfExtent(DirVelY(E.Raw[EF_FACING])));

  E.Raw[EF_FACING] := (E.Raw[EF_FACING] + 1) mod DIR_COUNT;
end;

procedure EntityUpdate_Type10(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T10_FRAMES) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T10_SPRITES[Frame];

  if AGameState <> GS_PLAY then
    Exit;

  Inc(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] > T10_TICKS then
  begin
    E.Raw[EF_BLOCK_B] := 0;
    Inc(E.Raw[EF_FLAG1C]);
    { Note the destroy is INSIDE the advance here, unlike types 3..7 where it
      is a separate test every frame. Same effect, and kept as written. }
    if E.Raw[EF_FLAG1C] > T10_FRAMES - 1 then
      World.DestroyEntity(E, False);
  end;
end;

procedure EntityUpdate_Type11(var E: TEntity; AGameState: Integer);
var
  Frame: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T11_FRAMES) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T11_SPRITES[Frame];

  if AGameState <> GS_PLAY then
    Exit;

  { Topped back up whenever it reaches zero, so this never actually dies of
    it - Entity_UpdateAll's flicker reads the same field, which is why an
    entity of this type blinks. }
  if E.Raw[EF_DEATH_TIMER] = 0 then
    E.Raw[EF_DEATH_TIMER] := T11_DEATH_TIMER;

  Inc(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] > T11_TICKS then
  begin
    E.Raw[EF_BLOCK_B] := 0;
    { WRAPS. No Entity_Destroy anywhere in this handler. }
    E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T11_FRAMES;
  end;
end;

procedure EntityUpdate_Type12(var E: TEntity; AGameState: Integer);
var
  Frame: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T12_FRAMES) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T12_SPRITES[Frame];

  if AGameState <> GS_PLAY then
    Exit;

  Inc(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] > T12_TICKS then
  begin
    E.Raw[EF_BLOCK_B] := 0;
    E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T12_FRAMES;
  end;
end;

procedure EntityUpdate_Type13(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];

  { The sprite, by state. Four independent ifs, and two of them also test the
    stage's terrain - so a state-1 shard in any terrain but 3 or 4 gets no
    write at all and keeps whatever it had. }
  if E.Raw[EF_STATE] = T13_STATE_SPLASH then
    if (Frame >= 0) and (Frame < T13_SPLASH_FRAMES) then
      E.Raw[EF_ANIM_ID] := T13_SPLASH_SPRITES[Frame];
  if (E.Raw[EF_STATE] = T13_STATE_SHARD)
     and (World.TerrainId = T13_TERRAIN_SHARD3) then
    if (Frame >= 0) and (Frame < T13_SHARD_FRAMES) then
      E.Raw[EF_ANIM_ID] := T13_SHARD3_SPRITES[Frame];
  if (E.Raw[EF_STATE] = T13_STATE_SHARD)
     and (World.TerrainId = T13_TERRAIN_SHARD4) then
    if (Frame >= 0) and (Frame < T13_SHARD_FRAMES) then
      E.Raw[EF_ANIM_ID] := T13_SHARD4_SPRITES[Frame];
  if E.Raw[EF_STATE] = 2 then
    E.Raw[EF_ANIM_ID] := T13_STATE2_SPRITE;
  if E.Raw[EF_STATE] = 3 then
    E.Raw[EF_ANIM_ID] := T13_STATE3_SPRITE;

  if (AGameState <> GS_PLAY) and (AGameState <> GS_PLAY_ALT) then
    Exit;

  if E.Raw[EF_STATE] = T13_STATE_SPLASH then
  begin
    { A pull that grows by one a frame, with no cap, and the X step comes off
      the direction table rather than a velocity. }
    Inc(E.Raw[EF_VEL_Y]);
    Inc(E.Raw[EF_POS_X], DirVelX(E.Raw[EF_FACING]));
    Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T13_SPLASH_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      Inc(E.Raw[EF_FLAG1C]);
      if E.Raw[EF_FLAG1C] > T13_SPLASH_FRAMES - 1 then
      begin
        World.DestroyEntity(E, False);
        Exit;
      end;
    end;
  end;

  if E.Raw[EF_STATE] = T13_STATE_SHARD then
  begin
    Inc(E.Raw[EF_VEL_Y], T13_GRAVITY);
    if E.Raw[EF_VEL_Y] > T13_TERMINAL then
      E.Raw[EF_VEL_Y] := T13_TERMINAL;
    { TWICE. The original writes POS_Y += VEL_Y on two separate lines with the
      X move between them, so this falls at double the rate its velocity
      says. Reproduced, not corrected. }
    Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);
    Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);
    Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T13_SHARD_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      Inc(E.Raw[EF_FLAG1C]);
      if E.Raw[EF_FLAG1C] > T13_SHARD_FRAMES - 1 then
      begin
        World.DestroyEntity(E, False);
        Exit;
      end;
    end;
  end;

  { States 2 and 3 share one arm - the original tests `state - 2 < 2` - and
    neither animates nor ends. }
  if (E.Raw[EF_STATE] = 2) or (E.Raw[EF_STATE] = 3) then
  begin
    Inc(E.Raw[EF_VEL_Y], T13_GRAVITY);
    if E.Raw[EF_VEL_Y] > T13_TERMINAL then
      E.Raw[EF_VEL_Y] := T13_TERMINAL;
    Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);
    Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);
    Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);
  end;
end;

procedure EntityUpdate_Type08(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= TYPE8_FRAMES) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := TYPE8_SPRITES[Frame];

  if AGameState <> GS_PLAY then
    Exit;

  Inc(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] > TYPE8_TICKS then
  begin
    E.Raw[EF_BLOCK_B] := 0;
    Inc(E.Raw[EF_FLAG1C]);
  end;
  if E.Raw[EF_FLAG1C] > TYPE8_FRAMES - 1 then
    World.DestroyEntity(E, False);
end;

procedure EntityUpdate_Type26(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Variant: Integer;
begin
  Variant := E.Raw[EF_VARIANT];
  if (Variant < 0) or (Variant >= TYPE26_VARIANTS) then
    Variant := 0;
  E.Raw[EF_ANIM_ID] := TYPE26_SPRITES[Variant];

  if AGameState <> GS_PLAY then
    Exit;

  { Straight up, at a fixed rate - no gravity and no horizontal drift. }
  Dec(E.Raw[EF_POS_Y], TYPE26_LIFT);

  Inc(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] > TYPE26_LIFETIME then
    World.DestroyEntity(E, False);
end;

procedure EntityUpdate_Type16_Sign(var E: TEntity);
begin
  E.Raw[EF_ANIM_ID] := SIGN_SPRITE;
end;

procedure EntityUpdate_Type22(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
begin
  E.Raw[EF_ANIM_ID] := TYPE22_SPRITE;
  { The original ignores what this answers, so this does too. }
  EntityUpdateDying(E, AGameState, World);
end;

procedure EntityUpdate_Type33_Explosion(var E: TEntity; AGameState: Integer;
                                        World: TEntityWorld);
var
  I, Slot, Facing, Frame: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  { The original indexes unchecked. It cannot actually run past the end - the
    frame that would do it is the one that destroys the entity, and the sprite
    is set before that - so this clamp is unreachable rather than corrective. }
  if (Frame < 0) or (Frame >= BOOM_FRAMES) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := BOOM_SPRITES[Frame];

  if AGameState <> GS_PLAY then
    Exit;

  if E.Raw[EF_STATE] = 0 then
  begin
    E.Raw[EF_STATE] := 1;
    for I := 1 to BOOM_SPARKS do
    begin
      Slot := World.Spawn(EKIND_MINOR, BOOM_SPARK_TYPE,
                          E.Raw[EF_POS_X] - POSITION_BIAS,
                          E.Raw[EF_POS_Y] - POSITION_BIAS);
      World.SetSpawnField(Slot, EF_BLOCK_A + 1, 0);

      { One heading, both tables - a radial burst. The two speeds are drawn
        separately, so the spread is an ellipse rather than a circle. }
      Facing := World.RandomBelow(DIR_COUNT);
      World.SetSpawnField(Slot, EF_FACING, Facing);
      World.SetSpawnField(Slot, EF_VEL_X,
        (World.RandomBelow(BOOM_SPEED_MAX) + 1) * HalfExtent(DirVelX(Facing)));
      World.SetSpawnField(Slot, EF_VEL_Y,
        (World.RandomBelow(BOOM_SPEED_MAX) + 1) * HalfExtent(DirVelY(Facing)));
    end;
  end;

  Inc(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] > BOOM_TICKS then
  begin
    E.Raw[EF_BLOCK_B] := 0;
    Inc(E.Raw[EF_FLAG1C]);
  end;
  if E.Raw[EF_FLAG1C] > BOOM_FRAMES - 1 then
    World.DestroyEntity(E, False);
end;

procedure EntityUpdate_Type32_Emitter(var E: TEntity; AGameState: Integer;
                                      World: TEntityWorld);
var
  Radius, OffX, OffY: Integer;
begin
  if AGameState <> GS_PLAY then
    Exit;

  { The countdown ticks only during play, and the rest happens only on the
    frame it goes below zero. }
  Dec(E.Raw[EMIT_NEXT]);
  if E.Raw[EMIT_NEXT] >= 0 then
    Exit;

  Dec(E.Raw[EMIT_SOUND_NEXT]);
  if E.Raw[EMIT_SOUND_NEXT] < 0 then
  begin
    E.Raw[EMIT_SOUND_NEXT] := E.Raw[EMIT_SOUND_EVERY];
    World.PlaySound(SND_BOM01);
  end;

  { Scatter in PIXELS: plus or minus radius * 8. }
  Radius := E.Raw[EMIT_RADIUS];
  OffX := World.RandomBelow(Radius shl EMIT_RADIUS_SHIFT) - Radius * 8;
  OffY := World.RandomBelow(Radius shl EMIT_RADIUS_SHIFT) - Radius * 8;
  World.Spawn(EKIND_MINOR, EMIT_SPAWN_TYPE,
              E.Raw[EF_POS_X] - POSITION_BIAS + OffX * 32,
              E.Raw[EF_POS_Y] - POSITION_BIAS + OffY * 32);

  E.Raw[EMIT_NEXT] := E.Raw[EMIT_EVERY];
  Inc(E.Raw[EMIT_COUNT]);
  if E.Raw[EMIT_TOTAL] < E.Raw[EMIT_COUNT] then
    World.DestroyEntity(E, True);
end;

procedure EntityUpdate_Type27(var E: TEntity; AGameState: Integer);
var
  Frame: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= SAVE_POINT_FRAMES) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := SAVE_POINT_SPRITES[Frame];

  if AGameState <> GS_PLAY then
    Exit;

  Inc(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] > SAVE_POINT_TICKS then
  begin
    E.Raw[EF_BLOCK_B] := 0;
    E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod SAVE_POINT_FRAMES;
  end;
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
      27: EntityUpdate_Type27(E^, AGameState);
      32: EntityUpdate_Type32_Emitter(E^, AGameState, World);
      33: EntityUpdate_Type33_Explosion(E^, AGameState, World);
      2:  EntityUpdate_Type02(E^, AGameState, World);
      3:  EntityUpdate_Type03(E^, AGameState, World);
      4:  EntityUpdate_Type04(E^, AGameState, World);
      5:  EntityUpdate_Type05(E^, AGameState, World);
      6:  EntityUpdate_Type06(E^, AGameState, World);
      7:  EntityUpdate_Type07(E^, AGameState, World);
      8:  EntityUpdate_Type08(E^, AGameState, World);
      9:  EntityUpdate_Type09(E^, AGameState);
      10: EntityUpdate_Type10(E^, AGameState, World);
      11: EntityUpdate_Type11(E^, AGameState);
      12: EntityUpdate_Type12(E^, AGameState);
      13: EntityUpdate_Type13(E^, AGameState, World);
      15: EntityUpdate_Type15(E^, AGameState, World);
      17: EntityUpdate_Type17(E^);
      19: EntityUpdate_Type19(E^);
      21: EntityUpdate_Type21(E^, AGameState, World);
      23: EntityUpdate_Type23(E^, AGameState, World);
      28: EntityUpdate_Type28(E^, AGameState, World);
      29: EntityUpdate_Type29(E^, AGameState, World);
      30: EntityUpdate_Type30(E^, AGameState, World);
      31: EntityUpdate_Type31(E^, AGameState, World);
      34: EntityUpdate_Type34(E^, AGameState, World);
      35: EntityUpdate_Type35(E^, AGameState, World);
      37: EntityUpdate_Type37(E^, AGameState, World);
      38: EntityUpdate_Type38(E^, AGameState, World);
      39: EntityUpdate_Type39(E^, AGameState, World);
      40: EntityUpdate_Type40(E^, AGameState, Inp, World);
      41: EntityUpdate_Type41(E^, AGameState, World);
      42: EntityUpdate_Type42(E^, AGameState, World);
      43: EntityUpdate_Type43(E^, AGameState, World);
      44: EntityUpdate_Type44(E^, AGameState, World);
      16: EntityUpdate_Type16_Sign(E^);
      22: EntityUpdate_Type22(E^, AGameState, World);
      26: EntityUpdate_Type26(E^, AGameState, World);
      36: EntityUpdate_Type36_FallingItem(E^, AGameState, World);
      { the other 36 arms are in HANDLER_ADDR, untranslated }
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
        EntityPlayerTouch(E^, Pool.Entity(0)^, P, Inp, World);
      if Assigned(EntityTakeProjectileHits) then
        EntityTakeProjectileHits(E^, World);
    end;

    if (E^.Raw[EF_TYPE] = TYPE_TOUCH_IN_STATE_3) and (E^.Raw[EF_STATE] = 3)
       and IsAlive(E^) then
      if Assigned(EntityPlayerTouch) then
        EntityPlayerTouch(E^, Pool.Entity(0)^, P, Inp, World);

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
      World.DestroyEntity(E^, False);
  end;
end;


initialization
  { The touch pass is real now. It stays a variable only so a test can put a
    counting stub in its place. }
  EntityPlayerTouch := @PlayerTouch;
  EntityTakeProjectileHits := @TakeProjectileHits;

end.