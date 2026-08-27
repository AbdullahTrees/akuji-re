# Function Map — Akuji the Demon

## Legend

| Prefix | Meaning |
|--------|---------|
| ✅ | Confirmed by cross-references and context |
| 🔶 | Likely (inferred from context, needs verification) |
| ❌ | Not yet analyzed |
| ⛔ | Borland VCL/RTL — statically linked library code, **do not port** |

> ⚠️ **The ✅ marks in this file are not yet trustworthy.** An entire section
> ("Game Loop") was marked ✅ but turned out to be Borland's tooltip
> implementation, not game code — see the VCL Hint section below. Those names had
> been guessed from the Win32 API each function calls, without cross-function
> context. Any entry named after a single Win32 import should be re-verified the
> same way: read its callers and callees and check whether the cluster matches a
> known `Forms.pas` / `Controls.pas` routine before trusting it.

## The address-range rule

Delphi links its own units before the program's, so library code sits at low
addresses and the game's own code follows it. This holds throughout the binary
and is the fastest sanity check on any name:

| Range | Contents |
|-------|----------|
| `0x402xxx`–`0x408xxx` | Delphi RTL (`System.pas`) — ⛔ |
| `0x417xxx`–`0x425xxx` | VCL (`Graphics.pas`, `Controls.pas`) — ⛔ |
| `0x439xxx`–`0x443xxx` | VCL (`Forms.pas`) — ⛔ |
| `0x444xxx` and above | The game's own code |

**A game-sounding name below `0x444000` is wrong until proven otherwise.** Every
misidentification found so far has been in that range; every spot-check above it
has held up.

## Entry Point Chain — ⛔ all VCL

All previously-listed entries were misnamed. Corrected:

| Address | Name | Confidence | Description |
|---------|------|------------|-------------|
| `004060d0` | `Delphi_RTL_Init` | ✅ | Delphi runtime initialization |
| `004428f4` | `TApplication_Initialize` | ✅ | `if InitProc <> nil then TProcedure(InitProc)` — nothing else |
| `00442510` | `TApplication_SetTitle` | ✅ | Generic `Title` property setter (`SetWindowTextA`). Not Akuji-specific |
| `0044290c` | `TApplication_CreateForm` | ✅ | Generic `CreateForm`; assigns `FMainForm` if the instance inherits from `TForm` |
| `0044298c` | `TApplication_Run` | ✅ | `FRunning := True; ... repeat HandleMessage until Terminated` |
| `004427f8` | `TApplication_HandleMessage` | ✅ | `if not ProcessMessage(Msg) then Idle(Msg)` |
| `00442760` | `TApplication_ProcessMessage` | 🔶 | Takes a `TMsg`; the actual `PeekMessage`/`DispatchMessage` pump |
| `00442f8c` | `TApplication_Idle` | 🔶 | Idle branch of `HandleMessage` |

### Correction: `004038f4` was never a message loop

Previously listed as `VCL_Message_Loop` — "Windows message pump
(PeekMessage/DispatchMessage)". It contains **no message-pump calls at all**. It
runs finalization handlers, emits `"Runtime error at 00000000"` on failure, and
ends in `ExitProcess`. It is `System._Halt0` — the process *shutdown* path.

Renamed here to `Delphi_Halt0`. The real pump is `TApplication_ProcessMessage`
above, reached via `TApplication_Run`.

## ✅ FOUND: the game's entry point — `entry` @ `004671ac`

The standard Delphi `.dpr` program block. Everything above is Borland's; this is
where Akuji starts:

```c
void entry(void)
{
  Delphi_RTL_Init(&LAB_00466ee4);
  TApplication_Initialize();
  TApplication_SetTitle(Application, "Akuji the Demon");
  TApplication_CreateForm(Application, PTR_PTR_00464b54, MainForm);
  TApplication_Run(Application);
  Delphi_Halt0();            // confirms 004038f4 = _Halt0
}
```

Corresponding to:

