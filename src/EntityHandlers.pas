{ EntityHandlers - the per-type entity update handlers.

  Entity_UpdateAll @ 0x004608BC switches on EF_TYPE into one handler per type.
  This unit accumulates them, translated one at a time straight from the
  disassembly - see CLAUDE.md section 3a for why that ordering is the rule
  rather than a preference.

  Each handler carries the address it came from, and that address is not
  decoration: tools/coverage.py reads it, and it is what to re-decompile
  against when auditing. HANDLER_ADDR below maps every type to its arm,
  while tools/implemented.py verifies that all 149 game-layer functions have
  implementations. Entity names come only from tools/entity_names.csv; blank
  names remain numeric rather than being guessed here. }

unit EntityHandlers;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils, Entities, GameState, SoundTable, PlayerState, Player, Directions;

const
  { --- The sprite DATA region, verbatim from 0x0046BC2C ---------------------

    DIV-011 EXISTED BECAUSE EACH TABLE WAS DECLARED ON ITS OWN. Four
    handlers index theirs with no bounds test - the disassembly is
    `base + Frame*4 + Row*0x10` in all four, at 0x00459A0C, 0x0045A08C,
    0x0045A3E0 and 0x0045B0CC - and out of range the original reads
    straight on into the next table, because the tables are laid end to
    end with every one flush against its neighbour.

    Clamping was the only honest answer while each table was a separate
    array: writing a neighbour's rows into one would assert a length the
    layout denies. This is the region ITSELF, so an overrun inside it is a
    read of the same memory the original reads.

    The per-type arrays below are unchanged and still say what each table
    IS. --selftest-spritedata asserts every one equals its slice of this,
    so the two cannot drift apart.

    RESIDUAL: an index far enough past a table to leave the REGION has
    nothing to read and is still clamped. That is a much smaller hole than
    the per-table clamp it replaces, and it is what is left of DIV-011. }
  SPRITE_DATA_BASE = $0046BC2C;
  SPRITE_DATA: array[0..245] of Integer = (
      28,   29,   30,   31,   32,   33,   34,   35,   36,   37,
      38,   39,   20,   21,   22,   23,   24,   25,   26,   27,
     200,  201,  202,  203,  204,  205,  206,  207,  208,  209,
     210,  211,   40,   41,   42,   43,  233,  234,  235,  236,
      50,   51,   52,   53,  212,  213,  214,  215,  216,  217,
     218,   64,   65,   66,   65,   67,   68,   69,   70,  219,
     220,  221,  240,  241,  240,  241,  242,  243,  242,  243,
     244,  245,  244,  245,  231,  232,  256,  257,  256,  257,
     258,  259,  258,  259,  260,  261,  260,  261,  283,  284,
     285,  286,  287,   71,   72,   73,   72,  118,  119,  120,
     119,   74,   75,   76,   77,   78,   79,   80,   81,  480,
     482,  483,  484,  485,  486,  487,  488,  480,  481,   82,
     104,  105,   83,   99,  102,  103,   84,   85,  279,  280,
     281,  282,   93,   94,   95,   96,   97,   98,  100,  101,
     222,  223,  224,  225,  226,  222,   54,   61,   62,   59,
      60,   63,   87,   86,   88,   86,   89,   90,   91,   92,
       8,   10,   12,   60,   30,   10,    8,    6,    4,    0,
      10,   20,  500,  501,  502,  501,  503,  512,  513,  514,
     515,  516,  504,  505,  506,  507,  508,  509,  510,  511,
     110,  111,  112,  113,  106,  107,  108,  109,  120,   60,
      30,  227,  228,  229,  230,  246,  247,  248,  249,  250,
     251,    2,    2,    3,    4,    2,    1,  123,  124,  125,
     124,  192,  193,  194,  193,  240,  180,  180,  126,  127,
     128,  127,  129,  130,   30,   20,   10,  120,   60,   30,
      30,   20,   10,    1,    3,    5);

  { Where each unchecked table starts in it, and the row stride they all
    share - Row*0x10 is four ints. }
  SPRITE_ROW = 4;
  T2_AT    = ($0046BC2C - SPRITE_DATA_BASE) div 4;
  T7_AT    = ($0046BCAC - SPRITE_DATA_BASE) div 4;
  MANA_AT  = ($0046BDA0 - SPRITE_DATA_BASE) div 4;
  T38_AT   = ($0046BF24 - SPRITE_DATA_BASE) div 4;

  { Four adjacent sprite tables. What settles an extent here is the LAYOUT,
    not the data: the region is a run of small const arrays laid end to end,
    each reached through its own pointer global, so a table ends where the
    next one begins.

      ptr         base        ints  used by
      0x0046CBA0  0x0046BDA0     8  type 14, as 2 rows of 4 frames (stride 16)
      0x0046D0E4  0x0046BDC0    16  type 24, FLAT - one sprite per variant
      0x0046D32C  0x0046BE00     2  type 24 variant 8's two-frame animation
      0x0046CF00  0x0046BE08     3  type 25, flat

    Each of those pointers has exactly ONE reader in the binary, so no second
    type could need more rows. Type 14's table was once recorded as sixteen
    rows and is two: reading N values out of akuji.exe and finding they match
    proves the VALUES and says nothing about N. tools/table_bounds.py checks
    the extent against the neighbouring pointer instead. }

  MANA_VARIANTS = 2;
  MANA_FRAMES   = 4;
  MANA_SPRITE_TABLE_ADDR = $0046BDA0;
  MANA_SPRITE_TABLE_PTR  = $0046CBA0;
  MANA_SPRITES: array[0..MANA_VARIANTS - 1, 0..MANA_FRAMES - 1] of Integer = (
    ( 71,  72,  73,  72),
    (118, 119, 120, 119));

  { Type 24 @ 0x0045A43C, a bobbing pickup. Sixteen variants, one sprite each,
    in a FLAT table - stride 4, not 16; this one has no frames.

    It reuses EF_FACING as a PHASE rather than a heading, adding DirVelY of it
    and advancing one step of 64 each frame, so it traces one full period of
    the direction table's vertical component just over a second long. Nothing
    else in the game uses the field that way.

    Variant 8 is special twice: its sprite comes from a two-frame table
    instead, and it plays kodou.wav - Japanese for HEARTBEAT - every 61
    frames. }
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

  { Type 27 @ 0x0045A540, the save point. The handler does not know it is one
    - what makes it a save point is the EVENT. Type 27 appears exactly ONCE in
    each of 43 stages, always opcode 1, always with no ParamA argument, and
    with a ParamB byte-identical in all 43:

        0000-03-0000 / 0003-13 / 0003-03-0001

    say line 0; if flag 3 is set, sub-op 13, SAVE; then say line 1. }
  SAVE_POINT_FRAMES = 2;
  SAVE_POINT_ADDR   = $0046BE24;
  SAVE_POINT_PTR    = $0046D18C;
  SAVE_POINT_SPRITES: array[0..SAVE_POINT_FRAMES - 1] of Integer = (84, 85);
  SAVE_POINT_TICKS  = 8;   { advance when the count EXCEEDS it, so every 9 }

  { The one-shot drop applied on the first update, in 1/32 pixel - five pixels.
    Events place things on a tile boundary and this settles them onto it. }
  MANA_SETTLE_DROP = $A0;
  MANA_FRAME_TICKS = 4;   { advance when the timer EXCEEDS this, so every 5 }

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

  { Entity_PlayerTouch @ 0x00457880. Seven touch kinds after one box test, and
    three guards first: the player must not be invulnerable UNLESS the kind is
    3 - which is the only kind that reaches through invulnerability - the
    entity's own EF_TIMER must be 0, and a kind of 0 is not a touch at all.

    Opcode 1, "walk up and press", needs the player STANDING, Up held, and
    Inp.AxisYNegative still clear, which is the edge; the latch is set the
    frame after, so holding Up does not retrigger.

    The original's return value is a local that is never assigned, so callers
    read whatever was on the stack. Entity_UpdateAll ignores it, so this is a
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

  { Type 36, the falling item @ 0x0045A7BC. Its two sprites are chosen by
    EF_FLAG1C, the field Entity_MaybeDropItem writes its rarity roll into - so
    the same flag that makes Entity_TouchLife give a full refill also picks
    which sprite the thing wears on the way down.

    After landing the velocity keeps being added, and what settles it is
    Entity_TileCollideY's zero-delta guard: once the snap leaves the velocity
    at 0 the query stops reporting a collision. }
  DROP_SPRITE_COUNT = 2;
  DROP_TABLE_ADDR   = $0046BE54;
  DROP_TABLE_PTR    = $0046CE18;
  DROP_SPRITES: array[0..DROP_SPRITE_COUNT - 1] of Integer = (100, 101);

  { The effect family, types 3..13. Eleven handlers built from the same four
    moves, and each one's own TN_ constants say which of them it does. What
    the constants cannot say:

      * types 11 and 12 never call Entity_Destroy. Not a leak - they are the
        torch's flame and type 23 owns their lifetime, and anything that
        wanders off is culled by Entity_UpdateAll.
      * types 9 and 13 also run in GS_PLAY_ALT; the rest run in GS_PLAY only.
      * type 6 takes its sprite ROW from block A[1], which the explosion sets
        when it spawns the spark, so one table serves two burst colours. Type
        7 takes its row from the VARIANT.

    The tables sit in one run at 0x0046BC5C, each one's extent being the next
    one's start - the rule tools/table_bounds.py enforces. }
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
  { TWO rows - eight ints. The bound is TYPE8_SPRITES at 0x0046BCCC, exactly
    0x20 past this table, and a twelve-int reading of it overruns into type
    8: the 50 --emudiff sees the original return for variant 2 is type 8's
    first sprite, reached by running off the end of this one. That is
    DIV-011 again.

    An adjacent table's contents are evidence about the ADJACENT table.
    tools/table_extents.py is what pins this one. }
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

  { Type 13, the debris. Its state is set by whoever spawns it - see
    Entity_SpawnDebris's DEBRIS_* kinds in Entities.pas.

    State 1's sprite table depends on the STAGE TERRAIN, with no write at all
    for any terrain but 3 and 4, which leaves whatever sprite it already had.
    States 2 and 3 never end; like types 11 and 12 they rely on the off-screen
    cull.

    Two things reproduced rather than tidied: states 1, 2 and 3 add VEL_Y to
    POS_Y TWICE in the same frame - the original really does write it on two
    separate lines - so debris falls at double the rate its velocity says; and
    the gravity is applied BEFORE the first add, so the first frame moves. }
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

  { Types 15, 21, 23, 28 and 29, the furniture - plus 17 and 19, whose arms
    are a single RET. That is not the same as having no arm, and HANDLER_ADDR
    keeps them apart from types 0, 18 and 20.

    Type 15 is the only handler that writes to the EVENT TABLE: it sets its
    own event's opcode to 9, which triggers nothing, so a thrown switch stays
    thrown without needing a progress flag.

    Type 21's EF_FACING is a signed SPEED, not a direction, negated every
    block A[1] frames, with EF_STATE choosing the axis. ParamA's 'R' letter
    writes both, so a placement carries the speed and the half-period.

    Type 23 owns types 11 and 12 - it spawns them as its flame and destroys
    them - which is why those two never destroy themselves. Both spawns
    SUBTRACT the layer delta: the children are placed after Entity_UpdateAll
    has already carried this frame's scroll into the parent, so without it
    they would be scrolled twice.

    Type 28 does nothing at all unless its variant is 0, so a variant-1
    placement is inert. }
  T15_TABLE_ADDR = $0046BE78;
  T15_SPRITES: array[0..1] of Integer = (61, 62);
  T15_SOUND = $0E;
  T15_THROWN_OPCODE = 9;

  T21_TABLE_ADDR = $0046BE80;
  T21_SPRITE = 59;
  { EF_STATE picks the axis, and the placement data is flush with these two
    values: 12 records, arg 0 taking only 0 (ten times) and 1 (twice). }
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

  { Types 30, 31 and 37 - the first handlers to read DIFFICULTY, and they do
    it through tables indexed by it rather than by branching on it.

    Type 30 doubles its speed and halves its turn period on its first frame,
    and only on difficulty 2.

    Type 31's state 3 is a dead end in this handler: nothing here leaves it.
    The type-35 child writes state 4 back, which is why the state machine
    looks broken and is not.

    Type 37's frame counter wraps with a div AND a mod, and the quotient is
    left in EAX and returned - dead, like type 16's. }
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

  { The table is SIX ints - (222, 223, 224, 225, 226, 222) - but the handler
    animates `frame := (frame + 1) mod 5`, so the sixth is unreachable. Five is
    the read count, not the extent; the sweep in --selftest-entities pins the
    extent separately so the two facts cannot be confused again. }
  T37_FRAMES = 5;  T37_TICKS = 6;
  T37_TABLE_ADDR = $0046BE5C;
  T37_SPRITES: array[0..T37_FRAMES - 1] of Integer = (222, 223, 224, 225, 226);
  T37_PUFF_TYPE = 8;
  T37_DROP      = $100;     { 8 px, once, on arrival }
  T37_TIMERS    = $3C;      { both timers armed to 60 }
  T37_GRAVITY   = 4;
  T37_TERMINAL  = $200;
  T37_LAND_SOUND = $1B;

  { Types 34 and 35, type 31's two children - and what closes the thread type
    31 leaves open, since nothing in type 31 sets its own state 4.

    Type 35 writes Angle_Between(owner, PLAYER) into its owner at the END of
    the telegraph rather than tracking it, which is why type 31's shots all
    leave along one heading however the player moves. It also destroys itself
    the moment its owner's HP reaches 0, so a parent killed mid-wind-up takes
    its telegraph with it.

    Type 34's frames advance on a difficulty divisor of 8, 10 or 12, so the
    shot animates FASTER on easy and, dying at the end of its animation, has a
    shorter range there. That is backwards from every other difficulty table
    and it is what the binary says. }
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

  { Type 2, the player's shot. The state it carries is the WEAPON - Player.pas
    passes its WEAPONS table's ProjState straight through - and only the
    charge accelerates.

    The sparks a wall impact throws carry 1 in block A[1] for a charge shot
    and 0 otherwise, which is what selects between type 6's two sprite rows,
    so a charged impact scatters a different colour.

    Their speed multiplier is Random(2) + 1. Type 33's explosion uses
    Random(3) + 1 for the same idiom, so these are not the same burst and the
    difference is deliberate. }
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

  { Types 38 and 39, a turret and its shot - the same division of labour
    types 31 and 35 have, and seeing it twice is what makes it a pattern: the
    parent holds a state it cannot leave, and the CHILD moves it on.

    Type 38's state 1 counter is gated by Entity_IsOffScreen, so a turret you
    cannot see never counts down and never fires. Its facing and its sprite
    row are both its VARIANT.

    Type 39 writes its owner's state 5 only IF ITS OWN HP IS ZERO, so a shot
    that still has HP leaves its parent stuck in state 4 - which is what type
    40 relies on. }
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

  { Type 40, the springboard - the first handler that reaches into the
    PLAYER'S ENTITY and rewrites it. Nothing here sets state 2, the launch;
    the touch handler does.

    The launch keeps the speed the player arrived with but takes the
    DIRECTION from whatever is held at that moment, so you can turn round on
    the spring. With no input the field is left alone entirely.

    Variant 1's shot is a type 39 with its HP set to 1, and only a ZERO-hp
    type 39 writes back to its owner - which is how the same shot type serves
    this parent and type 38's with different lifetimes. Its aim is a
    direction rather than an angle, and a zero is corrected to 0x20 so a shot
    fired at a player standing exactly in line still goes somewhere. }
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

  { Type 41, the hopper. On HARD ONLY it doubles its speed on its first frame
    - the same one-line scaling type 30 has. Like type 38, its idle counts
    only while on screen, so a hopper off screen is frozen mid-crouch rather
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

  { Type 42, a boss. Its timings scale with its own HP as well as with the
    difficulty, so a boss that has taken damage acts faster - a difficulty
    curve inside a single fight.

    EF_SHOTS, normally an owner's live-shot count, is reused here as the
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
  { -$40 and -$60, not -$C0 and -$A0. The handler writes these as the literals
    0xFFFFFFC0 and 0xFFFFFFA0, which are -64 and -96; the low byte is the two's
    complement, not the magnitude. Same slip as T44_LAUNCH_VY, and found the
    same way it should have been found the first time -
    tools/const_immediates.py, which searches the handler's own code for the
    encoding of each constant and reports when the FOLD is present instead.

    --emudiff could not have caught these: type 42 only reaches states 2 and 4
    through transitions the probe's four starting states never make. }
  T42_RISE_VY = -$40;
  T42_RETREAT_VY = -$60;
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

  { Types 43 and 44. Type 43 is four instructions and one of them is the
    point:

        EF_VULN_KIND := variant + 0x5A

    which lands exactly on the armour block Entity_TakeProjectileHits knows,
    0x5A..0x5D. One entity type covers all four armours and the placement's
    variant picks which - which is why those four constants sit contiguously
    rather than scattered like the other kinds. Written EVERY frame, not once.

    Type 44 has no Entity_Destroy at all; like types 9, 11 and 12 it relies on
    the off-screen cull. }
  T43_VARIANTS = 4;
  T43_TABLE_ADDR = $0046C02C;
  T43_SPRITES: array[0..T43_VARIANTS - 1] of Integer = (121, 122, 179, 442);
  T43_VULN_BASE = $5A;      { VULN_ARMOUR_1 - see the block above }

  T44_FRAMES = 8;  T44_TICKS = 2;
  T44_TABLE_ADDR = $0046C03C;
  T44_SPRITES: array[0..T44_FRAMES - 1] of Integer =
    (505, 506, 507, 508, 509, 510, 511, 512);
  { -$50, not -$B0. The disassembly writes the launch velocity as the literal
    0xFFFFFFB0, and that is -80, i.e. -$50 - the low byte is the two's
    complement, not the magnitude. Transcribed as -$B0 it was -176, and the
    entity left the ground more than twice as fast as it should.

    --emudiff caught it as a 96-unit error in one frame of EF_POS_Y: the
    original moved -78 (launch -80, plus one tick of gravity), ours moved -174. }
  T44_LAUNCH_VY = -$50;
  T44_GRAVITY = 2;
  T44_TERMINAL = $200;

  { Types 45 and 46. Type 45 is the only handler that reads EF_RIDDEN, the
    flag Entity_SolidCollideY sets when something stands on a solid - and that
    flag is cleared at the END of every frame whatever state it is in, so it
    is a one-frame signal the collision has to re-set to keep the count going.
    Its shake threshold SUBTRACTS a difficulty figure from the placement's own
    count, so a harder game crumbles it sooner.

    Type 46 wakes on horizontal pixel distance, and an EASIER game wakes it
    LATER. Its initial heading is Random(64) - the second use of the RNG
    outside the debris - so a room full of them does not move in lockstep. }
  T45_FRAMES = 5;  T45_TICKS = 8;
  T45_TABLE_ADDR = $0046C074;
  T45_SPRITES: array[0..T45_FRAMES - 1] of Integer = (131, 132, 133, 134, 133);
  T45_TOUGH_ADDR = $0046C088;
  T45_TOUGH: array[0..2] of Integer = (0, 2, 4);
  T45_SHAKE_FIRST = 1;      { the loop is frames 1..4 }
  T45_BREAK_SOUND = $1C;
  T45_GONE_FRAMES = $3C;

  T46_FRAMES = 4;  T46_TICKS = 4;
  T46_TABLE_ADDR = $0046C094;
  T46_SPRITES: array[0..4] of Integer = (136, 137, 138, 137, 135);
  T46_SLEEP_FRAME = 4;
  T46_RANGE_ADDR = $0046C0A8;
  T46_TURN_ADDR  = $0046C0B4;
  T46_SPEED_ADDR = $0046C0C0;
  T46_RANGE: array[0..2] of Integer = (64, 80, 128);   { easy wakes LATER }
  T46_TURN:  array[0..2] of Integer = (4, 4, 2);
  T46_SPEED: array[0..2] of Integer = (2, 3, 4);
  T46_RISE = $A0;
  T46_WAKE_SOUND = $1D;
  T46_TURN_TIMER = 1;       { Steer's timer slot }

  { Type 47, the lobber. Its two difficulty tables run in OPPOSITE directions
    - the wait before winding up is 120, 60, 60 and the rest afterwards is
    180, 120, 60. Both make it fire more often, but they were tuned as
    separate numbers rather than one.

    It reads only the first two entries of a four-int angle table - the loop
    is a `do ... while (--n)` from 2 - so the other two are unreachable from
    this handler. }
  T47_FRAMES = 2;  T47_TICKS = 8;
  T47_TABLE_ADDR = $0046C0CC;
  T47_SPRITES: array[0..4] of Integer = (139, 140, 141, 142, 143);
  T47_WAIT_ADDR = $0046C0E0;
  T47_REST_ADDR = $0046C0EC;
  T47_ANGLES_ADDR = $0046C108;
  T47_WAIT: array[0..2] of Integer = (120, 60, 60);
  T47_REST: array[0..2] of Integer = (180, 120, 60);
  T47_ANGLES: array[0..1] of Integer = (-1, 1);
  T47_WIND_FIRST = 1;
  T47_WIND_LAST = 3;
  T47_OFFSCREEN_MARGIN = 2;
  T47_SHOT_TYPE = $30;      { 48 }
  T47_SHOT_LIFT = $200;
  T47_SHOT_VY = -$40;
  T47_ANGLE_SHIFT = 5;
  T47_FIRE_SOUND = $1E;

  { Type 48, the bouncing shot. Each rebound is (bounces left + 1) * -0x10,
    so the arc decays out of the counter and there is no separate decay term.

    On the SECOND-TO-LAST bounce it arms EF_DEATH_TIMER to 3600 frames, far
    longer than it can survive its remaining bounce. Entity_UpdateAll uses
    that field's parity for the damage flicker, so the practical effect is
    that the ball starts BLINKING on its last bounce, not that it times out.

    It copies field 0x2C into its velocity on any frame that field is
    non-zero, then clears it. Entity_Spawn zeroes 0x2C and type 47 sets
    EF_VEL_X directly, so nothing in the shipped game ever puts anything
    there. Reproduced because the read is real. }
  T48_FRAMES = 4;  T48_TICKS = 8;
  T48_TABLE_ADDR = $0046C0F8;
  T48_SPRITES: array[0..T48_FRAMES - 1] of Integer = (237, 238, 239, 238);
  T48_BOUNCES = 4;
  T48_GRAVITY = 2;
  T48_TERMINAL = $200;
  T48_BOUNCE_SOUND = $21;
  T48_REBOUND_STEP = -$10;
  T48_BLINK_TIMER = $E10;   { armed on the second-to-last bounce }
  T48_HANDOFF = $2C;        { the one-shot velocity slot }

  { Type 49, the diver. Its trigger distance runs the ordinary way round -
    HARDER sees further - and above easy it also AIMS, because that write sits
    inside `if difficulty > 0`; on easy it dives straight down.

    It calls Entity_SpawnDebris twice, at the start and end of the dive, which
    is the only use of that function outside a death: the debris doubles as a
    dust puff here.

    It clears EF_BLOCK_A[1] and EF_CHILD_B when the dive starts, and neither
    is read anywhere in this handler. }
  T49_FRAMES = 2;  T49_TICKS = $10;
  T49_TABLE_ADDR = $0046C118;
  T49_SPRITES: array[0..3] of Integer = (144, 145, 146, 147);
  T49_RANGE_ADDR = $0046C128;
  T49_REST_ADDR  = $0046C134;
  T49_RANGE: array[0..2] of Integer = (64, 128, 256);   { harder sees further }
  T49_REST:  array[0..2] of Integer = (120, 120, 60);
  T49_BOB_SHIFT = 2;        { a quarter of the heading's Y component }
  T49_DIVE_VY = -$C0;
  T49_GRAVITY = 4;
  T49_DIVE_END = $BF;
  T49_RISING_FRAME = 2;
  T49_FALLING_FRAME = 3;
  T49_AIM_SHIFT = 5;

  { Type 50, the opener. While it is open it REWRITES ITS OWN EF_VULN_KIND,
    so the window in which it can be hurt is part of the animation rather than
    a property of the type.

    Its states are 1, 2, 3, 5 and 6 - there is no 4, and nothing here moves it
    from 3 to 5 either; the type-39 shot it spawns does, the same parent-child
    arrangement types 31/35 and 38/39 use.

    On EASY it starts by SUBTRACTING 2 from its own EF_HP - the only handler
    that makes itself weaker rather than the difficulty making it stronger. }
  T50_FRAMES = 4;  T50_TICKS = 8;
  T50_TABLE_ADDR = $0046C140;
  T50_SPRITES: array[0..5] of Integer = (148, 149, 150, 149, 151, 152);
  T50_PATROL_ADDR = $0046C158;
  T50_HOLD_ADDR   = $0046C164;
  T50_PATROL: array[0..2] of Integer = (60, 60, 60);   { deliberately flat }
  T50_HOLD:   array[0..2] of Integer = (120, 60, 60);
  T50_EASY_HP_PENALTY = -2;
  T50_OPEN_FIRST = 4;
  T50_OPEN_LAST  = 5;
  T50_OFFSCREEN_MARGIN = 2;
  T50_SHOT_TYPE = $27;      { 39 }
  T50_SHOT_SPEED = 2;
  T50_VULN_OPEN    = 1;
  T50_VULN_CLOSING = 2;

  { Types 51 and 53. Neither has an end: type 51 homes until something kills
    it, and type 53 runs until it leaves the screen.

    Type 53's sprite table is two rows of FIVE, so its stride is 0x14 rather
    than the usual 0x10. }
  T51_FRAMES = 4;  T51_TICKS = 8;
  T51_TABLE_ADDR = $0046C170;
  T51_SPRITES: array[0..T51_FRAMES - 1] of Integer = (153, 154, 155, 154);
  T51_TURN_TIMER = 1;
  T51_TURN_RELOAD = 6;
  T51_DEATH_TIMER = 2;

  T53_ROW = 5;
  T53_WIND_LAST = 2;
  T53_RUN_FIRST = 3;
  T53_RUN_LAST = 4;
  T53_TICKS = 4;
  T53_TABLE_ADDR = $0046C1D0;
  T53_SPRITES: array[0..1, 0..T53_ROW - 1] of Integer =
    ((512, 513, 514, 508, 509),      { going left  }
     (512, 513, 514, 510, 511));     { going right }
  T53_CHARGE_SOUND = 7;

  { Type 56, the burst trap. Its aim takes Angle_Between(self, player) and
    adds a difficulty SKEW of 0, -4 or -8, so harder settings LEAD the shot
    rather than aiming straight at the player.

    The heading wrap is written `next := aim + 4; if next > 63 then next :=
    aim - 0x3C` - a subtraction of 60 from the PREVIOUS value rather than a
    mask on the new one. It is exactly equivalent to (aim + 4) mod 64 for
    every aim in 0..63, which is worth stating because it does not look it.
    Kept in the original's form anyway.

    The fuse lives in EF_TIMER, which Entity_UpdateAll counts down, so this
    handler only watches for zero. }
  T56_FRAMES = 3;
  T56_TABLE_ADDR = $0046C268;
  T56_SPRITES: array[0..T56_FRAMES - 1] of Integer = (156, 157, 158);
  T56_SKEW_ADDR  = $0046C274;
  T56_COUNT_ADDR = $0046C280;
  T56_SPEED_ADDR = $0046C28C;
  T56_SKEW:  array[0..2] of Integer = (0, -4, -8);   { harder LEADS the shot }
  T56_COUNT: array[0..2] of Integer = (0, 2, 4);     { plus one }
  T56_SPEED: array[0..2] of Integer = (2, 2, 3);
  T56_TRIGGER_SCALE_X = 5;
  T56_TRIGGER_SCALE_Y = 2;
  T56_FUSE = 4;
  T56_SHOT_TYPE = $39;      { 57 }
  T56_FAN_STEP = 4;
  T56_FAN_WRAP = $3C;       { subtracted from the previous heading, not a mask }

  { Type 59, the riser. Its wake range is a bare literal - the only proximity
    test in the game that is not difficulty-keyed. It leaves the rise the
    moment its velocity turns positive, which is the apex rather than a fixed
    time, and takes Angle_Between ONCE on entering the flight, so it commits
    to a heading at the top of its arc and cannot correct.

    Nothing ends it. Once flying it flies until it is culled. }
  T59_TABLE_ADDR = $0046C300;
  T59_SPRITES: array[0..5] of Integer = (270, 162, 163, 164, 165, 166);
  T59_SPEED_ADDR = $0046C318;
  T59_SPEED: array[0..2] of Integer = (1, 2, 3);
  T59_WAKE_RANGE = $50;     { a bare literal - not difficulty-keyed }
  T59_RISE_VY = -$80;
  T59_GRAVITY = 2;
  T59_HANG_TICKS = 8;
  T59_FLY_TICKS = 4;
  T59_FLY_FIRST = 3;
  T59_FLY_LAST = 5;
  T59_RISE_FRAME = 1;
  T59_HANG_FRAME = 2;

  { Type 52, the boss. Two things the code does not say for itself:

      * it REWRITES ITS OWN EF_INSET_PCT_Y - 70 entering the circle, 20
        entering the dive - and Entity_UpdateAll turns that back into a
        hitbox inset every frame, so it is a small target while circling and
        a large one while diving. Type 50 does the same with EF_VULN_KIND.
      * its HP table is NEGATIVE on every difficulty and applied once at
        spawn, so the type table carries the HARD figure and each easier
        setting subtracts from it. Type 50 does this too, but only on easy.

    Only on hard does it re-aim before circling, and a zero heading is forced
    to +0x80 so it can never stall. }
  T52_FRAMES = 2;  T52_TICKS = 8;
  T52_TABLE_ADDR = $0046C1B0;
  T52_SPRITES: array[0..1, 0..3] of Integer =
    ((500, 501, 502, 506),        { going left  }
     (503, 504, 505, 507));       { going right }
  T52_HP_ADDR     = $0046C180;
  T52_TIMING_ADDR = $0046C1A4;
  T52_COUNT_ADDR  = $0046C18C;
  T52_SPEED_ADDR  = $0046C198;
  T52_HP:     array[0..2] of Integer = (-30, -20, -10);  { all negative }
  T52_TIMING: array[0..2] of Integer = (120, 60, 30);
  T52_COUNT:  array[0..2] of Integer = (2, 3, 4);
  T52_SPEED:  array[0..2] of Integer = (2, 3, 3);
  T52_ENTRY_DROP = $1E0;    { it starts by falling into view }
  T52_ENTRY_VX = -$80;
  T52_HP_PACE_DIV = $28;    { hp div 40 ... }
  T52_HP_PACE_MUL = 100;    { ... times 100, added to the wait }
  T52_INSET_CIRCLE = 70;    { a small target while it circles ... }
  T52_INSET_DIVE = 20;      { ... and a large one while it dives }
  T52_CIRCLE_FRAME = 2;
  T52_DIVE_FRAME = 3;
  T52_TURN_STEP = $10;      { a quarter turn per frame }
  T52_CIRCLE_TICKS = $3C;
  T52_DIVE_VY = -$20;
  T52_GRAVITY = 2;
  T52_LAND_VY = $1F;
  T52_CHARGE_VX = $80;      { forced when the aim comes out zero }
  T52_SUMMON_BEAT = 3;      { the beat on which it summons instead of diving }
  T52_MINION_TYPE = $35;    { 53, the charger }
  T52_MINION_AHEAD = $600;  { 48 px }
  T52_MINION_BELOW = $A0;   { 5 px }
  T52_SND_SUMMON = $24;
  T52_SND_SPAWN  = $25;
  T52_SND_LAND   = 4;

  { Types 54 and 55, the second boss and its fireball. Type 55 MULTIPLIES both
    velocity components by difficulty + 1 EVERY FRAME, so above easy it
    compounds between the frames on which the steer reloads. Kept as written,
    as is the order the two jitter randoms are drawn in - see the handler. }
  T54_FRAMES = 2;  T54_TICKS = $10;
  T54_TABLE_ADDR = $0046C204;
  T54_SPRITES: array[0..T54_FRAMES - 1] of Integer = (500, 501);
  T54_HP_ADDR = $0046C1F8;
  T54_HP: array[0..2] of Integer = (-30, -20, -10);   { type 52's numbers }
  T54_HOP_ADDR = $0046C20C;
  T54_HOPS = 4;
  T54_HOP: array[0..T54_HOPS - 1, 0..1] of Integer =
    ((160, 0), (-320, 0), (160, -96), (0, 96));       { sums to (0, 0) }
  T54_HOP_SCALE = $20;      { a pixel per unit }
  T54_HP_PACE_DIV = 2;      { hp div 2 ... }
  T54_HP_PACE_MUL = 60;     { ... times 60 ... }
  T54_HP_PACE_ADD = 60;     { ... plus 60 }
  T54_BLINK = $1E;          { both timers, entering and leaving the blink }
  T54_HOLD = $3C;
  T54_SHOT_TYPE = $37;      { 55 }
  T54_SND_BLINK = $1C;

  T55_FLY_FRAMES = 8;   T55_FLY_TICKS = 2;
  T55_TRAIL_FRAMES = 7; T55_TRAIL_TICKS = 5;
  T55_FLY_TABLE_ADDR = $0046C22C;
  T55_FLY_SPRITES: array[0..T55_FLY_FRAMES - 1] of Integer =
    (502, 503, 504, 505, 506, 507, 508, 509);
  T55_TRAIL_TABLE_ADDR = $0046C24C;
  T55_TRAIL_SPRITES: array[0..T55_TRAIL_FRAMES - 1] of Integer =
    (510, 511, 512, 511, 510, 511, 512);
  T55_TURN_TIMER = 1;
  T55_TURN_RELOAD = 2;
  T55_HOMING_UNTIL = $F0;   { EF_SHOTS - the homing stops here ... }
  T55_LIFETIME = $F0;       { ... and EF_BLOCK_B[4] ends it one frame later }
  T55_TRAIL_EVERY = $10;
  T55_TRAIL_SPREAD = $10;   { RandomBelow(16) - 8, so eight pixels either way }
  T55_TRAIL_CENTRE = 8;
  T55_TRAIL_SCALE = $20;
  T55_TRAIL_DEPTH = 3;
  T55_TRAIL_BLINK = 2;
  T55_TRAIL_TIMER = 2;
  T55_SELF_TYPE = $37;      { 55 - the trail is another one of these }
  T55_SND_LOOP = $26;       { on the frame the animation wraps to 0 }

  { Types 58 and 60. Type 58's setup runs BEFORE Entity_UpdateDying, so one
    killed on its spawn frame still takes its 5-pixel drop. Kept in that order.

    Type 60's `if EF_HP < 11 then EF_HP := 3` is a WRITE, not a clamp: an
    enemy on 10 hp loses 7 and one on 1 hp GAINS 2. Its only difficulty-keyed
    number is the charge speed AFTER enraging, so difficulty changes nothing
    about it until it has been hurt. Its two ledge probes are the same call
    with a different vertical delta - a wall ahead, and no floor one tile
    down. }
  T58_FRAMES = 2;           { 0 and 1 while awake; 2 is the dormant sprite }
  T58_TICKS = 4;
  T58_TABLE_ADDR = $0046C2F4;
  T58_SPRITES: array[0..2] of Integer = (160, 161, 159);
  T58_SLEEP_FRAME = 2;
  T58_SETTLE = $A0;         { 5 px down when it spawns ... }
  T58_RISE = -$60;          { ... and 3 px up when it wakes }
  T58_TRIGGER_SCALE = 3;
  T58_SND_WAKE = $27;

  T60_FRAMES = 2;
  T60_TABLE_ADDR = $0046C324;
  T60_SPRITES: array[0..1, 0..3] of Integer =
    ((167, 168, 169, 170),        { going left  }
     (171, 172, 173, 174));       { going right }
  T60_SPEED_ADDR = $0046C344;
  T60_TURN_ADDR  = $0046C35C;
  T60_RAGE_ADDR  = $0046C350;
  T60_SPEED: array[0..2] of Integer = (1, 1, 1);        { flat }
  T60_TURN:  array[0..2] of Integer = (180, 180, 180);  { flat }
  T60_RAGE:  array[0..2] of Integer = (3, 4, 5);        { the only one keyed }
  T60_SPEED_SHIFT = 4;
  T60_SETTLE = $20;
  T60_RAGE_BELOW = $B;      { hp under 11 ... }
  T60_RAGE_HP = 3;          { ... is SET to 3, up or down }
  T60_RAGE_VARIANT = 2;     { the second pair of frames in each row }
  T60_PUFF_LIFT = $20;
  T60_ANIM_BASE = $C;       { (state - 1) * -6 + 12, so 12 calm and 6 enraged }
  T60_ANIM_STEP = -6;
  T60_LEDGE_PROBE = $400;   { one tile down - no floor there means turn }

  { Type 57, four entities wearing one handler, switched on EF_VARIANT with
    no line shared between the branches: type 56's shot, type 63's skimmer,
    type 65's homing fireball, type 67's egg.

    Variant 1 reads the SAME eight-int table two ways - state 0 as two rows of
    four, picking by the sign of EF_VEL_X, state 1 as one linear walk.

    Variant 2 is type 55's state 0 down to the constants, including the
    multiply by difficulty + 1 every frame.

    Variant 3's bounce is worth reading twice. On the frame it hits a wall it
    writes the EXACT distance to that wall into EF_VEL_X so it lands flush,
    which would throw the reversed velocity away - so the reversal is parked
    in EF_PARKED_VEL and picked up the next frame. It bursts into a type 68
    spawned as an ACTOR in EF_STATE 3, which is where Entity_UpdateAll's
    type-68-in-state-3 special case comes from. }
  T57_V0_FRAMES = 4;  T57_V0_TICKS = 2;
  T57_V0_TABLE_ADDR = $0046C298;
  T57_V0_SPRITES: array[0..T57_V0_FRAMES - 1] of Integer =
    (252, 253, 254, 255);

  T57_V1_FRAMES = 8;  T57_V1_TICKS = 2;
  T57_V1_TABLE_ADDR = $0046C2A8;
  { Read as two rows of four in state 0 and as one run of eight in state 1. }
  T57_V1_SPRITES: array[0..T57_V1_FRAMES - 1] of Integer =
    (262, 263, 264, 265, 266, 267, 268, 269);
  T57_V1_ROW = 4;
  T57_V1_HOP = -$40;
  T57_V1_GRAVITY = 2;
  T57_V1_TERMINAL = $200;
  T57_V1_SND_HIT = $F;

  T57_V2_FRAMES = 8;  T57_V2_TICKS = 2;
  T57_V2_TABLE_ADDR = $0046C2C8;
  T57_V2_SPRITES: array[0..T57_V2_FRAMES - 1] of Integer =
    (271, 272, 273, 274, 275, 276, 277, 278);
  T57_V2_TURN_TIMER = 1;
  T57_V2_TURN_RELOAD = 2;
  T57_V2_HOMING_UNTIL = $F0;
  T57_V2_LIFETIME = $F0;
  T57_V2_TRAIL_EVERY = 8;
  T57_V2_TRAIL_TYPE = $1C;   { 28 }
  T57_V2_END_TYPE = 7;
  T57_V2_END_VARIANT = 1;
  T57_V2_SND_LOOP = $26;

  T57_V3_FRAMES = 3;  T57_V3_TICKS = 2;
  T57_V3_ROCK_FRAMES = 2;
  T57_V3_TABLE_ADDR = $0046C2E8;
  T57_V3_SPRITES: array[0..T57_V3_FRAMES - 1] of Integer = (288, 289, 290);
  T57_V3_HATCH_ADDR = $0046C460;
  T57_V3_HATCH: array[0..2] of Integer = (8, 4, 1);   { hard hatches at once }
  T57_V3_HOPS = 6;
  T57_V3_HOP_UNIT = -$10;
  T57_V3_GRAVITY = 4;
  T57_V3_TERMINAL = $200;
  T57_V3_SND_LAND = $1B;
  T57_V3_SND_HATCH = $31;
  T57_V3_BURST = 8;
  T57_V3_BURST_TYPE = 6;
  T57_V3_SPEED_SPREAD = 2;   { RandomBelow(2) + 3, so 3 or 4 half-components }
  T57_V3_SPEED_BASE = 3;
  T57_V3_HATCHLING = $44;    { 68 - the type Entity_UpdateAll touches twice }
  T57_V3_HATCHLING_STATE = 3;
  T57_V3_HATCHLING_HP = 8;
  T57_V3_HATCHLING_DEPTH = 5;

  { TYPE 61 runs AWAY from you, and the argument order below is how:

        Compare(player.x, self.x) * 4

    Compare(A, B) is the sign of B - A, so this is the sign of self.x -
    player.x, accelerating it further from the player. Every other chaser in
    the game writes the arguments the other way round. It is not a
    transcription slip - type 67 flees an egg with the identical expression,
    and two binaries agree byte for byte here (tools/bindiff.py).

    It also zeroes its OWN EF_HP wherever its box overlaps the player's, in
    both states, so catching it is what kills it. }
  T61_FRAMES = 2;  T61_TICKS = 2;
  T61_TABLE_ADDR = $0046C368;
  T61_SPRITES: array[0..3] of Integer = (175, 176, 177, 178);
  T61_SPEED_ADDR = $0046C378;
  T61_SPEED: array[0..2] of Integer = (4, 6, 8);
  T61_IDLE_TURN = $10;      { a quarter turn a frame - it sways }
  T61_WAKE_X = 6;           { wide and flat }
  T61_WAKE_Y = 2;
  T61_RUN_FIRST = 2;
  T61_RUN_LAST = 3;
  T61_RUN_TICKS = 3;
  T61_ACCEL = 4;
  T61_SPEED_SCALE = $10;
  T61_GRAVITY = 2;
  T61_TERMINAL = $200;
  T61_SQUEAK_EVERY = $1E;
  T61_TOUCH_SCALE = 1;
  T61_SND_SQUEAK = $29;

  T62_FRAMES = 2;  T62_TICKS = 8;
  T62_TABLE_ADDR = $0046C384;
  T62_SPRITES: array[0..1, 0..1] of Integer =
    ((180, 181),      { going left  }
     (182, 183));     { going right }
  T62_SPEED_ADDR = $0046C394;
  T62_SPEED: array[0..2] of Integer = (1, 2, 4);
  T62_SPEED_SCALE = $10;
  { Backwards along its own line of travel, so a stack of them placed on one
    spot with variants 0, 1, 2... spreads into a column all marching the same
    way. The variant is a rank in a queue. }
  T62_RANK_STEP = $400;
  T62_LEDGE_PROBE = $400;
  { Rewritten EVERY FRAME from the geometry. Type 50 also changes its own
    vulnerability, but as part of an animation; this is the only enemy whose
    weak side depends on where the PLAYER is standing. }
  T62_VULN_AWAY = 1;
  T62_VULN_TOWARDS = 2;

  { Types 63 and 64. Type 63 fires on an EQUALITY test against the fire frame
    rather than a threshold, and only while already moving TOWARDS the player
    - the same expression type 62 uses to pick its vulnerability, written out
    again rather than shared. Leaving state 2 negates EF_VEL_X, so it always
    walks back the way it came.

    Type 64's wait threshold is WAIT[difficulty] * EF_VARIANT, so a row of
    them with variants 1, 2, 3 drops in sequence and a variant 0 drops at
    once. Its animation ticks at the top of the handler, outside every state,
    so it flaps at the same rate whatever it is doing. }
  T63_FRAMES = 2;  T63_TICKS = 8;
  T63_TABLE_ADDR = $0046C3A0;
  T63_SPRITES: array[0..1, 0..3] of Integer =
    ((184, 185, 186, 187),        { going left  }
     (188, 189, 190, 191));       { going right }
  T63_FIRE_AT_ADDR  = $0046C3CC;
  T63_SHOT_SPD_ADDR = $0046C3C0;
  T63_RECOVER_ADDR  = $0046C3D8;
  T63_COOLDOWN_ADDR = $0046C3E4;
  T63_FIRE_AT:  array[0..2] of Integer = (40, 40, 20);
  T63_SHOT_SPD: array[0..2] of Integer = (2, 3, 3);
  T63_RECOVER:  array[0..2] of Integer = (60, 60, 30);
  T63_COOLDOWN: array[0..2] of Integer = (120, 120, 60);
  T63_WALK_SPEED = $20;
  T63_LEDGE_PROBE = $400;
  T63_WAKE_X = 6;
  T63_WAKE_Y = 2;
  T63_AIM_FRAME = 2;
  T63_FIRE_FRAME = 3;
  T63_SHOT_TYPE = $39;      { 57 ... }
  T63_SHOT_VARIANT = 1;     { ... variant 1, the skimmer }
  T63_SHOT_AHEAD = $C;      { twelve times its own velocity }
  T63_SHOT_DROP = $80;      { 4 px below }
  T63_SND_FIRE = $2B;

  T64_FRAMES = 2;  T64_TICKS = 2;
  T64_TABLE_ADDR = $0046C3F0;
  T64_SPRITES: array[0..T64_FRAMES - 1] of Integer = (420, 421);
  T64_WAIT_ADDR = $0046C3F8;
  T64_REST_ADDR = $0046C404;
  T64_RISE_ADDR = $0046C410;
  T64_WAIT: array[0..2] of Integer = (30, 20, 10);   { times EF_VARIANT }
  T64_REST: array[0..2] of Integer = (60, 40, 20);
  T64_RISE: array[0..2] of Integer = (2, 3, 4);
  T64_NUDGE = $200;         { 16 px right, once, on its first frame }
  T64_GRAVITY = 4;
  T64_TERMINAL = $200;
  T64_RISE_SCALE = -$10;
  T64_WAVE_TYPE = 3;
  T64_WAVE_OUT = $300;      { 24 px to each side ... }
  T64_WAVE_DROP = $100;     { ... and 8 px down }
  T64_WAVE_SPEED = $20;
  T64_SND_SLAM = $2A;

  { Types 65 and 66. Type 65 is the only enemy that reads the INPUT STATE: it
    will not start until ATTACK is pressed while the player stands in its box.
    It writes EF_VULN_KIND and EF_HIT_SOUND onto the type 57 it fires, which
    no other spawner does, so its fireball can be hurt. Above easy it gives
    ITSELF 2 more HP - the opposite direction from types 50, 52 and 54.

    Type 66's two sign tests are written differently - the anchor asks
    Compare(EF_FACING, 0) < 1 and the satellite < 0 - so at EF_FACING = 0 both
    still advance. The asymmetry is real and harmless. }
  T65_FRAMES = 2;  T65_TICKS = 4;
  T65_TABLE_ADDR = $0046C41C;
  T65_SPRITES: array[0..T65_FRAMES - 1] of Integer = (195, 196);
  T65_HOP_ADDR = $0046C424;
  T65_HOPS = 2;
  T65_HOP: array[0..T65_HOPS - 1] of Integer = (-96, 96);
  T65_HOP_SCALE = $20;
  T65_HARD_HP_BONUS = 2;    { it gives ITSELF hp - the others take it away }
  T65_WAKE_X = 10;
  T65_WAKE_Y = 2;
  T65_ATTACK_BUTTON = 1;
  T65_BLINK = $1E;
  T65_HOLD = $3C;
  T65_AIM_SHIFT = 5;
  T65_SHOT_TYPE = $39;      { 57 ... }
  T65_SHOT_VARIANT = 2;     { ... variant 2, the homing fireball }
  T65_SHOT_SPEED = $40;
  T65_SHOT_VULN = 6;
  T65_SHOT_HIT_SOUND = 2;
  T65_BOB_TICKS = 2;
  T65_SND_BLINK = $1C;

  T66_ANCHOR = 0;
  T66_SATELLITE = 1;
  T66_V0_FRAMES = 3;
  T66_V0_TABLE_ADDR = $0046C42C;
  T66_V0_SPRITES: array[0..T66_V0_FRAMES - 1] of Integer = (197, 198, 199);
  T66_V1_FRAMES = 2;  T66_V1_TICKS = 2;
  T66_V1_TABLE_ADDR = $0046C438;
  T66_V1_SPRITES: array[0..T66_V1_FRAMES - 1] of Integer = (490, 491);
  T66_SELF_TYPE = $42;      { 66 - the anchor spawns another of itself }
  T66_LIFT_UNIT = -$A0;     { facing * period * this, above the anchor }
  T66_ANCHOR_DEPTH = 2;
  T66_SND_LAP = $2E;        { on every wrap of the orbit }

  { Types 67 and 68, and the last of type 57. With type 67's egg, every
    variant of type 57 has an owner - 56's burst, 63's skimmer, 65's fireball,
    67's egg - so the four-things-in-one-handler at 0x0045D00C is four things
    four different enemies needed rather than a grab bag.

    Type 67's retreat uses Compare(player.x, self.x), the AWAY arithmetic that
    looks like a slip in type 61. Two handlers writing it settles that it is
    not a typo.

    Type 68 rewrites BOTH its own hitbox insets from a per-FRAME table while
    it animates in state 3. Types 50 and 52 also modify their own hitbox, but
    from a state; this is the only one driving it frame by frame, and it is
    why Entity_UpdateAll gives a state-3 type 68 a SECOND Entity_PlayerTouch -
    the window to catch it is the animation.

    Nothing here sets state 4; whatever catches it does. Its landing is the
    only Entity_Destroy in any handler translated so far that passes True, so
    it is the only one that pays out loot. }
  T67_FRAMES = 4;  T67_TICKS = 4;
  T67_TABLE_ADDR = $0046C440;
  T67_SPRITES: array[0..4] of Integer = (438, 439, 440, 439, 441);
  T67_LAY_FRAME = 4;        { the fifth entry, outside the walk loop }
  T67_RANGE_ADDR    = $0046C46C;
  T67_COOLDOWN_ADDR = $0046C454;
  T67_RANGE:    array[0..2] of Integer = (6, 8, 10);   { harder sees further }
  T67_COOLDOWN: array[0..2] of Integer = (120, 30, 10);
  T67_WAKE_Y = 4;
  T67_WALK_SHIFT = 4;
  T67_BOLT_SHIFT = 6;       { the sprint is sixteen times the walk }
  T67_FRICTION = 1;
  T67_LEDGE_PROBE = $400;
  T67_LAY_AT = 8;
  T67_LAY_END = $10;
  T67_EGG_TYPE = $39;       { 57 ... }
  T67_EGG_VARIANT = 3;      { ... variant 3 }
  T67_EGG_LIFT = $180;      { 12 px above it }
  T67_EGG_VY = -$40;
  T67_SND_LAY = $2B;

  T68_FRAMES = 8;  T68_TICKS = 4;
  T68_TABLE_ADDR = $0046C478;
  T68_SPRITES: array[0..T68_FRAMES - 1] of Integer =
    (492, 493, 494, 495, 496, 497, 498, 499);
  T68_INSET_ADDR = $0046C498;
  { One entry per frame, written to BOTH insets. The catchable window is the
    animation itself - see the T67_/T68_ note above. }
  T68_INSET: array[0..T68_FRAMES - 1] of Integer =
    (70, 55, 55, 40, 40, 50, 90, 90);
  T68_RISE = -$10;
  T68_GRAVITY = 2;
  T68_TERMINAL = $200;
  T68_RISING_STATE = 3;
  T68_CAUGHT_STATE = 4;     { nothing in this handler ever sets it }

  { Types 69 and 70. Type 69 sets Progress[the first four characters of its
    event's ParamB] UNCONDITIONALLY - no opcode test, and after the destroy
    rather than inside it - so it sets its flag whatever its event's opcode
    says, which Entity_Destroy would not have done.

    Type 70 watches `EF_HP <> 100`: not a threshold and not zero, so the
    first point of damage of any size ends it. Variant 1's sprite table is
    (0, 1, 2, 1, 1) where variant 0's is in the 434..437 range; those low
    numbers are what the binary holds, recorded rather than second-guessed. }
  T69_FRAMES = 4;
  T69_TABLE_ADDR = $0046C4B8;
  T69_SPRITES: array[0..T69_FRAMES - 1] of Integer = (430, 431, 432, 433);
  T69_FRICTION = 4;
  T69_FLOOR_PROBE = $400;   { one tile down; it acts when there is NO floor }
  T69_PRIZE_TYPE = $44;     { 68, spawned straight into its falling state }
  T69_PRIZE_STATE = 4;
  T69_PRIZE_HP = 1;

  T70_FRAMES = 4;  T70_TICKS = 8;
  T70_WALKER = 1;           { variant 1 walks; variant 0 stands still }
  T70_V0_TABLE_ADDR = $0046C4C8;
  T70_V0_SPRITES: array[0..4] of Integer = (434, 435, 436, 435, 437);
  T70_V1_TABLE_ADDR = $0046C4DC;
  T70_V1_SPRITES: array[0..4] of Integer = (0, 1, 2, 1, 1);
  T70_WOUND_FRAME = 4;
  T70_FULL_HP = 100;        { any value but this one counts as wounded }
  T70_WALK_SPEED = $20;
  T70_LEDGE_PROBE = $400;
  T70_DYING_FOR = $78;      { 120 frames of the wound frame, then hp := 0 }

  { Types 71 and 72. Type 71's walk timer only advances while it is ON SCREEN,
    so one that has wandered off the edge walks for ever and never presents
    its vulnerable phase. Its rest table is keyed on COMPLETED curl loops, so
    the harder the game the shorter the window in which it can be hurt.

    Type 72 variant 1 never writes EF_VEL_X or EF_VEL_Y, yet hands the trail
    its EF_VEL_* anyway - whatever it was spawned with, not where it is
    actually going - so the trail does not follow it. Written as found. }
  T71_ROW = 6;
  T71_WALK_FRAMES = 2;  T71_WALK_TICKS = 8;
  T71_CURL_FIRST = 2;   T71_CURL_LAST = 5;  T71_CURL_TICKS = 8;
  T71_TABLE_ADDR = $0046C4F0;
  T71_SPRITES: array[0..1, 0..T71_ROW - 1] of Integer =
    ((443, 444, 445, 446, 447, 446),      { going left  }
     (448, 449, 445, 446, 447, 446));     { going right - four are shared }
  T71_WALK_ADDR = $0046C520;
  T71_REST_ADDR = $0046C52C;
  T71_WALK: array[0..2] of Integer = (180, 180, 180);   { flat }
  T71_REST: array[0..2] of Integer = (2, 1, 0);         { loops, not frames }
  T71_SPEED_SHIFT = 5;
  T71_EASY_HP_PENALTY = -2;
  T71_LEDGE_PROBE = $400;
  T71_OFFSCREEN_MARGIN = 2;
  T71_VULN_WALKING = 7;
  T71_VULN_RESTING = 1;
  T71_STUN = 10;
  T71_SND_CURL = $1C;

  T72_V0_FRAMES = 8;  T72_V0_TICKS = 2;
  T72_V0_TABLE_ADDR = $0046C538;
  T72_V0_SPRITES: array[0..T72_V0_FRAMES - 1] of Integer =
    (472, 473, 474, 475, 476, 477, 478, 479);
  T72_V1_DIRS = 16;         { sixteen sprites for sixty-four headings }
  T72_V1_TABLE_ADDR = $0046C594;
  T72_V1_SPRITES: array[0..T72_V1_DIRS - 1] of Integer =
    (450, 451, 452, 453, 454, 455, 456, 457,
     458, 459, 460, 461, 462, 463, 464, 465);
  T72_V2_FRAMES = 4;  T72_V2_TICKS = 4;
  T72_V2_TABLE_ADDR = $0046C5EC;
  T72_V2_SPRITES: array[0..T72_V2_FRAMES - 1] of Integer = (469, 468, 467, 466);
  T72_SPEED_ADDR = $0046C5D4;
  T72_TRAIL_ADDR = $0046C5E0;
  T72_SPEED: array[0..2] of Integer = (2, 3, 4);
  T72_TRAIL: array[0..2] of Integer = (6, 4, 2);   { harder trails thicker }
  T72_DIR_SHIFT = 2;
  T72_GRAVITY = 4;
  T72_TERMINAL = $200;
  T72_FALLER_CLASS = 6;
  T72_FALLER_VULN = 1;
  T72_FLYER_DEPTH = 3;
  T72_FLYER_LIFE = $168;    { 360 frames }
  T72_TRAIL_DEPTH = 4;
  T72_TRAIL_BLINK = 2;
  T72_SELF_TYPE = $48;      { 72 - the flyer trails copies of itself }
  T72_TRAIL_VARIANT = 2;

  { Types 73 and 74. Type 73 hands THREE state transitions to three different
    children - state 3 to a type 75, state 5 to a type 74, state 8 to a type
    35 - and nothing in its own handler leaves any of them. Read alone it
    looks like it deadlocks three times over.

    `if EF_HP = 0 then frame := 4` sits BEFORE Entity_UpdateDying, so the dead
    pose shows on the frame the death sequence starts rather than one later.

    Type 74's fan is type 56's rebuilt line for line, and its three tables
    hold the SAME NUMBERS as type 56's at different addresses. Types 52 and 54
    duplicate an HP table the same way: these bosses were built by copying a
    working attack and re-entering its constants, not by sharing them. }
  T73_FRAMES = 4;  T73_TICKS = 8;
  T73_TABLE_ADDR = $0046C5FC;
  T73_SPRITES: array[0..4] of Integer = (500, 501, 502, 501, 503);
  T73_DEAD_FRAME = 4;
  T73_WAIT_ADDR   = $0046C610;
  T73_CHARGE_ADDR = $0046C61C;
  T73_WAIT:   array[0..2] of Integer = (20, 15, 10);
  T73_CHARGE: array[0..2] of Integer = (60, 30, 10);
  T73_HP_PACE_DIV = 4;      { hp div 4, times the wait, plus ... }
  T73_HP_PACE_ADD = $14;    { ... twenty }
  T73_ENTRY_SHIFT = -$100;  { 8 px left and 8 px up, once }
  T73_CHILD_LEFT = $400;    { every child appears 32 px to the left }
  T73_CHILD_DOWN_A = $C0;   { 6 px for the type 75 and the type 35 ... }
  T73_CHILD_DOWN_B = $100;  { ... and 8 px for the type 74 }
  T73_CHILD_ONE = $4B;      { 75 - moves it out of state 3 }
  T73_CHILD_TWO = $4A;      { 74 - moves it out of state 5 }
  T73_CHILD_THREE = $23;    { 35 - the marker type 31 uses too }
  T73_RECOVER = $1E;
  T73_SND_CHARGE = $32;

  T74_V0_FRAMES = 5;  T74_V0_TICKS = 4;
  T74_V0_TABLE_ADDR = $0046C628;
  T74_V0_SPRITES: array[0..T74_V0_FRAMES - 1] of Integer =
    (512, 513, 514, 515, 516);
  T74_V1_FRAMES = 4;  T74_V1_TICKS = 2;
  T74_V1_TABLE_ADDR = $0046C63C;
  T74_V1_SPRITES: array[0..T74_V1_FRAMES - 1] of Integer = (515, 516, 515, 516);
  T74_SKEW_ADDR  = $0046C64C;
  T74_COUNT_ADDR = $0046C658;
  T74_SPEED_ADDR = $0046C664;
  { The same three sets of numbers as T56_SKEW, T56_COUNT and T56_SPEED. }
  T74_SKEW:  array[0..2] of Integer = (0, -4, -8);
  T74_COUNT: array[0..2] of Integer = (0, 2, 4);
  T74_SPEED: array[0..2] of Integer = (2, 2, 3);
  T74_FAN_STEP = 4;
  T74_FAN_WRAP = $3C;
  T74_SELF_TYPE = $4A;      { 74 - the charge-up throws copies of itself }
  T74_SHOT_VARIANT = 1;
  T74_OWNER_STATE = 6;      { what it writes into its parent before it goes }

  { Types 75 and 76. Type 75 dies with its parent - after the dying check it
    reads the OWNER's EF_HP and destroys itself if that is zero. No other
    child does this; types 35, 39 and 74 outlive a dead parent.

    Type 76's lap sound fires when the new heading equals 63, not when it
    wraps to 0. Type 66's satellite plays the same sound on the wrap itself:
    one step apart, in two handlers, with the same sound id. Recorded as
    found. }
  T75_FRAMES = 8;  T75_TICKS = 4;
  T75_TABLE_ADDR = $0046C670;
  T75_SPRITES: array[0..T75_FRAMES - 1] of Integer =
    (504, 505, 506, 507, 508, 509, 510, 511);
  T75_OPENING = 0;          { reads the table forwards ... }
  T75_CLOSING = 1;          { ... and this one backwards }
  T75_OWNER_AFTER_OPEN = 4;
  T75_OWNER_AFTER_CLOSE = 1;
  T75_SND_OPEN = $18;

  T76_FRAMES = 2;  T76_TICKS = 2;
  T76_TABLE_ADDR = $0046C690;
  T76_SPRITES: array[0..T76_FRAMES - 1] of Integer = (422, 423);
  T76_PERIOD_ADDR = $0046C698;
  T76_SPEED_ADDR  = $0046C6A4;
  T76_PERIOD: array[0..2] of Integer = (4, 2, 2);   { frames between steps }
  T76_SPEED:  array[0..2] of Integer = (1, 2, 2);
  T76_NUDGE = $200;         { 16 px right, once }
  T76_LAP_AT = $3F;         { the step BEFORE the wrap, not the wrap }
  T76_SND_LAP = $2E;

  { Type 77, the final boss - the only handler that runs from a SCRIPT rather
    than a hand-written state chain: two 6x6 tables, durations and actions,
    indexed by [phase][step].

    Each phase's sprite table is exactly as wide as the highest frame that
    phase's script can reach, which is how the extents below are pinned - the
    binary's pointer layout and the action table agree on all five. }
  T77_PHASES = 6;
  T77_STEPS = 6;

  { phases 0 and 1 share this one - the `< 2` test in the original }
  T77_P01_TABLE_ADDR = $0046C6B0;
  T77_P01_SPRITES: array[0..1, 0..9] of Integer =
    ((584, 585, 500, 501, 502, 503, 535, 534, 535, 536),
     (586, 587, 504, 505, 506, 507, 538, 537, 538, 539));
  T77_P2_TABLE_ADDR = $0046C700;
  T77_P2_SPRITES: array[0..1, 0..13] of Integer =
    ((588, 589, 508, 509, 510, 511, 541, 540, 541, 542, 566, 567, 568, 592),
     (590, 591, 512, 513, 514, 515, 544, 543, 544, 545, 569, 570, 571, 593));
  T77_P3_TABLE_ADDR = $0046C770;
  T77_P3_SPRITES: array[0..1, 0..12] of Integer =
    ((594, 595, 516, 517, 518, 519, 547, 546, 547, 548, 572, 573, 574),
     (596, 597, 520, 521, 522, 523, 550, 549, 550, 551, 575, 576, 577));
  T77_P4_TABLE_ADDR = $0046C7D8;
  T77_P4_SPRITES: array[0..1, 0..5] of Integer =
    ((552, 553, 524, 525, 526, 527),
     (554, 555, 528, 529, 530, 531));
  T77_P5_TABLE_ADDR = $0046C808;
  T77_P5_SPRITES: array[0..1, 0..7] of Integer =
    ((578, 579, 558, 559, 560, 561, 556, 557),
     (580, 581, 562, 563, 564, 565, 556, 557));
  { phase 6 is the dead pose, and both directions are the same sprite }
  T77_P6_TABLE_ADDR = $0046C848;
  T77_P6_SPRITES: array[0..1] of Integer = (598, 598);

  T77_HP_ADDR = $0046C850;
  T77_HP: array[0..2, 0..T77_PHASES - 1] of Integer =
    ((968, 936, 904, 840, 808, 776),
     (968, 936, 904, 840, 808, 776),    { the same fight as easy }
     (984, 952, 920, 888, 856, 824));

  T77_STEP_ADDR   = $0046C8B4;
  T77_ACTION_ADDR = $0046C944;
  T77_DIVISOR_ADDR = $0046C9D4;
  T77_STEP: array[0..T77_PHASES - 1, 0..T77_STEPS - 1] of Integer =
    ((180, 0, 0, 180, 0, 0),
     (180, 0, 60, 180, 0, 60),
     (120, 0, 30, 120, 0, 60),
     (30, 0, 0, 0, 0, 30),
     (30, 0, 30, 0, 30, 0),
     (30, 0, 30, 30, 0, 30));
  T77_ACTION: array[0..T77_PHASES - 1, 0..T77_STEPS - 1] of Integer =
    ((2, 3, 0, 2, 3, 0),
     (2, 3, 4, 2, 3, 4),
     (2, 6, 5, 2, 3, 4),
     (4, 2, 3, 2, 3, 5),
     (2, 7, 2, 7, 2, 7),
     (2, 3, 8, 2, 3, 8));
  T77_DIVISOR: array[0..2] of Integer = (1, 2, 4);   { harder runs it faster }

  { T77_ACTION's values - what the step does when its duration runs out. The
    frame each one starts on is EF_FLAG1C in the arm below. }
  T77_ACT_WAIT      = 0;   { wait again }
  T77_ACT_FACE      = 2;   { turn to face the player }
  T77_ACT_DASH      = 3;   { dash, leaving a trail }
  T77_ACT_SLAM      = 4;   { the ground slam }
  T77_ACT_SHOT      = 5;   { the projectile }
  T77_ACT_RECOIL    = 6;   { like the dash, faster and backwards }
  T77_ACT_DASH_BACK = 7;   { the dash, entered facing the other way }
  T77_ACT_POSE      = 8;   { a held pose that spawns a variant-5 part }

  T77_SLAM_ADDR     = $0046C898;
  T77_SLAM_DIV_ADDR = $0046C9E0;
  T77_SLAM: array[0..3] of Integer = (4, 90, 2, 60);   { frames 6..9 }
  T77_SLAM_DIV: array[0..2] of Integer = (1, 1, 2);
  T77_SHOT_ADDR     = $0046C8A8;
  T77_SHOT_DIV_ADDR = $0046C9EC;
  T77_SHOT: array[0..2] of Integer = (90, 4, 60);      { frames 10..12 }
  T77_SHOT_DIV: array[0..2] of Integer = (1, 1, 2);

  T77_BURST_ADDR   = $0046C588;
  T77_BURST_VX_ADDR = $0046C558;
  T77_BURST_VY_ADDR = $0046C570;
  T77_BURST: array[0..2] of Integer = (1, 3, 5);       { plus one }
  T77_BURST_VX: array[0..5] of Integer = (2, -2, 5, -5, 10, -10);
  T77_BURST_VY: array[0..5] of Integer = (-24, -24, -20, -20, -14, -14);
  T77_BURST_SHIFT = 3;
  T77_BURST_TYPE = $48;     { 72 variant 0, the faller }

  T77_LOB_SPEED_ADDR = $0046CADC;
  T77_LOB_SPEED: array[0..2] of Integer = (1, 2, 3);

  T77_ENTRY_VX = -$10;
  T77_PART_A = $4E;         { 78 - spawned once, at the start }
  T77_PART_B = $4F;         { 79 - spawned once, and again for every effect }
  T77_TURN_SPEED = $60;
  T77_TURN_HOLD = $3C;
  T77_DASH_FRICTION = 2;
  T77_RECOIL_FRICTION = 4;
  T77_IDLE_TICKS = 8;
  T77_HELD_TICKS = 4;
  T77_HELD_FIRST = 6;
  T77_HELD_LAST = 7;
  T77_PUFF_LIFT = $20;
  T77_SHAKE_FRAMES = $3C;
  T77_SND_ROAR = $33;
  T77_SND_SLAM = $30;
  T77_SND_LOB = $2E;

  { Types 78, 79 and 80, the boss's furniture. Three things kept as written:

      78  clears EF_TOUCH_KIND for the whole of the lob, so the wind-up is the
          one window in which this half of the boss is safe to stand beside.
      79  variant 3 dies when its timer reaches 1, not 0 - one frame early,
          and deliberate: Entity_UpdateAll decrements it after the handler.
      80  both variants share ONE counter. EF_BLOCK_B is incremented at the
          top for both and AGAIN inside variant 1, so variant 1 runs at twice
          the rate off a field that is counted twice. }
  T78_SLAM_X_ADDR = $0046CA28;
  T78_SLAM_Y_ADDR = $0046CA48;
  T78_SLAM_X: array[0..1, 0..3] of Integer =
    ((0, 68, -16, -60), (0, -68, 16, 60));
  T78_SLAM_Y: array[0..3] of Integer = (-54, 0, -54, 0);
  T78_LOB_X_ADDR = $0046CA70;
  T78_LOB_Y_ADDR = $0046CA88;
  T78_LOB_X: array[0..1, 0..2] of Integer = ((60, -4, 8), (-60, 4, -8));
  T78_LOB_Y: array[0..2] of Integer = (-22, 0, -72);
  T78_IDLE_TABLE_ADDR = $0046C9F8;
  T78_IDLE_SPRITES: array[0..1] of Integer = (600, 601);
  T78_SLAM_TABLE_ADDR = $0046CA08;
  T78_SLAM_SPRITES: array[0..1, 0..3] of Integer =
    ((607, 602, 606, 603), (606, 604, 607, 605));
  T78_LOB_TABLE_ADDR = $0046CA58;
  T78_LOB_SPRITES: array[0..1, 0..2] of Integer =
    ((608, 610, 607), (609, 611, 606));
  T78_IDLE_X_ADDR = $0046CA00;
  T78_IDLE_X: array[0..1] of Integer = (-7, 7);
  T78_OFFSET_SCALE = $20;
  T78_IDLE_HIGH = -$680;    { on the boss's frames 0, 3 and 5 ... }
  T78_IDLE_LOW  = -$6A0;    { ... and on every other frame }
  T78_LEAVES_AT_PHASE = 5;

  T79_V0_TABLE_ADDR = $0046CA94;
  T79_V0_SPRITES: array[0..1] of Integer = (532, 533);
  T79_V1_TABLE_ADDR = $0046CAA4;
  T79_V1_SPRITES: array[0..1] of Integer = (612, 613);
  T79_V2_TABLE_ADDR = $0046CAB8;
  T79_V2_SPRITES: array[0..1] of Integer = (613, 612);   { v1's, reversed }
  T79_V3_TABLE_ADDR = $0046CACC;
  T79_V3_SPRITES: array[0..1, 0..1] of Integer = ((614, 615), (616, 617));
  T79_V4_TABLE_ADDR = $0046CAE8;
  T79_V4_SPRITES: array[0..3] of Integer = (291, 292, 293, 294);
  T79_V5_TABLE_ADDR = $0046CAF8;
  T79_V5_SPRITES: array[0..5] of Integer = (471, 470, 469, 468, 467, 466);
  T79_V0_X_ADDR = $0046CA9C;
  T79_V1_X_ADDR = $0046CAAC;
  T79_V1_Y_ADDR = $0046CAB4;
  T79_V2_X_ADDR = $0046CAC0;
  T79_V2_Y_ADDR = $0046CAC8;
  T79_V0_X: array[0..1] of Integer = (1, -1);
  T79_V1_X: array[0..1] of Integer = (-80, 80);
  T79_V1_Y: array[0..0] of Integer = (-48);
  T79_V2_X: array[0..1] of Integer = (80, -80);
  T79_V2_Y: array[0..0] of Integer = (-48);
  T79_V0_HIGH = -$160;      { on the boss's frames 1, 2 and 4 }
  T79_V0_LOW  = -$180;
  T79_V0_LEAVES_AT_PHASE = 1;
  T79_V1_LIFE = 10;
  T79_V2_LIFE = 2;
  T79_LOB_SND_EVERY = $1E;
  T79_LOB_FUSE = $F;        { armed on a wall, or on running out of time }
  T79_LOB_LIFE = $78;
  T79_V4_FRAMES = 4;
  T79_SUMMON_WAIT = $1E;
  T79_SUMMON_LAST = 5;
  T79_SUMMONS = 4;          { three flyers, and the fourth pass hands back }
  T79_FLYER_TYPE = $48;     { 72 ... }
  T79_FLYER_VARIANT = 1;    { ... variant 1, the one that picks its sprite
                              by heading }
  T79_SND_LOB = $2E;
  T79_SND_SUMMON = $34;

  T80_V0_FRAMES = 3;  T80_V0_TICKS = 8;
  T80_V0_TABLE_ADDR = $0046CB10;
  T80_V0_SPRITES: array[0..T80_V0_FRAMES - 1] of Integer = (582, 583, 599);
  T80_V1_FRAMES = 4;  T80_V1_TICKS = 2;
  T80_V1_TABLE_ADDR = $0046CB1C;
  T80_V1_SPRITES: array[0..T80_V1_FRAMES - 1] of Integer = (64, 65, 66, 65);
  T80_V1_BLINK = 2;

  { Types 8 and 26, the two self-destructing effects. Both are spawned by
    something else, play a short animation, and destroy themselves - which is
    why a MISSING handler here filled the screen with copies of Akuji rather
    than leaking: an effect that never reaches its Entity_Destroy stays alive
    for ever wearing the anim id Entity_Spawn gave it, and that is sprite 0.

    Type 26's VARIANT is the whole difference between its two sprites: 0 for
    an ordinary stone, 1 when the stone completed a target and paid a life.

    The frame index is unchecked in the original and cannot overflow: the
    frame that would run off the end is the frame that destroys the entity,
    and the sprite is written first. The clamps below are unreachable rather
    than corrective - the same situation type 33 is in. }
  TYPE8_FRAMES      = 4;
  TYPE8_TICKS       = 4;    { advance when the count EXCEEDS it, so every 5 }
  TYPE8_TABLE_ADDR  = $0046BCCC;
  TYPE8_SPRITES: array[0..TYPE8_FRAMES - 1] of Integer = (50, 51, 52, 53);

  TYPE26_LIFT       = $10;  { 16 sub-pixels a frame, straight up }
  TYPE26_LIFETIME   = $1E;  { destroyed when the count EXCEEDS 30 }
  TYPE26_TABLE_ADDR = $0046BE14;
  { The handler indexes this by EF_VARIANT with NO bound check, so all four
    entries are reachable even though the shipped data only ever spawns 0 and
    1. It was recorded here as two - the observed use - until the table sweep
    in --selftest-entities pinned the extent at four from the next table's
    start. Recorded at its extent now, which is what the binary holds. }
  TYPE26_VARIANTS   = 4;
  TYPE26_SPRITES: array[0..TYPE26_VARIANTS - 1] of Integer =
    (83, 99, 102, 103);

  { Types 16 and 22, the one-sprite entities. Each writes ONE anim id and
    stops. That id is not a literal - it is element 0 of a table reached
    through a pointer, in the same run at 0x0046BE3C as the animated types':

        0x0046BE74  54   type 16, the sign
        0x0046BE84  60   type 22

    Only element 0 is ever read, so the extent of these two is unknowable from
    their readers and unimportant - a single unconditional read cannot run off
    the end. Recorded rather than guessed: a length that nothing pins is not a
    length. }
  SIGN_SPRITE       = 54;
  SIGN_SPRITE_ADDR  = $0046BE74;
  TYPE22_SPRITE     = 60;
  TYPE22_SPRITE_ADDR = $0046BE84;

  { Type 33, the explosion @ 0x0045A698. On its FIRST update it throws six
    type-6 sparks, each taking one random heading of 64 and a velocity from
    BOTH direction tables at that index, which is what makes the burst radial
    rather than axis-aligned. The two speed multipliers are drawn SEPARATELY,
    so a spark's X and Y speeds are independent and the scatter is an ellipse
    of random eccentricity. }
  BOOM_FRAMES     = 6;
  BOOM_TICKS      = 6;    { advance when the count EXCEEDS it, so every 7 }
  BOOM_TABLE_ADDR = $0046BE3C;
  BOOM_TABLE_PTR  = $0046CE30;
  BOOM_SPRITES: array[0..BOOM_FRAMES - 1] of Integer = (93, 94, 95, 96, 97, 98);
  BOOM_SPARK_TYPE = 6;
  BOOM_SPARKS     = 6;
  BOOM_SPEED_MAX  = 3;    { RandomBelow(3) + 1, so 1..3, per axis }

  { Type 32, the emitter @ 0x0045A5D4 - an invisible spawner that reads its
    configuration out of block A and keeps its state in block B:

      A[1] $09  frames between spawns    B[0] $12  countdown to the next
      A[2] $0A  how many in all          B[1] $13  how many so far
      A[3] $0B  scatter radius           B[2] $14  countdown to the next sound
      A[4] $0C  frames between sounds

    The scatter is Random(r * 16) - r * 8 PIXELS on each axis - quarter tiles,
    not tiles. Entity_UpdateDying seeds it two ways, which is how one emitter
    type gives two different deaths.

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

  { Entity_TakeProjectileHits @ 0x00457AB4. A switch on the TARGET's
    EF_VULN_KIND, with the projectile's own EF_STATE as its POWER. Most arms
    are immunity, and several are conditional on that power, which is what
    makes them armour rather than invulnerability:

        2, $5C   immune outright
        $5A      immune to power below 1
        $5B      immune to power below 2
        $5D      immune UNLESS the power is exactly 3
        4        immune unless the power is exactly 4

    A power-3 shot is skipped entirely unless the kind is $5D, so that power
    exists to open exactly one kind of door.

    Kind 7 REFLECTS, and is the only place in the game seen writing all four
    hitbox percentage columns at runtime. Powers 2 and 3 PIERCE - not
    destroyed, and able to hit again - and power 4 is destroyed WITH loot.
    Only the special arms return early, so an ordinary hit carries on scanning
    and several shots can land in one pass. }
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

{ 0x0045A3E0. THE MANA STONE - the collectible the HUD counter counts.

  Identified two ways that agree. In the game it is the pickup the player
  gathers, confirmed on screen; and in the data its type-table column 3 is 2,
  which is TOUCH_KIND_MANA, so Entity_PlayerTouch routes it to
  Entity_TouchPickup @ 0x00458274 - the routine this file has always called
  "the Mana Stone". Types 24 and 25 use touch kind 3 and are something else.

  It is also by far the most placed collectible: 122 records over 32 stages,
  every one opcode 9, and its GET popup is type 26.

  An animated pickup: four frames on a five-frame cycle, and a one-shot settle
  downward the first time it updates.

  It animates ONLY while GameState is GS_PLAY, so items freeze during an event
  script or a pause rather than continuing behind the dialogue box. It does not
  call Entity_UpdateDying and has no touch handling of its own - what happens
  when the player walks into it is decided by EF_TOUCH_KIND from the type table,
  in Entity_PlayerTouch. }
procedure EntityUpdate_Type14_ManaStone(var E: TEntity; AGameState: Integer);

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

{ 0x0045A43C. The power orb. It carries one of Akuji's nine abilities - Dash,
  Fire, Bat and the rest - and which one is its placement variant. World is
  needed only for the heartbeat, which only variant 8 has. }
procedure EntityUpdate_Type24_PowerOrb(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045A7BC. The falling item. See DROP_SPRITES above. }
procedure EntityUpdate_Type36_FallingItem(var E: TEntity; AGameState: Integer;
                                          World: TEntityWorld);

{ 0x0045B3EC. PoyoPoyo, a bouncing blob - land on it and it throws the player
  very high. A springboard and a shooter by variant; see the T40_ block,
  whose launch rewrites six fields of the player's entity. }
procedure EntityUpdate_Type40_PoyoPoyo(var E: TEntity; AGameState: Integer;
                              var Inp: TInputState; World: TEntityWorld);

{ 0x0045C678. A BOSS - a fire lion that jumps about and breathes fire.
  Circle, dive, dive, summon; see the T52_ block. }
procedure EntityUpdate_Type52_Boss_FireLion(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045CAD8. A BOSS - a floating magician that teleports around the arena,
  throwing an orb as it goes. Hover, blink out, fire, hop, blink in; see the
  T54_ block. }
procedure EntityUpdate_Type54_Boss_FloatingMagician(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045CC98. The boss's fireball in state 0 and its trail in state 1. }
procedure EntityUpdate_Type55(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045D00C. Four unrelated entities in one handler, chosen by
  EF_VARIANT. See the T57_ block. }
procedure EntityUpdate_Type57(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045DA28. HenaHena, a monster that is AFRAID of the player and runs away.
  Catching it is the only way to kill it, which needs the Cloud dash: it
  zeroes its own EF_HP on a 1x1 overlap with the player, in both states. See
  the T61_ block, and note the acceleration really is away from the player. }
procedure EntityUpdate_Type61_Mon_HenaHena(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045DC84. A royal penguin carrying a shield, so its weak side is
  whichever way the shield is not: it recomputes its own vulnerability every
  frame from which way it is heading relative to the player. }
procedure EntityUpdate_Type62_Mon_PenguinHeishi(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045DDF4. An armoured penguin that stops to throw a knife. Walks, fires
  one type-57 skimmer, then turns round; see the T63_ block. }
procedure EntityUpdate_Type63_Mon_PenguinKnife(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045E030. A large spike press that stamps down on a fixed interval: drops
  from the ceiling, sends a wave each way along the floor, rests, and climbs
  back. }
procedure EntityUpdate_Type64_SpikePress(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045E25C. DorDor: it vanishes when attacked and can only be hurt in the
  moment after it reappears. It reads the input directly - nothing happens
  until the player presses ATTACK while standing in its box. See T65_. }
procedure EntityUpdate_Type65_Mon_DorDor(var E: TEntity; AGameState: Integer;
                              var Inp: TInputState; World: TEntityWorld);

{ 0x0045E4EC. A giant ball. Environmental rather than an enemy: it damages on
  contact and does nothing else. An anchor and the satellite that orbits it,
  one handler and two variants; see the T66_ block for what EF_FACING means
  here. }
procedure EntityUpdate_Type66_GiantBall(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045E714. A turtle that lays bombs and runs from them. Walks, lays a
  type-57 egg, then bolts away from it and coasts to a halt; see the T67_
  block. }
procedure EntityUpdate_Type67_Mon_TurtleBomb(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045EA40. What hatches: a riser that resizes its own hitbox frame by
  frame, and falls and drops loot once something has caught it. }
procedure EntityUpdate_Type68(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045EB1C. GoroGoro: a ball the player rolls by SHOOTING it, to be dropped
  onto a switch. It slides, and when it finds a hole under it pays out a type
  68 and sets its event's progress flag. }
procedure EntityUpdate_Type69_GoroGoro(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045EC4C. The angry switch - a switch, not an enemy. The only way to
  throw it is to drop a GoroGoro on top, which kills it: it has exactly 100
  hp and any wound at all is fatal, which is what makes the ball the one
  thing that works. Variant 1 walks, variant 0 stands; see the T70_ block. }
procedure EntityUpdate_Type70_AngrySwitch(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045ED88. A cat that DEFLECTS anything thrown at it, except during the
  brief pause when it stops. Walks invulnerable, curls up vulnerable,
  repeats; see the T71_ block, and note the walk timer only runs while it is
  on screen. }
procedure EntityUpdate_Type71_BouncyCat(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045EFC8. A faller, a flyer that picks its sprite by heading, and the
  trail the flyer drops. See the T72_ block. }
procedure EntityUpdate_Type72(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045F218. A MINIBOSS - the same lizard as type 31 in another colour, with
  its own attack. Three of its states are left by a spawned child rather than
  by anything here; see the T73_ block. }
procedure EntityUpdate_Type73_Boss_MidoriLizard(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045F498. Type 73's charge-up, and the fan of shots it throws. The
  charge-up is what writes state 6 back into its parent. }
procedure EntityUpdate_Type74(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045F668. Eight frames, then it writes a state into its owner and goes.
  The only child that dies when its parent's health reaches zero. }
procedure EntityUpdate_Type75(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045F744. A levitating spike press that tracks left and right: one
  heading step per reload, velocity from that heading, so it crosses and
  comes back over a full turn. }
procedure EntityUpdate_Type76_SpikePress_Lev(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045F85C. THE FINAL BOSS - the Hero, at the end of the game. Six phases,
  each running a six-step script out of two tables; see the T77_ block. }
procedure EntityUpdate_Type77_Boss_Hero(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0046023C. The boss's second body. It has no behaviour: it reads the
  boss's state every frame and writes its own position and sprite. }
procedure EntityUpdate_Type78(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x004603B4. Everything type 77 emits. Variant 5 is what frees the boss
  from state 8, after throwing three flyers. See the T79_ block. }
procedure EntityUpdate_Type79(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x004607E8. Decoration and nothing else: touch kind 0, so it cannot be
  touched or hurt, and the handler only animates. Two placements in the whole
  game, both unconditional in the final arena. Variant 1 is unreachable - no
  record selects it and nothing spawns type 80. }
procedure EntityUpdate_Type80_Fx_ArenaEmber(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045D598. A FAKE MANA STONE - it sits there looking like the collectible,
  and is a crab. Sleeps until touched, then wobbles on the spot. }
procedure EntityUpdate_Type58_Mon_NiseMana(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045D7D8. A golem. Attack it and it loses its head and gets faster. A
  walker that turns at walls AND at ledges, and enrages when its health drops
  below 11; see the T60_ block. }
procedure EntityUpdate_Type60_Mon_Golem(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045D670. The red eye: it rises out of the lava when the player comes
  near and travels toward where they are. Wakes, rises, aims once at the
  apex, then flies. }
procedure EntityUpdate_Type59_Mon_RedEye(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045CE78. A red mushroom that swells as the player nears and bursts,
  throwing a projectile. See the T56_ block. }
procedure EntityUpdate_Type56_Mon_AkaiKinoko(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045C608. A blue spherical ghost: it passes through terrain, follows the
  player and hurts on contact. The simplest chaser - steer, move, repeat, for
  ever. }
procedure EntityUpdate_Type51_Mon_Ghost(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045CA28. Winds up, then charges in whatever direction it faces. }
procedure EntityUpdate_Type53(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045C430. An armoured turtle, vulnerable only while it is open and
  firing. Patrols, opens to fire, closes, and changes its own vulnerability
  while open; see the T50_ block. }
procedure EntityUpdate_Type50_Mon_Turtle(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045C250. A red creature that lives in the water and leaps when the
  player nears. A diver - hover, drop, climb, rest; see the T49_ block. }
procedure EntityUpdate_Type49_Mon_Water(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045C0F4. Type 47's shot: four bounces, each shorter than the last. }
procedure EntityUpdate_Type48(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045BF58. A pink squid that lobs spiky bouncing balls on a fixed
  interval: wait, wind up, throw two shots, rest, repeat. }
procedure EntityUpdate_Type47_Mon_PinkSquid(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045BCC4. NukeNuke: a block that stops being solid once the player has
  stood on it too long. The only reader of EF_RIDDEN. }
procedure EntityUpdate_Type45_Block_NukeNuke(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045BD9C. A purple bat. It sleeps until the player comes close, then
  homes on them. }
procedure EntityUpdate_Type46_Mon_Bat(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045BBD8. GashiGashi: a BLOCK, broken by shooting it with Fire+ - not
  armour worn by anything. Its VARIANT selects which of the four
  vulnerability kinds it has, which is what makes Fire+ the one shot that
  works; see the T43_ block. }
procedure EntityUpdate_Type43_GashiGashi(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045BC00. Type 42's shot: thrown up, pulled down, culled off screen. }
procedure EntityUpdate_Type44(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045B7C4. THE SECOND BOSS, placed exactly once in the whole game. Six
  states, and its timings scale with its own HP as well as with the
  difficulty; see the T42_ block. }
procedure EntityUpdate_Type42_Boss_TealBlobSlammer(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045B62C. A green jumping cricket. A hopper; see the T41_ block. }
procedure EntityUpdate_Type41_Mon_TondaCricket(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045B0CC. A stationary cat that fires on a fixed interval. Waits only
  while on screen, then fires a type 39. }
procedure EntityUpdate_Type38_Mon_AkuNeko(var E: TEntity; AGameState: Integer;
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

{ 0x0045ABD8. Looks like Akuji. Whether it is MEANT to be him is unsettled -
  the sprite says so and nothing in the code does. A patroller that gets
  meaner on hard; see the T30_ block. }
procedure EntityUpdate_Type30_Akuji(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045AC94. THE FIRST BOSS, a purple lizard that spits short-range red
  projectiles. Six states, three difficulty tables, and a child entity that
  drives the transition this handler cannot make itself. }
procedure EntityUpdate_Type31_Boss_MurasakiLizard(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045A848. The boss key: it drops when a boss dies, opens the door and
  restores health. Drops, lands, and lies there animating. }
procedure EntityUpdate_Type37_BossKey(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045A95C. A switch, thrown by pressing UP against it - most often what
  unlocks a door. The only handler that writes to the event table. }
procedure EntityUpdate_Type15_Switch(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045A9D4 and 0x0045A9D0. Both are a single RET. The switch HAS an arm for
  these two types and the arm does nothing, which is not the same as types 0,
  18 and 20, which have no arm at all. Written out so the difference survives
  in code rather than only in HANDLER_ADDR. }
procedure EntityUpdate_Type17(var E: TEntity);
procedure EntityUpdate_Type19(var E: TEntity);

{ 0x0045AA10. The winged-horse block - a platform that carries the player
  along its axis. See the T21_ block above for why EF_FACING is a speed here
  and not a heading. }
procedure EntityUpdate_Type21_WingedHorseBlock(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045AA78. A candle, and a switch in disguise: it is set by SHOOTING FIRE
  at it. It owns the two flame entities above it. }
procedure EntityUpdate_Type23_Candle(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045A580. Four frames, and inert unless its variant is 0. }
procedure EntityUpdate_Type28(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045AB64. A green one-eyed monster. Its idle animates faster when the
  player is close. }
procedure EntityUpdate_Type29_Mon_MidoriMonster(var E: TEntity; AGameState: Integer;
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

{ 0x0045A944. The sign: the player reads its text by interacting with it. Two
  instructions of substance, and no game-state guard at all. }
procedure EntityUpdate_Type16_InfoSign(var E: TEntity);

{ 0x0045AA60. A stationary spike ball; it only has to exist and hurt. One
  sprite, plus the Entity_UpdateDying call whose result it discards. }
procedure EntityUpdate_Type22_SpikeBall(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);

{ 0x0045A698. The explosion. See BOOM_SPRITES above. }
procedure EntityUpdate_Type33_Explosion(var E: TEntity; AGameState: Integer;
                                        World: TEntityWorld);

{ 0x0045A5D4. The invisible emitter. See EMIT_EVERY above for the block-A
  configuration it runs off. }
procedure EntityUpdate_Type32_Emitter(var E: TEntity; AGameState: Integer;
                                      World: TEntityWorld);

{ 0x0045A4F0. The door, and the main way between rooms: interacting steps to
  the next or previous one. One table lookup indexed by the variant. It takes
  no game state because it does not read any. }
procedure EntityUpdate_Type25_Door(var E: TEntity);

{ 0x0045A540. The Akuji statue: the save point, which asks before it saves.
  See SAVE_POINT_SPRITES for why it is the save point, which is not visible
  from this function at all. }
procedure EntityUpdate_Type27_AkujiStatue(var E: TEntity; AGameState: Integer);

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

    Every mapped arm is now translated. HANDLER_ADDR remains the address index
    used to re-decompile and audit each implementation. }
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
    normally gets one, whenever its EF_STATE is 3 - so one sitting in a minor
    slot is touch-tested TWICE in a frame. That is the original.

    It is a HAZARD, not a generosity. Type 68's own table column 3 is 0, so a
    table-spawned one has EF_TOUCH_KIND 0 and the test does nothing; the only
    type 68 that touches the player is the one type 57's egg hatches, and the
    EGG sets its kind to 1 - Player_TakeDamage. The extra test doubles the
    chance of it hitting you.

    State 4 is unrelated: type 69 spawns a type 68 straight into it, leaving
    the kind at 0, so that one is harmless. Two uses of one type. }
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
{ The type switch on its own - see the note on the implementation. Exposed so
  --emudiff can run one handler against an entity of its choosing. }
procedure EntityRunHandler(var E: TEntity; var P: TPlayerState;
                           var L: TLayerInfo; var Inp: TInputState;
                           World: TEntityWorld; AGameState: Integer);

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

{ One int of the sprite DATA region - the four unchecked handlers read through
  this so that an overrun lands on the same bytes the original's does. }
function SpriteDatum(Index: Integer): Integer;


implementation


function EntityUpdateDying(var E: TEntity; AGameState: Integer;
                           World: TEntityWorld): Boolean;
var
  SpawnedSlot: Integer;
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
          SpawnedSlot := World.Spawn(2, EMITTER_TYPE,
                              E.Raw[EF_POS_X] - POSITION_BIAS,
                              E.Raw[EF_POS_Y] - POSITION_BIAS - $20);
          World.SetSpawnField(SpawnedSlot, EF_BLOCK_A + 1, 8);
          World.SetSpawnField(SpawnedSlot, EF_BLOCK_A + 2, 2);
          World.SetSpawnField(SpawnedSlot, EF_BLOCK_A + 3, 1);
          World.SetSpawnField(SpawnedSlot, EF_BLOCK_A + 4, 2);
        end;
      DEATH_CLASS_BIG:
        begin
          E.Raw[EF_DEATH_TIMER] := 180;
          E.Raw[EF_TIMER] := 240;
          SpawnedSlot := World.Spawn(2, EMITTER_TYPE,
                              E.Raw[EF_POS_X] - POSITION_BIAS,
                              E.Raw[EF_POS_Y] - POSITION_BIAS - $20);
          World.SetSpawnField(SpawnedSlot, EF_BLOCK_A + 1, 4);
          World.SetSpawnField(SpawnedSlot, EF_BLOCK_A + 2, $20);
          World.SetSpawnField(SpawnedSlot, EF_BLOCK_A + 3, 4);
          World.SetSpawnField(SpawnedSlot, EF_BLOCK_A + 4, 1);
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
  SpawnedSlot: Integer;
begin
  case E.Raw[EF_VARIANT] of
    0: Inc(P.Counter, MANA_SMALL);
    1: Inc(P.Counter, MANA_LARGE);
  end;

  SpawnedSlot := PickupCommon(E, World);

  { The comparison happens AFTER the counter has already gone up, so a stone
    that takes you exactly to the target counts as reaching it. }
  if P.Counter < ManaTarget(P.TargetIndex) then
  begin
    if E.Raw[EF_VARIANT] = 0 then
      World.PlaySound(SND_GET01)
    else if E.Raw[EF_VARIANT] = 1 then
      World.PlaySound(SND_GET02);
    World.SetSpawnField(SpawnedSlot, EF_VARIANT, PICKUP_FX_NORMAL);
  end
  else
  begin
    Inc(P.TargetIndex);
    Inc(P.MaxLives);
    P.Lives := P.MaxLives;
    World.PlaySound(SND_POWER02);
    World.SetSpawnField(SpawnedSlot, EF_VARIANT, PICKUP_FX_LEVELUP);
  end;

  World.DestroyEntity(E, False);
end;

procedure EntityTouchHeal(var E: TEntity; var P: TPlayerState;
                          World: TEntityWorld);
var
  SpawnedSlot: Integer;
begin
  World.PlaySound(SND_KACHI02);
  P.Lives := P.MaxLives;
  SpawnedSlot := PickupCommon(E, World);
  World.SetSpawnField(SpawnedSlot, EF_VARIANT, PICKUP_FX_HEAL);
  World.DestroyEntity(E, False);
end;

procedure EntityTouchLife(var E: TEntity; var P: TPlayerState;
                          World: TEntityWorld);
var
  SpawnedSlot, Variant: Integer;
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
  SpawnedSlot := PickupCommon(E, World);
  World.SetSpawnField(SpawnedSlot, EF_VARIANT, Variant + 2);
  World.DestroyEntity(E, False);
end;

procedure PlayerTakeDamage(var Player: TEntity; var P: TPlayerState;
                           Damage: Integer; World: TEntityWorld);
var
  DamageLeft, SoulIndex, SpawnedSlot: Integer;
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
  DamageLeft := Damage;
  repeat
    for SoulIndex := 0 to SOULS_PER_LIFE - 1 do
    begin
      { At the HUD icon, in screen space - the life being knocked off. }
      SpawnedSlot := World.Spawn(EKIND_MINOR, EF_DEBRIS_TYPE,
                          (P.Lives * HUD_LIFE_STEP + HUD_LIFE_X0) * 32,
                          HUD_LIFE_Y * 32);
      World.SetSpawnField(SpawnedSlot, EF_FACING,
                          World.RandomBelow(4) + SoulIndex * 8 + 8);
      World.SetSpawnField(SpawnedSlot, EF_VEL_Y,
                          World.RandomBelow($10)
                            + Abs(1 - SoulIndex) * $10 - $20);
    end;
    Dec(P.Lives);
    Dec(DamageLeft);
  until (P.Lives = 0) or (DamageLeft = 0);
end;

procedure PlayerTouch(var E, Player: TEntity; var P: TPlayerState;
                      var Inp: TInputState; World: TEntityWorld);
var
  TouchKind, EventId, Opcode: Integer;
begin
  TouchKind := E.Raw[EF_TOUCH_KIND];
  if (Player.Raw[EF_ALIVE] and $FF) = 0 then
    Exit;
  { Invulnerability blocks everything except kind 3. }
  if (Player.Raw[EF_TIMER] <> 0)
     and (TouchKind <> TOUCH_KIND_THRU_INVULN) then
    Exit;
  if TouchKind = 0 then
    Exit;
  if E.Raw[EF_TIMER] <> 0 then
    Exit;

  if not EntitiesOverlap(Player, E, 1, 1) then
    Exit;

  EventId := E.Raw[EF_EVENT_ID];
  if EventId <> -1 then
  begin
    Opcode := World.EventOpcode(EventId);
    if (Opcode = 0)
    or ((Opcode = 1) and (Player.Raw[EF_VEL_Y] = 0)
        and (Inp.AxisY < 0) and (not Inp.AxisYNegative)) then
      World.BeginEvent(EventId, EVENT_BEGIN_FROM_DESTROY);
  end;

  case TouchKind of
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
  SoundIndex: Integer;
begin
  SoundIndex := E.Raw[EF_HIT_SOUND];
  if (SoundIndex < 0) or (SoundIndex >= HIT_SOUND_COUNT) then
    SoundIndex := 0;            { the original indexes this unchecked }
  Result := HIT_SOUNDS[SoundIndex];
end;

procedure TakeProjectileHits(var E: TEntity; World: TEntityWorld);
var
  ProjectileSlot, Vulnerability, ProjectilePower, Direction: Integer;
  ReflectedSlot, EventId, BoxPercent: Integer;
  TargetBox, ProjectileBox: TBox;
  Projectile: PEntity;
begin
  Vulnerability := E.Raw[EF_VULN_KIND];
  if (Vulnerability = 0) or (E.Raw[EF_TIMER] <> 0)
     or (World.Pool = nil) then
    Exit;

  TargetBox := EntityBox(E, 1, 1);

  for ProjectileSlot := SLOT_ACTOR_FIRST to SLOT_ACTOR_LAST do
  begin
    Projectile := World.Pool.Entity(ProjectileSlot);
    ProjectilePower := Projectile^.Raw[EF_STATE];

    { A power-3 shot is invisible to everything except kind $5D. }
    if not ((Vulnerability = VULN_ONLY_POWER3)
            or (ProjectilePower <> 3)) then
      Continue;
    if (Projectile^.Raw[EF_ALIVE] and $FF) = 0 then
      Continue;
    if Projectile^.Raw[EF_HP] = 0 then { no damage means not a projectile }
      Continue;
    if (E.Raw[EF_ALIVE] and $FF) = 0 then
      Continue;
    if E.Raw[EF_HP] = 0 then
      Continue;

    ProjectileBox := EntityBox(Projectile^, 1, 1);
    if not RectOverlap(ProjectileBox, TargetBox, 0, 0) then
      Continue;

    World.Spawn(EKIND_MINOR, HIT_SPARK_TYPE,
                Projectile^.Raw[EF_POS_X] - POSITION_BIAS,
                Projectile^.Raw[EF_POS_Y] - POSITION_BIAS);

    EventId := E.Raw[EF_EVENT_ID];
    if (EventId <> -1) and (World.EventOpcode(EventId) = 6) then
      World.BeginEvent(EventId, EVENT_BEGIN_FROM_DESTROY);

    if Vulnerability = VULN_REFLECT then
    begin
      ReflectedSlot := World.Spawn(EKIND_MINOR, REFLECT_TYPE,
        Projectile^.Raw[EF_POS_X] - POSITION_BIAS,
        Projectile^.Raw[EF_POS_Y] - POSITION_BIAS);
      World.SetSpawnField(ReflectedSlot, EF_VEL_X,
        -Projectile^.Raw[EF_VEL_X]);
      World.SetSpawnField(ReflectedSlot, EF_STATE, ProjectilePower);
      World.SetSpawnField(ReflectedSlot, EF_CHILD_B, REFLECT_LIFE);
      World.SetSpawnField(ReflectedSlot, EF_CLASS, 0);
      if ProjectilePower = PIERCING_POWER_A then
      begin
        World.SetSpawnField(ReflectedSlot, EF_TOUCH_KIND,
          TOUCH_KIND_HURT_HARD);
        BoxPercent := REFLECT_BOX_STRONG;
      end
      else
      begin
        World.SetSpawnField(ReflectedSlot, EF_TOUCH_KIND, TOUCH_KIND_HURT);
        BoxPercent := REFLECT_BOX_WEAK;
      end;
      World.SetSpawnField(ReflectedSlot, EF_BOX_PCT_X, BoxPercent);
      World.SetSpawnField(ReflectedSlot, EF_BOX_PCT_Y, BoxPercent);
      World.SetSpawnField(ReflectedSlot, EF_INSET_PCT_X, BoxPercent);
      World.SetSpawnField(ReflectedSlot, EF_INSET_PCT_Y, BoxPercent);
      World.PlaySound(HitSound(E));
      World.DestroyEntity(Projectile^, False);
      Exit;
    end;

    if Vulnerability = VULN_SPIN then
    begin
      E.Raw[EF_SHOTS] := SPIN_MARK;
      Inc(E.Raw[EF_FACING], SPIN_TURN);
      if E.Raw[EF_FACING] > DIR_COUNT - 1 then
        Dec(E.Raw[EF_FACING], DIR_COUNT);
      World.PlaySound(HitSound(E));
      World.DestroyEntity(Projectile^, False);
      Exit;
    end;

    if Vulnerability = VULN_SHOVE then
    begin
      { Compare(0, X) is how the original spells Sign(X). }
      Direction := Compare(0, Projectile^.Raw[EF_VEL_X]);
      E.Raw[EF_VEL_X] := Direction shl SHOVE_SPEED_SHIFT;
      Inc(E.Raw[EF_FLAG1C], Compare(0, E.Raw[EF_VEL_X]));
      if E.Raw[EF_FLAG1C] > SHOVE_FRAMES - 1 then
        E.Raw[EF_FLAG1C] := 0;
      if E.Raw[EF_FLAG1C] < 0 then
        E.Raw[EF_FLAG1C] := SHOVE_FRAMES - 1;
      World.PlaySound(HitSound(E));
      World.DestroyEntity(Projectile^, False);
      Exit;
    end;

    { Immunity, some of it conditional on the shot's power. }
    if (Vulnerability = VULN_IMMUNE)
    or (Vulnerability = VULN_IMMUNE_ALT)
    or ((Vulnerability = VULN_ARMOUR_1) and (ProjectilePower < 1))
    or ((Vulnerability = VULN_ARMOUR_2) and (ProjectilePower < 2))
    or ((Vulnerability = VULN_ONLY_POWER3) and (ProjectilePower <> 3))
    or ((Vulnerability = VULN_ONLY_POWER4)
        and (ProjectilePower <> LOOT_POWER)) then
    begin
      World.PlaySound(HitSound(E));
      World.DestroyEntity(Projectile^, ProjectilePower = LOOT_POWER);
      Exit;
    end;

    { A real hit. The projectile's EF_HP is its DAMAGE - the same slot that
      holds hit points on a target. }
    Dec(E.Raw[EF_HP], Projectile^.Raw[EF_HP]);

    { Powers 2 and 3 pierce and are not consumed. }
    if (ProjectilePower <> PIERCING_POWER_A)
       and (ProjectilePower <> PIERCING_POWER_B) then
      World.DestroyEntity(Projectile^, ProjectilePower = LOOT_POWER);

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

procedure EntityUpdate_Type24_PowerOrb(var E: TEntity; AGameState: Integer;
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

procedure EntityUpdate_Type25_Door(var E: TEntity);
var
  Variant: Integer;
begin
  Variant := E.Raw[EF_VARIANT];
  { DIVERGENCE DIV-010. The original does not check, and out of range reads on
    into the next type's sprite table - the emulator says variant 3 gives 83
    and variant 7 gives 84, which are the DATA words at 0x0046BE14 and
    0x0046BE24. Every one of the 160 shipped placements carries 0, 1 or 2, and
    nothing writes EF_VARIANT on a live type 25, so the clamp is unreachable
    rather than corrective. }
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

procedure EntityUpdate_Type52_Boss_FireLion(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, D, Sign, Slot, PlayerX: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame > High(T52_SPRITES[0])) then
    Frame := 0;
  { By the SIGN, two ifs and no else, so a stalled one keeps its sprite. }
  if E.Raw[EF_VEL_X] < 0 then
    E.Raw[EF_ANIM_ID] := T52_SPRITES[0][Frame];
  if E.Raw[EF_VEL_X] > 0 then
    E.Raw[EF_ANIM_ID] := T52_SPRITES[1][Frame];

  if EntityUpdateDying(E, AGameState, World) then
    Exit;
  if World.Pool = nil then
    Exit;

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;
  PlayerX := World.Pool.Field(SLOT_SINGLE_FIRST, EF_POS_X);

  if E.Raw[EF_STATE] = 0 then
  begin
    { Negative on every difficulty - the type table holds the hard figure. }
    Inc(E.Raw[EF_HP], T52_HP[D]);
    E.Raw[EF_STATE] := 1;
    Inc(E.Raw[EF_POS_Y], T52_ENTRY_DROP);
    E.Raw[EF_VEL_X] := T52_ENTRY_VX;
  end;

  if E.Raw[EF_STATE] = 1 then
  begin
    Dec(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] < 1 then
    begin
      E.Raw[EF_BLOCK_B] := T52_TICKS;
      E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T52_FRAMES;
    end;

    Inc(E.Raw[EF_CHILD_A]);
    { Paced off its OWN health: the more you have hurt it, the sooner. }
    if (E.Raw[EF_HP] div T52_HP_PACE_DIV) * T52_HP_PACE_MUL + T52_TIMING[D]
       < E.Raw[EF_CHILD_A] then
    begin
      E.Raw[EF_INSET_PCT_Y] := T52_INSET_CIRCLE;
      E.Raw[EF_STATE] := 2;
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_CHILD_A] := 0;
      Inc(E.Raw[EF_CHILD_B]);
      if E.Raw[EF_CHILD_B] = T52_SUMMON_BEAT then
        World.PlaySound(T52_SND_SUMMON);
      { Only HARD re-aims. }
      if D = 2 then
        E.Raw[EF_VEL_X] := Compare(E.Raw[EF_POS_X], PlayerX) shl 7;
      if E.Raw[EF_VEL_X] = 0 then
        E.Raw[EF_VEL_X] := T52_CHARGE_VX;
    end;
  end;

  if E.Raw[EF_STATE] = 2 then
  begin
    Inc(E.Raw[EF_POS_X], DirVelX(E.Raw[EF_FACING]));
    E.Raw[EF_FACING] := (E.Raw[EF_FACING] + T52_TURN_STEP) mod DIR_COUNT;
    E.Raw[EF_FLAG1C] := T52_CIRCLE_FRAME;

    if E.Raw[EF_CHILD_B] < T52_SUMMON_BEAT then
    begin
      Inc(E.Raw[EF_CHILD_A]);
      if E.Raw[EF_CHILD_A] > T52_CIRCLE_TICKS then
      begin
        E.Raw[EF_INSET_PCT_Y] := T52_INSET_DIVE;
        E.Raw[EF_STATE] := 3;
        E.Raw[EF_BLOCK_B] := 0;
        E.Raw[EF_CHILD_A] := 0;
        E.Raw[EF_VEL_Y] := T52_DIVE_VY;
      end;
    end;

    if E.Raw[EF_CHILD_B] = T52_SUMMON_BEAT then
    begin
      Inc(E.Raw[EF_CHILD_A]);
      if E.Raw[EF_CHILD_A] > T52_TIMING[D] then
      begin
        E.Raw[EF_CHILD_A] := 0;
        Inc(E.Raw[EF_SHOTS]);
        if E.Raw[EF_SHOTS] <= T52_COUNT[D] - 1 then
        begin
          World.PlaySound(T52_SND_SPAWN);
          Sign := Compare(0, E.Raw[EF_VEL_X]);
          Slot := World.Spawn(EKIND_MINOR, T52_MINION_TYPE,
                              Sign * T52_MINION_AHEAD
                                + E.Raw[EF_POS_X] - POSITION_BIAS
                                - World.Layer.DeltaX,
                              E.Raw[EF_POS_Y] - POSITION_BIAS
                                + T52_MINION_BELOW
                                - World.Layer.DeltaY);
          { DirVelX(0) is 32, so the chargers run at 64, 96 or 96. }
          World.SetSpawnField(Slot, EF_VEL_X,
                              Compare(0, E.Raw[EF_VEL_X])
                                * DirVelX(0) * T52_SPEED[D]);
        end;
      end;

      if T52_COUNT[D] <= E.Raw[EF_SHOTS] then
      begin
        E.Raw[EF_STATE] := 1;
        E.Raw[EF_BLOCK_B] := 0;
        E.Raw[EF_CHILD_A] := 0;
        E.Raw[EF_CHILD_B] := 0;
        E.Raw[EF_SHOTS] := 0;
        E.Raw[EF_FLAG1C] := 0;
      end;
    end;
  end;

  if E.Raw[EF_STATE] = 3 then
  begin
    E.Raw[EF_FLAG1C] := T52_DIVE_FRAME;
    if World.TileAtX(E, E.Raw[EF_VEL_X], False) >= World.SolidThreshold then
      E.Raw[EF_VEL_X] := 0;
    Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);

    Inc(E.Raw[EF_VEL_Y], T52_GRAVITY);
    if E.Raw[EF_VEL_Y] > T52_LAND_VY then
    begin
      World.PlaySound(T52_SND_LAND);
      E.Raw[EF_STATE] := 1;
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_CHILD_A] := 0;
      E.Raw[EF_FLAG1C] := 0;
      E.Raw[EF_VEL_X] := Compare(E.Raw[EF_POS_X], PlayerX) shl 7;
      if E.Raw[EF_VEL_X] = 0 then
        E.Raw[EF_VEL_X] := T52_CHARGE_VX;
      E.Raw[EF_VEL_Y] := 0;
    end;
    Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);
  end;
end;

procedure EntityUpdate_Type54_Boss_FloatingMagician(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, D, Hop: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T54_FRAMES) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T54_SPRITES[Frame];

  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;

  Inc(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] > T54_TICKS then
  begin
    E.Raw[EF_BLOCK_B] := 0;
    E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T54_FRAMES;
  end;

  { The heading is an oscillator, not a direction of travel. }
  Inc(E.Raw[EF_POS_Y], DirVelY(E.Raw[EF_FACING]));
  E.Raw[EF_FACING] := (E.Raw[EF_FACING] + 1) mod DIR_COUNT;

  Inc(E.Raw[EF_CHILD_A]);

  if E.Raw[EF_STATE] = 0 then
  begin
    E.Raw[EF_STATE] := 1;
    Inc(E.Raw[EF_HP], T54_HP[D]);
  end;

  if E.Raw[EF_STATE] = 1 then
    { Paced off its OWN health, the same way type 52 is. }
    if (E.Raw[EF_HP] div T54_HP_PACE_DIV) * T54_HP_PACE_MUL + T54_HP_PACE_ADD
       < E.Raw[EF_CHILD_A] then
    begin
      World.PlaySound(T54_SND_BLINK);
      E.Raw[EF_STATE] := 2;
      E.Raw[EF_CHILD_A] := 0;
      E.Raw[EF_DEATH_TIMER] := T54_BLINK;
      E.Raw[EF_TIMER] := T54_BLINK;
    end;

  if (E.Raw[EF_STATE] = 2) and (E.Raw[EF_DEATH_TIMER] = 0) then
  begin
    E.Raw[EF_STATE] := 3;
    E.Raw[EF_CHILD_A] := 0;
    World.Spawn(EKIND_MINOR, T54_SHOT_TYPE,
                E.Raw[EF_POS_X] - POSITION_BIAS - World.Layer.DeltaX,
                E.Raw[EF_POS_Y] - POSITION_BIAS - World.Layer.DeltaY);
  end;

  if E.Raw[EF_STATE] = 3 then
  begin
    E.Raw[EF_DEATH_TIMER] := 1;
    E.Raw[EF_TIMER] := 2;
    if E.Raw[EF_CHILD_A] > T54_HOLD then
    begin
      World.PlaySound(T54_SND_BLINK);
      E.Raw[EF_STATE] := 4;
      E.Raw[EF_CHILD_A] := 0;
      E.Raw[EF_DEATH_TIMER] := T54_BLINK;
      E.Raw[EF_TIMER] := T54_BLINK;

      Hop := E.Raw[EF_CHILD_B];
      if (Hop < 0) or (Hop >= T54_HOPS) then
        Hop := 0;
      Inc(E.Raw[EF_POS_X], T54_HOP[Hop][0] * T54_HOP_SCALE);
      Inc(E.Raw[EF_POS_Y], T54_HOP[Hop][1] * T54_HOP_SCALE);
      Inc(E.Raw[EF_CHILD_B]);
      if E.Raw[EF_CHILD_B] > T54_HOPS - 1 then
        E.Raw[EF_CHILD_B] := 0;
    end;
  end;

  if (E.Raw[EF_STATE] = 4) and (E.Raw[EF_DEATH_TIMER] = 0) then
  begin
    E.Raw[EF_STATE] := 1;
    E.Raw[EF_CHILD_A] := 0;
  end;
end;

procedure EntityUpdate_Type55(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, D, Slot, JitterY, JitterX: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if E.Raw[EF_STATE] = 0 then
  begin
    if (Frame < 0) or (Frame >= T55_FLY_FRAMES) then
      Frame := 0;
    E.Raw[EF_ANIM_ID] := T55_FLY_SPRITES[Frame];
  end;
  if E.Raw[EF_STATE] = 1 then
  begin
    if (Frame < 0) or (Frame >= T55_TRAIL_FRAMES) then
      Frame := 0;
    E.Raw[EF_ANIM_ID] := T55_TRAIL_SPRITES[Frame];
  end;

  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;

  if E.Raw[EF_STATE] = 0 then
  begin
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T55_FLY_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T55_FLY_FRAMES;
      if E.Raw[EF_FLAG1C] = 0 then
        World.PlaySound(T55_SND_LOOP);
    end;

    Inc(E.Raw[EF_SHOTS]);
    if E.Raw[EF_SHOTS] < T55_HOMING_UNTIL then
    begin
      if World.Pool <> nil then
        World.Pool.Steer(E.Raw[EF_SLOT], T55_TURN_TIMER, T55_TURN_RELOAD);
      { Times one on easy, and compounding above it. As written. }
      E.Raw[EF_VEL_X] := (D + 1) * E.Raw[EF_VEL_X];
      E.Raw[EF_VEL_Y] := (D + 1) * E.Raw[EF_VEL_Y];
    end;

    { A second counter of the same thing, one frame longer. }
    Inc(E.Raw[EF_BLOCK_B + 4]);
    if E.Raw[EF_BLOCK_B + 4] > T55_LIFETIME then
    begin
      World.DestroyEntity(E, False);
      Exit;
    end;

    Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);
    Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);

    Inc(E.Raw[EF_CHILD_B]);
    if E.Raw[EF_CHILD_B] > T55_TRAIL_EVERY then
    begin
      E.Raw[EF_CHILD_B] := 0;
      { Y's random is drawn first - that is the order the original draws
        them, and the sequence only matches if it is kept. }
      JitterY := World.RandomBelow(T55_TRAIL_SPREAD) - T55_TRAIL_CENTRE;
      JitterX := World.RandomBelow(T55_TRAIL_SPREAD) - T55_TRAIL_CENTRE;
      Slot := World.Spawn(EKIND_MINOR, T55_SELF_TYPE,
                          JitterX * T55_TRAIL_SCALE
                            + E.Raw[EF_POS_X] - POSITION_BIAS,
                          JitterY * T55_TRAIL_SCALE
                            + E.Raw[EF_POS_Y] - POSITION_BIAS);
      World.SetSpawnField(Slot, EF_STATE, 1);
    end;
  end;

  if E.Raw[EF_STATE] = 1 then
  begin
    E.Raw[EF_DEPTH] := T55_TRAIL_DEPTH;
    E.Raw[EF_TIMER] := T55_TRAIL_TIMER;
    if E.Raw[EF_DEATH_TIMER] = 0 then
      E.Raw[EF_DEATH_TIMER] := T55_TRAIL_BLINK;

    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T55_TRAIL_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      Inc(E.Raw[EF_FLAG1C]);
      if E.Raw[EF_FLAG1C] > T55_TRAIL_FRAMES - 1 then
        World.DestroyEntity(E, False);
    end;
  end;
end;

procedure EntityUpdate_Type57(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, D, I, Slot, Facing: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];

  { --- the sprite, four different ways --- }
  if E.Raw[EF_VARIANT] = 0 then
  begin
    if (Frame < 0) or (Frame >= T57_V0_FRAMES) then
      Frame := 0;
    E.Raw[EF_ANIM_ID] := T57_V0_SPRITES[Frame];
  end;
  if E.Raw[EF_VARIANT] = 1 then
  begin
    if (Frame < 0) or (Frame >= T57_V1_FRAMES) then
      Frame := 0;
    if E.Raw[EF_STATE] = 0 then
    begin
      { The same table as two rows, by the sign - two ifs and no else. }
      if E.Raw[EF_VEL_X] > 0 then
        E.Raw[EF_ANIM_ID] := T57_V1_SPRITES[0];
      if E.Raw[EF_VEL_X] < 0 then
        E.Raw[EF_ANIM_ID] := T57_V1_SPRITES[T57_V1_ROW];
    end
    else
      E.Raw[EF_ANIM_ID] := T57_V1_SPRITES[Frame];
  end;
  if E.Raw[EF_VARIANT] = 2 then
  begin
    if (Frame < 0) or (Frame >= T57_V2_FRAMES) then
      Frame := 0;
    E.Raw[EF_ANIM_ID] := T57_V2_SPRITES[Frame];
  end;
  if E.Raw[EF_VARIANT] = 3 then
  begin
    if (Frame < 0) or (Frame >= T57_V3_FRAMES) then
      Frame := 0;
    E.Raw[EF_ANIM_ID] := T57_V3_SPRITES[Frame];
  end;

  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;

  { --- variant 0: type 56's shot --- }
  if E.Raw[EF_VARIANT] = 0 then
  begin
    Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);
    Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T57_V0_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T57_V0_FRAMES;
    end;
  end;

  { --- variant 1: skims, then falls when it meets a wall --- }
  if E.Raw[EF_VARIANT] = 1 then
  begin
    if E.Raw[EF_STATE] = 0 then
    begin
      Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);
      if World.TileAtX(E, E.Raw[EF_VEL_X], False) >= World.SolidThreshold then
      begin
        World.PlaySound(T57_V1_SND_HIT);
        E.Raw[EF_STATE] := 1;
        E.Raw[EF_VEL_Y] := T57_V1_HOP;
      end;
    end;

    if E.Raw[EF_STATE] = 1 then
    begin
      Inc(E.Raw[EF_VEL_Y], T57_V1_GRAVITY);
      if E.Raw[EF_VEL_Y] > T57_V1_TERMINAL then
        E.Raw[EF_VEL_Y] := T57_V1_TERMINAL;
      Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);
      Inc(E.Raw[EF_BLOCK_B]);
      if E.Raw[EF_BLOCK_B] > T57_V1_TICKS then
      begin
        E.Raw[EF_BLOCK_B] := 0;
        E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T57_V1_FRAMES;
      end;
    end;
  end;

  { --- variant 2: the homing fireball, type 55's state 0 rebuilt --- }
  if E.Raw[EF_VARIANT] = 2 then
  begin
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T57_V2_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T57_V2_FRAMES;
      if E.Raw[EF_FLAG1C] = 0 then
        World.PlaySound(T57_V2_SND_LOOP);
    end;

    Inc(E.Raw[EF_SHOTS]);
    if E.Raw[EF_SHOTS] < T57_V2_HOMING_UNTIL then
    begin
      if World.Pool <> nil then
        World.Pool.Steer(E.Raw[EF_SLOT], T57_V2_TURN_TIMER,
                         T57_V2_TURN_RELOAD);
      E.Raw[EF_VEL_X] := (D + 1) * E.Raw[EF_VEL_X];
      E.Raw[EF_VEL_Y] := (D + 1) * E.Raw[EF_VEL_Y];
    end;

    Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);
    Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);

    Inc(E.Raw[EF_BLOCK_B + 4]);
    if E.Raw[EF_BLOCK_B + 4] mod T57_V2_TRAIL_EVERY = 0 then
      World.Spawn(EKIND_MINOR, T57_V2_TRAIL_TYPE,
                  E.Raw[EF_POS_X] - POSITION_BIAS,
                  E.Raw[EF_POS_Y] - POSITION_BIAS);

    if E.Raw[EF_BLOCK_B + 4] > T57_V2_LIFETIME then
    begin
      Slot := World.Spawn(EKIND_MINOR, T57_V2_END_TYPE,
                          E.Raw[EF_POS_X] - POSITION_BIAS,
                          E.Raw[EF_POS_Y] - POSITION_BIAS);
      World.SetSpawnField(Slot, EF_VARIANT, T57_V2_END_VARIANT);
      World.DestroyEntity(E, False);
      Exit;
    end;
  end;

  { --- variant 3: the egg --- }
  if E.Raw[EF_VARIANT] = 3 then
  begin
    if E.Raw[EF_STATE] = 0 then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      Inc(E.Raw[EF_CHILD_A]);
      { Shrinking hops - the sixth has no lift at all. }
      E.Raw[EF_VEL_Y] := (T57_V3_HOPS - E.Raw[EF_CHILD_A]) * T57_V3_HOP_UNIT;
      if E.Raw[EF_CHILD_A] < T57_V3_HOPS then
        E.Raw[EF_STATE] := 1
      else
        E.Raw[EF_STATE] := 2;
    end;

    if E.Raw[EF_STATE] = 1 then
    begin
      Inc(E.Raw[EF_BLOCK_B]);
      if E.Raw[EF_BLOCK_B] > T57_V3_TICKS then
      begin
        E.Raw[EF_BLOCK_B] := 0;
        E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T57_V3_ROCK_FRAMES;
      end;

      { Last frame's reversal, collected now that the flush landing is done. }
      if E.Raw[EF_PARKED_VEL] <> 0 then
      begin
        E.Raw[EF_VEL_X] := E.Raw[EF_PARKED_VEL];
        E.Raw[EF_PARKED_VEL] := 0;
      end;

      if World.TileAtX(E, E.Raw[EF_VEL_X], False) >= World.SolidThreshold then
      begin
        E.Raw[EF_PARKED_VEL] := -E.Raw[EF_VEL_X];
        E.Raw[EF_VEL_X] := World.EdgeDistX(E, E.Raw[EF_VEL_X]);
      end;
      Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);

      Inc(E.Raw[EF_VEL_Y], T57_V3_GRAVITY);
      if E.Raw[EF_VEL_Y] > T57_V3_TERMINAL then
        E.Raw[EF_VEL_Y] := T57_V3_TERMINAL;
      if World.TileAtY(E, E.Raw[EF_VEL_Y], False) >= World.SolidThreshold then
      begin
        World.PlaySound(T57_V3_SND_LAND);
        E.Raw[EF_VEL_Y] := World.EdgeDistY(E, E.Raw[EF_VEL_Y]);
        E.Raw[EF_STATE] := 0;
        E.Raw[EF_FLAG1C] := 0;
      end;
      Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);
    end;

    if E.Raw[EF_STATE] = 2 then
    begin
      Inc(E.Raw[EF_BLOCK_B]);
      if E.Raw[EF_BLOCK_B] > T57_V3_TICKS then
      begin
        E.Raw[EF_BLOCK_B] := 0;
        Inc(E.Raw[EF_FLAG1C]);
        if E.Raw[EF_FLAG1C] > T57_V3_FRAMES - 1 then
        begin
          E.Raw[EF_FLAG1C] := 0;
          Inc(E.Raw[EF_CHILD_A]);
        end;

        if T57_V3_HATCH[D] < E.Raw[EF_CHILD_A] then
        begin
          for I := 1 to T57_V3_BURST do
          begin
            Slot := World.Spawn(EKIND_MINOR, T57_V3_BURST_TYPE,
                                E.Raw[EF_POS_X] - POSITION_BIAS,
                                E.Raw[EF_POS_Y] - POSITION_BIAS);
            World.SetSpawnField(Slot, EF_BLOCK_A + 1, 0);
            Facing := World.RandomBelow(DIR_COUNT);
            World.SetSpawnField(Slot, EF_FACING, Facing);
            World.SetSpawnField(Slot, EF_VEL_X,
              (World.RandomBelow(T57_V3_SPEED_SPREAD) + T57_V3_SPEED_BASE)
              * HalfExtent(DirVelX(Facing)));
            World.SetSpawnField(Slot, EF_VEL_Y,
              (World.RandomBelow(T57_V3_SPEED_SPREAD) + T57_V3_SPEED_BASE)
              * HalfExtent(DirVelY(Facing)));
          end;
          World.PlaySound(T57_V3_SND_HATCH);

          { An ACTOR, not a minor - and in state 3, which is the state
            Entity_UpdateAll touch-tests twice. }
          Slot := World.Spawn(EKIND_ACTOR, T57_V3_HATCHLING,
                              E.Raw[EF_POS_X] - POSITION_BIAS,
                              E.Raw[EF_POS_Y] - POSITION_BIAS);
          World.SetSpawnField(Slot, EF_STATE, T57_V3_HATCHLING_STATE);
          World.SetSpawnField(Slot, EF_HP, T57_V3_HATCHLING_HP);
          World.SetSpawnField(Slot, EF_TYPEF_0C, 1);
          World.SetSpawnField(Slot, EF_DEPTH, T57_V3_HATCHLING_DEPTH);
          World.DestroyEntity(E, False);
        end;
      end;
    end;
  end;
end;

procedure EntityUpdate_Type61_Mon_HenaHena(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, D, Cap: Integer;
  Player: PEntity;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame > High(T61_SPRITES)) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T61_SPRITES[Frame];

  if EntityUpdateDying(E, AGameState, World) then
    Exit;
  if World.Pool = nil then
    Exit;

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;
  Player := World.Pool.Entity(SLOT_SINGLE_FIRST);

  if E.Raw[EF_STATE] = 0 then
    E.Raw[EF_STATE] := 1;

  if E.Raw[EF_STATE] = 1 then
  begin
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T61_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T61_FRAMES;
    end;

    { A quarter turn a frame: 32, 0, -32, 0 - it sways. }
    Inc(E.Raw[EF_POS_X], DirVelX(E.Raw[EF_FACING]));
    E.Raw[EF_FACING] := (E.Raw[EF_FACING] + T61_IDLE_TURN) mod DIR_COUNT;

    if EntitiesOverlap(E, Player^, T61_WAKE_X, T61_WAKE_Y) then
    begin
      World.PlaySound(T61_SND_SQUEAK);
      E.Raw[EF_STATE] := 2;
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_VEL_X] := 0;
      E.Raw[EF_FLAG1C] := T61_RUN_FIRST;
    end;
  end;

  if E.Raw[EF_STATE] = 2 then
  begin
    { Compare(player, self), not Compare(self, player) - this accelerates
      AWAY. Every other chaser has the arguments the other way round. }
    Inc(E.Raw[EF_VEL_X],
        Compare(Player^.Raw[EF_POS_X], E.Raw[EF_POS_X]) * T61_ACCEL);
    Cap := T61_SPEED[D] * T61_SPEED_SCALE;
    if E.Raw[EF_VEL_X] > Cap then
      E.Raw[EF_VEL_X] := Cap;
    if E.Raw[EF_VEL_X] < -Cap then
      E.Raw[EF_VEL_X] := -Cap;

    if World.TileAtX(E, E.Raw[EF_VEL_X], False) >= World.SolidThreshold then
      E.Raw[EF_VEL_X] := World.EdgeDistX(E, E.Raw[EF_VEL_X]);
    Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);

    Inc(E.Raw[EF_VEL_Y], T61_GRAVITY);
    if E.Raw[EF_VEL_Y] > T61_TERMINAL then
      E.Raw[EF_VEL_Y] := T61_TERMINAL;
    if World.TileAtY(E, E.Raw[EF_VEL_Y], False) >= World.SolidThreshold then
      E.Raw[EF_VEL_Y] := World.EdgeDistY(E, E.Raw[EF_VEL_Y]);
    Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);

    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T61_RUN_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      Inc(E.Raw[EF_FLAG1C]);
      if E.Raw[EF_FLAG1C] > T61_RUN_LAST then
        E.Raw[EF_FLAG1C] := T61_RUN_FIRST;
    end;

    Inc(E.Raw[EF_CHILD_A]);
    if E.Raw[EF_CHILD_A] > T61_SQUEAK_EVERY then
    begin
      E.Raw[EF_CHILD_A] := 0;
      World.PlaySound(T61_SND_SQUEAK);
    end;
  end;

  { In BOTH states, and last: catching it is what kills it. }
  if EntitiesOverlap(E, Player^, T61_TOUCH_SCALE, T61_TOUCH_SCALE) then
    E.Raw[EF_HP] := 0;
end;

procedure EntityUpdate_Type62_Mon_PenguinHeishi(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, D, PlayerX: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T62_FRAMES) then
    Frame := 0;
  if E.Raw[EF_VEL_X] < 0 then
    E.Raw[EF_ANIM_ID] := T62_SPRITES[0][Frame];
  if E.Raw[EF_VEL_X] > 0 then
    E.Raw[EF_ANIM_ID] := T62_SPRITES[1][Frame];

  if EntityUpdateDying(E, AGameState, World) then
    Exit;
  if World.Pool = nil then
    Exit;

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;
  PlayerX := World.Pool.Field(SLOT_SINGLE_FIRST, EF_POS_X);

  { Recomputed from the geometry every frame - 2 while closing on you. }
  E.Raw[EF_VULN_KIND] := T62_VULN_AWAY;
  if ((PlayerX < E.Raw[EF_POS_X]) and (E.Raw[EF_VEL_X] < 0))
     or ((E.Raw[EF_POS_X] < PlayerX) and (E.Raw[EF_VEL_X] > 0)) then
    E.Raw[EF_VULN_KIND] := T62_VULN_TOWARDS;

  if E.Raw[EF_STATE] = 0 then
  begin
    E.Raw[EF_STATE] := 1;
    E.Raw[EF_VEL_X] := Compare(E.Raw[EF_POS_X], PlayerX);
    if E.Raw[EF_VEL_X] = 0 then
      E.Raw[EF_VEL_X] := 1;
    E.Raw[EF_VEL_X] := T62_SPEED[D] * E.Raw[EF_VEL_X] * T62_SPEED_SCALE;
    { Compare(vel, 0) is -sign(vel), so the rank offset goes BACKWARDS. }
    Inc(E.Raw[EF_POS_X],
        Compare(E.Raw[EF_VEL_X], 0) * T62_RANK_STEP * E.Raw[EF_VARIANT]);
  end;

  Dec(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] < 1 then
  begin
    E.Raw[EF_BLOCK_B] := T62_TICKS;
    E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T62_FRAMES;
  end;

  { A wall ahead, or no floor one tile down - type 60's probe pair. }
  if (World.TileAtX(E, E.Raw[EF_VEL_X], False) >= World.SolidThreshold)
     or (World.TileAtX(E, E.Raw[EF_VEL_X], False, T62_LEDGE_PROBE)
         < World.SolidThreshold) then
    E.Raw[EF_VEL_X] := -E.Raw[EF_VEL_X];

  { Frozen while EF_CHILD_A runs down. Nothing here ever sets it. }
  if E.Raw[EF_CHILD_A] = 0 then
    Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X])
  else
    Dec(E.Raw[EF_CHILD_A]);
end;

procedure EntityUpdate_Type63_Mon_PenguinKnife(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, D, Slot, PlayerX: Integer;
  Player: PEntity;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame > High(T63_SPRITES[0])) then
    Frame := 0;
  if E.Raw[EF_VEL_X] < 0 then
    E.Raw[EF_ANIM_ID] := T63_SPRITES[0][Frame];
  if E.Raw[EF_VEL_X] > 0 then
    E.Raw[EF_ANIM_ID] := T63_SPRITES[1][Frame];

  if EntityUpdateDying(E, AGameState, World) then
    Exit;
  if World.Pool = nil then
    Exit;

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;
  Player := World.Pool.Entity(SLOT_SINGLE_FIRST);
  PlayerX := Player^.Raw[EF_POS_X];

  if E.Raw[EF_STATE] = 0 then
  begin
    E.Raw[EF_STATE] := 1;
    E.Raw[EF_VEL_X] := T63_WALK_SPEED;
  end;

  if E.Raw[EF_STATE] = 1 then
  begin
    Dec(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] < 1 then
    begin
      E.Raw[EF_BLOCK_B] := T63_TICKS;
      E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T63_FRAMES;
    end;

    if (World.TileAtX(E, E.Raw[EF_VEL_X], False) >= World.SolidThreshold)
       or (World.TileAtX(E, E.Raw[EF_VEL_X], False, T63_LEDGE_PROBE)
           < World.SolidThreshold) then
      E.Raw[EF_VEL_X] := -E.Raw[EF_VEL_X];
    Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);

    if E.Raw[EF_CHILD_A] > 0 then
      Dec(E.Raw[EF_CHILD_A]);

    { Off cooldown, in range, AND already heading your way. }
    if (E.Raw[EF_CHILD_A] = 0)
       and EntitiesOverlap(E, Player^, T63_WAKE_X, T63_WAKE_Y)
       and (((PlayerX < E.Raw[EF_POS_X]) and (E.Raw[EF_VEL_X] < 0))
            or ((E.Raw[EF_POS_X] < PlayerX) and (E.Raw[EF_VEL_X] > 0))) then
    begin
      E.Raw[EF_STATE] := 2;
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_CHILD_A] := 0;
      E.Raw[EF_FLAG1C] := T63_AIM_FRAME;
    end;
  end;

  if E.Raw[EF_STATE] = 2 then
  begin
    Inc(E.Raw[EF_CHILD_A]);
    { An equality, not a threshold - so exactly one shot. }
    if T63_FIRE_AT[D] = E.Raw[EF_CHILD_A] then
    begin
      World.PlaySound(T63_SND_FIRE);
      Slot := World.Spawn(EKIND_MINOR, T63_SHOT_TYPE,
                          E.Raw[EF_POS_X] - POSITION_BIAS
                            + E.Raw[EF_VEL_X] * T63_SHOT_AHEAD,
                          E.Raw[EF_POS_Y] - POSITION_BIAS + T63_SHOT_DROP);
      World.SetSpawnField(Slot, EF_VARIANT, T63_SHOT_VARIANT);
      World.SetSpawnField(Slot, EF_VEL_X, T63_SHOT_SPD[D] * E.Raw[EF_VEL_X]);
      E.Raw[EF_FLAG1C] := T63_FIRE_FRAME;
    end;

    if T63_RECOVER[D] < E.Raw[EF_CHILD_A] then
    begin
      E.Raw[EF_STATE] := 1;
      E.Raw[EF_CHILD_A] := T63_COOLDOWN[D];
      E.Raw[EF_FLAG1C] := 0;
      { And it always walks back the way it came. }
      E.Raw[EF_VEL_X] := -E.Raw[EF_VEL_X];
    end;
  end;
end;

procedure EntityUpdate_Type64_SpikePress(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, D, Slot, Rise: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T64_FRAMES) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T64_SPRITES[Frame];

  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;

  { Outside every state - it flaps at the same rate throughout. }
  Inc(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] > T64_TICKS then
  begin
    E.Raw[EF_BLOCK_B] := 0;
    E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T64_FRAMES;
  end;

  if E.Raw[EF_STATE] = 0 then
  begin
    E.Raw[EF_STATE] := 1;
    Inc(E.Raw[EF_POS_X], T64_NUDGE);
  end;

  if E.Raw[EF_STATE] = 1 then
  begin
    Inc(E.Raw[EF_CHILD_A]);
    { Scaled by the variant, so a row of them drops in sequence - and a
      variant of 0 gives a threshold of 0 and drops at once. }
    if E.Raw[EF_CHILD_A] > T64_WAIT[D] * E.Raw[EF_VARIANT] then
    begin
      E.Raw[EF_STATE] := 2;
      E.Raw[EF_CHILD_A] := 0;
      E.Raw[EF_VEL_Y] := 0;
    end;
  end;

  if E.Raw[EF_STATE] = 2 then
  begin
    Inc(E.Raw[EF_VEL_Y], T64_GRAVITY);
    if E.Raw[EF_VEL_Y] > T64_TERMINAL then
      E.Raw[EF_VEL_Y] := T64_TERMINAL;

    if World.TileAtY(E, E.Raw[EF_VEL_Y], False) >= World.SolidThreshold then
    begin
      World.PlaySound(T64_SND_SLAM);
      Slot := World.Spawn(EKIND_MINOR, T64_WAVE_TYPE,
                          E.Raw[EF_POS_X] - POSITION_BIAS - T64_WAVE_OUT,
                          E.Raw[EF_POS_Y] - POSITION_BIAS + T64_WAVE_DROP);
      World.SetSpawnField(Slot, EF_VEL_X, -T64_WAVE_SPEED);
      Slot := World.Spawn(EKIND_MINOR, T64_WAVE_TYPE,
                          E.Raw[EF_POS_X] - POSITION_BIAS + T64_WAVE_OUT,
                          E.Raw[EF_POS_Y] - POSITION_BIAS + T64_WAVE_DROP);
      World.SetSpawnField(Slot, EF_VEL_X, T64_WAVE_SPEED);
      E.Raw[EF_STATE] := 3;
      E.Raw[EF_VEL_Y] := World.EdgeDistY(E, E.Raw[EF_VEL_Y]);
    end;
    Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);
  end;

  if E.Raw[EF_STATE] = 3 then
  begin
    Inc(E.Raw[EF_CHILD_A]);
    if E.Raw[EF_CHILD_A] > T64_REST[D] then
    begin
      E.Raw[EF_CHILD_A] := 0;
      E.Raw[EF_STATE] := 4;
    end;
  end;

  if E.Raw[EF_STATE] = 4 then
  begin
    Rise := T64_RISE[D] * T64_RISE_SCALE;
    E.Raw[EF_VEL_Y] := Rise;
    if World.TileAtY(E, Rise, False) >= World.SolidThreshold then
    begin
      E.Raw[EF_STATE] := 1;
      E.Raw[EF_VEL_Y] := World.EdgeDistY(E, E.Raw[EF_VEL_Y]);
    end;
    Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);
  end;
end;

procedure EntityUpdate_Type65_Mon_DorDor(var E: TEntity; AGameState: Integer;
                              var Inp: TInputState; World: TEntityWorld);
var
  Frame, D, Slot, Hop, Shot, PlayerX: Integer;
  Player: PEntity;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T65_FRAMES) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T65_SPRITES[Frame];

  if EntityUpdateDying(E, AGameState, World) then
    Exit;
  if World.Pool = nil then
    Exit;

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;
  Player := World.Pool.Entity(SLOT_SINGLE_FIRST);
  PlayerX := Player^.Raw[EF_POS_X];

  if E.Raw[EF_STATE] = 0 then
  begin
    { Above easy it gives ITSELF hp. Types 50, 52 and 54 take it away. }
    if D <> 0 then
      Inc(E.Raw[EF_HP], T65_HARD_HP_BONUS);
    E.Raw[EF_STATE] := 1;
    E.Raw[EF_CHILD_B] := E.Raw[EF_VARIANT];
  end;

  if E.Raw[EF_STATE] = 1 then
  begin
    E.Raw[EF_VEL_X] := Compare(E.Raw[EF_POS_X], PlayerX) shl T65_AIM_SHIFT;
    { The rising edge of ATTACK, inside a 10x2 box. Nothing else starts it. }
    if EntitiesOverlap(E, Player^, T65_WAKE_X, T65_WAKE_Y)
       and Inp.Button[T65_ATTACK_BUTTON]
       and (not Inp.ButtonLatch[T65_ATTACK_BUTTON]) then
    begin
      World.PlaySound(T65_SND_BLINK);
      E.Raw[EF_STATE] := 2;
      E.Raw[EF_DEATH_TIMER] := T65_BLINK;
      E.Raw[EF_TIMER] := T65_BLINK;
    end;
  end;

  if (E.Raw[EF_STATE] = 2) and (E.Raw[EF_DEATH_TIMER] = 0) then
  begin
    E.Raw[EF_STATE] := 3;
    E.Raw[EF_CHILD_A] := 0;
    Slot := World.Spawn(EKIND_MINOR, T65_SHOT_TYPE,
                        E.Raw[EF_POS_X] - POSITION_BIAS,
                        E.Raw[EF_POS_Y] - POSITION_BIAS);
    World.SetSpawnField(Slot, EF_VARIANT, T65_SHOT_VARIANT);
    Shot := Compare(E.Raw[EF_POS_X], PlayerX) * T65_SHOT_SPEED;
    if Shot = 0 then
      Shot := T65_SHOT_SPEED;
    World.SetSpawnField(Slot, EF_VEL_X, Shot);
    { Only this boss writes these two on its shot. }
    World.SetSpawnField(Slot, EF_VULN_KIND, T65_SHOT_VULN);
    World.SetSpawnField(Slot, EF_HIT_SOUND, T65_SHOT_HIT_SOUND);
  end;

  if E.Raw[EF_STATE] = 3 then
  begin
    E.Raw[EF_DEATH_TIMER] := 1;
    E.Raw[EF_TIMER] := 2;
    Inc(E.Raw[EF_CHILD_A]);
    if E.Raw[EF_CHILD_A] > T65_HOLD then
    begin
      World.PlaySound(T65_SND_BLINK);
      E.Raw[EF_STATE] := 4;
      E.Raw[EF_CHILD_A] := 0;
      Hop := E.Raw[EF_CHILD_B];
      if (Hop < 0) or (Hop >= T65_HOPS) then
        Hop := 0;
      Inc(E.Raw[EF_POS_X], T65_HOP[Hop] * T65_HOP_SCALE);
      E.Raw[EF_CHILD_B] := (E.Raw[EF_CHILD_B] + 1) mod T65_HOPS;
      E.Raw[EF_DEATH_TIMER] := T65_BLINK;
      E.Raw[EF_TIMER] := T65_BLINK;
    end;
  end;

  if (E.Raw[EF_STATE] = 4) and (E.Raw[EF_DEATH_TIMER] = 0) then
  begin
    E.Raw[EF_STATE] := 5;
    E.Raw[EF_CHILD_A] := 0;
  end;

  if E.Raw[EF_STATE] = 5 then
  begin
    Inc(E.Raw[EF_CHILD_A]);
    if E.Raw[EF_CHILD_A] > T65_HOLD then
    begin
      E.Raw[EF_STATE] := 1;
      E.Raw[EF_CHILD_A] := 0;
    end;
  end;

  { The bob, in every state. }
  Inc(E.Raw[EF_SHOTS]);
  if E.Raw[EF_SHOTS] > T65_BOB_TICKS then
  begin
    E.Raw[EF_SHOTS] := 0;
    E.Raw[EF_FACING] := (E.Raw[EF_FACING] + 1) mod DIR_COUNT;
  end;
  E.Raw[EF_VEL_Y] := HalfExtent(DirVelY(E.Raw[EF_FACING]));
  Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);

  Inc(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] > T65_TICKS then
  begin
    E.Raw[EF_BLOCK_B] := 0;
    E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T65_FRAMES;
  end;
end;

procedure EntityUpdate_Type66_GiantBall(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, Slot, Period: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if E.Raw[EF_VARIANT] = T66_ANCHOR then
  begin
    if (Frame < 0) or (Frame >= T66_V0_FRAMES) then
      Frame := 0;
    E.Raw[EF_ANIM_ID] := T66_V0_SPRITES[Frame];
  end;
  if E.Raw[EF_VARIANT] = T66_SATELLITE then
  begin
    if (Frame < 0) or (Frame >= T66_V1_FRAMES) then
      Frame := 0;
    E.Raw[EF_ANIM_ID] := T66_V1_SPRITES[Frame];
  end;

  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  { A placement parameter, not a timer - see the T66_ block. }
  Period := E.Raw[EF_BLOCK_A + 1];

  if E.Raw[EF_VARIANT] = T66_ANCHOR then
  begin
    if E.Raw[EF_STATE] = 0 then
    begin
      E.Raw[EF_STATE] := 1;
      E.Raw[EF_TYPEF_0C] := 0;
      E.Raw[EF_VULN_KIND] := 0;
      E.Raw[EF_DEPTH] := T66_ANCHOR_DEPTH;
      Slot := World.Spawn(EKIND_MINOR, T66_SELF_TYPE,
                          E.Raw[EF_POS_X] - POSITION_BIAS
                            - World.Layer.DeltaX,
                          E.Raw[EF_POS_Y] - POSITION_BIAS
                            + E.Raw[EF_FACING] * Period * T66_LIFT_UNIT
                            - World.Layer.DeltaY);
      World.SetSpawnField(Slot, EF_VARIANT, T66_SATELLITE);
      World.SetSpawnField(Slot, EF_FACING, E.Raw[EF_FACING]);
      World.SetSpawnField(Slot, EF_BLOCK_A + 1, Period);
    end;

    Inc(E.Raw[EF_BLOCK_B]);
    if Period < E.Raw[EF_BLOCK_B] then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      { `< 1`, where the satellite below asks `< 0`. }
      if Compare(E.Raw[EF_FACING], 0) < 1 then
        Inc(E.Raw[EF_FLAG1C])
      else
        Dec(E.Raw[EF_FLAG1C]);
      if E.Raw[EF_FLAG1C] > T66_V0_FRAMES - 1 then
        E.Raw[EF_FLAG1C] := 0;
      if E.Raw[EF_FLAG1C] < 0 then
        E.Raw[EF_FLAG1C] := T66_V0_FRAMES - 1;
    end;
  end;

  if E.Raw[EF_VARIANT] = T66_SATELLITE then
  begin
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T66_V1_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T66_V1_FRAMES;
    end;

    Dec(E.Raw[EF_CHILD_A]);
    if E.Raw[EF_CHILD_A] < 1 then
    begin
      E.Raw[EF_CHILD_A] := Period;
      { The MAGNITUDE of EF_FACING is a speed, not a heading. }
      E.Raw[EF_VEL_X] := Abs(E.Raw[EF_FACING])
                         * HalfExtent(DirVelX(E.Raw[EF_CHILD_B]));
      E.Raw[EF_VEL_Y] := Abs(E.Raw[EF_FACING])
                         * HalfExtent(DirVelY(E.Raw[EF_CHILD_B]));
      { And its SIGN is which way round the orbit goes. }
      if Compare(E.Raw[EF_FACING], 0) < 0 then
        Dec(E.Raw[EF_CHILD_B])
      else
        Inc(E.Raw[EF_CHILD_B]);
      if E.Raw[EF_CHILD_B] > DIR_COUNT - 1 then
      begin
        E.Raw[EF_CHILD_B] := 0;
        World.PlaySound(T66_SND_LAP);
      end;
      if E.Raw[EF_CHILD_B] < 0 then
      begin
        E.Raw[EF_CHILD_B] := DIR_COUNT - 1;
        World.PlaySound(T66_SND_LAP);
      end;
    end;

    Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);
    Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);
  end;
end;

procedure EntityUpdate_Type67_Mon_TurtleBomb(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, D, Slot, PlayerX: Integer;
  Player: PEntity;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame > High(T67_SPRITES)) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T67_SPRITES[Frame];

  if EntityUpdateDying(E, AGameState, World) then
    Exit;
  if World.Pool = nil then
    Exit;

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;
  Player := World.Pool.Entity(SLOT_SINGLE_FIRST);
  PlayerX := Player^.Raw[EF_POS_X];

  if E.Raw[EF_STATE] = 0 then
  begin
    E.Raw[EF_STATE] := 1;
    E.Raw[EF_VEL_X] := Compare(E.Raw[EF_POS_X], PlayerX);
    if E.Raw[EF_VEL_X] = 0 then
      E.Raw[EF_VEL_X] := 1;
    E.Raw[EF_VEL_X] := E.Raw[EF_VEL_X] shl T67_WALK_SHIFT;
  end;

  { Only the two moving states tick the walk cycle. }
  if (E.Raw[EF_STATE] = 1) or (E.Raw[EF_STATE] = 3) then
  begin
    Dec(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] < 1 then
    begin
      E.Raw[EF_BLOCK_B] := T67_TICKS;
      E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T67_FRAMES;
    end;
  end;

  if E.Raw[EF_STATE] = 1 then
  begin
    if (World.TileAtX(E, E.Raw[EF_VEL_X], False) >= World.SolidThreshold)
       or (World.TileAtX(E, E.Raw[EF_VEL_X], False, T67_LEDGE_PROBE)
           < World.SolidThreshold) then
      E.Raw[EF_VEL_X] := -E.Raw[EF_VEL_X];
    Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);
    Dec(E.Raw[EF_CHILD_A]);

    if (((PlayerX < E.Raw[EF_POS_X]) and (E.Raw[EF_VEL_X] < 0))
        or ((E.Raw[EF_POS_X] < PlayerX) and (E.Raw[EF_VEL_X] > 0)))
       and EntitiesOverlap(E, Player^, T67_RANGE[D], T67_WAKE_Y)
       and (E.Raw[EF_CHILD_A] < 1) then
    begin
      E.Raw[EF_STATE] := 2;
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_CHILD_A] := 0;
      E.Raw[EF_FLAG1C] := 0;
    end;
  end;

  if E.Raw[EF_STATE] = 2 then
  begin
    Inc(E.Raw[EF_CHILD_A]);
    if E.Raw[EF_CHILD_A] = T67_LAY_AT then
    begin
      World.PlaySound(T67_SND_LAY);
      Slot := World.Spawn(EKIND_MINOR, T67_EGG_TYPE,
                          E.Raw[EF_POS_X] - POSITION_BIAS
                            - World.Layer.DeltaX,
                          E.Raw[EF_POS_Y] - POSITION_BIAS - T67_EGG_LIFT
                            - World.Layer.DeltaY);
      World.SetSpawnField(Slot, EF_VARIANT, T67_EGG_VARIANT);
      World.SetSpawnField(Slot, EF_VEL_X, E.Raw[EF_VEL_X] * 2);
      World.SetSpawnField(Slot, EF_VEL_Y, T67_EGG_VY);
      World.SetSpawnField(Slot, EF_VULN_KIND, 0);
      E.Raw[EF_FLAG1C] := T67_LAY_FRAME;
    end;

    if E.Raw[EF_CHILD_A] > T67_LAY_END then
    begin
      E.Raw[EF_STATE] := 3;
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_CHILD_A] := 0;
      E.Raw[EF_FLAG1C] := 0;
      { AWAY - Compare's arguments the other way round, and a bigger shift. }
      E.Raw[EF_VEL_X] := Compare(PlayerX, E.Raw[EF_POS_X]);
      if E.Raw[EF_VEL_X] = 0 then
        E.Raw[EF_VEL_X] := 1;
      E.Raw[EF_VEL_X] := E.Raw[EF_VEL_X] shl T67_BOLT_SHIFT;
    end;
  end;

  if E.Raw[EF_STATE] = 3 then
  begin
    ApproachZero(E.Raw[EF_VEL_X], T67_FRICTION);
    if (World.TileAtX(E, E.Raw[EF_VEL_X], False) >= World.SolidThreshold)
       or (World.TileAtX(E, E.Raw[EF_VEL_X], False, T67_LEDGE_PROBE)
           < World.SolidThreshold) then
      E.Raw[EF_VEL_X] := -E.Raw[EF_VEL_X];
    Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);

    if E.Raw[EF_VEL_X] = 0 then
    begin
      E.Raw[EF_STATE] := 1;
      E.Raw[EF_CHILD_A] := T67_COOLDOWN[D];
      E.Raw[EF_VEL_X] := Compare(E.Raw[EF_POS_X], PlayerX);
      if E.Raw[EF_VEL_X] = 0 then
        E.Raw[EF_VEL_X] := 1;
      E.Raw[EF_VEL_X] := E.Raw[EF_VEL_X] shl T67_WALK_SHIFT;
    end;
  end;
end;

procedure EntityUpdate_Type68(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame: Integer;
begin
  { Only state 3 writes a sprite - a caught one keeps the frame it had. }
  if E.Raw[EF_STATE] = T68_RISING_STATE then
  begin
    Frame := E.Raw[EF_FLAG1C];
    if (Frame < 0) or (Frame >= T68_FRAMES) then
      Frame := 0;
    E.Raw[EF_ANIM_ID] := T68_SPRITES[Frame];
  end;

  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  if E.Raw[EF_STATE] = T68_RISING_STATE then
  begin
    Inc(E.Raw[EF_POS_Y], T68_RISE);
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T68_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      Inc(E.Raw[EF_FLAG1C]);
      if E.Raw[EF_FLAG1C] > T68_FRAMES - 1 then
      begin
        World.DestroyEntity(E, False);
        Exit;
      end;
    end;

    { Both insets from the same entry, one per frame. }
    Frame := E.Raw[EF_FLAG1C];
    if (Frame < 0) or (Frame >= T68_FRAMES) then
      Frame := 0;
    E.Raw[EF_INSET_PCT_X] := T68_INSET[Frame];
    E.Raw[EF_INSET_PCT_Y] := T68_INSET[Frame];
  end;

  if E.Raw[EF_STATE] = T68_CAUGHT_STATE then
  begin
    Inc(E.Raw[EF_VEL_Y], T68_GRAVITY);
    if E.Raw[EF_VEL_Y] > T68_TERMINAL then
      E.Raw[EF_VEL_Y] := T68_TERMINAL;
    if World.TileAtY(E, E.Raw[EF_VEL_Y], False) >= World.SolidThreshold then
    begin
      E.Raw[EF_VEL_Y] := World.EdgeDistY(E, E.Raw[EF_VEL_Y]);
      Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);
      { WITH loot - the only destroy in any handler here that passes True. }
      World.DestroyEntity(E, True);
      Exit;
    end;
    Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);
  end;
end;

procedure EntityUpdate_Type69_GoroGoro(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, Slot: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T69_FRAMES) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T69_SPRITES[Frame];

  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  if E.Raw[EF_STATE] = 0 then
    E.Raw[EF_STATE] := 1;

  { It never accelerates itself - something else has to push it. }
  ApproachZero(E.Raw[EF_VEL_X], T69_FRICTION);
  Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);

  { The absence of a floor, not the presence of a wall. }
  if World.TileAtY(E, T69_FLOOR_PROBE, False) < World.SolidThreshold then
  begin
    Slot := World.Spawn(EKIND_ACTOR, T69_PRIZE_TYPE,
                        E.Raw[EF_POS_X] - POSITION_BIAS,
                        E.Raw[EF_POS_Y] - POSITION_BIAS);
    World.SetSpawnField(Slot, EF_STATE, T69_PRIZE_STATE);
    World.SetSpawnField(Slot, EF_HP, T69_PRIZE_HP);
    { The prize wears this object's own sprite. }
    World.SetSpawnField(Slot, EF_ANIM_ID, E.Raw[EF_ANIM_ID]);
    World.DestroyEntity(E, False);
    { After the destroy, and with no opcode test - see the T69_ block.
      EF_EVENT_ID survives Entity_Destroy, which is why this order works. }
    World.SetProgress(World.EventProgressIndex(E.Raw[EF_EVENT_ID]));
  end;
end;

procedure EntityUpdate_Type70_AngrySwitch(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame > High(T70_V0_SPRITES)) then
    Frame := 0;
  if E.Raw[EF_VARIANT] = 0 then
    E.Raw[EF_ANIM_ID] := T70_V0_SPRITES[Frame];
  if E.Raw[EF_VARIANT] = T70_WALKER then
    E.Raw[EF_ANIM_ID] := T70_V1_SPRITES[Frame];

  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  if E.Raw[EF_STATE] = 0 then
  begin
    E.Raw[EF_STATE] := 1;
    E.Raw[EF_VEL_X] := T70_WALK_SPEED;
  end;

  if E.Raw[EF_STATE] = 1 then
  begin
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T70_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T70_FRAMES;
    end;

    { The one line the two variants differ by. }
    if E.Raw[EF_VARIANT] = T70_WALKER then
    begin
      if (World.TileAtX(E, E.Raw[EF_VEL_X], False) >= World.SolidThreshold)
         or (World.TileAtX(E, E.Raw[EF_VEL_X], False, T70_LEDGE_PROBE)
             < World.SolidThreshold) then
        E.Raw[EF_VEL_X] := -E.Raw[EF_VEL_X];
      Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);
    end;

    { Not a threshold and not zero - ANY value other than 100. }
    if E.Raw[EF_HP] <> T70_FULL_HP then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_STATE] := 2;
    end;
  end;

  if E.Raw[EF_STATE] = 2 then
  begin
    E.Raw[EF_FLAG1C] := T70_WOUND_FRAME;
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T70_DYING_FOR then
      E.Raw[EF_HP] := 0;
  end;
