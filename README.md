# toolchaincdi

A GCC toolchain for developing CD-i (or OS-9/68000) applications, as a Docker image.

This is a fork of [murachue/toolchaincdi](https://github.com/murachue/toolchaincdi), with
everything Murachue built kept as it is. It adds interoperability with Microware's OS-9 C
compilers, assemblers, linkers and libraries:

- GCC options for Microware's calling conventions (`-mos9call`, `-mos9call=ucc`), stack checking
  (`-mos9stkchk`), line ends (`-mos9newline`), OS-9's math module (`-mos9math`) and more;
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
| `src/binutils-gdb` | [cdifan/binutils-gdb](https://github.com/cdifan/binutils-gdb) | `m68k-gas-fixes` |
| `src/newlib-cygwin` | [cdifan/newlib-cygwin](https://github.com/cdifan/newlib-cygwin) | `newlib-4.1.0-os9-compat` |
| `src/m68k-os9-tools` | [cdifan/m68k-os9-tools](https://github.com/cdifan/m68k-os9-tools) | `main-compat` (a fork of Murachue's elf2mod) |

psximager points at Murachue's repository. Murachue's own toolchain is
[murachue/toolchaincdi](https://github.com/murachue/toolchaincdi).

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
- `test/r68corpus`: r68 sources compared with Microware's assemblers.

# How to use?

An example: a CD-i disc with two programs, built with GNU Make in the Docker image. `HELLO` is plain
C with GCC's options and newlib; `CDI_TEST.APP` is a program written for Microware C 3.2, with a
function in r68 assembler, built with the C 3.2 compiler driver's options, as an old makefile
would build it.

```
$ cat <<'EOF' | sed 's/^    /\t/' > Makefile
all: build.bin

build.bin: build.cat build/CDI_TEST.APP build/HELLO build/ABSTRACT.TXT build/COPYRGHT.TXT build/BIBLIOGR.TXT
    psxbuild --cuefile build.cat build

# GCC's options; compiled, linked with newlib's OS-9 runtime and made into a module in one step
# (-Wm,-g: also the debugger's symbol module, build/HELLO.stb)
build/HELLO: hello.c
    m68k-os9-gcc -Os -o $@ $< -Wm,-g

# Microware C 3.2's xcc options, with your own copy of its headers and libraries
build/CDI_TEST.APP: RELS/game.r RELS/twice.r
    m68k-os9-xcc $^ -f=$@ -n=cdi_test -m=8

RELS/%.r: %.c
    m68k-os9-xcc -r=RELS $<

RELS/%.r: %.a
    m68k-os9-xcc -r=RELS $<
EOF
$ cat <<EOF > hello.c
#include <stdio.h>

int main(void)
{
    printf("hello from GCC and newlib\n");
    return 0;
}
EOF
$ cat <<EOF > game.c
#include <stdio.h>

extern int twice();

main()
{
    printf("twice 21 is %d\n", twice(21));
}
EOF
$ cat <<EOF > twice.a
 psect twice_a,0,0,0,0,0
* int twice(n): n in d0, the result in d0 (Microware C's convention)
twice: add.l d0,d0
 rts
 ends
EOF
$ mkdir build RELS
$ echo 'this is a test.' > build/ABSTRACT.TXT
$ echo 'public domain' > build/COPYRGHT.TXT
$ echo 'cdifan/toolchaincdi' > build/BIBLIOGR.TXT
$ cat <<EOF > build.cat
volume {
    system_id [CD-RTOS CD-BRIDGE]
    volume_id [TEST]
    volume_set_id [TEST]
    publisher_id [YOURNAME]
    preparer_id [YOURNAME]
    application_id [CDI_TEST.APP;1]
    copyright_file_id [COPYRGHT.TXT;1]
    abstract_file_id [ABSTRACT.TXT;1]
    bibliographic_file_id [BIBLIOGR.TXT;1]
}

dir {
    file CDI_TEST.APP
    file HELLO
    file COPYRGHT.TXT
    file ABSTRACT.TXT
    file BIBLIOGR.TXT
}
EOF
$ cat <<EOF > Dockerfile
FROM ghcr.io/cdifan/toolchaincdi
RUN apt update && apt install --no-install-recommends -y make && apt clean
EOF
$ docker run --rm -ti -v $PWD:/work -w /work -u $(id -u):$(id -g) \
    -v /path/to/your/OS9C:/os9c:ro -e CDEF=/os9c/DEFS -e CLIB=/os9c/LIB \
    -e M68K_OS9_ELF=cache=/work/.cache $(docker build -q .) make
```

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

# Windows

The toolchain also runs on Windows, without Docker. GitHub Actions builds it with
[`build-win64.sh`](build-win64.sh) (on Linux, with mingw-w64, for `x86_64-w64-mingw32`):

- on every push to `main`, as the artifact `toolchaincdi-<commit>-win64` of the "Build the
  Windows toolchain" run in the Actions tab (downloading it needs a GitHub login; artifacts
  expire after 90 days);
- for every release tag `v*`, as `toolchaincdi-<tag>-win64.zip` on the Releases page.

Unpack it anywhere and put its `bin` folder on `PATH`. `bin` has the tools under their long names
(`m68k-elfos9-gcc`, `m68k-os9-gcc`, `m68k-os9-xcc`, ...) and, for old makefiles, under the short
names of Microware's tools: `xcc` and `cc` (`m68k-os9-xcc`), `ucc` (`m68k-os9-xcc` in Ultra C
mode), `l68`, `r68` and `libgen`. `CDEF` and `CLIB` work as above, with Windows paths; in cmd:

```
set PATH=C:\toolchaincdi-v0.9.0-win64\bin;%PATH%
set CDEF=C:\OS9C\DEFS
set CLIB=C:\OS9C\LIB
xcc hello.c -f=hello
```

The Windows build has no psximager and no make.


# Linux

The toolchain can also be built and used directly on Linux, without Docker.

## Prerequisites

Install the packages needed for building (Ubuntu/Debian names):

```bash
sudo apt install build-essential autoconf automake libtool gettext bison flex manpages-dev \
  wget git texinfo zlib1g-dev libiberty-dev pkg-config libboost-dev \
  libboost-filesystem-dev libboost-regex-dev libcdio-dev libiso9660-dev libvcdinfo-dev
```

On other distros the package names are similar — you need a C/C++ compiler, the GNU build
tools, bison/flex, texinfo, and the boost + libcdio dev libraries.

## Build

```bash
git submodule update --init --recursive
./build-linux.sh toolchaincdi-linux
```

This takes a while (GCC compilation). The output folder contains a self-contained toolchain
that you can use directly:

```bash
export PATH=$(pwd)/toolchaincdi-linux/bin:$PATH
m68k-os9-gcc -Os -o hello hello.c
```

The `bin` folder has the tools under their long names (`m68k-elfos9-gcc`, `m68k-os9-gcc`,
`m68k-os9-xcc`, ...) and, for old makefiles, under the short names of Microware's tools:
`xcc` and `cc` (`m68k-os9-xcc`), `ucc` (`m68k-os9-xcc` in Ultra C mode), `l68`, `r68` and
`libgen`. `CDEF` and `CLIB` work as described in "How to use?" above.

The Linux build includes **psximager** (for CD-i image creation) and **make** — both available
via the system packages, unlike the Windows build.

# License

MIT for Dockerfile.

The submodules keep their own licenses. The GCC and newlib changes are distributed under
the licenses of the files they modify (GCC: GPL version 3 or later). See section 10 of
[OS9-COMPAT-DESIGN.md](OS9-COMPAT-DESIGN.md) for authorship and upstreaming notes.