```pascal
begin
  Application.Initialize;
  Application.Title := 'Akuji the Demon';
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
```

| Symbol | Meaning |
|--------|---------|
| `PTR_PTR_00464b54` | the main form's **metaclass (VMT)** — the game's class |
| `MainForm` (`0046ce38`) | the main form **instance**; ~100 read sites, all in `0x455xxx`–`0x463xxx` |
| `PTR_DAT_0046d074` | the global `Application` pointer (indirect) |

**The entire game is one `TForm` subclass.** `MainForm` is the central object; its
fields seen so far include `+0x2D0` (a graphics/font object) and `+0x2DC` (audio).

### Game code — confirmed genuine

| Address | Name | Confidence | Description |
|---------|------|------------|-------------|
| `004671ac` | `entry` | ✅ | Delphi program block — the real entry point |
| `00456038` | `TitleMenu_Update` | 🔶 | Menu state machine (states 1–4); literal `"Yes       No  "` prompt, routes to `SaveGame_Select_Slot` |
| `00451004` | `Game_DrawTextOutlined` | ✅ | `(x, y, text, outlineColor, fillColor, fontSize, target)` — draws text 4× at ±1 offsets for the outline, then once centred. Uses "MS Sans Serif" |

## Game Loop

Not yet identified. (The functions previously listed here were VCL tooltip code —
see below.)

## VCL Hint (Tooltip) System — ⛔ Borland RTL, not game code

Methods on the global `Application: TApplication` object (`DAT_0046e7c8`),
statically linked from Delphi's `Forms.pas`. **None of this gets ported to SDL** —
it implements hover tooltips for VCL controls.

Identified by matching the cluster against Borland's shipped source: the
`StopHintTimer` / `HintTimerExpired` / `HideHint` / `CancelHint` bodies are
line-for-line matches, and `TApplication_ActivateHint` sends `0xB030`, which is
exactly `CM_HINTSHOW` (`CM_BASE`+48).

| Address | Name | Confidence | Description |
|---------|------|------------|-------------|
| `004412d4` | `VCL_HintTimerProc` | ✅ | `TIMERPROC` wrapping `HintTimerExpired` in a Delphi `try..except` |
| `00443414` | `TApplication_HintTimerExpired` | ✅ | Dispatches on `FTimerMode` (+0x79): 0 = show hint, 1 = hide hint |
| `004432b0` | `TApplication_StartHintTimer` | ✅ | `StopHintTimer`, then `SetTimer`; `CancelHint` if it fails |
| `004432e8` | `TApplication_StopHintTimer` | ✅ | Kills the hint timer, clears `FTimerHandle` |
| `00443308` | `TApplication_HintMouseMessage` | ✅ | Hover tracking; queries the control for its pause via `CM_HINTSHOWPAUSE` |
| `00443664` | `TApplication_ActivateHint` | ✅ | Builds `THintInfo`, sends `CM_HINTSHOW`, fires `OnShowHint`, shows the window |
| `00443610` | `TApplication_RecreateHintWindow` | ✅ | Recreates `FHintWindow` when `HintWindowClass` changed |
| `00443448` | `TApplication_HideHint` | ✅ | `ShowWindow(FHintWindow.Handle, SW_HIDE)` |
| `00443484` | `TApplication_CancelHint` | ✅ | Hides, nils `FHintControl`, clears `FHintActive`, unhooks, stops timer |
| `004434bc` | `VCL_GetCursorHeightMargin` | ✅ | Scans the cursor's AND-mask to place the tip below the pointer |
| `004413c8` | `VCL_InstallHintHooks` | ✅ | Installs `WH_GETMESSAGE` hook + event + watcher thread |
| `0044143c` | `VCL_UninstallHintHooks` | ✅ | Teardown twin of the above (same three globals) |

### `TApplication` field layout (partial)

Set this up as a struct in Ghidra's Data Type Manager and retype `param_1` on any
one of these — the decompiler propagates it across all of them at once.

