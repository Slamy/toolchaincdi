# Comparing r68 sources with Microware's assemblers

Nothing is written beside the sources: objects, listings and logs go to the work directory and,
for C 3.2's `r68`, to `OUT`. **Microware's assemblers run only in a mirror** of the sources
(`mirror.py`), never in the originals' directories: C 3.2's `r68` has no `-u` (`use` is relative
to the current directory) and has left temp files (`rma.NNN`) there; `m68k-os9-r68`, which
writes nothing beside its input, runs on the originals. Microware's outputs are never stored in
the repository.

## Steps

`dis.sh` makes the normalized listing that is compared: the code from a link of the object
alone, the data, the global symbols, the relocations (sorted; PC-relative ones to symbols the
object defines left out), sections padded to a multiple of 4 (Ultra C's `r68` pads to 4 with
`nop` or `trapf`, C 3.2's to 2; a final `trapf` word is taken as `nop`). Undefined symbols are
listed as `U` where a relocation uses them, as `U-unused` where nothing does (the Microware
assemblers write no reference for those); a link-time expression's terms, named only in its
note (`rof2elf`'s objects have them as symbols, ours don't), are left out.
