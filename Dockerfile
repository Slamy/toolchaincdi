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
FROM fedora:latest
RUN dnf -y --setopt=install_weak_deps=False install \
  gcc gcc-c++ make autoconf automake libtool gettext bison flex man-pages wget git texinfo file \
  zlib-devel ca-certificates pkgconf-pkg-config boost-devel boost-filesystem boost-regex \
  elfutils-debuginfod-client-devel libcdio-devel vcdimager-devel && \
  dnf clean all

# docker build -t toolchaincdi .
# docker run --rm -it   --user "$(id -u):$(id -g)"   --volume "$PWD:/home:Z"   --workdir /home   --env HOME=/home   toolchaincdi bash

# docker run --rm -it \
#  --user "$(id -u):$(id -g)" \
#  --volume "$PWD:/home:Z" \
#  --workdir /home \
#  --env HOME=/home \
#  toolchain-fedora \
#  ./build-linux64.sh toolchain-fedora