end;

procedure EntityUpdate_Type71_BouncyCat(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, D, PlayerX: Integer;

  procedure AimAndGo;
  begin
    E.Raw[EF_VEL_X] := Compare(E.Raw[EF_POS_X], PlayerX);
    if E.Raw[EF_VEL_X] = 0 then
      E.Raw[EF_VEL_X] := 1;
    E.Raw[EF_VEL_X] := E.Raw[EF_VEL_X] shl T71_SPEED_SHIFT;
  end;

begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T71_ROW) then
    Frame := 0;
  if E.Raw[EF_VEL_X] < 0 then
    E.Raw[EF_ANIM_ID] := T71_SPRITES[0][Frame];
  if E.Raw[EF_VEL_X] > 0 then
    E.Raw[EF_ANIM_ID] := T71_SPRITES[1][Frame];

  if EntityUpdateDying(E, AGameState, World) then
    Exit;
  if World.Pool = nil then
    Exit;

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;
  PlayerX := World.Pool.Field(SLOT_SINGLE_FIRST, EF_POS_X);

  if E.Raw[EF_STATE] = 0 then
  begin
    E.Raw[EF_STATE] := 1;
    AimAndGo;
    if D = 0 then
      Inc(E.Raw[EF_HP], T71_EASY_HP_PENALTY);
  end;

  if E.Raw[EF_STATE] = 1 then
  begin
    E.Raw[EF_VULN_KIND] := T71_VULN_WALKING;

    Dec(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] < 1 then
    begin
      E.Raw[EF_BLOCK_B] := T71_WALK_TICKS;
      E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T71_WALK_FRAMES;
    end;

    if (World.TileAtX(E, E.Raw[EF_VEL_X], False) >= World.SolidThreshold)
       or (World.TileAtX(E, E.Raw[EF_VEL_X], False, T71_LEDGE_PROBE)
           < World.SolidThreshold) then
      E.Raw[EF_VEL_X] := -E.Raw[EF_VEL_X];
    Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);

    { Only while it can be seen - off screen it walks for ever. }
    if not IsOffScreen(E, T71_OFFSCREEN_MARGIN) then
      Inc(E.Raw[EF_CHILD_A]);

    if T71_WALK[D] < E.Raw[EF_CHILD_A] then
    begin
      E.Raw[EF_STATE] := 2;
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_CHILD_A] := 0;
      E.Raw[EF_FLAG1C] := T71_CURL_FIRST;
      World.PlaySound(T71_SND_CURL);
      E.Raw[EF_DEATH_TIMER] := T71_STUN;
    end;
  end;

  if E.Raw[EF_STATE] = 2 then
  begin
    E.Raw[EF_VULN_KIND] := T71_VULN_RESTING;

    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T71_CURL_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      Inc(E.Raw[EF_FLAG1C]);
      if E.Raw[EF_FLAG1C] > T71_CURL_LAST then
      begin
        E.Raw[EF_FLAG1C] := T71_CURL_FIRST;
        { Counting completed LOOPS, which is what the rest table measures. }
        Inc(E.Raw[EF_CHILD_A]);
      end;
    end;

    if T71_REST[D] < E.Raw[EF_CHILD_A] then
    begin
      E.Raw[EF_STATE] := 1;
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_CHILD_A] := 0;
      E.Raw[EF_FLAG1C] := 0;
      AimAndGo;
      World.PlaySound(T71_SND_CURL);
      E.Raw[EF_DEATH_TIMER] := T71_STUN;
    end;
  end;
