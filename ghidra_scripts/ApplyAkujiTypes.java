/* Give Ghidra the types the reconstruction recovered.
 *
 * The decompilation stays unreadable while the game's records are int arrays:
 * E[8] is a number, not a field. This defines every struct src/*.pas pins the
 * layout of, applies them to the functions and the global pointer cells, and
 * turns E[8] into E->BlockA_State and p_EntityPool + slot * 0x104 into an
 * ordinary array index.
 *
 * Field names come from the units that own each record - the EF_/PF_ constants
 * for TEntity, the +0xNNN annotations for the rest, which tools/layout_lock.py
 * asserts at runtime. Where one entity slot carries both an entity and a player
 * meaning the name keeps both, because that is what it is: BlockB_AnimTimer is
 * the field Entity_CheckKillTiles clears and the death timer PS_DYING counts.
 * Offsets with no name are Field<offset>, never a guess.
 *
 * Where our own constants give a slot two names, the SEMANTIC one wins over a
 * range marker: EF_BLOCK_A is "10 ints, zeroed on spawn" and EF_STATE is
 * "block A[0]: per-type state", so +0x20 is State, not BlockA. Same for
 * TouchKind over EF_TYPEF_0C and NoDrop over EF_TYPEF_20, both of which mark
 * the start of a run copied from the type table rather than naming the field.
 * BlockB_AnimTimer keeps its compound: +0x48 is the first of ten per-entity
 * timers and the only semantic name we have for it is the player's.
 *
 * ALIASES COUNT TOO. Entities.pas declares EF_DEPTH = EF_TYPEF_08, an alias to
 * another constant rather than to a literal, which a first pass missed - so
 * +0x8C was briefly Typef08 when Entity_UpdateAll plainly uses it as the
 * sprite depth, clamped 1..0xF0 when it is not -1. It is Depth.
 *
 * Run from the Script Manager. Safe to re-run: types are replaced, not added.
 * ADD EVERY NEW STRUCT HERE as it is discovered, so one run brings the project
 * up to date with the reconstruction.
 */
//@category Akuji
//@menupath Tools.Apply Akuji Types
import ghidra.app.script.GhidraScript;
import ghidra.program.model.data.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.*;
import ghidra.program.model.address.Address;

public class ApplyAkujiTypes extends GhidraScript {

    private void add(Structure s, String name) {
        s.add(IntegerDataType.dataType, 4, name, null);
    }
    private void i(Structure s, int off, String name) {
        s.replaceAtOffset(off, IntegerDataType.dataType, 4, name, null);
    }
    private void b(Structure s, int off, String name) {
        s.replaceAtOffset(off, ByteDataType.dataType, 1, name, null);
    }
    private void arr(Structure s, int off, int count, String name) {
        s.replaceAtOffset(off, new ArrayDataType(ByteDataType.dataType, count, 1),
                          count, name, null);
    }
    private void ints(Structure s, int off, int count, String name) {
        s.replaceAtOffset(off, new ArrayDataType(IntegerDataType.dataType, count, 4),
                          count * 4, name, null);
    }

    private DataType put(DataTypeManager dtm, Structure s, int want) {
        Structure r = (Structure) dtm.addDataType(s, DataTypeConflictHandler.REPLACE_HANDLER);
        String ok = (r.getLength() == want) ? "ok" : ("WRONG, want " + want);
        println("  " + r.getName() + ": " + r.getLength() + " bytes (" + ok + ")");
        return r;
    }

    private void typeCell(DataTypeManager dtm, String symbol, DataType pointee) {
        DataType ptr = dtm.getPointer(pointee);
        for (Symbol s : currentProgram.getSymbolTable().getSymbols(symbol)) {
            Address a = s.getAddress();
            try {
                clearListing(a, a.add(3));
                createData(a, ptr);
                println("  " + symbol + " @ " + a + " -> " + ptr.getName());
            } catch (Exception ex) {
                println("  SKIP " + symbol + ": " + ex.getMessage());
            }
        }
    }

