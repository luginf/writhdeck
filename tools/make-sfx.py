#!/usr/bin/env python3
"""
Create a self-contained SFX executable: shell stub + jimsh binary + Tcl script.
Usage: python3 tools/make-sfx.py <jimsh> <script.tcl> <output>
"""
import os, sys

if len(sys.argv) != 4:
    print(f"Usage: {sys.argv[0]} <jimsh> <script.tcl> <output>", file=sys.stderr)
    sys.exit(1)

jimsh_path, script_path, output_path = sys.argv[1], sys.argv[2], sys.argv[3]

jimsh_data  = open(jimsh_path,  'rb').read()
script_data = open(script_path, 'rb').read()
jsize = len(jimsh_data)

# Template — {skip} = stub size, {jsize} = jimsh size, {soff} = script offset
TMPL = ('#!/bin/sh\n'
        'T=$(mktemp -d);trap "rm -rf $T" EXIT INT TERM\n'
        'dd if="$0" bs=1 skip={skip} count={jsize} of="$T/j" 2>/dev/null\n'
        'dd if="$0" bs=1 skip={soff} of="$T/s.tcl" 2>/dev/null\n'
        'chmod +x "$T/j";exec "$T/j" "$T/s.tcl" "$@"\n')

# Iterate until stub size converges (usually 1-2 rounds)
skip = 0
for _ in range(5):
    stub = TMPL.format(skip=skip, jsize=jsize, soff=skip + jsize)
    actual = len(stub.encode('ascii'))
    if actual == skip:
        break
    skip = actual
else:
    sys.exit("stub size did not converge")

stub_bytes = stub.encode('ascii')
assert len(stub_bytes) == skip

with open(output_path, 'wb') as f:
    f.write(stub_bytes)
    f.write(jimsh_data)
    f.write(script_data)

os.chmod(output_path, 0o755)
print(f"Built {output_path}  stub={skip}B  jim={jsize}B  script={len(script_data)}B")