end;

procedure EntityUpdate_Type72(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, D, Slot, Dir: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if E.Raw[EF_VARIANT] = 0 then
  begin
    if (Frame < 0) or (Frame >= T72_V0_FRAMES) then
      Frame := 0;
    E.Raw[EF_ANIM_ID] := T72_V0_SPRITES[Frame];
  end;
  if E.Raw[EF_VARIANT] = 1 then
  begin
    { By HEADING, not by a frame counter - and shifted with the original's
      round-toward-zero correction. }
    Dir := E.Raw[EF_FACING];
    if Dir < 0 then
      Inc(Dir, (1 shl T72_DIR_SHIFT) - 1);
    Dir := Dir shr T72_DIR_SHIFT;
    if (Dir < 0) or (Dir >= T72_V1_DIRS) then
      Dir := 0;
    E.Raw[EF_ANIM_ID] := T72_V1_SPRITES[Dir];
  end;
  if E.Raw[EF_VARIANT] = 2 then
  begin
    if (Frame < 0) or (Frame >= T72_V2_FRAMES) then
      Frame := 0;
    E.Raw[EF_ANIM_ID] := T72_V2_SPRITES[Frame];
  end;

  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;

  if E.Raw[EF_VARIANT] = 0 then
  begin
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T72_V0_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T72_V0_FRAMES;
    end;

    if E.Raw[EF_STATE] = 0 then
    begin
      E.Raw[EF_STATE] := 1;
      E.Raw[EF_FIELD_C0] := 1;
      E.Raw[EF_CLASS] := T72_FALLER_CLASS;
      E.Raw[EF_VULN_KIND] := T72_FALLER_VULN;
    end;

    if E.Raw[EF_STATE] = 1 then
    begin
      Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);
      Inc(E.Raw[EF_VEL_Y], T72_GRAVITY);
      if E.Raw[EF_VEL_Y] > T72_TERMINAL then
        E.Raw[EF_VEL_Y] := T72_TERMINAL;
      Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);
    end;
  end;

  if E.Raw[EF_VARIANT] = 1 then
  begin
    E.Raw[EF_DEPTH] := T72_FLYER_DEPTH;
    { It moves by its heading and never writes EF_VEL_X or EF_VEL_Y. }
    Inc(E.Raw[EF_POS_X], DirVelX(E.Raw[EF_FACING]) * T72_SPEED[D]);
    Inc(E.Raw[EF_POS_Y], DirVelY(E.Raw[EF_FACING]) * T72_SPEED[D]);

    Inc(E.Raw[EF_CHILD_A]);
    if E.Raw[EF_CHILD_A] > T72_FLYER_LIFE then
    begin
      World.DestroyEntity(E, False);
      Exit;
    end;

    Inc(E.Raw[EF_CHILD_B]);
    if T72_TRAIL[D] < E.Raw[EF_CHILD_B] then
    begin
      E.Raw[EF_CHILD_B] := 0;
      Slot := World.Spawn(EKIND_MINOR, T72_SELF_TYPE,
                          E.Raw[EF_POS_X] - POSITION_BIAS
                            - World.Layer.DeltaX,
                          E.Raw[EF_POS_Y] - POSITION_BIAS
                            - World.Layer.DeltaY);
      World.SetSpawnField(Slot, EF_OWNER, E.Raw[EF_SLOT]);
      World.SetSpawnField(Slot, EF_VARIANT, T72_TRAIL_VARIANT);
      { The flyer's OWN velocity fields, which it never updates - so this is
        whatever it was spawned with, not where it is going. }
      World.SetSpawnField(Slot, EF_VEL_X, E.Raw[EF_VEL_X]);
      World.SetSpawnField(Slot, EF_VEL_Y, E.Raw[EF_VEL_Y]);
    end;
  end;

  if E.Raw[EF_VARIANT] = 2 then
  begin
    E.Raw[EF_DEPTH] := T72_TRAIL_DEPTH;
    { Scenery, not a second hazard. }
    E.Raw[EF_TOUCH_KIND] := 0;
    if E.Raw[EF_DEATH_TIMER] = 0 then
      E.Raw[EF_DEATH_TIMER] := T72_TRAIL_BLINK;

    Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);
    Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);

    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T72_V2_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      Inc(E.Raw[EF_FLAG1C]);
      if E.Raw[EF_FLAG1C] > T72_V2_FRAMES - 1 then
        World.DestroyEntity(E, False);
    end;
  end;
