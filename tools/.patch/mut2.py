#!/usr/bin/env python3
# P-DRAW-INK / P-ORPHAN-ALL mutations + the P-DRAW-75 restatement. Every new law needs a
# mutation that MUST be killed by the gate that states it (tools/mutation_gate.py).
import sys

P = "tools/mutation_gate.py"
raw = open(P, "rb").read().decode("utf-8")
txt = raw.replace("\r\n", "\n")

REPL = []

# --- P-DRAW-75: the guard now guards the VALUE (the kind memory, else the last ink).
old75 = '''        "find": "    if((DrawKindCaps(k) & DRAW_CAP_COLOR) != 0 && (int)s_dkColor[k] >= 0)\\r\\n",
        "replace": "    if((DrawKindCaps(k) & DRAW_CAP_COLOR) != 0)\\r\\n",
        "expect": "P-DRAW-75",
'''
new75 = '''        "find": "    if((DrawKindCaps(k) & DRAW_CAP_COLOR) != 0 && (int)want >= 0)\\r\\n",
        "replace": "    if((DrawKindCaps(k) & DRAW_CAP_COLOR) != 0)\\r\\n",
        "expect": "P-DRAW-75",
'''
REPL.append((old75, new75))

anchor = '''        "expect": "P-DRAW-09c",
    },

]

#--- the register's own entries, so "no mutation yet" is a NUMBER and not a feeling.
'''

