/* Run the ORIGINAL's machine code, so the reconstruction can be diffed
 * against it rather than against my reading of it.
 *
 * WHY THIS EXISTS
 *
 * Everything else in this project verifies the reconstruction against
 * *evidence* - two readers agreeing, self-validating structure, mutation
 * testing. None of that can say the Pascal computes what akuji.exe computes;
 * only running both can. The project record said differential tracing was
 * blocked on a 32-bit toolchain, and that was wrong: a logging PROXY DLL for
 * kbgm32.dll would need one, because a 32-bit process can only load 32-bit
 * DLLs. Executing 32-bit code needs no 32-bit compiler at all.
 *
 * Ghidra ships a p-code emulator, and analyzeHeadless runs scripts without the
 * GUI, so the original's own bytes can be executed with controlled inputs and
 * the answers dumped for comparison. No new dependency, no toolchain.
 *
 * WHAT IT ASSUMES
 *
 * Delphi's __register convention: the first three integer arguments arrive in
 * EAX, EDX, ECX in that order, any further ones are PUSHED RIGHT TO LEFT, and
 * the result comes back in EAX. Callee-saved registers are the usual EBX, ESI,
 * EDI, EBP. A `var` parameter is a pointer, so it is passed as an address into
 * scratch memory and read back afterwards.
 *
 * The emulator executes p-code lifted from the instructions, which means it
 * models the ISA and not the process: no Windows, no imports, no VCL. A
 * function that calls into the RTL or touches an OS handle will fault, and
 * that is the honest boundary of this technique. Leaf functions and pure
 * arithmetic run fine, which is exactly where the reconstruction's risk is.
 *
 * SPEC FORMAT
 *
 * A TSV file, one call per line, comments with '#':
 *
 *     <name> <hexaddr> <eax> <edx> <ecx> [stack args, left to right]
 *
 * Values are decimal or 0x-prefixed. Output goes to the file named by the
 * -o argument as `<name> <inputs...> -> <eax>`, or `<name> ... -> FAULT msg`.
 *
 * USAGE
 *
 *   analyzeHeadless <projdir> <projname> -import akuji.exe -noanalysis \
 *      -scriptPath ghidra_scripts -postScript EmuDiff.java <spec.tsv> <out.txt>
 *
 * tools/emudiff.py drives all of that; use it rather than this directly.
 */
//@category Akuji
import ghidra.app.script.GhidraScript;
import ghidra.app.emulator.EmulatorHelper;
import ghidra.program.model.address.Address;

import java.io.BufferedReader;
import java.io.FileReader;
import java.io.PrintWriter;
import java.math.BigInteger;
import java.util.ArrayList;
import java.util.List;

public class EmuDiff extends GhidraScript {

    /* Somewhere to put a stack and scratch buffers. Chosen well clear of the
     * image so nothing the code touches can collide with it. */
    private static final long STACK_TOP  = 0x70000000L;
    private static final long SCRATCH    = 0x60000000L;
    /* The fake return address. Execution stops when it is reached, which is
     * how a call's end is detected without knowing where the RET is. */
    private static final long RETURN_TO  = 0x7FFF0000L;

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) {
            println("EmuDiff: need <spec.tsv> <out.txt>");
            return;
        }
        List<String> out = new ArrayList<>();
        int ok = 0, bad = 0;

        try (BufferedReader in = new BufferedReader(new FileReader(args[0]))) {
            String line;
            while ((line = in.readLine()) != null) {
                line = line.trim();
                if (line.isEmpty() || line.startsWith("#")) continue;
                String[] f = line.split("\\s+");
                if (f.length < 5) {
                    out.add(line + "  -> BADSPEC");
                    bad++;
                    continue;
                }
                String name = f[0];
                long addr = parse(f[1]);
                long eax = parse(f[2]), edx = parse(f[3]), ecx = parse(f[4]);
                long[] stack = new long[f.length - 5];
                for (int i = 5; i < f.length; i++) stack[i - 5] = parse(f[i]);

                try {
                    long r = call(addr, eax, edx, ecx, stack);
                    out.add(line + "  -> " + r);
                    ok++;
                } catch (Exception e) {
                    out.add(line + "  -> FAULT " + e.getMessage());
                    bad++;
                }
            }
        }

        try (PrintWriter w = new PrintWriter(args[1])) {
            for (String s : out) w.println(s);
        }
        println("EmuDiff: " + ok + " returned, " + bad + " faulted -> " + args[1]);
    }

    private static long parse(String s) {
        s = s.trim();
        boolean neg = s.startsWith("-");
        if (neg) s = s.substring(1);
        long v = s.toLowerCase().startsWith("0x")
                ? Long.parseLong(s.substring(2), 16) : Long.parseLong(s);
        return neg ? -v : v;
    }

    /** One __register call. Returns EAX. */
    private long call(long addr, long eax, long edx, long ecx, long[] stack)
            throws Exception {
        EmulatorHelper emu = new EmulatorHelper(currentProgram);
        try {
            Address entry = toAddr(addr);

            /* Arguments beyond the third are pushed right to left, so the
             * leftmost ends up nearest the return address. */
            long sp = STACK_TOP;
            for (int i = stack.length - 1; i >= 0; i--) {
                sp -= 4;
                emu.writeMemory(toAddr(sp), int32(stack[i]));
            }
            sp -= 4;
            emu.writeMemory(toAddr(sp), int32(RETURN_TO));

            emu.writeRegister("ESP", BigInteger.valueOf(sp));
            emu.writeRegister("EBP", BigInteger.valueOf(STACK_TOP));
            emu.writeRegister("EAX", BigInteger.valueOf(eax & 0xFFFFFFFFL));
            emu.writeRegister("EDX", BigInteger.valueOf(edx & 0xFFFFFFFFL));
            emu.writeRegister("ECX", BigInteger.valueOf(ecx & 0xFFFFFFFFL));
            emu.writeRegister(emu.getPCRegister().getName(),
                              BigInteger.valueOf(addr));

            emu.setBreakpoint(toAddr(RETURN_TO));

            /* A leaf routine here is a few hundred instructions at most; the
             * cap turns a runaway into a reported fault instead of a hang. */
            for (int steps = 0; steps < 2000000; steps++) {
                if (!emu.step(monitor)) {
                    String err = emu.getLastError();
                    throw new Exception(err == null ? "step failed" : err);
                }
                long pc = emu.readRegister(emu.getPCRegister().getName())
                             .longValue() & 0xFFFFFFFFL;
                if (pc == RETURN_TO) {
                    return emu.readRegister("EAX").longValue() & 0xFFFFFFFFL;
                }
            }
            throw new Exception("did not return within the step cap");
        } finally {
            emu.dispose();
        }
    }

    private static byte[] int32(long v) {
        return new byte[]{ (byte) v, (byte) (v >> 8),
                           (byte) (v >> 16), (byte) (v >> 24) };
    }
}