end;

procedure EntityUpdate_Type73_Boss_MidoriLizard(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, D, Slot, Hp: Integer;

  function SpawnChild(TypeId, Down: Integer): Integer;
  begin
    Result := World.Spawn(EKIND_MINOR, TypeId,
                          E.Raw[EF_POS_X] - POSITION_BIAS
                            - World.Layer.DeltaX - T73_CHILD_LEFT,
                          E.Raw[EF_POS_Y] - POSITION_BIAS
                            - World.Layer.DeltaY + Down);
    World.SetSpawnField(Result, EF_OWNER, E.Raw[EF_SLOT]);
  end;

begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame > High(T73_SPRITES)) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T73_SPRITES[Frame];

  if E.Raw[EF_STATE] = 0 then
  begin
    E.Raw[EF_STATE] := 1;
    Inc(E.Raw[EF_POS_X], T73_ENTRY_SHIFT);
    Inc(E.Raw[EF_POS_Y], T73_ENTRY_SHIFT);
  end;

  { BEFORE the dying check, so the dead pose shows on the same frame. }
  if E.Raw[EF_HP] = 0 then
    E.Raw[EF_FLAG1C] := T73_DEAD_FRAME;

  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;

  if E.Raw[EF_STATE] = 1 then
  begin
    { Half of the heading's X component, and one step a frame - a sway. }
    Inc(E.Raw[EF_POS_X], HalfExtent(DirVelX(E.Raw[EF_FACING])));
    E.Raw[EF_FACING] := (E.Raw[EF_FACING] + 1) mod DIR_COUNT;

    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T73_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T73_FRAMES;
    end;

    Inc(E.Raw[EF_CHILD_A]);
    Hp := E.Raw[EF_HP] div T73_HP_PACE_DIV;
    { Paced off its own health, like types 52 and 54. }
    if T73_WAIT[D] * Hp + T73_HP_PACE_ADD < E.Raw[EF_CHILD_A] then
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
    Slot := SpawnChild(T73_CHILD_ONE, T73_CHILD_DOWN_A);
    World.SetSpawnField(Slot, EF_STATE, 0);
  end;

  { State 3 is left by the type 75. }

  if E.Raw[EF_STATE] = 4 then
  begin
    E.Raw[EF_FLAG1C] := T73_DEAD_FRAME;
    Inc(E.Raw[EF_CHILD_A]);
    if T73_CHARGE[D] < E.Raw[EF_CHILD_A] then
    begin
      E.Raw[EF_STATE] := 5;
      E.Raw[EF_CHILD_A] := 0;
      World.PlaySound(T73_SND_CHARGE);
      SpawnChild(T73_CHILD_TWO, T73_CHILD_DOWN_B);
    end;
  end;

  { State 5 is left by the type 74 - see EntityUpdate_Type74. }

  if E.Raw[EF_STATE] = 6 then
  begin
    Inc(E.Raw[EF_CHILD_A]);
    if E.Raw[EF_CHILD_A] > T73_RECOVER then
    begin
      E.Raw[EF_STATE] := 7;
      E.Raw[EF_CHILD_A] := 0;
    end;
  end;

  if E.Raw[EF_STATE] = 7 then
  begin
    E.Raw[EF_STATE] := 8;
    E.Raw[EF_FLAG1C] := 0;
    Slot := SpawnChild(T73_CHILD_THREE, T73_CHILD_DOWN_A);
    World.SetSpawnField(Slot, EF_STATE, 1);
  end;

  { And state 8 is left by the type 35. }
end;

procedure EntityUpdate_Type74(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, D, Aim, I, N, Slot: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if E.Raw[EF_VARIANT] = 0 then
  begin
    if (Frame < 0) or (Frame >= T74_V0_FRAMES) then
      Frame := 0;
    E.Raw[EF_ANIM_ID] := T74_V0_SPRITES[Frame];
  end;
  if E.Raw[EF_VARIANT] = 1 then
  begin
    if (Frame < 0) or (Frame >= T74_V1_FRAMES) then
      Frame := 0;
    E.Raw[EF_ANIM_ID] := T74_V1_SPRITES[Frame];
  end;

  if EntityUpdateDying(E, AGameState, World) then
    Exit;
  if World.Pool = nil then
    Exit;

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;

  if E.Raw[EF_VARIANT] = 0 then
  begin
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T74_V0_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      Inc(E.Raw[EF_FLAG1C]);
      if E.Raw[EF_FLAG1C] > T74_V0_FRAMES - 1 then
      begin
        { Type 56's fan, rebuilt with type 56's numbers. }
        Aim := AngleBetween(E.Raw[EF_POS_X], E.Raw[EF_POS_Y],
                            World.Pool.Field(SLOT_SINGLE_FIRST, EF_POS_X),
                            World.Pool.Field(SLOT_SINGLE_FIRST, EF_POS_Y));
        Inc(Aim, T74_SKEW[D]);
        if Aim < 0 then
          Inc(Aim, DIR_COUNT);

        N := T74_COUNT[D];
        if N >= 0 then
          for I := 0 to N do
          begin
            Slot := World.Spawn(EKIND_MINOR, T74_SELF_TYPE,
                                E.Raw[EF_POS_X] - POSITION_BIAS
                                  - World.Layer.DeltaX,
                                E.Raw[EF_POS_Y] - POSITION_BIAS
                                  - World.Layer.DeltaY);
            World.SetSpawnField(Slot, EF_VARIANT, T74_SHOT_VARIANT);
            World.SetSpawnField(Slot, EF_VEL_X,
                                T74_SPEED[D] * DirVelX(Aim));
            World.SetSpawnField(Slot, EF_VEL_Y,
                                T74_SPEED[D] * DirVelY(Aim));
            if Aim + T74_FAN_STEP > DIR_COUNT - 1 then
              Aim := Aim - T74_FAN_WRAP
            else
              Inc(Aim, T74_FAN_STEP);
          end;

        { The write that lets type 73 leave state 5. }
        World.Pool.SetField(E.Raw[EF_OWNER], EF_STATE, T74_OWNER_STATE);
        World.DestroyEntity(E, False);
        Exit;
      end;
    end;
  end;

  if E.Raw[EF_VARIANT] = 1 then
  begin
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T74_V1_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T74_V1_FRAMES;
    end;
    Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);
    Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);
  end;
