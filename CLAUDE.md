# Akuji the Demon — Project Brief

Read this before touching anything. It records what the project is, what has been
decided, and the mistakes that have already cost time here.

Named `CLAUDE.md` so Claude Code auto-loads it; the content is tool-agnostic, so
point any other agent at it too.

---

## 1. What this is

`akuji.exe` is a 1998-era Japanese doujin game, **written in Object Pascal and
compiled with Borland Delphi**. The goal is a **source port**: real, compilable,
cross-platform source code — not a compatibility shim.

Compiler identification is settled, on three independent proofs:

- PE sections are `CODE` / `DATA` / `BSS` — Borland's linker, nobody else's
- `TimeDateStamp = 0x2A425E19` (19 Jun 1992) — Borland's fixed constant, not a build date
- `__register` calling convention, negative VMT offsets, `AnsiString` refcounting,
  and a textbook Delphi `.dpr` program block at `entry` (`0x004671ac`)

## 2. Decisions made

| Decision | Rationale |
|---|---|
| **Target Free Pascal + Lazarus LCL first** | The original is Object Pascal. Translating Pascal to Pascal preserves `AnsiString`, VMT dispatch, `try/finally`, and sets as *language features* instead of hand-reimplemented C. LCL supplies `TCanvas`/`TFont`/`TBitmap` near-1:1 with VCL |
| **SDL2 later, only if measured** | SDL2 has mature Pascal bindings. Swapping the presentation layer is cheap once the game runs. Do not start here |
| **Not C++** | Would require reimplementing the Delphi runtime *and* translating, simultaneously, with no working reference to check against. C++ remains a viable later migration from working source |
| **Get it running before making it good** | The hard part of a decompilation project is knowing you got it right. Reach a verifiable running build by the cheapest route first |

Project is private, not a community effort, so the "C++ has more contributors"
argument was weighed and rejected.

## 3. The three-layer structure — the most important section here

The binary is **not** "game code plus Windows APIs". It is three layers, and only
the innermost is Akuji's:

| Layer | Marker classes | ~Functions | What to do |
|---|---|---|---|
| Borland RTL + VCL | `TObject`, `TCanvas`, `TForm`, `TApplication` | ~1597 | **Skip.** FPC RTL + LCL replace it |
| Third-party DirectX suite | `TDDDD`, `TDDSD`, `TDDIDEX`, `TKbgmPlayer` | ~191 | **Replace wholesale.** Do not port |
| **Akuji** | **`TFrm_main`** and its units | **~83** | **This is what you write** |

**About 5% of the binary is the actual game** — roughly 80–110 functions, not 1,871.

### The address-range rule

Delphi links its own units before the program's, so library code sits low:

| Range | Contents |
|---|---|
| `0x402000`–`0x408fff` | Delphi RTL (`System.pas`) |
| `0x417000`–`0x425fff` | VCL (`Graphics.pas`, `Controls.pas`) |
| `0x439000`–`0x443fff` | VCL (`Forms.pas`) |
| `0x444000`–`0x455000` | Third-party DirectX components |
| `0x455000`+ | **The game** |

**A game-sounding name below `0x444000` is wrong until proven otherwise.** The
`0x455000` boundary is fuzzy — `Game_DrawTextOutlined` (`0x451004`) is game code
below it — but every misidentification found so far has been under `0x444000`.

## 4. Read this before naming anything

The most expensive mistake in this project was **naming functions after the Win32
API they call.** That produced `Game_KillTimer`, `Game_Tick`,
`Game_UpdateAndRender`, `VCL_Message_Loop`, `GDI_Blit_Sprite` — nineteen functions
marked "Confirmed" that were all Borland library code. The port plan was then
built around `GDI_Blit_Sprite` as "the core sprite blitter"; it is
`Graphics.pas`'s transparent-blit helper, and the game's real blitter had never
been found.

`004038f4` was labelled `VCL_Message_Loop`, "PeekMessage/DispatchMessage pump". It
contains no message-pump calls at all. It is `System._Halt0`, the process
**shutdown** path. The notes even recorded it being called as a "fatal abort" —
the contradiction sat in the document, unexamined.

**Rules:**

1. Check the address range first.
2. Name from the **cluster**, not the callee. Read callers and callees, and see
   whether the group matches a known `Forms.pas` / `Controls.pas` routine.
3. Do not mark a name confirmed without cross-function evidence. "Likely" is fine
   and honest.
4. Prefer built-in Ghidra features (`Auto Create Structure`) over hand-rolling —
   but check whether a standard type already fits before keeping a generated one.
   One auto-created struct here turned out to be `tagPOINT`, which already existed.

## 5. How Pascal source is actually recovered

Ghidra cannot emit Pascal, and no transpiler exists. Recovery is manual
re-authoring — but three things make it far cheaper than that sounds.

### 5a. The DFM gives you the form for free

Delphi embeds the form design as a binary `TPF0` resource. It has been decoded to
`notes/Frm_main.dfm` — **verbatim, not reconstructed**. It supplies component
names, properties, and **the original event-handler method names**:

```
object Frm_main: TFrm_main
  Caption = 'Akuji the Demon'
  ClientWidth = 320   ClientHeight = 240
  OnDestroy = FormDestroy
  OnKeyDown = FormKeyDown
  object DDDD1: TDDDD              // DirectDraw, 320x240, Use3D = False
    OnInit = DDDD1Init
  object Joy: TDDIDEX              // DirectInput
  object KbgmPlayer1: TKbgmPlayer  // MIDI, 15 tracks
  object DDSD1: TDDSD              // DirectSound, 57 channels
```

That is the skeleton of `Frm_main.pas` with real identifiers. Use these names.

### 5b. Delphi idioms map mechanically

Ghidra's C pseudocode carries recognisable Pascal fingerprints:

| Decompiled | Pascal |
|---|---|
| `Delphi_AnsiString_Assign(&a, b)` | `a := b;` |
| `Delphi_AnsiString_AddRef` / decref calls | *nothing* — the compiler emits these |
| `FS:[0]` frame plus a `LAB_xxx` handler | `try...finally` / `try...except` |
| `(**(code **)(*obj + 0x2C))(obj, ...)` | `obj.SomeVirtualMethod(...)` |
| `Delphi_TObject_Free(x)` | `x.Free;` |
| `param_1` on a method | `Self` |
| byte-sized bit ops over a small range | a Pascal `set of` |

### 5c. You do not port the component layer

`TDDDD` / `TDDSD` / `TDDIDEX` / `TKbgmPlayer` get *reimplemented* against the same
published interface, which the DFM documents. Write an LCL (later SDL2) `TDDDD`
that honours `InitialScreenWidth`/`InitialScreenHeight` and fires `OnInit`, and the
game's calls into it keep working unchanged.

## 6. Resolved: the D3DRM dependency costs nothing

The game will not launch without `d3drm.dll`, yet is purely 2D. Both are true:

- `Direct3DRMCreate` is a **static import**, so Windows resolves it at load time
  whether or not the code ever runs
- The import belongs to the **DirectX component suite**, not to the game
- The DFM settles it outright: **`Use3D = False`, `D3DOptions = []`**

The component layer is being replaced anyway, so the dependency leaves with it.
This was the largest apparent risk in the port, and it is closed.

## 7. Facts worth having

- Original unit was **`GmMain.pas`**, class `TFrm_main` (86 published properties),
  instance `Frm_main` — all recovered from `TTypeData` RTTI, not guessed
- Native resolution **320x240**, windowed (`system.ini`: `fullscreen=off`)
- Non-portable import surface is **24 of 396 imports** (6%): ddraw 2, dsound 1,
  dinput 1, d3drm 1, winmm 6 (`timeGetTime` plus RIFF/WAV `mmio*`), Kbgm32 13
- 248 imports are user32/gdi32/comctl32 — all VCL's, all replaced free by LCL
- **67 gdi32 imports versus 2 ddraw entry points**: the game draws mostly through
  GDI (`TCanvas`), which is why the LCL-first bet is sound
- Audio is external (`Kbgm32.dll`, 13 exports) — a clean replaceable boundary
- The MIDI playlist implies structure: 2 main areas, 2 bosses, **5 endings**
- No `OnCreate`, no `OnPaint`, no `TTimer` on the form. The main loop is driven
  elsewhere — likely `TApplication.OnIdle` (`FOnIdle` at `+0xD8`) or inside
  `TDDDD`. **Unverified; worth confirming early.**

## 8. State of the work

**Done:** compiler and language identified; three-layer structure established;
21 functions renamed (12 VCL tooltip cluster plus 9 entry-chain); `TApplication`
struct recovered and applied across 13 functions; game entry point found; DFM
decoded; D3DRM risk closed.

**Next:** walk the `TFrm_main` VMT at `PTR_PTR_00464b54`. Its virtual methods are
both the game's structure and the checklist of what remains to rebuild.

**`src/` holds the reconstructed source.** `akuji.lpr` and `GmMain.lfm` are done;
the four component units and `GmMain.pas` are not. This is not a "port" of an
existing codebase — no source was ever released. It is *the* source, rebuilt, and
it happens to be cross-platform because Free Pascal is. Avoid "port" framing in
new notes; `SDL_port_plan.md` predates this and uses it throughout.

**Stale:** `exports/functions/` predates the renames. Regenerate with
`ghidra_scripts/ExportAllFunctions.java` — clear the directory first, since it only
writes and never deletes.

**Contradicts this brief:** `SDL_port_plan.md` still assumes C + SDL2 throughout
and targets several misidentified functions. It carries a warning header. Treat
`notes/function_map.md` and this file as authoritative.

## 9. Tooling

Ghidra 12.0.4 with a GhidraMCP server on `127.0.0.1:8081/sse` (`.mcp.json` lives at
`devel/source`). It binds at session start — **if it drops, the session must be
restarted; it will not reconnect.** Ghidra scripts can be compile-checked offline
with `javac` against the install's jars rather than guessed at.
