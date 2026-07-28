# Akuji the Demon — Reverse Engineering & SDL Port

Reverse engineering of **Akuji the Demon** (circa 2000–2001), a 2D action-platformer built with Borland Delphi for Windows 98/2000/ME/XP.

## Project Goals

1. **Full decompilation** — annotate all ~1,500 functions in the binary
2. **SDL2 port** — replace DirectDraw/DirectSound/DirectInput/VCL with SDL2 for cross-platform support
3. **Documentation** — reverse-engineer data file formats, game mechanics, and engine architecture

## Repository Structure

```
akuji-re/
├── README.md                  ← You are here
├── .gitignore                 ← Ignores lock files, temp files
├── .gitattributes             ← Marks Ghidra DB as binary (Git LFS)
├── SDL_port_plan.md           ← Porting strategy & API mapping
├── ghidra/                    ← Ghidra project (binary database)
│   ├── Akuji_AIdecompAttempt.gpr
│   └── Akuji_AIdecompAttempt.rep/
├── exports/                   ← Text exports from Ghidra (diffable)
│   └── functions/             ← Per-function decompiled C (future)
├── notes/                     ← Analysis notes & documentation
│   ├── data_formats.md        ← Reverse-engineered file formats
│   ├── struct_layouts.md      ← Reconstructed struct layouts
│   └── function_map.md        ← Function → subsystem mapping
└── scripts/                   ← Ghidra scripts (future)
    └── apply_renames.py       ← Reapplies all function annotations
```

## Getting Started

### Prerequisites

- **Ghidra 11.x** (or later) — [Download](https://ghidra-sre.org/)
- **Git LFS** — `git lfs install` (for binary project files)

### Opening the Project

1. Clone the repository:
   ```bash
   git clone <repo-url>
   cd akuji-re
   ```

2. Open Ghidra, then **File → Open Project...** and select:
   ```
   ghidra/Akuji_AIdecompAttempt.gpr
   ```

3. All 35+ annotated functions will be visible with their renamed labels.

### Contributing

1. Open the Ghidra project and make your annotations (renames, comments, data types)
2. Export your changes as a script (Ghidra → Script Manager → write a Python script that reapplies your annotations)
3. Place the script in `scripts/`
4. Commit both the updated `.rep/` database and your script
5. Update `notes/` with any new discoveries

## Current Progress

| Area | Status |
|---|---|
| Functions annotated | **35** of ~1,500 |
| Entry point chain | ✅ Fully traced |
| Rendering (GDI/DDraw) | ✅ All call sites mapped |
| Audio (KBGM/DSound) | ✅ All call sites mapped |
| Input (DirectInput) | ✅ All call sites mapped |
| Data loading chain | ✅ surf, spr, tk, ev loaders identified |
| Save/load system | ✅ Player state init & save slot select identified |
| SDL port plan | ✅ Comprehensive mapping documented |
| Data file formats | 🔶 Formats identified, not yet fully documented |
| VCL class layouts | ❌ Not started |
| Bulk function export | ❌ Not started |

## Key Technical Details

- **Compiler:** Borland Delphi (Object Pascal), 32-bit x86
- **Calling convention:** Borland `register` (EAX, EDX, ECX for first 3 params)
- **Graphics:** DirectDraw 7 with GDI fallback, 8-bit indexed palettes
- **Audio:** DirectSound + KBGM custom MIDI engine
- **Input:** DirectInput 7 (keyboard + mouse)
- **Windowing:** VCL framework (TApplication, TForm, TCanvas)
- **File formats:** Proprietary binary `.dat` files in `data\surf\`, `data\spr\`, `data\tk\`, `data\ev\`

## License

This is a reverse engineering project for educational and preservation purposes. The original game "Akuji the Demon" is copyright by its respective owners.