end;

procedure EntityUpdate_Type75(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T75_FRAMES) then
    Frame := 0;
  { One table, two directions - that is the whole open/close difference. }
  if E.Raw[EF_STATE] = T75_OPENING then
    E.Raw[EF_ANIM_ID] := T75_SPRITES[Frame];
  if E.Raw[EF_STATE] = T75_CLOSING then
    E.Raw[EF_ANIM_ID] := T75_SPRITES[T75_FRAMES - 1 - Frame];

  if EntityUpdateDying(E, AGameState, World) then
    Exit;
  if World.Pool = nil then
    Exit;

  { It dies with its parent. No other child checks this. }
  if World.Pool.Field(E.Raw[EF_OWNER], EF_HP) = 0 then
  begin
    World.DestroyEntity(E, False);
    Exit;
  end;

  Inc(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] > T75_TICKS then
  begin
    E.Raw[EF_BLOCK_B] := 0;
    Inc(E.Raw[EF_FLAG1C]);
    if E.Raw[EF_FLAG1C] > T75_FRAMES - 1 then
    begin
      if E.Raw[EF_STATE] = T75_OPENING then
      begin
        World.PlaySound(T75_SND_OPEN);
        World.Pool.SetField(E.Raw[EF_OWNER], EF_STATE, T75_OWNER_AFTER_OPEN);
      end;
      if E.Raw[EF_STATE] = T75_CLOSING then
        World.Pool.SetField(E.Raw[EF_OWNER], EF_STATE, T75_OWNER_AFTER_CLOSE);
      World.DestroyEntity(E, False);
    end;
  end;
