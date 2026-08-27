#!/usr/bin/env python3
"""Extract a QDA0 archive (Akuji the Demon's bmp.qda).

Format, recovered 2026-08-27 and validated against bmp.qda:

    offset  size  meaning
    0x00    4     zero
    0x04    4     magic "QDA0"
    0x08    4     entry count (44 in bmp.qda)
    0x0C    244   zero padding to 0x100
    0x100   n*268 directory
    ...           file data, in directory order

  Each 268-byte directory entry:
    +0x00   4     absolute offset of the data
    +0x04   4     size
    +0x08   4     size again (equal in every entry - the format allows for
                  compression but bmp.qda stores everything uncompressed)
    +0x0C   256   NUL-terminated name

Validation: the directory size plus the sum of every entry size equals the
file length exactly, so no padding or trailing data is unaccounted for.

Usage:  extract_qda.py bmp.qda [outdir]
        extract_qda.py bmp.qda --list
"""

import os
import struct
import sys

HEADER_SIZE = 0x100
ENTRY_SIZE = 268
MAGIC = b"QDA0"


def read_directory(data):
    if data[4:8] != MAGIC:
        raise ValueError("not a QDA0 archive (magic is %r)" % data[4:8])
    count = struct.unpack_from("<I", data, 8)[0]
    entries = []
    for i in range(count):
        base = HEADER_SIZE + i * ENTRY_SIZE
        offset, size, usize = struct.unpack_from("<III", data, base)
        name = data[base + 12:base + ENTRY_SIZE].split(b"\x00")[0].decode("latin1")
        entries.append((name, offset, size, usize))
    return entries


def bmp_info(blob):
    """Dimensions of an uncompressed BMP, or None if it isn't one."""
    if blob[:2] != b"BM":
        return None
    w, h = struct.unpack_from("<ii", blob, 18)
    bpp = struct.unpack_from("<H", blob, 28)[0]
    return w, h, bpp


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1

    path = argv[1]
    with open(path, "rb") as fh:
        data = fh.read()

    entries = read_directory(data)

    accounted = HEADER_SIZE + len(entries) * ENTRY_SIZE + sum(e[2] for e in entries)
    if accounted != len(data):
        print("WARNING: %d bytes accounted for, file is %d"
              % (accounted, len(data)), file=sys.stderr)

    listing = "--list" in argv
    outdir = None
    if not listing:
        outdir = argv[2] if len(argv) > 2 else "qda_out"
        os.makedirs(outdir, exist_ok=True)

    for name, offset, size, _ in entries:
        blob = data[offset:offset + size]
        info = bmp_info(blob)
        shape = "%dx%d %dbpp" % info if info else "not a BMP"
        print("%-18s %9d %8d  %s" % (name, offset, size, shape))
        if outdir:
            # Names in the archive mix case (sys.BMP, title.BMP); keep them as
            # stored so lookups from the .dat metadata still match.
            with open(os.path.join(outdir, name), "wb") as out:
                out.write(blob)

    print("\n%d entries%s" % (len(entries),
                              "" if listing else ", written to %s/" % outdir))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
