#!/usr/bin/env python3
# The working-tree Toolbar_B was reverted by a stray `git checkout --`; look for any blob
# in the object store (a staged copy, a dangling write) that still carries the lost work.
import subprocess

ids = subprocess.run(["git", "cat-file", "--batch-all-objects", "--batch-check"],
                     capture_output=True).stdout.decode().splitlines()
blobs = [ln.split()[0] for ln in ids if ln.split()[1:2] == ["blob"]]
print("blobs:", len(blobs))

needles = [b"DrawStylePackA", b"DRAW_LASTLOOK_SLOT", b"s_dkAnyClr", b"P-DRAW-INK"]
found = {}
p = subprocess.Popen(["git", "cat-file", "--batch"], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
out = p.communicate(b"".join(i.encode() + b"\n" for i in blobs))[0]
for n in needles:
    i = out.find(n)
    print(n.decode(), "at", i)
    if i >= 0:
        found[n] = i
if b"DrawStylePackA" in out:
    i = out.find(b"DrawStylePackA")
    seg = out[max(0, i - 4000):i + 200]
    open("tools/.patch/blob_hit.bin", "wb").write(out)
    print("wrote tools/.patch/blob_hit.bin", len(out))
