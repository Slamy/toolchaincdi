# toolchaincdi

A GCC toolchain for developing CD-i (or OS-9/68000) applications, as a Docker image.

This is a fork of [murachue/toolchaincdi](https://github.com/murachue/toolchaincdi), with
everything Murachue built kept as it is. It adds interoperability with Microware's OS-9 C
compilers, assemblers, linkers and libraries:

- newlib built for both calling conventions, with an OS-9 runtime;
- drop-ins for Microware's compiler drivers, assembler, linker and librarian, which run existing
  makefiles with GCC and the GNU tools, and converters between Microware's ROF objects and ELF:
  the [m68k-os9-tools](https://github.com/cdifan/m68k-os9-tools) repository.

See [OS9-COMPAT-DESIGN.md](OS9-COMPAT-DESIGN.md) for the design. [`test/`](test/) holds the
tests (see "Tests" below).

## Repositories

The submodules come from forks under [github.com/cdifan](https://github.com/cdifan), each on its
own branch, next to Murachue's unchanged one where Murachue's repository has one:

| Submodule | Repository | Branch |
|---|---|---|
| `src/gcc` | [cdifan/gcc](https://github.com/cdifan/gcc) | `11.1.0-os9-compat` (`11.1.0-os9` is Murachue's) |
| `src/newlib-cygwin` | [cdifan/newlib-cygwin](https://github.com/cdifan/newlib-cygwin) | `newlib-4.1.0-os9-compat` |

# Ingredients

- binutils (`m68k-elfos9-*`)
    - _no_ linker script for elf2mod, you must prepare that (or use `m68k-os9-gcc` or
      `m68k-os9-l68`, which have one)
    - `m68k-elfos9-as` defaults to a 68020-class CPU; assemble hand-written code with `-m68000
      --pcrel`, so it rejects instructions the 68000/68070 lacks and keeps branches PC-relative
- gcc with OS-9/68000 customization (`m68k-elfos9-gcc`)
    - `-ma6rel` (with `-mpcrel`) is required for OS-9
    - `-mbsrw` may shrink your app a bit
    - the OS-9 options (`-mos9call` and the others) are in GCC's manual, under the m68k options
- newlib
    - built twice (multilibs): for GCC's own calling convention and for `-mos9call`; the driver
      picks the right `libc.a` from the flags
    - with an OS-9 runtime in libgloss (`-specs=os9.specs`: startup, system calls, linker
      script), which `m68k-os9-gcc` uses; without it, no system calls: implement them yourself,
      with `_` prefix
- the [m68k-os9-tools](https://github.com/cdifan/m68k-os9-tools) (see its README)
    - `m68k-os9-gcc`: compiles and links a module in one step, with GCC's options
    - `m68k-os9-xcc`, `m68k-os9-ucc`, `m68k-os9-r68`, `m68k-os9-l68`, `m68k-os9-libgen`: drop-ins
      for Microware's tools, with the user's own Microware headers and libraries
    - `elf2mod`, `rof2elf`, `elf2rof`, `r68togas`, `gastor68`: converters and translators
      between Microware's formats and the GNU tools'
- psximager
    - psxbuild with CD-BRIDGE is your friend
    - no ability to make native CD-i image

# Tests

- `test/baseline`: the toolchain against the unmodified fork (no regression).
- `test/dejagnu`: GCC's own test suite for the OS-9 options.
- `test/abi-exec`: compiled and linked programs run in a 68000 emulator, and the OS-9 targets on
  CD-i Emulator or a real CD-i player (`make check-os9` and the others).
- `test/l68cmp`: links compared with Microware's `l68`.
- `test/os9c`: Microware C probes, for the calling convention and for stack checking.

# How to use?

An example: a CD-i disc with two programs, built with GNU Make in the Docker image. `HELLO` is plain
C with GCC's options and newlib; `CDI_TEST.APP` is a program written for Microware C 3.2, with a
function in r68 assembler, built with the C 3.2 compiler driver's options, as an old makefile
would build it.

You'll get the disc image `build.bin` and its `build.cue`.

- **`HELLO`** needs nothing but the image: `m68k-os9-gcc` brings the startup code, the C library
  and the linker script (see `m68k-os9-gcc.md` in
  [m68k-os9-tools](https://github.com/cdifan/m68k-os9-tools)).
- **`CDI_TEST.APP`** uses Microware's own files, which are not included: mount your copy of the
  C 3.2 kit and point `CDEF` (headers) and `CLIB` (`cstart.r` and the libraries) at it.
  `m68k-os9-xcc` takes the options of Microware's `xcc`/`cc`, compiles with GCC in Microware's
  calling convention, assembles `.a` files with `m68k-os9-r68`, and links with `m68k-os9-l68`, which
  converts `cstart.r` and the libraries from ROF on the way. The converted files go to a cache
  (`M68K_OS9_ELF=cache=...`, here in the work directory, since the container's user has no home);
  nothing is written beside your kit. With `-r=RELS` the objects are ELF; `-obj=rof` writes ROFs
  that Microware's own `l68` links too.

Note that if you run docker without `-u`, built files are owned by root. Be careful.

psxbuild (libcdio) will say something about failing filename constraints, but it's OK.

The image is built by GitHub Actions on every push to `main` and published as
`ghcr.io/cdifan/toolchaincdi`. The original `ghcr.io/murachue/toolchaincdi` image predates this
fork's changes.

# License

MIT for Dockerfile.

The submodules keep their own licenses. The GCC and newlib changes are distributed under
the licenses of the files they modify (GCC: GPL version 3 or later). See section 10 of
[OS9-COMPAT-DESIGN.md](OS9-COMPAT-DESIGN.md) for authorship and upstreaming notes.