| Offset | Field | Type | Source |
|--------|-------|------|--------|
| `+0x24` | `FHandle` | HWND | `SetWindowTextA` target in `SetTitle` |
| `+0x38` | `FMainForm` | TForm* | assigned in `CreateForm`, read in `Run` |
| `+0x3C` | `FMouseControl` | TControl* | `if FShowHint and (FMouseControl = nil) then CancelHint` in `Idle` |
| `+0x48` | `FHintActive` | Boolean | hint cluster |
| `+0x4B` | `FShowMainForm` | Boolean | gates the show/minimize branch in `Run` |
| `+0x4C` | `FHintColor` | TColor | hint cluster |
| `+0x50` | `FHintControl` | TControl* | hint cluster |
| `+0x54` | `FHintCursorRect` | TRect (16 bytes) | hint cluster |
| `+0x64` | `FHintHidePause` | Integer | hint cluster |
| `+0x68` | `FHintPause` | Integer | hint cluster |
| `+0x70` | `FHintShortPause` | Integer | hint cluster |
| `+0x74` | `FHintWindow` | THintWindow* | hint cluster |
| `+0x78` | `FShowHint` | Boolean | hint cluster |
| `+0x79` | `FTimerMode` | TTimerMode (0=show, 1=hide) | hint cluster |
| `+0x7A` | `FTimerHandle` | Word | hint cluster |
| `+0x7C` | `FTitle` | AnsiString | `SetTitle` |
| `+0x8C` | `FTerminate` | Boolean | `repeat HandleMessage until Terminated` |
| `+0x94` | *(unidentified)* | Boolean | branch selector in `SetTitle` |
| `+0x95` | `FRunning` | Boolean | set 1 on entry to `Run`, 0 on exit |
| `+0xC0` | `FOnMessage` | TMessageEvent (Self at `+0xC4`) | fired per message in `ProcessMessage` |
| `+0xD8` | `FOnIdle` | TIdleEvent (Self at `+0xDC`) | fired in `Idle` before `WaitMessage` |
| `+0x108` | `FOnShowHint` | TShowHintEvent (code ptr, then Self at `+0x10C`) | hint cluster |

Delphi method pointers are always a **(code, Self) pair** — the `short` test at
`+0xC2` / `+0xDA` / `+0x10A` that guards each call is Delphi's `Assigned()` check
on the pair. Three of them now follow the same shape, which is a good pattern to
recognise elsewhere in the binary.

**`+0x95` is resolved.** It was the unknown field gating `VCL_InstallHintHooks`;
`TApplication_Run` sets it to 1 on entry and 0 on exit, which is `FRunning`. The
hint hooks are only installed while the app is running — which is exactly what
that guard is for.

## Rendering (GDI + DirectDraw)

| Address | Name | Confidence | Description |
|---------|------|------------|-------------|
| `0044ab24` | `DirectDraw_Init` | ✅ | DirectDraw 7 initialization (cooperative level, display mode) |
| `004475f4` | `DDraw_Create_Surface` | ✅ | Creates DirectDraw surfaces (primary, backbuffer, offscreen) |
| `00449ca4` | `Get_Display_BitDepth` | ✅ | Gets current display bit depth |
| `00446734` | `DDraw_Check_HRESULT` | ✅ | Checks HRESULT and shows error message on failure |
| `00417fd4` | `VCL_MaskedBlt` ⛔ | ✅ | **Not the game's blitter.** `Graphics.pas` transparent-blit helper — `MaskBlt`, then the classic SRCAND (`0x8800C6`) / SRCINVERT (`0x660046`) fallback. Address is in the VCL range |

## Audio (DirectSound + KBGM)

