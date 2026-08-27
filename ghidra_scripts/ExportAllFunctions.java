/* Export all decompiled functions to individual .c files.
 * Run this in Ghidra's Script Manager (Window -> Script Manager).
 * Find it in the list and double-click or press the Run button.
 *
 * Output: exports/functions/{FunctionName}.c (one file per function)
 *         exports/functions/_index.txt (list of all exported functions)
 */
//@category Akuji
//@menupath Tools.Export All Functions
import java.io.*;
import java.util.*;
import ghidra.app.decompiler.*;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.*;
import ghidra.program.model.address.*;
import ghidra.util.task.TaskMonitor;

public class ExportAllFunctions extends GhidraScript {

    @Override
    protected void run() throws Exception {
        // Output directory: <repo_root>/exports/functions/
        // getSourceFile() is the .java file itself, so go up twice: ghidra_scripts/ -> repo root
        if (getSourceFile() == null) {
            printerr("Cannot determine script location; run this from the Script Manager.");
            return;
        }
        File scriptDir = new File(getSourceFile().getAbsolutePath()).getParentFile();
        File outputDir = new File(scriptDir.getParentFile(), "exports" + File.separator + "functions");
        outputDir.mkdirs();

        println("Output directory: " + outputDir.getAbsolutePath());

        FunctionManager fm = currentProgram.getFunctionManager();
        List<Function> functions = new ArrayList<>();
        for (Function func : fm.getFunctions(true)) {
            functions.add(func);
        }

        int total = functions.size();
        int exported = 0;
        int skipped = 0;
        int failed = 0;

        StringBuilder index = new StringBuilder();
        index.append("# Exported Functions Index\n");
        index.append("# Total functions in binary: ").append(total).append("\n\n");

        DecompInterface decompiler = new DecompInterface();
        decompiler.openProgram(currentProgram);

        monitor.initialize(total);
        for (Function func : functions) {
            monitor.checkCancelled();
            monitor.incrementProgress(1);

            String name = func.getName();
            Address addr = func.getEntryPoint();
            monitor.setMessage(name);

            // Skip thunks, externals, and compiler-generated helpers
            if (func.isThunk() || func.isExternal()) {
                skipped++;
                continue;
            }
            // A single leading '_' is just MSVC cdecl decoration (_main, _WinMain@16) and
            // covers most of the game's own code, so only skip the '__' CRT/compiler internals.
            if (name.startsWith("__") || name.startsWith("thunk_")) {
                skipped++;
                continue;
            }

            try {
                DecompileResults results = decompiler.decompileFunction(func, 60, monitor);
                if (results == null || !results.decompileCompleted()) {
                    failed++;
                    println("DECOMPILE FAILED: " + name + " @ " + addr);
                    continue;
                }

                DecompiledFunction df = results.getDecompiledFunction();
                if (df == null) {
                    failed++;
                    println("NO C OUTPUT: " + name + " @ " + addr);
                    continue;
                }

                String code = df.getC();
                String safeName = name.replaceAll("[^a-zA-Z0-9_\\-\\.]", "_");
                File file = new File(outputDir, safeName + ".c");

                // Handle duplicate names by appending address
                if (file.exists()) {
                    safeName = safeName + "_" + String.format("%08X", addr.getOffset());
                    file = new File(outputDir, safeName + ".c");
                }

                try (PrintWriter pw = new PrintWriter(file)) {
                    pw.println("/*");
                    pw.println(" * Function: " + name);
                    pw.println(" * Address:  " + addr);
                    pw.println(" */");
                    pw.println();
                    pw.println(code);
                }

                index.append(name).append(" @ ").append(addr)
                     .append(" -> ").append(safeName).append(".c\n");
                exported++;
                println("OK: " + name + " -> " + safeName + ".c");

            } catch (Exception e) {
                failed++;
                println("ERROR: " + name + " @ " + addr + " - " + e.getMessage());
            }
        }

        decompiler.dispose();

        // Write index file
        index.append("\n---\n");
        index.append("Exported: ").append(exported).append("\n");
        index.append("Skipped (thunks/extern): ").append(skipped).append("\n");
        index.append("Failed to decompile: ").append(failed).append("\n");

        try (PrintWriter pw = new PrintWriter(new File(outputDir, "_index.txt"))) {
            pw.print(index.toString());
        }

        println("");
        println("===== DONE =====");
        println("Exported: " + exported);
        println("Skipped:  " + skipped);
        println("Failed:   " + failed);
        println("Output:   " + outputDir.getAbsolutePath());
    }
}