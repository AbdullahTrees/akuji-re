/* Create the Delphi VCL data types recovered from the hint/tooltip cluster and
 * apply them, so the decompiler shows named fields instead of raw offsets.
 *
 * Creates under category /VCL:
 *   TTimerMode   - enum (tmShowHint / tmHideHint)
 *   TRect        - LONG left, top, right, bottom
 *   TMethod      - Delphi method pointer (Code, Data)
 *   TApplication - partial layout; only the hint-related fields are known
 *
 * Then retypes param_1 to TApplication* on the seven methods whose first
 * parameter is Self, and types the global Application pointer at 0046e7c8.
 *
 * Safe to re-run: existing types are replaced.
 */
//@category Akuji
//@menupath Tools.Create VCL Types

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.data.*;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Parameter;
import ghidra.program.model.symbol.SourceType;

public class CreateVCLTypes extends GhidraScript {

    // Methods whose param_1 is Self (a TApplication). Deliberately excludes
    // TApplication_RecreateHintWindow (Self arrives via param_4-4, param_1 is the
    // window class) and the four free functions that take no Self at all.
    private static final long[] SELF_METHODS = {
        0x004432e8L, // TApplication_StopHintTimer
        0x004432b0L, // TApplication_StartHintTimer
        0x00443414L, // TApplication_HintTimerExpired
        0x00443448L, // TApplication_HideHint
        0x00443484L, // TApplication_CancelHint
        0x00443664L, // TApplication_ActivateHint
        0x00443308L, // TApplication_HintMouseMessage
    };

    private static final long APPLICATION_GLOBAL = 0x0046e7c8L;

    @Override
    protected void run() throws Exception {
        DataTypeManager dtm = currentProgram.getDataTypeManager();
        CategoryPath vcl = new CategoryPath("/VCL");

        // --- TTimerMode ---------------------------------------------------
        EnumDataType timerMode = new EnumDataType(vcl, "TTimerMode", 1, dtm);
        timerMode.add("tmShowHint", 0);
        timerMode.add("tmHideHint", 1);
        DataType timerModeT = dtm.addDataType(timerMode, DataTypeConflictHandler.REPLACE_HANDLER);

        // --- TRect --------------------------------------------------------
        StructureDataType rect = new StructureDataType(vcl, "TRect", 0, dtm);
        rect.add(IntegerDataType.dataType, 4, "left", null);
        rect.add(IntegerDataType.dataType, 4, "top", null);
        rect.add(IntegerDataType.dataType, 4, "right", null);
        rect.add(IntegerDataType.dataType, 4, "bottom", null);
        DataType rectT = dtm.addDataType(rect, DataTypeConflictHandler.REPLACE_HANDLER);

        // --- TMethod (Delphi method pointer: code first, then Self) --------
        StructureDataType method = new StructureDataType(vcl, "TMethod", 0, dtm);
        method.add(PointerDataType.dataType, 4, "Code", null);
        method.add(PointerDataType.dataType, 4, "Data", null);
        DataType methodT = dtm.addDataType(method, DataTypeConflictHandler.REPLACE_HANDLER);

        // --- TApplication -------------------------------------------------
        // Oversized on purpose: only the hint fields are known, and the real
        // object is larger than anything observed so far.
        StructureDataType app = new StructureDataType(vcl, "TApplication", 0x140, dtm);
        put(app, 0x48, BooleanDataType.dataType, 1, "FHintActive", null);
        put(app, 0x4C, IntegerDataType.dataType, 4, "FHintColor", "TColor");
        put(app, 0x50, PointerDataType.dataType, 4, "FHintControl", "TControl*");
        put(app, 0x54, rectT, 16, "FHintCursorRect", null);
        put(app, 0x64, IntegerDataType.dataType, 4, "FHintHidePause", null);
        put(app, 0x68, IntegerDataType.dataType, 4, "FHintPause", null);
        put(app, 0x70, IntegerDataType.dataType, 4, "FHintShortPause", null);
        put(app, 0x74, PointerDataType.dataType, 4, "FHintWindow", "THintWindow*");
        put(app, 0x78, BooleanDataType.dataType, 1, "FShowHint", null);
        put(app, 0x79, timerModeT, 1, "FTimerMode", null);
        put(app, 0x7A, WordDataType.dataType, 2, "FTimerHandle", null);
        put(app, 0x95, BooleanDataType.dataType, 1, "field_0x95",
            "unidentified; gates VCL_InstallHintHooks");
        put(app, 0x108, methodT, 8, "FOnShowHint", "TShowHintEvent");

        DataType appT = dtm.addDataType(app, DataTypeConflictHandler.REPLACE_HANDLER);
        DataType appPtr = dtm.getPointer(appT);
        println("Created /VCL: TTimerMode, TRect, TMethod, TApplication");

        // --- Apply to the Self parameter of each method -------------------
        int retyped = 0;
        for (long entry : SELF_METHODS) {
            Address addr = toAddr(entry);
            Function f = getFunctionAt(addr);
            if (f == null) {
                printerr("No function at " + addr);
                continue;
            }
            Parameter p = f.getParameter(0);
            if (p == null) {
                printerr("No param_1 on " + f.getName() + " @ " + addr + " - skipped");
                continue;
            }
            try {
                p.setDataType(appPtr, SourceType.USER_DEFINED);
                p.setName("Self", SourceType.USER_DEFINED);
                println("Retyped: " + f.getName());
                retyped++;
            } catch (Exception e) {
                printerr("Failed on " + f.getName() + ": " + e.getMessage());
            }
        }

        // --- Type and name the global Application pointer -----------------
        Address appGlobal = toAddr(APPLICATION_GLOBAL);
        try {
            clearListing(appGlobal, appGlobal.add(3));
            createData(appGlobal, appPtr);
            createLabel(appGlobal, "Application", true);
            println("Typed global Application @ " + appGlobal);
        } catch (Exception e) {
            printerr("Could not type the global at " + appGlobal + ": " + e.getMessage());
        }

        println("");
        println("===== DONE =====");
        println("Methods retyped: " + retyped + " / " + SELF_METHODS.length);
        println("Remember to save the program (Ctrl+S).");
    }

    /** Overwrite the undefined bytes at an offset with a named field. */
    private void put(Structure s, int offset, DataType dt, int len, String name, String comment) {
        s.replaceAtOffset(offset, dt, len, name, comment);
    }
}