end;

procedure EntityUpdate_Type76_SpikePress_Lev(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, D: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T76_FRAMES) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T76_SPRITES[Frame];

  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;

  if E.Raw[EF_STATE] = 0 then
  begin
    E.Raw[EF_STATE] := 1;
    Inc(E.Raw[EF_POS_X], T76_NUDGE);
  end;

  Inc(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] > T76_TICKS then
  begin
    E.Raw[EF_BLOCK_B] := 0;
    E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T76_FRAMES;
  end;

  Dec(E.Raw[EF_CHILD_A]);
  if E.Raw[EF_CHILD_A] < 1 then
  begin
    E.Raw[EF_CHILD_A] := T76_PERIOD[D];
    E.Raw[EF_VEL_X] := DirVelX(E.Raw[EF_FACING]) * T76_SPEED[D];
    E.Raw[EF_FACING] := (E.Raw[EF_FACING] + 1) mod DIR_COUNT;
    { On reaching 63, not on the wrap to 0 - see the T76_ block. }
    if E.Raw[EF_FACING] = T76_LAP_AT then
      World.PlaySound(T76_SND_LAP);
  end;

  Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);
end;

procedure EntityUpdate_Type77_Boss_Hero(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, Dir, Phase, D, Slot, I, N, Act, Speed: Integer;
  PlayerX: Integer;

  function Clamp(V, Hi: Integer): Integer;
  begin
    Result := V;
    if (Result < 0) or (Result > Hi) then
      Result := 0;
  end;

  { Every effect this boss makes is a type 79 carrying its slot. }
  function Part(Variant, DX, DY: Integer): Integer;
  begin
    Result := World.Spawn(EKIND_MINOR, T77_PART_B,
                          E.Raw[EF_POS_X] - POSITION_BIAS
                            - World.Layer.DeltaX + DX,
                          E.Raw[EF_POS_Y] - POSITION_BIAS
                            - World.Layer.DeltaY + DY);
    World.SetSpawnField(Result, EF_OWNER, E.Raw[EF_SLOT]);
    if Variant >= 0 then
      World.SetSpawnField(Result, EF_VARIANT, Variant);
  end;

  procedure BackToIdle;
  begin
    E.Raw[EF_STATE] := 1;
    E.Raw[EF_BLOCK_B] := 0;
    E.Raw[EF_FLAG1C] := 0;
  end;

begin
  Frame := E.Raw[EF_FLAG1C];
  Dir := Ord(E.Raw[EF_VEL_X] > 0);
  Phase := E.Raw[EF_BLOCK_A + 1];

  if Phase < 2 then
    E.Raw[EF_ANIM_ID] := T77_P01_SPRITES[Dir][Clamp(Frame, 9)];
  if Phase = 2 then
    E.Raw[EF_ANIM_ID] := T77_P2_SPRITES[Dir][Clamp(Frame, 13)];
  if Phase = 3 then
    E.Raw[EF_ANIM_ID] := T77_P3_SPRITES[Dir][Clamp(Frame, 12)];
  if Phase = 4 then
    E.Raw[EF_ANIM_ID] := T77_P4_SPRITES[Dir][Clamp(Frame, 5)];
  if Phase = 5 then
    E.Raw[EF_ANIM_ID] := T77_P5_SPRITES[Dir][Clamp(Frame, 7)];
  if Phase = 6 then
    E.Raw[EF_ANIM_ID] := T77_P6_SPRITES[Dir];

  if EntityUpdateDying(E, AGameState, World) then
    Exit;
  if World.Pool = nil then
    Exit;

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;
  PlayerX := World.Pool.Field(SLOT_SINGLE_FIRST, EF_POS_X);

  { --- the phase gate, before anything else --- }
  if (Phase >= 0) and (Phase < T77_PHASES)
     and (E.Raw[EF_HP] < T77_HP[D][Phase]) then
  begin
    { Phases 0 and 4 pass silently; the other four puff. }
    if (Phase <> 0) and (Phase <> 4) then
    begin
      Slot := World.Spawn(EKIND_MINOR, EMITTER_TYPE,
                          E.Raw[EF_POS_X] - POSITION_BIAS,
                          E.Raw[EF_POS_Y] - POSITION_BIAS - T77_PUFF_LIFT);
      World.SetSpawnField(Slot, EF_BLOCK_A + 1, 8);
      World.SetSpawnField(Slot, EF_BLOCK_A + 2, 2);
      World.SetSpawnField(Slot, EF_BLOCK_A + 3, 1);
      World.SetSpawnField(Slot, EF_BLOCK_A + 4, 2);
    end;
    E.Raw[EF_STATE] := 1;
    E.Raw[EF_BLOCK_B] := 0;
    E.Raw[EF_FLAG1C] := 0;
    Inc(E.Raw[EF_BLOCK_A + 1]);
    E.Raw[EF_CHILD_B] := 0;
    Phase := E.Raw[EF_BLOCK_A + 1];
    if Phase > T77_PHASES - 1 then
    begin
      E.Raw[EF_HP] := 0;
      Exit;
    end;
  end;

  if E.Raw[EF_STATE] = 0 then
  begin
    E.Raw[EF_STATE] := 1;
    E.Raw[EF_VEL_X] := T77_ENTRY_VX;
    Slot := World.Spawn(EKIND_MINOR, T77_PART_A,
                        E.Raw[EF_POS_X] - POSITION_BIAS - World.Layer.DeltaX,
                        E.Raw[EF_POS_Y] - POSITION_BIAS - World.Layer.DeltaY);
    World.SetSpawnField(Slot, EF_OWNER, E.Raw[EF_SLOT]);
    Part(-1, 0, 0);
  end;

  { --- state 1: run the script --- }
  if E.Raw[EF_STATE] = 1 then
  begin
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T77_IDLE_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod 2;
    end;

    Inc(E.Raw[EF_CHILD_A]);
    N := Clamp(E.Raw[EF_CHILD_B], T77_STEPS - 1);
    if T77_STEP[Clamp(Phase, T77_PHASES - 1)][N] div T77_DIVISOR[D]
       < E.Raw[EF_CHILD_A] then
    begin
      E.Raw[EF_CHILD_A] := 0;
      Act := T77_ACTION[Clamp(Phase, T77_PHASES - 1)][N];

      if Act = T77_ACT_FACE then
      begin
        E.Raw[EF_STATE] := 2;
        E.Raw[EF_BLOCK_B] := 0;
        E.Raw[EF_FLAG1C] := 1;
      end;
      if Act = T77_ACT_DASH then
      begin
        E.Raw[EF_STATE] := 3;
        E.Raw[EF_BLOCK_B] := 0;
        E.Raw[EF_FLAG1C] := 2;
      end;
      if Act = T77_ACT_SLAM then
      begin
        E.Raw[EF_STATE] := 4;
        E.Raw[EF_BLOCK_B] := 0;
        E.Raw[EF_FLAG1C] := 6;
      end;
      if Act = T77_ACT_SHOT then
      begin
        E.Raw[EF_STATE] := 5;
        E.Raw[EF_BLOCK_B] := 0;
        E.Raw[EF_FLAG1C] := 10;
        World.PlaySound(T77_SND_ROAR);
      end;
      if Act = T77_ACT_RECOIL then
      begin
        E.Raw[EF_STATE] := 6;
        E.Raw[EF_BLOCK_B] := 0;
        E.Raw[EF_FLAG1C] := 13;
        E.Raw[EF_VEL_X] := -E.Raw[EF_VEL_X];
      end;
      if Act = T77_ACT_DASH_BACK then
      begin
        { the same state as action 3, entered facing the other way }
        E.Raw[EF_STATE] := 3;
        E.Raw[EF_BLOCK_B] := 0;
        E.Raw[EF_FLAG1C] := 2;
        E.Raw[EF_VEL_X] := -E.Raw[EF_VEL_X];
      end;
      if Act = T77_ACT_POSE then
      begin
        E.Raw[EF_STATE] := 8;
        E.Raw[EF_BLOCK_B] := 0;
        E.Raw[EF_SHOTS] := $1E;
        E.Raw[EF_FLAG1C] := 6;
        World.PlaySound(T77_SND_ROAR);
        Part(5, -$100, -$400);
      end;

      Inc(E.Raw[EF_CHILD_B]);
      if E.Raw[EF_CHILD_B] > T77_STEPS - 1 then
        E.Raw[EF_CHILD_B] := 0;
    end;
  end;

  { --- state 2: face the player and hold --- }
  if E.Raw[EF_STATE] = 2 then
  begin
    { CompareNZ, not Compare - a zero would leave it with no facing. }
    E.Raw[EF_VEL_X] := CompareNZ(E.Raw[EF_POS_X], PlayerX) * T77_TURN_SPEED;
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T77_TURN_HOLD then
      BackToIdle;
  end;

  { --- states 3 and 7: the dash, trailing as it goes --- }
  if (E.Raw[EF_STATE] = 3) or (E.Raw[EF_STATE] = 7) then
  begin
    Inc(E.Raw[EF_BLOCK_B]);
    { The trail thins as it slows: the interval is 8 - 2 * its speed in
      pixels, so a fast dash drops one almost every frame. }
    Speed := Abs(E.Raw[EF_VEL_X]);
    if Speed < 0 then
      Inc(Speed, 31);
    if (Speed shr POSITION_SHIFT) * -2 + 8 < E.Raw[EF_BLOCK_B] then
    begin
      Part(4, E.Raw[EF_VEL_X] * -4, $100);
      E.Raw[EF_BLOCK_B] := 0;
      Inc(E.Raw[EF_FLAG1C]);
      if E.Raw[EF_FLAG1C] > 5 then
        E.Raw[EF_FLAG1C] := 2;
    end;

    ApproachZero(E.Raw[EF_VEL_X], T77_DASH_FRICTION);
    if World.TileAtX(E, E.Raw[EF_VEL_X], False) >= World.SolidThreshold then
      E.Raw[EF_VEL_X] := -E.Raw[EF_VEL_X];
    Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);

    if E.Raw[EF_VEL_X] = 0 then
    begin
      BackToIdle;
      { and it comes to rest facing you, at speed 1 }
      E.Raw[EF_VEL_X] := CompareNZ(E.Raw[EF_POS_X], PlayerX);
    end;
  end;

  { --- state 4: the ground slam --- }
  if E.Raw[EF_STATE] = 4 then
  begin
    Inc(E.Raw[EF_BLOCK_B]);
    if T77_SLAM[Clamp(E.Raw[EF_FLAG1C] - 6, 3)] div T77_SLAM_DIV[D]
       < E.Raw[EF_BLOCK_B] then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      Inc(E.Raw[EF_FLAG1C]);

      if (E.Raw[EF_FLAG1C] = 7) or (E.Raw[EF_FLAG1C] = 9) then
        World.PlaySound(T77_SND_SLAM);

      if E.Raw[EF_FLAG1C] = 9 then
      begin
        Part(1, 0, 0);
        N := T77_BURST[D];
        if N >= 0 then
          for I := 0 to N do
          begin
            Slot := World.Spawn(EKIND_MINOR, T77_BURST_TYPE,
                                CompareNZ(0, E.Raw[EF_VEL_X]) * $1000
                                  + E.Raw[EF_POS_X] - POSITION_BIAS
                                  - World.Layer.DeltaX,
                                E.Raw[EF_POS_Y] - POSITION_BIAS
                                  - World.Layer.DeltaY + $200);
            World.SetSpawnField(Slot, EF_VEL_X,
                                T77_BURST_VX[I] shl T77_BURST_SHIFT);
            World.SetSpawnField(Slot, EF_VEL_Y,
                                T77_BURST_VY[I] shl T77_BURST_SHIFT);
          end;
        { The only place in the game that starts the screen shake. }
        ScreenShakeOn := True;
        ScreenShakeTimer := T77_SHAKE_FRAMES;
      end;

      if E.Raw[EF_FLAG1C] = 8 then
        Part(2, 0, 0);

      if E.Raw[EF_FLAG1C] > 9 then
        BackToIdle;
    end;
  end;

  { --- state 5: the lob --- }
  if E.Raw[EF_STATE] = 5 then
  begin
    Inc(E.Raw[EF_BLOCK_B]);
    if T77_SHOT[Clamp(E.Raw[EF_FLAG1C] - 10, 2)] div T77_SHOT_DIV[D]
       < E.Raw[EF_BLOCK_B] then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      if E.Raw[EF_FLAG1C] = $B then
      begin
        World.PlaySound(T77_SND_LOB);
        Part(1, 0, 0);
        Slot := Part(3, CompareNZ(0, E.Raw[EF_VEL_X]) * $800, -$400);
        World.SetSpawnField(Slot, EF_VEL_X,
                            CompareNZ(0, E.Raw[EF_VEL_X]) * $20
                            * T77_LOB_SPEED[D]);
      end;
      Inc(E.Raw[EF_FLAG1C]);
      if E.Raw[EF_FLAG1C] > $C then
        BackToIdle;
    end;
  end;

  { --- state 6: the recoil, action 3's move at twice the friction --- }
  if E.Raw[EF_STATE] = 6 then
  begin
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > 2 then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      Part(4, E.Raw[EF_VEL_X] * -8, $100);
    end;

    ApproachZero(E.Raw[EF_VEL_X], T77_RECOIL_FRICTION);
    if World.TileAtX(E, E.Raw[EF_VEL_X], False) >= World.SolidThreshold then
      E.Raw[EF_VEL_X] := -E.Raw[EF_VEL_X];
    Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);

    if E.Raw[EF_VEL_X] = 0 then
    begin
      BackToIdle;
      E.Raw[EF_VEL_X] := CompareNZ(E.Raw[EF_POS_X], PlayerX);
    end;
  end;

  { --- state 8: a two-frame hold, and nothing leaves it --- }
  if E.Raw[EF_STATE] = 8 then
  begin
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T77_HELD_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      Inc(E.Raw[EF_FLAG1C]);
      if E.Raw[EF_FLAG1C] > T77_HELD_LAST then
        E.Raw[EF_FLAG1C] := T77_HELD_FIRST;
    end;
  end;
end;

