#!/usr/bin/env python3
# The P-DRAW-75 find string carries the `if(...)` closing paren; the patch source lost it.
# The patch source stores each escape as TWO backslashes (`\\r\\n`), so the anchors for
# this byte-level fix carry two as well.
p = "tools/.patch/mut2.py"
b = open(p, "rb").read()
BS = chr(92).encode()
BS2 = BS * 2
bad = b"(int)s_dkColor[k] >= 0" + BS2 + b"r" + BS2 + b'n"'
good = b"(int)s_dkColor[k] >= 0)" + BS2 + b"r" + BS2 + b'n"'
print("bad:", b.count(bad))
b = b.replace(bad, good)
print("after:", b.count(good))
open(p, "wb").write(b)
print("ok")
