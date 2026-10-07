#!/usr/bin/env python3
# The two payload anchors that carry a quote must hold `\"` (an escape inside the JSON
# string). Built with chr(34) so the shell never sees a quote.
Q = chr(34).encode()
BS = chr(92).encode()
pairs = [
    (b'== ' + Q + Q + b' || ObjectFind', b'== ' + BS + Q + BS + Q + b' || ObjectFind'),
    (b', ' + Q + b'0' + Q + b');', b', ' + BS + Q + b'0' + BS + Q + b');'),
]
b = open("tools/mutation_gate.py", "rb").read()
for old, new in pairs:
    print(old, "->", b.count(old))
    b = b.replace(old, new)
open("tools/mutation_gate.py", "wb").write(b)
print("written")
