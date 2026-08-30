# Test fixtures

## save.dat

The English release's **shipped** save, exactly as distributed: stage early
enough that only the dash is unlocked, with progress flag 0 set.

`SelfTestPlayer` pins four ability bytes and the guard flag against this file.
It is the evidence that `LoadSave` reads the real format, so it has to be a
real file rather than one this repository writes.

**It lives here, not in the game directory, because the game OVERWRITES the
copy in `<game>/data/save.dat` whenever you save at a statue.** That is how the
original was lost on 2026-08-30: a playtest session wrote over it, the pinned
numbers stopped matching, and no copy survived - the game directory is
gitignored and the file was never tracked.

If this file is missing the test SKIPS rather than failing, and says so. Restore
it by taking `data/save.dat` from a fresh copy of the English release
("Akuji the Demon" Win EN by D, v1.1) and putting it here. Do not substitute a
played save: `akuji_ver101/data/save.dat` is stage 30 with all four abilities
unlocked, and any save of your own has whatever you last did in it. Either one
would still read correctly and prove nothing about the shipped state.
