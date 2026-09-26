#!/usr/bin/env python3
"""
Bundle firmware codec packs into the suite, named by build ID.

Each wingflight-firmware release publishes, per target, a codec pack
(<fork>_<version>_<target>_codecs.lua) next to its hex and manifest. The suite
answers legacy MSP config opcodes from addressed parameter access with the
pack whose build ID the flight controller reports (tasks/msp/virtual.lua,
docs/msp-addressed-access.md), and loads it from src/wfsuite/codecs/<build id>.lua. This
copies packs there under that name, read from the pack itself.

    python bin/codecs/import-packs.py <pack.lua | directory> ...

For a local firmware build, point it at the firmware's obj/ directory after
`make manifest`.
"""

import os
import re
import shutil
import sys

DEST = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'src', 'wfsuite', 'codecs')


def packs(args):
    for arg in args:
        if os.path.isdir(arg):
            for name in sorted(os.listdir(arg)):
                if name.endswith('_codecs.lua'):
                    yield os.path.join(arg, name)
        else:
            yield arg


def main(argv):
    if len(argv) < 2:
        sys.stderr.write(__doc__)
        return 2
    os.makedirs(DEST, exist_ok=True)
    count = 0
    for path in packs(argv[1:]):
        with open(path, encoding='utf-8') as f:
            head = f.read(4096)
        m = re.search(r'^\s*build = "([0-9a-f]{16})",', head, re.M)
        if not m:
            sys.stderr.write('%s: no build id -- not a codec pack?\n' % path)
            return 1
        if m.group(1) == '0' * 16:
            sys.stderr.write('%s: build id is zero (a build without a manifest); skipped\n' % path)
            continue
        target = os.path.join(DEST, m.group(1) + '.lua')
        shutil.copyfile(path, target)
        print('%s -> codecs/%s.lua' % (os.path.basename(path), m.group(1)))
        count += 1
    print('%d pack(s) bundled' % count)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
