#!/usr/bin/env python3
"""
DIAG DIFF — what the paint DID versus what the TERMINAL held.

WHY THIS EXISTS. Three layers can be probed offline (constants, layout, ops) and one
cannot: the terminal. A paint defect that only MT4 can show therefore had no
machine-readable form — the 2026-10-01 reports («روی stroke که کلیک می‌کنم متن‌ها و غیره
این‌طوری ناقص هستش» and «این هنوز درست نشده») were a SCREENSHOT read by eye for an hour,
while the chart's own object list sat one command away. Now the panel writes both halves
of that answer in the same log block, on the same user action, describing the same state:

  [dsdiag] EXPECT obj=PnlDrawS_GS0T role=lbl xywh=374,140,0,0 z=1442 txt="50 % line"
  [drawstrip] TABCENSUS obj=PnlDrawS_GS0T type=23 xywh=374,140,0,0 bgcolor=0 ... z=1442
              back=0 fnt=13 tf=-1 bmp="" ink="50 % line":14865611

`DSTRIP_DIAG` (Biotak/DrawStrip_Head.mqh) arms the EXPECT half on a panel open or a group
switch; `DrawStripGearDiagDump()` (DrawStrip_GearB.mqh) prints the paint's own numbers and
then the census. This tool diffs them and names the objects that disagree, so the last
layer is machine-checked instead of eyeballed.

  python tools/diag-diff.py build-logs/experts.log     # or:  ... | python tools/diag-diff.py -
  python tools/diag-diff.py --sample                   # a self-test: it must name 4 defects
  python tools/diag-diff.py --frames <log>             # every frame the file carries
  python tools/diag-diff.py --frame 1 <log>            # one frame (negative = from the end)

Verdicts, one per EXPECT line (the paint placed it, so absence is a fact, not a guess):
  MISSING      the chart does not hold the name at all — a refused create, or a purge
               that ran after the paint
  TYPE         the chart holds the name as ANOTHER object type. The paint's writer
               finds the name (`ObjectFind >= 0`) and writes properties the type does
               not read, so the object EXISTS and paints NOTHING — the tree's own
               `DrawStripSweepStale` comment names this. The census SKIPS any type it
               does not know, so this verdict is the only way it could ever surface.
  NO INK       a label created with font size 0 (MT4 draws nothing) or an empty text
  TEXT         the chart's text is not the text the paint set (a LABEL's text or a
               BUTTON's caption — P-LOG-5: the census prints both)
  LAYER        the rung differs, or an object the panel paints reads back=1 (it is
               drawn in the background band, under the plate)
  SEAT         the object sits somewhere other than where the paint put it
  CORNER       the object is bound to another corner, so `x_distance` — and therefore
               the pixel it draws on — is not the one the paint declared (P-LOG-7)
  OCCLUDED     every property above reads correct and the screen shows nothing, because
               the panel's OWN PLATE outranks it and covers it (P-LOG-6). The plate is
               the one object that can hide the whole panel, so the verdict names it.

  (a `tf=` column is printed by the census and is NOT a verdict: this panel never
  writes OBJPROP_TIMEFRAMES, so every object of the family — the ones the screen shows
  included — reads tf=0. `OBJ_NO_PERIODS` is 0, so a reader MUST NOT translate it; the
  P-DRAW-120 note in DrawStrip_GearB says the same thing.)

  (P-LOG-8 adds an AFTER block per open: the NEXT paint pass re-walks the dump's own
  name list and prints only the delta — `AFTER GONE obj=` (a later purge),
  `AFTER MOVED obj= was=… now=…` (a later writer), `AFTER NEW obj=` (a later cover
  inside the panel rect) and `AFTER done snap=… gone=… moved=… new=…`. `gone=0 moved=0
  new=0` is the witness that the state the census described is still the state on the
  chart when the user screenshots it — the one thing a snapshot cannot say about
  itself.)

Exit 0 = every declared object is held exactly as declared; 1 = at least one divergence;
2 = the log carries no declaration (an old build, or DSTRIP_DIAG is 0).
"""

import re
import sys

EXPECT_RX = re.compile(
    r"\[dsdiag\]\s*EXPECT\s+obj=(?P<obj>\S+)\s+role=(?P<role>\S+)\s+"
    r"xywh=(?P<x>-?\d+),(?P<y>-?\d+),(?P<w>-?\d+),(?P<h>-?\d+)\s+"
    r"z=(?P<z>-?\d+)\s+txt=\"(?P<txt>[^\"]*)\"")
