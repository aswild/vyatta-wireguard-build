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

PACKAGE_REL_V1="2"
PACKAGE_REL_V2="2"

# Directory configuration
THISDIR="$(readlink -f "$(dirname "$0")")"
SRCDIR="$THISDIR/src"
SYSROOT="$THISDIR/sysroot"
KERNEL_DIR="$SRCDIR/kernel"
TOOLCHAIN_TAR="$SRCDIR/OCTEON-SDK-5.1-tools.tar.xz"
TOOLCHAIN_DIR="$THISDIR/OCTEON-SDK-5.1-tools"

V2="1"
ER_BOARD="e300"
ER_KERNEL_RELEASE="unset"
VYATTA_DIR="unset"
PACKAGE_REL="unset"

# Toolchain and path configuration
TARGET=mips64-octeon-linux-gnu
MUSL_CC="$SYSROOT/bin/musl-gcc"

export PATH="$TOOLCHAIN_DIR/bin:$PATH"
export CROSS_COMPILE="${TARGET}-"
export CC="${CROSS_COMPILE}gcc"
export CFLAGS="-O2 -mabi=64"
export ARCH="mips"
export PKG_CONFIG_PATH="$SYSROOT/lib/pkgconfig"

# Downloads configuration
# Git LFS has limited bandwidth on Github; S3 is more complicated but way cheaper
DOWNLOAD_PREFIX='https://vyatta-wireguard-build.s3.amazonaws.com'
declare -A DOWNLOADS
DOWNLOADS[toolchain_file]="$(basename "$TOOLCHAIN_TAR")"
DOWNLOADS[toolchain_sha256]='294315a47caf34a0fea2979ab61e3a198e020b9a95e9be361d0c45d2a17f07c4'
DOWNLOADS[kernel_e300_v2_file]='kernel_e300_v2_5251067-g460c89c15333.tar.xz'
DOWNLOADS[kernel_e300_v2_sha256]='a6620e75abcdbd513bd23f236fc294b1e97a390a31371b8ddb2870c187f2db5b'
DOWNLOADS[kernel_e300_v1_file]='kernel_e300_v1_5224950-g0da2c70.tar.xz'
DOWNLOADS[kernel_e300_v1_sha256]='d781357f1a0c9e56ddaccb6d652f16f4ae7bdeb433bb4d531ce166ddcc90d454'

# Enable parallel make
if [[ -z "$MAKEFLAGS" ]] && type nproc &>/dev/null; then
    export MAKEFLAGS="-j$(nproc)"
fi

# set terminal colors
if [[ -t 1 ]]; then
    RED=$'\033[1;31m'
    CYAN=$'\033[1;36m'
    BLUE=$'\033[1;34m'
    NC=$'\033[0m'
else
    RED=
    CYAN=
    BLUE=
    NC=
fi

cd "$THISDIR"

# utility functions
msg() {
    echo "${CYAN}>>> ${*} <<<${NC}"
}

err() {
    echo "${RED}ERROR: *** ${*} ***${NC}"
}

run() {
    echo "${BLUE}+ ${*}${NC}"
    "$@"
}

# set up variables that are dependent on FW v1/v2 or the board type
init_vars() {
    if (( $V2 )); then
        KERNEL_NAME=kernel_${ER_BOARD}_v2
        ER_KERNEL_RELEASE="4.9.79-UBNT"
        VYATTA_DIR="$SRCDIR/vyatta-wireguard-2.0"
        PACKAGE_REL="$PACKAGE_REL_V2"
    else
        KERNEL_NAME=kernel_${ER_BOARD}_v1
        ER_KERNEL_RELEASE="3.10.107-UBNT"
        VYATTA_DIR="$SRCDIR/vyatta-wireguard-1.10"
        PACKAGE_REL="$PACKAGE_REL_V1"
    fi
    KERNEL_TAR="$SRCDIR/${DOWNLOADS[${KERNEL_NAME}_file]}"
}

# download a file to $SRCDIR
# $1 should be a key where ${key}_url and ${key}_sha256 are set in the global DOWNLOADS map
download_file() {
    local filename="${DOWNLOADS[${1}_file]}"
    if [[ -z "$filename" ]]; then
        err "ERROR: Invalid file name '$1' passed to download_file"
        return 1
    fi
    if (( $FORCE_DOWNLOAD )); then
        rm -f "$SRCDIR/$filename"
    fi

    if [[ -s "$SRCDIR/$filename" ]]; then
        msg "$filename already downloaded"
    else
        msg "Download $filename"
        # careful, 'set -e' is active, so we can't just run wget and check $?
        wget "$DOWNLOAD_PREFIX/$filename" -O "$SRCDIR/$filename" || \
            ( err "Failed to download '$filename'"; rm -f "$SRCDIR/$filename"; return 1)
    fi

    msg "Verify checksum of $filename"
    local sha="$(sha256sum "$SRCDIR/$filename" | cut -d' ' -f1)"
    if [[ "$sha" != "${DOWNLOADS[${1}_sha256]}" ]]; then
        err "Incorrect checksum for $filename. Expected '${DOWNLOADS[${1}_sha256]}' but got '$sha'"
        return 1
    fi
}

