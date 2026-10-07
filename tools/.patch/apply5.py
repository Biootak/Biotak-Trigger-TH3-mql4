#!/usr/bin/env python3
# P-LOOK-RAY3 (2026-10-04) - THE PEN'S SPAN IS MT4'S SPAN, AND MT4 WILL NOT TELL US.
# Byte-exact splice into a CRLF MQL4 file; every anchor must match exactly once.
import io, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
P = os.path.join(ROOT, "Biotak", "FibPen.mqh")
d = open(P, "rb").read()

START = b"//--- P-LOOK-RAY2 (2026-10-04) - THE PEN COVERS THE LINE"
END = b"int FibPenRayBits(const string fibo)"

NEW = """//--- P-LOOK-RAY3 (2026-10-04) \u2014 THE PEN'S SPAN IS MT4'S SPAN, AND MT4 WILL NOT TELL US.
//---
//--- P-LOOK-RAY2 believed the master's OWN ray pair (`OBJPROP_RAY_LEFT/RIGHT`) was the
//--- fibo's level ray, and mirrored it onto every row of the pen. MEASURED FALSE on the
//--- hand's own chart, 2026-10-04 12:08 (EURUSD M1, AMarkets demo): the four level lines
//--- run edge to edge \u2014 x=250..1863, one 1 px dash-dot-dot row each \u2014 while the two rows the
//--- pen stacks beside them stop dead at x=595, the second anchor, which is the report
//--- («\u0686\u0631\u0627 \u0627\u0645\u062a\u062f\u0627\u062f \u062e\u0637 \u0647\u0627 \u0627\u0633\u062a\u0627\u06cc\u0644 \u0627\u0639\u0645\u0627\u0644 \u0646\u0634\u062f\u0647 \u0628\u0627\u06cc\u062f \u0647\u0645\u0647 \u062c\u0627 \u0628\u0627\u0634\u0647 \u062f\u06cc\u06af\u0647»). Counted, not
//--- eyeballed: between the anchors each level occupies rows 292..294 (level + 2 pen rows);
//--- past x=580 only row 293 survives \u2014 the master ran on to the chart edge, the pen did
//--- not, so the extension wore no thickness at all.
//---
//--- WHY the mirror read false every single time: on OBJ_FIBO that pair is NOT the level
//--- ray. MT4 keeps the level ray in a field of its own \u2014 the chart's own file stores
//--- `levels_ray=0` for a fibo and writes NO `ray=` entry for it at all, while the pen's
//--- rows (type=2, OBJ_TREND) carry `ray=1` \u2014 and MQL4 exposes nothing that reads or writes
//--- it: `ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false)` does NOT stop a fibo's levels
//--- from reaching the right chart edge (mql5.com/forum/164640, MT4 build 1030+: "it always
//--- stretch the fibo retracement to right end of the chart"). A read that can only ever
//--- answer false is not a mirror, it is a trimmer: the pen was shortened to the anchors
//--- while the line it belongs to went on.
//---
//--- So the truth is not a flag we own but a SHAPE MT4 draws: a fibo's level lines run from
//--- the FIRST anchor to the RIGHT edge of the chart, and never to the left (measured on
//--- the same frame: they begin at x=250 while the chart's own left edge is x=48). The pen
//--- states that shape instead of guessing it \u2014 right on, left off, on every dash row, the
//--- neon core and the wash halo, at birth and on every heal. One shape, one law: the
//--- style is the line's style WHEREVER THE LINE GOES, which is the whole of the report.
void FibPenRayPair(const string fibo, bool &rl, bool &rr)
{
   if(fibo == "" || ObjectFind(0, fibo) < 0) { rl = false; rr = false; return; }
   rl = false;   // P-LOOK-RAY3: a fibo's levels never run left of their first anchor
   rr = true;    // ...and always run on to the right chart edge, whatever any flag says
}
""".replace("\n", "\r\n").encode("utf-8")

i = d.find(START)
j = d.find(END)
if i < 0 or j < 0 or j < i:
    print("ANCHOR MISS")
    sys.exit(1)
d = d[:i] + NEW + d[j:]

OLD_DIAG = b'                        " look=" + IntegerToString(lk));'
NEW_DIAG = (b'                        " look=" + IntegerToString(lk) +\r\n'
            b'                        " rays=" + IntegerToString(FibPenRayBits(fibo)));')
if d.count(OLD_DIAG) != 1:
    print("DIAG ANCHOR MISS", d.count(OLD_DIAG))
    sys.exit(1)
d = d.replace(OLD_DIAG, NEW_DIAG)

open(P, "wb").write(d)
print("ok FibPen.mqh: P-LOOK-RAY3 applied")