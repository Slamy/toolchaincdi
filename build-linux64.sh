#!/bin/bash
# build-linux64.sh NAME: the toolchain for Linux (x86_64-linux-gnu), built into the folder NAME
# (e.g. toolchaincdi-v1.0.0-linux64) in the current directory.
#
# Run from anywhere, with the submodules checked out; the build directory is ./build-linux64 (or
# $WORK). Needs the packages listed in .github/workflows/linux-build.yml. $J sets make's job count
# (default: the number of CPUs).
#
# The steps: GMP, MPFR and MPC (static, so the programs don't need them); binutils, GCC (compiler
# and libgcc), newlib, GCC again (with newlib), configured as in the Dockerfile; the
# m68k-os9-tools with their Makefile, linked with that binutils' libbfd.
# The Linux programs are stripped; the m68k libraries are left as built. NAME/README.linux lists
# the glibc version and the shared libraries the programs need, read from the programs.
#
# Existing build trees are reused. To configure a step and every later step again, use, for
# example:
#   FORCE="newlib" ./build-linux64.sh NAME
# To start afresh: rm -rf build-linux64
set -euo pipefail

NAME=${1:?usage: build-linux64.sh NAME}
SRC=$(cd "$(dirname "$0")" && pwd)/src
OUT=$PWD/$NAME
WORK=${WORK:-$PWD/build-linux64}
J=${J:-$(nproc)}
T=m68k-elfos9
P=$WORK/install
H=$("$SRC/binutils-gdb/config.guess")
FORCE=${FORCE:-}

mkdir -p "$WORK"
cd "$WORK"
step() { echo "=== $(date +%H:%M:%S) $*"; }