# Build step functions, organized in the order a full build would run
prepare_submodules() {
    msg "Initialize submodules"
    run git submodule update --init
}

build_submodules() {
    :
}

prepare_toolchain() {
    if [[ ! -f "$TOOLCHAIN_DIR/bin/$CC" ]]; then
        download_file toolchain
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
    download_file $KERNEL_NAME
    msg "Extract kernel source"
    run rm -rf "$KERNEL_DIR"
    run tar xf "$KERNEL_TAR" -C "$SRCDIR"
}

build_kernel() {
    msg "Configure kernel source"
    pushd "$KERNEL_DIR"
    if (( $V2 )); then
        # v1 kernels just use .config in the kernel tar, no make *_defconfig needed
        run make ubnt_er_${ER_BOARD}_defconfig
    fi
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

prepare_wireguard() {
    pushd "$SRCDIR/wireguard-linux-compat"
    msg "Clean WireGuard kernel module"
    run git reset --hard
    run git clean -dxfq
    msg "Patch WireGuard with __vmalloc fix"
    # https://gist.github.com/Lochnair/805bf9ab96742d0fe1c25e4130268307
    run git apply "$SRCDIR/only-use-__vmalloc-for-now.patch"
    if (( ! $V2 )); then
        msg "Patch WireGuard compat.h prandom_u32_max"
        run sed -i 's/prandom_u32_max/\0_exclude_for_e300v1/' src/compat/compat.h
    fi
    popd
}

build_wireguard() {
    # "make module" in the WireGuard directory will update its version.h
    # and add "-dirty" since we patched the source. Avoid this by building
    # the module directly with the kernel Makefiles.
    msg "Build WireGuard kernel module"
    run make -C "$KERNEL_DIR" M="$SRCDIR/wireguard-linux-compat/src" modules

    msg "Install WireGuard kernel module"
    run install -m644 "$SRCDIR/wireguard-linux-compat/src/wireguard.ko" "$THISDIR"
}

prepare_tools() {
    pushd "$SRCDIR/wireguard-tools"
    msg "Clean WireGuard tools"
    run git reset --hard
    run git clean -dxfq
    popd
}

build_tools() {
    msg "Build WireGuard tools"
    run make -C "$SRCDIR/wireguard-tools/src" CC="$MUSL_CC"

    msg "Install WireGuard tools"
    run install -m755 "$SRCDIR/wireguard-tools/src/wg" "$THISDIR"
    run ${CROSS_COMPILE}strip "$THISDIR/wg"
}

prepare_package() {
    pushd "$VYATTA_DIR"
    msg "Clean deb package"
    run git reset --hard
    run git clean -dxfq
    popd
}

build_package() {
    local wireguard_ver="$(git -C "$SRCDIR/wireguard-linux-compat" describe --dirty= | sed 's/^v//')"
    if [[ -z "$wireguard_ver" ]]; then
        msg "ERROR: Unable to get WireGuard version"
        return 1
    fi

    pushd "$VYATTA_DIR"
    msg "Build deb package"
    run install -m644 "$THISDIR/wireguard.ko" "$ER_BOARD/lib/modules/$ER_KERNEL_RELEASE/kernel/net/"
    run install -m755 "$THISDIR/wg" "$VYATTA_DIR/$ER_BOARD/usr/bin/"
    run sed -i "s/^Version:.*/Version: ${wireguard_ver}-${PACKAGE_REL}/" "$VYATTA_DIR/debian/control"
    run make -j1 deb-${ER_BOARD}
    run install -m644 package/*.deb "$THISDIR"
    popd
    msg "Built package $(ls -t *.deb | head -n1)"
}

clean_all() {
    run rm -rf "$KERNEL_DIR" sysroot wg wireguard.ko *.deb
    run git submodule foreach 'git reset --hard; git clean -dxfq'
}

clean_extra() {
    run rm -rf "$TOOLCHAIN_DIR" "$TOOLCHAIN_TAR" "$KERNEL_TAR"
}

# check for v1/v2 and board type variable
while (( $# )); do
    case "$1" in
        v1|V1) V2=0 ;;
        v2|V2) V2=1 ;;
        *) break ;;
    esac
    shift
done

# set up globals based on v1/v2
init_vars

if (( $# == 0 )); then
    set -- submodules toolchain kernel musl wireguard tools package
fi
for x in "$@"; do
    case $x in
        build_*|prepare_*)
            eval $x
            ;;
        clean)
            clean_all
            ;;
        distclean)
            clean_all
            clean_extra
            ;;
        *)
            eval prepare_$x
            eval build_$x
            ;;
    esac
done
