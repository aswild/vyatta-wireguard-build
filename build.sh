#!/bin/bash
#
# Script to build WireGuard for Ubiquiti EdgeMAX Cavium Octeon based routers
# Based on https://github.com/Lochnair/vyatta-wireguard
#
# Copyright 2019 Allen Wild <allenwild93@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

set -eo pipefail

THISDIR="$(readlink -f "$(dirname "$0")")"
SRCDIR="$THISDIR/src"
SYSROOT="$THISDIR/sysroot"

ER_BOARD="e300"
ER_KERNEL_TAR="$(ls "$SRCDIR"/${ER_BOARD}_kernel_*.tgz)"
ER_KERNEL_RELEASE="4.9.79-UBNT"
KERNEL_DIR="$SRCDIR/kernel"

TOOLCHAIN_TAR="$SRCDIR/OCTEON-SDK-5.1-tools.tar.xz"
TOOLCHAIN_DIR="$THISDIR/OCTEON-SDK-5.1-tools"

# Toolchain and directory configurations
TARGET=mips64-octeon-linux-gnu
MUSL_CC="$SYSROOT/bin/musl-gcc"

export PATH="$TOOLCHAIN_DIR/bin:$PATH"
export CROSS_COMPILE="${TARGET}-"
export CC="${CROSS_COMPILE}gcc"
export CFLAGS="-O2 -mabi=64"
export ARCH="mips"
export PKG_CONFIG_PATH="$SYSROOT/lib/pkgconfig"

if [[ -z "$MAKEFLAGS" ]] && type nproc &>/dev/null; then
    export MAKEFLAGS="-j$(nproc)"
fi

# set terminal colors
if [[ -t 1 ]]; then
    CYAN=$'\033[1;36m'
    BLUE=$'\033[1;34m'
    NC=$'\033[0m'
else
    CYAN=
    BLUE=
    NC=
fi

cd "$THISDIR"

# utility functions
msg() {
    echo "${CYAN}>>> ${*} <<<${NC}"
}

run() {
    echo "${BLUE}+ ${*}${NC}"
    "$@"
}

# Build step functions, organized in the order a full build would run
prepare_submodules() {
    msg "Initialize submodules and LFS objects"
    run git submodule update --init
    run git lfs pull || true
}

build_submodules() {
    :
}

prepare_toolchain() {
    if [[ ! -f "$TOOLCHAIN_DIR/bin/$CC" ]]; then
        msg "Extract toolchain"
        run rm -rf "$TOOLCHAIN_DIR"
        run tar xf "$TOOLCHAIN_TAR"
    else
        msg "Toolchain already extracted"
    fi
}

build_toolchain() {
    :
}

prepare_kernel() {
    msg "Extracting kernel source"
    run rm -rf "$KERNEL_DIR"
    run tar xf "$ER_KERNEL_TAR" -C "$SRCDIR"
}

build_kernel() {
    msg "Configure kernel source"
    pushd "$KERNEL_DIR"
    run make ubnt_er_${ER_BOARD}_defconfig
    run make modules_prepare
    msg "Install kernel headers"
    run make INSTALL_HDR_PATH="$SYSROOT" headers_install
    popd
}

prepare_musl() {
    pushd "$SRCDIR/musl"
    msg "Clean musl"
    run git reset --hard
    run git clean -dxfq
    popd
}

build_musl() {
    pushd "$SRCDIR/musl"
    msg "Configure musl"
    ./configure --host=x86_64 --target=$TARGET --prefix=$SYSROOT --enable-static --disable-shared
    msg "Build musl"
    run make
    msg "Install musl"
    run make install
    popd
}

prepare_libmnl() {
    pushd "$SRCDIR/libmnl"
    msg "Clean libmnl"
    run git reset --hard
    run git clean -dxfq
    popd
}

build_libmnl() {
    pushd "$SRCDIR/libmnl"
    msg "Configure libmnl"
    run ./autogen.sh
    run ./configure CC=$MUSL_CC --prefix=$SYSROOT --host=$TARGET --enable-static --disable-shared
    msg "Build libmnl"
    run make
    msg "Install libmnl"
    run make install
    popd
}

prepare_wireguard() {
    pushd "$SRCDIR/WireGuard"
    msg "Clean WireGuard"
    run git reset --hard
    run git clean -dxfq
    msg "Patch WireGuard with __vmalloc fix"
    # https://gist.github.com/Lochnair/805bf9ab96742d0fe1c25e4130268307
    run git apply "$SRCDIR/only-use-__vmalloc-for-now.patch"
    popd
}

build_wireguard() {
    # "make module" in the WireGuard directory will update its version.h
    # and add "-dirty" since we patched the source. Avoid this by building
    # the module directly with the kernel Makefiles.
    msg "Build WireGuard kernel module"
    run make -C "$KERNEL_DIR" M="$SRCDIR/WireGuard/src" modules

    msg "Build WireGuard tools"
    run make -C "$SRCDIR/WireGuard/src/tools" CC="$MUSL_CC"

    msg "Install WireGuard"
    run install -m644 "$SRCDIR/WireGuard/src/wireguard.ko" "$THISDIR"
    run install -m755 "$SRCDIR/WireGuard/src/tools/wg" "$THISDIR"
    run ${CROSS_COMPILE}strip "$THISDIR/wg"
}

prepare_package() {
    pushd "$SRCDIR/vyatta-wireguard"
    msg "Clean deb package"
    run git reset --hard
    run git clean -dxfq
    popd
}

build_package() {
    local wireguard_ver="$(git -C "$SRCDIR/WireGuard" describe --dirty=)"
    if [[ -z "$wireguard_ver" ]]; then
        msg "ERROR: Unable to get WireGuard version"
        return 1
    fi

    pushd "$SRCDIR/vyatta-wireguard"
    msg "Build deb package"
    run install -m644 "$THISDIR/wireguard.ko" "$ER_BOARD/lib/modules/$ER_KERNEL_RELEASE/kernel/net/"
    run install -m755 "$THISDIR/wg" "$SRCDIR/vyatta-wireguard/$ER_BOARD/usr/bin/"
    run sed -i "s/^Version:.*/Version: ${wireguard_ver}-1/" "$SRCDIR/vyatta-wireguard/debian/control"
    run make -j1 deb-${ER_BOARD}
    run install -m644 package/*.deb "$THISDIR"
    popd
    msg "Built package $(ls *.deb)"
}

clean_all() {
    run rm -rf "$TOOLCHAIN_DIR" "$KERNEL_DIR" sysroot wg wireguard.ko *.deb
    run git submodule foreach 'git reset --hard; git clean -dxfq'
}

if (( $# == 0 )); then
    set -- submodules toolchain kernel musl libmnl wireguard package
fi
for x in "$@"; do
    case $x in
        build_*|prepare_*)
            eval $x
            ;;
        clean)
            clean_all
            ;;
        *)
            eval prepare_$x
            eval build_$x
            ;;
    esac
done
