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
        add(e, "State");
        add(e, "AirLatch");
        add(e, "Ridden_Landed");
        add(e, "FallFrames");
        add(e, "StateBefore");
        add(e, "DebrisType_Riding");
        add(e, "RideRef");
        add(e, "LandFrames");
        add(e, "JumpHeld");
        add(e, "Dying");
        add(e, "BlockB_AnimTimer");
        add(e, "ChildA_AirVx");
        add(e, "ChildB_Charge");
        add(e, "Shots");
        add(e, "JumpProbe");
        add(e, "DashFrames");
        add(e, "HasJumped");
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
        add(e, "Typef08");
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
        arr(gs, 0x2C, 7, "Unknown2C");
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

        StructureDataType li = new StructureDataType("TLifeIcon", 0);
        add(li, "X"); add(li, "Frame"); add(li, "Timer");
        DataType lifeicon = put(dtm, li, 0x0C);

        DataType entPtr = dtm.getPointer(ent);

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
                n.equals("Player_TakeDamage") || n.equals("Entity_TouchPickup") ||
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

        println("");
        println("global pointer cells:");
        typeCell(dtm, "p_LayerInfo", lay);
        typeCell(dtm, "p_EntityPool", ent);
        typeCell(dtm, "p_PlayerState", play);
        typeCell(dtm, "p_InputState", input);
        typeCell(dtm, "p_Settings", settings);
        typeCell(dtm, "p_EventTable", dtm.getPointer(evrec));
        typeCell(dtm, "p_LifeIcon", lifeicon);

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

        println("");
        println("===== DONE - remember to save the project =====");
    }
}
