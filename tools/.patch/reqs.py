#!/usr/bin/env python3
# What does the gate suite require of Biotak/Toolbar_B.mqh? Print every gate block that
# names it, with the assertions it makes (the reconstruction's spec).
import re

src = open("tools/check-regressions.js", encoding="utf-8").read().replace("\r\n", "\n")
# split into blocks on the register-style comments  // ── P-XXXX (date) ──
lines = src.split("\n")
blocks = []
cur = None
for i, ln in enumerate(lines):
    m = re.match(r"\s*//\s*[─-]{2,}\s*(P-[A-Z0-9-]+|DIAG-\d+|UI-\d+|TH3-[A-Z0-9-]+)\b", ln)
    if m:
        if cur:
            blocks.append(cur)
        cur = [m.group(1), i + 1, []]
    if cur is not None:
        cur[2].append(ln)
if cur:
    blocks.append(cur)

for name, at, body in blocks:
    text = "\n".join(body)
    if "Toolbar_B" not in text:
        continue
    print("=" * 78)
    print("GATE", name, "at line", at)
    for ln in body:
        if "/" in ln and (".test(" in ln or "match(" in ln or "indexOf(" in ln or "broken.push" in ln):
            print("   ", ln.strip()[:190])
