#!/usr/bin/env python3
"""Reference decoder for the game's sound effects.

This deliberately duplicates src/WaveFile.pas. It is not a helper for the
Pascal, it is a *second opinion* on it: both were written from the RIFF spec
and the observed file layout, and the point is that two independent readers
agree byte for byte on all 57 effects. That is the same technique used to
validate the QDA archive reader against src/QdaArchive.pas.

Usage:
    # 1. have the game write what its own reader produced
    akuji.exe --selftest-audio "<game dir>" "<pcm out dir>"

    # 2. decode the same files here and diff
    python decode_wav_ref.py "<game dir>" "<pcm out dir>"

Exit code 0 means every effect matched.
"""

import os
import struct
import sys

MIX_RATE = 22050

# The 57 names, in the order the executable stores them, from the static
# array[0..56] of AnsiString at VA 0x00468D50. Kept here rather than parsed out
# of the exe so this script stays a genuinely independent check of the table in
# src/SoundTable.pas.
SOUND_NAMES = [
    "pi.wav", "ok.wav", "ng.wav", "jump.wav", "yuka01.wav", "shot01.wav",
    "power01.wav", "shot02.wav", "yuka02.wav", "pon01.wav", "pon02.wav",
    "voice01.wav", "voice02.wav", "kakunin.wav", "kachi01.wav", "kin01.wav",
    "get01.wav", "hit01.wav", "bom01.wav", "power02.wav", "kachi02.wav",
    "puu01.wav", "bom02.wav", "shot03.wav", "open01.wav", "shot04.wav",
    "jump02.wav", "yuka03.wav", "puu02.wav", "voice03.wav", "shot05.wav",
    "water01.wav", "open02.wav", "jump03.wav", "bom03.wav", "voice04.wav",
    "voice05.wav", "power03.wav", "shot06.wav", "kachi03.wav", "water02.wav",
    "voice06.wav", "yuka04.wav", "shot07.wav", "bell.wav", "pi02.wav",
    "shot08.wav", "move01.wav", "bom04.wav", "bom05.wav", "shot09.wav",
    "kachi04.wav", "shot10.wav", "run.wav", "kodou.wav", "voice07.wav",
    "get02.wav",
]


def parse_wave(path):
    """Return (samples, rate, bits, channels); samples are signed 16-bit mono
    at MIX_RATE, matching what WaveFile.LoadWave produces."""
    data = open(path, "rb").read()
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise ValueError("not a RIFF/WAVE file")

    fmt = None
    raw = None
    pos = 12
    # A real chunk walk: 49 of the 57 files carry a 'fact' chunk between 'fmt '
    # and 'data', so assuming an order silently reads the wrong bytes.
    while pos + 8 <= len(data):
        cid = data[pos:pos + 4]
        size = struct.unpack("<I", data[pos + 4:pos + 8])[0]
        body = data[pos + 8:pos + 8 + size]
        if cid == b"fmt ":
            fmt = struct.unpack("<HHIIHH", body[:16])
        elif cid == b"data":
            raw = body
        pos += 8 + size + (size & 1)  # chunks are word-aligned

    if fmt is None or raw is None:
        raise ValueError("missing fmt or data chunk")

    tag, channels, rate, _avg, _align, bits = fmt
    if tag != 1:
        raise ValueError("not PCM (tag %d)" % tag)
    if bits not in (8, 16):
        raise ValueError("unsupported bit depth %d" % bits)

    bps = bits // 8
    frames = len(raw) // (bps * channels)
    out = []
    for i in range(frames):
        acc = 0
        for c in range(channels):
            p = (i * channels + c) * bps
            if bits == 8:
                # 8-bit RIFF PCM is unsigned, silence at 128
                acc += (raw[p] - 128) * 256
            else:
                acc += struct.unpack("<h", raw[p:p + 2])[0]
        out.append(acc // channels)

    if rate < MIX_RATE and MIX_RATE % rate == 0:
        factor = MIX_RATE // rate
        out = [s for s in out for _ in range(factor)]

    return out, rate, bits, channels


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    game_dir, pcm_dir = sys.argv[1], sys.argv[2]

    # Independent check of the table itself: the names the exe stores and the
    # files on disk must be the same set, with nothing left over either way.
    on_disk = {f.lower() for f in os.listdir(os.path.join(game_dir, "wav"))}
    in_table = {n.lower() for n in SOUND_NAMES}
    if on_disk != in_table:
        print("TABLE MISMATCH")
        print("  in table, not on disk:", sorted(in_table - on_disk))
        print("  on disk, not in table:", sorted(on_disk - in_table))
        return 1
    print("sound table: %d names, exactly matches wav/ on disk" % len(SOUND_NAMES))

    fails = 0
    checked = 0
    formats = {}
    for i, name in enumerate(SOUND_NAMES):
        src = os.path.join(game_dir, "wav", name)
        try:
            samples, rate, bits, channels = parse_wave(src)
        except Exception as exc:                      # noqa: BLE001
            print("%3d %-16s DECODE FAILED: %s" % (i, name, exc))
            fails += 1
            continue

        formats[(rate, bits, channels)] = formats.get((rate, bits, channels), 0) + 1

        got_path = os.path.join(pcm_dir, "%.2d.pcm" % i)
        if not os.path.exists(got_path):
            print("%3d %-16s no PCM from the Pascal reader" % (i, name))
            fails += 1
            continue

        mine = struct.pack("<%dh" % len(samples), *samples)
        theirs = open(got_path, "rb").read()
        checked += 1
        if mine != theirs:
            fails += 1
            if len(mine) != len(theirs):
                print("%3d %-16s LENGTH %d vs %d" % (i, name, len(mine), len(theirs)))
            else:
                bad = next(j for j in range(len(mine)) if mine[j] != theirs[j])
                print("%3d %-16s DIFFERS at byte %d" % (i, name, bad))

    print()
    print("source formats found (rate, bits, channels) -> count:")
    for k in sorted(formats):
        print("   %s -> %d" % (k, formats[k]))
    print()
    print("compared %d effects, %d mismatches" % (checked, fails))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