    @Override
    protected void run() throws Exception {
        DataTypeManager dtm = currentProgram.getDataTypeManager();
        println("structs:");

        StructureDataType e = new StructureDataType("TEntity", 0);
        add(e, "Slot");
        add(e, "Owner");
        add(e, "Alive");
        add(e, "Type");
        add(e, "Sprite");
        add(e, "AnimId");
        add(e, "Variant");
        add(e, "Flag1c_AnimFrame");
        // ---- block A, ten ints at +0x20, and block B, ten at +0x48 ----
        // These twenty slots have NO fixed meaning. Each entity type reads
        // them as it likes, and the player - slot 0 - is just one more
        // reader. The Pascal handles that by declaring a separate set of
        // constants per type against the same offsets: PF_AIR_LATCH,
        // EMIT_EVERY and EF_BLOCK_A + 1 are all $09.
        //
        // A Ghidra struct gets one name per offset, so the name must not
        // pretend otherwise. These carry the SLOT first and the player's use
        // second: A1_AirLatch is block A[1], which the player uses as an air
        // latch and type 21 uses as an oscillation half-period. Reading
        // `E->A1_AirLatch` in a handler should prompt "what does THIS type
        // keep in A[1]", which the bare name AirLatch actively discouraged.
        //
        // Do not drop the prefixes to tidy them up. State, A9_Dying, B0's
        // anim timer, B1/B2's child refs and B3_Shots are the only ones with
        // a meaning that holds across types, and even those get the prefix so
        // the block layout stays readable at a glance.
        add(e, "State");                 // A[0], per-type state - universal
        add(e, "A1_AirLatch");
        add(e, "A2_Ridden_Landed");
        add(e, "A3_FallFrames");
        add(e, "A4_StateBefore");
        add(e, "A5_DebrisType_Riding");
        add(e, "A6_RideRef");
        add(e, "A7_LandFrames");
        add(e, "A8_JumpHeld");
        add(e, "A9_Dying");
        add(e, "B0_AnimTimer");
        add(e, "B1_ChildA_AirVx");
        add(e, "B2_ChildB_Charge");
        add(e, "B3_Shots");
        add(e, "B4_JumpProbe");
        add(e, "B5_DashFrames");
        add(e, "B6_HasJumped");
        add(e, "Field64");
        add(e, "Field68");
        add(e, "Field6C");
        add(e, "Timer");
        add(e, "DeathTimer");
        add(e, "PosX");
        add(e, "PosY");
        add(e, "VelX");
        add(e, "VelY");
        add(e, "Facing");
        add(e, "Depth");
        add(e, "Hp");
        add(e, "Byte94");
        add(e, "ExtentX");
        add(e, "ExtentY");
        add(e, "BoxOfsX");
        add(e, "BoxOfsY");
        add(e, "HitboxInsetX");
        add(e, "HitboxInsetY");
        add(e, "ParkedVel_PendVx");
        add(e, "PendVy");
        add(e, "EventId");
        add(e, "FieldBC");
        add(e, "FieldC0");
        add(e, "FieldC4");
        add(e, "TouchKind");
        add(e, "Class");
        add(e, "ScreenSpace");
        add(e, "VulnKind");
        add(e, "FieldD8");
        add(e, "NoDrop");
        add(e, "HitSound");
        add(e, "CullOffscreen");
        add(e, "BoxPctX");
        add(e, "BoxPctY");
        add(e, "InsetPctX");
        add(e, "InsetPctY");
        add(e, "Solid");
        add(e, "TileOfsX");
        add(e, "TileOfsY");
        DataType ent = put(dtm, e, 0x104);

        StructureDataType l = new StructureDataType("TLayerInfo", 0);
        add(l, "OriginX");  add(l, "OriginY");  add(l, "DeltaX");  add(l, "DeltaY");
        add(l, "TileW");    add(l, "TileH");    add(l, "MapTilesX"); add(l, "MapTilesY");
        DataType lay = put(dtm, l, 0x20);

        StructureDataType ps = new StructureDataType("TPlayerState", 0x11E4);
        arr(ps, 0x0, 10, "Head");
        arr(ps, 0xA, 4501, "Progress");
        b(ps, 0x119F, "Pad119F");
        i(ps, 0x11A0, "SavedStage");
        i(ps, 0x11A4, "SpawnX");
        i(ps, 0x11A8, "SpawnY");
        i(ps, 0x11AC, "ScrollX");
        i(ps, 0x11B0, "ScrollY");
        i(ps, 0x11B4, "Lives");
        i(ps, 0x11B8, "MaxLives");
        i(ps, 0x11BC, "ElapsedSec");
        i(ps, 0x11C0, "Field11C0");
        i(ps, 0x11C4, "Counter");
        i(ps, 0x11C8, "EventCounter");
        i(ps, 0x11CC, "Weapon");
        i(ps, 0x11D0, "JumpStrength");
        i(ps, 0x11D4, "MusicTrack");
        i(ps, 0x11D8, "SpawnFacing");
        i(ps, 0x11DC, "TargetIndex");
        i(ps, 0x11E0, "Difficulty");
        DataType play = put(dtm, ps, 0x11E4);

        StructureDataType inp = new StructureDataType("TInputState", 0x38);
        i(inp, 0x0, "AxisX");
        i(inp, 0x4, "AxisY");
        i(inp, 0x8, "HeldX");
        i(inp, 0xC, "HeldY");
        b(inp, 0x10, "Moving");
        b(inp, 0x11, "AxisYNegative");
        i(inp, 0x14, "RepeatTimer");
        i(inp, 0x18, "HoldTimer");
        arr(inp, 0x1C, 4, "Button");
        arr(inp, 0x20, 4, "ButtonLatch");
        ints(inp, 0x24, 4, "ButtonRepeat");
        b(inp, 0x34, "AnyPressed");
        DataType input = put(dtm, inp, 0x38);

        // Unknown2C is GalleryUnlocked: Title_MainMenu indexes it by
        // GallerySel and draws ON or OFF from it, and Ending.pas already
        // describes +0x2C..+0x32 as the seven gallery flags. Our record still
        // calls it Unknown2C; the name here follows the evidence.
        StructureDataType gs = new StructureDataType("TGameSettings", 0x38);
        i(gs, 0x0, "CurrentStage");
        i(gs, 0x4, "GameLevel");
        ints(gs, 0x8, 4, "KeyMap");
        b(gs, 0x18, "SoftwareVsyncFlag");
        b(gs, 0x19, "WaitOnFlag");
        b(gs, 0x1A, "FullScreenFlag");
        b(gs, 0x1B, "DebugLogFlag");
        b(gs, 0x1C, "ExtraDoor1");
        b(gs, 0x1D, "ExtraDoor2");
        arr(gs, 0x1E, 6, "Unknown1E");
        i(gs, 0x24, "Volume");
        i(gs, 0x28, "GallerySel");
        arr(gs, 0x2C, 7, "GalleryUnlocked");
        i(gs, 0x34, "InputDevice");
        DataType settings = put(dtm, gs, 0x38);

        StructureDataType ev = new StructureDataType("TEventRecord", 0x24);
        i(ev, 0x00, "Opcode");
        b(ev, 0x04, "InWindow");
        b(ev, 0x05, "Active");
        i(ev, 0x08, "EntitySlot");
        i(ev, 0x0C, "ParamA");
        i(ev, 0x10, "TileX");
        i(ev, 0x14, "TileY");
        i(ev, 0x18, "ParamB");
        i(ev, 0x1C, "NeedsFlag");
        i(ev, 0x20, "BlockedBy");
        DataType evrec = put(dtm, ev, 0x24);

        StructureDataType li = new StructureDataType("TIconAnim", 0);
        add(li, "X"); add(li, "Frame"); add(li, "Timer");
        DataType lifeicon = put(dtm, li, 0x0C);

        // An animated icon's state - X, Frame, Timer. NOT life-specific: it is
        // an ARRAY, and MessageBox_Update drives [1] as the wait-for-key and
        // yes/no prompt animation while HUD_Draw drives [0] as the life icon.
        // It was briefly named TLifeIcon for the first use found.
        // The sprite object the sprite list holds. Only the fields the game
        // touches are named; the rest of the object is left undefined, which
        // is fine because it is only ever reached through a pointer.
        StructureDataType sp = new StructureDataType("TSprite", 0x40);
        i(sp, 0x1C, "AnimId");
        i(sp, 0x2C, "X");
        i(sp, 0x30, "Y");
        i(sp, 0x34, "Depth");
        b(sp, 0x3D, "Visible");
        DataType sprite = put(dtm, sp, 0x40);

        // The entity type table, stride 0x48. Every column is named by where
        // Entity_Spawn COPIES it into the entity, which is evidence from the
        // binary rather than a name carried over from the reconstruction -
        // TEntityType is a raw int array on our side. +0x1C is the one column
        // Entity_Spawn does not copy, so it stays unnamed.
        StructureDataType et = new StructureDataType("TEntityType", 0);
        add(et, "AnimId");    add(et, "Hp");        add(et, "Depth");
        add(et, "TouchKind"); add(et, "Class");     add(et, "ScreenSpace");
        add(et, "VulnKind");  add(et, "Field1C");   add(et, "NoDrop");
        add(et, "HitSound");  add(et, "CullOffscreen");
        add(et, "BoxPctX");   add(et, "BoxPctY");   add(et, "InsetPctX");
        add(et, "InsetPctY"); add(et, "Solid");     add(et, "TileOfsX");
        add(et, "TileOfsY");
        DataType enttype = put(dtm, et, 0x48);

        DataType entPtr = dtm.getPointer(ent);

        // TList.Get is generic in the VCL, but in THIS binary every one of its
        // call sites passes p_SpriteList - checked across the whole export, 20
        // of 20 - so typing the return TSprite * is correct here rather than a
        // convenient lie. If a second list is ever read through it, this is
        // wrong at that site and the comment on the function says so.
        Function tlg = getFunctionAt(toAddr(0x0044cfb8));
        if (tlg != null) {
            try {
                tlg.setReturnType(dtm.getPointer(sprite), SourceType.USER_DEFINED);
                println("  TList_Get returns TSprite *");
            } catch (Exception ex) {
                println("  SKIP TList_Get return: " + ex.getMessage());
            }
        }

        // ---- TJoyState = the Win32 DIJOYSTATE, from dinput.h ----
        // This is not inferred from offsets. It is the documented Windows
        // structure IDirectInputDevice8::GetDeviceState fills when the data
        // format is c_dfDIJoystick, quoted from MSDN:
        //
        //   typedef struct DIJOYSTATE {
        //       LONG  lX;             // usually left-right on the stick
        //       LONG  lY;             // usually forward-back
        //       LONG  lZ;             // often the throttle
        //       LONG  lRx, lRy, lRz;  // rotations; lRz is often the rudder
        //       LONG  rglSlider[2];   // the old u- and v-axes
        //       DWORD rgdwPOV[4];     // POV hats
        //       BYTE  rgbButtons[32];
        //   } DIJOYSTATE, *LPDIJOYSTATE;
        //
        //   24 + 8 + 16 + 32 = 80 bytes = 0x50
        //
        // and the binary agrees to the byte: FUN_00454158 zeroes the block
        // with Delphi_FillChar(Dev + 0x1B8, 0x50), keeps a stack mirror of
        // exactly that shape - six LONGs, a pair, four, then 32 bytes - and
        // copies it back with a 0x14-dword move.
        //
        // Two documented details the code depends on:
        //
        //   rgbButtons: "The high-order bit of the byte is set if the
        //   corresponding button is down". That is exactly Input_IsKeyDown's
        //   `> 0x7F` test - it is the DirectInput convention, not a magic
        //   number.
        //
        //   rgdwPOV: "the position is indicated in hundredths of a degree
        //   clockwise from north", centre normally -1. A POV is therefore a
        //   DIRECTION, not a magnitude, which is why Input_ReadJoyState
        //   copies the four hats raw while signing all eight axes - signing a
        //   hat would turn its -1 centre into "left" and 27000 into "right".
        //
        // Field names below drop the array brackets Ghidra cannot express;
        // Slider0/1, POV0..3 and Buttons are rglSlider, rgdwPOV, rgbButtons.
        StructureDataType joy = new StructureDataType("TJoyState", 0);
        add(joy, "lX");
        add(joy, "lY");
        add(joy, "lZ");
        add(joy, "lRx");
        add(joy, "lRy");
        add(joy, "lRz");
        add(joy, "Slider0");
        add(joy, "Slider1");
        add(joy, "POV0");
        add(joy, "POV1");
        add(joy, "POV2");
        add(joy, "POV3");
        joy.add(new ArrayDataType(ByteDataType.dataType, 32, 1), 32, "Buttons", null);
        DataType joyT = put(dtm, joy, 0x50);

        // ---- TInputDevice ----
        // The component's own object. Only the fields the game layer or
        // FUN_00454158 actually touch are named; the rest is left as filler
        // rather than guessed at.
        //
        // KeyBind1/KeyBind2 are two 32-entry tables of scan codes, one per
        // virtual button - the keyboard path ORs local key state through both
        // into Buttons, so each button has two bindings. RangePercent scales
        // the synthesised axis extremes (+-0x7FFF, the DirectInput full
        // deflection) by a percentage.
        StructureDataType dev = new StructureDataType("TInputDevice", 0x228);
        i(dev, 0x2c, "DIKeyboard");
        i(dev, 0x30, "DIDevice0");
        dev.replaceAtOffset(0x78, new ArrayDataType(IntegerDataType.dataType, 32, 4),
                            128, "KeyBind1", null);
        dev.replaceAtOffset(0x118, new ArrayDataType(IntegerDataType.dataType, 32, 4),
                            128, "KeyBind2", null);
        dev.replaceAtOffset(0x1b8, joyT, 0x50, "Joy", null);
        i(dev, 0x220, "RangePercent");
        i(dev, 0x224, "ActiveKind");
        DataType devT = put(dtm, dev, 0x228);
        DataType devPtr = dtm.getPointer(devT);
        DataType joyPtr = dtm.getPointer(joyT);

        // Apply BY ADDRESS, never by name. Setting a prototype renames the
        // function to whatever identifier the string carries, so a wrong
        // address silently retypes AND renames the wrong code - which has
        // happened twice here. See notes/ghidra_naming.md.
        Function rjs = getFunctionAt(toAddr(0x00454648));   // Input_ReadJoyState
        if (rjs != null && rjs.getParameterCount() > 1) {
            rjs.getParameter(0).setDataType(devPtr, SourceType.USER_DEFINED);
            rjs.getParameter(0).setName("Dev", SourceType.USER_DEFINED);
            rjs.getParameter(1).setDataType(joyPtr, SourceType.USER_DEFINED);
            rjs.getParameter(1).setName("Out", SourceType.USER_DEFINED);
            println("  Input_ReadJoyState(TInputDevice *, TJoyState *)");
        }
        Function ikd = getFunctionAt(toAddr(0x004546c4));   // Input_IsKeyDown
        if (ikd != null && ikd.getParameterCount() > 1) {
            ikd.getParameter(0).setDataType(devPtr, SourceType.USER_DEFINED);
            ikd.getParameter(0).setName("Dev", SourceType.USER_DEFINED);
            println("  Input_IsKeyDown(TInputDevice *, int)");
        }
        Function poll = getFunctionAt(toAddr(0x00454158));  // the device poll
        if (poll != null && poll.getParameterCount() > 0) {
            poll.getParameter(0).setDataType(devPtr, SourceType.USER_DEFINED);
            poll.getParameter(0).setName("Dev", SourceType.USER_DEFINED);
            println("  poll @ 0x00454158 (TInputDevice *, ...)");
        }

        println("");
        println("functions:");
        int done = 0, skipped = 0;
        for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
            String n = f.getName();
            boolean isHandler = n.startsWith("EntityUpdate_Type");
            boolean isEntityFn =
                n.equals("Player_Update") || n.equals("Player_UpdateGlide") ||
                n.equals("Player_UpdateAirDash") || n.equals("Player_UpdateKnockback") ||
                n.equals("Camera_ApplyMoveX") || n.equals("Camera_ApplyMoveY") ||
                n.equals("Camera_ShouldScrollX") || n.equals("Camera_ShouldScrollY") ||
                n.equals("Entity_CheckKillTiles") || n.equals("Entity_IsOffScreen") ||
                n.equals("Entity_TileEdgeDistX") || n.equals("Entity_TileEdgeDistY") ||
                n.equals("Entity_TileCollideX") || n.equals("Entity_TileCollideY") ||
                n.equals("Entity_Destroy") || n.equals("Entity_SpawnDebris") ||
                n.equals("Entity_MaybeDropItem") || n.equals("Entity_UpdateDying") ||
                n.equals("Entity_PlayerTouch") || n.equals("Entity_TakeProjectileHits") ||
                n.equals("Entity_TouchPickup") ||
                n.equals("Entity_TouchLife") || n.equals("Entity_TouchHeal");
            if (!isHandler && !isEntityFn) continue;
            Parameter[] pp = f.getParameters();
            if (pp.length == 0) { skipped++; continue; }
            try {
                pp[0].setDataType(entPtr, SourceType.USER_DEFINED);
                if (pp[0].getName() == null || pp[0].getName().startsWith("param_"))
                    pp[0].setName("E", SourceType.USER_DEFINED);
                done++;
            } catch (Exception ex) {
                println("  SKIP " + n + ": " + ex.getMessage());
                skipped++;
            }
        }
        println("  TEntity * applied to " + done + " functions, " + skipped + " skipped");
        // NOT Player_TakeDamage: it takes an int damage amount, not an entity.
        // Entity_PlayerTouch calls it as Player_TakeDamage(1) for touch kind 1
        // and (2) for kind 7. It was in this list by mistake and the wrong
        // type showed up at the call site as (TEntity *)0x1.
        Function ptd = getFunctionAt(toAddr(0x00458138));
        if (ptd != null && ptd.getParameterCount() > 0) {
            ptd.getParameter(0).setDataType(IntegerDataType.dataType, SourceType.USER_DEFINED);
            ptd.getParameter(0).setName("Amount", SourceType.USER_DEFINED);
            println("  Player_TakeDamage(int Amount) - not an entity");
        }