procedure EntityUpdate_Type78(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Owner, Dir, OwnerState, OwnerFrame, F: Integer;

  function Clamp(V, Hi: Integer): Integer;
  begin
    Result := V;
    if (Result < 0) or (Result > Hi) then
      Result := 0;
  end;

begin
  if World.Pool = nil then
    Exit;
  Owner := E.Raw[EF_OWNER];
  Dir := Ord(World.Pool.Field(Owner, EF_VEL_X) > 0);
  OwnerState := World.Pool.Field(Owner, EF_STATE);
  OwnerFrame := World.Pool.Field(Owner, EF_FLAG1C);

  { The slam and the lob place it AND set its sprite, before the dying
    check; the idle placement happens after. That order is the original's. }
  if OwnerState = 4 then
  begin
    E.Raw[EF_TOUCH_KIND] := 1;
    E.Raw[EF_FLAG1C] := OwnerFrame - 6;
    F := Clamp(E.Raw[EF_FLAG1C], 3);
    E.Raw[EF_POS_X] := T78_SLAM_X[Dir][F] * T78_OFFSET_SCALE
                       + World.Pool.Field(Owner, EF_POS_X);
    E.Raw[EF_POS_Y] := T78_SLAM_Y[F] * T78_OFFSET_SCALE
                       + World.Pool.Field(Owner, EF_POS_Y);
  end;
  if OwnerState = 5 then
  begin
    { Harmless for the whole of the lob - the one safe window. }
    E.Raw[EF_TOUCH_KIND] := 0;
    E.Raw[EF_FLAG1C] := OwnerFrame - 10;
    F := Clamp(E.Raw[EF_FLAG1C], 2);
    E.Raw[EF_POS_X] := T78_LOB_X[Dir][F] * T78_OFFSET_SCALE
                       + World.Pool.Field(Owner, EF_POS_X);
    E.Raw[EF_POS_Y] := T78_LOB_Y[F] * T78_OFFSET_SCALE
                       + World.Pool.Field(Owner, EF_POS_Y);
  end;

  if (OwnerState >= 1) and (OwnerState <= 3) or (OwnerState = 6) then
    E.Raw[EF_ANIM_ID] := T78_IDLE_SPRITES[Dir];
  if OwnerState = 4 then
    E.Raw[EF_ANIM_ID] := T78_SLAM_SPRITES[Dir][Clamp(E.Raw[EF_FLAG1C], 3)];
  if OwnerState = 5 then
    E.Raw[EF_ANIM_ID] := T78_LOB_SPRITES[Dir][Clamp(E.Raw[EF_FLAG1C], 2)];

  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  if (OwnerState >= 1) and (OwnerState <= 3) or (OwnerState = 6) then
  begin
    E.Raw[EF_TOUCH_KIND] := 1;
    E.Raw[EF_POS_X] := T78_IDLE_X[Dir] * T78_OFFSET_SCALE
                       + World.Pool.Field(Owner, EF_POS_X);
    { Frames 0, 3 and 5 sit higher. They belong to two different
      animations, which is why the list is not a range. }
    if (OwnerFrame = 0) or (OwnerFrame = 3) or (OwnerFrame = 5) then
      E.Raw[EF_POS_Y] := World.Pool.Field(Owner, EF_POS_Y) + T78_IDLE_HIGH
    else
      E.Raw[EF_POS_Y] := World.Pool.Field(Owner, EF_POS_Y) + T78_IDLE_LOW;
  end;

  { The boss sheds this half when it reaches its last phase. }
  if World.Pool.Field(Owner, EF_BLOCK_A + 1) = T78_LEAVES_AT_PHASE then
    E.Raw[EF_HP] := 0;
end;

procedure EntityUpdate_Type79(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Owner, Dir, Frame, Slot, OwnerFrame: Integer;

  function Clamp(V, Hi: Integer): Integer;
  begin
    Result := V;
    if (Result < 0) or (Result > Hi) then
      Result := 0;
  end;

begin
  if EntityUpdateDying(E, AGameState, World) then
    Exit;
  if World.Pool = nil then
    Exit;

  Owner := E.Raw[EF_OWNER];
  { Everything it emits dies with it. }
  if World.Pool.Field(Owner, EF_HP) = 0 then
    E.Raw[EF_HP] := 0;
  Dir := Ord(World.Pool.Field(Owner, EF_VEL_X) > 0);
  Frame := E.Raw[EF_FLAG1C];

  if E.Raw[EF_VARIANT] = 0 then
    E.Raw[EF_ANIM_ID] := T79_V0_SPRITES[Dir];
  if E.Raw[EF_VARIANT] = 1 then
    E.Raw[EF_ANIM_ID] := T79_V1_SPRITES[Dir];
  if E.Raw[EF_VARIANT] = 2 then
    E.Raw[EF_ANIM_ID] := T79_V2_SPRITES[Dir];
  if (E.Raw[EF_VARIANT] = 3) and (E.Raw[EF_VEL_X] > 0) then
    E.Raw[EF_ANIM_ID] := T79_V3_SPRITES[0][Clamp(Frame, 1)];
  if (E.Raw[EF_VARIANT] = 3) and (E.Raw[EF_VEL_X] < 0) then
    E.Raw[EF_ANIM_ID] := T79_V3_SPRITES[1][Clamp(Frame, 1)];
  if E.Raw[EF_VARIANT] = 4 then
    E.Raw[EF_ANIM_ID] := T79_V4_SPRITES[Clamp(Frame, T79_V4_FRAMES - 1)];
  if E.Raw[EF_VARIANT] = 5 then
    E.Raw[EF_ANIM_ID] := T79_V5_SPRITES[Clamp(Frame, T79_SUMMON_LAST)];

  if E.Raw[EF_VARIANT] = 0 then
  begin
    E.Raw[EF_POS_X] := T79_V0_X[Dir] * T78_OFFSET_SCALE
                       + World.Pool.Field(Owner, EF_POS_X);
    OwnerFrame := World.Pool.Field(Owner, EF_FLAG1C);
    if (OwnerFrame = 1) or (OwnerFrame = 2) or (OwnerFrame = 4) then
      E.Raw[EF_POS_Y] := World.Pool.Field(Owner, EF_POS_Y) + T79_V0_HIGH
    else
      E.Raw[EF_POS_Y] := World.Pool.Field(Owner, EF_POS_Y) + T79_V0_LOW;
    { and this piece goes four phases before type 78 does }
    if World.Pool.Field(Owner, EF_BLOCK_A + 1) = T79_V0_LEAVES_AT_PHASE then
      E.Raw[EF_HP] := 0;
  end;

  if E.Raw[EF_VARIANT] = 1 then
  begin
    E.Raw[EF_TOUCH_KIND] := 0;
    if E.Raw[EF_DEATH_TIMER] = 0 then
      E.Raw[EF_DEATH_TIMER] := 2;
    E.Raw[EF_POS_X] := T79_V1_X[Dir] * T78_OFFSET_SCALE
                       + World.Pool.Field(Owner, EF_POS_X);
    E.Raw[EF_POS_Y] := T79_V1_Y[0] * T78_OFFSET_SCALE
                       + World.Pool.Field(Owner, EF_POS_Y);
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T79_V1_LIFE then
    begin
      World.DestroyEntity(E, False);
      Exit;
    end;
  end;

  if E.Raw[EF_VARIANT] = 2 then
  begin
    E.Raw[EF_TOUCH_KIND] := 0;
    if E.Raw[EF_DEATH_TIMER] = 0 then
      E.Raw[EF_DEATH_TIMER] := 2;
    E.Raw[EF_POS_X] := T79_V2_X[Dir] * T78_OFFSET_SCALE
                       + World.Pool.Field(Owner, EF_POS_X);
    E.Raw[EF_POS_Y] := T79_V2_Y[0] * T78_OFFSET_SCALE
                       + World.Pool.Field(Owner, EF_POS_Y);
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T79_V2_LIFE then
    begin
      World.DestroyEntity(E, False);
      Exit;
    end;
  end;

  if E.Raw[EF_VARIANT] = 3 then
  begin
    Inc(E.Raw[EF_CHILD_A]);
    if E.Raw[EF_CHILD_A] > T79_LOB_SND_EVERY then
    begin
      E.Raw[EF_CHILD_A] := 0;
      World.PlaySound(T79_SND_LOB);
    end;

    if World.TileAtX(E, E.Raw[EF_VEL_X], False) >= World.SolidThreshold then
    begin
      E.Raw[EF_VEL_X] := 0;
      E.Raw[EF_DEATH_TIMER] := T79_LOB_FUSE;
    end;
    Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);

    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > 2 then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod 2;
    end;

    Inc(E.Raw[EF_CHILD_B]);
    if (E.Raw[EF_CHILD_B] > T79_LOB_LIFE) and (E.Raw[EF_DEATH_TIMER] = 0) then
      E.Raw[EF_DEATH_TIMER] := T79_LOB_FUSE;
    { At ONE, not zero: Entity_UpdateAll ticks the timer after this runs. }
    if E.Raw[EF_DEATH_TIMER] = 1 then
    begin
      World.DestroyEntity(E, False);
      Exit;
    end;
  end;

  if E.Raw[EF_VARIANT] = 4 then
  begin
    E.Raw[EF_TOUCH_KIND] := 0;
    E.Raw[EF_VULN_KIND] := 0;
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > 2 then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      Inc(E.Raw[EF_FLAG1C]);
      if E.Raw[EF_FLAG1C] > T79_V4_FRAMES - 1 then
      begin
        World.DestroyEntity(E, False);
        Exit;
      end;
    end;
  end;

  if E.Raw[EF_VARIANT] = 5 then
  begin
    E.Raw[EF_TOUCH_KIND] := 0;

    if E.Raw[EF_STATE] = 0 then
    begin
      Inc(E.Raw[EF_BLOCK_B]);
      if E.Raw[EF_BLOCK_B] > 2 then
      begin
        E.Raw[EF_BLOCK_B] := 0;
        E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod 2;
      end;
      Inc(E.Raw[EF_CHILD_A]);
      if E.Raw[EF_CHILD_A] > T79_SUMMON_WAIT then
      begin
        E.Raw[EF_STATE] := 1;
        E.Raw[EF_CHILD_A] := 0;
        E.Raw[EF_FLAG1C] := 0;
      end;
    end;

    if E.Raw[EF_STATE] = 1 then
    begin
      Inc(E.Raw[EF_BLOCK_B]);
      if E.Raw[EF_BLOCK_B] > 2 then
      begin
        E.Raw[EF_BLOCK_B] := 0;
        Inc(E.Raw[EF_FLAG1C]);
        if E.Raw[EF_FLAG1C] > T79_SUMMON_LAST then
        begin
          Inc(E.Raw[EF_CHILD_B]);
          if E.Raw[EF_CHILD_B] < T79_SUMMONS then
          begin
            E.Raw[EF_STATE] := 0;
            E.Raw[EF_FLAG1C] := 0;
            Slot := World.Spawn(EKIND_MINOR, T79_FLYER_TYPE,
                                E.Raw[EF_POS_X] - POSITION_BIAS
                                  - World.Layer.DeltaX,
                                E.Raw[EF_POS_Y] - POSITION_BIAS
                                  - World.Layer.DeltaY);
            World.SetSpawnField(Slot, EF_OWNER, E.Raw[EF_SLOT]);
            World.SetSpawnField(Slot, EF_VARIANT, T79_FLYER_VARIANT);
            World.SetSpawnField(Slot, EF_FACING,
              AngleBetween(E.Raw[EF_POS_X], E.Raw[EF_POS_Y],
                           World.Pool.Field(SLOT_SINGLE_FIRST, EF_POS_X),
                           World.Pool.Field(SLOT_SINGLE_FIRST, EF_POS_Y)));
            World.PlaySound(T79_SND_SUMMON);
          end
          else
          begin
            { The fourth pass hands the boss back its idle state. }
            World.Pool.SetField(Owner, EF_STATE, 1);
            World.Pool.SetField(Owner, EF_BLOCK_B, 0);
            World.Pool.SetField(Owner, EF_FLAG1C, 0);
            World.DestroyEntity(E, False);
          end;
        end;
      end;
    end;
  end;
end;

procedure EntityUpdate_Type80_Fx_ArenaEmber(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if E.Raw[EF_VARIANT] = 0 then
  begin
    if (Frame < 0) or (Frame >= T80_V0_FRAMES) then
      Frame := 0;
    E.Raw[EF_ANIM_ID] := T80_V0_SPRITES[Frame];
  end;
  if E.Raw[EF_VARIANT] = 1 then
  begin
    if (Frame < 0) or (Frame >= T80_V1_FRAMES) then
      Frame := 0;
    E.Raw[EF_ANIM_ID] := T80_V1_SPRITES[Frame];
  end;

  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  { Shared by both variants - and variant 1 adds a second one below, which
    is why it runs at more than twice variant 0's rate. }
  Inc(E.Raw[EF_BLOCK_B]);

  if E.Raw[EF_VARIANT] = 0 then
  begin
    if E.Raw[EF_STATE] = 0 then
      E.Raw[EF_STATE] := 1;
    if E.Raw[EF_BLOCK_B] > T80_V0_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T80_V0_FRAMES;
    end;
  end;

  if E.Raw[EF_VARIANT] = 1 then
  begin
    if E.Raw[EF_DEATH_TIMER] = 0 then
      E.Raw[EF_DEATH_TIMER] := T80_V1_BLINK;
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T80_V1_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T80_V1_FRAMES;
    end;
  end;
end;

procedure EntityUpdate_Type58_Mon_NiseMana(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame > High(T58_SPRITES)) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T58_SPRITES[Frame];

  { BEFORE the dying check, not after - so one killed on its first frame
    still takes the drop. }
  if E.Raw[EF_STATE] = 0 then
  begin
    E.Raw[EF_STATE] := 1;
    E.Raw[EF_FLAG1C] := T58_SLEEP_FRAME;
    Inc(E.Raw[EF_POS_Y], T58_SETTLE);
  end;

  if EntityUpdateDying(E, AGameState, World) then
    Exit;
  if World.Pool = nil then
    Exit;

  if EntitiesOverlap(E, World.Pool.Entity(SLOT_SINGLE_FIRST)^,
                     T58_TRIGGER_SCALE, T58_TRIGGER_SCALE)
     and (E.Raw[EF_STATE] = 1) then
  begin
    World.PlaySound(T58_SND_WAKE);
    E.Raw[EF_STATE] := 2;
    E.Raw[EF_FLAG1C] := 0;
    Inc(E.Raw[EF_POS_Y], T58_RISE);
  end;

  if E.Raw[EF_STATE] = 2 then
  begin
    { A full turn sums to zero, so this wobbles rather than travels. }
    Inc(E.Raw[EF_POS_X], DirVelX(E.Raw[EF_FACING]));
    E.Raw[EF_FACING] := (E.Raw[EF_FACING] + 1) mod DIR_COUNT;

    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T58_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T58_FRAMES;
    end;
  end;
end;

procedure EntityUpdate_Type60_Mon_Golem(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, D, Slot, PlayerX: Integer;
begin
  Frame := E.Raw[EF_VARIANT] + E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame > High(T60_SPRITES[0])) then
    Frame := 0;
  { By the SIGN, two ifs and no else. }
  if E.Raw[EF_VEL_X] < 0 then
    E.Raw[EF_ANIM_ID] := T60_SPRITES[0][Frame];
  if E.Raw[EF_VEL_X] > 0 then
    E.Raw[EF_ANIM_ID] := T60_SPRITES[1][Frame];

  if EntityUpdateDying(E, AGameState, World) then
    Exit;
  if World.Pool = nil then
    Exit;

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;
  PlayerX := World.Pool.Field(SLOT_SINGLE_FIRST, EF_POS_X);

  if E.Raw[EF_STATE] = 0 then
  begin
    E.Raw[EF_STATE] := 1;
    Inc(E.Raw[EF_POS_Y], T60_SETTLE);
    E.Raw[EF_VEL_X] := T60_SPEED[D] shl T60_SPEED_SHIFT;
  end;

  if E.Raw[EF_STATE] = 1 then
  begin
    Inc(E.Raw[EF_CHILD_A]);
    if E.Raw[EF_CHILD_A] > T60_TURN[D] then
    begin
      E.Raw[EF_CHILD_A] := 0;
      E.Raw[EF_VEL_X] := Compare(E.Raw[EF_POS_X], PlayerX)
                         * (1 shl T60_SPEED_SHIFT) * T60_SPEED[D];
      if E.Raw[EF_VEL_X] = 0 then
        E.Raw[EF_VEL_X] := T60_SPEED[D] shl T60_SPEED_SHIFT;
    end;
  end;

  if (E.Raw[EF_HP] < T60_RAGE_BELOW) and (E.Raw[EF_STATE] = 1) then
  begin
    E.Raw[EF_STATE] := 2;
    { A write, not a clamp - 10 becomes 3 and 1 becomes 3. }
    E.Raw[EF_HP] := T60_RAGE_HP;
    E.Raw[EF_VARIANT] := T60_RAGE_VARIANT;
    E.Raw[EF_VEL_X] := Compare(E.Raw[EF_POS_X], PlayerX)
                       * (1 shl T60_SPEED_SHIFT) * T60_RAGE[D];
    if E.Raw[EF_VEL_X] = 0 then
      E.Raw[EF_VEL_X] := T60_RAGE[D] shl T60_SPEED_SHIFT;

    { The small death's emitter, with its four parameters, used as a puff. }
    Slot := World.Spawn(EKIND_MINOR, EMITTER_TYPE,
                        E.Raw[EF_POS_X] - POSITION_BIAS,
                        E.Raw[EF_POS_Y] - POSITION_BIAS - T60_PUFF_LIFT);
    World.SetSpawnField(Slot, EF_BLOCK_A + 1, 8);
    World.SetSpawnField(Slot, EF_BLOCK_A + 2, 2);
    World.SetSpawnField(Slot, EF_BLOCK_A + 3, 1);
    World.SetSpawnField(Slot, EF_BLOCK_A + 4, 2);
  end;

  Dec(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] < 1 then
  begin
    { 12 frames while calm, 6 once enraged. }
    E.Raw[EF_BLOCK_B] := (E.Raw[EF_STATE] - 1) * T60_ANIM_STEP + T60_ANIM_BASE;
    E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T60_FRAMES;
  end;

  { A wall ahead, or no floor one tile down - either turns it round. }
  if (World.TileAtX(E, E.Raw[EF_VEL_X], False) >= World.SolidThreshold)
     or (World.TileAtX(E, E.Raw[EF_VEL_X], False, T60_LEDGE_PROBE)
         < World.SolidThreshold) then
    E.Raw[EF_VEL_X] := -E.Raw[EF_VEL_X];
  Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);
end;

procedure EntityUpdate_Type59_Mon_RedEye(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, D, Dist: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame > High(T59_SPRITES)) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T59_SPRITES[Frame];

  if EntityUpdateDying(E, AGameState, World) then
    Exit;
  if World.Pool = nil then
    Exit;

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;

  if E.Raw[EF_STATE] = 0 then
    E.Raw[EF_STATE] := 1;

  if E.Raw[EF_STATE] = 1 then
  begin
    Dist := Abs(E.Raw[EF_POS_X]
                - World.Pool.Field(SLOT_SINGLE_FIRST, EF_POS_X));
    if Dist < 0 then
      Inc(Dist, 31);
    { A bare 0x50 - the only proximity test that is not difficulty-keyed. }
    if (Dist shr POSITION_SHIFT) < T59_WAKE_RANGE then
    begin
      E.Raw[EF_STATE] := 2;
      World.SpawnDebris(E, 0);
      E.Raw[EF_VEL_Y] := T59_RISE_VY;
    end;
  end;

  if E.Raw[EF_STATE] = 2 then
  begin
    E.Raw[EF_FLAG1C] := T59_RISE_FRAME;
    Inc(E.Raw[EF_VEL_Y], T59_GRAVITY);
    Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);
    { Leaves at the APEX - when the velocity turns positive - not on a timer. }
    if E.Raw[EF_VEL_Y] > 0 then
    begin
      E.Raw[EF_STATE] := 3;
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_FLAG1C] := T59_HANG_FRAME;
      E.Raw[EF_VEL_Y] := 0;
    end;
  end;

  if E.Raw[EF_STATE] = 3 then
  begin
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T59_HANG_TICKS then
    begin
      E.Raw[EF_STATE] := 4;
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_FLAG1C] := T59_HANG_FRAME;
      { ONCE, here, and never again - it cannot correct after this. }
      E.Raw[EF_FACING] :=
        AngleBetween(E.Raw[EF_POS_X], E.Raw[EF_POS_Y],
                     World.Pool.Field(SLOT_SINGLE_FIRST, EF_POS_X),
                     World.Pool.Field(SLOT_SINGLE_FIRST, EF_POS_Y));
    end;
  end;

  if E.Raw[EF_STATE] = 4 then
  begin
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T59_FLY_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      Inc(E.Raw[EF_FLAG1C]);
      if E.Raw[EF_FLAG1C] > T59_FLY_LAST then
        E.Raw[EF_FLAG1C] := T59_FLY_FIRST;
    end;
    Inc(E.Raw[EF_POS_X], DirVelX(E.Raw[EF_FACING]) * T59_SPEED[D]);
    Inc(E.Raw[EF_POS_Y], DirVelY(E.Raw[EF_FACING]) * T59_SPEED[D]);
  end;
end;

procedure EntityUpdate_Type56_Mon_AkaiKinoko(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, D, Aim, I, N, Slot: Integer;
  Player: PEntity;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T56_FRAMES) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T56_SPRITES[Frame];

  if EntityUpdateDying(E, AGameState, World) then
    Exit;
  if World.Pool = nil then
    Exit;

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;
  Player := World.Pool.Entity(SLOT_SINGLE_FIRST);

  { EF_TIMER is the fuse and Entity_UpdateAll counts it down. }
  if E.Raw[EF_TIMER] = 0 then
    E.Raw[EF_STATE] := 0;

  if (E.Raw[EF_STATE] = 0) and (E.Raw[EF_TIMER] <> 0) then
  begin
    E.Raw[EF_STATE] := 1;
    Inc(E.Raw[EF_FLAG1C]);
    if E.Raw[EF_FLAG1C] > T56_FRAMES - 1 then
    begin
      E.Raw[EF_FLAG1C] := T56_FRAMES - 1;
      E.Raw[EF_HP] := 0;

      { Aim, then SKEW it - harder settings lead the shot. }
      Aim := AngleBetween(E.Raw[EF_POS_X], E.Raw[EF_POS_Y],
                          Player^.Raw[EF_POS_X], Player^.Raw[EF_POS_Y]);
      Inc(Aim, T56_SKEW[D]);
      if Aim < 0 then
        Inc(Aim, DIR_COUNT);

      N := T56_COUNT[D];
      if N >= 0 then
        for I := 0 to N do
        begin
          Slot := World.Spawn(EKIND_MINOR, T56_SHOT_TYPE,
                              E.Raw[EF_POS_X] - POSITION_BIAS,
                              E.Raw[EF_POS_Y] - POSITION_BIAS);
          World.SetSpawnField(Slot, EF_VARIANT, 0);
          World.SetSpawnField(Slot, EF_VEL_X, T56_SPEED[D] * DirVelX(Aim));
          World.SetSpawnField(Slot, EF_VEL_Y, T56_SPEED[D] * DirVelY(Aim));
          { The shots are hurtable themselves. }
          World.SetSpawnField(Slot, EF_VULN_KIND, 1);

          { `next := aim + 4; if next > 63 then next := aim - 60`, which is
            (aim + 4) mod 64 for every aim in range - see the T56_ block. }
          if Aim + T56_FAN_STEP > DIR_COUNT - 1 then
            Aim := Aim - T56_FAN_WRAP
          else
            Inc(Aim, T56_FAN_STEP);
        end;
    end;
  end;

  if EntitiesOverlap(E, Player^, T56_TRIGGER_SCALE_X, T56_TRIGGER_SCALE_Y)
     and (E.Raw[EF_TIMER] = 0) then
    E.Raw[EF_TIMER] := T56_FUSE;
end;

procedure EntityUpdate_Type51_Mon_Ghost(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T51_FRAMES) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T51_SPRITES[Frame];

  { Topped back up whenever it reaches zero, so it blinks continuously - the
    same thing types 11 and 28 do with this field. }
  if E.Raw[EF_DEATH_TIMER] = 0 then
    E.Raw[EF_DEATH_TIMER] := T51_DEATH_TIMER;

  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  Inc(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] > T51_TICKS then
  begin
    E.Raw[EF_BLOCK_B] := 0;
    E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T51_FRAMES;
  end;

  if World.Pool <> nil then
    World.Pool.Steer(E.Raw[EF_SLOT], T51_TURN_TIMER, T51_TURN_RELOAD);
  Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);
  Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);
end;

procedure EntityUpdate_Type53(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T53_ROW) then
    Frame := 0;
  { By the SIGN, two ifs and no else - a stationary one keeps its sprite. }
  if E.Raw[EF_VEL_X] < 0 then
    E.Raw[EF_ANIM_ID] := T53_SPRITES[0][Frame];
  if E.Raw[EF_VEL_X] > 0 then
    E.Raw[EF_ANIM_ID] := T53_SPRITES[1][Frame];

  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  if E.Raw[EF_STATE] = 0 then
  begin
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T53_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      Inc(E.Raw[EF_FLAG1C]);
      if E.Raw[EF_FLAG1C] > T53_WIND_LAST then
      begin
        World.PlaySound(T53_CHARGE_SOUND);
        E.Raw[EF_STATE] := 1;
        E.Raw[EF_FLAG1C] := T53_RUN_FIRST;
      end;
    end;
  end;

  if E.Raw[EF_STATE] = 1 then
  begin
    Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T53_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      Inc(E.Raw[EF_FLAG1C]);
      if E.Raw[EF_FLAG1C] > T53_RUN_LAST then
        E.Raw[EF_FLAG1C] := T53_RUN_FIRST;
    end;
  end;
end;

procedure EntityUpdate_Type50_Mon_Turtle(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, D, Slot: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame > High(T50_SPRITES)) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T50_SPRITES[Frame];

  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;

  if E.Raw[EF_STATE] = 0 then
  begin
    E.Raw[EF_STATE] := 1;
    { The only handler that weakens ITSELF on easy. }
    if D = 0 then
      Inc(E.Raw[EF_HP], T50_EASY_HP_PENALTY);
  end;

  if E.Raw[EF_STATE] = 1 then
  begin
    Dec(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] < 1 then
    begin
      E.Raw[EF_BLOCK_B] := T50_TICKS;
      E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T50_FRAMES;
    end;

    Inc(E.Raw[EF_CHILD_A]);
    if E.Raw[EF_CHILD_A] > E.Raw[EF_BLOCK_A + 1] then
    begin
      E.Raw[EF_CHILD_A] := 0;
      E.Raw[EF_FACING] := -E.Raw[EF_FACING];
    end;
    Inc(E.Raw[EF_POS_X], E.Raw[EF_FACING]);

    Inc(E.Raw[EF_CHILD_B]);
    if E.Raw[EF_CHILD_B] > T50_PATROL[D] then
    begin
      E.Raw[EF_STATE] := 2;
      E.Raw[EF_FLAG1C] := T50_OPEN_FIRST;
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_CHILD_B] := 0;
      E.Raw[EF_SHOTS] := 0;
    end;
  end;

  if (E.Raw[EF_STATE] = 2) and (not IsOffScreen(E, T50_OFFSCREEN_MARGIN)) then
  begin
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T50_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      Inc(E.Raw[EF_FLAG1C]);
      if E.Raw[EF_FLAG1C] > T50_OPEN_LAST then
      begin
        E.Raw[EF_FLAG1C] := T50_OPEN_LAST;
        E.Raw[EF_STATE] := 3;
        { Open, and hurtable differently while it is. }
        E.Raw[EF_VULN_KIND] := T50_VULN_OPEN;
        Slot := World.Spawn(EKIND_MINOR, T50_SHOT_TYPE,
                            E.Raw[EF_POS_X] - POSITION_BIAS
                              - World.Layer.DeltaX,
                            E.Raw[EF_POS_Y] - POSITION_BIAS
                              - World.Layer.DeltaY);
        World.SetSpawnField(Slot, EF_OWNER, E.Raw[EF_SLOT]);
        World.SetSpawnField(Slot, EF_VEL_X,
                            E.Raw[EF_FACING] * T50_SHOT_SPEED);
      end;
    end;
  end;

  { State 3 is a hold - the type-39 shot moves it to 5. }

  if E.Raw[EF_STATE] = 5 then
  begin
    Inc(E.Raw[EF_CHILD_B]);
    if E.Raw[EF_CHILD_B] > T50_HOLD[D] then
    begin
      E.Raw[EF_STATE] := 6;
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_CHILD_B] := 0;
      E.Raw[EF_VULN_KIND] := T50_VULN_CLOSING;
    end;
  end;

  if E.Raw[EF_STATE] = 6 then
  begin
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T50_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      Dec(E.Raw[EF_FLAG1C]);
      if E.Raw[EF_FLAG1C] < T50_OPEN_FIRST then
      begin
        E.Raw[EF_FLAG1C] := 0;
        E.Raw[EF_STATE] := 1;
        E.Raw[EF_BLOCK_B] := 0;
      end;
    end;
  end;
end;

