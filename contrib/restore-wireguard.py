#!/usr/bin/env python
# Restore wireguard without rebooting or messing with the config shell.
# Parses the vyatta configuration commands and runs appropriate ip and wg commands
# to reconfigure the interface. Routes appear to get automatically added by wg.
#
# Copyright 2019 Allen Wild <allenwild93@gmail.com>
# SPDX-License-Identifier: MIT

from __future__ import print_function
import os
import re
from shlex import split
from subprocess import call, check_output
import sys

def run(cmd):
    print(cmd)
    return call(split(cmd))

if os.geteuid() != 0:
    print('Please run this script as root or with sudo')
    sys.exit(1)

out = check_output(split('/opt/vyatta/bin/vyatta-op-cmd-wrapper show configuration commands'), universal_newlines=True)
conflines = [line for line in out.splitlines() if 'wireguard' in line]

interfaces = []
for line in conflines:
    m = re.search(r'\bwg\d+\b', line)
    if m and not m.group(0) in interfaces:
        interfaces.append(m.group(0))

for intf in interfaces:
    run('ip link delete dev %s'%intf)
    run('ip link add dev %s type wireguard'%intf)

for line in conflines:
    m = re.search(r'set interfaces wireguard (wg\d+) mtu (\d+)', line)
    if m:
        run('ip link set dev %s mtu %s'%(m.group(1), m.group(2)))
        continue

    m = re.search(r'set interfaces wireguard (wg\d+) address (.*)', line)
    if m:
        run('ip addr add %s dev %s'%(m.group(2), m.group(1)))
        continue

    m = re.search(r'set interfaces wireguard (wg\d+) ((?:listen-port|private-key|peer|allowed-ips) .*)', line)
    if m and ('description' not in m.group(2)):
        run('wg set %s %s'%(m.group(1), m.group(2)))

for intf in interfaces:
    run('ip link set up dev %s'%intf)