| Address | Name | Confidence | Description |
|---------|------|------------|-------------|
| `0044f8a4` | `DirectSound_Init` | ✅ | DirectSound initialization |
| `0044fbd8` | `KBGMOpen` | ✅ | KBGM audio engine — open |
| `0044fbe0` | `KBGMClose` | ✅ | KBGM audio engine — close |
| `0044fbe8` | `KBGMPlay` | ✅ | KBGM audio engine — play |
| `0044fbf0` | `KBGMStop` | ✅ | KBGM audio engine — stop |
| `0044fbf8` | `KBGMFree` | ✅ | KBGM audio engine — free |
| `0044fc00` | `KBGMLoadFile` | ✅ | KBGM audio engine — load file |
| `0044fc08` | `KBGMInit` | ✅ | KBGM audio engine — init |
| `0044fc10` | `KBGMGetInfo` | ✅ | KBGM audio engine — get info |
| `0044fc18` | `KBGMSetVolume` | ✅ | KBGM audio engine — set volume |
| `0044fc20` | `KBGMSendSysx` | ✅ | KBGM audio engine — send sysex |
| `0044fc28` | `KBGMFadeIn` | ✅ | KBGM audio engine — fade in |
| `0044fc30` | `KBGMFadeOut` | ✅ | KBGM audio engine — fade out |
| `0044fc38` | `KBGMSetRepeat` | ✅ | KBGM audio engine — set repeat |

## Input (DirectInput)

| Address | Name | Confidence | Description |
|---------|------|------------|-------------|
| `00453bdc` | `DirectInput_Init` | ✅ | DirectInput 7 initialization |

## Game State

| Address | Name | Confidence | Description |
|---------|------|------------|-------------|
| `004653c8` | `GameState_Reset` | ✅ | Resets all game state to defaults |
| `0046214c` | `Stage_Init` | ✅ | Initializes a new stage/level |
| `00462f40` | `Game_Init_PlayerState` | ✅ | Initializes player state struct (0x11E4 bytes) |
| `0045509c` | `SaveGame_Select_Slot` | ✅ | Save slot selection UI |
| `00463154` | `Game_CheckSaveExists` | ✅ | Checks if a save file exists |

## Data Loading