CENSUS_RX = re.compile(
    r"\[drawstrip\]\s*TABCENSUS\s+(?:idx=(?P<idx>-?\d+)\s+)?obj=(?P<obj>\S+)\s+type=(?P<ty>-?\d+)\s+"
    r"xywh=(?P<x>-?\d+),(?P<y>-?\d+),(?P<w>-?\d+),(?P<h>-?\d+)\s+"
    r"bgcolor=(?P<bg>-?\d+).*?\sz=(?P<z>-?\d+)\s+back=(?P<back>-?\d+)\s+"
    r"fnt=(?P<fnt>-?\d+)\s+tf=(?P<tf>-?\d+)\s+bmp=\"(?P<bmp>[^\"]*)\"\s+"
    r"ink=(?P<ink>.*?)(?:\s+win=(?P<win>-?\d+)\s+corner=(?P<corner>-?\d+)(?P<rest>.*))?\s*$")   # P-LOG-7/8

#--- role -> the object type the writer must have created (measured on the live
#--- 2026-10-01 log: lbl 23 · bmp 24 · btn 25 · rect 28).
ROLE_TYPE = {"lbl": 23, "bmp": 24, "btn": 25, "rect": 28}

#--- P-LOG-6 (2026-10-01): the panel's OWN BODY, by name. `DrawStripGearPlate` paints
#--- the narrow bake (`Gbake`), the wide composed body (`Gtop`/`Gmid*`/`Gbot`), the
#--- retired underlayer (`GBG`) and the colour board's own plate (`BB*`). Skin.mqh's
#--- P-DRAW-72 note records a real past failure of exactly this shape — "the bake sat
#--- ABOVE the tabs, the hex fields, the Interior switch and the foot", and the panel
#--- answered nothing. A plate covers everything it overlaps, so when it outranks a
#--- declared object the VERDICT is the occluder's own name, not a guess about z.
PLATE_RX = re.compile(r"PnlDrawS_(Gbake|Gtop|Gmid\d*|Gbot|GBG|BB\w*)")


def _ink_box(d):
    """The rect a label's ink occupies; every other object answers with its own box.

    A label carries w=h=0 (MT4 sizes it from the font), so the box is measured from the
    text it holds and the font size the census read back.
    """
    if d["ty"] == 23:
        fnt = d["fnt"] or 10
        return (d["x"], d["y"], max(8, int(len(d["text"]) * fnt * 0.62)), fnt + 2)
    return (d["x"], d["y"], max(d["w"], 2), max(d["h"], 2))


def _covers(outer, inner):
    ox, oy, ow, oh = outer
    ix, iy, iw, ih = inner
    return ox <= ix and oy <= iy and ox + ow >= ix + iw and oy + oh >= iy + ih

SAMPLE = """
[dsdiag] EXPECT obj=PnlDrawS_GS0T role=lbl xywh=374,140,0,0 z=1442 txt="LINE STYLE"
[dsdiag] EXPECT obj=PnlDrawS_GR2T role=lbl xywh=374,182,0,0 z=1442 txt="50 % line"
[dsdiag] EXPECT obj=PnlDrawS_GCH0 role=rect xywh=390,186,48,32 z=1470 txt=""
[dsdiag] EXPECT obj=PnlDrawS_GS0L role=rect xywh=909,231,165,1 z=1500 txt=""
[drawstrip] TABCENSUS idx=136 obj=PnlDrawS_GS0T type=23 xywh=374,140,0,0 bgcolor=0 tone=-1 z=1442 back=0 fnt=0 tf=0 bmp="" ink="LINE STYLE":14865611
[drawstrip] TABCENSUS idx=137 obj=PnlDrawS_GR2T type=23 xywh=374,182,0,0 bgcolor=0 tone=-1 z=1442 back=0 fnt=13 tf=0 bmp="" ink="":14865611
[drawstrip] TABCENSUS idx=138 obj=PnlDrawS_GS0L type=24 xywh=909,231,16,16 bgcolor=0 tone=-1 z=1442 back=0 fnt=8 tf=0 bmp="X" ink=-
"""
#: the sample must name FOUR: NO INK (fnt=0 on a labelled object), TEXT (empty ink),
#: MISSING (GCH0 — the paint placed it, the chart never held the name) and TYPE
#: (GS0L held as a 24-bitmap while the paint asked for a rect).


