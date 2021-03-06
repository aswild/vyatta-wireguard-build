# Upstream Vyatta WireGuard Development Moved
There's now official build tools for WireGuard on Ubnt Vyatta routers at https://github.com/WireGuard/wireguard-vyatta-ubnt.
Please look there for the latest WireGuard packages for your EdgeRouter.

Lochnair's original vyatta-wireguard repo has been archived, and the WireGuard team is consolodating
work on the [new official repo](https://github.com/WireGuard/wireguard-vyatta-ubnt).

I will likely be deprecating/archiving the build scripts in this repo some time soon, in favor of the
official packaging.

# About
This repository contains my scripts to build [WireGuard](https://wireguard.com) for Ubiquiti EdgeMAX
routers.  Specifically, this builds Lochnair's https://github.com/Lochnair/vyatta-wireguard packages
from source, based on the "[Build from
scratch](https://github.com/Lochnair/vyatta-wireguard#build-from-scratch)" instructions of that
repo's Readme.

Currently only the e300 platform (ER-4, ER-6P, and ER-12) is supported, but
other Cavium-based models could be added without too much trouble.

This repository is provided **AS IS** with **NO WARRANTY** whatsoever. Always back up your
configuration before installing unofficial 3rd-party packages, especially kernel modules! I am not
responsible for data loss, bricked routers, getting fired because you couldn't VPN into work, etc.

# Build Instructions
## Dependencies
This is mostly self-contained thanks to Git submodules, but there are some standard
development packages that must be installed:

  * A GNU/Linux x86 (32 or 64 bit) build environment. Cygwin probably won't work. Other build
    architectures or OSes may work, but you're on your own finding a compatible Octeon toolchain.
  * A new enough version of git to support submodules
  * GNU Make
  * At least 3 gigabytes of free disk space (the statically-linked Octeon toolchain is big)

## Easy mode
Build the .deb package with `./build.sh`

To install on an EdgeRouter, scp it to the router and install with `sudo dpkg -i /path/to/package.deb`

## Advanced Use
To clean everything, run `./build.sh clean`. To clean everything, including the downloaded kernel
source and toolchains, run `./build.sh distclean`.

`build.sh` is organized into a series of steps, which are all executed in order by default. The
current steps are `submodules toolchain kernel musl wireguard tools package`, plus `clean`
as a special case.

Each step (besides `clean`) is split into `prepare_<step>` and `build_<step>` functions.
`prepare_<step>` extracts (for `submodules`, `toolchain` and `kernel`) and cleans the source.
`build_<step>` actually compiles and installs to the sysroot.

The `package` step copies the newly-compiled `wireguard.ko` and `wg` binaries into the
[vyatta-wireguard](https://github.com/Lochnair/vyatta-wireguard) repo, updates the version, and
creates the deb package.

# Included Packages
As submodules:
  * [WireGuard](https://wireguard.com) (latest snapshot)
  * [vyatta-wireguard](https://github.com/Lochnair/vyatta-wireguard) (master and v2.0 branches)
  * [musl-libc](https://www.musl-libc.org/) (latest release tag)

Downloaded tarballs:
  * UBNT e300 (ER-4/6P/12) kernel source from EdgeRouter firmware extracted from UBNT's GPL release
  * Cavium Octeon SDK toolchain version 5.1 (based on GCC 4.7.0). The original GitHub repo where
    I got this is gone now, as all the Cavium code moved to
    [Marvell's](https://github.com/MarvellEmbeddedProcessors/Octeon-Toolchain) GitHub page.
    Unfortunately it seems that the new repo only contains source tarballs, but this build script
    downloads from my S3 bucket.

# License
The only original content in this repository is the `build.sh` script, written by me and released
under the MIT license.

All other packages and sources downloaded/compiled by `build.sh` are copyrighted by their respective
owners.

  * [vyatta-wireguard](https://github.com/Lochnair/vyatta-wireguard) is released under the GPL v3
  * The Linux kernel (source released by Ubiquiti hosted in this repository) is released under the
    GPL v2. The kernel tarball was extracted from the ER-4 GPL archive at
    https://www.ui.com/download/edgemax/edgerouter-4 and re-hosted on S3 to save space and slow bzip2
    decompression.
  * The Cavium Octeon SDK toolchain is downloaded from S3, re-hosted to save space and avoid slow
    bzip2 decompression.  The Cavium repo doesn't exist anymore, and didn't explicitly list
    a license, but the GNU Binutils/GCC tools should be some flavor of GPL.
  * [WireGuard](https://wireguard.com) is released under the GPL v2.0
  * [musl-libc](https://www.musl-libc.org/) is released under the MIT License