        println("");
        println("global pointer cells:");
        typeCell(dtm, "p_LayerInfo", lay);
        typeCell(dtm, "p_EntityPool", ent);
        typeCell(dtm, "p_PlayerState", play);
        typeCell(dtm, "p_InputState", input);
        typeCell(dtm, "p_Settings", settings);
        typeCell(dtm, "p_EventTable", dtm.getPointer(evrec));
        typeCell(dtm, "p_IconAnim", lifeicon);

        // Cells holding the address of a flat int table. Typing them turns
        // *(int *)(p_X + i * 4) into p_X[i].
        DataType i32 = IntegerDataType.dataType;
        typeCell(dtm, "p_LifeIconX", i32);
        typeCell(dtm, "p_StageGoalTable", i32);
        typeCell(dtm, "p_SprKnockback", i32);
        typeCell(dtm, "p_DirX", i32);
        typeCell(dtm, "p_DirY", i32);
        typeCell(dtm, "p_OpeningSlideSeconds", i32);
        typeCell(dtm, "p_OpeningTextIds", i32);

        // Cells holding the address of a table of POINTERS - surfaces, the
        // tilemaps, the midi playlist, the text table.
        DataType anyPtr = dtm.getPointer(DataType.DEFAULT);
        typeCell(dtm, "p_Surfaces", anyPtr);
        typeCell(dtm, "p_TileMaps", anyPtr);
        typeCell(dtm, "p_MidiNames", anyPtr);
        typeCell(dtm, "p_TextTable", anyPtr);
        typeCell(dtm, "p_OpeningImageIds", i32);
        // The player sprite tables, confirmed by their strides: 0x14 per
        // facing is five ints (SPR_GROUND, SPR_AIR), 0x10 is four (SPR_GLIDE),
        // 8 is two (SPR_AIRDASH), and the flat pair is SPR_DEATH.
        typeCell(dtm, "p_SprGround", i32);
        typeCell(dtm, "p_SprAir", i32);
        typeCell(dtm, "p_SprGlide", i32);
        typeCell(dtm, "p_SprAirDash", i32);
        typeCell(dtm, "p_SprDeath", i32);

