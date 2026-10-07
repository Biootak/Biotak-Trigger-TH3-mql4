# P-LOOK-RAY2 splice, part 2: the two edits the MARK branch of apply.py dropped
# (it rebuilt the text from a `lines` snapshot taken before the string edits ran).
import sys

FIB = "Biotak/FibPen.mqh"


def load(p):
    txt = open(p, "rb").read().decode("utf-8").replace("\r\n", "\n")
    if "\r" in txt:
        print("!! stray CR in " + p)
        sys.exit(1)
    return txt


def save(p, txt):
    open(p, "wb").write(txt.replace("\n", "\r\n").encode("utf-8"))


BLOCK = open("tools/.patch/block.txt", "rb").read().decode("utf-8").replace("\r\n", "\n")
if not BLOCK.endswith("\n"):
    BLOCK += "\n"

txt = load(FIB)

if "FibPenRayPair" in txt:
    print("!! the block is already in place")
    sys.exit(1)

E1 = ("//--- the FIBPEN witness channel (PathTool.mqh:31 is the precedent): Full borrows",
      BLOCK + "//--- the FIBPEN witness channel (PathTool.mqh:31 is the precedent): Full borrows")

E2 = ("   bool anchorsOk = (ta > 0 && tb > 0 && p1 > 0.0 && p2 > 0.0);\n",
      "   bool anchorsOk = (ta > 0 && tb > 0 && p1 > 0.0 && p2 > 0.0);\n"
      "   //--- P-LOOK-RAY2: the pen mirrors the master's own level rays (one read per sync).\n"
      "   bool penRL = false, penRR = false;\n"
      "   FibPenRayPair(fibo, penRL, penRR);\n")

for i, (old, new) in enumerate((E1, E2)):
    c = txt.count(old)
    if c != 1:
        print("!! edit %d matched %d times" % (i, c))
        sys.exit(1)
    txt = txt.replace(old, new, 1)

save(FIB, txt)
print("ok: the P-LOOK-RAY2 block + penRL/penRR are in place")
for probe in ("void FibPenRayPair(", "int FibPenRayBits(", "bool FibPenHasPen(",
              "int FibPenNetFind(", "void FibPenNetWrite(", "bool FibPenHeal(",
              "string FibPenChildParent(", "bool penRL = false, penRR = false;"):
    print("  %-42s %d" % (probe, txt.count(probe)))
print("  %-42s %d" % ("#define FIBPEN_NET_SLOTS", txt.count("#define FIBPEN_NET_SLOTS")))
