# GameState_Reset @ 0x004653C8 - what the reconstruction does NOT clear

`GameSession.ResetState` reproduces the reset. Four things the original does
there have no counterpart, and each is unobservable rather than forgotten.

## 0x0046D29C

`GameState_Reset` is the ONLY function in the binary that touches it - nothing
reads it, ever. A counterpart would be a variable that exists to be cleared and
never examined. Left unmodelled deliberately.

## The other two layers

The `mode <> 2` clear walks THREE layers in the original and zeroes each tile
component's scroll at +0x6034/+0x6038 as well as the layer record. This engine
models ONE layer, and no shipped stage row uses layers 1 or 2 - every one of
the 66 has -1 in csv 3 and 4 - so the other two are never populated and
clearing them cannot be observed.

## The two objects freed through 0x0046D1F0 and 0x0046CEA4

The first is the power-up panel surface, which this build loads once at startup
instead of per-use (see `PowerUp_Show`).

The second is the ENDING SCREEN'S SCRATCH SURFACE: `DDDD1Init` zeroes it,
`Ending_Update` frees and rebuilds it - a run of `FUN_00451560` blits composes
the results screen into it - and `FormDestroy` frees it too. `Ending.pas`
models the results and the unlocks and allocates no surface of its own, so as
with the panel there is nothing here to free.

## No extras

`SavedMenuIndex := 0` used to sit beside `MenuIndex` in the reconstruction and
was removed: 0x0046D2C0 is SavedMenuIndex and `GameState_Reset` never writes
it. Harmless either way - `EnterPause` overwrites it from `MenuIndex` before
anything reads it back - but the standard is that nothing exists here which the
original does not do.