        // SCALAR CELLS. These are why *(int *)p_ScreenPhase appears in every
        // function that touches a global: the cell holds the address of an int
        // and was never typed, so every read and write needed a cast. Typed,
        // they read as *p_ScreenPhase.
        String[] intCells = {
            "p_GameState", "p_ScreenPhase", "p_TitleSubMode", "p_MenuIndex",
            "p_SavedMenuIndex", "p_SavedGameState", "p_OpeningSlide",
            "p_OpeningTimer", "p_EventId", "p_EventArg", "p_EventCursor",
            "p_EventStepIndex", "p_MessageMode", "p_MessageReveal",
            "p_MessagePageStart", "p_OverlayActive", "p_OverlayMode",
            "p_RevealTimer", "p_AnswerIndex", "p_ScreenShakeTimer",
            "p_EntitiesLive", "p_EntitiesDrawn", "p_SolidThreshold",
            "p_KillTile", "p_LastFrameTime", "p_KeyMap",
        };
        for (String n : intCells) typeCell(dtm, n, i32);

        // Byte flags, same problem.
        String[] byteCells = {
            "p_ScreenShakeOn", "p_OnTopOfSolid", "p_UseArchive",
            "p_FullScreenOn", "p_WaitOn", "p_SoftwareVsync",
        };
        for (String n : byteCells) typeCell(dtm, n, ByteDataType.dataType);

        // Cells holding an OBJECT pointer - one more indirection, so the
        // pointee is itself a pointer.
        String[] objCells = {
            "p_Fader", "p_SpriteList", "p_BgAnime", "p_EndingSurface",
            "p_PanelSurface", "p_TileBuffer", "p_MessageText",
        };
        for (String n : objCells) typeCell(dtm, n, dtm.getPointer(DataType.DEFAULT));
        typeCell(dtm, "p_EntityTypes", enttype);

        println("");
        println("===== DONE - remember to save the project =====");
    }
}
