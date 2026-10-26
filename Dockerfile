# MIT License
#
# Copyright (c) 2021 Murachue
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# note: above licensing is only for this Dockerfile, not for built docker image.

# ref: ArchLinux User Repository: m68k-elf-binutils, m68k-elf-gcc-bootstrap, m68k-elf-newlib
FROM fedora:latest AS build
RUN dnf -y --setopt=install_weak_deps=False install \
  gcc gcc-c++ make autoconf automake libtool gettext bison flex man-pages wget git texinfo \
  zlib-devel ca-certificates pkgconf-pkg-config boost-devel boost-filesystem boost-regex \
  libcdio-devel vcdimager-devel && \
  dnf clean all

WORKDIR /work
RUN wget \
  http://ftp.gnu.org/gnu/mpfr/mpfr-4.1.0.tar.xz \
  http://ftp.gnu.org/gnu/mpc/mpc-1.2.1.tar.gz \
  http://ftp.gnu.org/gnu/gmp/gmp-6.2.1.tar.xz
COPY src src/
RUN \
  tar xf mpfr-4.1.0.tar.xz && mv mpfr-4.1.0 src/gcc/mpfr && \
  tar xf mpc-1.2.1.tar.gz && mv mpc-1.2.1 src/gcc/mpc && \
  tar xf gmp-6.2.1.tar.xz && mv gmp-6.2.1 src/gcc/gmp && \
  mkdir -p /work/root

WORKDIR /work/binutils-build
RUN CFLAGS="-std=gnu17" ../src/binutils-gdb/configure --target=m68k-elfos9 --prefix=/usr --disable-multilib --with-cpu=68000 \
  --disable-nls --disable-gdb --disable-gdbserver --disable-readline --enable-install-libbfd \
  --disable-libctf --disable-werror && \
  make -j$(grep -c ^processor /proc/cpuinfo) && \
  mkdir -p /work/binutils-root/usr && \
  make prefix=/work/binutils-root/usr install && \
  cp -r /work/binutils-root/usr /work/root/ && \
  cp -r /work/binutils-root/usr /

WORKDIR /work/gcc-bootstrap-build
# GMP 6.2.1's compiler probe is incompatible with GCC 15's default C23 dialect.
RUN CFLAGS="-std=gnu17" CFLAGS_FOR_TARGET="-mpcrel -ma6rel -mbsrw" ../src/gcc/configure --prefix=/usr --target=m68k-elfos9 \
  --enable-languages="c" --enable-multilib --with-cpu=68000 --with-system-zlib --with-libgloss --without-headers --disable-shared --disable-nls && \
  make all-gcc all-target-libgcc -j$(grep -c ^processor /proc/cpuinfo) && \
  mkdir -p /work/gcc-bootstrap-root && \
  make DESTDIR=/work/gcc-bootstrap-root install-gcc install-target-libgcc && \
  strip /work/gcc-bootstrap-root/usr/bin/* && \
  cp -r /work/gcc-bootstrap-root/usr /work/root/ && \
  cp -r /work/gcc-bootstrap-root/usr /

WORKDIR /work/newlib-build
RUN CFLAGS_FOR_TARGET="-Os -g -mpcrel -ma6rel -ffunction-sections -fdata-sections -fomit-frame-pointer -ffast-math" ../src/newlib-cygwin/configure \
  --target=m68k-elfos9 --prefix=/usr --disable-newlib-supplied-syscalls --enable-multilib --with-cpu=68000 --disable-nls && \
  make -j$(grep -c ^processor /proc/cpuinfo) && \
  mkdir -p /work/newlib-root && \
  DESTDIR=/work/newlib-root/ make install && \
  cp -r /work/newlib-root/usr / && \
  cp -r /work/newlib-root/usr /work/root/

WORKDIR /work/src/psximager
RUN ./bootstrap && ./configure --prefix=/usr --with-boost-libdir=/usr/lib64 && make && make DESTDIR=/work/root install

WORKDIR /work/src/m68k-os9-tools
RUN H=$(../binutils-gdb/config.guess) && BFD=/work/binutils-root/usr/$H/m68k-elfos9 && \
  make -j$(nproc) CC=gcc BFDPATH="$BFD" CFLAGS="-g -I$BFD/include -Wall -Wextra" \
  LIBIBERTY_CFLAGS="-I/work/src/binutils-gdb/include" LDFLAGS="-L/work/binutils-build/libiberty" \
  LIBS="$BFD/lib/libbfd.a /work/binutils-build/libiberty/libiberty.a /work/binutils-build/zlib/libz.a -ldl" && \
  make DESTDIR=/work/root/usr LN=cp CC=gcc BFDPATH="$BFD" CFLAGS="-g -I$BFD/include -Wall -Wextra" \
  LIBIBERTY_CFLAGS="-I/work/src/binutils-gdb/include" LDFLAGS="-L/work/binutils-build/libiberty" \
  LIBS="$BFD/lib/libbfd.a /work/binutils-build/libiberty/libiberty.a /work/binutils-build/zlib/libz.a -ldl" install

FROM fedora:latest
RUN dnf -y --setopt=install_weak_deps=False install boost-filesystem boost-regex libcdio vcdimager-libs && \
  dnf clean all
COPY --from=build /work/root/usr /usr/
