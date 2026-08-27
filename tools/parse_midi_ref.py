#!/usr/bin/env python3
"""Reference parser for the game's MIDI playlist.

Second opinion on src/MidiFile.pas, the same way decode_wav_ref.py is a second
opinion on src/WaveFile.pas. Both were written from the SMF spec; if they agree
on the merged event stream of all 15 tracks, the Pascal reader's chunk walk,
running-status handling, tempo map and k-way track merge are all corroborated.

The checksum deliberately covers the MERGED stream rather than each track, so
merging the tracks in the wrong order changes it. Event count alone would not.

Usage:
    akuji.exe --selftest-midi "<game dir>"      # writes src/selftest.log
    python parse_midi_ref.py "<game dir>" [src/selftest.log]

With a log path it diffs against the Pascal run and exits non-zero on any
mismatch; without one it just prints its own numbers.
"""

import os
import struct
import sys

# From the form resource's AutoLoadMidis, and from the static array[0..14] of
# AnsiString at VA 0x00468D14 in the executable. Both agree.
PLAYLIST = [
    "init", "main01", "gameover", "boss01", "itemget", "open01", "end01",
    "main02", "open02", "boss02", "end02", "soulget", "end03", "end04",
    "end05",
]

# Must match TMidiEventKind in src/MidiFile.pas.
MEK_SHORT, MEK_SYSEX, MEK_TEMPO, MEK_EOT = 0, 1, 2, 3

DEFAULT_TEMPO_US = 500000   # 120 bpm, the SMF default


class Reader:
    def __init__(self, data, pos=0, limit=None):
        self.d = data
        self.p = pos
        self.limit = len(data) if limit is None else limit

    def byte(self):
        if self.p >= self.limit:
            return 0
        b = self.d[self.p]
        self.p += 1
        return b

    def be16(self):
        return (self.byte() << 8) | self.byte()

    def be32(self):
        return (self.byte() << 24) | (self.byte() << 16) | \
               (self.byte() << 8) | self.byte()

    def vlq(self):
        val = 0
        for _ in range(4):
            b = self.byte()
            val = (val << 7) | (b & 0x7F)
            if not (b & 0x80):
                break
        return val


def parse_track(r, track_end):
    """Returns a list of (tick, kind, msg) in the track's own order."""
    events = []
    tick = 0
    running = 0

    while r.p < track_end:
        tick += r.vlq()
        if r.p >= track_end:
            break

        status = r.d[r.p]
        if status >= 0x80:
            r.p += 1
            # F0/F7/FF are not channel messages and must not become the
            # running status.
            if status < 0xF0:
                running = status
        else:
            status = running

        if status == 0:
            break

        high = status & 0xF0
        if high in (0x80, 0x90, 0xA0, 0xB0, 0xE0):
            d1, d2 = r.byte(), r.byte()
            events.append((tick, MEK_SHORT, status | (d1 << 8) | (d2 << 16)))
        elif high in (0xC0, 0xD0):
            d1 = r.byte()
            events.append((tick, MEK_SHORT, status | (d1 << 8)))
        elif status == 0xFF:
            meta = r.byte()
            length = r.vlq()
            if meta == 0x51:
                usec = (r.byte() << 16) | (r.byte() << 8) | r.byte()
                if length > 3:
                    r.p += length - 3
                events.append((tick, MEK_TEMPO, usec))
            elif meta == 0x2F:
                r.p += length
                events.append((tick, MEK_EOT, 0))
            else:
                r.p += length          # names, lyrics - skipped, not stored
        elif status in (0xF0, 0xF7):
            length = r.vlq()
            r.p += length
            events.append((tick, MEK_SYSEX, 0))
        else:
            break                       # out of sync; abandon the track

    return events


def parse_midi(path):
    data = open(path, "rb").read()
    r = Reader(data)
    if r.be32() != 0x4D546864:          # 'MThd'
        raise ValueError("not an SMF")
    header_len = r.be32()
    fmt = r.be16()
    ntrks = r.be16()
    division = r.be16()
    if division & 0x8000 or division == 0:
        raise ValueError("SMPTE or zero division")
    r.p = 8 + header_len

    tracks = []
    while len(tracks) < ntrks and r.p + 8 <= len(data):
        cid = r.be32()
        clen = r.be32()
        if cid != 0x4D54726B:           # 'MTrk'
            r.p += clen
            continue
        end = min(r.p + clen, len(data))
        tracks.append(parse_track(r, end))
        r.p = end

    # k-way merge: lowest tick wins, ties to the lower-numbered track. Python's
    # sort is stable, so sorting the concatenation by tick alone with the track
    # index as a tiebreaker gives the identical order.
    merged = []
    for ti, tr in enumerate(tracks):
        for order, ev in enumerate(tr):
            merged.append((ev[0], ti, order, ev[1], ev[2]))
    merged.sort(key=lambda e: (e[0], e[1], e[2]))

    # Tempo map -> absolute microseconds.
    tempo = DEFAULT_TEMPO_US
    last_tick = 0
    acc = 0
    for tick, _ti, _order, kind, msg in merged:
        acc += ((tick - last_tick) * tempo) // division
        last_tick = tick
        if kind == MEK_TEMPO:
            tempo = msg

    checksum = 0
    for tick, _ti, _order, kind, msg in merged:
        for value in (tick, msg, kind):
            checksum = (((checksum << 1) | (checksum >> 31)) & 0xFFFFFFFF) ^ \
                       (value & 0xFFFFFFFF)

    return {
        "format": fmt,
        "tracks": ntrks,
        "division": division,
        "events": len(merged),
        "ms": acc // 1000,
        "checksum": checksum,
    }


def read_pascal_log(path):
    """Pulls the table out of selftest.log written by --selftest-midi."""
    rows = {}
    for line in open(path, encoding="utf-8", errors="replace"):
        parts = line.split()
        if len(parts) == 7 and parts[0] in PLAYLIST:
            try:
                rows[parts[0]] = {
                    "format": int(parts[1]),
                    "tracks": int(parts[2]),
                    "division": int(parts[3]),
                    "events": int(parts[4]),
                    "ms": int(parts[5]),
                    "checksum": int(parts[6], 16),
                }
            except ValueError:
                pass
    return rows


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    game_dir = sys.argv[1]
    theirs = read_pascal_log(sys.argv[2]) if len(sys.argv) > 2 else {}

    print("name        fmt trks  div   events   ms  checksum")
    fails = 0
    for name in PLAYLIST:
        path = os.path.join(game_dir, "midi", name + ".mid")
        try:
            got = parse_midi(path)
        except Exception as exc:                     # noqa: BLE001
            print("%-11s PARSE FAILED: %s" % (name, exc))
            fails += 1
            continue

        print("%-11s %3d %4d %4d %8d %6d  %08X" % (
            name, got["format"], got["tracks"], got["division"],
            got["events"], got["ms"], got["checksum"]))

        if theirs:
            if name not in theirs:
                print("            ^ missing from the Pascal log")
                fails += 1
            elif theirs[name] != got:
                print("            ^ MISMATCH, Pascal reported %r" % (theirs[name],))
                fails += 1

    if theirs:
        print()
        print("compared %d tracks against the Pascal reader, %d mismatches"
              % (len(PLAYLIST), fails))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