# needs_configure DIR CHECK_FILE...: whether DIR must be configured (again): FORCE names it, an
# earlier step was configured again (its results and installed files may change), DIR or one of
# the files is missing. Otherwise make rebuilds what changed in the sources.
REBUILD_CHAIN=0
needs_configure() {
	local dir=$1 forced check
	shift
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

step "GMP, MPFR and MPC (the Dockerfile's versions, static)"
GMP=gmp-6.2.1 MPFR=mpfr-4.1.0 MPC=mpc-1.2.1
D=$WORK/deps
if needs_configure deps "$D/lib/libgmp.a" "$D/lib/libmpfr.a" "$D/lib/libmpc.a"; then
	for f in mpfr/$MPFR.tar.xz mpc/$MPC.tar.gz gmp/$GMP.tar.xz; do
		[ -f "${f#*/}" ] || wget -q "https://ftp.gnu.org/gnu/$f"
	done
	rm -rf deps && mkdir deps
	for b in $GMP $MPFR $MPC; do
		rm -rf "$b" "build-$b" && tar xf $b.tar.* && mkdir "build-$b" && cd "build-$b"
		"../$b/configure" --prefix="$D" --disable-shared --enable-static --with-gmp="$D" \
		  --with-mpfr="$D" > configure.log
		make -j"$J" > make.log
		make install > install.log
		cd ..
	done
else
	echo "reusing GMP, MPFR and MPC"
fi
WITH_DEPS=(--with-gmp="$D" --with-mpfr="$D" --with-mpc="$D")

step "binutils"
if needs_configure binutils "$P/bin/$T-as"; then
	rm -rf binutils && mkdir binutils && cd binutils
	"$SRC/binutils-gdb/configure" --target=$T --prefix="$P" --disable-multilib --with-cpu=68000 \
	  --disable-nls --disable-gdb --disable-gdbserver --disable-readline --enable-install-libbfd \
	  --disable-libctf --disable-werror > configure.log
else
	echo "reusing the binutils configuration"
	cd binutils
fi
make -j"$J" MAKEINFO=true > make.log 2>&1
make install MAKEINFO=true > install.log 2>&1
cd ..

step "GCC (compiler and libgcc)"
if needs_configure gcc-bootstrap "$P/bin/$T-gcc"; then
	rm -rf gcc-bootstrap && mkdir gcc-bootstrap && cd gcc-bootstrap
	CFLAGS_FOR_TARGET="-mpcrel -ma6rel -mbsrw" "$SRC/gcc/configure" --prefix="$P" --target=$T \
	  --enable-languages=c --enable-multilib --with-cpu=68000 --with-system-zlib --with-libgloss \
	  --without-headers --disable-shared --disable-nls "${WITH_DEPS[@]}" \
	  > configure.log
else
	echo "reusing the GCC (compiler and libgcc) configuration"
	cd gcc-bootstrap
fi
make -j"$J" all-gcc all-target-libgcc MAKEINFO=true > make.log 2>&1
make install-gcc install-target-libgcc MAKEINFO=true > install.log 2>&1
cd ..

# libgloss's configure looks for <target>-cc, which GCC doesn't install
ln -sf $T-gcc "$P/bin/$T-cc"
export PATH="$P/bin:$PATH"

step "newlib (multilib: GCC's and OS-9's calling conventions)"
if needs_configure newlib "$P/$T/include/newlib.h"; then
	rm -rf newlib && mkdir newlib && cd newlib
	CFLAGS_FOR_TARGET="-Os -g -mpcrel -ma6rel -ffunction-sections -fdata-sections -fomit-frame-pointer -ffast-math" \
	  "$SRC/newlib-cygwin/configure" --target=$T --prefix="$P" --disable-newlib-supplied-syscalls \
	  --enable-multilib --with-cpu=68000 --disable-nls > configure.log
else
	echo "reusing the newlib configuration"
	cd newlib
fi
make -j"$J" MAKEINFO=true > make.log 2>&1
make install MAKEINFO=true > install.log 2>&1
cd ..

step "GCC (with newlib)"
if needs_configure gcc-final "$P/bin/$T-gcc" "$P/$T/lib/libc.a"; then
	rm -rf gcc-final && mkdir gcc-final && cd gcc-final
	CFLAGS_FOR_TARGET="-mpcrel -ma6rel -mbsrw" "$SRC/gcc/configure" --prefix="$P" --target=$T \
	  --enable-languages=c --enable-multilib --with-cpu=68000 --with-system-zlib --with-libgloss \
	  --without-headers --disable-shared --disable-nls "${WITH_DEPS[@]}" \
	  > configure.log
else
	echo "reusing the GCC (with newlib) configuration"
	cd gcc-final
fi
make -j"$J" MAKEINFO=true > make.log 2>&1
make install MAKEINFO=true > install.log 2>&1
cd ..
rm -f "$P/bin/$T-cc"

step "m68k-os9-tools"
if needs_configure tools "$P/bin/m68k-os9-gcc" "$P/bin/m68k-os9-xcc" "$P/bin/m68k-os9-ucc" \
	"$P/bin/m68k-os9-l68" "$P/bin/m68k-os9-r68" "$P/bin/m68k-os9-libgen"; then
	rm -rf tools && cp -r "$SRC/m68k-os9-tools" tools
else
	echo "reusing the m68k-os9-tools build"
fi
# the libbfd and libiberty built above, not the host's
BFD=$P/$H/$T
MK=(CC=gcc BFDPATH="$BFD" CFLAGS="-g -I$BFD/include -Wall -Wextra"
	LIBIBERTY_CFLAGS="-I$SRC/binutils-gdb/include" LDFLAGS="-L$WORK/binutils/libiberty"
	LIBS="$BFD/lib/libbfd.a $WORK/binutils/libiberty/libiberty.a $WORK/binutils/zlib/libz.a -ldl")
make -C tools -j"$J" all "${MK[@]}" > tools.log 2>&1
make -C tools install "${MK[@]}" DESTDIR="$P" LN=cp >> tools.log 2>&1
grep 'warning:' tools.log || true

# The short names (m68k-os9-xcc.md, "Finding the tools"): xcc and cc are m68k-os9-xcc, ucc
# m68k-os9-xcc in Ultra C mode, l68, r68 and libgen the front ends of the same names.
cd "$P/bin"
cp m68k-os9-xcc xcc
cp m68k-os9-xcc cc
cp m68k-os9-ucc ucc
for t in l68 r68 libgen; do cp m68k-os9-$t $t; done
cd "$WORK"

step "stripping the Linux programs"
mapfile -t progs < <(find "$P" -type f -exec file {} + | grep 'ELF 64-bit.*x86-64' | cut -d: -f1)
strip --strip-unneeded "${progs[@]}"

step "README.linux"
# the highest GLIBC_ symbol version and the shared libraries the programs need (a static
# program has neither)
glibc=$(for f in "${progs[@]}"; do objdump -T "$f" 2> /dev/null || true; done |
	grep -o 'GLIBC_[0-9.]*' | sed 's/GLIBC_//' | sort -u -V | tail -1)
needed=$(for f in "${progs[@]}"; do objdump -p "$f" | awk '$1 == "NEEDED" {print $2}'; done |
	sort -u)
cat > "$P/README.linux" << EOF
toolchaincdi for Linux ($NAME)

The cross toolchain for OS-9/68000 (CD-i): GCC, binutils and newlib for m68k-elfos9, and the
m68k-os9-tools (m68k-os9-gcc, m68k-os9-xcc, m68k-os9-l68, ...), for x86_64 Linux.

Use: unpack anywhere and put the bin folder on PATH:

    export PATH=/path/to/$NAME/bin:\$PATH
    m68k-os9-gcc -o hello hello.c

See README.md at https://github.com/cdifan/toolchaincdi for the tools and their options.

Needs: x86_64 Linux with glibc $glibc or newer, and these shared libraries (all part of a
standard installation):

$(echo "$needed" | sed 's/^/    /')

Built on: $(. /etc/os-release && echo "$PRETTY_NAME"), $(ldd --version | head -1).
Not included: psximager and make.
EOF
cat "$P/README.linux"

rm -rf "$OUT"
cp -r "$P" "$OUT"
"$OUT/bin/$T-gcc" --version | head -1
step "done: $OUT ($(du -sh "$OUT" | cut -f1))"
