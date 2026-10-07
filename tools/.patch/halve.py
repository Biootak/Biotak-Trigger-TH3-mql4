#!/usr/bin/env python3
# Halve the backslash runs inside the patch source so the anchors it builds carry ONE
# backslash per escape (the mutation file stores `\r\n` as text).
p = "tools/.patch/mut2.py"
b = open(p, "rb").read()
BS = chr(92).encode()
four = BS * 4 + b"r"
two = BS * 2 + b"r"
print("four-runs:", b.count(four))
b = b.replace(four, two)
print("four-runs after:", b.count(four), "two-runs:", b.count(two))
open(p, "wb").write(b)
print("ok")
