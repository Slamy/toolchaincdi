#!/bin/bash
# build-win64.sh NAME: the toolchain for Windows (x86_64-w64-mingw32), built on Linux into the
# folder NAME (e.g. toolchaincdi-v1.0.0-win64) in the current directory.
#
# Run from anywhere, with the submodules checked out; the build directory is ./build-win64 (or
# $WORK). Needs a mingw-w64 cross compiler and the packages listed in
# .github/workflows/windows-build.yml. $J sets make's job count (default: the number of CPUs).
#
# The steps: the Linux toolchain for m68k-elfos9 (binutils, GCC, newlib, configured as in the
# Dockerfile), which builds the target libraries and the Windows GCC; GMP, MPFR and MPC for
# Windows; binutils (with libbfd) and GCC for Windows as a Canadian cross; the m68k-os9-tools
# with their Makefile. The Windows programs are stripped; the m68k libraries are left as built.
set -euo pipefail

NAME=${1:?usage: build-win64.sh NAME}
SRC=$(cd "$(dirname "$0")" && pwd)/src
OUT=$PWD/$NAME
WORK=${WORK:-$PWD/build-win64}
J=${J:-$(nproc)}
H=x86_64-w64-mingw32
T=m68k-elfos9
L=$WORK/linux
D=$WORK/deps-$H
P=$WORK/install
GMP=gmp-6.2.1 MPFR=mpfr-4.1.0 MPC=mpc-1.2.1

mkdir -p "$WORK"
cd "$WORK"
step() { echo "=== $(date +%H:%M:%S) $*"; }

step "sources of GMP, MPFR and MPC (the Dockerfile's versions)"
for f in mpfr/$MPFR.tar.xz mpc/$MPC.tar.gz gmp/$GMP.tar.xz; do
  [ -f "${f#*/}" ] || wget -q "https://ftp.gnu.org/gnu/$f"
done
for f in $GMP.tar.xz $MPFR.tar.xz $MPC.tar.gz; do
  [ -d "${f%.tar.*}" ] || tar xf "$f"
done

# deps HOST PREFIX: GMP, MPFR and MPC, static, for HOST
deps() {
  local host=$1 prefix=$2 b
  for b in $GMP $MPFR $MPC; do
    rm -rf "build-$b-$host" && mkdir "build-$b-$host" && cd "build-$b-$host"
    "../$b/configure" --host="$host" --prefix="$prefix" --disable-shared --enable-static \
      --with-gmp="$prefix" --with-mpfr="$prefix" > configure.log
    make -j"$J" > make.log
    make install > install.log
    cd ..
  done
}

step "GMP, MPFR and MPC for Linux"
deps "$(gcc -dumpmachine)" "$WORK/deps-linux"
step "GMP, MPFR and MPC for Windows"
deps $H "$D"

export PATH="$L/bin:$PATH"

step "binutils for Linux"
rm -rf binutils-linux && mkdir binutils-linux && cd binutils-linux
"$SRC/binutils-gdb/configure" --target=$T --prefix="$L" --disable-multilib --with-cpu=68000 \
  --disable-nls --disable-gdb --enable-install-libbfd --disable-libctf > configure.log
make -j"$J" MAKEINFO=true > make.log
make install MAKEINFO=true > install.log
cd ..

step "GCC for Linux"
rm -rf gcc-linux && mkdir gcc-linux && cd gcc-linux
CFLAGS_FOR_TARGET="-mpcrel -ma6rel -mbsrw" "$SRC/gcc/configure" --prefix="$L" --target=$T \
  --enable-languages=c --enable-multilib --with-cpu=68000 --with-system-zlib --with-libgloss \
  --without-headers --disable-shared --disable-nls \
  --with-gmp="$WORK/deps-linux" --with-mpfr="$WORK/deps-linux" --with-mpc="$WORK/deps-linux" \
  > configure.log
make -j"$J" all-gcc all-target-libgcc MAKEINFO=true > make.log
make install-gcc install-target-libgcc MAKEINFO=true > install.log
cd ..

