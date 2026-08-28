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
 * the result comes back in EAX.
 *
 * The emulator executes p-code lifted from the instructions, which means it
 * models the ISA and not the process: no Windows, no imports, no VCL. A
 * function that calls into the RTL or touches an OS handle will fault, and
 * that is the honest boundary of this technique rather than a bug in it.
 * Faults are reported, never silently skipped.
 *
 * BSS IS NOT IN THE FILE. Globals like p_LayerInfo point into BSS, which a PE
 * does not store, so anything read from there has to be written first with a
 * mem= entry. That is not a workaround - it is the setup the test wants
 * control over anyway.
 *
 * SPEC FORMAT - one line per call, and BOTH SIDES READ THE SAME FILE
 *
 *     CASE <name> <hexaddr> [key=value ...]
 *
 *       eax= edx= ecx=      the register arguments, default 0
 *       stk=a,b,c           further arguments, left to right
 *       mem=ADDR:HEXBYTES   memory to place first; repeatable
 *       f.<anything>=<int>  ignored here, carried through for the Pascal
 *
 * Each line is echoed to the output with `  -> <eax>` or `  -> FAULT <why>`
 * appended, so the output file is the input file plus the original's answers.
 * `akuji.exe --emudiff <that file>` then recomputes each case and diffs.
 *
 * USAGE - tools/emudiff.py drives all of this; prefer that.
 *
 *   analyzeHeadless <projdir> <proj> -import akuji.exe -noanalysis \
 *      -scriptPath ghidra_scripts -postScript EmuDiff.java <spec> <out>
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

    /* A stack and scratch space, chosen well clear of the image so nothing
     * the code touches can collide with them. */
    private static final long STACK_TOP = 0x70000000L;
    /* The fake return address. Execution stops when it is reached, which is
     * how the end of a call is detected without knowing where its RET is -
     * and these are Borland frameless routines with several exit paths. */
    private static final long RETURN_TO = 0x7FFF0000L;
    private static final int  STEP_CAP  = 2000000;

    private static class Case {
        String raw, name;
        long addr, eax, edx, ecx;
        List<Long> stack = new ArrayList<>();
        List<long[]> memAddr = new ArrayList<>();   // {addr}
        List<byte[]> memData = new ArrayList<>();
    }

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) {
            println("EmuDiff: need <spec> <out>");
            return;
        }
        List<String> out = new ArrayList<>();
        int ok = 0, faulted = 0;

        try (BufferedReader in = new BufferedReader(new FileReader(args[0]))) {
            String line;
            while ((line = in.readLine()) != null) {
                String t = line.trim();
                if (t.isEmpty() || t.startsWith("#")) {
                    out.add(line);
                    continue;
                }
                Case c;
                try {
                    c = parse(t);
                } catch (Exception e) {
                    out.add(line + "  -> BADSPEC " + e.getMessage());
                    faulted++;
                    continue;
                }
                try {
                    out.add(line + "  -> " + call(c));
                    ok++;
                } catch (Throwable e) {
                    String m = e.getMessage();
                    out.add(line + "  -> FAULT " + (m == null ? e.toString() : m));
                    faulted++;
                }
            }
        }

        try (PrintWriter w = new PrintWriter(args[1])) {
            for (String s : out) w.println(s);
        }
        println("EmuDiff: " + ok + " returned, " + faulted + " faulted -> "
                + args[1]);
    }

    private Case parse(String line) {
        String[] f = line.split("\\s+");
        if (!f[0].equals("CASE") || f.length < 3)
            throw new IllegalArgumentException("expected: CASE <name> <addr>");
        Case c = new Case();
        c.raw = line;
        c.name = f[1];
        c.addr = num(f[2]);
        for (int i = 3; i < f.length; i++) {
            int eq = f[i].indexOf('=');
            if (eq < 0) continue;
            String k = f[i].substring(0, eq), v = f[i].substring(eq + 1);
            if (k.equals("eax")) c.eax = num(v);
            else if (k.equals("edx")) c.edx = num(v);
            else if (k.equals("ecx")) c.ecx = num(v);
            else if (k.equals("stk")) {
                for (String s : v.split(",")) c.stack.add(num(s));
            } else if (k.equals("mem")) {
                int colon = v.indexOf(':');
                c.memAddr.add(new long[]{ num(v.substring(0, colon)) });
                c.memData.add(hex(v.substring(colon + 1)));
            }
            /* f.* keys are for the Pascal side and ignored here. */
        }
        return c;
    }

    private static long num(String s) {
        s = s.trim();
        boolean neg = s.startsWith("-");
        if (neg) s = s.substring(1);
        long v = s.toLowerCase().startsWith("0x")
                ? Long.parseLong(s.substring(2), 16) : Long.parseLong(s);
        return neg ? -v : v;
    }

    private static byte[] hex(String s) {
        byte[] b = new byte[s.length() / 2];
        for (int i = 0; i < b.length; i++)
            b[i] = (byte) Integer.parseInt(s.substring(i * 2, i * 2 + 2), 16);
        return b;
    }

    /** One __register call. Returns EAX as an unsigned 32-bit value. */
    private long call(Case c) throws Exception {
        EmulatorHelper emu = new EmulatorHelper(currentProgram);
        try {
            for (int i = 0; i < c.memAddr.size(); i++)
                emu.writeMemory(toAddr(c.memAddr.get(i)[0]), c.memData.get(i));

            /* Arguments past the third are pushed right to left, so the
             * leftmost ends up nearest the return address. */
            long sp = STACK_TOP;
            for (int i = c.stack.size() - 1; i >= 0; i--) {
                sp -= 4;
                emu.writeMemory(toAddr(sp), int32(c.stack.get(i)));
            }
            sp -= 4;
            emu.writeMemory(toAddr(sp), int32(RETURN_TO));

            emu.writeRegister("ESP", BigInteger.valueOf(sp));
            emu.writeRegister("EBP", BigInteger.valueOf(STACK_TOP));
            emu.writeRegister("EAX", BigInteger.valueOf(c.eax & 0xFFFFFFFFL));
            emu.writeRegister("EDX", BigInteger.valueOf(c.edx & 0xFFFFFFFFL));
            emu.writeRegister("ECX", BigInteger.valueOf(c.ecx & 0xFFFFFFFFL));
            emu.writeRegister(emu.getPCRegister().getName(),
                              BigInteger.valueOf(c.addr));
            emu.setBreakpoint(toAddr(RETURN_TO));

            String pcName = emu.getPCRegister().getName();
            for (int steps = 0; steps < STEP_CAP; steps++) {
                if (!emu.step(monitor)) {
                    String err = emu.getLastError();
                    throw new Exception(err == null ? "step failed" : err);
                }
                long pc = emu.readRegister(pcName).longValue() & 0xFFFFFFFFL;
                if (pc == RETURN_TO)
                    return emu.readRegister("EAX").longValue() & 0xFFFFFFFFL;
            }
            throw new Exception("did not return within " + STEP_CAP + " steps");
        } finally {
            emu.dispose();
        }
    }

    private static byte[] int32(long v) {
        return new byte[]{ (byte) v, (byte) (v >> 8),
                           (byte) (v >> 16), (byte) (v >> 24) };
    }
}
