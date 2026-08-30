# Test fixtures

## save.dat

An **early-game save**: stage 2, 46 seconds, the starting jump and weapon, and
the dash as the only unlocked ability, with progress flag 0 set.

Provenance matters here. The file distributed with the English release was lost
on 2026-08-30 - a playtest session saved over it and no copy was tracked. This
is a replacement, supplied 2026-08-31: a genuine game-written save of the same
shape, not the shipped bytes. That is enough for what the test actually claims,
because the game wrote the file and so it is real evidence about the format -
but do not describe it as the shipped save.

`SelfTestPlayer` pins four ability bytes and the guard flag against this file.
It is the evidence that `LoadSave` reads the real format, so it has to be a
real file rather than one this repository writes.

**It lives here, not in the game directory, because the game OVERWRITES the
copy in `<game>/data/save.dat` whenever you save at a statue.** That is how the
original was lost on 2026-08-30: a playtest session wrote over it, the pinned
numbers stopped matching, and no copy survived - the game directory is
gitignored and the file was never tracked.

If this file is missing the test SKIPS rather than failing, and says so.
Replace it with an EARLY save - one where only the dash is unlocked - and
re-derive the pinned numbers in `SelfTestPlayer` from the new file rather than
bending them to fit. `akuji_ver101/data/save.dat` will not do: it is stage 30
with all four abilities, so it reads correctly and proves nothing about the
early state the pin is testing.