| Address | Name | Confidence | Description |
|---------|------|------------|-------------|
| `00465a1c` | `Load_Stage_Assets` | ✅ | Orchestrates all asset loading for a stage |
| `00465e9c` | `Load_Surface_Textures` | ✅ | Loads surface textures from `data\surf\` |
| `004660b8` | `Load_Sprite_Sheets` | ✅ | Loads sprite sheets from `data\spr\` |
| `00466340` | `Load_Tile_Data` | ✅ | Loads tile data from `data\tk\` |
| `00465b50` | `Load_Event_Scripts` | ✅ | Loads event scripts from `data\ev\` |
| `004645b0` | `Configure_Stage_Params` | ✅ | Sets stage-specific parameters (timer, boss HP) |

## Entity System

| Address | Name | Confidence | Description |
|---------|------|------------|-------------|
| `0044e1b8` | `Entity_Create` | ✅ | Creates a new entity (VMT + 3 params + name) |
| `0044e224` | `FUN_0044e224` | 🔶 | Entity property setter (index + value) |
| `0044e25c` | `FUN_0044e25c` | 🔶 | Entity property setter (index + 4 values) |

## Delphi RTL Helpers

| Address | Name | Confidence | Description |
|---------|------|------------|-------------|
| `004026d8` | `Delphi_GetMem` | ✅ | Delphi memory allocation |
| `004026f0` | `Delphi_FreeMem` | ✅ | Delphi memory deallocation |
| `00402da4` | `Delphi_TObject_Free` | ✅ | Delphi TObject.Free |
| `00406a50` | `Delphi_FillChar` | ✅ | Delphi FillChar |
| `00403cf8` | `Delphi_AnsiString_Assign` | ✅ | Delphi AnsiString assignment |
| `00403e60` | `Delphi_AnsiString_AddRef` | ✅ | Delphi AnsiString reference counting |
| `00407f64` | `Delphi_IntToStr` | ✅ | Delphi IntToStr |
| `00407ff8` | `Delphi_FileOpen` | ✅ | Delphi file open |
| `0040805c` | `Delphi_FileRead` | ✅ | Delphi file read |
| `00408088` | `Delphi_FileWrite` | ✅ | Delphi file write |
| `004080c0` | `Delphi_FileClose` | ✅ | Delphi file close |

## Audit status

Every entry below `0x444000` has now been re-read. Results:

**Misidentified as game code, actually Borland's (⛔):** the 12 hint functions,
the 5 entry-chain entries, `004038f4` (shutdown, not a message loop), and
`00417fd4` (VCL blitter, not the game's). **19 total.**

**Spot-checked and confirmed genuine:** `Get_Display_BitDepth` (`00449ca4` —
`GetDeviceCaps(BITSPIXEL)`, exact), `Load_Stage_Assets` (`00465a1c`),
`GameState_Reset` (`004653c8`), `DirectDraw_Init` (`0044ab24`). All sit above
`0x444000`, consistent with the range rule.

**Not yet re-verified:** the remaining Rendering, Audio, Input, Game State, Data
Loading, and Entity System entries. All are above `0x444000`, so they are far
more likely to be sound — but they were named by the same process, so treat ✅
there as 🔶 until read.

The `KBGM*` block (`0044fbd8`–`0044fc38`) is 8-byte-spaced stubs — an import
thunk table for a KBGM audio DLL. Those names came from real exported symbols and
are trustworthy.

## Total: 49 functions annotated
## The three-layer structure (2026-08-03)

Class names recovered from Delphi RTTI in the binary show the program is three
distinct layers, not two. Only the innermost is Akuji's:

| Layer | Classes | Functions | Fate |
|-------|---------|-----------|------|
| Borland RTL + VCL | `TObject`, `TCanvas`, `TForm`, `TApplication`, … | ~1597 | ⛔ skip — replaced by FPC RTL + LCL |
| Third-party DirectX suite | `TDDDDSurface`, `TDDDDCanvas`, `TDDDDSprite`, `TDDSDWave3D`, `TDDSDChannel`, `TDDIDDebugOption`, `TKbgmPlayer`, `TD3DOptions` | ~191 | ⛔ replace wholesale — do not port |
| **The game** | **`TFrm_main`** + its units | **~83** | ✏️ this is what you write |

The component/game boundary (`0x455000`) is approximate — `Game_DrawTextOutlined`
at `0x451004` is game code sitting below it — so treat the game figure as ~80–110.
Either way it is **~5% of the binary**, not 1871 functions.

`TFrm_main` is the main form class; its metaclass is `PTR_PTR_00464b54`, its
instance is `MainForm` (`0046ce38`), and `entry` (`004671ac`) creates it.

### ✅ RESOLVED: the D3DRM dependency is not the game's

`akuji.exe` statically imports `Direct3DRMCreate`, so `d3drm.dll` must be present
or the process will not load — but the game is purely 2D and never uses it.

The import belongs to the **DirectX component suite**, which supports an optional
Direct3D retained-mode path (`TD3DOptions`). In `DirectDraw_Init` the D3DRM calls
sit behind `if ((param_2 == '\0') && (mode != 0))`; the shipped `system.ini` has
`fullscreen=off`. The interface is stored at wrapper field `+0xd0`, used for
exactly two vtable calls (`+0x44`, `+0x50`) in init, and released in `FUN_0044975c`.

**Porting cost: zero.** The component layer is being replaced anyway, and the
D3DRM dependency leaves with it. This closes the largest open risk in the port.

## Frame-loop internals (2026-08-27)

| Address | Name | Evidence |
|---|---|---|
| `00464d30` | `TFrm_main_AppIdle` | the frame loop; `Done := False`, state dispatch, present, spin-wait |
| `00465584` | `TFrm_main_DDDD1Init` | loads settings, installs `Application.OnIdle` |
| `00449e78` | `TDDDD_Clear` | 100-byte `DDBLTFX` + `BackColor` (+0x4C), surface vtable `+0x14` = `Blt` |
| `00449d00` | `TDDDD_Present` | vtable `+0x2C` = `Flip` when fullscreen; else 124-byte `DDSURFACEDESC2` + `Blt` to window origin |
| `00448918` | `TDDDD_DrawSprite` | `(surface, x, y, transparent, srcRect)` |
| `00461ba8` | `HUD_Draw` | `"%3d/%-3d"` counter, `"%.2d:%.2d:%.2d"` timer, life-icon loops |
| `004511ec` | `Game_DrawText` | takes x, y, colour index and a string |
| `00451004` | `Game_DrawTextOutlined` | draws 4x at +/-1 for outline, then centred |

### `p_PlayerState` @ `0x0046cff0` — the 0x11E4 struct from `Game_Init_PlayerState`

| Offset | Meaning |
|---|---|
| `+0x11B4` | current lives/health (clamped to 0..`+0x11B8`) |
| `+0x11B8` | maximum lives/health |
| `+0x11BC` | elapsed seconds — HUD renders it as `h:mm:ss` |
| `+0x11C4` | counter shown as `%3d/%-3d` |
| `+0x11DC` | index into the table at `0x0046d2b4` |

## State handlers (2026-08-27, cont.)

| Address | Name | Evidence |
|---|---|---|
| `00461ee4` | `PauseMenu_Update` | dims 320x240, 3 options; confirm branches to saved state / 10 / 999 |
| `00462210` | `Stage_Begin` | `GameState_Reset`, `Load_Stage_Assets`, spawns player, sets state 60 |
| `00466e4c` | `Input_ConfirmPressed` | returns 1 on confirm; same use in title and pause menus |
| `00450fd8` | `TDDSD_PlaySound` | called as `(MainForm.DDSD1, id, 1)` — confirms `+0x2DC` |

Globals: `p_PauseMenuIndex` `0x46cf88` (0..2), `p_SavedGameState` `0x46cbbc`.

More `p_PlayerState` fields, from `Stage_Begin`:
`+0x11A4`/`+0x11A8` spawn tile X/Y, `+0x11AC`/`+0x11B0` scroll X/Y, `+0x11D8`
passed to the spawned entity.

## Name audit of the Load_* / Stage_* pass (2026-08-27)

Every remaining name from the original unverified pass was checked against the
filename its function actually builds. Method: disassemble the entry, resolve
pushed pointers as Delphi string literals (length at -4).

| Address | Old name | Verdict |
|---|---|---|
| `465e9c` | `Load_Surface_Textures` | ✅ builds `data\surf%.03d.dat` |
| `4660b8` | `Load_Sprite_Sheets` | ✅ builds `data\spr%.03d.dat` |
| `465b50` | `Load_Event_Scripts` | ✅ builds `data\ev%.03d.dat` |
| `466340` | ~~`Load_Tile_Data`~~ | ❌ → **`Load_Map`**, builds `map\%.03d.map` |
| `46214c` | ~~`Stage_Init`~~ | ❌ → **`Title_Init`**; resets, loads asset set 0, starts music, sets 57 channel volumes, → state 20 |
| `462330` | `FUN_00462330` | → **`Title_MainMenu`**; owns "NEW GAME"/"CONTINUE"/" OPTION "/"  EXIT  " |
| `463154` | ~~`Game_CheckSaveExists`~~ | ❌ → **`Opening_Update`**, the intro cutscene |

**Caution on the method:** scanning a fixed window past the entry overruns into
neighbouring functions and picks up their literals. That produced a false claim
that `Title_Init` owned the menu strings; the string xref showed they belong to
`Title_MainMenu`. Confirm ownership with an xref, not proximity.

### `Opening_Update` @ `0x463154` — the intro cutscene

10 slides. Per slide: load `op%.3d.bmp` from `bmp.qda` (or `bmp\op%.3d.bmp`
when `p_UseArchive` is 0), draw at (0x28, 8) sized 240x180, then two lines of
`Game_DrawTextOutlined` at y=200 and y=216. Slide duration is
`p_OpeningDurations[slide] * 60` frames. Music cues at slides 1, 8 and 9.
`Input_ConfirmPressed` skips.

Globals: `p_OpeningSlide` `0x46d298`, `p_OpeningTimer` `0x46d174`,
`p_OpeningImageIds` `0x46ce68`, `p_TextTable` `0x46cce4` (subtitle strings,
indexed via `0x46ce88`).

### Author

`"CREATED BY E.HASHIMOTO"` at `0x462dc4`, drawn by `Title_MainMenu`.

### Settings field confirmed

`p_Settings+0x24` (default 10) is **volume** — `Title_Init` applies it to all 57
sound channels as `(10 - value) * -0x1C2`.

## `Title_MainMenu` @ `0x00462330` — fully decoded

Three sub-modes on `p_TitleSubMode` (`0x46cef8`):

**0 — main menu.** Background `p_Surfaces[1]` full-screen. Items at x=`0xEE`,
y=`(i*2+0x11)*8`: NEW GAME, CONTINUE, ` OPTION `, `  EXIT  `. Cursor x=`0xE6`.
Credit string at (0, `0xD8`). Confirm: 0/1 → `GameState_Reset`, state `0x28`,
sub-mode records which; 2 → options; 3 → state 999.

**1 — options.** Background `p_Surfaces[2]`. Labels x=`0x28`, values x=`0xE8`,
rows y=`0x38 + row*0x10`, cursor x=`0xE0` y=`(i*2+7)*8`. Ten rows:

| Row | Controls | Range |
|---|---|---|
| 0 | game level | `p_Settings+0x04`, 0..2 |
| 1 | toggle | `0x46d268` |
| 2-4 | **key rebinding** | `p_KeyMap[0..2]`; polls 16 buttons, swaps if already bound |
| 5 | toggle | `0x46d2e4` |
| 6 | **frame limiter** | `p_FrameLimitOn` `0x46ce60` |
| 7 | volume | `p_Settings+0x24`, 0..10, reapplied to 57 channels |
| 8 | omake select | `p_Settings+0x28`, 0..6; confirm shows `omake%.02d.bmp` if `p_Settings[0x2C+i]` |
| 9 | exit | → menu, cursor on OPTION |

**2 — omake viewer.** Full-screen unlocked image; confirm returns to row 8.

`p_MenuIndex` (`0x46cf88`) is the shared cursor for title, options and pause —
it is not pause-specific, hence the rename from `p_PauseMenuIndex`.

## Bitmap font — solved

`Font_Define` `0x4511a0` fills a table at `0x46e8a4` (0x20 stride, multiple
fonts possible). `Title_Init` registers font 0:

```
Font_Define(0, p_Surfaces[0], $20, $140, 8, 8, 9, 9, $5F)
               surface  firstCh screenW adv cellH cellW lastCh
```

`Game_DrawText` `0x4511ec` `(fontIdx, x, y, centred, variant, text)`:

```
idx = ch - FirstChar
col = idx mod 32       srcX = col * CellW
row = idx div 32       srcY = row * CellH + CellH * Variant * 2
dest = (x + i * Advance, y)
centred: x = (ScreenW - Len*Advance) div 2
```

Verified against `font9x9-01.bmp`: 288x54 == exactly 32 cols x 6 rows of 9x9,
i.e. 3 colour variants x 2 rows x 32 glyphs. Range `$20..$5F` is 64 glyphs,
space through underscore — **no lowercase**, which is why every string in the
game is upper case.

Colours sampled from the sheet: black background (the colour key), a shared
dark-brown outline `(61,35,35)`, and per-variant fill — 0 white, 1 pink
`(255,123,123)`, 2 peach `(255,188,133)`.

Implemented as `src/GameFont.pas`. Glyphs are pre-cut into individual bitmaps
because LCL's `Draw` honours `TBitmap.Transparent` but `CopyRect` does not.
