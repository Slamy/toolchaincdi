#!/bin/bash
# build-linux.sh NAME: the toolchain for Linux (x86_64-linux), built into the folder NAME
# (e.g. toolchaincdi-v1.0.0-linux) in the current directory.
#
# Run from anywhere, with the submodules checked out; the build directory is ./build-linux (or
# $WORK). Needs the packages listed in the Dockerfile's build stage. $J sets make's job count
# (default: the number of CPUs).
#
# The steps: binutils, GCC (bootstrap), newlib, GCC (final), m68k-os9-tools, all compiled for
# the host platform and targeting m68k-elfos9. The result is a native Linux toolchain you can
# drop into your PATH.
#
# Existing build trees are reused.  To reconfigure a step and every later step, use, for example:
#   FORCE="newlib" ./build-linux.sh NAME
# To start completely fresh: rm -rf build-linux

set -euo pipefail

NAME=${1:?usage: build-linux.sh NAME}
SRC=$(cd "$(dirname "$0")" && pwd)/src
OUT=$PWD/$NAME
WORK=${WORK:-$PWD/build-linux}
J=${J:-$(nproc)}
T=m68k-elfos9
P=$WORK/install
H=$("$SRC/binutils-gdb/config.guess")
FORCE=${FORCE:-}

mkdir -p "$WORK"
cd "$WORK"
step() { echo "=== $(date +%H:%M:%S) $*"; }

# needs_configure DIR CHECK_FILE [CHECK_FILE ...]
# A rebuilt earlier stage invalidates later stages, whose configure results and installed files
# may depend on it.  Otherwise, make itself handles source-level incremental rebuilds.
REBUILD_CHAIN=0
needs_configure() {
  local dir=$1
  shift
  local forced

  for forced in $FORCE; do
    if [ "$forced" = "$dir" ]; then
      REBUILD_CHAIN=1
      return 0
    fi
  done
  if [ "$REBUILD_CHAIN" -eq 1 ] || [ ! -d "$dir" ]; then
    REBUILD_CHAIN=1
    return 0
  fi
  for check in "$@"; do
    if [ ! -e "$check" ]; then
      REBUILD_CHAIN=1
      return 0
    fi
  done
  return 1
}

step "binutils"
if needs_configure binutils "$P/bin/$T-as"; then
  rm -rf binutils && mkdir binutils && cd binutils
  "$SRC/binutils-gdb/configure" --target=$T --prefix="$P" --disable-multilib --with-cpu=68000 \
    --disable-nls --disable-gdb --disable-gdbserver --disable-readline --enable-install-libbfd --disable-libctf --disable-werror \
    > configure.log
else
  echo "Reusing existing binutils configuration"
  cd binutils
fi
make -j"$J" MAKEINFO=true > make.log 2>&1
make install MAKEINFO=true > install.log 2>&1
cd ..

step "GCC (bootstrap: compiler + libgcc only)"
if needs_configure gcc-bootstrap "$P/bin/$T-gcc"; then
  rm -rf gcc-bootstrap && mkdir gcc-bootstrap && cd gcc-bootstrap
  CFLAGS_FOR_TARGET="-mpcrel -ma6rel -mbsrw" "$SRC/gcc/configure" --prefix="$P" --target=$T \
    --enable-languages=c --enable-multilib --with-cpu=68000 --with-system-zlib --with-libgloss \
    --without-headers --disable-shared --disable-nls \
    > configure.log
else
  echo "Reusing existing GCC bootstrap configuration"
  cd gcc-bootstrap
fi
make -j"$J" all-gcc all-target-libgcc MAKEINFO=true > make.log 2>&1
make install-gcc install-target-libgcc MAKEINFO=true > install.log 2>&1
cd ..

step "create m68k-elfos9-cc symlink for libgloss"
# libgloss configure looks for <target>-cc, but GCC only installs <target>-gcc at this stage.
# Create the symlink so libgloss can find the compiler.
ln -sf m68k-elfos9-gcc "$P/bin/m68k-elfos9-cc"
export PATH="$P/bin:$PATH"