def parse(text):
    exp, act = [], {}
    for ln in text.splitlines():
        m = EXPECT_RX.search(ln)
        if m:
            d = m.groupdict()
            d.update({k: int(d[k]) for k in ("x", "y", "w", "h", "z")})
            exp.append(d)
            continue
        m = CENSUS_RX.search(ln)
        if m:
            d = m.groupdict()
            d.update({k: int(d[k]) for k in
                      ("ty", "x", "y", "w", "h", "z", "back", "fnt", "tf")})
            # P-LOG-7: the two columns that decide WHERE an object draws when its
            # `xywh` is not the whole answer (a corner-bound x is measured from the
            # right edge; `win` is the subwindow the name actually lives in).
            for k in ("win", "corner"):
                if d.get(k) is not None:
                    d[k] = int(d[k])
            #--- `idx` is the TERMINAL's own list order and settles an equal `z`
            #--- (P-DRAW-124), so it compares as a NUMBER, never as text.
            if d.get("idx") is not None:
                d["idx"] = int(d["idx"])
            ink = d["ink"]
            d["text"] = ink.split('":')[0].lstrip('"') if '":' in ink else ""
            act[d["obj"]] = d
    return exp, act


def split_frames(text):
    """Split a diag log into frames: one run of EXPECT lines, then one run of CENSUS lines.

    P-LOG-3 (2026-10-01): the panel appends a WHOLE frame per open and never truncates
    (one handle per attach), so a file holding three opens carries three declarations
    and three censuses. Diffing them as ONE document pairs the first open's intent with
    the last open's reality and invents divergences that never existed. MEASURED
    2026-10-01 21:58 (`biotak_diag_EURUSD.txt`, two opens): the mixed read reported
    "DIVERGED: 53 of 187" - SEAT 38, TEXT 15 - and the LAST frame ALONE reported
    "declared 91 / held 139, PASS, 0 divergences". Same bytes, one frame boundary.
    """
    frames, cur, prev = [], [], None
    for ln in text.splitlines():
        if EXPECT_RX.search(ln):
            k = "E"
        elif CENSUS_RX.search(ln):
            k = "C"
        else:
            continue
        if k == "E" and prev == "C":
            frames.append(cur)
            cur = []
        cur.append(ln)
        prev = k
    if cur:
        frames.append(cur)
    return frames


