# About
This repository contains my scripts to build [WireGuard](https://wireguard.com) for Ubiquiti EdgeMAX
routers.  Specifically, this builds Lochnair's https://github.com/Lochnair/vyatta-wireguard packages
from source, based on the "[Build from
scratch](https://github.com/Lochnair/vyatta-wireguard#build-from-scratch)" instructions of that
repo's Readme.

Currently only the v2.0 firmware series for the e300 platform (ER-4, ER-6P, and ER-12) is supported,
but other Cavium-based models and EdgeMAX versions could be added without too much trouble.

This repository is provided **AS IS** with **NO WARRANTY** whatsoever. Always back up your
configuration before installing unofficial 3rd-party packages, especially kernel modules! I am not
responsible for data loss, bricked routers, getting fired because you couldn't VPN into work, etc.

# Build Instructions
## Dependencies
This is mostly self-contained thanks to Git submodules and LFS, but there are some standard
development packages that must be installed:

  * A GNU/Linux x86 (32 or 64 bit) build environment. Cygwin probably won't work. Other build
    architectures or OSes may work, but you're on your own finding a compatible Octeon toolchain.
  * [Git LFS](https://git-lfs.github.com/)
  * A new enough version of git to support lfs and submodules
  * GNU make and Autotools, including `make autoconf automake libtool pkg-config` (`pkg-config` may
    be provided by a `pkgconf` package on some Linux distros)
  * About 4 gigabytes of free disk space (the statically-linked Octeon toolchain is big)

## Easy mode
Build the .deb package with `./build.sh`

To install on an EdgeRouter, scp it to the router and install with `sudo dpkg -i /path/to/package.deb`

## Advanced Use
To clean everything, run `./build.sh clean`

`build.sh` is organized into a series of steps, which are all executed in order by default. The
current steps are `submodules toolchain kernel musl libmnl wireguard package`, plus `clean` which is
special.

Each step (besdies `clean`) is split into `prepare_<step>` and `build_<step>` functions.
`prepare_<step>` extracts (for `submodules`, `toolchain` and `kernel`) and cleans the source.
`build_<step>` actually compiles and installs to the sysroot.

The `package` step copies the newly-compiled `wireguard.ko` and `wg` binaries into the
[vyatta-wireguard](https://github.com/Lochnair/vyatta-wireguard) repo, updates the version, and
creates the deb package.

# Included Packages
  * [WireGuard](https://wireguard.com) version 0.0.20190601
  * [vyatta-wireguard](https://github.com/Lochnair/vyatta-wireguard) v2.0 branch
  * UBNT e300 (ER-4/6P/12) kernel source from EdgeRouter firmware v2.0.1
  * [musl-libc](https://www.musl-libc.org/) version 1.1.22
  * [libmnl](https://netfilter.org/projects/libmnl/index.html) version 1.0.4
  * [Cavium Octeon SDK toolchain](https://github.com/Cavium-Open-Source-Distributions/OCTEON-SDK)
    version 5.1 (based on GCC 4.7.0)

# License
The only original content in this repository is the `build.sh` script, written by me and released
under the MIT license.

All other packages and sources downloaded/compiled by `build.sh` are copyrighted by their respective
owners.

  * [vyatta-wireguard](https://github.com/Lochnair/vyatta-wireguard) is released under the GPL v3
  * The Linux kernel (source released by Ubiquiti hosted in this repository) is released under the
    GPL v2. The kernel tarball was extracted from the ER-4 GPL archive at
    https://www.ui.com/download/edgemax/edgerouter-4 and included as an LFS tarball in this
    repository to save space (just the kernel rather than the full system GPL release, and without
    a slow layer of bzip2 compression)
  * The [Cavium Octeon SDK toolchain](https://github.com/Cavium-Open-Source-Distributions/OCTEON-SDK)
    is included in this repository as an LFS tarball to save space and avoid a slow layer of bzip2.
    The Cavium repo doesn't explicitly list a license, but the GNU Binutils/GCC tools should be some
    flavor of GPL.
  * [WireGuard](https://wireguard.com) is released under the GPL v2.0
  * [musl-libc](https://www.musl-libc.org/) is released under the MIT License
  * [libmnl](https://netfilter.org/projects/libmnl/index.html) is released under the LGPL v2.1+
