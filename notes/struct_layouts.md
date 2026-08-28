# Reconstructed Struct Layouts

## Player State Struct (0x11E4 bytes)

**Location:** `PTR_DAT_0046cff0` (global pointer)
**Size:** 0x11E4 bytes
**Saved to:** `data\save.dat` (full struct written/read)

### Field Map

| Offset | Size | Type | Description | Evidence |
|--------|------|------|-------------|----------|
| +0x00 | 4 | int | Stage ID / current level | Set to 1 in `Game_Init_PlayerState` |
| +0x04 | 1 | byte | Flag 0 | Cleared to 0 on init |
| +0x05 | 1 | byte | Flag 1 | Cleared to 0 on init |
| +0x06 | 1 | byte | Flag 2 | Cleared to 0 on init |
| +0x07 | 1 | byte | Flag 3 | Cleared to 0 on init |
| +0x08 | 2 | short | (unknown) | |
| +0x0A | 1 | byte | Save slot occupied flag | Set to 1 after init/load |
| +0x0B | 1 | byte | (unknown) | |
| +0x0C | 1 | byte | (unknown) | |
| +0x0D | 1 | byte | (unknown) | |
| +0x0E | 1 | byte | (unknown) | |
| +0x0F | 1 | byte | Difficulty flag 0 (easy?) | Set when `stage_id == 1` |
| +0x10 | 1 | byte | Difficulty flag 1 (medium?) | Set when `stage_id == 2` |
| +0x11 | 1 | byte | Difficulty flag 2 (hard?) | Cleared to 0 on init |
| +0x12 | 1 | byte | (unknown) | Cleared to 0 on init |
| +0x13 | 1 | byte | (unknown) | Cleared to 0 on init |
| +0x14 | 1 | byte | Difficulty flag 3 (easy?) | Set when `stage_id == 0` |
| ... | | | | |
| +0x48 | 1 | byte | Active flag | Set to 1 when game is active |
| +0x4C | 4 | int | (unknown) | |
| +0x50 | 4 | int* | Pointer to active form/control | Used in `Game_UpdateAndRender` |
| +0x54 | 4 | int | Rect left | Set from control rect |
| +0x58 | 4 | int | Rect top | Set from control rect |
| +0x5C | 4 | int | Rect right | Set from control rect |
| +0x60 | 4 | int | Rect bottom | Set from control rect |
| +0x74 | 4 | int* | Pointer to current form | Switched in `Game_SwitchForm` |
| +0x78 | 1 | byte | Mode flag | Checked in `Game_Tick` |
| +0x79 | 1 | byte | Sub-mode flag | 0 = normal, 1 = hidden |
| +0x7A | 2 | short | Timer ID | Killed in `Game_KillTimer` |
| +0x100 | 4 | int | (unknown) | |
| +0x108 | 4 | code* | Function pointer | Called in update loop |
| +0x10C | 4 | int | Param for function pointer | |
| ... | | | | |
| +0x4AB | 1 | byte | Option flag 1 | Set from `PTR_DAT_0046d0e8[0x1c]` |
| +0x4B4 | 1 | byte | Option flag 2 | Set from `PTR_DAT_0046d0e8[0x1d]` |
| ... | | | | |
| +0x11A0 | 4 | int | Save slot index | Copied to `PTR_DAT_0046d0e8` on load |
| +0x11A4 | 4 | int | Player HP | Set to 0x60 (96) on init |
| +0x11A8 | 4 | int | Player max HP | Set to 0x73 (115) on init |
| +0x11AC | 4 | int | Player X position | Set to 0 on init |
| +0x11B0 | 4 | int | Player Y position | Set to 0x1C0 (448) on init |
| +0x11B4 | 4 | int | Lives count | Set to 3 on init |
| +0x11B8 | 4 | int | Max lives | Set to 3 on init |
| +0x11BC | 4 | int | (unknown counter) | Set to 0 on init |
| +0x11C0 | 4 | int | (unknown counter) | Set to 0 on init |
| +0x11C4 | 4 | int | (unknown) | Set to 0 on init |
| +0x11C8 | 4 | int | Timer/score? | Set to 300 on init |
| +0x11CC | 4 | int | (unknown) | Set to 0 on init |
| +0x11D0 | 4 | int | (unknown) | Set to 0x68 (104) on init |
| +0x11D4 | 4 | int | Current save slot | Set to 1 on init |
| +0x11D8 | 4 | int | (unknown) | Set to 0 on init |
| +0x11DC | 4 | int | (unknown) | Set to 0 on init |
| +0x11E0 | 4 | int | Stage ID (duplicate?) | Set from `PTR_DAT_0046d0e8 + 4` |

### Notes

- The struct is zeroed from offset +0x0A to +0x119E (0x1195 bytes) on init
- Save file is exactly 0x11E4 bytes
- The struct contains both gameplay state (HP, position, lives) and UI state (form pointers, timer IDs)
- Difficulty flags at +0x0F, +0x10, +0x14 are mutually exclusive based on stage_id

## Entity Struct (0x14 bytes?)

**Location:** Created by `Entity_Create` (FUN_0044e1b8)
**Size:** At least 0x10 bytes (4 ints + pointer)

### Field Map

| Offset | Size | Type | Description |
|--------|------|------|-------------|
| +0x00 | 4 | int* | VMT pointer (virtual method table) |
| +0x04 | 4 | int | param_3 (type/ID?) |
| +0x08 | 4 | int | param_5 (position/param?) |
| +0x0C | 4 | int | param_4 (position/param?) |
| +0x10 | 4 | int* | Pointer to string/name (set via `FUN_00404d4c`) |

## Global State Pointers

| Address | Name | Description |
|---------|------|-------------|
| `0046cff0` | `PTR_DAT_0046cff0` | Player state struct (0x11E4 bytes) |
| `0046d0e8` | `PTR_DAT_0046d0e8` | Options/settings struct |
| `0046cef8` | `PTR_DAT_0046cef8` | Mode flag (0 = new game, 1 = load save) |
| `0046cc14` | `PTR_DAT_0046cc14` | (unknown global) |
| `0046d06c` | `PTR_DAT_0046d06c` | (unknown global) |
| `0046ccb4` | `PTR_DAT_0046ccb4` | Packed archive flag (0 = loose files, 1 = bmp.qda) |
| `0046ce38` | `PTR_DAT_0046ce38` | Main form/application object |
| `0046d154` | `PTR_PTR_0046d154` | Array of pointers (save slot strings?) |
| `0046d24c` | `PTR_DAT_0046d24c` | Save slot string list |
| `0046d334` | `PTR_DAT_0046d334` | Current save slot index |
| `0046d218` | `PTR_DAT_0046d218` | (unknown) |
| `0046d344` | `PTR_DAT_0046d344` | Surface texture array (32 slots) |
| `0046cce0` | `PTR_DAT_0046cce0` | Event script array |
| `0046d1c8` | `PTR_DAT_0046d1c8` | Event string data |
| `0046cfb4` | `PTR_DAT_0046cfb4` | Stage definition table (0x4C-byte entries) |
| `0046cc44` | `PTR_DAT_0046cc44` | Solid-tile threshold (set by `Terrain_Configure`) - every reader is a tile test |
| `0046cf5c` | `PTR_DAT_0046cf5c` | Stage timer (set by `Configure_Stage_Params`) |
| `0046d060` | `PTR_DAT_0046d060` | Boss entity pointer |
| `0044e14c` | `PTR_DAT_0044e14c` | Entity class reference |