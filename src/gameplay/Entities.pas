{ Entity storage, lifecycle, collision helpers, and static type metadata.

  The pool is one flat array of 65-integer records, partitioned by Spawn's
  first argument:

      kind 0 -> slot 0 only        kind 1 -> slots 1..0x20
      kind 2 -> slots 0x21..0x120  289 in all

  Slot 0 is the player. A slot is free when its Alive byte is zero; Spawn
  returns -1 and drops the request when the selected partition is full.

  POSITIONS ARE BIASED, not fixed point: Spawn adds $10000 and its callers
  subtract it again, so the bias cancels and the logical coordinate is plain
  pixels. It exists to keep the stored field positive, so truncating division
  by a tile size behaves the same either side of the origin.

  The type table contains 81 rows of 18 integers. Unknown fields
  retain numeric names until their behavior is understood. }

unit Entities;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, Directions;

const
  ENTITY_INTS   = $41;      { 65 ints = 0x104 bytes, the array stride }
  ENTITY_BYTES  = $104;

  { Slot partitions selected by Spawn's Kind argument. }
  EKIND_SINGLE  = 0;        { slot 0 only - the player }
  EKIND_ACTOR   = 1;        { slots 1..0x20 }
  EKIND_MINOR   = 2;        { slots 0x21..0x120 }

  SLOT_SINGLE_FIRST = $00;  SLOT_SINGLE_LAST = $00;
  SLOT_ACTOR_FIRST  = $01;  SLOT_ACTOR_LAST  = $20;
  SLOT_MINOR_FIRST  = $21;  SLOT_MINOR_LAST  = $120;
  ENTITY_COUNT      = SLOT_MINOR_LAST + 1;   { 289 }

  SLOT_NONE = -1;           { Entity_Spawn's failure return }

  { Positions are biased by POSITION_BIAS and held in 1/32-pixel units.
    Conversion to pixels must remove the bias with truncation toward zero:

        p := Raw[EF_POS_X] - POSITION_BIAS;
        if p < 0 then p := Raw[EF_POS_X] - (POSITION_BIAS - 31);
        pixels := p shr 5;

    The second line compensates for the arithmetic shift of negative values. }
  POSITION_BIAS  = $10000;
  POSITION_SHIFT = 5;         { 1/32 pixel }
  POSITION_ROUND = $10000 - 31;

  { The bias expressed in whole pixels. Entity_UpdateAll converts a position to
    a screen coordinate by shifting FIRST and subtracting the bias afterwards -
    `(Raw div 32) - 2048` rather than `(Raw - $10000) div 32`. The two agree
    because $10000 is an exact multiple of 32. }
  POSITION_BIAS_PIXELS = POSITION_BIAS shr POSITION_SHIFT;   { 2048 }

  { Collision combines two biased coordinates, producing 128 tiles of bias at
    the game's 32-pixel tile size. }
  TILE_BIAS_TILES = $80;   { 128 }

  TILE_NONE = -1;

  { What Entity_CheckKillTiles puts an entity into on touching the stage's kill
    tile. Stages.pas has which tile that is per terrain. }
  KILL_TILE_STATE = 10;          { Entity_TileCollide*'s "nothing solid that way" }

  { Delphi-compatible random generator:

        RandSeed := RandSeed * $08088405 + 1
        Result   := (N * RandSeed) shr 32

    Debris, scatter, and item drops share one seed. }
  RANDOM_MULT = $08088405;

  { Five debris particles, fanned upward at fixed speeds and scattered
    horizontally at random. The impact sound depends on the KIND, and kind 0
    asks the terrain - which is where terrain 3 and 4 turn out to mean water. }
  DEBRIS_SPLASH   = 0;    { the sound comes from the terrain }
  DEBRIS_IMPACT   = 1;
  DEBRIS_SHATTER  = 2;
  DEBRIS_LIFT     = 8;    { particle i leaves at (i + 4) * -8 }
  DEBRIS_DEPTH    = 6;
  DEBRIS_SPEED_MAX = 3;   { RandomBelow(3) + 1, so 1..3 }

  { One Random(256) roll decides both whether an item drops and its rarity. The
    item drops when the roll
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

  DESTROY_CLASS_PROJECTILE = 4;
  DESTROY_CLASS_PARENT     = 5;
  DESTROY_CLASS_SHATTER    = 7;
  EF_NO_DROP  = $37;   { type table column 8; non-zero means never drop }
  EF_OWNER    = $01;   { the slot that fired this }
  EF_SHOTS    = $15;   { on an OWNER: how many of its shots are alive }
  EVENT_OPCODE_DESTROY = 7;
  EVENT_OPCODE_FLAG    = 5;
  EVENT_BEGIN_FROM_DESTROY = 4;

  PLAYER_SLOT = 0;       { the player always occupies pool slot 0 }
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
  EF_FLAG1C      = $07;   { item variant or animation selector }
  EF_BLOCK_A     = $08;   { 10 ints, zeroed on spawn }
  { Block B is a bank of 10 countdown timers. Steer decrements and reloads one
    to rate-limit per-entity behavior without a scheduler. }
  EF_BLOCK_B     = $12;   { 10 ints at +0x48, contiguous with A }
  EF_TIMER_COUNT = 10;
  EF_TIMER       = $1C;   { +0x70. One slot with several uses, all timers:
                            Entity_MaybeDropItem seeds it with 30, the death
                            sequence uses it as a countdown, and a hit sets it
                            and EF_DEATH_TIMER to 8 as invulnerability. }
  EF_POS_X       = $1E;   { biased; use PosX }
  EF_POS_Y       = $1F;
  EF_VEL_X       = $20;   { zeroed on spawn }
  EF_VEL_Y       = $21;   { dropped items receive their upward launch here }
  EF_FACING      = $22;   { direction 0..63, see Directions.pas }
  { Sprite draw layer. -1 selects screen-Y sorting, although no shipped entity
    type uses that mode. Touch handling also reads this slot as a vertical
    inset, so the type-table alias remains explicit. }
  EF_TYPEF_08    = $23;   { <- type table +0x08, column 2 }
  EF_DEPTH       = EF_TYPEF_08;
  DEPTH_BY_SCREEN_Y = -1;
  EF_HP          = $24;   { type table col 1. On a target this is HIT POINTS;
                            on a projectile the SAME slot is its damage. One
                            field, two roles by role - see the note below. }
  EF_TYPEF_04    = EF_HP; { type-table alias used by spawn initialization }
  EF_BYTE94      = $25;   { byte, set to 1 on spawn }
  { +0xB0. A velocity PARKED for one frame. Type 57 variant 3 uses it to
    bounce off a wall: on the frame it hits, EF_VEL_X is overwritten with the
    exact distance to the wall so it lands flush, and the reversed velocity is
    left here for the NEXT frame to pick up. Without the parking spot the
    flush-landing write would destroy the bounce. }
  EF_PARKED_VEL  = $2C;

  { Unidentified field retained between occupants because Spawn neither clears
    nor initializes it. Type 72 variant 0 writes 1; no reader is known. }
  EF_FIELD_C0    = $30;

  EF_EVENT_ID    = $2E;   { +0xB8. Source event, or -1 for direct spawns }
  { Type-table columns copied by Spawn:

        col   0        -> int $05   the drawn sprite id
        col   1        -> int $24   EF_HP
        col   2        -> int $23
        col   3 ..  6  -> int $32 .. $35
        col   7        -> NOWHERE. Never copied, and zero in all 81 rows.
        col   8 .. 17  -> int $37 .. $40

    Column 7 is intentionally skipped. Columns 1 and 2 cross over into fields
    $24 and $23 respectively. }
  EF_TYPEF_0C    = $32;   { <- type table col 3, the first of the $32..$35 run }
  EF_TYPEF_20    = $37;   { <- type table col 8, the first of the $37..$40 run }

  { Bounding-box and tile-grid fields. Extents are full width and height; box
    calculations halve them around the entity position. }
  { Also not stored. Entity_UpdateAll refreshes both from the sprite's CURRENT
    frame, and only while it is visible - so an entity that animates through
    frames of different sizes has a collision box that changes with them. }
  EF_EXTENT_X    = $26;   { +0x98, sprite width }
  EF_EXTENT_Y    = $27;   { +0x9C, sprite height }
  EF_BOX_OFS_X   = $28;   { +0xA0, added going one way and subtracted the other }
  EF_BOX_OFS_Y   = $29;   { +0xA4 }
  EF_TILE_OFS_X  = $3F;   { +0xFC }
  EF_TILE_OFS_Y  = $40;   { +0x100 - the LAST int in the record }

  { The entity-versus-entity box, from Entity_SolidCollideX / ...Y. NOT the
    tile box: EF_EXTENT_* is shared, but the offsets are not - EF_BOX_OFS_*
    belongs to the tile path and EF_HITBOX_INSET_* to this one. }
  EF_HITBOX_INSET_X = $2A;  { +0xA8 }
  EF_HITBOX_INSET_Y = $2B;  { +0xAC }

  { EF_BOX_OFS_* and EF_HITBOX_INSET_* are not stored. Entity_UpdateAll
    recomputes all four every GS_PLAY frame from the sprite's current size and
    these percentages - see EntityHandlers.pas, which also explains why the
    scaling is done in integers rather than with Round. }
  EF_BOX_PCT_X   = $3A;   { +0xE8, type table column 11 }
  EF_BOX_PCT_Y   = $3B;   { +0xEC, column 12 }
  EF_INSET_PCT_X = $3C;   { +0xF0, column 13 }
  EF_INSET_PCT_Y = $3D;   { +0xF4, column 14 }
  BOX_PERCENT_DIVISOR: Single = 100.0;
  EF_SOLID          = $3E;  { +0xF8, the kind above, from TYPE_COL_SOLID. The
                              shipped table holds only 0, 1 and 2, so "blocks
                              both" is a case the code supports and this game
                              never reaches. }
  EF_RIDDEN         = $0A;  { +0x28, block A[2]. Entity_SolidCollideY sets it
                              on the SOLID when something lands on top of it. }

  { Landing counts as "on top" only if the overlap is under this many pixels,
    which is what stops a deep overlap being read as a landing. }
  SOLID_TOP_TOLERANCE = 8;

  { Entities 1..32 are never scanned as solids: both functions sweep 33..255,
    or slot 0 alone when asked to collide against the player only. }
  SOLID_SCAN_FIRST = $21;
  SOLID_SCAN_LAST  = $FF;

  { Shared dying-state fields. }
  EF_DEATH_TIMER = $1D;   { +0x74, counts down; 0 destroys the entity }
  EF_DYING       = $11;   { +0x44, the one-shot latch }
  EF_CLASS       = $33;   { +0xCC }

  { EF_CLASS is the entity's broad lifecycle category, not its type index:

        1, 2, 6   Entity_UpdateDying   each with its own death effect
        4, 5, 7   Entity_Destroy       4 decrements a counter on its owner,
                                       5 recursively destroys two child slots
                                       at +0x4C and +0x50, 7 spawns debris }
  EF_CHILD_A     = $13;   { +0x4C, destroyed with the parent when EF_CLASS = 5 }
  EF_CHILD_B     = $14;   { +0x50 }

  EF_DEBRIS_SPEEDS = 5;   { the burst is always five particles }
  EF_DEBRIS_TYPE   = $0D; { the type they are spawned as }

  { The type table's 18 columns, in order, each named for the entity field
    Entity_Spawn copies it into. }
  TYPE_COL_ANIM_ID     = 0;   { -> EF_ANIM_ID; -1 means the type has no art }
  TYPE_COL_HP          = 1;   { -> EF_HP    } { 1 and 2 CROSS OVER: the HP }
  TYPE_COL_DEPTH       = 2;   { -> EF_DEPTH } { column lands in the depth field }
  TYPE_COL_TOUCH_KIND  = 3;   { -> EF_TYPEF_0C, first of a run of four }
  TYPE_COL_SCREEN_SPACE = 5;  { -> EF_SCREEN_SPACE; 1 = does not scroll }
  TYPE_COL_UNUSED      = 7;   { never copied; zero in all 81 rows }
  TYPE_COL_NO_DROP     = 8;   { -> EF_NO_DROP, first of a run of ten }
  TYPE_COL_TAIL_COUNT  = 10;  { columns 8..17 -> EF_TYPEF_20..EF_TILE_OFS_Y }
  TYPE_COL_CULL_OFFSCREEN = 10; { -> EF_CULL_OFFSCREEN }
  TYPE_COL_BOX_PCT_X   = 11;  { -> EF_BOX_PCT_X   }
  TYPE_COL_BOX_PCT_Y   = 12;  { -> EF_BOX_PCT_Y   }
  TYPE_COL_INSET_PCT_X = 13;  { -> EF_INSET_PCT_X }
  TYPE_COL_INSET_PCT_Y = 14;  { -> EF_INSET_PCT_Y }
  TYPE_COL_SOLID       = 15;  { -> EF_SOLID }
  TYPE_COL_TILE_OFS_X  = 16;  { -> EF_TILE_OFS_X; a runtime offset, 0 here }
  TYPE_COL_TILE_OFS_Y  = 17;  { -> EF_TILE_OFS_Y }

  EF_SCREEN_SPACE   = $34;
  EF_CULL_OFFSCREEN = $39;
  CULL_MARGIN       = 4;        { Entity_IsOffScreen's argument in the update loop }

  { Types 0, 18, and 20 have no update handler. Type 32 updates without a
    sprite. }

  { Deliberately smaller than ENTITY_COUNT: Entity_Spawn allocates as far as
    slot $120 but Entity_UpdateAll returns after 256, so the last 33 slots can
    be spawned into and are then never updated, drawn or culled. The sprite
    search stops at 256 too, so they cannot receive art. }
  ENTITY_UPDATE_COUNT = $100;   { what Entity_UpdateAll actually walks }

  { The two 10-int blocks Entity_Spawn zeroes, $08..$11 and $12..$1B:

      Block A   the placement's PARAMETERS, from A[1] up. A[0] is a general
                per-type state slot, used as one by at least three handlers.
      Block B   the handler's RUNTIME COUNTERS.

    EntityHandlers' type 32 block shows the pairing slot by slot. }
  EF_BLOCK_LEN = 10;
  EF_STATE     = $08;   { block A[0]: per-type state, not a parameter }

  GRAVITY           = 8;      { added to EF_VEL_Y each frame, in 1/32 pixel }
  TERMINAL_VELOCITY = $200;   { 512, i.e. 16 pixels per frame }

  { EF_TOUCH_KIND and EF_CLASS are adjacent, come from adjacent type table
    columns, and are easy to conflate: one says what touching the player
    does, the other how the entity dies. }
  EF_TOUCH_KIND = $32;

  { +0x90 is HIT POINTS. Entity_TakeProjectileHits subtracts the projectile's
    own +0x90 from it and clamps at zero; the stun is the +0x70/+0x74 pair,
    set to 8 on every hit. }

  { Projectile-hit handling scans actor slots 1..$20 for each minor entity.

    EF_VULN_KIND decides what a hit does, and it is a wide switch: kinds 2, 4,
    5, 6, 7 and $5A..$5D each behave differently, several of them gated on the
    projectile's own EF_BLOCK_A, which acts as its power or element. Only the
    common path is translated here. }
  EF_VULN_KIND  = $35;   { +0xD4, from type table column 6 }
  EF_HIT_SOUND  = $38;   { +0xE0, from type column 9 }
  HIT_STUN_FRAMES = 8;

  { These runtime tile offsets alias the last two type-specific fields. Both
    fields initialize to zero for every entity type. }

  ENTITY_TYPE_COUNT  = 81;
  ENTITY_TYPE_FIELDS = 18;

type
  { Origin uses the same biased 1/32-pixel units as entity positions. Delta is
    the layer movement during the current frame. }
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
  { Raw storage preserves the fixed layout while some fields remain unknown. }
  TEntity = record
    Raw: array[0..ENTITY_INTS - 1] of Integer;
  end;
  PEntity = ^TEntity;

  { Services and shared state used by entity handlers. Tile collision returns
    the encountered tile, while solid collision reports displacement through
    PushX, PushY, and OnTopOfSolid. }
  { Declared ahead of TEntityWorld because Entity_Destroy reaches other
    entities by slot, and the pool is defined further down. }
  TEntityPool = class;

  { Axis-aligned collision box in screen pixels. }
  TBox = record L, T, R, B: Integer; end;

  { Collision-facing tile access. Implementations use linear X + Y * Width
    indexing; an X outside the row can therefore address an adjacent row. }
  TTileSource = class
  public
    function TileAt(TileX, TileY: Integer): Integer; virtual; abstract;
  end;

  { Sprite operations required by entity creation, updates, and destruction. }
  TSpriteSink = class
  public
    { The default implementation disables sprite allocation. }
    function AllocSprite(AnimId: Integer): Integer; virtual;
    procedure ReleaseSprite(Handle: Integer); virtual;

    procedure SetVisible(Handle: Integer; Visible: Boolean); virtual; abstract;
    function  GetVisible(Handle: Integer): Boolean; virtual; abstract;
    procedure SetAnim(Handle, AnimId: Integer); virtual; abstract;
    function  Width(Handle: Integer): Integer; virtual; abstract;
    function  Height(Handle: Integer): Integer; virtual; abstract;
    procedure SetPos(Handle, X, Y: Integer); virtual; abstract;
    procedure SetDepth(Handle, Depth: Integer); virtual; abstract;
  end;

  { Callback for state that must be sampled at the point of use. }
  TWorldQuery = function: Boolean of object;

  TEntityWorld = class
  private
    FFading: Boolean;
    FOnFading: TWorldQuery;
    function GetFading: Boolean;
  public
    PushX, PushY: Integer;
    OnTopOfSolid: Boolean;
    SolidThreshold: Integer;
    { Tile index that kills an entity on contact. }
    KillTile: Integer;
    { Fading is sampled on demand so sound decisions use the current state. }

    { Current entity layer and terrain profile. }
    Layer: TLayerInfo;
    TerrainId: Integer;

    { Nil disables cross-entity bookkeeping during destruction. }
    Pool: TEntityPool;

    { Nil when the world does not draw entities. }
    Sprites: TSpriteSink;

    { Nil represents a world with no collidable terrain. }
    Tiles: TTileSource;

    { Scrolling selects whether motion is applied to the layer origin or the
      entity position during tile queries. }
    { DeltaY lets horizontal probes inspect the row above or below the entity,
      such as when a walker checks for a platform edge. }
    property Fading: Boolean read GetFading write FFading;
    property OnFading: TWorldQuery read FOnFading write FOnFading;

    function TileAtX(const E: TEntity; Delta: Integer;
                     Scrolling: Boolean;
                     DeltaY: Integer = 0): Integer; virtual;
    function TileAtY(const E: TEntity; Delta: Integer;
                     Scrolling: Boolean): Integer; virtual;
    function EdgeDistX(const E: TEntity; Delta: Integer): Integer; virtual;
    function EdgeDistY(const E: TEntity; Delta: Integer): Integer; virtual;

    { AgainstPlayer restricts the collision scan to the player slot. }
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
    procedure DestroyEntity(var E: TEntity; DropLoot: Boolean); virtual;

    { Event hooks default to an unattached event table. }
    function EventOpcode(EventId: Integer): Integer; virtual;
    function EventProgressIndex(EventId: Integer): Integer; virtual;
    procedure BeginEvent(EventId, Arg: Integer); virtual;
    procedure ClearEventEntity(EventId: Integer); virtual;
    procedure SetProgress(Index: Integer); virtual;
    { EntityUpdate_Type15_Switch rewrites its own event's OPCODE - a switch that has
      been thrown becomes opcode 9, which no longer triggers anything. The
      event table is the entity system's, not the interpreter's, so it comes
      through the world like the rest. }
    procedure SetEventOpcode(EventId, Opcode: Integer); virtual;
    { The player's difficulty, 0..2. Several enemy handlers index a
      three-entry table with it - EntityUpdate_Type30_Akuji doubles its speed on 2,
      and type 31 has three separate tables keyed by it. The player state is
      not otherwise reachable from a handler, so it comes through here. }
    function PlayerDifficulty: Integer; virtual;
    procedure SetSpawnField(Slot, IntIndex, Value: Integer); virtual; abstract;
    procedure SpawnDebris(const E: TEntity; Kind: Integer); virtual;

    { Gives the entity a roughly 30 percent chance to drop an item. }
    procedure MaybeDropItem(const E: TEntity); virtual;
    procedure PlaySound(Id: Integer); virtual; abstract;
    { Player_Update's fall-death arm stops the music before the death
      sound - FUN_00450CBC with a fade of 0. Abstract on purpose: a
      no-op default is how the other silent-audio bugs happened. }
    procedure StopMusic; virtual; abstract;
    { Overridable to support deterministic simulations. }
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
    { Where Spawn takes an entity's sprite from. Nil means no sprite pool, in
      which case every entity spawns without one - which is what every
      existing test does, and it is why extents have to be set by hand there. }
    Sprites: TSpriteSink;

    procedure Clear;

    { X and Y are logical pixels. Returns SLOT_NONE when the selected partition
      is full. }
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

    { Periodically turns one step toward the player, then refreshes velocity
      from the direction table on every call. }
    procedure Steer(Slot, TimerSlot, Reload: Integer);

    property Alive[Index: Integer]: Boolean read GetAlive;
  end;

const
  { Per-type defaults copied into new entities. A sprite id of -1 disables
    sprite allocation for that type. }
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

{ Returns an all-zero record for an unknown type id. }
function EntityType(Id: Integer): TEntityType;

{ Pixel position with the fixed-point bias removed and rounded toward zero. }
function EntityPixelX(const E: TEntity): Integer;
function EntityPixelY(const E: TEntity): Integer;

{ Margin scales with the entity extent. }
function IsOffScreen(const E: TEntity; Margin: Integer): Boolean;

{ Converts a layer origin to pixels without removing POSITION_BIAS. }
function OriginPixel(Raw: Integer): Integer;

{ Distance in 1/32-pixel units to the next tile edge on each axis. }
function TileEdgeDistX(const E: TEntity; const L: TLayerInfo;
                       Delta: Integer): Integer;
function TileEdgeDistY(const E: TEntity; const L: TLayerInfo;
                       Delta: Integer): Integer;

{ Moves V toward zero by Step without crossing zero. }
procedure ApproachZero(var V: Integer; Step: Integer);

{ Returns the first solid tile in the path of DeltaMain, or TILE_NONE.

  The leading edge is swept across every tile occupied on the other axis, with
  DeltaCross shifting that span.

  A zero delta returns TILE_NONE, so stationary entities are not tested.

  Scrolling applies DeltaMain to the layer origin instead of the entity. The
  distinction matters when fixed-point fractions round across a pixel edge. }
function EntityTileCollideX(const E: TEntity; const L: TLayerInfo;
                            Tiles: TTileSource; SolidThreshold: Integer;
                            DeltaX, DeltaY: Integer;
                            Scrolling: Boolean): Integer;
function EntityTileCollideY(const E: TEntity; const L: TLayerInfo;
                            Tiles: TTileSource; SolidThreshold: Integer;
                            DeltaY, DeltaX: Integer;
                            Scrolling: Boolean): Integer;

{ Sweeps the tiles covered by the entity and starts fall-death when it touches
  the configured kill tile.

  This runs during vertical camera movement only. A match uses the tile's low
  16 bits, and stops the current row scan after a hit.

  The routine has no meaningful result, so it is represented as a procedure.
  Kill-tile values are defined in Stages.pas. }
procedure EntityCheckKillTiles(var E: TEntity; const L: TLayerInfo;
                               Tiles: TTileSource; KillTile: Integer);

{ Entity-to-entity collision uses the
  EF_HITBOX_INSET_* box, not the EF_BOX_OFS_* one tile collision uses;
  getting those the wrong way round would be silent and wrong.

  Both boxes retain POSITION_BIAS during pixel conversion, so the shared offset
  cancels in comparisons. }
function EntityBox(const E: TEntity; ScaleX, ScaleY: Integer): TBox;
function EntitiesOverlap(const A, B: TEntity;
                         ScaleX, ScaleY: Integer): Boolean;

{ Axis-aligned overlap with a per-axis margin that shrinks the test area. }
function RectOverlap(const A, B: TBox; ShrinkX, ShrinkY: Integer): Boolean;

{ Converts a biased fixed-point position to pixels, rounding toward zero. }
function PixelOf(Raw: Integer): Integer;

{ Three-way comparison: -1 when B < A, 1 when A < B, otherwise 0. }
function Compare(A, B: Integer): Integer;

{ Two-way comparison. Equal values return +1, allowing callers to choose a
  direction instead of stopping. }
function CompareNZ(A, B: Integer): Integer;

{ Halves an extent with signed rounding toward zero. }
function HalfExtent(V: Integer): Integer;

{ Delphi-compatible Random(N), exposed for deterministic replay. }
function DelphiRandom(N: Integer): Integer;

var
  { Set this seed to replay a random sequence. }
  RandomSeed: Cardinal = 0;

  { Updated once per frame by Entity_UpdateAll. }
  EntitiesLive:  Integer = 0;
  EntitiesDrawn: Integer = 0;

  { Counts dispatcher fall-throughs. Valid entity types 0, 18, and 20 have no
    handler; every mapped type must leave this counter unchanged. }
  EntitiesUnhandled: Integer = 0;

implementation


function TSpriteSink.AllocSprite(AnimId: Integer): Integer;
begin
  Result := SPRITE_NONE;
end;

procedure TSpriteSink.ReleaseSprite(Handle: Integer);
begin
end;

function OriginPixel(Raw: Integer): Integer;
begin
  Result := Raw div (1 shl POSITION_SHIFT);
end;


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

function CompareNZ(A, B: Integer): Integer;
begin
  if B < A then
    Result := -1
  else
    Result := 1;
end;

function TileEdgeDistX(const E: TEntity; const L: TLayerInfo;
                       Delta: Integer): Integer;
var
  LayerOriginPx, TileW, EntityPx, HalfWidth, EdgeWorldPx: Integer;
begin
  { A zero delta has no edge direction. }
  Result := 0;
  if Delta = 0 then
    Exit;
  { POSITION_BIAS is a whole number of shipped 32-pixel tiles, so retaining it
    does not change the distance to the next edge. }
  LayerOriginPx := OriginPixel(L.OriginX);
  TileW := L.TileW;
  if TileW = 0 then
    Exit;
  EntityPx := OriginPixel(E.Raw[EF_POS_X]);
  HalfWidth := HalfExtent(E.Raw[EF_EXTENT_X]);
  if Delta < 0 then
  begin
    EdgeWorldPx := (LayerOriginPx mod TileW) + (EntityPx - HalfWidth)
                   + E.Raw[EF_BOX_OFS_X] + E.Raw[EF_TILE_OFS_X];
    Result := ((EdgeWorldPx div TileW) * TileW - EdgeWorldPx)
              shl POSITION_SHIFT;
  end
  else
  begin
    EdgeWorldPx := (LayerOriginPx mod TileW)
                   + ((EntityPx + HalfWidth) - E.Raw[EF_BOX_OFS_X])
                   + E.Raw[EF_TILE_OFS_X] - 1;
    Result := (((EdgeWorldPx div TileW + 1) * TileW - 1) - EdgeWorldPx)
              shl POSITION_SHIFT;
  end;
end;

function TileEdgeDistY(const E: TEntity; const L: TLayerInfo;
                       Delta: Integer): Integer;
var
  LayerOriginPx, TileH, EntityPx, HalfHeight, EdgeWorldPx: Integer;
begin
  Result := 0;
  if Delta = 0 then
    Exit;
  LayerOriginPx := OriginPixel(L.OriginY);
  TileH := L.TileH;
  if TileH = 0 then
    Exit;
  EntityPx := OriginPixel(E.Raw[EF_POS_Y]);
  HalfHeight := HalfExtent(E.Raw[EF_EXTENT_Y]);
  if Delta < 0 then
  begin
    EdgeWorldPx := (LayerOriginPx mod TileH) + (EntityPx - HalfHeight)
                   + E.Raw[EF_BOX_OFS_Y] + E.Raw[EF_TILE_OFS_Y];
    Result := ((EdgeWorldPx div TileH) * TileH - EdgeWorldPx)
              shl POSITION_SHIFT;
  end
  else
  begin
    EdgeWorldPx := (LayerOriginPx mod TileH)
                   + ((EntityPx + HalfHeight) - E.Raw[EF_BOX_OFS_Y])
                   + E.Raw[EF_TILE_OFS_Y] - 1;
    Result := (((EdgeWorldPx div TileH + 1) * TileH - 1) - EdgeWorldPx)
              shl POSITION_SHIFT;
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
  LeadingEdgePx, LayerDeltaX, EntityDeltaX, CrossAxisPx: Integer;
  Row, LastRow, Column, TileId: Integer;
begin
  Result := TILE_NONE;
  if (DeltaX = 0) or (L.TileW = 0) or (L.TileH = 0) then
    Exit;

  { The leading edge, as a pixel offset from the entity's centre. The two arms
    are not symmetric: the right edge carries a -1 because it is the last pixel
    INSIDE the box, not the first one past it. }
  if DeltaX < 0 then
    LeadingEdgePx := E.Raw[EF_BOX_OFS_X] - HalfExtent(E.Raw[EF_EXTENT_X])
                     + E.Raw[EF_TILE_OFS_X]
  else
    LeadingEdgePx := HalfExtent(E.Raw[EF_EXTENT_X]) - E.Raw[EF_BOX_OFS_X]
                     + E.Raw[EF_TILE_OFS_X] - 1;

  if Scrolling then
  begin
    LayerDeltaX  := DeltaX;
    EntityDeltaX := 0;
  end
  else
  begin
    LayerDeltaX  := 0;
    EntityDeltaX := DeltaX;
  end;

  { The rows the box spans, with DeltaCross applied. Each term is converted to
    pixels on its own - not summed first - which is what makes Scrolling a
    rounding decision. }
  CrossAxisPx := OriginPixel(L.OriginY)
                 + OriginPixel(E.Raw[EF_POS_Y] + DeltaY);
  Row := (CrossAxisPx - HalfExtent(E.Raw[EF_EXTENT_Y])
          + E.Raw[EF_BOX_OFS_Y] + E.Raw[EF_TILE_OFS_Y]) div L.TileH;
  LastRow := (CrossAxisPx + HalfExtent(E.Raw[EF_EXTENT_Y])
              - E.Raw[EF_BOX_OFS_Y] + E.Raw[EF_TILE_OFS_Y] - 1) div L.TileH;

  Column := (OriginPixel(L.OriginX + LayerDeltaX)
             + OriginPixel(E.Raw[EF_POS_X] + EntityDeltaX) + LeadingEdgePx)
            div L.TileW - TILE_BIAS_TILES;

  while Row <= LastRow do
  begin
    TileId := Tiles.TileAt(Column, Row - TILE_BIAS_TILES);
    if TileId >= SolidThreshold then
      Exit(TileId);
    Inc(Row);
  end;
end;

function EntityTileCollideY(const E: TEntity; const L: TLayerInfo;
                            Tiles: TTileSource; SolidThreshold: Integer;
                            DeltaY, DeltaX: Integer;
                            Scrolling: Boolean): Integer;
var
  LeadingEdgePx, LayerDeltaY, EntityDeltaY, CrossAxisPx: Integer;
  Column, LastColumn, Row, TileId: Integer;
begin
  Result := TILE_NONE;
  if (DeltaY = 0) or (L.TileW = 0) or (L.TileH = 0) then
    Exit;

  if DeltaY < 0 then
    LeadingEdgePx := E.Raw[EF_BOX_OFS_Y] - HalfExtent(E.Raw[EF_EXTENT_Y])
                     + E.Raw[EF_TILE_OFS_Y]
  else
    LeadingEdgePx := HalfExtent(E.Raw[EF_EXTENT_Y]) - E.Raw[EF_BOX_OFS_Y]
                     + E.Raw[EF_TILE_OFS_Y] - 1;

  if Scrolling then
  begin
    LayerDeltaY  := DeltaY;
    EntityDeltaY := 0;
  end
  else
  begin
    LayerDeltaY  := 0;
    EntityDeltaY := DeltaY;
  end;

  CrossAxisPx := OriginPixel(L.OriginX)
                 + OriginPixel(E.Raw[EF_POS_X] + DeltaX);
  Column := (CrossAxisPx - HalfExtent(E.Raw[EF_EXTENT_X])
             + E.Raw[EF_BOX_OFS_X] + E.Raw[EF_TILE_OFS_X]) div L.TileW;
  LastColumn := (CrossAxisPx + HalfExtent(E.Raw[EF_EXTENT_X])
                 - E.Raw[EF_BOX_OFS_X] + E.Raw[EF_TILE_OFS_X] - 1) div L.TileW;

  Row := (OriginPixel(L.OriginY + LayerDeltaY)
          + OriginPixel(E.Raw[EF_POS_Y] + EntityDeltaY) + LeadingEdgePx)
         div L.TileH
         - TILE_BIAS_TILES;

  while Column <= LastColumn do
  begin
    TileId := Tiles.TileAt(Column - TILE_BIAS_TILES, Row);
    if TileId >= SolidThreshold then
      Exit(TileId);
    Inc(Column);
  end;
end;

function DelphiRandom(N: Integer): Integer;
begin
  RandomSeed := Cardinal(RandomSeed * RANDOM_MULT + 1);
  Result := Integer(Cardinal((UInt64(Cardinal(N)) * UInt64(RandomSeed)) shr 32));
end;

function TEntityWorld.RandomBelow(N: Integer): Integer;
begin
  Result := DelphiRandom(N);
end;

function TEntityWorld.GetFading: Boolean;
begin
  if Assigned(FOnFading) then
    Result := FOnFading()
  else
    Result := FFading;
end;

function TEntityWorld.TileAtX(const E: TEntity; Delta: Integer;
                             Scrolling: Boolean;
                             DeltaY: Integer): Integer;
begin
  if Tiles = nil then
    Exit(TILE_NONE);
  Result := EntityTileCollideX(E, Layer, Tiles, SolidThreshold, Delta, DeltaY,
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
  FirstSlot, LastSlot, Slot, CurrentSlot: Integer;
  Candidate: PEntity;
begin
  Result := SLOT_NONE;
  if Pool = nil then
    Exit;
  CurrentSlot := E.Raw[EF_SLOT];
  if AgainstPlayer then
  begin
    FirstSlot := PLAYER_SLOT;
    LastSlot := PLAYER_SLOT;
  end
  else
  begin
    FirstSlot := SOLID_SCAN_FIRST;
    LastSlot := SOLID_SCAN_LAST;
  end;

  for Slot := FirstSlot to LastSlot do
  begin
    if Slot = CurrentSlot then
      Continue;
    Candidate := Pool.Entity(Slot);
    if (Candidate^.Raw[EF_ALIVE] and $FF) = 0 then
      Continue;
    if Candidate^.Raw[EF_SOLID] = 0 then
      Continue;
    { The air dash goes through a particular kind of solid. }
    if (E.Raw[EF_STATE] = SOLID_STATE_AIRDASH)
       and (Candidate^.Raw[EF_VULN_KIND] = SOLID_PHASE_VULN) then
      Continue;
    if (Candidate^.Raw[EF_SOLID] = SoftKind) and SkipSoft then
      Continue;

    Other := EntityBox(Candidate^, 1, 1);
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
  if Slot <> PLAYER_SLOT then     { only the player can push against a solid }
    Exit;
  EventId := Pool.Entity(Blocker)^.Raw[EF_EVENT_ID];
  Op := EventOpcode(EventId);
  if ((Op = EVENT_OPCODE_PUSH) and (Axis <> 0))
  or ((Op = EVENT_OPCODE_PUSH_CONFIRM) and ConfirmPressed) then
    BeginEvent(EventId, EVENT_BEGIN_FROM_DESTROY);
end;

function TEntityWorld.SolidCollideX(const E: TEntity; Delta: Integer;
                                    SkipSoft: Boolean;
                                    AgainstPlayer: Boolean): Boolean;
var
  MovedBox, BlockingBox: TBox;
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
  MovedBox := EntityBox(Moved, 1, 1);

  Blocker := FindBlockingSolid(E, MovedBox, SOLID_SOFT_IN_X, SkipSoft,
                               AgainstPlayer, BlockingBox);
  if Blocker = SLOT_NONE then
    Exit;

  if MovedBox.L < BlockingBox.L then
    PushX := -Abs(MovedBox.R - BlockingBox.L) shl POSITION_SHIFT
  else
    PushX := Abs(MovedBox.L - BlockingBox.R) shl POSITION_SHIFT;
  Result := True;

  MaybePushEvent(E.Raw[EF_SLOT], Blocker, AxisX);
end;

function TEntityWorld.SolidCollideY(const E: TEntity; Delta: Integer;
                                    SkipSoft: Boolean;
                                    AgainstPlayer: Boolean): Boolean;
var
  MovedBox, BlockingBox: TBox;
  Moved: TEntity;
  Blocker, OverlapPx: Integer;
  BlockingEntity: PEntity;
begin
  OnTopOfSolid := False;
  Result := False;
  { Zero-delta checks keep a resting entity aware of its supporting platform. }
  if (E.Raw[EF_ALIVE] and $FF) = 0 then
    Exit;

  Moved := E;
  Inc(Moved.Raw[EF_POS_Y], Delta);
  MovedBox := EntityBox(Moved, 1, 1);

  Blocker := FindBlockingSolid(E, MovedBox, SOLID_SOFT_IN_Y, SkipSoft,
                               AgainstPlayer, BlockingBox);
  if Blocker = SLOT_NONE then
    Exit;

  if MovedBox.T < BlockingBox.T then
  begin
    { Coming down onto it. }
    OverlapPx := Abs(MovedBox.B - BlockingBox.T);
    if OverlapPx < SOLID_TOP_TOLERANCE then
    begin
      OnTopOfSolid := True;
      Pool.SetField(Blocker, EF_RIDDEN, 1);
    end;

    { Riding: the horizontal offset between the two, WITH this frame's layer
      scroll folded in, so a rider is carried along by a moving platform. }
    BlockingEntity := Pool.Entity(Blocker);
    PushX := ((OriginPixel(BlockingEntity^.Raw[EF_POS_X] + Layer.DeltaX)
               - HalfExtent(BlockingEntity^.Raw[EF_EXTENT_X]))
              - (OriginPixel(E.Raw[EF_POS_X])
                 - HalfExtent(E.Raw[EF_EXTENT_X]))) shl POSITION_SHIFT;

    PushY := -OverlapPx shl POSITION_SHIFT;
  end
  else
    PushY := Abs(MovedBox.T - BlockingBox.B) shl POSITION_SHIFT;
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

procedure TEntityWorld.SetEventOpcode(EventId, Opcode: Integer);
begin
end;

function TEntityWorld.PlayerDifficulty: Integer;
begin
  Result := 0;
end;

procedure TEntityWorld.DestroyEntity(var E: TEntity; DropLoot: Boolean);
var
  OwnerSlot, ChildSlot, EventId, Opcode, ProgressIndex: Integer;
begin
  { A dying projectile hands a shot back to whoever fired it. }
  if (E.Raw[EF_CLASS] = DESTROY_CLASS_PROJECTILE) and (Pool <> nil) then
  begin
    OwnerSlot := E.Raw[EF_OWNER];
    Pool.SetField(OwnerSlot, EF_SHOTS,
                  Pool.Field(OwnerSlot, EF_SHOTS) - 1);
  end;

  { A parent takes its children with it. Recursive, and deliberately WITHOUT
    loot - the children were never separately earned. }
  if (E.Raw[EF_CLASS] = DESTROY_CLASS_PARENT) and (Pool <> nil) then
  begin
    ChildSlot := E.Raw[EF_CHILD_A];
    if ChildSlot <> 0 then
      DestroyEntity(Pool.Entity(ChildSlot)^, False);
    ChildSlot := E.Raw[EF_CHILD_B];
    if ChildSlot <> 0 then
      DestroyEntity(Pool.Entity(ChildSlot)^, False);
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
    Opcode := EventOpcode(EventId);
    if (Opcode = EVENT_OPCODE_DESTROY) and DropLoot then
      BeginEvent(EventId, EVENT_BEGIN_FROM_DESTROY);
    if (Opcode = EVENT_OPCODE_FLAG) and DropLoot then
    begin
      ProgressIndex := EventProgressIndex(EventId);
      if ProgressIndex >= 0 then
        SetProgress(ProgressIndex);
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
      { Released sprite slots are hidden and reset to neutral depth. }
      Sprites.ReleaseSprite(E.Raw[EF_SPRITE]);
    end;
    E.Raw[EF_SPRITE] := SPRITE_NONE;
  end
  else
    E.Raw[EF_SPRITE] := SPRITE_NONE;
end;

procedure TEntityWorld.MaybeDropItem(const E: TEntity);
var
  DropRoll, SpawnedSlot: Integer;
begin
  DropRoll := RandomBelow(DROP_ROLL);
  if DropRoll <= DROP_THRESHOLD then
    Exit;

  { Drops use the parent's position without compensating for layer movement. }
  SpawnedSlot := Spawn(EKIND_MINOR, DROP_TYPE,
                       E.Raw[EF_POS_X] - POSITION_BIAS,
                       E.Raw[EF_POS_Y] - POSITION_BIAS);
  if SpawnedSlot = SLOT_NONE then
    Exit;

  SetSpawnField(SpawnedSlot, EF_TIMER, DROP_TIMER);
  SetSpawnField(SpawnedSlot, EF_VEL_Y, DROP_LIFT);
  SetSpawnField(SpawnedSlot, EF_FLAG1C, Ord(DropRoll > DROP_RARE));
end;

procedure TEntityWorld.SpawnDebris(const E: TEntity; Kind: Integer);
var
  ParticleIndex, SpawnedSlot, HorizontalDirection, Speed: Integer;
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

  for ParticleIndex := 0 to EF_DEBRIS_SPEEDS - 1 do
  begin
    { The layer delta is SUBTRACTED from the spawn position. The particle is
      created after this frame's scroll has been applied to its parent but
      before Entity_UpdateAll carries it along too, so taking the delta back
      out is what stops it being scrolled twice on its first frame. }
    SpawnedSlot := Spawn(EKIND_MINOR, EF_DEBRIS_TYPE,
                         E.Raw[EF_POS_X] - POSITION_BIAS - Layer.DeltaX,
                         E.Raw[EF_POS_Y] - POSITION_BIAS - Layer.DeltaY);

    { A full minor-entity partition drops the remaining particle. }
    if SpawnedSlot = SLOT_NONE then
      Continue;

    SetSpawnField(SpawnedSlot, EF_STATE, Kind + 1);

    HorizontalDirection := HalfExtent(DirVelX(RandomBelow(DIR_COUNT)));
    Speed := RandomBelow(DEBRIS_SPEED_MAX) + 1;
    SetSpawnField(SpawnedSlot, EF_VEL_X, HorizontalDirection * Speed);
    SetSpawnField(SpawnedSlot, EF_VEL_Y,
                  (ParticleIndex + 4) * -DEBRIS_LIFT);

    SetSpawnField(SpawnedSlot, EF_SCREEN_SPACE, 0);
    SetSpawnField(SpawnedSlot, EF_DEPTH, DEBRIS_DEPTH);

    { The two effect kinds pick their frame differently: one at random, one
      by position in the burst, so a shatter fans through its frames in order. }
    if Kind = DEBRIS_IMPACT then
      SetSpawnField(SpawnedSlot, EF_FLAG1C, RandomBelow(2))
    else if Kind = DEBRIS_SHATTER then
      SetSpawnField(SpawnedSlot, EF_FLAG1C, ParticleIndex);
  end;
end;

procedure EntityCheckKillTiles(var E: TEntity; const L: TLayerInfo;
                               Tiles: TTileSource; KillTile: Integer);
var
  TopRow, BottomRow, LeftColumn, RightColumn, Row, Column: Integer;
  OriginX, OriginY, PositionX, PositionY, HalfWidth, HalfHeight: Integer;
begin
  if (Tiles = nil) or (L.TileW = 0) or (L.TileH = 0) then
    Exit;

  OriginX := OriginPixel(L.OriginX);
  OriginY := OriginPixel(L.OriginY);
  PositionX := OriginPixel(E.Raw[EF_POS_X]);
  PositionY := OriginPixel(E.Raw[EF_POS_Y]);
  HalfWidth := HalfExtent(E.Raw[EF_EXTENT_X]);
  HalfHeight := HalfExtent(E.Raw[EF_EXTENT_Y]);

  TopRow := (OriginY + PositionY - HalfHeight + E.Raw[EF_BOX_OFS_Y]
             + E.Raw[EF_TILE_OFS_Y]) div L.TileH;
  BottomRow := (OriginY + PositionY + HalfHeight - E.Raw[EF_BOX_OFS_Y]
                + E.Raw[EF_TILE_OFS_Y] - 1) div L.TileH;
  LeftColumn := (OriginX + PositionX - HalfWidth + E.Raw[EF_BOX_OFS_X]
                 + E.Raw[EF_TILE_OFS_X]) div L.TileW;
  RightColumn := (OriginX + PositionX + HalfWidth - E.Raw[EF_BOX_OFS_X]
                  + E.Raw[EF_TILE_OFS_X] - 1) div L.TileW;

  for Row := TopRow to BottomRow do
    for Column := LeftColumn to RightColumn do
      if (Tiles.TileAt(Column - TILE_BIAS_TILES, Row - TILE_BIAS_TILES)
          and $FFFF) = KillTile then
      begin
        E.Raw[EF_STATE] := KILL_TILE_STATE;
        E.Raw[EF_BLOCK_B] := 0;
        Break;                 { Continue with the next row. }
      end;
end;

function EntityBox(const E: TEntity; ScaleX, ScaleY: Integer): TBox;
var
  Width, Height: Integer;
begin
  Width := E.Raw[EF_EXTENT_X] * ScaleX;
  Height := E.Raw[EF_EXTENT_Y] * ScaleY;
  { OriginPixel, not EntityPixelX - see the header: the bias stays in. }
  Result.L := OriginPixel(E.Raw[EF_POS_X]) - HalfExtent(Width)
              + E.Raw[EF_HITBOX_INSET_X];
  Result.T := OriginPixel(E.Raw[EF_POS_Y]) - HalfExtent(Height)
              + E.Raw[EF_HITBOX_INSET_Y];
  Result.R := Result.L + Width - 2 * E.Raw[EF_HITBOX_INSET_X];
  Result.B := Result.T + Height - 2 * E.Raw[EF_HITBOX_INSET_Y];
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
  FieldIndex: Integer;
begin
  if (Id < 0) or (Id >= ENTITY_TYPE_COUNT) then
  begin
    for FieldIndex := 0 to ENTITY_TYPE_FIELDS - 1 do
      Result.Raw[FieldIndex] := 0;
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
  Slot: Integer;
begin
  Result := 0;
  for Slot := 0 to ENTITY_COUNT - 1 do
    if FSlots[Slot].Raw[EF_ALIVE] <> 0 then
      Inc(Result);
end;

procedure TEntityPool.Kill(Slot: Integer);
begin
  SetField(Slot, EF_ALIVE, 0);
end;

procedure TEntityPool.Steer(Slot, TimerSlot, Reload: Integer);
var
  EntityPtr: PEntity;
  CurrentDirection, TargetDirection: Integer;
begin
  if (Slot < 0) or (Slot >= ENTITY_COUNT) then
    Exit;
  if (TimerSlot < 0) or (TimerSlot >= EF_TIMER_COUNT) then
    Exit;
  EntityPtr := @FSlots[Slot];

  Dec(EntityPtr^.Raw[EF_BLOCK_B + TimerSlot]);
  if EntityPtr^.Raw[EF_BLOCK_B + TimerSlot] < 1 then
  begin
    EntityPtr^.Raw[EF_BLOCK_B + TimerSlot] := Reload;
    { The shared position bias cancels inside AngleBetween. }
    TargetDirection := AngleBetween(
      EntityPtr^.Raw[EF_POS_X], EntityPtr^.Raw[EF_POS_Y],
      FSlots[PLAYER_SLOT].Raw[EF_POS_X], FSlots[PLAYER_SLOT].Raw[EF_POS_Y]);
    CurrentDirection := EntityPtr^.Raw[EF_FACING];
    TurnToward(CurrentDirection, TargetDirection);
    EntityPtr^.Raw[EF_FACING] := CurrentDirection;
  end;

  EntityPtr^.Raw[EF_VEL_X] := DirVelX(EntityPtr^.Raw[EF_FACING]);
  EntityPtr^.Raw[EF_VEL_Y] := DirVelY(EntityPtr^.Raw[EF_FACING]);
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
    { DIVERGENCE DIV-003: reject unknown partition kinds deterministically. }
    Exit;
  end;

  Slot := SLOT_NONE;
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
  E^.Raw[EF_OWNER] := 0;
  E^.Raw[EF_ALIVE] := 1;
  E^.Raw[EF_TYPE]  := TypeId;

  { Reset both ten-element runtime state blocks. }
  for I := 0 to EF_BLOCK_LEN - 1 do
  begin
    E^.Raw[EF_BLOCK_A + I] := 0;
    E^.Raw[EF_BLOCK_B + I] := 0;
  end;

  E^.Raw[EF_ANIM_ID] := 0;
  E^.Raw[EF_VARIANT] := 0;
  E^.Raw[EF_FLAG1C]  := 0;
  E^.Raw[EF_SPRITE]    := SPRITE_NONE;
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
  E^.Raw[EF_DEATH_TIMER] := 0;
  E^.Raw[EF_PARKED_VEL]  := 0;
  E^.Raw[$2D]          := 0;
  E^.Raw[EF_EXTENT_X]  := 0;
  E^.Raw[EF_EXTENT_Y]  := 0;

  { Then the type table is copied over those defaults. }
  T := EntityType(TypeId);
  E^.Raw[EF_ANIM_ID]  := T.Raw[TYPE_COL_ANIM_ID];
  E^.Raw[EF_TYPEF_04] := T.Raw[TYPE_COL_HP];
  E^.Raw[EF_TYPEF_08] := T.Raw[TYPE_COL_DEPTH];
  for I := 0 to 3 do
    E^.Raw[EF_TYPEF_0C + I] := T.Raw[TYPE_COL_TOUCH_KIND + I];
  for I := 0 to TYPE_COL_TAIL_COUNT - 1 do
    E^.Raw[EF_TYPEF_20 + I] := T.Raw[TYPE_COL_NO_DROP + I];

  { An entity's EXTENTS come off its sprite every frame, and every collision
    box is built from those - so a spawn without one has no size and collides
    with nothing. Three of the eighty-one types ask for TYPE_COL_ANIM_ID = -1 and
    are meant to be that way.

    A full sprite pool FAILS THE SPAWN, alive flag and all, which is what
    makes the pool size a hard limit rather than a guard. }
  if (Sprites <> nil) and (T.Raw[TYPE_COL_ANIM_ID] <> SPRITE_NONE) then
  begin
    I := Sprites.AllocSprite(T.Raw[TYPE_COL_ANIM_ID]);
    if I = SPRITE_NONE then
    begin
      E^.Raw[EF_ALIVE] := 0;
      Exit(SLOT_NONE);
    end;
    E^.Raw[EF_SPRITE] := I;
  end;

  Result := Slot;
end;

function PixelOf(Raw: Integer): Integer;
begin
  { `div`, not `shr`: Pascal's shr on an Integer is LOGICAL and so is wrong
    for anything left of or above the origin. Do not give POSITION_ROUND a
    type either - being untyped is what widens this to Int64. }
  Result := (Raw - POSITION_BIAS) div (1 shl POSITION_SHIFT);
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
  PixelX, PixelY, MarginX, MarginY: Integer;
begin
  PixelX := EntityPixelX(E);
  PixelY := EntityPixelY(E);
  MarginX := E.Raw[EF_EXTENT_X] * Margin;
  MarginY := E.Raw[EF_EXTENT_Y] * Margin;
  Result := (PixelX < -MarginX) or (PixelX > MarginX + SCREEN_W)
            or (PixelY < -MarginY) or (PixelY > MarginY + SCREEN_H);
end;

initialization
  { A layout slip silently misaligns every slot after the first, so fail at
    startup. NOT Assert: FPC compiles assertions out without -Sa and this
    project does not pass it, so an Assert here would never run.
    --selftest-layouts checks these sizes and every field offset besides. }
  if SizeOf(TEntity) <> ENTITY_BYTES then
    raise Exception.CreateFmt('TEntity is %d bytes; the original indexes the '
      + 'pool as base + index * %d and the layout must match',
      [SizeOf(TEntity), ENTITY_BYTES]);
  if SizeOf(TEntityType) <> $48 then
    raise Exception.CreateFmt('TEntityType is %d bytes; the type table steps '
      + '0x48 per entry and the layout must match', [SizeOf(TEntityType)]);

end.
