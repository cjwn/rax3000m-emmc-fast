#!/usr/bin/env python3
"""Patch only the RAX3000M MMC overlay, allowing safe repeated execution."""
import argparse
import pathlib
import re

p = argparse.ArgumentParser()
p.add_argument('source', type=pathlib.Path)
p.add_argument('--frequency', choices=['26', '52'], default='26')
p.add_argument('--mode', choices=['highspeed', 'legacy'], default='highspeed')
a = p.parse_args()
if a.mode == 'legacy' and a.frequency != '26':
    p.error('legacy is only supported with 26 MHz')
f = a.source / 'target/linux/mediatek/dts/mt7981b-cmcc-rax3000m-emmc.dtso'
s = f.read_text()
if s.count('target = <&mmc0>;') != 1 or s.count('max-frequency =') != 1:
    raise SystemExit('Unexpected device tree; refusing to patch')
s, n = re.subn(r'max-frequency = <\d+>;', f'max-frequency = <{a.frequency}000000>;', s)
if n != 1:
    raise SystemExit('Unexpected frequency property')
s = re.sub(r'^\s*cap-mmc-highspeed;\s*\n', '', s, flags=re.M)
if a.mode == 'highspeed':
    s, n = re.subn(r'^(\s*)bus-width = <8>;', r'\1bus-width = <8>;\n\1cap-mmc-highspeed;', s, flags=re.M)
    if n != 1:
        raise SystemExit('Unexpected bus width; refusing to patch')
f.write_text(s)
print(f'{f}: {a.frequency} MHz, {a.mode}')