new_entries = '''        "expect": "P-DRAW-09c",
    },
    #--- P-DRAW-INK-a — THE FILE CAN TELL A COLOUR FROM NO COLOUR. `clrNONE` is -1 and
    #--- `-1 & 0xFFFFFF` is WHITE, so without the presence bit the memory of a kind that
    #--- was never coloured comes back as a colour nobody chose — measured on the hand's
    #--- own disk (`5;255;550091358208;771751935`, colour field 0xFFFFFF).
    {
        "id": "P-DRAW-INK-a",
        "gate": "regression",
        "rule": "the pack records WHETHER a colour is present (bit 33)",
        "what": "the presence bit is gone: an empty colour is stored, and read back, as white",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "   v += ((long)(((int)s_dkColor[k] >= 0) ? 1 : 0) << 33);\\r\\n",
        "replace": "   // MUTATION: the presence bit is gone\\r\\n",
        "expect": "P-DRAW-INK",
    },
    #--- P-DRAW-INK-b — AND THE OTHER HALF BELIEVES IT. A pack that says "no colour"
    #--- read by an unpack that reads the mask anyway is white again.
    {
        "id": "P-DRAW-INK-b",
        "gate": "regression",
        "rule": "the unpack answers clrNONE when the row carries no colour",
        "what": "the unpack reads the masked field as a colour (a kind that never had one comes back white)",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "   s_dkColor[k] = (((((a >> 33) & 0x1) != 0)) ? (color)(int)(a & 0xFFFFFF) : clrNONE);\\r\\n",
        "replace": "   s_dkColor[k] = (color)(int)(a & 0xFFFFFF);   // MUTATION: the presence bit is ignored\\r\\n",
        "expect": "P-DRAW-INK",
    },
    #--- P-DRAW-INK-c — THE FALLBACK. A kind with no colour of its own takes the last ink
    #--- the hand picked anywhere («آخرین تغییرات آبی بود»); without it the fresh drawing
    #--- keeps the terminal's factory white while the hand is drawing in blue.
    {
        "id": "P-DRAW-INK-c",
        "gate": "regression",
        "rule": "the create path falls back to the last ink the hand chose",
        "what": "a kind without a colour of its own is left factory-white again",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "    if((int)want < 0) want = s_dkAnyClr;\\r\\n",
        "replace": "    // MUTATION: no fallback (the white default comes back)\\r\\n",
        "expect": "P-DRAW-INK",
    },
    #--- P-DRAW-INK-d — THE INK IS NOTED WHERE EVERY PICK ARRIVES. One line in the ONE
    #--- colour writer; without it the fallback answers with a stale colour forever.
    {
        "id": "P-DRAW-INK-d",
        "gate": "regression",
        "rule": "the one colour writer notes the last ink",
        "what": "the last ink is never noted (the fallback can only answer with a colour from before)",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "         if((int)c >= 0) s_dkAnyClr = c;\\r\\n",
        "replace": "         // MUTATION: the last ink is never noted\\r\\n",
        "expect": "P-DRAW-INK",
    },
    #--- P-DRAW-INK-e — AND IT SURVIVES THE ATTACH. The row is what makes the fallback
    #--- true on the first drawing of the next session.
    {
        "id": "P-DRAW-INK-e",
        "gate": "regression",
        "rule": "the shared ink is written to the presets' own file",
        "what": "the shared ink is never written (the next attach starts on the terminal default)",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "   if((int)s_dkAnyClr >= 0)\\r\\n      FileWrite(h, 1, DRAW_LASTINK_SLOT, IntegerToString((int)s_dkAnyClr), \\"0\\");\\r\\n",
        "replace": "   // MUTATION: the shared ink is never written\\r\\n",
        "expect": "P-DRAW-INK",
    },
    #--- P-ORPHAN-ALL-a — THE PEN ANSWERS FOR ITS OWN PARENT. Measured on the hand's own
    #--- chart file: two deleted fibos left all 36 of their `_FSD` rows behind.
    {
        "id": "P-ORPHAN-ALL-a",
        "gate": "regression",
        "rule": "the pen's rows are dropped when their master is gone (through the one deleter)",
        "what": "the pen's orphan rule deletes silently again (no witness, no one deleter)",
        "file": "Biotak/DrawStrip_Pick.mqh",
        "find": "         string par = FibPenChildParent(nm);\\r\\n         if(par == \\"\\" || ObjectFind(0, par) < 0) DrawOrphanDrop(nm, par);   // P-ORPHAN-ALL\\r\\n",
        "replace": "         string par = FibPenChildParent(nm);\\r\\n         if(par == \\"\\" || ObjectFind(0, par) < 0) ObjectDelete(0, nm);\\r\\n",
        "expect": "P-ORPHAN-ALL",
    },
    #--- P-ORPHAN-ALL-b — EVERY FAMILY, NOT JUST THE ONE THAT WAS REPORTED. A suffix with
    #--- a builder and a parent parser but no orphan rule is the shape that leaked.
    {
        "id": "P-ORPHAN-ALL-b",
        "gate": "regression",
        "rule": "every companion family has its orphan rule on the pass (the box's 50 % line included)",
        "what": "the 50 % line's orphan rule is deleted from the pass",
        "file": "Biotak/DrawStrip_Pick.mqh",
        "find": "      if(BoxIsMidChild(nm))\\r\\n      {\\r\\n         string par = BoxMidParent(nm);\\r\\n         if(par == \\"\\" || ObjectFind(0, par) < 0) DrawOrphanDrop(nm, par);   // P-ORPHAN-ALL\\r\\n         continue;\\r\\n      }\\r\\n",
        "replace": "      // MUTATION: the 50 % line's orphan rule is gone\\r\\n",
        "expect": "P-ORPHAN-ALL",
    },

]

#--- the register's own entries, so "no mutation yet" is a NUMBER and not a feeling.
'''

REPL.append((anchor, new_entries))

out = txt
for old, new in REPL:
    n = out.count(old)
    if n != 1:
        print("!! anchor matched %d times: %r" % (n, old[:100]))
        import difflib
        j = out.find(old[:40])
        if j >= 0:
            near = out[j:j + len(old) + 120]
            for line in difflib.unified_diff(old.split("\n"), near.split("\n"), "anchor", "file", lineterm=""):
                print(line)
        sys.exit(1)
    out = out.replace(old, new)

open(P, "wb").write(out.replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8"))
print("patched", P)
