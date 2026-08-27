## 🎯 SDL Porting Strategy — Akuji the Demon

> # 🛑 STOP — parts of this plan target the wrong functions
>
> A 2026-08-03 audit found that several functions this plan is built around are
> **Borland VCL library code, not the game's**. See `notes/function_map.md` for
> the evidence. Affected sections, and what's actually true:
>
> | This plan says | Reality |
> |---|---|
> | `GDI_Blit_Sprite` (`0x00417fd4`) is "the core sprite blitter" — §Rendering, lines ~37, 80–89, 191 | It's `Graphics.pas`'s transparent-blit helper. **The game's real blitter has not been found.** The whole rendering section targets Borland's code |
> | `VCL_Message_Loop` (`0x004038f4`) is the `PeekMessage`/`DispatchMessage` pump — line ~141 | It's `System._Halt0`, the **shutdown** path. It has no message-pump calls. The real pump is `TApplication_ProcessMessage` at `0x00442760` |
> | `Create_Main_Form` → `SDL_CreateWindow` — line ~136 | It's the generic `TApplication.CreateForm`, not the game's window setup |
> | `Game_Tick` → `SDL_GetMouseState` — line ~118 | It's `TApplication.HintTimerExpired` — tooltip code |
>
> Line ~261 actually corroborates this: it notes `DDraw_Check_HRESULT` calls
> `VCL_Message_Loop` **"(fatal abort)"**. A message loop invoked as a fatal abort
> makes no sense; `_Halt0` does. The evidence was already in the document.
>
> **Do not start Phase "Rendering" from this plan.** Find the game's own
> rendering code first — it will be above `0x444000`, per the address-range rule
> in `function_map.md`. Sections on Audio, Input, File I/O, and the general
> Delphi-porting challenges were not implicated and still look sound.

### Architecture Overview

The game is a **Borland Delphi** application using the VCL framework. The porting strategy is to keep all game logic intact and replace platform-specific API calls with SDL2 equivalents. Here's the complete mapping:

---

### ⚠️ Critical: Age-Related Porting Challenges

This binary was compiled circa 2000–2001 for **Windows 98/2000/ME/XP** on **32-bit x86** using **Borland Delphi (Object Pascal)**. Porting it to modern systems introduces several categories of challenges beyond simple API replacement:

#### A. Compiler & ABI Differences (Borland Delphi → Modern C/C++)

| Concern | Detail | Mitigation |
|---|---|---|
| **Calling convention** | Delphi uses `register` (Borland fastcall): first 3 params in EAX, EDX, ECX; rest on stack. Callee cleans stack. Modern C uses `cdecl` (caller cleans) or `stdcall` (callee cleans, params on stack). | All decompiled function signatures must be audited. Ghidra's decompiler may misrepresent parameter counts and types due to register-based passing. Each function's prototype must be verified against its call sites. |
| **String types** | Delphi uses `ShortString` (length-prefixed, 255-byte max), `AnsiString` (heap-allocated, ref-counted), and `WideString` (COM BSTR). C uses null-terminated `char*`. | String-manipulation functions (`lstrcpyA`, `lstrlenA`, `SysAllocStringLen`, etc.) must be wrapped. The `data\*.dat` files likely contain Pascal-style strings. |
| **Exception handling** | Delphi uses its own SEH-based exception model (`Try...Except...Finally`). Ghidra shows `RaiseException`, `RtlUnwind`, and `UnhandledExceptionFilter` imports. | Exception handling logic must be translated to C++ `try`/`catch` or removed if it's only RTL boilerplate. |
| **RTL initialization** | `Delphi_RTL_Init` sets up memory manager, thread-local storage (`TlsGetValue`/`TlsSetValue`), locale info, and FPU mask (`FPUMaskValue` registry key). | All RTL-dependent initialization must be replaced with standard C runtime equivalents or SDL platform abstractions. |
| **VCL class hierarchy** | The binary contains VCL class names in strings: `TNotifyEvent`, `TGraphicsObject`, `TFont`, `TMetafile`, `TProgressStage`, `TDragDropEvent`, etc. These are Delphi's object model with virtual method tables (VMTs). | VCL object layouts must be reconstructed as C structs with function pointer tables. The `TObject` base class uses a VMT pointer at offset 0. |
| **Set types** | Delphi `set of` types (e.g., `TShiftState`, `Anchors`, `BiDiMode`) are bitmasks stored as 1–4 bytes. Ghidra may decompile these as raw integer operations. | Identify and typedef all set types as `uint8_t`/`uint16_t`/`uint32_t` with named bit constants. |
| **Enumerated types** | Delphi enums default to 1-byte storage unless `{$MINENUMSIZE}` is set. Ghidra may treat them as `int`. | Verify enum sizes at each usage site to avoid struct layout mismatches. |
| **Dynamic arrays** | Delphi dynamic arrays are ref-counted heap objects with a length prefix at offset -4. Ghidra shows `LocalAlloc`/`LocalFree` patterns. | Replace with `std::vector` or manual malloc/free with explicit length tracking. |
| **Variant types** | `VariantChangeTypeEx`, `VariantCopyInd`, `VariantClear` imports indicate COM Variant usage (likely for OLE/ActiveX or interop). | Replace with `std::variant` or typed unions. |

