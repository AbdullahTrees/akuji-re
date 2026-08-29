/* akuji_powerup.js - a focused trace of ONE thing: collecting a power-up orb.
 *
 *   cd "<gamedir>"
 *   frida -f akuji.exe -l akuji_powerup.js
 *
 * Then: NEW GAME, skip the opening with Z, walk to the dash orb in the first
 * room and collect it. Close the game. The log is akuji_powerup.log.
 *
 * WHY A SECOND SCRIPT. The general trace answers "what runs, in what order".
 * This answers "what CHANGED", which is the question when a thing runs and has
 * no effect - the ability was not granted even though the panel appeared with
 * the right name, so the interesting record is the player's bytes either side
 * of the grant, not the call sequence.
 *
 * WHAT IT DUMPS, per event:
 *
 *   PlayerState[0..9]   the ability bytes. Head[4] is the dash, and byte 4
 *                       going 0 -> 1 across PowerUp_Show IS the grant.
 *   Weapon, Jump        +0x11CC and +0x11D0, the other two things a power-up
 *                       can change
 *   the ENTITY          slot, alive flag, EF_VARIANT (+0x18) and the sprite
 *                       handle (+0x10) - the variant is what the grant keys
 *                       off, and the sprite is what should stop being drawn
 *   the OVERLAY         active (0x0046CD00) and panel mode (0x0046CDA0)
 *
 * Every one of those globals is reached through a POINTER CELL, not read at
 * the address directly - see notes/trace_findings.md. Getting that wrong is
 * how the first trace reported three consecutive addresses as game state.
 */

'use strict';

var IMAGE_BASE = ptr(0x400000);

/* Functions, from notes/game_functions.txt. */
var F_POWERUP_SHOW = 0x456698;
var F_OVERLAY_UPDATE = 0x4568d0;
var F_ENTITY_DESTROY = 0x461400;
var F_PLAYER_TOUCH = 0x457880;
var F_ADVANCE_STEP = 0x45509c;

/* Pointer CELLS. Each holds the address of the thing, not the thing. */
var P_PLAYERSTATE = 0x46cff0;
var P_POOL = 0x46cb68;
var P_EVENTTABLE = 0x46cce0;
var P_EVENTID = 0x46ce7c;
var P_OVERLAY_ACTIVE = 0x46cd00;
var P_OVERLAY_MODE = 0x46cda0;

/* Layout, all established elsewhere in the project. */
var ENTITY_STRIDE = 0x104;
var EVENT_STRIDE = 0x24;
var EVENT_SLOT_AT = 0x08;
var EF_SPRITE_AT = 0x10;
var EF_ALIVE_AT = 0x08;
var EF_VARIANT_AT = 0x18;
var PS_WEAPON_AT = 0x11cc;
var PS_JUMP_AT = 0x11d0;

var mod = Process.mainModule;
var slide = mod.base.sub(IMAGE_BASE);

var logPath = 'akuji_powerup.log';
try {
    var BS = String.fromCharCode(92);
    var sep = mod.path.lastIndexOf(BS);
    if (sep < 0) { sep = mod.path.lastIndexOf('/'); }
    if (sep > 0) { logPath = mod.path.substring(0, sep + 1) + logPath; }
} catch (e) { /* keep the relative fallback */ }

var log = new File(logPath, 'w');
function emit(s) { log.write(s + '\n'); log.flush(); }

function deref(cell) {
    try { return slide.add(cell).readPointer(); } catch (e) { return null; }
}

function playerBytes() {
    var ps = deref(P_PLAYERSTATE);
    if (ps === null || ps.isNull()) { return '(no player state)'; }
    var out = [];
    for (var i = 0; i < 10; i++) {
        try { out.push(ps.add(i).readU8()); } catch (e) { out.push('?'); }
    }
    var w = '?', j = '?';
    try { w = ps.add(PS_WEAPON_AT).readS32(); } catch (e) { }
    try { j = ps.add(PS_JUMP_AT).readS32(); } catch (e) { }
    return 'head[0..9]=' + out.join(',') + '  weapon=' + w + ' jump=' + j;
}

