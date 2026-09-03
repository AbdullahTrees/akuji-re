# The player controller: Player_Update @ 0x004585A8

Moved out of src/gameplay/PlayerState.pas on 2026-09-01; the unit keeps the state map
and the ability table, this keeps the working-out.

{ ===========================================================================
The player controller - Player_Update @ 0x004585A8, the 

type 1 handler.

Ghidra could not find this one: it is frameless, so Function Start Search
never matched it, and it had to be created explicitly. It is the single
largest piece of game behaviour in the binary.

## The state machine

The state lives in the entity's EF_STATE (block A[0]) and drives everything:

    0   on the ground, walking or standing
    1   dashing
    2   airborne
    3   landing recovery
    4   wall kick
    5   attacking
    6   gliding      - Player_UpdateGlide     0x004593B0
    7   air dashing  - Player_UpdateAirDash   0x00459624
    8   knocked back - Player_UpdateKnockback 0x00459828
    9   dying - after 0x79 frames, GameState := 100 (game over)
   10   dying by falling - spawns debris, then the same

States 9 and 10 both end at GameState 100, which is the game-over screen
recovered earlier from a completely different direction.

## The dash is a double tap, and the game says so

In state 0, pressing a direction stores it and opens a 30-frame window. Press
the SAME direction again inside that window, with the ability flag at
PlayerState[4] set, and the state becomes 1 with sound 21 - puu01.wav.

tk001.dat, the game's own tutorial text, reads:

    "Press the arrow key twice to perform a Dash move."

Three independent sources agreeing - the code, the sound table, and the
script the game shows the player - is about as good as evidence gets here.

Dashing moves at dir shl 6 against dir shl 5 walking, so exactly double.

## The three delegated states, and the four abilities

States 6, 7 and 8 are handled by their own functions rather than inline. All
three were frameless and had to be created by hand.

6 - GLIDE, entered from the air by pressing UP with no horizontal input,
    after having jumped. Gravity is 2 instead of 4, a fresh jump PRESS adds
    -0x20 of lift (an edge - the test is Button and not ButtonLatch, so
    HOLDING does nothing), and steering is +-4 per frame capped at +-0x40 - a
    quarter of walking speed. A four-frame wing flap, A-B-C-B. Touching
    anything ends it: effect, sound 9, back to state 0.

7 - AIR DASH, entered from the air by pressing DOWN, same conditions. It has
    NO gravity term at all - it is purely horizontal, launched at the facing
    direction times 8 and bled off by 8 per frame until it stops. It also
    sets both EF_TIMER and EF_DEATH_TIMER to 0xE10, and Entity_SolidCollideX
    and ...Y both skip solids whose EF_VULN_KIND is 0x5C while the mover is
    in state 7: you pass through those while dashing. Ends on contact or when
    the speed reaches zero: effect, sound 10, state 3 with a 15-frame
    recovery.

8 - KNOCKBACK. No input is read at all and there is no animation, just one
    sprite per facing. It falls at the ordinary GRAVITY of 8 - faster than
    the player's own 4 - and on landing goes to state 3 with a 30-frame
    recovery. If Lives has reached 0 by then it instead spawns three souls at
    headings 0, 0x14 and 0x28, plays sound 12 and enters state 9.

Each of 6 and 7 is gated on an ABILITY BYTE, and so are the dash and the wall
kick. Game_StartOrLoad sets all four to zero on a new game; nothing else in
the binary writes them, so they are set by the event scripts as the game is
played.

    Head[4]  double-tap dash      state 1
    Head[5]  wall kick            state 4
    Head[6]  air dash             state 7
    Head[7]  glide                state 6

The shipped mid-game save has Head[4] = 1 and Head[5..7] = 0, which is what a
progression that teaches the dash first should look like - and tk001.dat, the
game's own tutorial text, teaches exactly the dash. Three sources agreeing.

## Every sound matches its name

Not one of these was chosen to fit; they are what the handler passes, and the
names come from the array recovered during the audio work:

    jump                 3   jump.wav
    land, hard           4   yuka01.wav      (yuka is Japanese for floor)
    attack               5   shot01.wav
    charge reaches full  6   power01.wav
    charged shot         7   shot02.wav
    land, soft           8   yuka02.wav
    dash starts         21   puu01.wav
    death               12   voice02.wav

The hard/soft landing split is on fall distance: the handler counts frames of
downward motion in block A[3], capped at 0x5A, and divides by 3. Under 11 it
plays the soft sound; at or over, the hard one plus two type-3 dust entities
thrown left and right.

## Attacking

Two attacks share state 5, chosen by how long the button is held:

  tapped   sound 5, one type 2 projectile
  held     a counter climbs to 60; sound 6 fires at exactly 60, and every 8th
           frame before that spawns a type 5 spark. Releasing after 60 plays
           sound 7 and fires a faster projectile.

## The sprite tables

Every state picks its sprite out of a table indexed by (Facing shr 5), i.e.
0 for right and 1 for left. The six tables are CONTIGUOUS in the image, in
state order, with no gaps:

    0x0046BB9C   5 per side   ground and dash    states 0, 1
    0x0046BBC4   5 per side   rise, fall, land, wall kick, attack
    0x0046BBEC   4 per side   glide              state 6
    0x0046BC0C   2 per side   air dash           state 7
    0x0046BC1C   1 per side   knockback          state 8
    0x0046BC24   1 per side   death              state 9
    0x0046BC2C   end

Each table's width is exactly the frame count its handler cycles through, and
every table ends precisely where the next begins. Getting any stride wrong
would break that fit somewhere along the chain.

In the first two tables the right-facing sprite is always the left-facing one
PLUS TEN - 10/0, 11/1, 15/5, 19/9 and so on - so sprites 0..9 are one facing
of the base character and 10..19 the other. That relation is what fixes the
index order as right-then-left rather than the reverse, and it is checked by
--selftest-player.

Both attacks are limited by a weapon table, reached through the pointer at
0x0046CD44 and living at 0x00468E84, indexed by the current weapon in
PlayerState +0x11CC, with 16-byte records:

    +0x00  how many of this shot may exist at once
    +0x04  speed, multiplied by the direction table entry
    +0x08  the value written to the projectile's block A[0]
    +0x0C  the projectile's lifetime

=========================================================================== }