#### B. Known Runtime Bugs & Compatibility Issues

| Issue | Symptom on Windows 11 | Root Cause | Fix Strategy |
|---|---|---|---|
| **Palette handling** | Wrong colors, psychedelic graphics | The game uses 8-bit indexed palettes (`SelectPalette`, `RealizePalette`, `GetSystemPaletteEntries`). Windows 11's display driver model no longer supports hardware palettes; GDI palette realization is emulated and unreliable. | Convert all 8-bit indexed surfaces to 32-bit RGBA at asset load time. Replace palette-based blits with direct color rendering. |
| **DirectDraw 7 deprecation** | Black screen, crash on launch | DirectDraw 7 was removed from Windows 8+. The game falls back to GDI when DD fails, but the fallback path may have bit-rot. | Replace entirely with SDL_Renderer. No DirectDraw dependency. |
| **Direct3D Retained Mode** | Crash or missing effects | `Direct3DRMCreate` — D3DRM was deprecated in DirectX 9 and removed entirely in later versions. The game uses it for optional 3D effects (`local_98 + 0xcc` flag). | Either drop D3DRM effects or reimplement with OpenGL/SDL_GPU. The 3D path appears optional (has fallback). |
| **DirectSound buffer size** | Audio stutter or silence | The game requests specific buffer sizes (`0x14` = 20 bytes for DSBUFFERDESC). Modern audio stacks may not honor these small buffer requests. | Use SDL_mixer with reasonable buffer sizes (1024–4096 samples). |
| **KBGM MIDI playback** | No music | KBGM likely uses the system MIDI mapper or a hardware MIDI device. Windows 11's software synth may not respond to the same SysEx messages (`KBGMSendSysx`). | Replace with SDL_mixer's built-in MIDI support (FluidSynth/Timidity) or convert BGM to OGG/MP3. |
| **Timer granularity** | Game runs too fast or too slow | `SetTimer` with the game's tick rate relies on the Windows message queue timer, which has ~10–16ms granularity. Modern systems may fire timers at different rates. | Replace with frame-delta timing using `SDL_GetTicks`. Cap frame rate with `SDL_Delay` for consistent speed. |
| **GDI ROP operations** | Transparency broken | `GDI_Blit_Sprite` uses ternary raster operations (`0x8800C6`, `0x660046`, `0xCC0020`, `0x440328`) for sprite transparency. These ROP codes interact with the framebuffer in ways that GDI emulation on modern Windows may not replicate correctly. | Replace with SDL2 alpha blending (`SDL_BLENDMODE_BLEND`). The ROP patterns must be analyzed to determine the intended compositing mode (source-over, mask, color-key). |
| **Fullscreen mode** | Alt-Tab crash, resolution issues | The game uses `SetWindowLongA` to toggle window styles and `DirectDraw_SetCooperativeLevel` for fullscreen exclusive mode. Modern compositing window managers (DWM) interfere with exclusive mode. | Use SDL2's borderless fullscreen window or `SDL_SetWindowFullscreen`. |
| **INI file paths** | Settings not saved | `GetPrivateProfileStringA`/`WritePrivateProfileStringA` write to `data\system.dat` and registry keys under `Software\Borland\Delphi\RTL`. Modern Windows may virtualize or block writes to the application directory. | Use SDL's preferred file I/O (`SDL_GetPrefPath`) for save data. |
| **Thread locale** | Crash on non-English systems | `SetThreadLocale`, `GetThreadLocale`, `EnumCalendarInfoA`, `CompareStringA` are used for locale-aware string operations. The Delphi RTL initializes locale from registry. | Replace with C++ locale or hardcode to UTF-8 (the game is English-only based on strings). |

