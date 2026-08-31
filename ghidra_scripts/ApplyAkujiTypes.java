/* Give Ghidra the types the reconstruction recovered.
 *
 * The decompilation stays unreadable while an entity is an int array: E[8] is
 * a number, not a field. This defines TEntity and TLayerInfo from the offsets
 * src/Entities.pas and src/Player.pas pin, applies TEntity* to every handler
 * that takes one, and types the layer pointer cell - after which E[8] reads as
 * E->BlockA_State and *(int *)(p_LayerInfo + 0x14) reads as p_LayerInfo->TileH.
 *
 * Field names come from the EF_ and PF_ constants. Where one slot carries both
 * an entity and a player meaning the name keeps both, because it really is one
 * slot with two jobs - BlockB_AnimTimer is the field Entity_CheckKillTiles
 * clears and the death timer PS_DYING counts.
 *
 * Run from the Script Manager. Safe to re-run: types are replaced, not added.
 */
//@category Akuji
//@menupath Tools.Apply Akuji Types
import ghidra.app.script.GhidraScript;
import ghidra.program.model.data.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.*;
import ghidra.program.model.address.Address;
import java.util.*;

public class ApplyAkujiTypes extends GhidraScript {

    private void add(Structure s, String name) {
        s.add(IntegerDataType.dataType, 4, name, null);
    }

    @Override
    protected void run() throws Exception {
        DataTypeManager dtm = currentProgram.getDataTypeManager();

        StructureDataType e = new StructureDataType("TEntity", 0);
        add(e, "Slot");
        add(e, "Owner");
        add(e, "Alive");
        add(e, "Type");
        add(e, "Sprite");
        add(e, "AnimId");
        add(e, "Variant");
        add(e, "Flag1c_AnimFrame");
        add(e, "BlockA_State");
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
        add(e, "TouchKind_Typef0c");
        add(e, "Class");
        add(e, "ScreenSpace");
        add(e, "VulnKind");
        add(e, "FieldD8");
        add(e, "NoDrop_Typef20");
        add(e, "HitSound");
        add(e, "CullOffscreen");
        add(e, "BoxPctX");
        add(e, "BoxPctY");
        add(e, "InsetPctX");
        add(e, "InsetPctY");
        add(e, "Solid");
        add(e, "TileOfsX");
        add(e, "TileOfsY");
        Structure ent = (Structure) dtm.addDataType(e, DataTypeConflictHandler.REPLACE_HANDLER);
        println("TEntity: " + ent.getLength() + " bytes (want 260)");

        StructureDataType l = new StructureDataType("TLayerInfo", 0);
        add(l, "OriginX");
        add(l, "OriginY");
        add(l, "DeltaX");
        add(l, "DeltaY");
        add(l, "TileW");
        add(l, "TileH");
        add(l, "MapTilesX");
        add(l, "MapTilesY");
        Structure lay = (Structure) dtm.addDataType(l, DataTypeConflictHandler.REPLACE_HANDLER);
        println("TLayerInfo: " + lay.getLength() + " bytes (want 32)");

        DataType entPtr = dtm.getPointer(ent);
        DataType layPtr = dtm.getPointer(lay);

        // Every function whose first argument is an entity.
        int done = 0, skipped = 0;
        FunctionManager fm = currentProgram.getFunctionManager();
        for (Function f : fm.getFunctions(true)) {
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
                n.equals("Entity_MaybeDropItem") || n.equals("Entity_UpdateDying");
            if (!isHandler && !isEntityFn) continue;
            Parameter[] ps = f.getParameters();
            if (ps.length == 0) { skipped++; continue; }
            try {
                ps[0].setDataType(entPtr, SourceType.USER_DEFINED);
                if (ps[0].getName() == null || ps[0].getName().startsWith("param_"))
                    ps[0].setName("E", SourceType.USER_DEFINED);
                done++;
            } catch (Exception ex) {
                println("SKIP " + n + ": " + ex.getMessage());
                skipped++;
            }
        }
        println("entity pointer applied to " + done + " functions, " + skipped + " skipped");

        // The layer pointer CELL holds the address of the record.
        for (Symbol s : currentProgram.getSymbolTable().getSymbols("p_LayerInfo")) {
            Address a = s.getAddress();
            clearListing(a, a.add(3));
            createData(a, layPtr);
            println("p_LayerInfo at " + a + " typed as TLayerInfo *");
        }

        println("");
        println("===== DONE - remember to save the project =====");
    }
}