procedure EntityUpdate_Type49_Mon_Water(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, D, Step, Dist: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame > High(T49_SPRITES)) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T49_SPRITES[Frame];

  if EntityUpdateDying(E, AGameState, World) then
    Exit;
  if World.Pool = nil then
    Exit;

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;

  if E.Raw[EF_STATE] = 0 then
    E.Raw[EF_STATE] := 1;

  { Hovering and resting share the flap and the bob. }
  if (E.Raw[EF_STATE] = 1) or (E.Raw[EF_STATE] = 3) then
  begin
    Dec(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] < 1 then
    begin
      E.Raw[EF_BLOCK_B] := T49_TICKS;
      E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T49_FRAMES;
    end;

    E.Raw[EF_FACING] := (E.Raw[EF_FACING] + 1) mod DIR_COUNT;
    { A quarter of the heading's Y component.

      `div`, NOT `shr`. The original's `if v < 0 then v := v + 3; v := v sar
      2` is not a shift the author wrote - it is what Delphi EMITS for a
      signed `div 4`, the +3 turning the arithmetic shift's floor into
      truncation toward zero. Transcribing that codegen literally gives a
      LOGICAL shift in Pascal: with Step = -1 the original gives -1 and `shr
      2` gives $3FFFFFFF. Caught by --emudiff on type 49. }
    Inc(E.Raw[EF_POS_Y],
        DirVelY(E.Raw[EF_FACING]) div (1 shl T49_BOB_SHIFT));
  end;

  if E.Raw[EF_STATE] = 1 then
  begin
    Dist := Abs(E.Raw[EF_POS_X]
                - World.Pool.Field(SLOT_SINGLE_FIRST, EF_POS_X));
    if Dist < 0 then
      Inc(Dist, 31);
    if (Dist shr POSITION_SHIFT) < T49_RANGE[D] then
    begin
      World.SpawnDebris(E, 0);
      E.Raw[EF_STATE] := 2;
      E.Raw[EF_BLOCK_A + 1] := 0;
      E.Raw[EF_CHILD_B] := 0;
      { Only above easy does it aim - on easy it drops straight down. }
      if D > 0 then
        E.Raw[EF_VEL_X] :=
          Compare(E.Raw[EF_POS_X],
                  World.Pool.Field(SLOT_SINGLE_FIRST, EF_POS_X))
          shl T49_AIM_SHIFT;
      E.Raw[EF_VEL_Y] := T49_DIVE_VY;
    end;
  end;

  if E.Raw[EF_STATE] = 2 then
  begin
    { A sign test, not a state: rising shows one frame and falling another. }
    E.Raw[EF_FLAG1C] := T49_RISING_FRAME;
    if E.Raw[EF_VEL_Y] > 0 then
      E.Raw[EF_FLAG1C] := T49_FALLING_FRAME;

    Inc(E.Raw[EF_VEL_Y], T49_GRAVITY);
    if E.Raw[EF_VEL_Y] > T49_DIVE_END then
    begin
      World.SpawnDebris(E, 0);
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_STATE] := 3;
      E.Raw[EF_VEL_Y] := 0;
    end;

    Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);
    Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);
  end;

  if E.Raw[EF_STATE] = 3 then
  begin
    Inc(E.Raw[EF_CHILD_A]);
    if E.Raw[EF_CHILD_A] > T49_REST[D] then
    begin
      E.Raw[EF_STATE] := 1;
      E.Raw[EF_CHILD_A] := 0;
    end;
  end;
end;

procedure EntityUpdate_Type48(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T48_FRAMES) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T48_SPRITES[Frame];

  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  if E.Raw[EF_STATE] = 0 then
  begin
    E.Raw[EF_STATE] := 1;
    E.Raw[EF_CHILD_A] := T48_BOUNCES;
  end;

  { A one-shot handoff slot. Nothing in the shipped game writes it - see the
    T48_ block - but the read is real, so it is here. }
  if E.Raw[T48_HANDOFF] <> 0 then
  begin
    E.Raw[EF_VEL_X] := E.Raw[T48_HANDOFF];
    E.Raw[T48_HANDOFF] := 0;
  end;

  Inc(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] > T48_TICKS then
  begin
    E.Raw[EF_BLOCK_B] := 0;
    E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T48_FRAMES;
  end;

  if World.TileAtX(E, E.Raw[EF_VEL_X], False) >= World.SolidThreshold then
    E.Raw[EF_VEL_X] := World.EdgeDistX(E, E.Raw[EF_VEL_X]);
  Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);

  Inc(E.Raw[EF_VEL_Y], T48_GRAVITY);
  if E.Raw[EF_VEL_Y] > T48_TERMINAL then
    E.Raw[EF_VEL_Y] := T48_TERMINAL;

  if World.TileAtY(E, E.Raw[EF_VEL_Y], False) >= World.SolidThreshold then
  begin
    World.PlaySound(T48_BOUNCE_SOUND);
    Dec(E.Raw[EF_CHILD_A]);
    { On the second-to-last bounce. Entity_UpdateAll flickers the sprite on
      this field's parity, so what this really does is start it blinking. }
    if E.Raw[EF_CHILD_A] = 1 then
      E.Raw[EF_DEATH_TIMER] := T48_BLINK_TIMER;
    E.Raw[EF_VEL_Y] := World.EdgeDistY(E, E.Raw[EF_VEL_Y]);
    E.Raw[EF_STATE] := 2;
  end;

  Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);

  if E.Raw[EF_STATE] = 2 then
  begin
    E.Raw[EF_STATE] := 1;
    { Each rebound is shorter than the last, and this is the only decay. }
    E.Raw[EF_VEL_Y] := (E.Raw[EF_CHILD_A] + 1) * T48_REBOUND_STEP;
  end;

  if E.Raw[EF_CHILD_A] = 0 then
    World.DestroyEntity(E, False);
end;

procedure EntityUpdate_Type47_Mon_PinkSquid(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, D, I, Slot: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame > High(T47_SPRITES)) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T47_SPRITES[Frame];

  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;

  if E.Raw[EF_STATE] = 0 then
    E.Raw[EF_STATE] := 1;

  { The idle and the rest share one two-frame loop. }
  if (E.Raw[EF_STATE] = 1) or (E.Raw[EF_STATE] = 3) then
  begin
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T47_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T47_FRAMES;
    end;
  end;

  if E.Raw[EF_STATE] = 1 then
  begin
    Inc(E.Raw[EF_CHILD_A]);
    if E.Raw[EF_CHILD_A] > T47_WAIT[D] then
    begin
      E.Raw[EF_STATE] := 2;
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_CHILD_A] := 0;
      E.Raw[EF_FLAG1C] := T47_WIND_FIRST;
    end;
  end;

  { The wind-up only advances while visible. }
  if (E.Raw[EF_STATE] = 2) and (not IsOffScreen(E, T47_OFFSCREEN_MARGIN)) then
  begin
    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T47_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      Inc(E.Raw[EF_FLAG1C]);
      if E.Raw[EF_FLAG1C] > T47_WIND_LAST then
      begin
        for I := 0 to High(T47_ANGLES) do
        begin
          Slot := World.Spawn(EKIND_MINOR, T47_SHOT_TYPE,
                              E.Raw[EF_POS_X] - POSITION_BIAS
                                - World.Layer.DeltaX,
                              E.Raw[EF_POS_Y] - World.Layer.DeltaY
                                - POSITION_BIAS - T47_SHOT_LIFT);
          World.SetSpawnField(Slot, EF_VEL_X,
                              T47_ANGLES[I] shl T47_ANGLE_SHIFT);
          World.SetSpawnField(Slot, EF_VEL_Y, T47_SHOT_VY);
        end;
        World.PlaySound(T47_FIRE_SOUND);
        E.Raw[EF_STATE] := 3;
        E.Raw[EF_BLOCK_B] := 0;
      end;
    end;
  end;

  if E.Raw[EF_STATE] = 3 then
  begin
    Inc(E.Raw[EF_CHILD_A]);
    if E.Raw[EF_CHILD_A] > T47_REST[D] then
    begin
      E.Raw[EF_STATE] := 1;
      E.Raw[EF_CHILD_A] := 0;
    end;
  end;
end;

procedure EntityUpdate_Type45_Block_NukeNuke(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, D: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame >= T45_FRAMES) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T45_SPRITES[Frame];

  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;

  { EF_RIDDEN is what Entity_SolidCollideY sets when something stands on a
    solid. This is the only handler that reads it. }
  if (E.Raw[EF_STATE] = 0) and (E.Raw[EF_RIDDEN] = 1) then
    E.Raw[EF_STATE] := 1;

  if E.Raw[EF_STATE] = 1 then
  begin
    Dec(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] < 1 then
    begin
      E.Raw[EF_BLOCK_B] := T45_TICKS;
      Inc(E.Raw[EF_FLAG1C]);
      if E.Raw[EF_FLAG1C] > T45_FRAMES - 1 then
      begin
        E.Raw[EF_FLAG1C] := T45_SHAKE_FIRST;
        Inc(E.Raw[EF_CHILD_A]);
        { A HIGHER difficulty subtracts more, so it breaks SOONER. }
        if E.Raw[EF_CHILD_A] > E.Raw[EF_BLOCK_A + 1] - T45_TOUGH[D] then
        begin
          World.PlaySound(T45_BREAK_SOUND);
          E.Raw[EF_STATE] := 2;
          E.Raw[EF_BLOCK_B] := 0;
          E.Raw[EF_CHILD_A] := 0;
          E.Raw[EF_DEATH_TIMER] := T45_GONE_FRAMES;
          E.Raw[EF_SOLID] := 0;
        end;
      end;
    end;
  end;

  if (E.Raw[EF_STATE] = 2) and (E.Raw[EF_DEATH_TIMER] = 0) then
  begin
    E.Raw[EF_FLAG1C] := 0;
    E.Raw[EF_STATE] := 0;
    E.Raw[EF_SOLID] := 1;
  end;

  { Cleared every frame whatever the state - a one-frame signal the collision
    has to re-set to keep the count going. }
  E.Raw[EF_RIDDEN] := 0;
end;

procedure EntityUpdate_Type46_Mon_Bat(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, D, Dist: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  if (Frame < 0) or (Frame > High(T46_SPRITES)) then
    Frame := 0;
  E.Raw[EF_ANIM_ID] := T46_SPRITES[Frame];

  if E.Raw[EF_STATE] = 0 then
  begin
    E.Raw[EF_STATE] := 1;
    Dec(E.Raw[EF_POS_Y], T46_RISE);
    { So a room full of these does not move in lockstep. }
    E.Raw[EF_FACING] := World.RandomBelow(DIR_COUNT);
  end;

  if EntityUpdateDying(E, AGameState, World) then
    Exit;
  if World.Pool = nil then
    Exit;

  D := World.PlayerDifficulty;
  if (D < 0) or (D > 2) then
    D := 0;

  if E.Raw[EF_STATE] = 1 then
  begin
    E.Raw[EF_FLAG1C] := T46_SLEEP_FRAME;
    { Horizontal distance in PIXELS, with the original's round-toward-zero
      shift. Easy has the LONGEST range, so it wakes soonest there. }
    Dist := Abs(OriginPixel(E.Raw[EF_POS_X]
                - World.Pool.Field(SLOT_SINGLE_FIRST, EF_POS_X)));
    if Dist < T46_RANGE[D] then
    begin
      World.PlaySound(T46_WAKE_SOUND);
      E.Raw[EF_FLAG1C] := 0;
      E.Raw[EF_STATE] := 2;
    end;
  end;

  if E.Raw[EF_STATE] = 2 then
  begin
    { Steer turns one step toward the player and rewrites the velocity from
      the direction table; this then halves it and scales by difficulty. }
    World.Pool.Steer(E.Raw[EF_SLOT], T46_TURN_TIMER, T46_TURN[D]);
    E.Raw[EF_VEL_X] := T46_SPEED[D] * HalfExtent(E.Raw[EF_VEL_X]);
    E.Raw[EF_VEL_Y] := T46_SPEED[D] * HalfExtent(E.Raw[EF_VEL_Y]);

    { Clamped on both axes, so it slides along walls instead of entering. }
    if World.TileAtX(E, E.Raw[EF_VEL_X], False) >= World.SolidThreshold then
      E.Raw[EF_VEL_X] := World.EdgeDistX(E, E.Raw[EF_VEL_X]);
    if World.TileAtY(E, E.Raw[EF_VEL_Y], False) >= World.SolidThreshold then
      E.Raw[EF_VEL_Y] := World.EdgeDistY(E, E.Raw[EF_VEL_Y]);

    Inc(E.Raw[EF_POS_X], E.Raw[EF_VEL_X]);
    Inc(E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y]);

    Inc(E.Raw[EF_BLOCK_B]);
    if E.Raw[EF_BLOCK_B] > T46_TICKS then
    begin
      E.Raw[EF_BLOCK_B] := 0;
      E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod T46_FRAMES;
    end;
  end;
end;

procedure EntityUpdate_Type43_GashiGashi(var E: TEntity; AGameState: Integer;
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

procedure EntityUpdate_Type42_Boss_TealBlobSlammer(var E: TEntity; AGameState: Integer;
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

procedure EntityUpdate_Type41_Mon_TondaCricket(var E: TEntity; AGameState: Integer;
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

procedure EntityUpdate_Type40_PoyoPoyo(var E: TEntity; AGameState: Integer;
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

procedure EntityUpdate_Type38_Mon_AkuNeko(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
var
  Frame, Row, D, Slot: Integer;
begin
  Frame := E.Raw[EF_FLAG1C];
  Row := E.Raw[EF_VARIANT];
  { 0x0045B0CC, unchecked. }
  E.Raw[EF_ANIM_ID] := SpriteDatum(T38_AT + Row * SPRITE_ROW + Frame);

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
  Row := E.Raw[EF_STATE];
  { 0x00459A0C indexes base + Frame*4 + State*0x10 with no bounds test, and
    takes the left-facing half from eight bytes further on. Right half then
    left, by the SIGN, two ifs and no else. }
  if E.Raw[EF_VEL_X] > 0 then
    E.Raw[EF_ANIM_ID] := SpriteDatum(T2_AT + Row * SPRITE_ROW + Frame);
  if E.Raw[EF_VEL_X] < 0 then
    E.Raw[EF_ANIM_ID] :=
      SpriteDatum(T2_AT + Row * SPRITE_ROW + Frame + T2_FRAMES);

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

procedure EntityUpdate_Type30_Akuji(var E: TEntity; AGameState: Integer;
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

procedure EntityUpdate_Type31_Boss_MurasakiLizard(var E: TEntity; AGameState: Integer;
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

procedure EntityUpdate_Type37_BossKey(var E: TEntity; AGameState: Integer;
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

procedure EntityUpdate_Type15_Switch(var E: TEntity; AGameState: Integer;
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

procedure EntityUpdate_Type21_WingedHorseBlock(var E: TEntity; AGameState: Integer;
                              World: TEntityWorld);
begin
  E.Raw[EF_ANIM_ID] := T21_SPRITE;
  if EntityUpdateDying(E, AGameState, World) then
    Exit;

  Inc(E.Raw[EF_BLOCK_B]);
  { The half-period is block A[1]. CORRECTED: this used to credit ParamA's
    'R' letter. Both 'M' and 'R' write that field, but every one of the 12
    shipped type-21 placements uses 'M' - see tools/entity_usage.py --type 21.

    'M' is also where the speed comes from, and it arrives disguised: the
    letter writes EF_FACING := Arg(2) shl 3, meaning it as a heading in
    eighths of the 64-step turn. Type 21 does not read it as a heading at all,
    it adds it to a coordinate. The placements pass -4, so Facing holds -32,
    which at POSITION_SHIFT 5 is exactly one pixel a frame. }
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

procedure EntityUpdate_Type23_Candle(var E: TEntity; AGameState: Integer;
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

procedure EntityUpdate_Type29_Mon_MidoriMonster(var E: TEntity; AGameState: Integer;
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
  Row := E.Raw[EF_VARIANT];
  { 0x0045A08C, unchecked. This one can overrun on the FRAME as well as the
    row: the sprite is written before the `> 3` test that destroys the
    entity, so the frame that ends it reads one past its row. }
  E.Raw[EF_ANIM_ID] := SpriteDatum(T7_AT + Row * SPRITE_ROW + Frame);

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

procedure EntityUpdate_Type16_InfoSign(var E: TEntity);
begin
  E.Raw[EF_ANIM_ID] := SIGN_SPRITE;
end;

procedure EntityUpdate_Type22_SpikeBall(var E: TEntity; AGameState: Integer;
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

procedure EntityUpdate_Type27_AkujiStatue(var E: TEntity; AGameState: Integer);
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

procedure EntityUpdate_Type14_ManaStone(var E: TEntity; AGameState: Integer);
var
  Variant, Frame: Integer;
begin
  Variant := E.Raw[EF_VARIANT];
  Frame := E.Raw[EF_FLAG1C];
  { The original indexes without bounds checks and would read past the table
    on a bad variant; clamping instead of faulting is the one deviation here,
    and it is DIV-011's class.

    It is unreachable for shipped data. tools/entity_usage.py finds 122
    placements of type 14 over 32 stages, all opcode 9, with only two ParamA
    forms: `0014-*` 91 times, which writes no variant at all, and
    `0014-A-001` 31 times. So the shipped variants are exactly 0 and 1,
    against a table the layout independently says is two rows. }
  { 0x0045A3E0, unchecked. Only the VARIANT can leave the table here - the
    frame counter is masked to 0..3 where it is advanced. }
  E.Raw[EF_ANIM_ID] := SpriteDatum(MANA_AT + Variant * SPRITE_ROW + Frame);

  if E.Raw[EF_STATE] = 0 then
  begin
    E.Raw[EF_STATE] := 1;
    E.Raw[EF_POS_Y] := E.Raw[EF_POS_Y] + MANA_SETTLE_DROP;
  end;

  if AGameState <> GS_PLAY then
    Exit;

  Inc(E.Raw[EF_BLOCK_B]);
  if E.Raw[EF_BLOCK_B] > MANA_FRAME_TICKS then
  begin
    E.Raw[EF_BLOCK_B] := 0;
    E.Raw[EF_FLAG1C] := (E.Raw[EF_FLAG1C] + 1) mod MANA_FRAMES;
  end;
end;


{ The original compares the LOW BYTE of +0x08 against 1, not the int against 0.
  Only 0 and 1 are ever stored there, so the two agree - but the loop is written
  the original's way because the difference is free to keep. }
function IsAlive(const E: TEntity): Boolean;
begin
  Result := (E.Raw[EF_ALIVE] and $FF) = 1;
end;

{ One int of the sprite DATA region.

  Inside the region this is the read the original makes, overrun and all.
  Outside it there is nothing to read - the original would take whatever the
  process happened to have at that address, which is not reproducible - so the
  index is clamped THERE and only there. }
function SpriteDatum(Index: Integer): Integer;
begin
  { DIVERGENCE DIV-011, and all that is left of it: inside the region this is
    the original's read, overrun and all. Outside it there is nothing to copy. }
  if Index < 0 then
    Index := 0;
  if Index > High(SPRITE_DATA) then
    Index := High(SPRITE_DATA);
  Result := SPRITE_DATA[Index];
end;

function ScaleByPercent(Half, Percent: Integer): Integer;
var
  SignMultiplier, NormalizeShift, SignificandShift, BitIndex: Integer;
  Pow2Mod200, ErrorMagnitude, ScaledError, ValueExponent: Integer;
  ComparisonShift: Integer;
  Product, Quotient, Remainder, Remainder200, TwiceTie: Int64;
  LeftSide, RightSide: Int64;
begin
  SignMultiplier := 1;
  if Half < 0 then
  begin
    SignMultiplier := -1;
    Half := -Half;
  end;
  if Percent < 0 then
  begin
    SignMultiplier := -SignMultiplier;
    Percent := -Percent;
  end;
  if (Half = 0) or (Percent = 0) then
    Exit(0);

  Product := Int64(Half) * Percent;
  Quotient := Product div 100;
  Remainder := Product mod 100;
  if Remainder > 50 then
    Exit(SignMultiplier * Integer(Quotient + 1));
  if Remainder < 50 then
    Exit(SignMultiplier * Integer(Quotient));

  { --- a tie, and the only case where the FPU's own error decides -----------
    SignificandShift normalises Percent/100 to a 64-bit significand: starting
    with NormalizeShift such that
    100 <= Percent * 2^NormalizeShift < 200, then adding 63. }
  NormalizeShift := 0;
  if Percent < 100 then
    while (Int64(Percent) shl NormalizeShift) < 100 do
      Inc(NormalizeShift)
  else
    while (Int64(Percent) shr (-NormalizeShift)) >= 200 do
      Dec(NormalizeShift);
  SignificandShift := 63 + NormalizeShift;

  { ScaledError = D*100 - Percent*2^SignificandShift: the divide's rounding
    error scaled up. Its magnitude is at most 50 and can be derived from
    Percent*2^SignificandShift mod 200, avoiding a 128-bit product. Modulo 200
    rather than 100 carries the parity needed for a tie inside the tie. }
  Pow2Mod200 := 1;
  for BitIndex := 1 to SignificandShift do
    Pow2Mod200 := (Pow2Mod200 * 2) mod 200;
  Remainder200 := (Int64(Percent) * Pow2Mod200) mod 200;
  ErrorMagnitude := Integer(Remainder200 mod 100);
  if ErrorMagnitude < 50 then
    ScaledError := -ErrorMagnitude
  else if ErrorMagnitude > 50 then
    ScaledError := 100 - ErrorMagnitude
  else if Remainder200 >= 100 then
    ScaledError := 50
  else
    ScaledError := -50;

  if ScaledError <> 0 then
  begin
    { Compare |Half * ScaledError| / (100 * 2^SignificandShift) against half
      an ulp of V = Quotient + 1/2, which is 2^(ValueExponent - 64). Both
      sides scale to integers well inside Int64. }
    TwiceTie := 2 * Quotient + 1;
    ValueExponent := -1;
    while (Int64(1) shl (ValueExponent + 2)) <= TwiceTie do
      Inc(ValueExponent);
    ComparisonShift := SignificandShift + ValueExponent - 64;
    LeftSide := Abs(Int64(Half) * ScaledError);
    if ComparisonShift >= 0 then
      RightSide := Int64(100) shl ComparisonShift
    else
    begin
      LeftSide := LeftSide shl (-ComparisonShift);
      RightSide := 100;
    end;
    { Equality means the product landed exactly half an ulp off the tie. It
      occurs five times in the self-test domain and falls through because RN64
      breaks its own tie toward V's even significand. Writing >= here changes
      no tested answer; > is established by the derivation. }
    if LeftSide > RightSide then
    begin
      { The product landed off the tie, and the sign of the error decides. }
      if ScaledError > 0 then
        Exit(SignMultiplier * Integer(Quotient + 1))
      else
        Exit(SignMultiplier * Integer(Quotient));
    end;
  end;

  { The second rounding pulled the product back onto the tie exactly, so the
    final store rounds half to even. }
  if Quotient mod 2 = 0 then
    Result := SignMultiplier * Integer(Quotient)
  else
    Result := SignMultiplier * Integer(Quotient + 1);
end;

{ The type switch, lifted out of EntityUpdateAll's loop so a test can drive
  one handler without running a whole frame.

  This is a REFACTOR, not a divergence: it is the same case statement, called
  from the same place, in the same order, and no arm's behaviour changes. It is
  extracted because --emudiff needs to call a handler by type against an entity
  it controls, and the alternative was a second copy of a 78-arm switch that
  could drift from this one silently. In the original the switch is a jump
  table inlined in Entity_UpdateAll @ 0x004608BC; it is a procedure here for
  the same reason TEntityWorld is a class - so the parts can be tested. }
procedure EntityRunHandler(var E: TEntity; var P: TPlayerState;
                           var L: TLayerInfo; var Inp: TInputState;
                           World: TEntityWorld; AGameState: Integer);
begin
  case E.Raw[EF_TYPE] of
    1:  PlayerUpdate(E, P, L, Inp, World, AGameState);
    14: EntityUpdate_Type14_ManaStone(E, AGameState);
    24: EntityUpdate_Type24_PowerOrb(E, AGameState, World);
    25: EntityUpdate_Type25_Door(E);
    27: EntityUpdate_Type27_AkujiStatue(E, AGameState);
    32: EntityUpdate_Type32_Emitter(E, AGameState, World);
    33: EntityUpdate_Type33_Explosion(E, AGameState, World);
    2:  EntityUpdate_Type02(E, AGameState, World);
    3:  EntityUpdate_Type03(E, AGameState, World);
    4:  EntityUpdate_Type04(E, AGameState, World);
    5:  EntityUpdate_Type05(E, AGameState, World);
    6:  EntityUpdate_Type06(E, AGameState, World);
    7:  EntityUpdate_Type07(E, AGameState, World);
    8:  EntityUpdate_Type08(E, AGameState, World);
    9:  EntityUpdate_Type09(E, AGameState);
    10: EntityUpdate_Type10(E, AGameState, World);
    11: EntityUpdate_Type11(E, AGameState);
    12: EntityUpdate_Type12(E, AGameState);
    13: EntityUpdate_Type13(E, AGameState, World);
    15: EntityUpdate_Type15_Switch(E, AGameState, World);
    17: EntityUpdate_Type17(E);
    19: EntityUpdate_Type19(E);
    21: EntityUpdate_Type21_WingedHorseBlock(E, AGameState, World);
    23: EntityUpdate_Type23_Candle(E, AGameState, World);
    28: EntityUpdate_Type28(E, AGameState, World);
    29: EntityUpdate_Type29_Mon_MidoriMonster(E, AGameState, World);
    30: EntityUpdate_Type30_Akuji(E, AGameState, World);
    31: EntityUpdate_Type31_Boss_MurasakiLizard(E, AGameState, World);
    34: EntityUpdate_Type34(E, AGameState, World);
    35: EntityUpdate_Type35(E, AGameState, World);
    37: EntityUpdate_Type37_BossKey(E, AGameState, World);
    38: EntityUpdate_Type38_Mon_AkuNeko(E, AGameState, World);
    39: EntityUpdate_Type39(E, AGameState, World);
    40: EntityUpdate_Type40_PoyoPoyo(E, AGameState, Inp, World);
    41: EntityUpdate_Type41_Mon_TondaCricket(E, AGameState, World);
    42: EntityUpdate_Type42_Boss_TealBlobSlammer(E, AGameState, World);
    43: EntityUpdate_Type43_GashiGashi(E, AGameState, World);
    44: EntityUpdate_Type44(E, AGameState, World);
    45: EntityUpdate_Type45_Block_NukeNuke(E, AGameState, World);
    46: EntityUpdate_Type46_Mon_Bat(E, AGameState, World);
    47: EntityUpdate_Type47_Mon_PinkSquid(E, AGameState, World);
    48: EntityUpdate_Type48(E, AGameState, World);
    49: EntityUpdate_Type49_Mon_Water(E, AGameState, World);
    50: EntityUpdate_Type50_Mon_Turtle(E, AGameState, World);
    51: EntityUpdate_Type51_Mon_Ghost(E, AGameState, World);
    53: EntityUpdate_Type53(E, AGameState, World);
    56: EntityUpdate_Type56_Mon_AkaiKinoko(E, AGameState, World);
    52: EntityUpdate_Type52_Boss_FireLion(E, AGameState, World);
    54: EntityUpdate_Type54_Boss_FloatingMagician(E, AGameState, World);
    55: EntityUpdate_Type55(E, AGameState, World);
    57: EntityUpdate_Type57(E, AGameState, World);
    58: EntityUpdate_Type58_Mon_NiseMana(E, AGameState, World);
    59: EntityUpdate_Type59_Mon_RedEye(E, AGameState, World);
    60: EntityUpdate_Type60_Mon_Golem(E, AGameState, World);
    61: EntityUpdate_Type61_Mon_HenaHena(E, AGameState, World);
    62: EntityUpdate_Type62_Mon_PenguinHeishi(E, AGameState, World);
    63: EntityUpdate_Type63_Mon_PenguinKnife(E, AGameState, World);
    64: EntityUpdate_Type64_SpikePress(E, AGameState, World);
    65: EntityUpdate_Type65_Mon_DorDor(E, AGameState, Inp, World);
    66: EntityUpdate_Type66_GiantBall(E, AGameState, World);
    67: EntityUpdate_Type67_Mon_TurtleBomb(E, AGameState, World);
    68: EntityUpdate_Type68(E, AGameState, World);
    69: EntityUpdate_Type69_GoroGoro(E, AGameState, World);
    70: EntityUpdate_Type70_AngrySwitch(E, AGameState, World);
    71: EntityUpdate_Type71_BouncyCat(E, AGameState, World);
    72: EntityUpdate_Type72(E, AGameState, World);
    73: EntityUpdate_Type73_Boss_MidoriLizard(E, AGameState, World);
    74: EntityUpdate_Type74(E, AGameState, World);
    75: EntityUpdate_Type75(E, AGameState, World);
    76: EntityUpdate_Type76_SpikePress_Lev(E, AGameState, World);
    77: EntityUpdate_Type77_Boss_Hero(E, AGameState, World);
    78: EntityUpdate_Type78(E, AGameState, World);
    79: EntityUpdate_Type79(E, AGameState, World);
    80: EntityUpdate_Type80_Fx_ArenaEmber(E, AGameState, World);
    16: EntityUpdate_Type16_InfoSign(E);
    22: EntityUpdate_Type22_SpikeBall(E, AGameState, World);
    26: EntityUpdate_Type26(E, AGameState, World);
    36: EntityUpdate_Type36_FallingItem(E, AGameState, World);
    { Every arm in HANDLER_ADDR now has a case above. This else is not in
      the original - the compiler emitted a jump table with no default -
      and exists only so the claim can be checked; see EntitiesUnhandled.
      DIVERGENCE DIV-006. }
  else
    Inc(EntitiesUnhandled);
  end;
end;

procedure EntityUpdateAll(Pool: TEntityPool; World: TEntityWorld;
                          Sprites: TSpriteSink;
                          var P: TPlayerState; var L: TLayerInfo;
                          var Inp: TInputState; var AGameState: Integer);
var
  EntitySlot, SpriteHandle, ScreenX, ScreenY, Depth: Integer;
  HalfWidth, HalfHeight: Integer;
  EntityPtr: PEntity;
begin
  EntitiesDrawn := 0;
  EntitiesLive  := 0;

  for EntitySlot := 0 to ENTITY_UPDATE_COUNT - 1 do
  begin
    EntityPtr := Pool.Entity(EntitySlot);
    if not IsAlive(EntityPtr^) then
      Continue;
    Inc(EntitiesLive);

    { Carried along by the scroll unless the type is screen-space. This is why
      a HUD element placed as an entity stays put while the map moves under it. }
    if EntityPtr^.Raw[EF_SCREEN_SPACE] = 0 then
    begin
      Inc(EntityPtr^.Raw[EF_POS_X], L.DeltaX);
      Inc(EntityPtr^.Raw[EF_POS_Y], L.DeltaY);
    end;

    EntityRunHandler(EntityPtr^, P, L, Inp, World, AGameState);

    { --- push the entity onto its sprite ---------------------------------
      Skipped entirely for a type with no sprite, and re-tests aliveness
      because the handler above may have destroyed the entity. }
    SpriteHandle := EntityPtr^.Raw[EF_SPRITE];
    if (SpriteHandle <> SPRITE_NONE) and IsAlive(EntityPtr^) then
    begin
      Inc(EntitiesDrawn);

      { The death timer doubles as the damage flicker: while it is ODD the
        sprite is hidden, so an entity blinks for as long as it is counting
        down. On even frames the sprite takes EF_BYTE94 verbatim - a byte copy,
        so it is that field and not a normalised boolean that decides
        visibility. }
      if EntityPtr^.Raw[EF_DEATH_TIMER] mod 2 = 0 then
        Sprites.SetVisible(SpriteHandle,
          (EntityPtr^.Raw[EF_BYTE94] and $FF) <> 0)
      else
        Sprites.SetVisible(SpriteHandle, False);

      Sprites.SetAnim(SpriteHandle, EntityPtr^.Raw[EF_ANIM_ID]);

      { Extents refresh only while visible, so a hidden entity keeps the size it
        had when it was last drawn - and keeps colliding at that size. }
      if Sprites.GetVisible(SpriteHandle) then
      begin
        EntityPtr^.Raw[EF_EXTENT_X] := Sprites.Width(SpriteHandle);
        EntityPtr^.Raw[EF_EXTENT_Y] := Sprites.Height(SpriteHandle);
      end;

      { The sprite is placed by its top-left, the entity by its CENTRE: half the
        sprite comes off each axis. That is what fixes an entity position as a
        centre point rather than a corner. }
      ScreenX := OriginPixel(EntityPtr^.Raw[EF_POS_X]) - POSITION_BIAS_PIXELS
                 - HalfExtent(EntityPtr^.Raw[EF_EXTENT_X]);
      ScreenY := OriginPixel(EntityPtr^.Raw[EF_POS_Y]) - POSITION_BIAS_PIXELS
                 - HalfExtent(EntityPtr^.Raw[EF_EXTENT_Y]);
      Sprites.SetPos(SpriteHandle, ScreenX, ScreenY);

      Depth := EntityPtr^.Raw[EF_DEPTH];
      if Depth = DEPTH_BY_SCREEN_Y then
      begin
        Depth := ScreenY;
        if Depth < 1 then Depth := 1;
        if Depth > SCREEN_H then Depth := SCREEN_H;
      end;
      Sprites.SetDepth(SpriteHandle, Depth);
    end;

    { --- the two timers -------------------------------------------------
      Frozen during the pause menu and during state 140, which is what makes a
      paused invulnerability or a paused death animation hold. }
    if (AGameState <> GS_PAUSE) and (AGameState <> GS_STATE_140) then
    begin
      if EntityPtr^.Raw[EF_TIMER] <> 0 then
        Dec(EntityPtr^.Raw[EF_TIMER]);
      if EntityPtr^.Raw[EF_DEATH_TIMER] <> 0 then
        Dec(EntityPtr^.Raw[EF_DEATH_TIMER]);
    end;

    if AGameState <> GS_PLAY then
      Continue;

    { --- collision boxes, rebuilt from the sprite size ------------------- }
    HalfWidth := HalfExtent(EntityPtr^.Raw[EF_EXTENT_X]);
    HalfHeight := HalfExtent(EntityPtr^.Raw[EF_EXTENT_Y]);
    EntityPtr^.Raw[EF_BOX_OFS_X] :=
      ScaleByPercent(HalfWidth, EntityPtr^.Raw[EF_BOX_PCT_X]);
    EntityPtr^.Raw[EF_BOX_OFS_Y] :=
      ScaleByPercent(HalfHeight, EntityPtr^.Raw[EF_BOX_PCT_Y]);
    EntityPtr^.Raw[EF_HITBOX_INSET_X] :=
      ScaleByPercent(HalfWidth, EntityPtr^.Raw[EF_INSET_PCT_X]);
    EntityPtr^.Raw[EF_HITBOX_INSET_Y] :=
      ScaleByPercent(HalfHeight, EntityPtr^.Raw[EF_INSET_PCT_Y]);

    { Only the minor slots are touch-tested and shot-tested. The player and the
      actors below SLOT_MINOR_FIRST are not, which is the same boundary
      Entity_TakeProjectileHits scans up to from the other side. }
    if (EntitySlot >= SLOT_MINOR_FIRST) and IsAlive(EntityPtr^) then
    begin
      if Assigned(EntityPlayerTouch) then
        EntityPlayerTouch(EntityPtr^, Pool.Entity(0)^, P, Inp, World);
      if Assigned(EntityTakeProjectileHits) then
        EntityTakeProjectileHits(EntityPtr^, World);
    end;

    if (EntityPtr^.Raw[EF_TYPE] = TYPE_TOUCH_IN_STATE_3)
       and (EntityPtr^.Raw[EF_STATE] = 3) and IsAlive(EntityPtr^) then
      if Assigned(EntityPlayerTouch) then
        EntityPlayerTouch(EntityPtr^, Pool.Entity(0)^, P, Inp, World);

    { A touch can change the game state - start an event script, kill the
      player - and when it does the original ABANDONS the rest of the pool for
      this frame. It is a real early return: the branch target is the function
      epilogue, not the loop tail, and the loop tail is four instructions away.
      Reachable only through the two calls above, since the state was GS_PLAY a
      dozen lines up. }
    if (AGameState <> GS_PLAY) and (AGameState <> GS_STATE_140) then
      Exit;

    if IsAlive(EntityPtr^) and (EntityPtr^.Raw[EF_CULL_OFFSCREEN] = 1)
       and IsOffScreen(EntityPtr^, CULL_MARGIN) then
      World.DestroyEntity(EntityPtr^, False);
  end;
end;


{ THE REGION AND THE PER-TYPE TABLES MUST AGREE. SPRITE_DATA is the memory the
  four unchecked handlers read through; the arrays are what each table IS. Both
  come from the same image, and if one were ever edited without the other the
  overruns would quietly stop matching.

  Checked at startup rather than in a self-test, because a mismatch makes all
  four of those handlers wrong and nothing else would notice. NOT Assert - FPC
  compiles assertions out without -Sa, which this project does not pass. }
procedure CheckSpriteData;

  procedure Same(const Name: string; At: Integer; const Want: array of Integer);
  var
    ValueIndex: Integer;
  begin
    for ValueIndex := 0 to High(Want) do
      if SPRITE_DATA[At + ValueIndex] <> Want[ValueIndex] then
        raise Exception.CreateFmt(
          '%s[%d] is %d but SPRITE_DATA at 0x%.8x is %d - the region and the '
          + 'tables have been edited apart', [Name, ValueIndex,
          Want[ValueIndex], SPRITE_DATA_BASE + 4 * (At + ValueIndex),
          SPRITE_DATA[At + ValueIndex]]);
  end;

begin
  Same('T2_SPRITES', T2_AT, [T2_SPRITES[0][0], T2_SPRITES[0][1],
       T2_SPRITES[0][2], T2_SPRITES[0][3], T2_SPRITES[1][0]]);
  Same('T7_SPRITES', T7_AT, [T7_SPRITES[0][0], T7_SPRITES[0][1],
       T7_SPRITES[0][2], T7_SPRITES[0][3], T7_SPRITES[1][0]]);
  Same('MANA_SPRITES', MANA_AT, [MANA_SPRITES[0][0], MANA_SPRITES[0][1],
       MANA_SPRITES[0][2], MANA_SPRITES[0][3], MANA_SPRITES[1][0]]);
  Same('T38_SPRITES', T38_AT, [T38_SPRITES[0][0], T38_SPRITES[0][1],
       T38_SPRITES[0][2], T38_SPRITES[0][3], T38_SPRITES[1][0]]);
end;

initialization
  CheckSpriteData;
  { The touch pass is real now. It stays a variable only so a test can put a
    counting stub in its place. }
  EntityPlayerTouch := @PlayerTouch;
  EntityTakeProjectileHits := @TakeProjectileHits;

end.
