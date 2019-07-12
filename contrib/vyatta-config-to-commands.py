#!/usr/bin/env python

""" Quick and dirty python script to turn Vyatta config file syntax
into a series of "set" commands that can be pasted into the configure
terminal on the console.

Send the config file to stdin, commands will be printed to stdout.
Exit code is zero if all lines are parsed, nonzero otherwise.

This is useful for restoring wireguard config from an old config.boot
after losing it during an upgrade.
"""

from __future__ import print_function
import sys, re

levels = []
err = False
for line in sys.stdin:
    m = re.match(r'\s*(.*) {$', line)
    if m:
        levels.append(m.group(1))
        continue

    m = re.match(r'\s*}$', line)
    if m:
        levels.pop()
        continue

    m = re.match(r'\s*(\S*) (\S*)$', line)
    if m:
        print('set', ' '.join(levels), m.group(1), m.group(2))
    else:
        print('Error: unparsed line: "%s"'%line, file=sys.stderr)
        err = True

if levels:
    print('warning: not all config levels were closed', file=sys.stderr)

if err:
    sys.exit('failed to parse some lines')
