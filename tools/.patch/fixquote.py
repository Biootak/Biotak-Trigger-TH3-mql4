#!/usr/bin/env python3
# Inside the patch's payload strings a quote must reach the generated file as `\"` — the
# python source therefore needs TWO backslashes + quote, or the payload breaks the JSON
# (and python) it is written into.
p = "tools/.patch/mut2.py"
b = open(p, "rb").read()
BS = chr(92).encode()
one = BS + b'"'
two = BS * 2 + b'"'
print("escaped-quote runs:", b.count(one))
b = b.replace(one, two)
open(p, "wb").write(b)
print("now:", b.count(two), "ok")
