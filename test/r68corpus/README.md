# Comparing r68 sources with Microware's assemblers

Scripts that take any set of r68 sources (whatever is on a disk), assemble them with
`m68k-os9-r68` and with Microware's own assemblers, Ultra C's `r68` (Windows, through WSL interop)
and C 3.2's `r68` (DOS, in vDos), and compare the objects. See "Microware compatibility" in
`src/m68k-os9-tools/r68togas.md`. Machine specific: every path is a setting in the environment or
an argument.

Nothing is written beside the sources: objects, listings and logs go to the work directory and,
for C 3.2's `r68`, to `OUT`. **Microware's assemblers run only in a mirror** of the sources
(`mirror.py`), never in the originals' directories: C 3.2's `r68` has no `-u` (`use` is relative
to the current directory) and has left temp files (`rma.NNN`) there; `m68k-os9-r68`, which
writes nothing beside its input, runs on the originals. Microware's outputs are never stored in
the repository.

## Steps

1. The list (Windows Python): `python psectscan.py <root> list.txt`: the `.s` files with a
   `psect` line, one per content. Copy it to `$WORK/list.txt`.
2. The mirror (Windows Python): `python mirror.py list.txt <mirror root> mirlist.txt`: each
   source's directory and its two parents (text files), and every file a `use` names (any kind,
   any subdirectory); `mirlist.txt` has the mirrored paths, line for line. Copy it to
   `$WORK/mirlist.txt`.
3. The defs directory `$WORK/defs`: the files the sources `use` with `<...>` (and the target's
   `oskdefs.d`). The same files in an 8.3 directory for vDos (`RCDEFS`).
4. Ultra C's `r68` (WSL): `R68=<r68.exe> bash run.sh ucc`. `WORK` and `DEFS` must
   be on a Windows drive (`/mnt/c/...`): `r68.exe` can't use `\\wsl.localhost\...` paths for
   `-u` and `-o`.
5. C 3.2's assembler (Git Bash, with a vDos job poller running): `MIRLIST=... MIRROR=... OUT=...
   RCDEFS=... VJOB=... bash rc.sh` (`r68`; `ASM=r68020 ASMOPTS=-m2` for its 68020 assembler).
6. Ours, compared with both (WSL, `m68k-os9-r68` and the `m68k-elfos9` binutils in `PATH`):
   `RC=<OUT as a WSL path> bash run.sh ours r1` (Ultra C's dialect) and `... bash
   run.sh ours r2 -dialect=c32`. `python diffkinds.py <work>/r1 mw` (or `c32`) groups the
   differences by instruction.

`dis.sh` makes the normalized listing that is compared: the code from a link of the object
alone, the data, the global symbols, the relocations (sorted; PC-relative ones to symbols the
object defines left out), sections padded to a multiple of 4 (Ultra C's `r68` pads to 4 with
`nop` or `trapf`, C 3.2's to 2; a final `trapf` word is taken as `nop`). Undefined symbols are
listed as `U` where a relocation uses them, as `U-unused` where nothing does (the Microware
assemblers write no reference for those); a link-time expression's terms, named only in its
note (`rof2elf`'s objects have them as symbols, ours don't), are left out.