step "newlib (multilib: GCC and OS-9 calling conventions)"
if needs_configure newlib "$P/$T/include/newlib.h"; then
  rm -rf newlib && mkdir newlib && cd newlib
  CFLAGS_FOR_TARGET="-Os -g -mpcrel -ma6rel -ffunction-sections -fdata-sections -fomit-frame-pointer -ffast-math" \
    "$SRC/newlib-cygwin/configure" --target=$T --prefix="$P" --disable-newlib-supplied-syscalls \
    --enable-multilib --with-cpu=68000 --disable-nls > configure.log
else
  echo "Reusing existing newlib configuration"
  cd newlib
fi
make -j"$J" MAKEINFO=true > make.log 2>&1
make install MAKEINFO=true > install.log 2>&1
cd ..

step "GCC (final: with newlib)"
if needs_configure gcc-final "$P/bin/$T-gcc" "$P/$T/lib/libc.a"; then
  rm -rf gcc-final && mkdir gcc-final && cd gcc-final
  CFLAGS_FOR_TARGET="-mpcrel -ma6rel -mbsrw" "$SRC/gcc/configure" --prefix="$P" --target=$T \
    --enable-languages=c --enable-multilib --with-cpu=68000 --with-system-zlib --with-libgloss \
    --without-headers --disable-shared --disable-nls \
    > configure.log
else
  echo "Reusing existing final GCC configuration"
  cd gcc-final
fi
make -j"$J" MAKEINFO=true > make.log 2>&1
make install MAKEINFO=true > install.log 2>&1
cd ..

step "m68k-os9-tools"
if needs_configure tools "$P/bin/m68k-os9-gcc" "$P/bin/m68k-os9-xcc" \
  "$P/bin/m68k-os9-ucc" "$P/bin/m68k-os9-l68" "$P/bin/m68k-os9-r68" "$P/bin/m68k-os9-libgen"; then
  rm -rf tools && cp -r "$SRC/m68k-os9-tools" tools
else
  echo "Reusing existing m68k-os9-tools build"
fi
# Use the BFD and libiberty built above, rather than the host's /usr installation.
BFD=$P/$H/$T
TOOLS_MK=(CC=gcc BFDPATH="$BFD" CFLAGS="-g -I$BFD/include -Wall -Wextra"
  LIBIBERTY_CFLAGS="-I$SRC/binutils-gdb/include" LDFLAGS="-L$WORK/binutils/libiberty"
  LIBS="$BFD/lib/libbfd.a $WORK/binutils/libiberty/libiberty.a $WORK/binutils/zlib/libz.a -ldl")
make -C tools -j"$J" all "${TOOLS_MK[@]}" > tools.log 2>&1
make -C tools install "${TOOLS_MK[@]}" DESTDIR="$P" LN=cp >> tools.log 2>&1
grep 'warning:' tools.log || true

step "short name aliases (Microware compatibility)"
cd "$P/bin"
cp m68k-os9-xcc xcc
cp m68k-os9-ucc ucc
for t in l68 r68 libgen; do cp m68k-os9-$t $t; done
cd "$WORK"

# Strip the Linux host-toolchain binaries (not the m68k target libs)
find "$P" -type f -executable -exec file {} + | grep -i 'elf.*64-bit' | cut -d: -f1 | xargs strip --strip-unneeded 2>/dev/null || true

rm -rf "$OUT"
cp -r "$P" "$OUT"

# Verify the toolchain works
echo ""
echo "=== Verifying toolchain ==="
"$OUT/bin/m68k-elfos9-gcc" --version | head -1
"$OUT/bin/m68k-os9-gcc" --version | head -1
echo ""

rm -rf "$OUT"
cp -r "$P" "$OUT"
step "done: $OUT ($(du -sh "$OUT" | cut -f1))"
echo ""
echo "To use: export PATH=\"\$(pwd)/$NAME/bin:\$PATH\""