#### C. Decompilation Artifacts & Code Cleanup Pass

The decompiled output from Ghidra contains artifacts that are **not** part of the original source code. A future pass must address:

| Artifact | Example | Cleanup |
|---|---|---|
| **Borland RTL boilerplate** | `FUN_004060d0` (RTL init), `FUN_004038f4` (message loop), `FUN_00403e60` (try...finally setup) | Replace with standard C equivalents or remove entirely. |
| **Register-based parameter passing** | Functions with `unaff_EBX`, `extraout_ECX`, `in_FS_OFFSET` variables | Reconstruct correct parameter lists by analyzing call sites and VCL calling conventions. |
| **VCL VMT calls** | `(**(code **)(*piVar1 + 0x2c))(piVar1, ...)` — these are virtual method dispatches through the VMT | Reconstruct the VMT layout for each class. Replace with direct function calls or C++ virtual methods. |
| **Delphi string operations** | `FUN_00403cf8` (string concatenation), `FUN_00407f64` (IntToStr), `FUN_00403d6c` (string assignment) | Replace with `std::string` or `snprintf`. |
| **Try...finally blocks** | `puStack_18 = &LAB_0044294a; uStack_20 = *in_FS_OFFSET; *in_FS_OFFSET = &uStack_20;` — this is Delphi's exception frame setup | Replace with C++ RAII or `try`/`catch`. |
| **Thunk functions** | `thunk_FUN_00402764` — these are linker-generated jump tables for DLL imports | Remove; call SDL functions directly. |
| **Inlined RTL functions** | Small utility functions like `FUN_00402da4` (FreeMem), `FUN_004026d8` (GetMem), `FUN_00406a50` (FillChar/memset) | Replace with standard library equivalents (`free`, `malloc`, `memset`). |
| **Global data pointers** | `PTR_DAT_0046d074`, `PTR_DAT_0046ce38`, etc. — these are Delphi global variables stored in the DATA/BSS segments | Reconstruct as named global variables with correct types. The `0046xxxx` range is the game's global state. |

#### D. Data File Format Considerations

The game's asset files (`data\*.dat`) are likely in a proprietary binary format:

| File | Probable Format | Notes |
|---|---|---|
| `data\stage.dat` | Stage definitions (tile maps, entity placements, triggers) | Must be reverse-engineered to load levels |
| `data\save.dat` | Save game data (binary blob) | Structure must be preserved for save compatibility |
| `data\system.dat` | INI-style configuration | Can be replaced with a modern config format |
| `data\ev\` | Event scripts (likely bytecode) | May need a script interpreter |
| `data\tk\` | Tile/terrain graphics | Likely raw pixel data with palette indices |
| `data\surf\` | Surface/background textures | Same as above |
| `data\spr\` | Sprite sheets/animations | May include frame metadata |

These formats must be documented and a loader written. The original game reads them via `CreateFileA`/`ReadFile` — the loading code itself reveals the format.

---

### 1. Rendering: GDI/DirectDraw → SDL_Renderer / SDL_Texture

| Original API | Call Sites | SDL Replacement |
|---|---|---|
| `DirectDrawCreateEx` | `DirectDraw_Init` (5 call sites) | `SDL_CreateWindow` + `SDL_CreateRenderer` |
| `StretchBlt` | `GDI_Blit_Sprite` (6 call sites) | `SDL_RenderCopy` with scaling |
| `BitBlt` | 6 call sites across 3 functions | `SDL_RenderCopy` |
| `MaskBlt` | `GDI_Blit_Sprite` | `SDL_SetTextureBlendMode(SDL_BLENDMODE_BLEND)` |
| `CreateCompatibleDC/Bitmap` | `GDI_Blit_Sprite` | `SDL_CreateTexture` |
| `SelectPalette/RealizePalette` | `GDI_Blit_Sprite` | `SDL_SetPaletteColors` (or convert to RGBA) |
| `SetTextColor/SetBkColor` | `GDI_Blit_Sprite` | `SDL_SetTextureColorMod` |
| `CreateDIBSection` | Surface creation | `SDL_CreateRGBSurface` |
| `GetDC/ReleaseDC` | Window management | `SDL_GetWindowSurface` |

**Key function to rewrite:** `GDI_Blit_Sprite` (at `0x00417fd4`) — this is the core sprite blitter using ROP raster operations for transparency. Replace with `SDL_RenderCopy` + alpha blending.

---

### 2. Audio: KBGM/DirectSound → SDL_mixer

| Original API | Call Sites | SDL Replacement |
|---|---|---|
| `DirectSoundCreate` | `DirectSound_Init` | `Mix_OpenAudio` |
| `KBGMOpen` | 1 call site (`FUN_00450870`) | `Mix_LoadMUS` (for MIDI/BGM) |
| `KBGMPlay` | 2 call sites (`FUN_00450ad8`) | `Mix_PlayMusic` |
| `KBGMStop` | 2 call sites | `Mix_HaltMusic` |
| `KBGMLoadFile` | Audio loading | `Mix_LoadWAV` / `Mix_LoadMUS` |
| `KBGMSetVolume` | Volume control | `Mix_VolumeMusic` / `Mix_Volume` |
| `KBGMFadeIn/FadeOut` | Fade effects | `Mix_FadeInMusic` / `Mix_FadeOutMusic` |
| `KBGMFree` | Cleanup | `Mix_FreeMusic` / `Mix_FreeChunk` |
| `KBGMInit/KBGMClose` | Init/shutdown | `Mix_Init` / `Mix_Close` |

**KBGM library** appears to be a custom MIDI/BGM engine (possibly "Koei BGM"). All 14 KBGM functions map cleanly to SDL_mixer equivalents.

---

### 3. Input: DirectInput → SDL_Event

| Original API | Call Sites | SDL Replacement |
|---|---|---|
| `DirectInputCreateA` | `DirectInput_Init` | `SDL_Init(SDL_INIT_JOYSTICK)` |
| DI keyboard device | `DirectInput_Init` | `SDL_GetKeyboardState` / `SDL_KEYDOWN` events |
| DI mouse device | `DirectInput_Init` | `SDL_GetMouseState` / `SDL_MOUSEMOTION` events |
| `GetCursorPos` | `Game_Tick` | `SDL_GetMouseState` |
| `GetKeyboardState` | Input polling | `SDL_PollEvent` loop |
| `SetWindowsHookExA` | Keyboard hook | Not needed — SDL provides events directly |

**Key mapping table** in `DirectInput_Init` (at `0x00453bdc`):
- DIK codes `0x2C-0x2E` (Z,X,C) → action buttons
- DIK codes `0x1E-0x20` (A,S,D) → secondary actions
- DIK codes `0x02-0x0B` (1-0 keys) → item/weapon selection
- DIK codes `0x39` (Space) → jump
- DIK codes `0xC8-0xCD` (Arrow keys) → movement
- DIK codes `0x47-0x51` (Numpad) → alternate movement

---

### 4. Windowing: Win32/VCL → SDL_Window

| Original API | Call Sites | SDL Replacement |
|---|---|---|
| `CreateWindowExA` | `Create_Main_Form` | `SDL_CreateWindow` |
| `RegisterClassA` | Window registration | Not needed |
| `GetDC/ReleaseDC` | DC management | `SDL_GetWindowSurface` |
| `SetWindowLongA` | Window style | `SDL_SetWindowFullscreen` etc. |
| `ShowWindow/UpdateWindow` | Display | `SDL_ShowWindow` |
| `PeekMessage/DispatchMessage` | `VCL_Message_Loop` | `SDL_PollEvent` loop |
| `SetTimer/KillTimer` | `Game_Timer_Callback` | `SDL_AddTimer` or frame-based delta |
| `MessageBoxA` | Error dialogs | `SDL_ShowSimpleMessageBox` |
| `GetSystemMetrics` | Screen info | `SDL_GetDesktopDisplayMode` |

---

### 5. File I/O: Win32 → stdio / SDL_RWops

| Original API | SDL Replacement |
|---|---|
| `CreateFileA/ReadFile/WriteFile` | `fopen`/`fread`/`fwrite` or `SDL_RWops` |
| `FindFirstFileA/FindNextFileA` | `dirent.h` (POSIX) or `SDL_filesystem` |
| `GetPrivateProfileStringA` (INI) | Custom INI parser or `SDL_RWops` |
| `WritePrivateProfileStringA` | Same |

---

### 6. Timing: Win32 → SDL

| Original API | SDL Replacement |
|---|---|
| `timeGetTime` (winmm) | `SDL_GetTicks` |
| `GetTickCount` | `SDL_GetTicks` |
| `Sleep` | `SDL_Delay` |
| `SetTimer` (game tick) | Frame-based delta timing in `SDL_PollEvent` loop |

---

### Revised Porting Phases

**Phase 0: Deep Static Analysis & Annotation**
- Complete function renaming for all ~1,500 functions
- Reconstruct VCL class layouts and VMTs
- Identify and type all global variables in the DATA/BSS segments
- Document all data file formats by tracing the file I/O code
- Map all Delphi RTL helper functions to standard C equivalents

**Phase 1: Stub Layer**
Create a thin compatibility header (`sdl_compat.h`) that maps:
- `HDC` → `SDL_Renderer*` + `SDL_Texture*`
- `HBITMAP` → `SDL_Texture*`
- `HPALETTE` → `SDL_Palette*` (or eliminate — convert to RGBA at load)
- `HWND` → `SDL_Window*`
- KBGM functions → SDL_mixer wrappers
- Delphi string types → `std::string` / `char*`
- Delphi dynamic arrays → `std::vector`
- VCL exception frames → C++ RAII

**Phase 2: Rewrite Rendering**
Replace `GDI_Blit_Sprite` and all `StretchBlt`/`BitBlt`/`MaskBlt` calls with SDL texture rendering. Convert palette-based surfaces to RGBA at load time. Analyze ROP codes to determine correct blend modes.

**Phase 3: Rewrite Audio**
Replace all 14 KBGM functions and DirectSound calls with SDL_mixer equivalents. Handle MIDI → digital audio conversion for BGM.

**Phase 4: Rewrite Input**
Replace DirectInput polling with SDL event-driven input. Map DIK scancodes to `SDL_Scancode` equivalents.

**Phase 5: Rewrite Windowing**
Replace the VCL message loop with an SDL event loop. Replace `SetTimer` with frame-delta-based updates.

**Phase 6: Code Cleanup Pass**
- Replace all decompiler artifacts with idiomatic C/C++
- Reconstruct function prototypes from call site analysis
- Replace Delphi RTL helpers with standard C library calls
- Convert Pascal-style strings to null-terminated C strings
- Replace VCL VMT dispatch with direct function calls or C++ virtual methods
- Remove Borland exception frames; replace with RAII or try/catch
- Audit all struct layouts for correct enum/set sizes and alignment

---

### Current Annotation Progress

| Function | New Name |
|---|---|
| `FUN_004060d0` | `Delphi_RTL_Init` |
| `FUN_004428f4` | `Application_Setup` |
| `FUN_00442510` | `Set_Application_Title` |
| `FUN_0044290c` | `Create_Main_Form` |
| `FUN_0044298c` | `Show_Main_Form` |
| `FUN_004038f4` | `VCL_Message_Loop` |
| `FUN_004412d4` | `Game_Timer_Callback` |
| `FUN_00443414` | `Game_Tick` |
| `FUN_0044ab24` | `DirectDraw_Init` |
| `FUN_004475f4` | `DDraw_Create_Surface` |
| `FUN_00449ca4` | `Get_Display_BitDepth` |
| `FUN_004653c8` | `GameState_Reset` |
| `FUN_0046214c` | `Stage_Init` |
| `FUN_00417fd4` | `GDI_Blit_Sprite` |
| `FUN_0044f8a4` | `DirectSound_Init` |
| `FUN_00453bdc` | `DirectInput_Init` |

---

### RTL Helper Annotations (with Evidence & Confidence)

Each renaming is based on the following methodology:
1. **Parameter analysis** — what does the function receive/return?
2. **Call graph** — what does it call internally?
3. **Call sites** — who calls it and in what context?
4. **Error semantics** — what error codes does it raise?
5. **Known Delphi RTL patterns** — does it match documented Borland internals?

#### 🟢 High Confidence

| Function | New Name | Evidence |
|---|---|---|
| `FUN_004026d8` | **Delphi_GetMem** | Calls BSS memory manager dispatch at `PTR_FUN_0046801c` (Delphi's internal `GetMemoryManager` table). On failure (returns 0), raises error code 1 = `EOutOfMemory`. Adjacent to FreeMem dispatch at +0x20. |
| `FUN_004026f0` | **Delphi_FreeMem** | Calls BSS memory manager dispatch at `PTR_FUN_00468020`. Raises error code 2 = `EInvalidPointer`. Shares error path with GetMem. |
| `FUN_00402da4` | **Delphi_TObject_Free** | Dereferences VMT at `*param_1`, calls `(**(code **)(*param_1 + -4))(param_1, 1)` — offset -4 in Delphi VMT = `vmtDestroy` virtual destructor. Param `1` = called via `Free` (triggers `FreeInstance` after `Destroy`). Exact `TObject.Free` pattern. |
| `FUN_00406a50` | **Delphi_FillChar** | Calls `FUN_00402aa4(dest, count, 0)` with fill byte hardcoded to 0. Callers use it for struct zero-init (`FillChar(&local, sizeof(local), 0)`). Delphi equivalent of `memset`. |
| `FUN_00403cf8` | **Delphi_AnsiString_Assign** | Accesses Delphi `AnsiString` header: refcount at offset -8, length at offset -4. Uses `LOCK` prefix for thread-safe refcounting. Handles assignment (one source null) and concatenation (both non-null). Classic `LStrAsg` / `UStrAsg` internal. |
| `FUN_00403e60` | **Delphi_AnsiString_AddRef** | Atomic `LOCK` increment of refcount at offset -8. Skips string literals (refcount = -1 in Delphi). Called to pin strings before use, preventing premature deallocation. |
| `FUN_00407f64` | **Delphi_IntToStr** | Calls `FUN_00408a44` (Delphi's `FormatBuf`/`FmtStr`) with a format string pointer at `0x00407f9c` and a single integer argument. Thin wrapper around Delphi's `IntToStr` RTL. |

#### 🟡 Medium Confidence

| Function | New Name | Evidence | Open Questions |
|---|---|---|---|
| `FUN_00446734` | **DDraw_Check_HRESULT** | Called at every DirectDraw/DirectSound/Direct3D COM call site in `DirectDraw_Init`. Formats HRESULT as hex `"(Error Code(%x))"`, logs it, and on failure calls `VCL_Message_Loop` (fatal abort). Pattern matches Delphi COM `OleCheck` / custom HRESULT checker. | Is this a general COM check or DirectX-specific? Need to verify call sites outside of DD init. |
| `FUN_00407ff8` | **Delphi_FileOpen** | Wraps `CreateFileA`. Translates Delphi file mode via lookup tables at `DAT_00468138` (access modes) and `DAT_00468144` (share modes). Calls `FUN_00403e70` to convert Delphi filename string to C string. Matches Delphi `FileOpen` RTL signature. | Haven't verified the lookup table constants against known Delphi `SysUtils` file mode values (0=fmOpenRead, 1=fmOpenWrite, etc.). |
| `FUN_0040805c` | **Delphi_FileRead** | Thin `ReadFile` wrapper. Returns `0xFFFFFFFF` on error, bytes read on success. Matches Delphi `FileRead` semantics. | Could simply be a local `ReadFile` wrapper rather than the actual RTL function. Function is small enough it may be inlined in the original source. |

### Annotation Methodology (Going Forward)

For every future renaming, the following evidence chain will be provided **before** the rename is performed:
1. **Input parameters** — types and meanings inferred from usage
2. **Internal calls** — what RTL/API functions it delegates to
3. **Caller analysis** — which functions call it and in what context
4. **Error/success semantics** — what does it return or raise on failure
5. **Known pattern match** — link to Delphi RTL documentation or known binary pattern

Renamings will include a confidence tag (🟢 High / 🟡 Medium / 🔴 Low) and any open questions.