step "newlib"
rm -rf newlib && mkdir newlib && cd newlib
CFLAGS_FOR_TARGET="-Os -g -mpcrel -ma6rel -ffunction-sections -fdata-sections -fomit-frame-pointer -ffast-math" \
  "$SRC/newlib-cygwin/configure" --target=$T --prefix="$L" --disable-newlib-supplied-syscalls \
  --enable-multilib --with-cpu=68000 --disable-nls > configure.log
make -j"$J" MAKEINFO=true > make.log
make install MAKEINFO=true > install.log
cd ..

rm -rf "$P"
step "binutils for Windows"
rm -rf binutils-$H && mkdir binutils-$H && cd binutils-$H
"$SRC/binutils-gdb/configure" --host=$H --target=$T --prefix="$P" --disable-multilib \
  --with-cpu=68000 --disable-nls --disable-gdb --disable-gdbserver --disable-sim \
  --disable-readline --disable-libdecnumber --enable-install-libbfd --disable-libctf \
  --disable-werror > configure.log
make -j"$J" MAKEINFO=true > make.log
make install MAKEINFO=true > install.log
cd ..

step "GCC for Windows"
rm -rf gcc-$H && mkdir gcc-$H && cd gcc-$H
"$SRC/gcc/configure" --host=$H --target=$T --prefix="$P" --enable-languages=c \
  --enable-multilib --with-cpu=68000 --with-libgloss --without-headers --disable-shared \
  --disable-nls --with-gmp="$D" --with-mpfr="$D" --with-mpc="$D" --disable-win32-registry \
  > configure.log
make -j"$J" all-gcc MAKEINFO=true > make.log
make install-gcc MAKEINFO=true > install.log
cd ..

step "the target libraries (libgcc, newlib) from the Linux build"
mkdir -p "$P/lib/gcc/$T" "$P/$T/lib" "$P/$T/include"
cp -r "$L/lib/gcc/$T/." "$P/lib/gcc/$T/"
cp -r "$L/$T/lib/." "$P/$T/lib/"
cp -r "$L/$T/include/." "$P/$T/include/"

step "the m68k-os9-tools for Windows"
rm -rf tools && cp -r "$SRC/m68k-os9-tools" tools
find tools -maxdepth 1 \( -name '*.[ch]' -o -name Makefile \) -exec sed -i 's/\r$//' {} +
BFD=$P/$H/$T
MK=(CC="$H-gcc -std=gnu17" EXEEXT=.exe BFDPATH="$BFD"
    CFLAGS="-O2 -I$BFD/include -Wall -Wextra -D_GNU_SOURCE"
    LIBIBERTY_CFLAGS="-I$SRC/binutils-gdb/include" LDFLAGS="-L$WORK/binutils-$H/libiberty"
    LIBS="$BFD/lib/libbfd.a $WORK/binutils-$H/libiberty/libiberty.a $WORK/binutils-$H/zlib/libz.a")
make -C tools -j"$J" all "${MK[@]}" > tools.log 2>&1
make -C tools install "${MK[@]}" DESTDIR="$P" LN=cp \
  INSTALL_PROGRAM="install --strip-program=$H-strip -s" >> tools.log 2>&1
grep 'warning:' tools.log || true

# The short names (m68k-os9-xcc.md, "Finding the tools"): xcc and cc are m68k-os9-xcc, ucc
# m68k-os9-xcc in Ultra C mode, l68, r68 and libgen the front ends of the same names.
cd "$P/bin"
cp m68k-os9-xcc.exe xcc.exe
cp m68k-os9-xcc.exe cc.exe
cp m68k-os9-ucc.exe ucc.exe
for t in l68 r68 libgen; do cp m68k-os9-$t.exe $t.exe; done
cd "$WORK"

step "stripping the Windows programs"
find "$P" -name '*.exe' -exec $H-strip --strip-unneeded {} +

rm -rf "$OUT"
cp -r "$P" "$OUT"
step "done: $OUT ($(du -sh "$OUT" | cut -f1))"
