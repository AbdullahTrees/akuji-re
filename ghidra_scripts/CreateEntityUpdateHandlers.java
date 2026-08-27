/* Create the entity-type update handlers that auto-analysis cannot find.
 *
 * Entity_UpdateAll @ 0x004608BC switches on EF_TYPE into one handler per entity
 * type. 48 of those handlers are FRAMELESS - Borland omits push ebp / mov
 * ebp,esp when a routine needs no stack frame - so they do not start with
 * 55 8B EC and Ghidra's Function Start Search will never match them. Re-running
 * auto-analysis does not help and cannot help.
 *
 * This script does not search for anything. The 48 addresses below were read
 * out of Entity_UpdateAll's switch, one per case arm, and are hard-coded with
 * the type number they belong to. It touches those addresses and nothing else,
 * which is what makes it safe in a binary full of Delphi string literals that
 * happen to decode as valid x86 - the failure mode that already mangled the
 * '.' literal at 0x0045520C.
 *
 * Each function is named EntityUpdate_TypeNN. That name is a claim about what
 * the function IS, and the evidence for it is that Entity_UpdateAll reaches it
 * from the case arm for type NN. Nothing about the body is being asserted.
 *
 * Run from Window -> Script Manager. It reports what it did and changes
 * nothing that already exists.
 */
//@category Akuji
//@menupath Tools.Create Entity Update Handlers
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;

public class CreateEntityUpdateHandlers extends GhidraScript {

    /* { entity type, handler address }, from Entity_UpdateAll's switch. */
    private static final long[][] HANDLERS = {
        {  1, 0x004585A8L }, {  3, 0x00459EB4L }, {  4, 0x00459F1CL },
        {  5, 0x00459F6CL }, {  6, 0x0045A020L }, {  7, 0x0045A08CL },
        {  8, 0x0045A0E4L }, {  9, 0x0045A120L }, { 10, 0x0045A184L },
        { 11, 0x0045A1C0L }, { 12, 0x0045A20CL }, { 13, 0x0045A24CL },
        { 14, 0x0045A3E0L }, { 15, 0x0045A95CL }, { 16, 0x0045A944L },
        { 17, 0x0045A9D4L }, { 19, 0x0045A9D0L }, { 21, 0x0045AA10L },
        { 24, 0x0045A43CL }, { 25, 0x0045A4F0L }, { 26, 0x0045A50CL },
        { 27, 0x0045A540L }, { 28, 0x0045A580L }, { 29, 0x0045AB64L },
        { 31, 0x0045AC94L }, { 35, 0x0045AFA8L }, { 40, 0x0045B3ECL },
        { 43, 0x0045BBD8L }, { 45, 0x0045BCC4L }, { 49, 0x0045C250L },
        { 50, 0x0045C430L }, { 51, 0x0045C608L }, { 53, 0x0045CA28L },
        { 56, 0x0045CE78L }, { 59, 0x0045D670L }, { 63, 0x0045DDF4L },
        { 64, 0x0045E030L }, { 65, 0x0045E25CL }, { 68, 0x0045EA40L },
        { 70, 0x0045EC4CL }, { 71, 0x0045ED88L }, { 72, 0x0045EFC8L },
        { 74, 0x0045F498L }, { 75, 0x0045F668L }, { 77, 0x0045F85CL },
        { 78, 0x0046023CL }, { 79, 0x004603B4L }, { 80, 0x004607E8L },
    };

    @Override
    public void run() throws Exception {
        int already = 0, made = 0, failed = 0;

        for (long[] entry : HANDLERS) {
            int type = (int) entry[0];
            Address addr = toAddr(entry[1]);
            String name = String.format("EntityUpdate_Type%02d", type);

            Function existing = getFunctionAt(addr);
            if (existing != null) {
                println(String.format("t%-2d %s already a function: %s",
                        type, addr, existing.getName()));
                already++;
                continue;
            }

            /* Only disassemble when there is no instruction there yet. If the
               bytes are already code this is a no-op, and we avoid clearing
               anything that another function may own. */
            if (getInstructionAt(addr) == null) {
                disassemble(addr);
            }

            Function created = createFunction(addr, name);
            if (created == null) {
                println(String.format("t%-2d %s FAILED to create", type, addr));
                failed++;
            } else {
                println(String.format("t%-2d %s -> %s", type, addr, name));
                made++;
            }
        }

        println("");
        println(String.format("created %d, already present %d, failed %d, of %d",
                made, already, failed, HANDLERS.length));
        if (failed > 0) {
            println("A failure usually means the address sits inside a function that");
            println("already owns it. Clear that function first, then re-run.");
        }
    }
}