/* The entity the CURRENT event points at - the one PowerUp_Show grants from. */
function eventEntity() {
    var idCell = deref(P_EVENTID);
    var tbl = deref(P_EVENTTABLE);
    var pool = deref(P_POOL);
    if (idCell === null || tbl === null || pool === null) { return '(globals unset)'; }
    var id;
    try { id = idCell.readS32(); } catch (e) { return '(no event id)'; }
    var slot;
    try {
        slot = tbl.add(id * EVENT_STRIDE + EVENT_SLOT_AT).readS32();
    } catch (e) { return 'event=' + id + ' (slot unreadable)'; }
    var e = pool.add(slot * ENTITY_STRIDE);
    var alive = '?', variant = '?', sprite = '?';
    try { alive = e.add(EF_ALIVE_AT).readU8(); } catch (ex) { }
    try { variant = e.add(EF_VARIANT_AT).readS32(); } catch (ex) { }
    try { sprite = e.add(EF_SPRITE_AT).readS32(); } catch (ex) { }
    return 'event=' + id + ' slot=' + slot + ' alive=' + alive +
           ' variant=' + variant + ' sprite=' + sprite;
}

function overlay() {
    var a = deref(P_OVERLAY_ACTIVE), m = deref(P_OVERLAY_MODE);
    var av = '?', mv = '?';
    try { av = a.readS32(); } catch (e) { }
    try { mv = m.readS32(); } catch (e) { }
    return 'overlay active=' + av + ' mode=' + mv;
}

function snap(tag) {
    emit(tag);
    emit('      ' + playerBytes());
    emit('      ' + eventEntity());
    emit('      ' + overlay());
}

emit('# akuji_powerup  base=' + mod.base);
emit('# collect the dash orb; head[4] going 0 -> 1 across PowerUp_Show is the grant');

Interceptor.attach(slide.add(F_POWERUP_SHOW), {
    onEnter: function () { snap('PowerUp_Show ENTER'); },
    onLeave: function () { snap('PowerUp_Show LEAVE'); }
});

Interceptor.attach(slide.add(F_ENTITY_DESTROY), {
    onEnter: function () {
        var pool = deref(P_POOL);
        var e = this.context.eax;
        var slot = '?';
        try {
            if (pool !== null) {
                slot = e.sub(pool).toInt32() / ENTITY_STRIDE;
            }
        } catch (ex) { }
        var sprite = '?';
        try { sprite = e.add(EF_SPRITE_AT).readS32(); } catch (ex) { }
        emit('Entity_Destroy  slot=' + slot + ' sprite=' + sprite +
             ' droploot=' + this.context.edx.toInt32());
    }
});

Interceptor.attach(slide.add(F_ADVANCE_STEP), {
    onEnter: function () { emit('EventScript_AdvanceStep'); }
});

var overlayFrames = 0;
Interceptor.attach(slide.add(F_OVERLAY_UPDATE), {
    onEnter: function () {
        /* Only the first and last few, or this drowns everything. */
        overlayFrames++;
        if (overlayFrames <= 3) { snap('Overlay_Update #' + overlayFrames); }
    },
    onLeave: function () {
        var a = deref(P_OVERLAY_ACTIVE);
        try {
            if (a.readS32() === 0) {
                snap('Overlay_Update CLOSED after ' + overlayFrames + ' frames');
                overlayFrames = 0;
            }
        } catch (e) { }
    }
});

Interceptor.attach(slide.add(F_PLAYER_TOUCH), {
    onEnter: function () { this.before = playerBytes(); },
    onLeave: function () {
        var after = playerBytes();
        if (after !== this.before) {
            emit('Entity_PlayerTouch CHANGED the player');
            emit('      before ' + this.before);
            emit('      after  ' + after);
        }
    }
});

console.log('akuji_powerup: writing ' + logPath);