def diff(exp, act):
    out = []
    for e in exp:
        obj = e["obj"]
        a = act.get(obj)
        if a is None:
            out.append(("MISSING", e, "the paint placed it; the chart does not hold the name"))
            continue
        # the chart holds the name as another type: the writer's properties are not
        # read by that type, and the census itself would skip it — name it here.
        want = ROLE_TYPE.get(e["role"])
        if want is not None and a["ty"] != want:
            out.append(("TYPE", e, "the chart holds type=%d where role=%s needs %d"
                        % (a["ty"], e["role"], want)))
            continue
        #--- P-LOG-7 (2026-10-01): THE ONE PROPERTY THAT MOVES AN OBJECT WITHOUT
        #--- MOVING ITS `xywh`. `OBJPROP_XDISTANCE` is measured from the object's own
        #--- binding corner, so a control carrying `CORNER_RIGHT_UPPER` while the paint
        #--- reasons as if it were left-bound draws at `chart_width - x - w`: a
        #--- different pixel with every other column of this census reading CORRECT.
        #--- The paint writes CORNER_LEFT_UPPER at every create site, so any other
        #--- value is the defect itself - named, not guessed at.
        if a.get("corner") not in (None, 0):
            out.append(("CORNER", e, "corner=%d - x is measured from the right edge, "
                        "so it draws at chart_width-x-w" % a["corner"]))
            continue
        # a label with no font size draws nothing at all (MT4), whatever its text says
        if a["ty"] == 23 and a["fnt"] == 0 and e["txt"]:
            out.append(("NO INK", e, "fnt=0 - MT4 draws no text for this object"))
            continue
        if a["back"] != 0:
            out.append(("LAYER", e, "back=%d — drawn in the background band, under the plate"
                        % a["back"]))
            continue
        if a["z"] != e["z"]:
            out.append(("LAYER", e, "z=%d where the paint set %d" % (a["z"], e["z"])))
            continue
        if e["role"] == "bmp":
            # a face's "text" is its RESOURCE. The census answers with the path the
            # terminal RESOLVED (`\indicators\...ex4::Files\Icons\x.bmp`), the paint
            # with the resource it asked for (`::Files\Icons\x.bmp`) — so the compare
            # is by basename, and an EMPTY resolution is the only real defect: the
            # raster did not load, so the face draws nothing (P-DRAW-120's own column).
            want = e["txt"].replace("\\", "/").rsplit("/", 1)[-1]
            got = a["bmp"].replace("\\", "/").rsplit("/", 1)[-1]
            if want and got == "":
                out.append(("NO INK", e, "the terminal resolved no raster (%s asked)" % e["txt"]))
                continue
            if want and got != want:
                out.append(("TEXT", e, "the terminal resolved %r, the paint set %r"
                            % (a["bmp"], e["txt"])))
                continue
            # a face is CENTRED in its cell: compare centres, not boxes. P-LOG-6: the
            # census reports the OBJECT's own box now (MT4 answers XSIZE/YSIZE with the
            # raster's native size — `bk_w2.bmp` 16 where the cell is 22), and the paint
            # spends the difference centring the art inside the cell, so the tolerance
            # is half that difference. A compare that ignores it calls every face a
            # seat defect the moment the cell stops matching the raster.
            # P-LOG-6: the census answers XSIZE/YSIZE with the raster's OWN FILE size
            # (`bk_w2.bmp` 16, `gl_layers_m.bmp` 15) while the paint declares the CELL
            # (22) it insets the art into. A centre compare between those two can never
            # hold — MEASURED: it called `GR5I` off by 5.5px while the art sat inside its
            # cell the whole time. The invariant that IS true is containment: the face
            # must be INSIDE the cell the paint declared, with the design's own inset as
            # slack. A face that moved escapes the cell and still fails.
            #--- P-LOG-7: AND THE RULE IS TWO WAYS. A raster can be SMALLER than its
            #--- cell (the paint insets the art: `gl_layers_m.bmp` 15 in a 22 seat,
            #--- `bk_w2.bmp` 16) or LARGER than it (the switch's own `pnl_sw_off.bmp`
            #--- is 52x34 around a 40x22 seat - the pill is drawn inside the sprite's
            #--- own padding). MEASURED on the 22:51 frame: containment alone called all
            #--- four switches outer faces a seat defect while each sat centred on its
            #--- cell, and a centre compare alone called the inset glyphs defects.
            #--- Either invariant proves the seat: contained, or centred.
            slack = 2
            inside = not (a["x"] < e["x"] - slack or a["y"] < e["y"] - slack or
                          a["x"] + a["w"] > e["x"] + e["w"] + slack or
                          a["y"] + a["h"] > e["y"] + e["h"] + slack)
            centred = (abs((a["x"] + a["w"] // 2) - (e["x"] + e["w"] // 2)) <= slack and
                       abs((a["y"] + a["h"] // 2) - (e["y"] + e["h"] // 2)) <= slack)
            if not inside and not centred:
                out.append(("SEAT", e, "box %d,%d,%d,%d is outside its %d,%d,%d,%d cell"
                            % (a["x"], a["y"], a["w"], a["h"], e["x"], e["y"], e["w"], e["h"])))
            continue
        # P-LOG-5 (2026-10-01): the census's ink column carries EVERY caption now, so
        # a button's own text is compared exactly as a label's is. It has to be: the
        # swatch row's captions (`1px`..`5px`, `Solid`..`D-Dot`) are BUTTON text, and
        # while the column was written for OBJ_LABEL only a lost caption and a healthy
        # face both read `ink=-` — the report "some rows show no text" was undecidable
        # from the log, and the 22:10 frame passed 91/91 with that blind spot intact.
        if e["role"] in ("lbl", "btn") and e["txt"] and a["text"] != e["txt"]:
            out.append(("TEXT", e, "chart holds %r, the paint set %r"
                        % (a["text"], e["txt"])))
            continue
        # a label's ink top is MEASURED from its band (`StrapInkY`), so one pixel of
        # rounding is the measure's own, not a seat defect (the faces above allow the
        # same on their centres).
        if abs(a["x"] - e["x"]) > 1 or abs(a["y"] - e["y"]) > 1:
            out.append(("SEAT", e, "xy=%d,%d where the paint put %d,%d"
                        % (a["x"], a["y"], e["x"], e["y"])))

    #--- P-LOG-6: AND THE PANEL'S OWN BODY CAN HIDE ITS OWN CONTROLS. Every property
    #--- above can read CORRECT while the screen shows nothing, because none of them
    #--- says who is on top: a plate that outranks a control covers it completely. The
    #--- plate is a bitmap label at `gx-14, gy-14` — its own 14px margin, OUTSIDE the
    #--- panel rect — and until P-LOG-6 the census's box test dropped it (a bitmap's
    #--- box came from the resource table, which reads 0 for a name it does not carry),
    #--- so this verdict could not exist. Two objects on one rung are settled by the
    #--- terminal's list order, which is the `idx` the census prints (P-DRAW-124).
    plates = [d for d in act.values() if PLATE_RX.match(d["obj"])]
    for e in exp:
        a = act.get(e["obj"])
        if a is None:
            continue
        target = _ink_box(a)
        for p in plates:
            if not _covers((p["x"], p["y"], p["w"], p["h"]), target):
                continue
            pr, ar = (p["z"], p["idx"] if p["idx"] is not None else -1), \
                     (a["z"], a["idx"] if a["idx"] is not None else -1)
            if pr <= ar:
                continue
            out.append(("OCCLUDED", e,
                        "the panel's own plate %s (z=%s idx=%s) covers it entirely"
                        % (p["obj"], p["z"], p["idx"])))
            break
    return out


def main():
    argv = sys.argv[1:]
    #--- `--frame N` carries a value that is NOT a path; a bare scan for non-dash
    #--- arguments would hand `N` to the file reader and report "cannot read 1".
    values = set(argv[i + 1] for i, a in enumerate(argv)
                 if a == "--frame" and i + 1 < len(argv))
    args = [a for a in argv if not a.startswith("-") and a not in values]
    if "--sample" in sys.argv:
        text = SAMPLE
    elif args and args[0] != "-":
        try:
            with open(args[0], encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        except OSError as e:
            print("cannot read %s: %s" % (args[0], e))
            return 2
    else:
        text = sys.stdin.read()

    #--- P-LOG-3: a diag file carries one WHOLE frame per panel open, so the unit a
    #--- reader may diff is a FRAME - never the file. Default to the last one: it is
    #--- the state the screen is showing, and it is the only one whose census belongs
    #--- to the same paint as its declaration.
    frames = split_frames(text)
    if "--frames" in sys.argv:
        print("DIAG FRAMES - one run of EXPECT lines plus its own census, per panel open")
        for i, f in enumerate(frames, 1):
            ne = sum(1 for l in f if EXPECT_RX.search(l))
            nc = sum(1 for l in f if CENSUS_RX.search(l))
            print("  frame %d: %d declaration(s), %d census line(s)" % (i, ne, nc))
        return 0
    if not frames:
        exp, act = parse(text)
    else:
        want = None
        for i, a in enumerate(sys.argv):
            if a == "--frame" and i + 1 < len(sys.argv):
                want = int(sys.argv[i + 1])
        #--- the LAST frame is the state the screen is showing; anything else must be
        #--- asked for by number.
        idx = len(frames) - 1 if want is None else (want - 1 if want > 0 else len(frames) + want)
        idx = max(0, min(idx, len(frames) - 1))
        text = "\n".join(frames[idx])
        exp, act = parse(text)

    print("DIAG DIFF - the paint's own declaration vs the terminal's object list")
    if frames:
        print("  frame: %d of %d (last frame unless --frame picked another)"
              % (idx + 1, len(frames)))
    if not exp:
        print("  expected objects: 0")
        print("")
        print("NOT READABLE: this log carries no `[dsdiag] EXPECT` line. Either the build")
        print("predates P-DRAW-123 or DSTRIP_DIAG is 0 (Biotak/DrawStrip_Head.mqh). Open")
        print("the panel (or switch a group) with the switch on, then run this on the")
        print("terminal's own Experts log.")
        return 2
    print("  declared by the paint: %d   held by the chart: %d" % (len(exp), len(act)))
    bad = diff(exp, act)
    if not bad:
        print("")
        print("PASS - every object the panel painted is held exactly as declared "
              "(seat, layer, text).")
        return 0

    by_class = {}
    for cls, e, why in bad:
        by_class.setdefault(cls, []).append((e, why))
    print("")
    for cls in ("MISSING", "TYPE", "CORNER", "NO INK", "LAYER", "TEXT", "SEAT", "OCCLUDED"):
        for e, why in by_class.get(cls, []):
            print("  [%-7s] %-22s role=%-4s %s" % (cls, e["obj"], e["role"], why))
    print("")
    print("DIVERGED: %d of %d declared object(s) - %s"
          % (len(bad), len(exp),
             ", ".join("%s %d" % (c, len(v)) for c, v in sorted(by_class.items()))))
    print("CORE GAP is the first class above: the paint's declaration is the intent and")
    print("the census is the fact, so the difference is the terminal's doing - not a")
    print("layout guess. Fix the named objects, rebuild, re-open the panel, run again.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
