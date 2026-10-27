#!/usr/bin/env python3
"""
THE MUTATION GATE — prove the gates can FAIL, or admit they cannot.

WHY. A green gate proves something only if that gate is able to go red. On 2026-10-01 a
band's `.cnt` pill read 4 for a two-member group and EVERY gate was green, because none
of them measured the number: the check existed, the assertion did not. The industry
answer to exactly that asymmetry is mutation testing — put the defect back, and the
suite must die (Zeller's delta debugging asks the same question of a failing input: what
is the MINIMAL change between the passing and the failing case?). This tool does it for
this project's rules, one rule at a time:

  * apply the mutation (the exact inverse of a fixed defect, by literal string),
  * run the gate that owns the rule,
  * KILLED  = the gate failed AND its message names the rule — the objective evidence
              is the gate's own failing line, printed here,
  * SURVIVED = the gate passed, so the rule is NOT gated: a blind spot, and a build fail,
  * STALE    = the anchor is gone (the code moved), which is its own alarm: a mutation
              that no longer applies is a check that no longer runs.

SAFETY. Every mutated file is restored from an in-memory copy in a `finally`, and every
touched file's sha256 is verified against its pre-run hash before this tool reports
anything. It never uses git (your uncommitted work is not its business), it mutates one
file at a time, and it takes about two seconds. Run it when nobody else is editing the
tree: an outside write during the ~0.3 s a mutation is on disk would be overwritten.

  python tools/mutation_gate.py            # every mutation
  python tools/mutation_gate.py P-DRAW-121 # one rule
  python tools/mutation_gate.py --list     # the mutations + which register entries lack one

Exit 0 = every mutation was killed and the tree is byte-identical to how it was found.
"""

import hashlib
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

#--- the gates a mutation may be aimed at: key -> (runner, path from ROOT, label)
GATES = {
    "gear": ("python", "tools/check-gear-panel.py", "gear panel gate"),
    "lifecycle": ("node", "tools/object_lifecycle_check.js", "object lifecycle gate"),
    "regression": ("node", "tools/check-regressions.js", "regression gate"),
    "parity": ("python", "tools/ui_parity_audit.py", "ui parity gate"),
    "resources": ("node", "tools/check-resources.js", "resource gate"),
    "pen": ("python", "tools/pen-sim.py", "pen scenario sim"),
}

GEAR_B = "Biotak/DrawStrip_GearB.mqh"
STRIP_BASE = "Biotak/DrawStrip_Base.mqh"
GEAR_SIM = "tools/sim-gear-panel.py"
GEAR_GATE = "tools/check-gear-panel.py"
REGISTER = "tools/check-regressions.js"

#--- ONE RULE PER MUTATION. `find` is the fixed spelling, `replace` puts the defect back;
#--- `expect` is the text the owning gate must print (its own message, so a gate that
#--- fails for an unrelated reason does not count as a kill).
MUTATIONS = [
    {
        "id": "P-DRAW-121",
        "gate": "gear",
        "rule": "a band's pill counts members, never the accordion's nav",
        "what": "the row loop stops excluding DSTRIP_GRK_GROUP",
        "file": GEAR_B,
        "find": "      if(s_dsGRKind[r] != DSTRIP_GRK_GROUP &&\r\n"
                "         s_dsGRCol[r] == col && s_dsGRY[r] >= y0 && s_dsGRY[r] < y1) n++;",
        "replace": "      if(s_dsGRCol[r] == col && s_dsGRY[r] >= y0 && s_dsGRY[r] < y1) n++;",
        "expect": "P-DRAW-121",
    },
    {
        "id": "P-DRAW-121b",
        "gate": "gear",
        "rule": "the mirror's nav detector must be able to fire (self-test)",
        "what": "the mirror stops noticing group headers inside a band's range",
        "file": GEAR_SIM,
        "find": "            if b[3] and str(b[3][0]) == str(GRK_GROUP):",
        "replace": "            if False and b[3] and str(b[3][0]) == str(GRK_GROUP):",
        "expect": "detector is blind",
    },
    {
        "id": "P-DRAW-121c",
        "gate": "regression",
        "rule": "the gate must assert the count rule and its numbers",
        "what": "the gear gate stops asserting the rule (the register must notice)",
        "file": GEAR_GATE,
        "find": "        check(M.count_rule_excludes_nav(),",
        "replace": "        check(True,   # MUTATION: the assertion removed",
        "expect": "must assert the rule",
    },
    {
        "id": "P-DRAW-122",
        "gate": "lifecycle",
        "rule": "a painted layer is re-asserted every pass",
        "what": "DrawStripRect writes its layer only at birth again",
        "file": GEAR_B,
        "find": "   dirty |= DrawStripSetInt(nm, OBJPROP_ZORDER, z);\r\n"
                "   dirty |= DrawStripSetInt(nm, OBJPROP_BACK, false);\r\n"
                "   dirty |= DrawStripSetInt(nm, OBJPROP_XDISTANCE, x);\r\n"
                "   dirty |= DrawStripSetInt(nm, OBJPROP_YDISTANCE, y);\r\n"
                "   dirty |= DrawStripSetInt(nm, OBJPROP_XSIZE, w);\r\n"
                "   dirty |= DrawStripSetInt(nm, OBJPROP_YSIZE, h);\r\n"
                "   dirty |= DrawStripSetInt(nm, OBJPROP_BGCOLOR, face);",
        "replace": "   dirty |= DrawStripSetInt(nm, OBJPROP_XDISTANCE, x);\r\n"
                   "   dirty |= DrawStripSetInt(nm, OBJPROP_YDISTANCE, y);\r\n"
                   "   dirty |= DrawStripSetInt(nm, OBJPROP_XSIZE, w);\r\n"
                   "   dirty |= DrawStripSetInt(nm, OBJPROP_YSIZE, h);\r\n"
                   "   dirty |= DrawStripSetInt(nm, OBJPROP_BGCOLOR, face);",
        "expect": "P-DRAW-122",
    },
    {
        "id": "P-DRAW-120",
        "gate": "regression",
        "rule": "a face re-asserts its own layer every paint",
        "what": "DrawStripFaceZ writes its layer only at birth again",
        "file": GEAR_B,
        "find": "   dirty |= DrawStripSetInt(nm, OBJPROP_ZORDER, z);\r\n"
                "   dirty |= DrawStripSetInt(nm, OBJPROP_BACK, false);\r\n"
                "   int pw = DrawStripResW(res), ph = DrawStripResH(res);",
        "replace": "   int pw = DrawStripResW(res), ph = DrawStripResH(res);",
        "expect": "P-DRAW-120",
    },
    {
        "id": "P-DRAW-125",
        "gate": "regression",
        "rule": "the diagnostic repaints only an open, laid-out panel",
        "what": "the dump paints a shut panel again (head+foot of a closed panel, body deleted)",
        "file": GEAR_B,
        "find": "   if(s_dsGear != 0 && s_dsGearH > 0)\r\n"
                "   {\r\n"
                "      s_dsDiagArm = true;",
        "replace": "   if(true)\r\n"
                   "   {\r\n"
                   "      s_dsDiagArm = true;",
        "expect": "P-DRAW-125",
    },
    {
        "id": "P-DRAW-125b",
        "gate": "regression",
        "rule": "every writer asks the object's own TYPE, not its name alone",
        "what": "DrawStripForeign stops reading OBJPROP_TYPE (a foreign name is never reclaimed)",
        "file": STRIP_BASE,
        "find": "   if((int)ObjectGetInteger(0, nm, OBJPROP_TYPE) == type) return;",
        "replace": "   if(true) return;",
        "expect": "P-DRAW-125",
    },

    #--- P-PAL-20 — THE SURFACE LEDGER IS CONSULTED BY THE PIXEL ORACLE. Dropping the
    #--- clause is the exact measured defect: the strip owns a floating popup (the
    #--- cards' palette), a colour pick is a release on TWO channels, the palette
    #--- serves it first, and `DrawStripPointInside` then reads the release pixel as
    #--- bare chart and calls `DrawStripClose()` — «یک رنگ انتخاب می‌کنم کل استریپ بسته می‌شه».
    #--- The compiler cannot see it (a missing call), and no existing gate looked.
    {
        "id": "P-PAL-20",
        "gate": "regression",
        "rule": "the surface oracle consults the ledger, so a release on a popup the strip owns is not a click on the chart",
        "what": "DrawStripPointInside stops asking DrawStripSurfaceAt (the exact defect)",
        "file": STRIP_BASE,
        "find": "   if(DrawStripSurfaceAt(mx, my)) return true;",
        "replace": "   // MUTATION: the ledger is not consulted",
        "expect": "P-PAL-20",
    },
    #--- P-PAL-20b — AND THE BRIDGE IS THE SINGLE WRITER. Without it the ledger is
    #--- never fed: `g_PalX/PalW()` live in the panels, which the strip cannot see.
    {
        "id": "P-PAL-20b",
        "gate": "regression",
        "rule": "the entry's bridge republishes the ledger whole, every event",
        "what": "the bridge stops publishing the popup rect into the strip's ledger",
        "file": "Biotak Trigger TH3.mq4",
        "find": "     DrawStripSurfacePublish(g_PalX, g_PalY, PalW(), PalH());",
        "replace": "     // MUTATION: nobody publishes the popup rect",
        "expect": "P-PAL-20",
    },
    #--- P-DRAW-64a2 — THE BORDER BAR IS ANSWERED BY NAME. The merged seat paints two
    #--- bars; the name router is the whole hit test (the tap asks the OBJECT MT4
    #--- reported, never a coordinate). Drop `"R"` and the border's half paints and
    #--- never opens anything — the exact state the 4px ring left behind.
    {
        "id": "P-DRAW-64a2",
        "gate": "regression",
        "rule": "the name router answers the merged seat's border bar",
        "what": "the quick-row name loop stops answering the border bar's object",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": " || sparam == DrawStripIconName(i) + \"R\")",
        "replace": " )   // MUTATION: the border bar is not a control",
        "expect": "P-DRAW-64a2",
    },
    #--- P-DRAW-64a2b — THE CHIP ASKS THE STRIP FOR THE SLOT. Without it the popup
    #--- holds the kind and the strip keeps the OLD slot, so picking a border colour
    #--- writes the interior's tag: a swap the user cannot see until the next repaint.
    {
        "id": "P-DRAW-64a2b",
        "gate": "regression",
        "rule": "a role chip asks the strip which slot it means (the popup owns the kind, the strip owns the slot)",
        "what": "the role chip changes the popup's kind but never the strip's slot",
        "file": "Biotak/BiotakPanels_PalB.mqh",
        "find": "      DrawStripPalRoleSet(wantBorder ? 0 : 1);",
        "replace": "      // MUTATION: the slot is never moved with the kind",
        "expect": "P-DRAW-64a2",
    },
    #--- P-DRAW-64a2c — THE INK LIVES ABOVE ITS OWN BUTTON. Measured on the live
    #--- popup: both chips and both names were written at Z_PANEL_POP_BG (1601) while
    #--- their button sits at Z_PANEL_POP_CTL (1602), so the control covered its own
    #--- words — «APPLY TO» with two empty boxes. The constant's own comment already
    #--- said it (_FG = \«knobs/ink\»); this mutation puts the numbers back where the
    #--- report found them.
    {
        "id": "P-DRAW-64a2c",
        "gate": "regression",
        "rule": "a chip's own ink is painted above its button",
        "what": "the role chip's name goes back under its own button (the measured empty boxes)",
        "file": "Biotak/BiotakPanels_PalB.mqh",
        "find": "         ObjectSetInteger(0,p+sfx+\"t\",OBJPROP_ZORDER,Z_PANEL_POP_FG);",
        "replace": "         ObjectSetInteger(0,p+sfx+\"t\",OBJPROP_ZORDER,Z_PANEL_POP_BG);",
        "expect": "P-DRAW-64a2",
    },
    #--- P-DRAW-74b — THE CHILD TEST SEARCHES. The old test matched the suffix at
    #--- the END of the name, while every child ends in "<level>.<q>": no child was
    #--- ever one, and each stacked line was served, hit and learned as a drawing.
    {
        "id": "P-DRAW-74b",
        "gate": "regression",
        "rule": "the child test searches the suffix, so every stacked line is unowned",
        "what": "FibPenIsChild stops searching (no child is ever one again)",
        "file": "Biotak/FibPen.mqh",
        "find": "      int at = StringFind(name, FIBPEN_SUFFIX, pos);\r\n",
        "replace": "      int at = -1;   // MUTATION: the suffix is never searched\r\n",
        "expect": "P-DRAW-74b",
    },
    #--- P-DRAW-74b-b — THE VISIBLE WIDTH CONVERGES. Without the write the
    #--- thick dash stays the terminal's solid: the exact user report.
    {
        "id": "P-DRAW-74b-b",
        "gate": "regression",
        "rule": "the visible width of each level converges every sync",
        "what": "the convergence write goes back out (thick dash paints solid again)",
        "file": "Biotak/FibPen.mqh",
        "find": "         ObjectSetInteger(0, fibo, OBJPROP_LEVELWIDTH, l, vis);\r\n",
        "replace": "         // MUTATION: no convergence\r\n",
        "expect": "P-DRAW-74b",
    },
    #--- P-DRAW-74b-c — A LOOK PICK STICKS. Without the tag write the popover
    #--- shows Neon/Caps/Wash and nothing on the chart ever wears them.
    {
        "id": "P-DRAW-74b-c",
        "gate": "regression",
        "rule": "a look pick writes its tag through the slot's one writer",
        "what": "the STYLE slot stops translating 5/6/7 (looks never stick)",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "            if(lk > 0) FibPenLookSet(name, lk);\r\n",
        "replace": "            // MUTATION: look never sticks\r\n",
        "expect": "P-DRAW-74b",
    },
    #--- P-DRAW-74b-k — THE STYLE SLOT DOES NOT FOLD A PEN KIND'S LEVEL WIDTHS. While no
    #--- stack stands the LEVEL widths ARE the logical width; folding them to 1 BEFORE the
    #--- style write made the pen read 1, build nothing, and the level come out a plain
    #--- 1 px dash — the exact report «استایل ها روی ضخامت های بزرگ اعمال نمیشه».
    {
        "id": "P-DRAW-74b-k",
        "gate": "regression",
        "rule": "a style pick leaves a pen kind's level widths (the logical width) alone",
        "what": "the STYLE slot folds the level widths on a pen kind again (thick styled fibo dies)",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "            if(!penKind) DrawLevelsSetWidth(name, DRAW_WIDTH_MIN);\r\n",
        "replace": "            DrawLevelsSetWidth(name, DRAW_WIDTH_MIN);   // MUTATION: fold the levels\r\n",
        "expect": "P-DRAW-74b",
    },
    #--- P-DRAW-74b-l — THE COERCION DOES NOT TOUCH A PEN KIND. The fibo's OWN width/style
    #--- is a memory, not what it draws; reading it here forced a thick styled fibo back to
    #--- STYLE_SOLID every time the strip opened or the chart repainted, so the stack died
    #--- and the style vanished — the same report, one seat over.
    {
        "id": "P-DRAW-74b-l",
        "gate": "regression",
        "rule": "DrawStylePairCoerce never resets a pen kind (its drawn pair lives on the levels)",
        "what": "the coerce reads a pen kind again (a strip open resets a thick styled fibo to solid)",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "   if(FibPenServesName(name)) return false;   // P-UNIFY-3: the pen's own four \u2014 its sync owns the visible pair; the other level kinds fall back to the native fold\r\n",
        "replace": "   if(false) return false;   // MUTATION: pen kinds coerced again\r\n",
        "expect": "P-DRAW-74b",
    },
    #--- P-LOOK-RAY2 — THE PEN MIRRORS THE MASTER (2026-10-04). P-LOOK-RAY's "a level is
    #--- full width" was measured FALSE on the hand's own chart: the fibo carries its own
    #--- level-ray flag (`levels_ray`), and with it off the level lines stop AT THE
    #--- ANCHORS (`Fibo 54705`, x=681..1079) while a hardcoded-both-rays pen ran x=59..721
    #--- — the style hung in empty space on the left and stopped 40px short of the line
    #--- on the right («چرا استایل ها برا سمت راست اعمال نشده»). This mutation puts the hardcoded
    #--- TRUE pair back, the shape that produced it.
    {
        "id": "P-LOOK-RAY2-a",
        "gate": "regression",
        "rule": "the stacked rows take their span from the one owner, never a hardcoded pair",
        "what": "a fixed both-rays child comes back (the pen ignores its owner's span)",
        "file": "Biotak/FibPen.mqh",
        "find": "            ObjectSetInteger(0, nm2, OBJPROP_RAY_LEFT, penRL);\r\n"
                "            ObjectSetInteger(0, nm2, OBJPROP_RAY_RIGHT, penRR);\r\n",
        "replace": "            ObjectSetInteger(0, nm2, OBJPROP_RAY_LEFT, true);   // MUTATION: the old fixed ray\r\n"
                   "            ObjectSetInteger(0, nm2, OBJPROP_RAY_RIGHT, true);\r\n",
        "expect": "P-LOOK-RAY2",
    },
    #--- P-LOOK-RAY3-a (2026-10-04) \u2014 THE PEN'S SPAN IS MT4'S SPAN. P-LOOK-RAY2 mirrored
    #--- the master's OWN ray pair because it believed `OBJPROP_RAY_LEFT/RIGHT` was the fibo's
    #--- LEVEL ray. It is not: MT4 keeps that ray in its own field (`levels_ray` in the chart
    #--- file; a fibo writes no `ray=` entry at all) and MQL4 cannot read or write it, so the
    #--- read was always false and the pen was trimmed to the anchors while MT4's level lines
    #--- ran on to the chart edge \u2014 measured x=250..1863 for the line against x=595 for the pen
    #--- («\u0627\u0645\u062a\u062f\u0627\u062f \u062e\u0637 \u0647\u0627 \u0627\u0633\u062a\u0627\u06cc\u0644 \u0627\u0639\u0645\u0627\u0644 \u0646\u0634\u062f\u0647»). This mutation puts that read back.
    {
        "id": "P-LOOK-RAY3-a",
        "gate": "regression",
        "rule": "the pen states MT4's own level span instead of reading a flag that is not one",
        "what": "the pen reads OBJPROP_RAY_* off the fibo again (trimmed to the anchors)",
        "file": "Biotak/FibPen.mqh",
        "find": "   rl = true;    // P-LOOK-RAY5: the backward extension wears the style too\r\n"
                "   rr = true;    // P-LOOK-RAY5: ...and the forward one \u2014 full width, both anchor orders",
        "replace": "   rl = ((int)ObjectGetInteger(0, fibo, OBJPROP_RAY_LEFT) != 0);   // MUTATION: a flag that is not one\r\n"
                   "   rr = ((int)ObjectGetInteger(0, fibo, OBJPROP_RAY_RIGHT) != 0);\r\n",
        "expect": "P-LOOK-RAY3",
    },
    #--- P-LOOK-RAY3-b \u2014 THE SPAN IS STATED, NOT GUESSED. Without the right-hand half the
    #--- pen runs the OLD shape (anchors only) and the extension wears no thickness at all.
    {
        "id": "P-LOOK-RAY3-b",
        "gate": "regression",
        "rule": "the pen runs to the chart's right edge, the span MT4 gives a fibo's levels",
        "what": "the right-hand span goes back out (the pen stops at the second anchor)",
        "file": "Biotak/FibPen.mqh",
        "find": "   rr = true;    // P-LOOK-RAY5: ...and the forward one \u2014 full width, both anchor orders",
        "replace": "   rr = false;   // MUTATION: the pen stops at the anchors",
        "expect": "P-LOOK-RAY3",
    },
    #--- P-LOOK-RAY4-a/b (2026-10-04 14:27) — THE RAY TURNS WITH THE ANCHORS. RAY3's pair
    #--- was measured on a FORWARD-drawn fibo; with the anchors reversed MT4's DIRECTIONAL
    #--- trend rays turn the run leftward (measured on the hand's frame: MT4's own centre row
    #--- 0.01 left of the earlier anchor vs 0.62 from it, while the pen's rows hung at 0.63
    #--- there and read 0.00 right of point0 — «این امتداد به عقب و جلو چرا استایل و ضخامت
    #--- نمیگیره»). This mutation puts the forward pair on reversed anchors — the exact defect,
    #--- P-LOOK-RAY5 (2026-10-04): RAY4's branch retired — the master spans full width
    #--- both ways, so both mutations below put the forward-only pair back (the report).
    {
        "id": "P-LOOK-RAY4-a",
        "gate": "regression",
        "rule": "both extensions wear the style, in both anchor orders",
        "what": "the forward-only pair is back (the backward extension is bare again)",
        "file": "Biotak/FibPen.mqh",
        "find": "   rl = true;    // P-LOOK-RAY5: the backward extension wears the style too\r\n"
                "   rr = true;    // P-LOOK-RAY5: ...and the forward one \u2014 full width, both anchor orders",
        "replace": "   rl = false;   // MUTATION: forward-only again\r\n"
                   "   rr = true;    // MUTATION: the backward extension is bare\r\n",
        "expect": "P-LOOK-RAY4",
    },
    {
        "id": "P-LOOK-RAY4-b",
        "gate": "pen",
        "rule": "both extensions wear the style, in both anchor orders",
        "what": "the forward-only pair is back (the backward extension loses the run's thickness)",
        "file": "Biotak/FibPen.mqh",
        "find": "   rl = true;    // P-LOOK-RAY5: the backward extension wears the style too\r\n"
                "   rr = true;    // P-LOOK-RAY5: ...and the forward one \u2014 full width, both anchor orders",
        "replace": "   rl = false;   // MUTATION: forward-only again\r\n"
                   "   rr = true;    // MUTATION: the backward extension is bare\r\n",
        "expect": "P-SIM-RAY",
    },
    #--- P-LOOK-RAY2-b — THE PEN'S OWN NET. The pen had only event paths, so a master the
    #--- terminal landed after the last event kept a stale pen forever (the scene above,
    #--- hours old). The 2 s pass asks each fibo now; this mutation takes the seat away.
    {
        "id": "P-LOOK-RAY2-b",
        "gate": "regression",
        "rule": "the pen has its own net on the 2 s chart-side pass",
        "what": "the net seat is gone (a stale pen stays stale until the next touch)",
        "file": "Biotak/DrawStrip_Pick.mqh",
        "find": "      if(FibPenServesType(ty)) FibPenHeal(nm);\r\n",
        "replace": "      // MUTATION: no net\r\n",
        "expect": "P-LOOK-RAY2",
    },
    #--- P-LOOK-RAY2-c — THE HEAL COMPARES BEFORE IT SYNCS, or the net is a full sync of
    #--- every fibo on every pass (this repo's law: a still frame pays reads, writes none).
    {
        "id": "P-LOOK-RAY2-c",
        "gate": "regression",
        "rule": "FibPenHeal is a memo compare first, the sync only on a mismatch",
        "what": "the memo compare goes out (every pass syncs every fibo)",
        "file": "Biotak/FibPen.mqh",
        "find": "   int    at  = FibPenNetFind(fibo);\r\n",
        "replace": "   int    at  = -1;   // MUTATION: no memo\r\n",
        "expect": "P-LOOK-RAY2",
    },
    #--- P-LOOK-ANCHOR (2026-10-18) — MT4 PUTS 0 % AT THE SECOND ANCHOR. MEASURED on the
    #--- shot chart (StripShot_fibo_3d3.png, AMarkets A1660; anchors p0=1.12135,
    #--- p1=1.12298): the band wearing the «0.0» label sits at PRICE,1 (y=445) and
    #--- «423.6» at PRICE,1 + (PRICE,0 - PRICE,1) * 4.236 = 1.11605 (y=633) — the label
    #--- text and the pixels agree within 1 px on all nine bands, so the terminal's law
    #--- is `lv = PRICE,1 + (PRICE,0 - PRICE,1) * v`. The old `p1 + (p2 - p1) * v` wore
    #--- the mirror twin R(1 - v): every child sat under the wrong level (the «3D واقعی
    #--- نیست» report — its orphan dashes measured at y=305/376/420) and the press naming
    #--- (DrawHitLevels) and the drag arm (DrawFiboFullHit) measured lines MT4 never
    #--- draws. P-UNIFY-3 (2026-10-19) moved five of the six seats behind ONE owner —
    #--- Toolbar_A's `DrawLevelPriceAt` (the terminal's horizontal law is its fallback) —
    #--- and the chase keeps its one inline statement. Every mutation below puts the
    #--- mirror twin back at one seat or in the owner itself; the owning gate must fail
    #--- naming P-LOOK-ANCHOR.
    {
        "id": "P-LOOK-ANCHOR-b",
        "gate": "regression",
        "rule": "the sync rows seat every child through the one geometry owner",
        "what": "a sync row wears the mirror twin again (that kind's children land under the wrong levels)",
        "file": "Biotak/FibPen.mqh",
        "find": "            lvA = DrawLevelPriceAt(k, v, ta, p1, tb, p2, t3, p3, ts0);\r\n",
        "replace": "            lvA = p2 + (p1 - p2) * v;   // MUTATION: the mirror twin\r\n",
        "expect": "P-LOOK-ANCHOR",
    },
    {
        "id": "P-LOOK-ANCHOR-c",
        "gate": "regression",
        "rule": "the drag chase carries the family on the terminal's own law",
        "what": "the chase wears the mirror twin again (a dragged fibo's family lands under other levels mid-gesture)",
        "file": "Biotak/FibPen.mqh",
        "find": "      double lva = pb + (pa - pb) * v;   // P-LOOK-ANCHOR: 0 % at the SECOND anchor (the terminal's law)\r\n",
        "replace": "      double lva = pa + (pb - pa) * v;   // MUTATION: the mirror twin\r\n",
        "expect": "P-LOOK-ANCHOR",
    },
    {
        "id": "P-LOOK-ANCHOR-d",
        "gate": "regression",
        "rule": "the press naming measures the level lines the terminal actually draws",
        "what": "DrawHitLevels wears the mirror twin again (presses on the real lines name nothing — the P-DRAGF3c missed-grab class)",
        "file": "Biotak/Toolbar_Hit.mqh",
        "find": "      double la = DrawLevelPriceAt(k, v, t1, p1, t2, p2, t3, p3, t1);\r\n",
        "replace": "      double la = p2 + (p1 - p2) * v;   // MUTATION: the mirror twin\r\n",
        "expect": "P-LOOK-ANCHOR",
    },
    {
        "id": "P-LOOK-ANCHOR-e",
        "gate": "regression",
        "rule": "the drag arm's full hit measures the level lines the terminal actually draws",
        "what": "DrawFiboFullHit wears the mirror twin again (a fast flick on a real level line arms only at the release door)",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "      double la = DrawLevelPriceAt(k, v, t1, p1, t2, p2, t3, p3, t1);\r\n",
        "replace": "      double la = p2 + (p1 - p2) * v;   // MUTATION: the mirror twin\r\n",
        "expect": "P-LOOK-ANCHOR",
    },
    {
        "id": "P-LOOK-ANCHOR-f",
        "gate": "regression",
        "rule": "the one geometry owner carries the terminal's horizontal law",
        "what": "the owner's fallback wears the mirror twin again (every horizontal kind's children land under the wrong levels)",
        "file": "Biotak/Toolbar_A.mqh",
        "find": "   return pb + (pa - pb) * v;      //--- DK_FIBO/FIBOTIMES and the families this law already served\r\n",
        "replace": "   return pa + (pb - pa) * v;   // MUTATION: the mirror twin\r\n",
        "expect": "P-LOOK-ANCHOR",
    },
    #--- P-DRAW-74b-e — P-LOOK-ALL: ONE FIBO, ONE LOOK. The dialog edits one
    #--- level at a time, so a fibo arrives mixed; without the reference write
    #--- only the diverged level converges and the rest stay thin.
    {
        "id": "P-DRAW-74b-e",
        "gate": "regression",
        "rule": "every level converges onto level 0's style",
        "what": "the reference write goes back out (levels diverge again)",
        "file": "Biotak/FibPen.mqh",
        "find": "         ObjectSetInteger(0, fibo, OBJPROP_LEVELSTYLE, l, refSt);\r\n",
        "replace": "         // MUTATION: levels diverge again\r\n",
        "expect": "P-DRAW-74b",
    },
    #--- P-DRAW-74b-i — P-DRAGF: THE CHASE RIDES THE HAND STREAM. Drag events
    #--- arrive ~1-2/s against ~60-100 moves/s; parking the follow on the drag
    #--- event trails by whole seconds.
    {
        "id": "P-DRAW-74b-i",
        "gate": "regression",
        "rule": "the fibo chase runs on the mouse stream, armed by the drag",
        "what": "the follow leaves the mouse stream (chase trails by seconds)",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "       if(tleft) FibPenDragFollow((int)lparam, (int)dparam);\r\n",
        "replace": "       // MUTATION: no chase\r\n",
        "expect": "P-DRAW-74b",
    },
    #--- P-DRAW-74b-j — P-DEL-ALL: EVERYTHING A DRAWING OWNS DIES WITH IT. A
    #--- native delete bypasses the strip bin; without the hub sweep the fibo
    #--- family stays on the chart over the next drawing.
    {
        "id": "P-DRAW-74b-j",
        "gate": "regression",
        "rule": "a native delete sweeps the fibo family by name",
        "what": "the delete hub stops sweeping fibo strays (phantoms persist)",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "         if(FibPenStraysDrop(sparam)) casc = true;\r\n",
        "replace": "         // MUTATION: strays persist\r\n",
        "expect": "P-DRAW-74b",
    },
    #--- P-DRAW-74b-m — A DELETED CHILD IS NOT A MASTER. The native delete hub
    #--- calls the name-keyed sweep for every object the terminal removes; a child
    #--- has no family below it, and probing 48 master names per child measured
    #--- 1000 ms per master and 7125 ms for one cascade (2026-10-22 17:43).
    {
        "id": "P-DRAW-74b-m",
        "gate": "regression",
        "rule": "a deleted child never walks the master sweep",
        "what": "the child guard goes out (each child pays 48 absent probes)",
        "file": "Biotak/FibPen.mqh",
        "find": "   if(FibPenChildParent(fibo) != \"\") return false;\r\n",
        "replace": "   // MUTATION: child walks the master sweep\r\n",
        "expect": "P-DRAW-74b",
    },
    #--- P-DRAW-74b-n — THE FAMILY DIES IN ONE NATIVE CALL. The per-child loop
    #--- paid 27 ObjectDelete calls at ~225 ms each (6078 ms measured for one
    #--- fibo, 2026-10-22 18:10); the prefix call answers in one pass.
    {
        "id": "P-DRAW-74b-n",
        "gate": "regression",
        "rule": "the fibo family is swept in one prefix call",
        "what": "the sweep deletes nothing (the per-child loop would come back)",
        "file": "Biotak/FibPen.mqh",
        "find": "   return (ObjectsDeleteAll(0, fibo + \"_FS\") > 0);\r\n",
        "replace": "   return false;\r\n",
        "expect": "P-DRAW-74b",
    },
    #--- P-DRAW-74b-f — A DRAG FLUSHES ITS OWN FRAME. The terminal blits the
    #--- dragged master live; without the flush the followers trail one frame
    #--- behind for the whole resize gesture.
    {
        "id": "P-DRAW-74b-f",
        "gate": "regression",
        "rule": "the drag branch that re-syncs the followers flushes one frame",
        "what": "the drag flush goes back out (resized followers trail a frame)",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "      // GEAR branch: a user action gets one flush, a paint pass never does.\r\n"
                "      ChartRedraw();\r\n",
        "replace": "      // MUTATION: no drag flush\r\n",
        "expect": "P-DRAW-74b",
    },
    #--- P-DRAW-74b-g — THE RELEASE FLUSHES THE RE-STAMP. A gesture's last drag
    #--- frame can be coalesced away; the release repairs it in data, and only a
    #--- flush puts it on screen. RE-ANCHORED 2026-10-17: the 74c/DRAGF4 doors landed
    #--- inside the release block (PenStackSync + PenStackDragDisarm), so the find
    #--- follows the block's current spelling.
    {
        "id": "P-DRAW-74b-g",
        "gate": "regression",
        "rule": "the release that re-stamps the followers flushes one frame",
        "what": "the release flush goes back out (the last frame settles late)",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "            FibPenSync(relPressObj, false);   // P-DRAW-74b: the release re-states the pair too\r\n"
                "            PenStackSync(relPressObj, false);   // P-DRAW-74c: ...and the line's rows on the final seat\r\n"
                "            FibPenDragDisarm();   // P-DRAGF: the gesture is over, the chase stands down\r\n"
                "            PenStackDragDisarm();\r\n"
                "            ChartRedraw();   // P-DRAW-74b-f: the release flushes the re-stamp\r\n",
        "replace": "            FibPenSync(relPressObj, false);   // P-DRAW-74b: the release re-states the pair too\r\n"
                   "            PenStackSync(relPressObj, false);   // P-DRAW-74c: ...and the line's rows on the final seat\r\n"
                   "            FibPenDragDisarm();   // P-DRAGF: the gesture is over, the chase stands down\r\n"
                   "            PenStackDragDisarm();\r\n",
        "expect": "P-DRAW-74b",
    },
    #--- P-DRAW-74b-h — ZOOM RE-MEASURES THE SERVED FIBO. Pixel offsets go stale
    #--- under a new scale; the served object re-syncs with no walks.
    {
        "id": "P-DRAW-74b-h",
        "gate": "regression",
        "rule": "a chart change re-syncs the served fibo, walks none",
        "what": "the zoom hook goes back out (offsets go stale until a touch)",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "      if(id == CHARTEVENT_CHART_CHANGE) FibPenSync(s_dsObj, false);\r\n",
        "replace": "      // MUTATION: no zoom hook\r\n",
        "expect": "P-DRAW-74b",
    },
    #--- P-DRAGF2-a — THE PRESS ASKS ONCE, BY PIXELS. The chase that asked "the
    #--- nearest anchor by CURSOR PRICE" per move made the far (stale) anchor the
    #--- hand's as soon as the hand travelled, and the stack rode two positions at
    #--- once («موقع درگ و جابجای فیبو یک فریم عقب»). Re-guessing every move IS
    #--- that defect back: the decision is a press answer, taken once.
    {
        "id": "P-DRAGF2-a",
        "gate": "regression",
        "rule": "which anchor the hand took is decided once, at the press, by pixels",
        "what": "the anchor question is re-asked on every mouse move",
        "file": "Biotak/FibPen.mqh",
        "find": "   if(s_fibGrab < 0)\r\n",
        "replace": "   if(true)   // MUTATION: re-guess the anchor every move\r\n",
        "expect": "P-DRAGF2",
    },
    #--- P-DRAGF2-b — THE MOVE CHANNEL FLUSHES ITS OWN FRAME. The terminal blits
    #--- the dragged master live; the children are code-side moves and need the
    #--- flush, or they wait for the next natural repaint — the frame behind.
    {
        "id": "P-DRAGF2-b",
        "gate": "regression",
        "rule": "the move channel that re-seats the children flushes its own frame",
        "what": "the move flush goes back out (the stack waits for the next repaint)",
        "file": "Biotak/FibPen.mqh",
        "find": "   if(nMov > 0) ChartRedraw();\r\n",
        "replace": "   // MUTATION: no move flush\r\n",
        "expect": "P-DRAGF2",
    },
    #--- P-DRAGF2-c — A LANDING RESYNCS THE SNAPSHOT. The chase extrapolates the
    #--- hand between two terminal landings; without the probe the snapshot
    #--- drifts against the master's own truth for the whole gesture.
    {
        "id": "P-DRAGF2-c",
        "gate": "regression",
        "rule": "a terminal landing resyncs the snapshot and moves the cursor origin",
        "what": "the probe is blind to landings (the stack drifts against the master)",
        "file": "Biotak/FibPen.mqh",
        "find": "   if(p1 != s_fibProbeP[0] || p2 != s_fibProbeP[1] || t1 != s_fibProbeT[0] || t2 != s_fibProbeT[1])\r\n",
        "replace": "   if(false)   // MUTATION: never resync\r\n",
        "expect": "P-DRAGF2",
    },
    #--- P-DRAGF2-e — THE CHASE IS THE DRAWING'S, NOT THE STRIP'S. `FibPenDragArm`
    #--- stands above every guard, so with the strip shut the chase is the ONLY
    #--- per-move follower a dragged fibo has; put it under a shut-strip guard (the
    #--- seat it held before, and the shape P-DRAW-64d fixed one line away) and the
    #--- stack moves on the terminal drag events alone, DRAGSTAT 0.6-1.6 s apart.
    {
        "id": "P-DRAGF2-e",
        "gate": "regression",
        "rule": "the chase stands above the shut-strip guard, beside the press edge",
        "what": "the chase is pushed back under a shut-strip guard",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "       if(tleft) FibPenDragFollow((int)lparam, (int)dparam);\r\n",
        "replace": "       if(!s_dsOpen) return false;   // MUTATION: the chase back under the shut-strip guard\r\n       if(tleft) FibPenDragFollow((int)lparam, (int)dparam);\r\n",
        "expect": "P-DRAGF2",
    },
    #--- P-DRAGF2-d — A BODY DRAG TRANSLATES BOTH ANCHORS. MT4 moves the whole
    #--- pair when the hand is not on an anchor; substituting one side bends the
    #--- fibo under the hand instead of carrying it.
    {
        "id": "P-DRAGF2-d",
        "gate": "regression",
        "rule": "a body drag translates both anchors by the hand's own delta",
        "what": "the body drag freezes the pair (only one side would follow)",
        "file": "Biotak/FibPen.mqh",
        "find": "      pa = s_fibP0[0] + dp; pb = s_fibP0[1] + dp;\r\n",
        "replace": "      pa = s_fibP0[0]; pb = s_fibP0[1];   // MUTATION: the body drag freezes the pair\r\n",
        "expect": "P-DRAGF2",
    },
    #--- P-DRAGF3 (2026-10-17) — THE GESTURE BELONGS TO THE TERMINAL. MEASURED
    #--- (P-DRAGF2's own numbers): OBJECT_DRAG fires ~1-2/s while the hand's moves
    #--- arrive ~60-100/s, and the demoted master's children are re-seated by US on
    #--- every move — a frame AFTER the terminal's own blit, which is structural: a
    #--- follower can never be in the frame it follows. The fix: at the arm the stack
    #--- hands the body back (every stacked level to its logical width — MT4 draws
    #--- SOLID at width>1 — children hidden once), Follow/Sync/Heal stand down, and
    #--- ONE sync converges at the release through both doors (click, button-up).
    #--- Each inverse must fail §58 naming P-DRAGF3. P-DRAGF3c (2026-10-17): the ARM
    #--- is the gesture's FIRST TRAVELED MOVE, not the terminal's drag event — MEASURED
    #--- (the user's 20:17 flick): id=2 arrived in the SAME TICK as the release, the
    #--- preview lived ~10 ms (view=on -> view=off) and the stack stood frozen at the
    #--- old seat through the whole motion. The press names (s_dsPressObj), the travel
    #--- vetoes (a hold/click never arms), the memo is per press, and the trip must
    #--- stand BEFORE the chase call. Its inverse must fail §58 too (g and h below).
    {
        "id": "P-DRAGF3-a",
        "gate": "regression",
        "rule": "the chase stands down while the preview owns the gesture",
        "what": "the chase is not gated — every move re-seats the stack the preview just handed back",
        "file": "Biotak/FibPen.mqh",
        "find": "   if(s_fibPreview) return;   // P-DRAGF3: the preview owns the gesture - zero writes per move\r\n",
        "replace": "   // MUTATION: the chase is not gated\r\n",
        "expect": "P-DRAGF3",
    },
    {
        "id": "P-DRAGF3-b",
        "gate": "regression",
        "rule": "the arm opens the preview (only a new gesture's first drag event)",
        "what": "arm without preview — the gesture falls back to the chase, which IS the frame behind",
        "file": "Biotak/FibPen.mqh",
        "find": "   FibPenPreviewArm();   // P-DRAGF3: a patterned thick fibo drags NATIVELY - see the block below\r\n",
        "replace": "   // MUTATION: no preview is opened\r\n",
        "expect": "P-DRAGF3",
    },
    {
        "id": "P-DRAGF3-c",
        "gate": "regression",
        "rule": "the sync is gated by the preview but NEVER for dropAll",
        "what": "the sync gate is gone — mid-gesture syncs re-demote the body while the terminal blits it full-width",
        "file": "Biotak/FibPen.mqh",
        "find": "   if(s_fibPreview && !dropAll && fibo == s_fibPreviewObj) return false;   // P-DRAGF3: gated while the preview owns the gesture; dropAll (delete) is never gated\r\n",
        "replace": "   // MUTATION: the sync is not gated\r\n",
        "expect": "P-DRAGF3",
    },
    {
        "id": "P-DRAGF3-d",
        "gate": "regression",
        "rule": "the release ends the preview BEFORE it re-states the pair",
        "what": "the click door never ends the preview — the body stays native and the un-hide never lands in the release's frame",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "         bool fbPrev = FibPenPreviewEnd();\r\n",
        "replace": "          bool fbPrev = false;   // MUTATION: the click door never ends the preview\r\n",
        "expect": "P-DRAGF3",
    },
    {
        "id": "P-DRAGF3-e",
        "gate": "regression",
        "rule": "the button-up door converges a preview too",
        "what": "the off-chart release has no door — the preview stays armed until the next gesture",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "          if(FibPenPreviewEnd()) ChartRedraw();\r\n",
        "replace": "          // MUTATION: the button-up door is gone\r\n",
        "expect": "P-DRAGF3",
    },
    {
        "id": "P-DRAGF3-f",
        "gate": "regression",
        "rule": "the end clears the flag before its own convergence sync",
        "what": "the flag never clears — the convergence call reads its own gate and the fibo stays native with hidden children",
        "file": "Biotak/FibPen.mqh",
        "find": "   s_fibPreview = false;   // cleared FIRST: the sync below must not read its own gate\r\n",
        "replace": "   // MUTATION: the flag is not cleared\r\n",
        "expect": "P-DRAGF3",
    },
    {
        "id": "P-DRAGF3-g",
        "gate": "regression",
        "rule": "the first TRAVELED MOVE of the press opens the gesture (the terminal names too late)",
        "what": "the press-move arm is gone — a flick's OBJECT_DRAG arrives at the release, so the stack stands frozen through the whole motion and snaps at the end",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "         if(tleft && armAsk != \"\" && armAsk != s_dsArmTried && s_dsTravel > DSTRIP_CLICK_SLOP)\r\n"
                "         {\r\n"
                "            s_dsArmTried = armAsk;\r\n"
                "            FibPenDragArm(armAsk);\r\n"
                "            PenStackDragArm(armAsk);   // P-DRAW-74c: the same trip names the line pen\r\n"
                "            BoxPreviewArm(armAsk);   // P-DRAGF4: and hands the box's interior to the terminal\r\n"
                "            if(s_fibDragObj != \"\")\r\n"
                "               DrawStripDiagEmit(\"[drawstrip] FIBPENARM obj=\\\"\" + s_fibDragObj + \"\\\" travel=\" +\r\n"
                "                                 IntegerToString(s_dsTravel));\r\n"
                "            if(s_psDragObj != \"\")\r\n"
                "               DrawStripDiagEmit(\"[drawstrip] PENSTACKARM obj=\\\"\" + s_psDragObj + \"\\\" travel=\" +\r\n"
                "                                 IntegerToString(s_dsTravel));\r\n"
                "         }\r\n",
        "replace": "         // MUTATION: the terminal alone arms, at its own late tick\r\n",
        "expect": "P-DRAGF3",
    },
    {
        "id": "P-DRAGF3-h",
        "gate": "regression",
        "rule": "the press-move arm writes its flushed witness",
        "what": "the arm witness is gone — «preview never armed» becomes unarguable at the next capture",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "            if(s_fibDragObj != \"\")\r\n"
                "               DrawStripDiagEmit(\"[drawstrip] FIBPENARM obj=\\\"\" + s_fibDragObj + \"\\\" travel=\" +\r\n"
                "                                 IntegerToString(s_dsTravel));\r\n",
        "replace": "            // MUTATION: the press-move arm writes no witness\r\n",
        "expect": "P-DRAGF3",
    },
    #--- P-DRAGF3d (2026-10-17) - THE PRESS THAT NAMED NOTHING CAN STILL BE THE PEN'S.
    #--- MEASURED (the 20:51 frame, biotak_diag_EURUSD_134362571361933137): FIBPENPRE
    #--- view=on 25 against FIBPENARM 22, and 4 of the 25 real drags armed only at the
    #--- release door - the press named nothing because a fast flick grabs the fibo by
    #--- its DIAGONAL, which DrawHitLevels never measures. The trip now asks the
    #--- terminal's selected fibo through a geometry fence (Toolbar_B), spends its
    #--- probe on a miss, and the fence measures the anchor handles, the ray-paired
    #--- diagonal and ray-extended levels. Each inverse must fail 58 naming P-DRAGF3d.
    {
        "id": "P-DRAGF3-i",
        "gate": "regression",
        "rule": "an unnamed press asks the terminal's selected fibo (the diagonal grab)",
        "what": "the probe call is gone - a fast flick's diagonal grab names nothing again (the reported defect)",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "           armAsk = DrawSelectedFiboAt(tmx, tmy);\r\n",
        "replace": "           // MUTATION: an unnamed press never asks the terminal's selection\r\n",
        "expect": "P-DRAGF3d",
    },
    {
        "id": "P-DRAGF3-j",
        "gate": "regression",
        "rule": "the unnamed-press probe is spent on a miss (one walk per press, not per move)",
        "what": "the miss is not memoed - every move of a pan re-walks the object list",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "           if(armAsk == \"\") s_dsArmTried = \"@\";   // the probe is spent: no name, no re-walk\r\n",
        "replace": "           // MUTATION: the probe is never spent - a pan re-walks every move\r\n",
        "expect": "P-DRAGF3d",
    },
    {
        "id": "P-DRAGF3-k",
        "gate": "regression",
        "rule": "the third pick measures the diagonal with the object's own rays",
        "what": "the diagonal test is gone - the pick the terminal grabs by is not measured (the reported defect)",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "   if(DrawSegDist(px, py, x1, y1, x2, y2, oA, oB) <= (double)DRAW_HIT_PX) return true;   // the diagonal\r\n",
        "replace": "   // MUTATION: the diagonal is not measured - the flick names nothing again\r\n",
        "expect": "P-DRAGF3d",
    },
    #--- P-DRAGF3a (2026-10-17) - A LOOK'S CHILDREN EXIST WITH NO STACK. CAPS and WASH
    #--- ride a SOLID level (`want` is 0), so the stack-gated loop never saw them and
    #--- the halo chased the hand one frame behind while the arm refused them on width
    #--- alone. The arm asks the look tag before any width fence, no level skips its
    #--- caps/wash, and the arm's gate counts them (nH) beside demoted levels (nW).
    #--- Each inverse must fail 58 naming P-DRAGF3a.
    {
        "id": "P-DRAGF3a-a",
        "gate": "regression",
        "rule": "the arm asks the look tag before any width fence",
        "what": "the width fence returns alone - a look-only fibo (CAPS/WASH, no stack) is refused and its halo is back to the chase",
        "file": "Biotak/FibPen.mqh",
        "find": "   if(FibPenLookGet(fibo) == 0 && refLog <= DRAW_WIDTH_MIN) return;\r\n",
        "replace": "   if(refLog <= DRAW_WIDTH_MIN) return;   // MUTATION: the look tag is not asked\r\n",
        "expect": "P-DRAGF3a",
    },
    {
        "id": "P-DRAGF3a-b",
        "gate": "regression",
        "rule": "the arm's gate counts hidden look children beside demoted levels",
        "what": "the gate counts only nW - a look-only fibo hides its children and never flips the flag, so the END never runs to un-hide them",
        "file": "Biotak/FibPen.mqh",
        "find": "   if(nW <= 0 && nH <= 0) return;   // nothing demoted and no look child: no preview, no flag\r\n",
        "replace": "   if(nW <= 0) return;   // MUTATION: the gate counts only demoted levels\r\n",
        "expect": "P-DRAGF3a",
    },
    {
        "id": "P-DRAGF3a-c",
        "gate": "regression",
        "rule": "no level skips its caps/wash when it carries no stack",
        "what": "the `c <= 0` skip returns - the look children are re-seated per move by the chase, one frame behind",
        "file": "Biotak/FibPen.mqh",
        "find": "      int c = FibPenChildCount(fibo, l);\r\n      if(c > 0)   // the rows the arm hid\r\n",
        "replace": "      int c = FibPenChildCount(fibo, l);\r\n      if(c <= 0) continue;   // MUTATION: a level without a stack skips its caps/wash again\r\n",
        "expect": "P-DRAGF3a",
    },
    #--- P-LOOK-3D RETIRED (2026-10-18) - "3D: remove entirely" (user order). The
    #--- fourth look, its `[LK4]` tag and its `_FSH` shadow are gone end to end; what
    #--- stays is the SWEEP (the sync's spend pass, the delete hub, HasPen, the early-out
    #--- probe) so a legacy chart degrades to the previous look. Every mutation below
    #--- puts a seat back and must fail 58 naming P-LOOK-3D (the gate prefixes its
    #--- message with 'P-LOOK-3D retired:').
    {
        "id": "P-LOOK-3D-b",
        "gate": "regression",
        "rule": "the tag reader fences the retired seat",
        "what": "the reader's fence walks past WASH - a `[LK4]` from a legacy chart is read as a live look again",
        "file": "Biotak/FibPen.mqh",
        "find": "   if(lk < FIBPEN_LOOK_NEON || lk > FIBPEN_LOOK_WASH) return 0;\r\n",
        "replace": "   if(lk < FIBPEN_LOOK_NEON || lk > FIBPEN_LOOK_WASH + 1) return 0;   // MUTATION: 4 is read again\r\n",
        "expect": "P-LOOK-3D",
    },
    {
        "id": "P-LOOK-3D-c",
        "gate": "regression",
        "rule": "the retired define stays gone",
        "what": "the `FIBPEN_LOOK_3D` define is back - the fourth seat has a name again",
        "file": "Biotak/DrawKindProfile.mqh",
        "find": "#define DRAW_LOOK_WASH   3\n",
        "replace": "#define DRAW_LOOK_WASH   3\n#define DRAW_LOOK_3D     4   // MUTATION: the retired define is back\n",
        "expect": "P-LOOK-3D",
    },
    {
        "id": "P-LOOK-3D-d",
        "gate": "regression",
        "rule": "the retirement sweep stays",
        "what": "the sync's spend pass is gone - a legacy `_FSH` shadow stays on the chart forever",
        "file": "Biotak/FibPen.mqh",
        "find": "       if(ObjectFind(0, snm) >= 0) { ObjectDelete(0, snm); dirty = true; nDrop++; }\r\n",
        "replace": "       // MUTATION: the retirement sweep is gone\r\n",
        "expect": "P-LOOK-3D",
    },
    {
        "id": "P-LOOK-3D-e",
        "gate": "regression",
        "rule": "the build fence stays out of the sync",
        "what": "the `shwOk` fence is back - the sync can paint a shadow the look no longer offers",
        "file": "Biotak/FibPen.mqh",
        "find": "       string snm = FibPenShwName(fibo, l6);\r\n",
        "replace": "       bool shwOk = false;   // MUTATION: the build fence is back\r\n       string snm = FibPenShwName(fibo, l6);\r\n",
        "expect": "P-LOOK-3D",
    },
    {
        "id": "P-LOOK-3D-f",
        "gate": "regression",
        "rule": "the delete sweep covers every family in ONE prefix call",
        "what": "the sweep is gone - a deleted fibo leaves its `_FS*` family on the chart",
        "file": "Biotak/FibPen.mqh",
        "find": "   return (ObjectsDeleteAll(0, fibo + \"_FS\") > 0);\r\n",
        "replace": "   return false;   // MUTATION: the sweep is gone\r\n",
        "expect": "P-LOOK-3D",
    },
    {
        "id": "P-LOOK-3D-f2",
        "gate": "regression",
        "rule": "the drop path is not fenced on level 0",
        "what": "the level-0 fence is back - a stray on another level survives and the net re-syncs it forever",
        "file": "Biotak/FibPen.mqh",
        "find": "      bool dd = FibPenStraysDrop(fibo);\r\n",
        "replace": "      if(!dropAll && ObjectFind(0, FibPenName(fibo, 0, 0)) < 0) return false;   // MUTATION: the level-0 fence is back\r\n      bool dd = FibPenStraysDrop(fibo);\r\n",
        "expect": "P-LOOK-3D",
    },
    {
        "id": "P-LOOK-3D-g",
        "gate": "regression",
        "rule": "the fam test accepts `_FSH`",
        "what": "the shadow family is refused - a `_FSH` stray is served, hit and learned as a drawing of its own",
        "file": "Biotak/FibPen.mqh",
        "find": "         if(fc != 'C' && fc != 'W' && fc != 'H') ok = false;\r\n",
        "replace": "         if(fc != 'C' && fc != 'W' && fc == 'H') ok = false;   // MUTATION: the shadow family is refused\r\n",
        "expect": "P-LOOK-3D",
    },
    {
        "id": "P-LOOK-3D-h",
        "gate": "regression",
        "rule": "the STYLE popover owes the fibo eight rows",
        "what": "the ninth cell is back - a retired look asks for a row again",
        "file": "Biotak/DrawStrip_Pick.mqh",
        "find": "   if(slot == DRAW_SLOT_STYLE) return ((int)STYLE_DASHDOTDOT + 1 + (DrawStripPenLook(k) ? DrawLookCount() : 0));   // P-UNIFY-4: native five + the registry's looks\r\n",
        "replace": "   if(slot == DRAW_SLOT_STYLE) return ((int)STYLE_DASHDOTDOT + 1 + (DrawStripPenLook(k) ? DrawLookCount() : 0) + 1);   // MUTATION: the ninth cell is back\r\n",
        "expect": "P-DRAW-74b",
    },
    {
        "id": "P-LOOK-3D-i",
        "gate": "regression",
        "rule": "the STYLE writer keeps its WASH cap",
        "what": "the writer walks past WASH - the eighth cell is pickable and dead",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "            lk = DrawLookFromSlot(st);   // P-UNIFY-4: 5 -> 1, 6 -> 2, 7 -> 3; 8 and above -> 0\r\n",
        "replace": "            lk = st - (int)STYLE_DASHDOTDOT;   // MUTATION: 8 is live again\r\n",
        "expect": "P-LOOK-3D",
    },
    {
        "id": "P-LOOK-3D-k",
        "gate": "regression",
        "rule": "the pen's existence test knows the shadow family",
        "what": "HasPen is blind to `_FSH` - the heal's memo reads \"no pen\" for a 3D fibo and the net stops converging",
        "file": "Biotak/FibPen.mqh",
        "find": "   if(ObjectFind(0, FibPenShwName(fibo, 0)) >= 0) return true;\r\n",
        "replace": "   // MUTATION: the shadow family is not a pen\r\n",
        "expect": "P-LOOK-3D",
    },
    #--- P-LOOK-3D-l RETIRED (2026-10-22): it mutated the level-0 fence's shadow
    #--- probe. The fence itself is gone (P-LOOK-3D-f2 asserts its absence), so
    #--- there is no spelling left to break — a mutation without an anchor is a
    #--- rule that stopped running, and this one was retired with its site.
    {
        "id": "P-LOOK-3D-m",
        "gate": "regression",
        "rule": "the retired look stays out of the shot harness",
        "what": "the harness re-adds the 3D state - a retired look asks for real pixels again",
        "file": "tests/Biotak_StripShot_Test.mq4",
        "find": "       SSFiboLook(\"fibo_wash2\",  2, 4 + FIBPEN_LOOK_WASH);\r\n",
        "replace": "       SSFiboLook(\"fibo_wash2\",  2, 4 + FIBPEN_LOOK_WASH);\r\n       SSFiboLook(\"fibo_3d3\",    3, 8);   // MUTATION: the retired state is back\r\n",
        "expect": "P-LOOK-3D",
    },
    {
        "id": "P-DRAW-119-a",
        "gate": "regression",
        "rule": "the freshness gate parses EVERY harness ask (the look states included)",
        "what": "the state parser forgets SSFiboLook - five look PNGs are shot and never called current or stale",
        "file": "tools/check-shot-freshness.js",
        "find": "SS(?:State|Kind|FiboLook|Pen)",
        "replace": "SS(?:State|Kind|Pen)",
        "expect": "P-DRAW-119",
    },
    {
        "id": "P-DRAW-119-b",
        "gate": "regression",
        "rule": "the shot launch hands MT4 the ini as a BARE argument",
        "what": "the launch goes back to the colon-suffixed switch of MT5 - MT4 ignores it in silence: the profile opens, no extra chart, no script, 120 s of silence (measured 2026-10-18)",
        "file": "compile-th3.ps1",
        "find": "$shotArgs = (\"$($shotStart.Args) `\"$configPath`\"\").Trim()",
        "replace": "$shotArgs = (\"$($shotStart.Args) /config:`\"$configPath`\"\").Trim()   # MUTATION: MT5's switch form, ignored by MT4",
        "expect": "P-DRAW-119",
    },
    {
        "id": "P-DRAW-119-c",
        "gate": "regression",
        "rule": "the printed NEXT line shows the bare-argument launch",
        "what": "the printed command reverts to the switch form - a user running it by hand gets the profile and 120 s of silence (measured 2026-10-18)",
        "file": "compile-th3.ps1",
        "find": "        Write-Host \"        terminal.exe `\"$configPath`\"\" -ForegroundColor Yellow",
        "replace": "        Write-Host \"        terminal.exe /config:`\"$configPath`\"\" -ForegroundColor Yellow   # MUTATION: the switch MT4 ignores",
        "expect": "P-DRAW-119",
    },
    #--- P-DRAW-74c (2026-10-17) - THE LINE PEN'S WIRING. PenStack.mqh was born beside
    #--- the fibo's pen (P-DRAGF3's law) and wired NOWHERE: a thick dashed HLINE/VLine/
    #--- trendline stayed a demoted 1 px line and every reader lied about its width.
    #--- Each inverse must fail 58 naming P-DRAW-74c.
    {
        "id": "P-DRAW-74c-a",
        "gate": "regression",
        "rule": "the module is a member of the toolbar unit",
        "what": "PenStack.mqh joins no compiling unit - every call below is dead code and the terminal paints the demoted 1",
        "file": "Biotak/DrawToolbar.mqh",
        "find": "#include \"PenStack.mqh\"",
        "replace": "// MUTATION: the line pen's module is not included\n",
        "expect": "P-DRAW-74c",
    },
    {
        "id": "P-DRAW-74c-b",
        "gate": "regression",
        "rule": "a row is never served (DrawKindOf answers DK_NONE)",
        "what": "a stacked row is served again - hits, presets and the strip learn the rows instead of their master",
        "file": "Biotak/Toolbar_A.mqh",
        "find": "   if(PenStackIsChild(name)) return DK_NONE;   // P-DRAW-74c: nor the line pen's rows - served, hit and learned never\r\n",
        "replace": "   // MUTATION: a row is served as its master\r\n",
        "expect": "P-DRAW-74c",
    },
    {
        "id": "P-DRAW-74c-c",
        "gate": "regression",
        "rule": "the width cell reads 1 + rows, not the demoted 1",
        "what": "the width cell answers the demoted 1 - the strip shows 1 px for a 3 px line and a re-pick writes 1",
        "file": "Biotak/Toolbar_A.mqh",
        "find": "            if(pw <= DRAW_WIDTH_MIN && ObjectFind(0, PenStackName(name, 0)) >= 0)\r\n               return (double)PenStackLogicalWidth(name);\r\n",
        "replace": "            // MUTATION: the width cell answers the demoted 1 again\r\n",
        "expect": "P-DRAW-74c",
    },
    {
        "id": "P-DRAW-74c-d",
        "gate": "regression",
        "rule": "a hover preview reaches the rows",
        "what": "the hover re-inks the master alone - the rows keep the old ink through the scrub and after it",
        "file": "Biotak/Toolbar_A.mqh",
        "find": "   PenStackSync(name, false);   // P-DRAW-74c: and a line's rows ride the hover too\r\n",
        "replace": "   // MUTATION: the hover never re-dresses the rows\r\n",
        "expect": "P-DRAW-74c",
    },
    {
        "id": "P-DRAW-74c-e",
        "gate": "regression",
        "rule": "DrawStylePairCoerce refuses pen kinds (the sync owns their visible pair)",
        "what": "the coerce reads a line pen again - the strip open forces a stacked line back to a 1 px pen and the rows die",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "   if(PenStackServes(name)) return false;\r\n",
        "replace": "   // MUTATION: the coerce reads a line pen again\r\n",
        "expect": "P-DRAW-74c",
    },
    {
        "id": "P-DRAW-74c-f",
        "gate": "regression",
        "rule": "the STYLE path's fold knows the line pen",
        "what": "the fold forgets the line pen - its own width is folded to 1 before the sync can read it, so a thick dashed line comes out a plain 1 px dash",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "            bool penKind = FibPenServesName(name) || PenStackServes(name);   // P-UNIFY-3: the pen's own four; the other level kinds fall back to the native fold\r\n",
        "replace": "            bool penKind = FibPenServesName(name);   // MUTATION: the fold forgets the line pen\r\n",
        "expect": "P-DRAW-74c",
    },
    {
        "id": "P-DRAW-74c-g",
        "gate": "regression",
        "rule": "the object-width fold stands down on a pen kind",
        "what": "the STYLE slot folds the object width on a pen kind - the logical memory dies one write early (P-DRAW-74b's defect, one family over)",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "            if(!penKind && (int)ObjectGetInteger(0, name, OBJPROP_WIDTH) != DRAW_WIDTH_MIN)\r\n",
        "replace": "            if((int)ObjectGetInteger(0, name, OBJPROP_WIDTH) != DRAW_WIDTH_MIN)   // MUTATION: the object width folds on a pen kind\r\n",
        "expect": "P-DRAW-74c",
    },
    {
        "id": "P-DRAW-74c-h",
        "gate": "regression",
        "rule": "a width-1 pick resolves the rows where the intent is known",
        "what": "a width-1 pick cannot come back - the stale rows outrank the read and the line keeps its old thickness",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "            if(w <= DRAW_WIDTH_MIN) PenStackStraysDrop(name);\r\n",
        "replace": "            // MUTATION: a width-1 pick never resolves the rows\r\n",
        "expect": "P-DRAW-74c",
    },
    {
        "id": "P-DRAW-74c-i",
        "gate": "regression",
        "rule": "the COLOUR slot converges the stack in its own pass",
        "what": "the colour slot leaves the rows behind - a recoloured line keeps old-ink rows",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "         //--- P-DRAW-74c: and a line's rows wear the same ink - one write reaches the stack.\r\n         PenStackSync(name, false);\r\n",
        "replace": "         // MUTATION: the colour slot leaves old-ink rows\r\n",
        "expect": "P-DRAW-74c",
    },
    {
        "id": "P-DRAW-74c-j",
        "gate": "regression",
        "rule": "the STYLE slot converges the stack in its own pass",
        "what": "the style slot leaves solid rows behind - a dashed pick never reaches the stack",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "         //--- dissolved them back into the master's width). Refuses non-pen kinds itself.\r\n         PenStackSync(name, false);\r\n",
        "replace": "         // MUTATION: the style slot leaves solid rows\r\n",
        "expect": "P-DRAW-74c",
    },
    {
        "id": "P-DRAW-74c-k",
        "gate": "regression",
        "rule": "a fresh line is stacked at birth (the remembered pair)",
        "what": "a line is born un-stacked - a remembered thick + dash pair flashes solid at birth until the 2 s heal",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "   //--- P-DRAW-74c: a fresh line born with a remembered THICK + DASH pair is stacked\r\n   //--- here, at birth - otherwise it would flash a solid thick line until the next\r\n   //--- heal pass. The sync reads the remembered width off the master and demotes it.\r\n   PenStackSync(name, false);\r\n",
        "replace": "   // MUTATION: a line is born un-stacked\r\n",
        "expect": "P-DRAW-74c",
    },
    {
        "id": "P-DRAW-74c-l",
        "gate": "regression",
        "rule": "an open re-converges the rows",
        "what": "an open never re-converges - a stack the terminal moved without an event trails the drawing until the next touch",
        "file": "Biotak/DrawStrip_Paint.mqh",
        "find": "      PenStackSync(name, false);   // P-DRAW-74c: ...and the line's rows with it\r\n",
        "replace": "      // MUTATION: the open converge leaves the rows stale\r\n",
        "expect": "P-DRAW-74c",
    },
    {
        "id": "P-DRAW-74c-m",
        "gate": "regression",
        "rule": "the drag/change event reaches the rows",
        "what": "the event never reaches the rows - a line's stack trails the hand's own event",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "      PenStackSync(sparam, false);   // P-DRAW-74c: and the line's rows ride it too\r\n",
        "replace": "      // MUTATION: the drag event never reaches the rows\r\n",
        "expect": "P-DRAW-74c",
    },
    {
        "id": "P-DRAW-74c-n",
        "gate": "regression",
        "rule": "the drag event arms the line pen",
        "what": "the drag event arms no pen - the chase never runs and the rows stand frozen through the motion",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "         PenStackDragArm(sparam);   // P-DRAW-74c: the same hand names both pens\r\n",
        "replace": "         // MUTATION: the drag event arms no pen\r\n",
        "expect": "P-DRAW-74c",
    },
    {
        "id": "P-DRAW-74c-o",
        "gate": "regression",
        "rule": "the move-stream trip arms the line pen (the fast flick)",
        "what": "the trip never arms the line pen - a fast flick freezes the rows through the whole motion and snaps at the release",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "            PenStackDragArm(armAsk);   // P-DRAW-74c: the same trip names the line pen\r\n",
        "replace": "            // MUTATION: the trip names no line pen\r\n",
        "expect": "P-DRAW-74c",
    },
    {
        "id": "P-DRAW-74c-p",
        "gate": "regression",
        "rule": "the move stream chases the rows, not the drag event",
        "what": "moves never chase - the follow belongs on the mouse stream, not the terminal's 1-2 Hz drag event",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "         if(tleft) PenStackDragFollow((int)lparam, (int)dparam);   // P-DRAW-74c: the rows ride the hand too\r\n",
        "replace": "         // MUTATION: the rows never chase the hand\r\n",
        "expect": "P-DRAW-74c",
    },
    {
        "id": "P-DRAW-74c-q",
        "gate": "regression",
        "rule": "the button-up door ends the line preview",
        "what": "the off-chart release has no door - the preview stays armed until the next gesture",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "            if(PenStackPreviewEnd()) ChartRedraw();\r\n",
        "replace": "            // MUTATION: the button-up door ends no line preview\r\n",
        "expect": "P-DRAW-74c",
    },
    {
        "id": "P-DRAW-74c-r",
        "gate": "regression",
        "rule": "the click door ends the line preview",
        "what": "the click door never ends the line preview - the rows stay hidden until an unrelated repaint",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "         if(PenStackPreviewEnd()) fbPrev = true;   // P-DRAW-74c: the same law, the line pen\r\n",
        "replace": "         // MUTATION: the click door ends no line preview\r\n",
        "expect": "P-DRAW-74c",
    },
    {
        "id": "P-DRAW-74c-s",
        "gate": "regression",
        "rule": "the release re-states the rows on the final seat",
        "what": "the release never re-states the rows - the stack converges one frame behind the terminal's own final blit",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "            PenStackSync(relPressObj, false);   // P-DRAW-74c: ...and the line's rows on the final seat\r\n",
        "replace": "            // MUTATION: the release leaves the rows off their final seat\r\n",
        "expect": "P-DRAW-74c",
    },
    {
        "id": "P-DRAW-74c-t",
        "gate": "regression",
        "rule": "both release doors disarm the pen",
        "what": "a release door forgot its disarm - the next gesture inherits a stale chase",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "            FibPenDragDisarm();   // P-DRAGF: the gesture is over, the chase stands down\r\n            PenStackDragDisarm();\r\n",
        "replace": "            FibPenDragDisarm();   // MUTATION: the line pen stays armed\r\n",
        "expect": "P-DRAW-74c",
    },
    {
        "id": "P-DRAW-74c-u",
        "gate": "regression",
        "rule": "a native delete drops the rows with their line",
        "what": "a native delete strands the rows - every dependent must die with its object",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "         if(PenStackStraysDrop(sparam)) casc = true;   // P-DRAW-74c: the rows die with the line\r\n",
        "replace": "         // MUTATION: the rows survive their line\r\n",
        "expect": "P-DRAW-74c",
    },
    {
        "id": "P-DRAW-74c-v",
        "gate": "regression",
        "rule": "a zoom re-syncs the served line",
        "what": "a zoom never re-syncs the served line - the pixel ring goes stale until the next touch",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "      if(id == CHARTEVENT_CHART_CHANGE) PenStackSync(s_dsObj, false);   // P-DRAW-74c: the rows' ring re-measures with it\r\n",
        "replace": "      // MUTATION: the zoom never re-measures the served line\r\n",
        "expect": "P-DRAW-74c",
    },
    {
        "id": "P-DRAW-74c-w",
        "gate": "regression",
        "rule": "the 2 s heal is the net for a master the terminal moves silently",
        "what": "the pen has no net - a master the terminal moved with no event keeps a stale pen until the next touch",
        "file": "Biotak/DrawStrip_Pick.mqh",
        "find": "      if(PenStackServesType(ty)) PenStackHeal(nm);",
        "replace": "      // MUTATION: the pen has no net",
        "expect": "P-DRAW-74c",
    },
    {
        "id": "P-DRAW-74c-x",
        "gate": "regression",
        "rule": "a row whose master is gone is dropped (the parent oracle)",
        "what": "the rows have no parent oracle - a row whose master is gone survives a reattach",
        "file": "Biotak/DrawStrip_Pick.mqh",
        "find": "      if(PenStackIsChild(nm))\r\n",
        "replace": "      // MUTATION: a row whose master is gone survives\r\n",
        "expect": "P-DRAW-74c",
    },
    {
        "id": "P-DRAW-74c-y",
        "gate": "regression",
        "rule": "a duplicate copies the LOGICAL width, not the demoted 1",
        "what": "a duplicate copies the demoted 1 - the clone of a 3 px line shrinks to a dash",
        "file": "Biotak/DrawStrip_Tap.mqh",
        "find": "   if(duW <= DRAW_WIDTH_MIN && ObjectFind(0, PenStackName(s_dsObj, 0)) >= 0)\r\n      duW = PenStackLogicalWidth(s_dsObj);\r\n",
        "replace": "   // MUTATION: the clone copies the demoted 1\r\n",
        "expect": "P-DRAW-74c",
    },
    {
        "id": "P-DRAW-74c-z",
        "gate": "regression",
        "rule": "the clone re-forms beside itself, stacked, before the open's converge",
        "what": "the copy is born un-stacked - it shows one frame as a bare 1 px dash",
        "file": "Biotak/DrawStrip_Tap.mqh",
        "find": "   PenStackSync(nm, false);\r\n",
        "replace": "   // MUTATION: the copy is born un-stacked\r\n",
        "expect": "P-DRAW-74c",
    },
    {
        "id": "P-DRAW-74c-aa",
        "gate": "regression",
        "rule": "the sweep door drops the rows of every swept line",
        "what": "a swept line's rows survive the strip bin",
        "file": "Biotak/DrawStrip_Tap.mqh",
        "find": "      PenStackSync(DrawSelAt(j), true);   // P-DRAW-74c: the rows die with the line\r\n",
        "replace": "      // MUTATION: the swept line's rows survive\r\n",
        "expect": "P-DRAW-74c",
    },
    {
        "id": "P-DRAW-74c-ab",
        "gate": "regression",
        "rule": "the single-delete door drops the rows too",
        "what": "the held line's rows survive its delete - a styled pen on nothing",
        "file": "Biotak/DrawStrip_Tap.mqh",
        "find": "FibPenSync(s_dsObj, true); PenStackSync(s_dsObj, true); BoxMidDrop(s_dsObj);",
        "replace": "FibPenSync(s_dsObj, true); BoxMidDrop(s_dsObj);",
        "expect": "P-DRAW-74c",
    },
    #--- P-DRAGF4 (2026-10-17) - THE BOX'S INTERIOR RIDES THE TERMINAL. The interior
    #--- (`_FL` child) and the 50 % mid are followers re-seated by US from the event
    #--- stream, so they are always one frame behind the dragged master - the fibo's
    #--- lag law (P-DRAGF3), one family over. The master takes the interior back for
    #--- the gesture; the two syncs stand down; the release re-seats in one pass.
    #--- Each inverse must fail 58 naming P-DRAGF4.
    {
        "id": "P-DRAGF4-a",
        "gate": "regression",
        "rule": "the module is a member of the toolbar unit",
        "what": "BoxPreview.mqh joins no compiling unit - every arm/end call is dead code and the child lag survives",
        "file": "Biotak/DrawToolbar.mqh",
        "find": "#include \"BoxPreview.mqh\"   // P-DRAGF4: the box family's interior rides the terminal mid-gesture\n",
        "replace": "// MUTATION: the box preview's module is not included\n",
        "expect": "P-DRAGF4",
    },
    {
        "id": "P-DRAGF4-b",
        "gate": "regression",
        "rule": "the preview has an owner entry point",
        "what": "the arm entry point is gone - nothing can open the gesture",
        "file": "Biotak/BoxPreview.mqh",
        "find": "void BoxPreviewArm(const string obj)\r\n",
        "replace": "void BoxPreviewArmX(const string obj)   // MUTATION: the entry point is renamed away\r\n",
        "expect": "P-DRAGF4",
    },
    {
        "id": "P-DRAGF4-c",
        "gate": "regression",
        "rule": "the interior's hand-sync stands down while the preview owns the name",
        "what": "two writers re-seat one child - the hand-sync fights the preview every frame",
        "file": "Biotak/Toolbar_A.mqh",
        "find": "   if(BoxPreviewOwns(obj)) return false;   // P-DRAGF4: mid-gesture the master wears the interior natively\r\n",
        "replace": "   // MUTATION: the interior's hand-sync fights the preview\r\n",
        "expect": "P-DRAGF4",
    },
    {
        "id": "P-DRAGF4-d",
        "gate": "regression",
        "rule": "the mid's sync stands down while the preview owns the name",
        "what": "the mid's sync fights the hidden mid and re-seats it mid-gesture",
        "file": "Biotak/DrawStrip_Pick.mqh",
        "find": "   if(BoxPreviewOwns(box)) return false;   // P-DRAGF4: mid-gesture the mid is hidden; the end re-seats it\r\n",
        "replace": "   // MUTATION: the mid's sync fights the preview\r\n",
        "expect": "P-DRAGF4",
    },
    {
        "id": "P-DRAGF4-e",
        "gate": "regression",
        "rule": "the arm keeps its family fence",
        "what": "any object may arm - a stranger's object gets a fill it never had",
        "file": "Biotak/BoxPreview.mqh",
        "find": "   if(obj == \"\" || !DrawTypeHasFillChild(DrawObjectType(obj))) return;\r\n",
        "replace": "   // MUTATION: any object may arm\r\n",
        "expect": "P-DRAGF4",
    },
    {
        "id": "P-DRAGF4-f",
        "gate": "regression",
        "rule": "the interior is handed back to the terminal (native FILL)",
        "what": "the interior is never handed over - the child lag survives the whole gesture",
        "file": "Biotak/BoxPreview.mqh",
        "find": "      ObjectSetInteger(0, obj, OBJPROP_FILL, true);\r\n",
        "replace": "      // MUTATION: the interior is never handed over\r\n",
        "expect": "P-DRAGF4",
    },
    {
        "id": "P-DRAGF4-g",
        "gate": "regression",
        "rule": "the native fill wears the child's own rendered ink (P-UI-175: the property MT4 paints a shape's fill with)",
        "what": "the native fill guesses its ink - the interior flickers to the wrong colour for the gesture",
        "file": "Biotak/BoxPreview.mqh",
        "find": "      ObjectSetInteger(0, obj, OBJPROP_COLOR, (color)ObjectGetInteger(0, fil, OBJPROP_COLOR));\r\n",
        "replace": "      ObjectSetInteger(0, obj, OBJPROP_COLOR, (color)ObjectGetInteger(0, obj, OBJPROP_COLOR));\r\n      // MUTATION: the native fill guesses its ink\r\n",
        "expect": "P-DRAGF4",
    },
    {
        "id": "P-DRAGF4-h",
        "gate": "regression",
        "rule": "the child hides during the gesture",
        "what": "the child is not hidden - two interiors paint at once",
        "file": "Biotak/BoxPreview.mqh",
        "find": "      ObjectSetInteger(0, fil, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);\r\n",
        "replace": "      // MUTATION: two interiors paint at once\r\n",
        "expect": "P-DRAGF4",
    },
    {
        "id": "P-DRAGF4-i",
        "gate": "regression",
        "rule": "the child comes back at the release",
        "what": "the child never comes back - the box loses its interior for good",
        "file": "Biotak/BoxPreview.mqh",
        "find": "      ObjectSetInteger(0, fil, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);\r\n",
        "replace": "      // MUTATION: the child never comes back\r\n",
        "expect": "P-DRAGF4",
    },
    {
        "id": "P-DRAGF4-j",
        "gate": "regression",
        "rule": "the release re-seats the interior on the final seat",
        "what": "the interior is never re-seated - it returns at the seat it held when the gesture began",
        "file": "Biotak/BoxPreview.mqh",
        "find": "   FillChildSync(master);   // re-seat the interior on the FINAL station, one pass\r\n",
        "replace": "   // MUTATION: the interior is never re-seated\r\n",
        "expect": "P-DRAGF4",
    },
    {
        "id": "P-DRAGF4-k",
        "gate": "regression",
        "rule": "the release re-seats the 50 % mid too",
        "what": "the mid is never re-seated - it returns at the seat it held when the gesture began",
        "file": "Biotak/BoxPreview.mqh",
        "find": "   BoxMidSync(master);      // and the 50 % mid with it (Full only: its owner lives in the strip; Lite ships no mid)\r\n",
        "replace": "   // MUTATION: the mid is never re-seated\r\n",
        "expect": "P-DRAGF4",
    },
    {
        "id": "P-DRAGF4-l",
        "gate": "regression",
        "rule": "the preview leaves a flushed witness on both edges",
        "what": "the preview writes no witness - «یک فریم عقب» is unprovable without its numbers",
        "file": "Biotak/BoxPreview.mqh",
        "find": "\"[drawstrip] BOXPRE view=on obj=",
        "replace": "\"[drawstrip] BOXON obj=",
        "expect": "P-DRAGF4",
    },
    {
        "id": "P-DRAGF4-m",
        "gate": "regression",
        "rule": "the drag event arms the box preview",
        "what": "the drag event arms nothing - the interior lags from the first named drag",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "         BoxPreviewArm(sparam);   // P-DRAGF4: and the box family's interior goes native\r\n",
        "replace": "         // MUTATION: the drag event arms no box preview\r\n",
        "expect": "P-DRAGF4",
    },
    {
        "id": "P-DRAGF4-n",
        "gate": "regression",
        "rule": "the move-stream trip arms the box preview",
        "what": "the trip arms nothing - a fast flick keeps the interior lag through the whole motion",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "            BoxPreviewArm(armAsk);   // P-DRAGF4: and hands the box's interior to the terminal\r\n",
        "replace": "            // MUTATION: the trip arms no box preview\r\n",
        "expect": "P-DRAGF4",
    },
    {
        "id": "P-DRAGF4-o",
        "gate": "regression",
        "rule": "the button-up door ends the box preview",
        "what": "the off-chart release has no door - the box stays native with a hidden interior",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "            if(BoxPreviewEnd()) ChartRedraw();   // P-DRAGF4: the interior returns on the final seat\r\n",
        "replace": "            // MUTATION: the button-up door ends no box preview\r\n",
        "expect": "P-DRAGF4",
    },
    {
        "id": "P-DRAGF4-p",
        "gate": "regression",
        "rule": "the click door ends the box preview",
        "what": "the click door never ends the box preview - the interior stays hidden until an unrelated repaint",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "         if(BoxPreviewEnd()) fbPrev = true;   // P-DRAGF4: and the box's interior goes back\r\n",
        "replace": "         // MUTATION: the click door ends no box preview\r\n",
        "expect": "P-DRAGF4",
    },
    {
        "id": "P-DRAGF4-q",
        "gate": "regression",
        "rule": "the trip asks the terminal's own selection (the press that named nothing)",
        "what": "the fallback probe is gone - a fast flick that grabbed by the edge names nothing and loses the arm",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "            if(armAsk == \"\") armAsk = DrawSelectedObjectAt(tmx, tmy);\r\n",
        "replace": "            // MUTATION: the trip never asks the terminal's selection\r\n",
        "expect": "P-DRAGF4",
    },
    #--- P-DRAW-75 — AN UNCHOSEN COLOUR IS NEVER WRITTEN. s_dkValid is set by
    #--- any slot write while s_dkColor stays clrNONE until a colour is picked:
    #--- the create path then paints every fresh drawing white, anchors alone.
    {
        "id": "P-DRAW-75",
        "gate": "regression",
        "rule": "the create path never writes a colour nobody chose",
        "what": "the create path writes clrNONE onto fresh drawings again",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "    if((DrawKindCaps(k) & DRAW_CAP_COLOR) != 0 && (int)want >= 0)\r\n",
        "replace": "    if((DrawKindCaps(k) & DRAW_CAP_COLOR) != 0)\r\n",
        "expect": "P-DRAW-75",
    },
    #--- P-DRAW-09b-RETIRED — THE STRIP SERVES ONE OBJECT. The selection walk in
    #--- `DrawSelSnapshot` made one old Ctrl+click a standing instruction that every
    #--- later tap lands on every drawing of the kind («رنگ يک شو عوض کنم روي ديگر
    #--- هم اعمال ميشه»). Putting the walk back is the defect, whole.
    {
        "id": "P-DRAW-09b-retired",
        "gate": "regression",
        "rule": "the strip serves one object: no selection walk in the served set",
        "what": "the snapshot walks the chart and collects the selected drawings of the kind again",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "   s_dkSel[0] = hold;\r\n   s_dkSelN = 1;\r\n   return s_dkSelN;\r\n",
        "replace": "   s_dkSel[0] = hold;\r\n   s_dkSelN = 1;\r\n   int total = ObjectsTotal(0, -1, -1);\r\n   for(int i = total - 1; i >= 0 && s_dkSelN < DRAW_SEL_MAX; i--)\r\n   {\r\n      string nm = ObjectName(0, i, -1, -1);\r\n      if(nm == \"\" || nm == hold) continue;\r\n      if(DrawIsIndicatorObject(nm) && !DrawIsHRay(nm) && !DrawIsPathSeg(nm)) continue;\r\n      if(DrawKindOf(nm) != k) continue;\r\n      if(!(bool)ObjectGetInteger(0, nm, OBJPROP_SELECTED)) continue;\r\n      s_dkSel[s_dkSelN] = nm;\r\n      s_dkSelN++;\r\n   }\r\n   return s_dkSelN;\r\n",
        "expect": "P-DRAW-09b-RETIRED",
    },
    #--- P-SIZE-SPLIT — THE HALF GOES BELOW ITS CALLER. MQL4 resolves a call
    #--- top-down, so the hub's ORDER is not cosmetic: put the custom price
    #--- half under Init and the build stops with `error 168` while the rule it
    #--- was split for (one file, one owner, under the ceiling) reads fine.
    {
        "id": "P-SIZE-SPLIT",
        "gate": "regression",
        "rule": "a split half stays a member of the unit, included above the file that calls it",
        "what": "the custom price half is included BELOW Init (the call resolves downward)",
        "file": "Biotak/EventHandlers.mqh",
        "find": "#include \"EventHandlers_CustomPrice.mqh\"      // the custom price line (was the tail of Init)\r\n#include \"EventHandlers_Init.mqh\"\r\n",
        "replace": "#include \"EventHandlers_Init.mqh\"\r\n#include \"EventHandlers_CustomPrice.mqh\"      // MUTATION: the half below its caller\r\n",
        "expect": "P-SIZE-SPLIT",
    },
    #--- P-DRAW-09c-a — THE LOOK IS WRITTEN. «همیشه آخرین تغییرات روی ابجکت
    #--- پیش‌فرض بشه و هر سری نیاز نباشه تنظیم بکن» — with the row gone the look
    #--- survives the session and dies at the attach, which IS the ask.
    {
        "id": "P-DRAW-09c-a",
        "gate": "regression",
        "rule": "the save writes one last-look row per kind the user has styled",
        "what": "the last-look rows are never written (the look dies at the attach)",
        "file": "Biotak/Toolbar_Tpl.mqh",
        "find": "      FileWrite(h, (int)k, DRAW_LASTLOOK_SLOT, \"\",\r\n                DoubleToString(DrawStylePackA(k), 0), DoubleToString(DrawStylePackB(k), 0));\r\n",
        "replace": "      // MUTATION: the last look is never written\r\n",
        "expect": "P-DRAW-09c",
    },
    #--- P-DRAW-09c-b — THE LOOK IS READ BACK. The write half is useless without
    #--- the read half, and the reserved slot must be answered BEFORE the preset
    #--- bands reject it.
    {
        "id": "P-DRAW-09c-b",
        "gate": "regression",
        "rule": "the load restores the reserved last-look slot into the kind memory",
        "what": "the last-look row is read and thrown away (a row no reader accepts)",
        "file": "Biotak/Toolbar_Tpl.mqh",
        "find": "      if(i == DRAW_LASTLOOK_SLOT) { DrawStyleUnpack(k, StringToDouble(pa), StringToDouble(pb)); continue; }\r\n",
        "replace": "      // MUTATION: the last look is read and thrown away\r\n",
        "expect": "P-DRAW-09c",
    },
    #--- P-DRAW-09c-c — THE WRITER PERSISTS WHAT IT LEARNED. One write per user
    #--- act, from the same tail that sets `s_dkValid[k]`: a look learned and not
    #--- saved is the exact sentence the entry is about. (The anchor moved under
    #--- P-DRAW-130's `if(remember)` block — the write is the same write.)
    {
        "id": "P-DRAW-09c-c",
        "gate": "regression",
        "rule": "the ONE slot writer persists the look it just learned",
        "what": "learning stops saving (the look is remembered until the next attach and no further)",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "      if(s_dkTplHold <= 0) DrawTplSave();\r\n   }\r\n   return true;\r\n}\r\n\r\n//--- THE STYLE THE USER LAST USED FOR THIS KIND",
        "replace": "      // MUTATION: learning stops saving (the reported defect)\r\n   }\r\n   return true;\r\n}\r\n\r\n//--- THE STYLE THE USER LAST USED FOR THIS KIND",
        "expect": "P-DRAW-09c",
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
        "file": "Biotak/Toolbar_Tpl.mqh",
        "find": "   v += ((long)(((int)s_dkColor[k] >= 0) ? 1 : 0) << 33);\r\n",
        "replace": "   // MUTATION: the presence bit is gone\r\n",
        "expect": "P-DRAW-INK",
    },
    #--- P-DRAW-INK-b — AND THE OTHER HALF BELIEVES IT. A pack that says "no colour"
    #--- read by an unpack that reads the mask anyway is white again.
    {
        "id": "P-DRAW-INK-b",
        "gate": "regression",
        "rule": "the unpack answers clrNONE when the row carries no colour",
        "what": "the unpack reads the masked field as a colour (a kind that never had one comes back white)",
        "file": "Biotak/Toolbar_Tpl.mqh",
        "find": "   s_dkColor[k] = (((((a >> 33) & 0x1) != 0)) ? (color)(int)(a & 0xFFFFFF) : clrNONE);\r\n",
        "replace": "   s_dkColor[k] = (color)(int)(a & 0xFFFFFF);   // MUTATION: the presence bit is ignored\r\n",
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
        "find": "    if((int)want < 0) want = s_dkAnyClr;\r\n",
        "replace": "    // MUTATION: no fallback (the white default comes back)\r\n",
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
        "find": "         if((int)c >= 0) s_dkAnyClr = c;\r\n",
        "replace": "         // MUTATION: the last ink is never noted\r\n",
        "expect": "P-DRAW-INK",
    },
    #--- P-DRAW-INK-e — AND IT SURVIVES THE ATTACH. The row is what makes the fallback
    #--- true on the first drawing of the next session.
    {
        "id": "P-DRAW-INK-e",
        "gate": "regression",
        "rule": "the shared ink is written to the presets' own file",
        "what": "the shared ink is never written (the next attach starts on the terminal default)",
        "file": "Biotak/Toolbar_Tpl.mqh",
        "find": "   if((int)s_dkAnyClr >= 0)\r\n      FileWrite(h, 1, DRAW_LASTINK_SLOT, IntegerToString((int)s_dkAnyClr), \"0\", \"0\");\r\n",
        "replace": "   // MUTATION: the shared ink is never written\r\n",
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
        "find": "         string par = FibPenChildParent(nm);\r\n         if(par == \"\" || ObjectFind(0, par) < 0) DrawOrphanDrop(nm, par);   // P-ORPHAN-ALL\r\n",
        "replace": "         string par = FibPenChildParent(nm);\r\n         if(par == \"\" || ObjectFind(0, par) < 0) ObjectDelete(0, nm);\r\n",
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
        "find": "      if(BoxIsMidChild(nm))\r\n      {\r\n         string par = BoxMidParent(nm);\r\n         if(par == \"\" || ObjectFind(0, par) < 0) DrawOrphanDrop(nm, par);   // P-ORPHAN-ALL\r\n         continue;\r\n      }\r\n",
        "replace": "      // MUTATION: the 50 % line's orphan rule is gone\r\n",
        "expect": "P-ORPHAN-ALL",
    },
    #--- P-ORPHAN-ALL-c — THE LINE PEN'S ROWS, THE SAME RULE. The 74c family joined the
    #--- pump after this register was written; its orphan rule goes through the same one
    #--- deleter, or the silent drop the register exists against comes back one family
    #--- over. The gate's seat for each family is its OWN rule (P-ORPHAN-ALL-a's lesson),
    #--- so this inverse dies on the PenStack rule alone.
    {
        "id": "P-ORPHAN-ALL-c",
        "gate": "regression",
        "rule": "the line pen's rows are dropped when their master is gone (through the one deleter)",
        "what": "the line pen's orphan rule deletes silently again (no witness, no one deleter)",
        "file": "Biotak/DrawStrip_Pick.mqh",
        "find": "      if(PenStackIsChild(nm))\r\n      {\r\n         string par = PenStackChildParent(nm);\r\n         if(par == \"\" || ObjectFind(0, par) < 0) DrawOrphanDrop(nm, par);   // P-ORPHAN-ALL\r\n",
        "replace": "      if(PenStackIsChild(nm))\r\n      {\r\n         string par = PenStackChildParent(nm);\r\n         if(par == \"\" || ObjectFind(0, par) < 0) ObjectDelete(0, nm);\r\n",
        "expect": "P-ORPHAN-ALL",
    },

#--- P-SIM-* (2026-10-04) — THE SCENARIOS, RUN OFFLINE. Every report about this drawing
    #--- was a scenario answered from a screenshot («استایل ها روی ضخامت های بزرگ»,
    #--- «چرا امتداد خط ها استایل اعمال نشده», «عقب و جلو میره»). `tools/pen-sim.py` extracts
    #--- the rules from `Biotak/FibPen.mqh` AS WRITTEN and runs the whole matrix, so these
    #--- four mutations put the defect back in the SOURCE and the sim must die on it.
    {
        "id": "P-SIM-RAY-a",
        "gate": "pen",
        "rule": "the pen runs the full width forward, the span MT4 gives a fibo's levels",
        "what": "the right-hand span goes back out (the pen stops at the second anchor)",
        "file": "Biotak/FibPen.mqh",
        "find": "   rr = true;    // P-LOOK-RAY5: ...and the forward one \u2014 full width, both anchor orders",
        "replace": "   rr = false;   // MUTATION: the pen stops at the anchors",
        "expect": "P-SIM-RAY",
    },
    {
        "id": "P-SIM-RAY-b",
        "gate": "pen",
        "rule": "the pen's span is not read off a property that is not the level ray",
        "what": "the pen reads OBJPROP_RAY_* off the fibo again",
        "file": "Biotak/FibPen.mqh",
        "find": "   rl = true;    // P-LOOK-RAY5: the backward extension wears the style too",
        "replace": "   rl = ((int)ObjectGetInteger(0, fibo, OBJPROP_RAY_LEFT) != 0);   // MUTATION\r\n",
        "expect": "P-SIM-RAY",
    },
    {
        "id": "P-SIM-SPAN-a",
        "gate": "pen",
        "rule": "the rows wear ordered time on both movers",
        "what": "the sync seats rows in the master's own order again (reversed anchors lose an extension)",
        "file": "Biotak/FibPen.mqh",
        "find": "    datetime tb = (datetime)ObjectGetInteger(0, fibo, OBJPROP_TIME, 1);\r\n"
                "    datetime ts0 = (ta < tb ? ta : tb);",
        "replace": "    datetime tb = (datetime)ObjectGetInteger(0, fibo, OBJPROP_TIME, 1);\r\n"
                   "    datetime ts0 = (ta < tb ? tb : ta);   // MUTATION: rows wear the reversed order again",
        "expect": "P-SIM-RAY",
    },
    {
        "id": "P-SIM-74b-a",
        "gate": "pen",
        "rule": "a styled level builds exactly one row per pixel of thickness it lost",
        "what": "the row count loses a row (the pen is thinner than the width the hand chose)",
        "file": "Biotak/FibPen.mqh",
        "find": "         want = (refSt != (int)STYLE_SOLID && refLog > DRAW_WIDTH_MIN) ? refLog - 1 : 0;",
        "replace": "         want = (refSt != (int)STYLE_SOLID && refLog > DRAW_WIDTH_MIN) ? refLog - 2 : 0;   // MUTATION",
        "expect": "P-SIM-74b",
    },
    {
        "id": "P-SIM-SRC-a",
        "gate": "pen",
        "rule": "the chase re-seats its snapshot on every terminal landing",
        "what": "the landing resync goes out (a hand that goes back and forth drifts the pen)",
        "file": "Biotak/FibPen.mqh",
        "find": "   if(p1 != s_fibProbeP[0] || p2 != s_fibProbeP[1] || t1 != s_fibProbeT[0] || t2 != s_fibProbeT[1])\r\n",
        "replace": "   if(false)   // MUTATION: no landing resync\r\n",
        "expect": "P-SIM-SRC",
    },
    {
        "id": "P-BK-105-a",
        "gate": "regression",
        "rule": "a closed knot's step is the knot's own TH, read at the knot's own bar",
        "what": "the node read stops reading the anchored row (the step goes back to the live chart-TF one)",
        "file": "Biotak/BaseKnot_Nodes.mqh",
        "find": "    BaseKnotStepRow(nodeTimeMin, nd.anchor, nd.stepTH);",
        "replace": "    // MUTATION: the anchored step read is gone",
        "expect": "P-BK-105",
    },
    {
        "id": "P-BK-105-b",
        "gate": "regression",
        "rule": "the hover names the TF the step was measured on",
        "what": "the hover quotes the chart TF beside the node's own step",
        "file": "Biotak/BaseKnot_Nodes.mqh",
        "find": "      t += \"\\n      step (TH \" + BaseKnotTFHuman(nd.nodeTF) + \", at the box' own bar) = \" + DoubleToString(BaseKnotToPips(nd.stepTH), 1) + \" pips\";",
        "replace": "      t += \"\\n      step (TH \" + BaseKnotTFHuman(Period()) + \", at the box' own bar) = \" + DoubleToString(BaseKnotToPips(nd.stepTH), 1) + \" pips\";   // MUTATION",
        "expect": "P-BK-105",
    },
    {
        "id": "P-BK-111-a",
        "gate": "regression",
        "rule": "the price follow yields to the user's own call on the side",
        "what": "the lock gate is gone - the cell paints, hits, answers and the next 500 ms pump reads it back off",
        "file": "Biotak/BaseKnot_Measure.mqh",
        "find": "   if(g_bkBoxes[k].dirLock != 0) return false;",
        "replace": "   // MUTATION: the follow no longer yields to the user's side",
        "expect": "P-BK-111",
    },
    {
        "id": "P-BK-111-f",
        "gate": "regression",
        "rule": "EVERY writer of the side yields to the user's call - the price follow AND the break's story",
        "what": "the story's write loses the lock gate again - Sync runs on the very call the flip makes, so the rebuild takes the side straight back (measured: now=SELL read=BUY)",
        "file": "Biotak/BaseKnot_Plan.mqh",
        "find": "   if(ndDir != 0 && ndDir != dir && g_bkBoxes[k].dirLock == 0)",
        "replace": "   if(ndDir != 0 && ndDir != dir)   // MUTATION: the story overwrites the user's side",
        "expect": "P-BK-111",
    },
    {
        "id": "P-BK-111-b",
        "gate": "regression",
        "rule": "the direction cell is a counted seat in the draw-strip's command group",
        "what": "the seat is defined but left outside the count - the layout never reserves it and no tap reaches it",
        "file": "Biotak/DrawStrip_Head.mqh",
        "find": "#define DSTRIP_ACT_DIR 3\r\n#define DSTRIP_ACT_DEL 4\r\n#define DSTRIP_ACT_N 5",
        "replace": "#define DSTRIP_ACT_DIR 3\r\n#define DSTRIP_ACT_DEL 4\r\n#define DSTRIP_ACT_N 4   // MUTATION: the direction seat is outside its own count",
        "expect": "P-BK-111",
    },
    {
        "id": "P-BK-111-c",
        "gate": "regression",
        "rule": "the served drawing is checked before the side is touched",
        "what": "the tap stops asking what the strip serves - a press on a fib would reach the knot layer with no box to answer for",
        "file": "Biotak/DrawStrip_Tap.mqh",
        "find": "      string id = BaseKnotDirBoxFor(s_dsObj);",
        "replace": "      string id = \"\";   // MUTATION: never asks what the strip serves",
        "expect": "P-BK-111",
    },
    {
        "id": "P-BK-111-d",
        "gate": "regression",
        "rule": "the flip is witnessed on the flushed channel, with a read-back",
        "what": "the read-back is gone - the line would report the write and never whether the chart agreed",
        "file": "Biotak/BaseKnot_Witness.mqh",
        "find": '                        " read=" + (k < 0 ? "gone" : (g_bkBoxes[k].dir >= 0 ? "BUY" : "SELL")) +',
        "replace": '                        " read=" + (k < 0 ? "gone" : (now >= 0 ? "BUY" : "SELL")) +   // MUTATION: reads back the write',
        "expect": "P-BK-111",
    },
    {
        "id": "P-BK-111-e",
        "gate": "regression",
        "rule": "the control lives on ONE surface (the draw-strip the hand is holding)",
        "what": "a second direction cell is added to the Base Box mini-strip - two places to learn and two that can disagree about which box is meant",
        "file": "Biotak/BiotakPanels_Rows.mqh",
        "find": '      case 5:  return "TBlock";     // padlock (held box)',
        "replace": '      case 5:  return "TBdir";      // MUTATION: a second direction cell on the mini-strip\n      case 6:  return "TBlock";     // padlock (held box)',
        "expect": "P-BK-111",
    },
    {
        "id": "P-BK-111-g",
        "gate": "regression",
        "rule": "the page mock answers the same act count as the strip",
        "what": "the mock's act faces go back to four while DSTRIP_ACT_N is five - the page rebuild dies with an IndexError at the end of every -Shot run (measured 2026-10-18, sim-strip-panels.py:539)",
        "file": "tools/sim-strip-panels.py",
        "find": "DEMO_ACT = [\"bk_more.bmp\", \"bk_gear.bmp\", \"gl_pin_m.bmp\", \"bk_dirflip.bmp\", \"bk_del.bmp\"]",
        "replace": "DEMO_ACT = [\"bk_more.bmp\", \"bk_gear.bmp\", \"gl_pin_m.bmp\", \"bk_del.bmp\"]   # MUTATION: four faces against five seats",
        "expect": "P-BK-111",
    },

    #--- P-UI-144 (2026-10-13) — THE GHOST SWEEP IS CALLED. Measured defect:
    #--- profiles/default/chart03.chr carried `BiotakMenuV2_134342075006101685_CircOrbBg`
    #--- at x=70,y=79 — a previous session's name restored at stale absolute pixels.
    #--- The definition alone is prose; the init path must run it (P-DRAW-120's law).
    {
        "id": "P-UI-144",
        "gate": "regression",
        "rule": "an attach sweeps every foreign chart-id spelling of the menu/panel family",
        "what": "InitializeUIStates stops calling the sweep - the owner exists and nobody runs it",
        "file": "Biotak/BiotakMenu_A.mqh",
        "find": "   BiotakMenuGhostSweep();",
        "replace": "   // MUTATION: the sweep is never called",
        "expect": "does not CALL the sweep",
    },
    #--- ...and it must cover the V2 spelling - the only one a live build writes.
    {
        "id": "P-UI-144b",
        "gate": "regression",
        "rule": "the sweep covers both spellings the family ever painted",
        "what": "the V2 walk is removed - a half sweep that leaves every live name's ghosts behind",
        "file": "Biotak/BiotakHomes.mqh",
        "find": '   ObjectsDeleteAll(0, "BiotakMenuV2_", -1, -1);   // V2 (the char after "BiotakMenu" is \'V\')',
        "replace": "   // MUTATION: the V2 walk removed",
        "expect": "the sweep lost the V2 spelling",
    },
    #--- P-UI-142b (2026-10-18) — THE TOOLS CHROME DOES NOT SURVIVE AN ATTACH. Measured:
    #--- the user's screenshot shows the tools page (light sub panel + a page of cells +
    #--- the orb) standing with no ring after a restart — the P-UI-142 snapshot re-floated
    #--- it and the ring stays suppressed behind it, so the menu reads as closed.
    {
        "id": "P-UI-142b",
        "gate": "regression",
        "rule": "the tools chrome starts shut at every attach — a literal, never the snapshot",
        "what": "LoadUIState restores the chrome from the snapshot again - an attach can float a tools page under a closed menu",
        "file": "Biotak/BiotakMenu_A.mqh",
        "find": "   g_ToolsOpen = false;   // P-UI-142b: shut every attach; the MEN snapshot still restores the ring",
        "replace": "   g_ToolsOpen = (GlobalVariableCheck(gvTools) && GlobalVariableGet(gvTools) > 0.5);   // MUTATION: the snapshot reopens the chrome",
        "expect": "no longer shuts the tools chrome with a literal false",
    },
    #--- P-UI-145 (2026-10-13) — THE SEAT IS REMEMBERED BY THE PAINT. Measured
    #--- defect: a selectable control is native-dragged by the terminal on the press
    #--- that lands on it (P-UI-48), so a shaky hand leaves the button off its seat -
    #--- and the displaced button then rides the chart profile into the next session.
    {
        "id": "P-UI-145",
        "gate": "regression",
        "rule": "the seat a control is painted at is remembered by the paint itself",
        "what": "PnlSetButton stops remembering the seat - the registry would be a second grid",
        "file": "Biotak/BiotakPanels_Apply.mqh",
        "find": "   PnlSeatRemember(n, x, y);",
        "replace": "   // MUTATION: the seat is not remembered",
        "expect": "PnlSetButton() no longer remembers the seat",
    },
    #--- ...and the revert must actually run on the terminal's own drag channel.
    {
        "id": "P-UI-145b",
        "gate": "regression",
        "rule": "a native drag of our own control is reverted in the same event",
        "what": "the OBJECT_DRAG branch stops reverting - the button stays where MT4 dragged it",
        "file": "Biotak/BiotakPanels_Life.mqh",
        "find": "         PnlSeatRevert(sparam);",
        "replace": "         // MUTATION: no revert",
        "expect": "the OBJECT_DRAG branch does not revert our own control",
    },
    #--- P-UI-146 (2026-10-13) — THE HOME NEVER STORES THE CLAMP. The exact defect
    #--- docs/th3-ui-placement.md still owed the strip: a shrunk window moved the
    #--- stored place inward for good (the P-UI-131e ratchet, said in fractions).
    {
        "id": "P-UI-146",
        "gate": "regression",
        "rule": "the home is the hand's place; the live pair is clamped, never stored",
        "what": "DrawStripHomeClamp writes the clamped pair back into the home again",
        "file": "Biotak/DrawStrip_Paint.mqh",
        "find": "   s_dsX = nx; s_dsY = ny;                  // the live pair follows; the home does not",
        "replace": "   s_dsHomeX = nx; s_dsHomeY = ny;\r\n   s_dsX = nx; s_dsY = ny;",
        "expect": "writes the clamped pair back into the home",
    },
    #--- ...and the restore must have its caller (an owner nobody calls is prose).
    {
        "id": "P-UI-146b",
        "gate": "regression",
        "rule": "the strip's saved state is restored once on a fresh attach",
        "what": "RefreshKitOnBar stops calling the restore - the strip reopens nothing",
        "file": "Biotak/BiotakPanels_Life.mqh",
        "find": "   DrawStripStateRestore();",
        "replace": "   // MUTATION: the restore is never called",
        "expect": "RefreshKitOnBar() does not call the restore",
    },

    #--- P-UI-146c (2026-10-22) — THE PIN MUST PRECEDE THE ONE PAINT PASS.
    {
        "id": "P-UI-146c",
        "gate": "regression",
        "rule": "the restored pin is written before the strip's only paint pass",
        "what": "the pin is written after DrawStripOpen - the first frame keeps the old pin",
        "file": "Biotak/BiotakPanels_Life.mqh",
        "find": "   const bool oldPin = s_dsPinned;\n   s_dsPinned = pin;\n   if(!DrawStripOpen(target))\n   {\n      s_dsPinned = oldPin;\n      tries++;\n      lastTry = nowMs;\n      return;\n   }",
        "replace": "   const bool oldPin = s_dsPinned;\n   if(!DrawStripOpen(target))\n   {\n      s_dsPinned = oldPin;\n      tries++;\n      lastTry = nowMs;\n      return;\n   }\n   s_dsPinned = pin;",
        "expect": "writes the restored pin after the open",
    },

    #--- P-UI-146d (2026-10-22) — A MISSED RESTORE IS RETRIED, BOUNDED.
    {
        "id": "P-UI-146d",
        "gate": "regression",
        "rule": "a restore that misses the drawing or fails the open retries, bounded (P-UI-146d)",
        "what": "a failed open latches the one-shot instead of retrying - the strip stays shut after a transient miss",
        "file": "Biotak/BiotakPanels_Life.mqh",
        "find": "      s_dsPinned = oldPin;\n      tries++;\n      lastTry = nowMs;\n      return;",
        "replace": "      s_dsPinned = oldPin;\n      done = true;\n      return;",
        "expect": "a failed open is not retried",
    },

    #--- P-UI-81b (2026-10-22) — A CLOSE REAPS THE GESTURE IT CLOSES OVER.
    {
        "id": "P-UI-81b",
        "gate": "regression",
        "rule": "closing a card reaps the gesture that owns its chart lock",
        "what": "PnlCloseAll stops reaping the live move/slider - the chart lock outlives the panel",
        "file": "Biotak/BiotakPanels_Hit.mqh",
        "find": "   BkFlushTextEdit();   // close = apply (TV Ok semantics)\n   PnlReapStaleGestures(false);\n",
        "replace": "   BkFlushTextEdit();   // close = apply (TV Ok semantics)\n   // MUTATION: the gesture is not reaped\n",
        "expect": "does not reap the live gesture",
    },

    #--- P-UI-81b-b (2026-10-22) — THE PRESS EDGE IS THE STALE GESTURE'S NET.
    {
        "id": "P-UI-81b-b",
        "gate": "regression",
        "rule": "a new press reaps a gesture whose release never arrived",
        "what": "the press edge stops reaping - a missed release bricks every card control",
        "file": "Biotak/BiotakPanels_Route.mqh",
        "find": "   if(pressStart && !s_PnlClickChannel) PnlReapStaleGestures(s_PnlMoveMoved);\n",
        "replace": "   // MUTATION: the press edge no longer reaps\n",
        "expect": "the press edge no longer reaps a stale gesture",
    },

    #--- P-UI-81c (2026-10-22) — A PALETTE CLOSE ENDS ITS OWN MIXER.
    {
        "id": "P-UI-81c",
        "gate": "regression",
        "rule": "a palette close ends the live mixer that owns its chart lock",
        "what": "PalClose stops ending the mixer - the popup dies and the chart stays modal",
        "file": "Biotak/BiotakPanels_PalA.mqh",
        "find": "    if(g_PalMixDrag > 0)\n    {\n       g_PalMixDrag = 0;\n       PalRefreshRecents(true);\n       DragReleaseIf(DRAG_PANEL_KNOB);\n       UIDragBudgetEnd();\n       CircUnlockChart();\n    }\n",
        "replace": "    // MUTATION: the live mixer is reset without its release path\n",
        "expect": "PalClose() resets the mixer without ending its chart-lock claim",
    },

    #--- P-SIZE-SPLIT-LBL (2026-10-13) — A HALF THE CEILING CUT OUT IS A MEMBER.
    #--- P-UI-148 needed a few lines in Labels_A.mqh, which sat at its grandfathered
    #--- baseline, so the countdown owner moved to Biotak/Labels_Countdown.mqh
    #--- (contract §7). The half can be present, compile and be DEAD — the hub must
    #--- include it, and the owner must still call into it.
    {
        "id": "P-SIZE-SPLIT-LBL",
        "gate": "regression",
        "rule": "a half the ceiling cut out is a MEMBER of the unit, and it is called",
        "what": "the label hub stops including its own half - Labels_Countdown.mqh is in nobody's unit",
        "file": "Biotak/LabelFunctions.mqh",
        "find": '#include "Labels_Countdown.mqh"   // P-UI-148: the countdown owner (after Labels_A: its helpers\' home)\n',
        "replace": "// MUTATION: the half is not included\n",
        "expect": "does not include its own half",
    },

    #--- P-UI-145c (2026-10-13) — A DEAD FAMILY HANDS ITS SLOT BACK. P-UI-145's seat
    #--- registry was bounded by `PNL_SEAT_MAX` and its counter only ever GREW:
    #--- `PnlSeatForget` blanked the name and kept the entry, so the ceiling bounded
    #--- every name ever PAINTED rather than the live controls. One 24-row card teaches
    #--- more than a hundred names, so two cards reached 192 and from then on every
    #--- later card and palette lost its revert with nothing said.
    {
        "id": "P-UI-145c",
        "gate": "regression",
        "rule": "a dead family hands its seats back to the registry",
        "what": "PnlSeatForget keeps the slot - the counter only grows and the registry dies silently",
        "file": "Biotak/BiotakPanels_Apply.mqh",
        "find": "   s_pnlSeatN = w;",
        "replace": "   // MUTATION: the counter keeps the dead slot",
        "expect": "no longer DECREMENTS the counter",
    },
    #--- ...and the popup must release its OWN, or the card teardown is the only
    #--- releaser in the tree and every palette open leaves ~44 entries dead forever.
    {
        "id": "P-UI-145d",
        "gate": "regression",
        "rule": "the palette releases the seats its own popup taught",
        "what": "PalClose stops forgetting the popup's seats - every open leaves them dead forever",
        "file": "Biotak/BiotakPanels_PalA.mqh",
        "find": '   PnlSeatForget(g_UI.btnPrefix+"Pal_");',
        "replace": "   // MUTATION: the popup keeps its seats",
        "expect": "PalClose() does not release the popup",
    },
    #--- P-UI-149 (2026-10-13) — A GATE NOBODY RUNS IS A RULE NOBODY KEEPS. Both tools
    #--- existed, both were correct in intent, and neither was in the build - so both
    #--- had gone blind unnoticed and their failures read as product defects.
    {
        "id": "P-UI-149",
        "gate": "regression",
        "rule": "the skin and parity gates are run by every build",
        "what": "the build stops running the skin metrics gate - a rule nobody runs",
        "file": "compile-th3.ps1",
        "find": '$skinGate = Join-Path $SCRIPT_ROOT "tools\\skin_metrics_check.js"',
        "replace": "# MUTATION: the skin gate is not run",
        "expect": "the build does not run",
    },
    #--- ...and a gate that cannot READ its input is not a gate: the parity audit
    #--- resolved the strip's deliberate aliases (`DSTRIP_GEAR_* = PNL_*`, P-DRAW-116)
    #--- nowhere, so five seats compared as `None` and an unmeasured seat prints
    #--- exactly like an agreeing one (the P-DRAW-120 class).
    {
        "id": "P-UI-149b",
        "gate": "regression",
        "rule": "the parity gate can resolve the strip's aliases into the cards' unit",
        "what": "the card fallback goes - five seats compare as None and print as agreeing",
        "file": "tools/ui_parity_audit.py",
        "find": "        val, _ = define(CARD, name)",
        "replace": "        val, _ = None, None   # MUTATION: the alias is not resolved",
        "expect": "cannot resolve the strip",
    },
    #--- P-BE-03 (2026-10-13) — DEAD CODE IS A DEFECT. `CalculateShortStep` had no
    #--- caller anywhere in the tree, and it carried the NAME of the SS factor while
    #--- the live path wrote the literal. Re-adding it must make the regression entry
    #--- say so; if it does not, the "no dead code" rule is a comment, not a gate.
    {
        "id": "P-BE-03",
        "gate": "regression",
        "rule": "the dead step functions stay deleted",
        "what": "`CalculateShortStep` is re-added — dead code is back and nothing notices",
        "file": "Biotak/THCalculations.mqh",
        "find": "double CalculateTH(const double price, const int digits, const double percentage) {",
        "replace": "double CalculateShortStep(const double thValue) { return thValue * SS_MULTIPLIER; }\ndouble CalculateTH(const double price, const int digits, const double percentage) {",
        "expect": "is back in THCalculations.mqh",
    },
    #--- P-BE-04 — ONE FACTOR, ONE OWNER. The live SS_LS_STEP path wrote `1.5` inline
    #--- while `SS_MULTIPLIER` (MathConstants.mqh) owned the number, so a retune
    #--- reached nothing. Putting the literal back must fail the gate.
    {
        "id": "P-BE-04",
        "gate": "regression",
        "rule": "the live SS factor reads its one owner",
        "what": "SS_LS_STEP goes back to a bare `1.5` — two owners for one factor",
        "file": "Biotak/Util_A.mqh",
        "find": "return structureValue * SS_MULTIPLIER;",
        "replace": "return structureValue * 1.5;   # MUTATION: the factor loses its owner",
        "expect": "no longer reads",
    },
    #--- P-UI-152 (2026-10-13) — THE MIXER'S TRACK, ONE OWNER. Four sites spelled the
    #--- same track out by hand. Sending ONE of them back to the literal must fail the
    #--- gate: it both re-adds a second owner and drops a reader below the four the
    #--- paint needs.
    {
        "id": "P-UI-152",
        "gate": "regression",
        "rule": "the mixer track has one owner",
        "what": "the mixer paint re-derives its own track — the press and the bed part company",
        "file": "Biotak/BiotakPanels_PalA.mqh",
        "find": "   int trackX=PalMixTrackX();",
        "replace": "   int trackX=px+PAL_PAD+30;   // MUTATION: a second owner",
        "expect": "is a literal again",
    },
    #--- P-UI-153 (2026-10-13) — THE GEAR CLOSE SEAT, ONE OWNER. Three sites wrote the
    #--- bare 26. Sending the hit test back to the literal must fail the gate.
    {
        "id": "P-UI-153",
        "gate": "regression",
        "rule": "the gear close seat has one owner",
        "what": "the gear hit test writes the bare 26 again — paint and probe can part company",
        "file": "Biotak/DrawStrip_Base.mqh",
        "find": "         const int xbtn = DSTRIP_GEAR_XW, xpad = 3;",
        "replace": "         const int xbtn = 26, xpad = 3;   // MUTATION: a third literal",
        "expect": "writes the bare",
    },
    #--- ...and the parity gate must compare NAME against NAME. A literal on the panel
    #--- side can only report drift after it has happened, so the row is the rule.
    {
        "id": "P-UI-153b",
        "gate": "regression",
        "rule": "the parity gate compares the close seat name-to-name",
        "what": "the close-seat row goes back to the literal \"26\" — a number against a name",
        "file": "tools/ui_parity_audit.py",
        "find": '"PNL_XBTN_VIS",               "DSTRIP_GEAR_XW",',
        "replace": '"PNL_XBTN_VIS",               "26",',
        "expect": "compares the close seat as a literal",
    },
    #--- ...and the define the whole seat hangs off must survive the splice that added
    #--- this rule: the first version of the P-UI-153 edit REPLACED the
    #--- `#define DSTRIP_GEAR_PAD` anchor instead of inserting after it, so the "side
    #--- pad" seat silently became `None`. Renaming it must fail the gate.
    {
        "id": "P-UI-153c",
        "gate": "regression",
        "rule": "DSTRIP_GEAR_PAD survives",
        "what": "`#define DSTRIP_GEAR_PAD` is renamed away — the parity gate's side-pad seat reads None",
        "file": "Biotak/DrawStrip_Head.mqh",
        "find": "#define DSTRIP_GEAR_PAD  PNL_PAD_X",
        "replace": "#define DSTRIP_GEAR_PADX PNL_PAD_X   // MUTATION: the anchor was eaten",
        "expect": "lost `#define DSTRIP_GEAR_PAD`",
    },
    #--- P-PERF-40 (2026-10-13) — THE CENSUS'S BOUND IS ON EVENTS, NEVER ON RATE.
    #--- MEASURED: 17,547 `[gest]` lines in one day (79% of the journal), 160 in one
    #--- second. One press re-armed three seconds of one flushed write per mouse-move.
    #--- Dropping the bound must fail the gate.
    {
        "id": "P-PERF-40",
        "gate": "regression",
        "rule": "the gesture census is rate-bounded",
        "what": "the rate bound is removed - every mouse-move inside the window prints a flushed line again",
        "file": "Biotak/GlobalVariables.mqh",
        "find": "   if(pressEdge || (now - g_gestCensusMs) >= GEST_CENSUS_MIN_MS)",
        "replace": "   if(pressEdge || true)   // MUTATION: the census is unbounded again",
        "expect": "rate bound is gone",
    },
    #--- ...and the bound must sit BELOW the discriminator: the terminal's own drag/create
    #--- IS the P-UI-142 answer, and a coalesced discriminator cannot answer it.
    {
        "id": "P-PERF-40b",
        "gate": "regression",
        "rule": "the drag/create edge is answered before any rate is considered",
        "what": "the drag/create edge is coalesced too - the order question loses its witness",
        "file": "Biotak/GlobalVariables.mqh",
        "find": "   if(id == CHARTEVENT_OBJECT_DRAG || id == CHARTEVENT_OBJECT_CREATE) return true;",
        "replace": "   if(id == CHARTEVENT_OBJECT_DRAG || id == CHARTEVENT_OBJECT_CREATE) return (GetTickCount() - g_gestCensusMs) >= GEST_CENSUS_MIN_MS;   // MUTATION: the edge is coalesced",
        "expect": "no longer answers the terminal",
    },
    #--- ...and the edge detector must be cleared by a refusal, or a stale `true` swallows
    #--- the next press - the one line the order question actually needs.
    {
        "id": "P-PERF-40c",
        "gate": "regression",
        "rule": "the census's edge detector is cleared by a refusal",
        "what": "the edge detector is never cleared - the next press is not an edge any more",
        "file": "Biotak/GlobalVariables.mqh",
        "find": "      g_gestCensusDown = false;   // a refusal ends the stroke, so the next press is an edge",
        "replace": "      // MUTATION: the edge detector is never cleared",
        "expect": "edge detector is never cleared",
    },
    #--- P-BUILD-12 (2026-10-13) - the deploy must check its own claim. MEASURED:
    #--- the build printed «Terminal restarted» while the journal held «stopped»
    #--- and no «started», and no terminal.exe existed - yet it exited 0.
    {
        "id": "P-BUILD-12",
        "gate": "regression",
        "rule": "the deploy looks for the relaunched process",
        "what": "the relaunch is never verified - a launch that never came up still exits 0",
        "file": "compile-th3.ps1",
        "find": "    if ($up -lt $want) {",
        "replace": "    if ($false) {   # MUTATION: the relaunch is never verified",
        "expect": "relaunch is never verified",
    },
    #--- ...and the failure must SAY it failed: a silent one is what let a stale ex4
    #--- pass for a landed deploy while every chart kept the previous binary.
    {
        "id": "P-BUILD-12b",
        "gate": "regression",
        "rule": "a failed relaunch names itself",
        "what": "the failed relaunch no longer says so - the honest line is gone",
        "file": "compile-th3.ps1",
        "find": "  [FAIL] the relaunch did not come up",
        "replace": "  [FAIL] relaunch problem",
        "expect": "no longer says so",
    },
    #--- P-UI-154 (2026-10-13) - the Hover Chip card rendered on the OPENING DEFAULTS
    #--- because `PnlSetDef` had a branch for every card except 4. MEASURED: the card
    #--- showed a nameless 0..100 slider where its one ON/OFF switch belongs.
    {
        "id": "P-UI-154",
        "gate": "regression",
        "rule": "every card has a branch in PnlSetDef",
        "what": "the Hover Chip card loses its row definition - it renders on the opening defaults again",
        "file": "Biotak/BiotakPanels_PalB.mqh",
        "find": "else if(item==4)   // HOVER CHIP",
        "replace": "else if(item==40)   // MUTATION: the chip's card has no definition",
        "expect": "have no branch in `PnlSetDef`",
    },
    #--- P-UI-156 (2026-10-13) - A READER WITH NO BOX DERIVES NOTHING. The reader used to
    #--- fall back to 1920x1080 when the terminal reported 0 for the chart box (which it
    #--- does at attach and during CHART_CHANGE). That fallback is a denominator the pixels
    #--- did not come from; the pair it produced was handed to the in-memory HOME and then
    #--- persisted against the REAL box. MEASURED and still in the store:
    #--- `BIOMENU_HOME_STRIP_FX` = 1.000000 exactly.
    {
        "id": "P-UI-156a",
        "gate": "regression",
        "rule": "the home reader refuses an unmeasured box",
        "what": "the reader invents a denominator again - it derives pixels from a box it never measured",
        "file": "Biotak/BiotakHomes.mqh",
        "find": "   if(!HomeChartSizeRaw(cw, ch)) { x = -1; y = -1; return false; }",
        "replace": "   if(!HomeChartSize(cw, ch)) { x = -1; y = -1; return false; }   // MUTATION: the poisoned denominator is back",
        "expect": "invents a denominator",
    },
    #--- ...and the WRITER must refuse a pair outside the box: the clamp used to saturate
    #--- it into the store, which is how `STRIP_FX` became a permanent 1.0.
    {
        "id": "P-UI-156b",
        "gate": "regression",
        "rule": "the home writer refuses a pair outside the box",
        "what": "a place outside the box is stored again - the clamp saturates it into the store",
        "file": "Biotak/BiotakHomes.mqh",
        "find": "   if(x > rcw || y > rch) return;",
        "replace": "   if(false) return;   // MUTATION: an out-of-box pair is written again",
        "expect": "a place outside the box is written again",
    },
    #--- P-UI-158 (2026-10-13) - ONLY THE HAND MOVES A HOME. The user asked for the RING's
    #--- method («پنل رینگ از چه روشی استفاده کرده مثل همون بشه»): the ring stores no place
    #--- of its own, so it cannot drift. The chip stored a fraction AND re-derived it on
    #--- every attach, so a derivation in one window was saved against another and the
    #--- fraction crept (MEASURED: CHIP_FX 0.942731 -> 0.618392, a 589 px jump). The
    #--- automatic door must refuse every write that no NEW ANSWER produced.
    {
        "id": "P-UI-158a",
        "gate": "regression",
        "rule": "the automatic door writes a home only for a pending answer",
        "what": "the automatic door writes without a claim - a derivation in one window is saved against another",
        "file": "Biotak/BiotakHomes.mqh",
        "find": "   if(!GVHomeAnswerTake(id)) return;",
        "replace": "   // MUTATION: the automatic door writes without a claim",
        "expect": "writes without a claim",
    },
    #--- ...and the HAND's door must make its own claim, or the user's own release would be
    #--- refused exactly like a derivation is.
    {
        "id": "P-UI-158b",
        "gate": "regression",
        "rule": "the hand's door claims the answer it publishes",
        "what": "the hand's door stops claiming - a release, a first placement and a migration are all refused",
        "file": "Biotak/BiotakHomes.mqh",
        "find": "   GVHomeAnswerNew(id);\r\n   GVHomeWriteFrac(id, x, y);",
        "replace": "   GVHomeWriteFrac(id, x, y);   // MUTATION: the hand's door makes no claim",
        "expect": "no longer makes its own claim",
    },
    #--- ...and a claim that reached no write must be SPENT, or it authorises a LATER save
    #--- (a resize, a TF switch, the teardown) to store a derived pair - the creep again.
    {
        "id": "P-UI-158c",
        "gate": "regression",
        "rule": "SaveUIStates spends a claim it did not honour",
        "what": "an unhonoured claim is left standing - the next automatic save stores a derived pair",
        "file": "Biotak/BiotakMenu_A.mqh",
        "find": "   if(haveBox) GVHomeAnswerClear();",
        "replace": "   ;   // MUTATION: an unhonoured claim is left standing",
        "expect": "no longer spends an unhonoured claim",
    },
    #--- ...and the CHIP's own drag must claim, or the store would refuse the hand's move.
    {
        "id": "P-UI-158d",
        "gate": "regression",
        "rule": "the chip drag claims the answer it publishes",
        "what": "the chip drag stops claiming - the store refuses the hand's own move",
        "file": "Biotak/BiotakMenu_B.mqh",
        "find": "   GVHomeAnswerNew(\"CHIP\");",
        "replace": "   // MUTATION: the chip drag claims nothing",
        "expect": "no longer claims its answer",
    },
    #--- ...and so must BOTH of the orb's hand paths: the drag release and the stale-claim
    #--- reap that commits a travelled pair. Losing either silently refuses that answer.
    {
        "id": "P-UI-158e",
        "gate": "regression",
        "rule": "the orb's release claims the answer it publishes",
        "what": "the orb release stops claiming - the store refuses the hand's own move",
        "file": "Biotak/BiotakMenu_C.mqh",
        "find": "         GVHomeAnswerNew(\"ORB\");",
        "replace": "         // MUTATION: the orb release claims nothing",
        "expect": "no longer claims its answer",
    },
    #--- ...and every surface must be SEEDED from its fraction, or at attach (when the
    #--- terminal reports no box) it paints at its DEFAULT and the first 250 ms pass jumps
    #--- it - the chip was the one surface the orb's seed missed.
    {
        "id": "P-UI-158f",
        "gate": "regression",
        "rule": "every surface is seeded from its own fraction at load",
        "what": "the chip has no fraction seed - it paints at the chart's middle and the refresh jumps it",
        "file": "Biotak/BiotakMenu_A.mqh",
        "find": "   if(!GVHomeLoadFrac(\"CHIP\", \"TIP\", tx, ty)) GVHomeFracSeed(\"CHIP\", tx, ty);",
        "replace": "   GVHomeLoadFrac(\"CHIP\", \"TIP\", tx, ty);   // MUTATION: no seed for the chip",
        "expect": "has no fraction seed",
    },
    #--- ...and the strip's FRESH placement is a new answer like a release is: it must write
    #--- through the hand's door, and only from a measured window.
    {
        "id": "P-UI-158g",
        "gate": "regression",
        "rule": "the strip's first placement writes through the hand's door",
        "what": "the strip writes a fresh home without a measured box - the live ratchet",
        "file": "Biotak/DrawStrip_Paint.mqh",
        "find": "   if(dsFreshHome && dsBox) { DrawStripHomeSet(s_dsX, s_dsY); GVHomeSaveFracHand(\"STRIP\", s_dsX, s_dsY); }",
        "replace": "   if(dsFreshHome) { DrawStripHomeSet(s_dsX, s_dsY); }   // MUTATION: no measured box, no hand door",
        "expect": "writes a fresh home without a measured box",
    },
    #--- ...and the strip's drag must claim, or its own move is refused.
    {
        "id": "P-UI-158h",
        "gate": "regression",
        "rule": "the strip drag claims the answer it publishes",
        "what": "the strip drag stops claiming - the store refuses the hand's own move",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "   GVHomeAnswerNew(\"STRIP\");",
        "replace": "   // MUTATION: the strip drag claims nothing",
        "expect": "no longer claims its answer",
    },
    #--- ...and the one refresh pass must NOT write: it is a DERIVATION, and a derivation
    #--- paints without ever reaching the store. This is the mutation that reproduces the
    #--- user's own bug in one line.
    {
        "id": "P-UI-158i",
        "gate": "regression",
        "rule": "the refresh derives and never stores",
        "what": "the refresh saves a home again - a derivation in one window is stored against another",
        "file": "Biotak/BiotakMenu_C.mqh",
        "find": "      CircOrbHomeSet(x, y);            // the home is the truth",
        "replace": "      CircOrbHomeSet(x, y); GVHomeSaveFrac(\"ORB\", x, y);   // MUTATION: a derivation reaches the store",
        "expect": "the refresh saves a home again",
    },
    #--- ...and the deleted derivation-box record must not come back: a second piece of
    #--- state that has to stay in step with the writer is what P-UI-158 removed.
    {
        "id": "P-UI-158j",
        "gate": "regression",
        "rule": "the derivation-box record stays deleted",
        "what": "the deleted derivation-box record is reintroduced",
        "file": "Biotak/BiotakHomes.mqh",
        "find": "void GVHomeWriteFrac(const string id, const int x, const int y)\r\n{",
        "replace": "void GVHomeWriteFrac(const string id, const int x, const int y)\r\n{\r\n   GVHomeDeclareBox();   // MUTATION: the derivation-box record is back",
        "expect": "is back",
    },
    #--- ...and the refresh gate must ask the READER's own question. `HomeChartSize`
    #--- substitutes 1920x1080 for a box the reader REFUSES, so the gate could consume a
    #--- change it never acted on and the home was then never applied that session.
    {
        "id": "P-UI-158k",
        "gate": "regression",
        "rule": "the refresh gate is the reader's own measure",
        "what": "the refresh gate reads a substituted box again - it records what the reader refuses",
        "file": "Biotak/BiotakMenu_C.mqh",
        "find": "   if(!HomeChartSizeRaw(cw, ch)) return;",
        "replace": "   HomeChartSize(cw, ch);   // MUTATION: the gate asks a different question",
        "expect": "the refresh gate",
    },
    #--- ...and the orb must follow its home with the ring SHUT, which is the normal state.
    {
        "id": "P-UI-158l",
        "gate": "regression",
        "rule": "the orb follows its home whether the ring is open or not",
        "what": "the orb repaint is gated on the ring again - with the ring shut the orb keeps the seed",
        "file": "Biotak/BiotakMenu_C.mqh",
        "find": "      UpdateCircularMenuPosition();\n   }\n   if(!CircTipDragging()",
        "replace": "      if(g_UI.menuVisible) UpdateCircularMenuPosition();\n   }\n   if(!CircTipDragging()",
        "expect": "the orb repaint is gated on the ring again",
    },
    #--- ...and the ONE writer must not invent a denominator either: the reader's rule is
    #--- only half of it (P-UI-156a is the other half).
    {
        "id": "P-UI-158m",
        "gate": "regression",
        "rule": "the home writer refuses an unmeasured box",
        "what": "the writer invents a denominator again - a fraction divided by a box the pixels did not come from",
        "file": "Biotak/BiotakHomes.mqh",
        "find": "   if(!HomeChartSizeRaw(rcw, rch)) return;   // unknown denominator: store nothing,",
        "replace": "   if(!HomeChartSize(rcw, rch)) return;   // MUTATION: a fallback denominator",
        "expect": "the writer invents a denominator",
    },
    #--- P-LOG-02b (2026-10-13): the half-applied P-LOG-02 left SIX invalidators at
    #--- ERROR. MEASURED on the live journal: 130 `[E][SYNC]` lines in a day, five per
    #--- timeframe switch. One site back at ERROR must fail the whole-file rule.
    {
        "id": "P-LOG-02b",
        "gate": "regression",
        "rule": "every cache invalidator is a lifecycle event, not an error",
        "what": "an invalidation is back at ERROR - it prints at production level and buries a real error",
        "file": "Biotak/CalculationCache.mqh",
        "find": '    _LOG_GATE_I Print("[I][SYNC] Geometry Cache Invalidated");',
        "replace": '    _LOG_GATE_E Print("[E][SYNC] Geometry Cache Invalidated");   // MUTATION: back at ERROR',
        "expect": "an invalidation is back at ERROR",
    },
    #--- P-PERF-45c (2026-10-13): the by-definition branch stamped the CLOCK and left
    #--- the FLAG false, so the frame's own re-arm overwrote the clock and the ledger
    #--- printed `waited=-16ms` (impossible by construction). Deleting the flag line is
    #--- the defect itself.
    {
        "id": "P-PERF-45c",
        "gate": "regression",
        "rule": "the by-definition frame owes its flag as well as its clock",
        "what": "the branch stamps the clock without setting the flag - `waited` goes negative and the ledger lies",
        "file": "Biotak/EventHandlers_Tail.mqh",
        "find": "         s_coopOwed[job] = true;\n",
        "replace": "",
        "expect": "WITHOUT setting the flag",
    },
    #--- P-BE-05 (2026-10-13): `GetOrCreateSymbolState` carried an unreachable SECOND
    #--- copy of its creation block below `return newIndex;` - a second counter bump and
    #--- its own return. MQL4 never warns on unreachable statements.
    {
        "id": "P-BE-05",
        "gate": "regression",
        "rule": "one path creates, initialises and counts the symbol state",
        "what": "the unreachable duplicate creation block after the return is back",
        "file": "Biotak/BasePrice_A.mqh",
        "find": "    return newIndex;\n    // P-BE-05",
        "replace": "    return newIndex;\n    g_symbolStateCount++;   // MUTATION: the dead block is back\n    // P-BE-05",
        "expect": "is back below the return",
    },
    #--- P-PERF-55a (2026-10-13): the sweep's membership test was a LINEAR scan of a
    #--- ~1,189-name list, once per family object on a ~1,200-object chart. One of the
    #--- two tests back on the scan must fail the rule.
    {
        "id": "P-PERF-55a",
        "gate": "regression",
        "rule": "the foreign-ladder sweep answers membership with a set",
        "what": "one of the sweep's membership tests is a linear scan again",
        "file": "Biotak/LevelPipe_B.mqh",
        "find": "        if(LadderNameIsZoneBand(nm))\n        {\n            if(producedSet ? LadderSetHas(nm) : ProducedLadderName(nm, produced, pc)) continue;",
        "replace": "        if(LadderNameIsZoneBand(nm))\n        {\n            if(ProducedLadderName(nm, produced, pc)) continue;   // MUTATION: the scan is back",
        "expect": "membership tests use the set",
    },
    #--- P-PERF-55b (2026-10-13): the set must REFUSE a list it cannot hold, or an
    #--- oversized ladder is answered by a half-filled table and a produced name reads
    #--- as "not produced" - i.e. the chart deletes its own ladder.
    {
        "id": "P-PERF-55b",
        "gate": "regression",
        "rule": "the set refuses a list it cannot hold",
        "what": "the set answers an oversized list from a half-filled table",
        "file": "Biotak/LevelPipe_B.mqh",
        "find": "    if(pc <= 0 || pc * 2 > LADDER_SET_SIZE) return false;",
        "replace": "    if(pc <= 0) return false;   // MUTATION: a half-filled table answers",
        "expect": "no longer refuses a list it cannot hold",
    },
    #--- P-BUILD-13 (2026-10-13): `-Project all` printed «All compilations PASSED!»
    #--- while `Biotak Trigger TH3 Lite.mq4` was compiled by NO project at all — the
    #--- summary shipped a STALE Lite ex4. Each of the two halves of the fix, plus the
    #--- orphan guard, must be able to fail the rule.
    {
        "id": "P-BUILD-13a",
        "gate": "regression",
        "rule": "`-Project all` names the Lite product",
        "what": "the `all` set drops `lite` again (the measured 18:23 defect)",
        "file": "compile-th3.ps1",
        "find": '$ALL_PROJECT_ORDER = @("workspace", "installed", "lite")',
        "replace": '$ALL_PROJECT_ORDER = @("workspace", "installed")   # MUTATION: Lite orphaned',
        "expect": "P-BUILD-13",
    },
    {
        "id": "P-BUILD-13b",
        "gate": "regression",
        "rule": "the `lite` project points at the Lite source",
        "what": "the Lite table entry is pointed at the Full source",
        "file": "compile-th3.ps1",
        "find": '        Source = Join-Path $SCRIPT_ROOT "Biotak Trigger TH3 Lite.mq4"',
        "replace": '        Source = Join-Path $SCRIPT_ROOT "Biotak Trigger TH3.mq4"   # MUTATION: the Full source',
        "expect": "P-BUILD-13",
    },
    {
        "id": "P-BUILD-13c",
        "gate": "regression",
        "rule": "a table entry missing from `all` fails the build",
        "what": "the completeness assertion is demoted to a harmless note",
        "file": "compile-th3.ps1",
        "find": "does not cover: $($uncovered -join ', ')",
        "replace": "uncovered projects: $($uncovered -join ', ')",
        "expect": "P-BUILD-13",
    },
    #--- P-BUILD-14 (2026-10-13): a case-duplicate env key (http_proxy + HTTP_PROXY,
    #--- Git Bash / MSYS and this agent runtime) made Start-Process throw BEFORE
    #--- metaeditor.exe launched — both ex4 stayed stale while the gates still passed.
    #--- The normalizer must read the env, re-add the surviving spelling, and RUN
    #--- before the first Start-Process; each link must be able to fail the rule.
    {
        "id": "P-BUILD-14a",
        "gate": "regression",
        "rule": "the env normalizer is actually called",
        "what": "the normalizer is defined but never invoked",
        "file": "compile-th3.ps1",
        "find": "$script:EnvDeduped = Remove-CaseDuplicateEnv",
        "replace": "$script:EnvDeduped = 0   # MUTATION: defined but never called",
        "expect": "P-BUILD-14",
    },
    {
        "id": "P-BUILD-14b",
        "gate": "regression",
        "rule": "the env normalizer reads the process environment",
        "what": "the normalizer no longer enumerates the environment",
        "file": "compile-th3.ps1",
        "find": "foreach ($item in ([System.Environment]::GetEnvironmentVariables().GetEnumerator())) {",
        "replace": "foreach ($item in (@())) {   # MUTATION: nothing to read",
        "expect": "P-BUILD-14",
    },
    {
        "id": "P-BUILD-14c",
        "gate": "regression",
        "rule": "the env normalizer re-adds the surviving spelling",
        "what": "the canonical spelling is never re-added (the value would be lost)",
        "file": "compile-th3.ps1",
        "find": "[System.Environment]::SetEnvironmentVariable($keepName, $keepValue, 'Process')",
        "replace": "# MUTATION: the surviving spelling is dropped",
        "expect": "P-BUILD-14",
    },
    #--- P-DRAW-128/129/130 (2026-10-13) — A HOVER PREVIEW IS NOT A CHOICE, AND THE
    #--- NATIVE SURFACE'S PICK IS A PICK. The palette's DRAWING pages pushed to
    #--- RECENT and learned the kind's memory on every hover crossing («موس روش
    #--- میبیم عوض میشه یک شیء دیگه جاش میاد»), and a colour set in MT4's OWN
    #--- dialog/toolbar never reached the memory at all, so the terminal's Ctrl+drag
    #--- copy came back wearing the old colour («برمیگرده به رنگ خودش»). `remember`
    #--- now rides from the apply down to the slot owner's learn half; the native
    #--- colour arrives as OBJECT_CHANGE behind a move-vs-colour witness and is
    #--- taught through the memory's ONE owner. Each link must be able to fail.
    {
        "id": "P-DRAW-128",
        "gate": "regression",
        "rule": "a DRAWING pick reaches RECENT and the kind memory only on the hand's own apply",
        "what": "the palette's DRAW branch ignores remember again (hover reorders RECENT and learns)",
        "file": "Biotak/BiotakPanels_State.mqh",
        "find": "case PAL_DRAW_FILL:      DrawStripPalTargetApply(clr, remember); if(remember) PushPalRecent(clr); return REFRESH_BUFFERS;",
        "replace": "case PAL_DRAW_FILL:      DrawStripPalTargetApply(clr); PushPalRecent(clr); return REFRESH_BUFFERS; // MUTATION: remember ignored",
        "expect": "P-DRAW-128/129/130",
    },
    {
        "id": "P-DRAW-128b",
        "gate": "regression",
        "rule": "the strip's own ring moves on a commit, not on a preview",
        "what": "the bridge's recents push is ungated",
        "file": "Biotak/DrawStrip_Base.mqh",
        "find": "   DrawStripColorCommit(s_dsPalSlot, c, remember);\n   if(remember) DrawStripRecentPush(c);",
        "replace": "   DrawStripColorCommit(s_dsPalSlot, c, remember);\n   DrawStripRecentPush(c);   // MUTATION: the ring moves on hover",
        "expect": "P-DRAW-128/129/130",
    },
    {
        "id": "P-DRAW-128c",
        "gate": "regression",
        "rule": "the slot owner learns the kind colour on a pick only",
        "what": "DrawSlotWrite learns even when remember=false (a preview teaches the kind)",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "         if(remember)\r\n         {\r\n            s_dkColor[k] = c;\r\n"
                "            //--- P-DRAW-INK (2026-10-04): the ONE ink every kind shares is noted HERE,\r\n"
                "            //--- where every pick arrives. The kind's own memory records what IT wore; this\r\n"
                "            //--- records the last colour the HAND chose anywhere, so a kind with no colour\r\n"
                "            //--- of its own can wear it at birth.\r\n"
                "            if((int)c >= 0) s_dkAnyClr = c;\r\n         }",
        "replace": "         s_dkColor[k] = c;\r\n         if((int)c >= 0) s_dkAnyClr = c;   // MUTATION: a preview learns",
        "expect": "P-DRAW-128/129/130",
    },
    {
        "id": "P-DRAW-128d",
        "gate": "regression",
        "rule": "the native surface's colour change reaches the kind memory",
        "what": "the OBJECT_CHANGE branch never calls the learner",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "      if(id == CHARTEVENT_OBJECT_CHANGE) DrawInkLearnNative(sparam);",
        "replace": "      // MUTATION: the native surface's pick is never learned",
        "expect": "P-DRAW-128/129/130",
    },
    {
        "id": "P-DRAW-128e",
        "gate": "regression",
        "rule": "the learner needs its witness to tell a colour edit from a move-drop",
        "what": "the witness is dropped — a drop would teach the kind a factory colour",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "   if(!DrawInkMemoDelta(name, c)) return;    // nothing moved: our own write, or a drop",
        "replace": "   // MUTATION: no move-vs-colour witness",
        "expect": "P-DRAW-128/129/130",
    },
    {
        "id": "P-DRAW-128f",
        "gate": "regression",
        "rule": "a borrowed ink is never frozen as a kind's own colour",
        "what": "the borrowed-ink guard is removed",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "   if((int)s_dkColor[k] < 0 && c == s_dkAnyClr) return;   // a borrowed ink is not this kind's own",
        "replace": "   // MUTATION: the borrowed ink is frozen as the kind's own",
        "expect": "P-DRAW-128/129/130",
    },
    {
        "id": "P-DRAW-128g",
        "gate": "regression",
        "rule": "the witness refuses a level kind — its colours are the LEVEL family's (P-DRAW-BODY)",
        "what": "the level-kind guard is dropped, so a fibo's meaningless OBJPROP_COLOR is learned as a pick",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "   if(DrawKindHasLevels(k)) return clrNONE;",
        "replace": "   // MUTATION: the witness reads a property a level kind does not own",
        "expect": "P-DRAW-128/129/130",
    },
    #--- P-LM-25 (2026-10-16) — THE LEG'S OWN TIME, NOT THE CHART'S NOW. A leg
    #--- drawn over history printed TODAY's live ATR (MEASURED: H1 143 / H4 327 /
    #--- D1 999, the live strip row to the digit) because `LegAtr14` read
    #--- `CalculateWeightedATR`. The inverse puts the live read back: §48 must
    #--- fail naming P-LM-25.
    {
        "id": "P-LM-25",
        "gate": "regression",
        "rule": "every leg-measure ATR is read AT the leg's own bar (the later anchor), never the chart's live composite",
        "what": "LegAtr14 reads the live composite again — a historical leg prints today's ATR",
        "file": "Biotak/TH3Tool_C.mqh",
        "find": "    double a = CalculateWeightedATRAt(CompatTF(tf), anchor);",
        "replace": "    double a = CalculateWeightedATR(CompatTF(tf));   // MUTATION: live again (the reported defect)",
        "expect": "P-LM-25",
    },
    #--- P-UI-160b (2026-10-16) — THE F MUTE TAKES THE DRAWING FAMILIES TOO.
    #--- MEASURED: F darkened the level families and left the leg meter, the ABCD
    #--- family, the rays and the paths standing («دکمه f که فقط زون ها رو خاموش و
    #--- روشن میکنه پیس همه رو باید خاموش بکنه»). The inverse drops one family from
    #--- the hide pass: §49 must fail naming P-UI-160b.
    {
        "id": "P-UI-160b",
        "gate": "regression",
        "rule": "the F mute takes the drawing families too (hide pass + show half + every rider carries the hidden term)",
        "what": "the hide pass stops hiding the rays — F leaves them standing again (the reported defect)",
        "file": "Biotak/EventHandlers_CustomPrice.mqh",
        "find": "    drawHr = HRayHideAll();",
        "replace": "    drawHr = 0;   // MUTATION: the rays escape the mute again (the reported defect)",
        "expect": "P-UI-160b",
    },
    #--- P-TH-VOLNORM-COMBO (2026-10-16) — THE COMBO COMPONENTS WEAR V.
    #--- MEASURED in the sources: TH/SS-LS ladders wear the block V and every TH
    #--- label column wears its rung's V, but the combo engine read the RAW table
    #--- («این نرمال سازی مثل بقیه موده در مود کامبو کار نمیکنه سطوح درست نیست»).
    #--- The inverse drops the V from the standard path — §50 must fail naming
    #--- P-TH-VOLNORM-COMBO.
    {
        "id": "P-TH-VOLNORM-COMBO",
        "gate": "regression",
        "rule": "the combo components wear the normalization (the rung whose pct the component used, OFF = 1.0)",
        "what": "the standard path multiplies by 1.0 — combo levels read the raw table again (the reported defect)",
        "file": "Biotak/ComboEngine.mqh",
        "find": "           ComboComponentVolNorm(GetTimeframeTHForPeriod(timeframe));   // P-TH-VOLNORM-COMBO",
        "replace": "           1.0;   // MUTATION: the standard path reads the raw table again (the reported defect)",
        "expect": "P-TH-VOLNORM-COMBO",
    },
    #--- P-UI-161 (2026-10-17) — THE RING'S MEMBERSHIP, ITS DOOR, ITS WITNESS.
    #--- The star is the only door to the eight features, the Tools door is always
    #--- the LAST seat, and the toggle's verdict goes out through the FLUSHED
    #--- channel. Each inverse must fail §51 naming P-UI-161.
    {
        "id": "P-UI-161a",
        "gate": "regression",
        "rule": "the Tools door is always the ring's LAST seat (an unstarred door is a menu with no way back)",
        "what": "RingFeature answers the door's index with -1 — the door falls off the ring",
        "file": "Biotak/BiotakMenu_Ring.mqh",
        "find": "   if(ringIdx == CircPlacedCount() - 1) return CIR_TOOLS;   // the door, always last",
        "replace": "   if(ringIdx == CircPlacedCount() - 1) return -1;   // MUTATION: the door is not last",
        "expect": "P-UI-161",
    },
    {
        "id": "P-UI-161b",
        "gate": "regression",
        "rule": "the star toggle's verdict goes through the FLUSHED channel (DrawStripDiagEmit, P-LOG-3)",
        "what": "the toggle's witness is a Print — it waits in MT4's RAM buffer and answers «nothing happened» (P-DRAW-126)",
        "file": "Biotak/BiotakMenu_C.mqh",
        "find": "   DrawStripDiagEmit(StringFormat(\"[P-UI-161] star cat=%d on=%d mask=0x%X ringN=%d\",",
        "replace": "   Print(StringFormat(\"[P-UI-161] star cat=%d on=%d mask=0x%X ringN=%d\",",
        "expect": "P-UI-161",
    },
    {
        "id": "P-UI-161c",
        "gate": "regression",
        "rule": "the shipped default mask restores the 9-feature ring with its handoff stamp (sessions appended at bit 15)",
        "what": "CIRC_STAR_DEFAULT drops bit 15 — a first run forgets the sessions cell",
        "file": "Biotak/BiotakMenu_Ring.mqh",
        "find": "#define CIRC_STAR_DEFAULT (0xFF80 | CIRC_STAR_STAMP)",
        "replace": "#define CIRC_STAR_DEFAULT (0x7F80 | CIRC_STAR_STAMP)",
        "expect": "CIRC_STAR_DEFAULT",
    },
    #--- P-UI-164 (2026-10-17) — THE CAPACITY IS THE DRAWN LAYOUT'S OWN. A ring
    #--- dragged to an edge and released came back short (13 built, 9 rebuilt —
    #--- the tail AND the door) because the capacity answered the RING's
    #--- ray-vs-bounds while the drawn layout there is the TRAIN, whose room is
    #--- the free run of the edge. ONE shape decision (CircRailShape) must be
    #--- read by the capacity and the paint alike, the train seats at its own
    #--- side, the ring is drawn only where the chord proves it fits, and the
    #--- door rides the LAST PLACED seat. Each inverse must fail §55 naming
    #--- P-UI-164.
    {
        "id": "P-UI-164a",
        "gate": "regression",
        "rule": "the capacity asks the DRAWN shape (CircRailShape) before it counts",
        "what": "CircPlacedCountLive answers the ring's fit walk on the train too — the release rebuilds a fitting 13-seat train as 9 and the tail (door included) vanishes (the reported defect)",
        "file": "Biotak/BiotakMenu_Ring.mqh",
        "find": "   if(CircRailShape(vertical, dir))\n   {\n      s_liveR = CircRailCapacity(MathMin(n, CIRC_SEAT_CAP), vertical, dir);   // P-UI-166: the train honours the cap too\n   }",
        "replace": "   if(false)   // MUTATION: the capacity answers the ring's fit walk where the train draws\n   {\n      s_liveR = CircRailCapacity(MathMin(n, CIRC_SEAT_CAP), vertical, dir);\n   }",
        "expect": "P-UI-164",
    },
    {
        "id": "P-UI-164b",
        "gate": "regression",
        "rule": "the PAINT reads the same shape decision as the capacity (CircLayout asks CircRailShape)",
        "what": "CircLayout decides the branch on its own again — the painted train and the measured capacity are two grids",
        "file": "Biotak/BiotakMenu_B.mqh",
        "find": "   if(CircRailShape(vertical, dir))",
        "replace": "   if(false)   // MUTATION: the paint decides the branch on its own again",
        "expect": "P-UI-164",
    },
    {
        "id": "P-UI-164c",
        "gate": "regression",
        "rule": "the door rides the LAST PLACED seat (CircPlacedCount() - 1)",
        "what": "the door is seated at RingCount() - 1 again — it falls off the ring whenever the cap seats fewer than the mask",
        "file": "Biotak/BiotakMenu_Ring.mqh",
        "find": "   if(ringIdx == CircPlacedCount() - 1) return CIR_TOOLS;   // the door, always last",
        "replace": "   if(ringIdx == RingCount() - 1) return CIR_TOOLS;   // MUTATION: the door only when every star fits",
        "expect": "P-UI-164",
    },
    {
        "id": "P-UI-164d",
        "gate": "regression",
        "rule": "the ring is drawn only where BOTH circles fit (the first circle's chord AND the outer circle's own reach)",
        "what": "CircRingFits stops testing the outer circle's reach — the second circle draws past the chart edge, and the shape gate and the paint disagree again",
        "file": "Biotak/BiotakMenu_Ring.mqh",
        "find": "   if(CircRing2Count() > 0 && CircRing2Radius() > CircFitLimitOuter()) return false;",
        "replace": "   if(false) return false;   // MUTATION: the outer circle's reach is not tested",
        "expect": "P-UI-164",
    },
    #--- P-UI-165 (2026-10-17) — THE PLACE BELONGS TO THE PAIR. P-UI-131e's
    #--- chart-free key made one pair's hand land every other pair (the orb
    #--- near an edge everywhere, P-UI-164's squeeze following it). The keys
    #--- now carry the SYMBOL (never the chart id, which is per session) and
    #--- the pre-165 spellings are READ-ONLY migration sources: the load
    #--- snapshots them once in a measured window and no writer touches them.
    #--- Each inverse must fail §56 naming P-UI-165.
    {
        "id": "P-UI-165a",
        "gate": "regression",
        "rule": "the home's fraction key carries the SYMBOL (one pair's hand never moves another pair's surface)",
        "what": "GVHomeFracName drops the symbol — the chart-free key is back and every pair lands on one place (the reported defect)",
        "file": "Biotak/BiotakHomes.mqh",
        "find": 'string GVHomeFracName(const string id,const bool y) { return "BIOMENU_" + _Symbol + "_HOME_" + id + (y ? "_FY" : "_FX"); }',
        "replace": 'string GVHomeFracName(const string id,const bool y) { return "BIOMENU_HOME_" + id + (y ? "_FY" : "_FX"); }   // MUTATION: chart-free again',
        "expect": "P-UI-165",
    },
    {
        "id": "P-UI-165b",
        "gate": "regression",
        "rule": "the panel's fraction key carries the SYMBOL",
        "what": "PnlFracKey drops the symbol — a panel dragged on EURUSD lands every other pair (the P-UI-140q behaviour back)",
        "file": "Biotak/BiotakPanels_Build.mqh",
        "find": 'string PnlFracKey(const int item) { return "BIOMENU_" + _Symbol + "_PNL_" + IntegerToString(item) + "_F"; }',
        "replace": 'string PnlFracKey(const int item) { return "BIOMENU_PNL_" + IntegerToString(item) + "_F"; }   // MUTATION: symbol-free again',
        "expect": "P-UI-165",
    },
    {
        "id": "P-UI-165c",
        "gate": "regression",
        "rule": "the shared pre-165 pair is snapshotted into the pair's own key ONCE (the migration)",
        "what": "the snapshot is gone — every pair reads the shared key forever and the next hand move on ANY pair moves them all",
        "file": "Biotak/BiotakHomes.mqh",
        "find": "      if(!GVHomeFracKnownOwn(id)) GVHomeSaveFracHand(id, x, y);",
        "replace": "      // MUTATION: no snapshot — the pair reads the shared key forever",
        "expect": "P-UI-165",
    },
    {
        "id": "P-UI-165d",
        "gate": "regression",
        "rule": "a pre-165 store still answers (GVHomeFracKnown accepts the shared pair)",
        "what": "the shared fallback is gone — a pre-165 store answers «no home» and every surface drops to its default on the upgrade",
        "file": "Biotak/BiotakHomes.mqh",
        "find": " || GlobalVariableCheck(GVHomeFracNameShared(id,false)))",
        "replace": "   // MUTATION: the shared store is invisible",
        "expect": "P-UI-165",
    },
    {
        "id": "P-UI-165e",
        "gate": "regression",
        "rule": "no writer ever writes or deletes the shared pre-165 keys",
        "what": "the writer sweeps the SHARED pixel keys — deleting them strands every pair that has not migrated yet",
        "file": "Biotak/BiotakHomes.mqh",
        "find": "   GlobalVariableDel(GVHomeName(id,false)); GlobalVariableDel(GVHomeName(id,true));",
        "replace": "   GlobalVariableDel(GVHomeNameShared(id,false)); GlobalVariableDel(GVHomeNameShared(id,true));   // MUTATION: sweeps the shared pair",
        "expect": "P-UI-165",
    },
    #--- P-UI-195 (2026-10-21) — TWO CIRCLES, by the user's own order. «این
    #--- رینگ‌ها پیش فرض ۹ تا اصلی باشه و بقیه دورش از یک طرف شروع به چینش در
    #--- دایره دوم بکنه ولی از دایره اول کوچیک‌تر باشه» + «شعاع بزرگ‌تر ولی بین دو
    #--- ایتم اصلی … سایز کوچیک‌تر از سایز دکمه های اولی» + «بالا (۱۲ ساعت)،
    #--- ساعتگرد». P-UI-161's taper and P-UI-166's twelve-seat cap are retired
    #--- for the ring: nine inner seats at 44px/r80, the rest plus the door on a
    #--- 32px outer circle at a bigger radius. P-UI-195b (2026-10-22) — «دایره
    #--- کوچیک‌تر به ردیف باشه» + the drawing: the outer seats take the LAST n2
    #--- GAPS of the row at the row's own pitch (210/250 for n1=9, n2=2), never a
    #--- 360/n2 scatter (the measured 110 deg sat radially behind an inner seat).
    #--- Each inverse must fail §57 naming P-UI-195.
    {
        "id": "P-UI-195a",
        "gate": "regression",
        "rule": "the first circle is the shipped nine; every seat past it rides the second",
        "what": "CircSeatOuter never answers the outer circle — the tenth star returns to the main ring and the second circle stays empty",
        "file": "Biotak/BiotakMenu_Ring.mqh",
        "find": "bool CircSeatOuter(const int i) { return (i >= CircRing1Count()); }",
        "replace": "bool CircSeatOuter(const int i) { return false; }   // MUTATION: one circle again",
        "expect": "P-UI-195",
    },
    {
        "id": "P-UI-195b",
        "gate": "regression",
        "rule": "the second circle is SMALLER than the first (the user's own order)",
        "what": "CIRC_RING2_BTN_SIZE is 44 — the outer circle draws at the inner side and the order «کوچیک‌تر» is gone",
        "file": "Biotak/BiotakMenu_A.mqh",
        "find": "#define CIRC_RING2_BTN_SIZE 32",
        "replace": "#define CIRC_RING2_BTN_SIZE 44",
        "expect": "P-UI-195",
    },
    {
        "id": "P-UI-195c",
        "gate": "regression",
        "rule": "the outer seats borrow the inner row's own pitch (never 360/n2)",
        "what": "CircRing2StepDeg returns 360/n2 again — the second small lands at 30 deg, radially BEHIND an inner seat (the measured defect, P-UI-195b)",
        "file": "Biotak/BiotakMenu_Ring.mqh",
        "find": "   return (n2 > n1) ? (360.0 / n2) : (360.0 / n1);",
        "replace": "   return 360.0 / n2;   // MUTATION: scattered by 360/n2 — the second seat lands behind an inner one",
        "expect": "P-UI-195",
    },
    {
        "id": "P-UI-195d",
        "gate": "regression",
        "rule": "the outer circle clears the inner discs (gap + both half-sides)",
        "what": "CircRing2Radius drops the inner-disc clearance — the two circles overlap and their skins draw on one pixel",
        "file": "Biotak/BiotakMenu_Ring.mqh",
        "find": "   double r = CircRadius() + CIRC_BTN_SIZE / 2.0 + CIRC_GAP + CIRC_RING2_BTN_SIZE / 2.0;",
        "replace": "   double r = CircRadius();   // MUTATION: the circles overlap",
        "expect": "P-UI-195",
    },
    {
        "id": "P-UI-195e",
        "gate": "regression",
        "rule": "the ring seats every starred item on the two circles",
        "what": "CircPlacedCountLive falls back to nine — the tail stars and the door drop off the ring again",
        "file": "Biotak/BiotakMenu_Ring.mqh",
        "find": "      s_liveR = n;",
        "replace": "      s_liveR = 9;   // MUTATION: the tail drops",
        "expect": "P-UI-195",
    },
    {
        "id": "P-UI-195f",
        "gate": "regression",
        "rule": "the train honours the seat cap (a drag to an edge never seats a thirteenth tail)",
        "what": "CircRailCapacity walks from RingCount() again — the edge seats tail stars the ring would not",
        "file": "Biotak/BiotakMenu_Ring.mqh",
        "find": "      s_liveR = CircRailCapacity(MathMin(n, CIRC_SEAT_CAP), vertical, dir);   // P-UI-166: the train honours the cap too",
        "replace": "      s_liveR = CircRailCapacity(n, vertical, dir);   // MUTATION: the train is uncapped",
        "expect": "P-UI-195",
    },
    {
        "id": "P-UI-195g",
        "gate": "regression",
        "rule": "the train's taper floor is 35 (CIRC_BTN_MIN)",
        "what": "CIRC_BTN_MIN drops back to 30 — the edge train seats discs smaller than the glyph's own 28px box",
        "file": "Biotak/BiotakMenu_A.mqh",
        "find": "#define CIRC_BTN_MIN     35",
        "replace": "#define CIRC_BTN_MIN     30",
        "expect": "P-UI-195",
    },
    {
        "id": "P-UI-195h",
        "gate": "regression",
        "rule": "CIRC_SEAT_CAP is 12 (the train's cap, P-UI-166)",
        "what": "the cap is raised out of the design — twelve becomes whatever a future edit says",
        "file": "Biotak/BiotakMenu_Ring.mqh",
        "find": "#define CIRC_SEAT_CAP 12",
        "replace": "#define CIRC_SEAT_CAP 99",
        "expect": "P-UI-195",
    },
    {
        "id": "P-UI-195i",
        "gate": "regression",
        "rule": "the outer row takes the LAST n2 gaps, ending just before 12 o'clock (the user's drawing: 170/210/250)",
        "what": "the row starts at the FIRST gap again (k = 0) — the smalls leave the drawn zone before 12 and sit at -70/-30 instead of 210/250",
        "file": "Biotak/BiotakMenu_Ring.mqh",
        "find": "   int k = n1 - n2;                                 // the LAST n2 gaps of the row",
        "replace": "   int k = 0;   // MUTATION: the row starts at the first gap",
        "expect": "P-UI-195",
    },
    {
        "id": "P-UI-195j",
        "gate": "regression",
        "rule": "the paint asks the start/step owners (one grid with the fit and the hit test)",
        "what": "CircLayout computes the outer angle on its own — the paint and the row-gap law disagree again",
        "file": "Biotak/BiotakMenu_B.mqh",
        "find": "      double deg = (CircRing2StartDeg() + CircRing2StepDeg() * (i - n1)) * M_PI / 180.0;",
        "replace": "      double deg = (CircRing2StartDeg() + 360.0 * (i - n1) / CircRing2Count()) * M_PI / 180.0;   // MUTATION: a second grid",
        "expect": "P-UI-195",
    },
    #--- P-SESS (2026-10-17) — THE SESSIONS CELL. CIR_SESSIONS (19) sits ABOVE the
    #--- card-number space, so the identity fallback cannot answer it: FeaturePanel
    #--- MUST map it to card 15, the press MUST flip g_sessMaster once and persist
    #--- it through the throttled saver before the render tick, and the cell MUST
    #--- wear the baked clock. Each inverse fails §52 naming P-SESS.
    {
        "id": "P-SESS-a",
        "gate": "regression",
        "rule": "FeaturePanel maps CIR_SESSIONS to card 15 (the identity fallback answers 19, which is no card)",
        "what": "the sessions case answers its own code — the press opens nothing",
        "file": "Biotak/BiotakMenu_A.mqh",
        "find": "   if(feat == CIR_SESSIONS)      return 15;   // Sessions Zones card (P-SESS)",
        "replace": "   if(feat == CIR_SESSIONS)      return 19;   // MUTATION: the identity fallback",
        "expect": "P-SESS",
    },
    {
        "id": "P-SESS-b",
        "gate": "regression",
        "rule": "ONE writer per fact: the sessions press flips g_sessMaster, persists OV_SSON and ticks the renderer",
        "what": "the branch stops persisting — the master flips in RAM only",
        "file": "Biotak/BiotakMenu_D.mqh",
        "find": "      RuntimeSettingsSaveOverridesThrottled();   // OV_SSON\r\n      SessionsTick();",
        "replace": "      SessionsTick();",
        "expect": "P-SESS",
    },
    {
        "id": "P-SESS-c",
        "gate": "regression",
        "rule": "the sessions cell wears the baked clock (ART.sessions -> sessions_on/off.bmp)",
        "what": "CircIconRes loses the sessions base — the cell wears the fallback glyph",
        "file": "Biotak/BiotakMenu_A.mqh",
        "find": "      else if(i == CIR_SESSIONS)   base = \"sessions\"; // P-SESS — Sessions Zones cell (clock)",
        "replace": "      else if(i == CIR_SESSIONS)   base = \"htf\"; // MUTATION",
        "expect": "P-SESS",
    },
    {
        "id": "P-SESS-d",
        "gate": "regression",
        "rule": "P-SESS-04: a pre-SESSIONS saved star mask gets the clock starred ONCE (stamped), the user's own bits untouched",
        "what": "the handoff never stars bit 15 — an upgraded chart keeps a clockless ring (the user's own report)",
        "file": "Biotak/BiotakMenu_Ring.mqh",
        "find": "      v |= (uint)(0x8000 | CIRC_STAR_STAMP);",
        "replace": "      v |= (uint)(CIRC_STAR_STAMP);   // MUTATION: sessions never added",
        "expect": "P-SESS",
    },
    {
        "id": "P-SESS-e",
        "gate": "regression",
        "rule": "P-SESS-05: a hollow session box is four border segments — a rectangle renders filled whatever FILL says on some MT4 builds (ZoneFactory.mqh:143)",
        "what": "one edge loses its suffix — the hollow frame is no longer the four-edge body and a slab can return (the report this entry was born from)",
        "file": "Biotak/Sessions_Draw.mqh",
        "find": "      SessEdge(nm + \"ET\", t1, p1, t2, p1, borderC, width, style, tip);",
        "replace": "      SessEdge(nm + \"XT\", t1, p1, t2, p1, borderC, width, style, tip);   // MUTATION",
        "expect": "P-SESS",
    },
    {
        "id": "P-SESS-f",
        "gate": "regression",
        "rule": "P-SESS-05: the filled box CLAIMS its fill — OBJPROP_FILL is written true, never assumed",
        "what": "the FILL write is dropped — the fill becomes a guess again (the report this entry was born from)",
        "file": "Biotak/Sessions_Draw.mqh",
        "find": "   ObjectSetInteger(0, nm, OBJPROP_FILL, true);   // a fill is written, never assumed",
        "replace": "   // MUTATION: the FILL claim is dropped",
        "expect": "P-SESS",
    },
    {
        "id": "P-SESS-g",
        "gate": "regression",
        "rule": "P-SESS-05: the factory session box ships OUTLINE — some MT4 builds slab a rectangle whatever FILL/BGCOLOR say (ZoneFactory.mqh:143)",
        "what": "the factory style flips back to FILLED — a fresh chart paints solid slabs again (shipped twice: the 14:58 and 16:31 reports)",
        "file": "Biotak/Sessions_Model.mqh",
        "find": "   s.style = SESS_STYLE_OUTLINE; s.col = 0; s.enabled = false;",
        "replace": "   s.style = SESS_STYLE_FILLED; s.col = 0; s.enabled = false;   // MUTATION",
        "expect": "P-SESS",
    },
    {
        "id": "P-SESS-h",
        "gate": "regression",
        "rule": "P-SESS-06: the LIVE session's box is BOLD — width 2 beside the past windows' 1 (the user's ask, 2026-10-17)",
        "what": "the live/past width split collapses — the session you are in stops standing out",
        "file": "Biotak/Sessions_Draw.mqh",
        "find": "         int bW = wLive ? 2 : 1;",
        "replace": "         int bW = wLive ? 1 : 1;   // MUTATION: the live box is no longer bold",
        "expect": "P-SESS",
    },
    {
        "id": "P-SESS-i",
        "gate": "regression",
        "rule": "P-SESS-06: every PAST window fades to SESS_PAST_ALPHA — only the live one keeps the base ink",
        "what": "the past ink keeps the base colour — past and live sessions read alike again (the report this entry was born from)",
        "file": "Biotak/Sessions_Draw.mqh",
        "find": "         color ink = wLive ? base : SessBlend(base, SESS_PAST_ALPHA);",
        "replace": "         color ink = base;   // MUTATION: past keeps the base ink",
        "expect": "P-SESS",
    },
    {
        "id": "P-SESS-j",
        "gate": "regression",
        "rule": "P-SESS-06: the live window's H/L lines are bold (width 2) with its box",
        "what": "the H/L width split collapses — the live window's high/low stays hairline",
        "file": "Biotak/Sessions_Draw.mqh",
        "find": "            int lw = wLinLive ? 2 : 1;",
        "replace": "            int lw = wLinLive ? 1 : 1;   // MUTATION: no bold H/L",
        "expect": "P-SESS",
    },
    #--- P-SESS-07 (2026-10-20) — THE LIVE WINDOW IS THE STATE'S, NOT THE DAY'S.
    #--- kk is a ZONE-DAY index against server noon: a live window that started
    #--- yesterday (western zones before noon) is kk=-1 and one that starts late
    #--- (eastern zones) is kk=+1. The `kk == 0` gate cost exactly those windows
    #--- their live cache, bold width, H/L lines and overlap. Each inverse must
    #--- fail 52e naming P-SESS-07.
    {
        "id": "P-SESS-k",
        "gate": "regression",
        "rule": "P-SESS-07: the live window is named by SessWindowState — kk is a day index, never a session edge",
        "what": "the day-index gate returns to the H/L block — a session spanning server noon loses its live lines and cache",
        "file": "Biotak/Sessions_Draw.mqh",
        "find": "bool wLinLive = (SessWindowState(wins[wLin], now) == SESS_WS_LIVE);   // P-SESS-06/07",
        "replace": "bool wLinLive = (wins[wLin].kk == 0 && SessWindowState(wins[wLin], now) == SESS_WS_LIVE);   // MUTATION: day-index gate",
        "expect": "P-SESS",
    },
    #--- P-SESS-08 (2026-10-20) — THE GHOST TAG IS NOT A FILL CHILD. `nmF` ends in
    #--- `_F`; the tag tail "L" made `_FL`, FILLCHILD_SUFFIX. Measured in the live
    #--- journal: ORPHAN drop="THLevelsSESS_<slot>_<stamp>_FL" on every timeframe,
    #--- 20+ times in five minutes. The sweep deleted every ghost tag 2 s after paint.
    {
        "id": "P-SESS-l",
        "gate": "regression",
        "rule": "P-SESS-08: the ghost tag tail is not 'L' — `_F` + `L` spells the fill-child suffix `_FL`",
        "what": "the ghost tag is named `_FL` again — BoxExtrasPump deletes it as a stray child of a master that never exists",
        "file": "Biotak/Sessions_Draw.mqh",
        "find": "         SessText(nmF + \"T\", wins[w].sU, bandHi[sl],",
        "replace": "         SessText(nmF + \"L\", wins[w].sU, bandHi[sl],   // MUTATION: _F + L = _FL",
        "expect": "P-SESS",
    },
    #--- P-SESS-09 (2026-10-20) — A WINDOW OLDER THAN THE SERIES PAINTS NOTHING.
    #--- iBarShift(exact=false) answers the OLDEST bar for any time before the
    #--- series, so a window beyond the loaded history wore that bar's H/L as its
    #--- own. The file's contract says NO object, never a fake one.
    {
        "id": "P-SESS-m",
        "gate": "regression",
        "rule": "P-SESS-09: a window wholly before the loaded history paints NO object — never the oldest bar clamped as its own H/L",
        "what": "the oldest-bar guard is gone — every window older than the series paints the oldest bar's high/low",
        "file": "Biotak/Sessions_Draw.mqh",
        "find": "   if(t2 <= oldestT) return false;",
        "replace": "   // MUTATION: no oldest-bar guard",
        "expect": "P-SESS",
    },
    #--- P-SESS-10 (2026-10-20) — THE WINDOW'S END IS EXCLUSIVE. The bar that
    #--- OPENS at t2 belongs to the next window; iBarShift(t2) counted it and every
    #--- past H/L was one bar too wide (measured on H1/H4 around a TF switch).
    {
        "id": "P-SESS-n",
        "gate": "regression",
        "rule": "P-SESS-10: the bar scan ends at t2 - 1 — the bar opening at the window end is the next window's first bar",
        "what": "the end-bar exclusion is gone — every past window counts the next window's first bar",
        "file": "Biotak/Sessions_Draw.mqh",
        "find": "   int i2 = iBarShift(NULL, 0, t2 - 1, false);",
        "replace": "   int i2 = iBarShift(NULL, 0, t2, false);   // MUTATION: end bar counted",
        "expect": "P-SESS",
    },
    #--- P-SESS-11 (2026-10-20) — A CLOSED BAR IS NOT RE-COMPARED. The extend only
    #--- read bar 0, so a bar that closed while no tick arrived (sleep, reconnect,
    #--- a stalled pump) kept its extreme out of the live window for the rest of
    #--- the session. One rescan on the first tick of a new bar answers it.
    {
        "id": "P-SESS-o",
        "gate": "regression",
        "rule": "P-SESS-11: a new bar rescans the live window — an unobserved closed bar's extreme still enters the H/L",
        "what": "the new-bar rescan is gone — the extend compares bar 0 alone again",
        "file": "Biotak/Sessions_Draw.mqh",
        "find": "      bool newBar = (bt > 0 && s_sessLiveBar[sl] > 0 && bt != s_sessLiveBar[sl]);\n      bool grew = false;\n      if(newBar)\n      {\n         double hW = 0.0, lW = 0.0;\n         datetime rEnd = (s_sessLiveE[sl] <= now) ? s_sessLiveE[sl] : now;\n         if(SessHiLoFor(s_sessLiveS[sl], rEnd, hW, lW))\n         {\n            if(hW > s_sessLiveHi[sl]) { s_sessLiveHi[sl] = hW; grew = true; }\n            if(lW < s_sessLiveLo[sl]) { s_sessLiveLo[sl] = lW; grew = true; }\n         }\n      }\n",
        "replace": "      bool grew = false;   // MUTATION: no new-bar rescan\n",
        "expect": "P-SESS",
    },
    #--- P-SESS-12 (2026-10-20) — A ZERO-BAR REBUILD IS NOT A BUILD. SessPaintAll
    #--- wipes first, so a TF switch/attach that ran before the new timeframe's
    #--- history was loaded wiped the family, painted nothing, and stored the hash:
    #--- the sessions stayed blank until the next day. Return and retry on the next
    #--- 250 ms tick instead.
    {
        "id": "P-SESS-p",
        "gate": "regression",
        "rule": "P-SESS-12: a rebuild with zero bars keeps the family and retries — never wipe, paint nothing, and store the hash",
        "what": "the zero-bar guard is gone — a TF switch can blank the sessions and mark the empty build done",
        "file": "Biotak/Sessions_Draw.mqh",
        "find": "   if(iBars(NULL, 0) <= 0) return;",
        "replace": "   // MUTATION: a zero-bar rebuild wipes",
        "expect": "P-SESS",
    },
    #--- P-UI-162 (2026-10-17) — THE RING'S ART IS THE BOX'S SIZE. MT4 blits a
    #--- bitmap 1:1 from the object's top-left and clips at XSIZE x YSIZE, so the
    #--- taper's smaller box cut the shipped 52px canvas (round tiles shipped as
    #--- cut squares). The painter must resolve per-side art through CircBgRes,
    #--- the resolver must know every side, and the glyph must keep ONE size.
    #--- Each inverse must fail 53 naming P-UI-162.
    {
        "id": "P-UI-162a",
        "gate": "regression",
        "rule": "the ring painter resolves its skin through CircBgRes at the seat's own side (canvas == box on every side)",
        "what": "CircCreateItem names a fixed 44px canvas again — the 32px outer box cuts the disc (the reported defect, P-UI-195/P-UI-162)",
        "file": "Biotak/BiotakMenu_C.mqh",
        "find": "   string bgRes = CircBgRes(s, on);   // P-UI-162: the canvas is the seat's own box size (s + 2*margin)",
        "replace": "   string bgRes = on ? \"::Files\\\\Icons\\\\circ_on.bmp\" : \"::Files\\\\Icons\\\\circ_off.bmp\";   // MUTATION: one fixed canvas for every side",
        "expect": "P-UI-162",
    },
    {
        "id": "P-UI-162b",
        "gate": "regression",
        "rule": "CircBgRes knows every side CircBtnSizeForN can return",
        "what": "the 35px case hands out the 44px canvas — the 43px box cuts the disc again",
        "file": "Biotak/BiotakMenu_Ring.mqh",
        "find": "circ_on_35.bmp",
        "replace": "circ_on.bmp",
        "expect": "P-UI-162",
    },
    {
        "id": "P-UI-162c",
        "gate": "regression",
        "rule": "the glyph keeps ONE size on create (CIRC_ICON_SIZE, no tapered box)",
        "what": "CircCreateItem seats the glyph in a CircIconSize() box — the 28px canvas is clipped at 10+ seats",
        "file": "Biotak/BiotakMenu_C.mqh",
        "find": "   CircConfigureIcon(icon, feat, on, x, y);   // P-UI-162: the glyph's box is its own 28px canvas (no taper)",
        "replace": "   CircConfigureIcon(icon, feat, on, x, y, CircIconSize());   // MUTATION: tapered glyph box",
        "expect": "P-UI-162",
    },
    {
        "id": "P-UI-162d",
        "gate": "regression",
        "rule": "the glyph keeps ONE size on the move path (CIRC_ICON_SIZE/2)",
        "what": "CircMoveItem seats the glyph by CircIconSize()/2 — a drag shifts it off the disc",
        "file": "Biotak/BiotakMenu_C.mqh",
        "find": "      ObjectSetInteger(0, CircIcon(i), OBJPROP_XDISTANCE, x - CIRC_ICON_SIZE / 2);",
        "replace": "      ObjectSetInteger(0, CircIcon(i), OBJPROP_XDISTANCE, x - CircIconSize() / 2);   // MUTATION",
        "expect": "P-UI-162",
    },
    {
        "id": "P-UI-162e",
        "gate": "regression",
        "rule": "the baker bakes one pair per taper side (circSkin(on, s))",
        "what": "circSkin loses its side parameter — every bake is the 44 canvas, every taper seat clips",
        "file": "tools/gen-th3-icons.js",
        "find": "function circSkin(on, s = 44) {",
        "replace": "function circSkin(on) {   // MUTATION: the side parameter is gone",
        "expect": "P-UI-162",
    },
    #--- P-UI-163 (2026-10-17) — A MISSING GLYPH IS REPAIRED, NEVER SKIPPED. The
    #--- (1707) frame kept four ring seats' discs with NO glyphs until a chart
    #--- change rebuilt the ring: the icon path was delete+recreate in one tick
    #--- with a silent early return, and every sync gated on ObjectFind>=0
    #--- (exists-only), so nothing ever wrote the missing icon back. Each inverse
    #--- must fail 54 naming P-UI-163.
    #--- P-UI-163c (2026-10-17, the 17:07 frame) — THE RESURRECTION CLASS: while
    #--- the fan was open a state change ran the sync loop (no g_ToolsOpen guard,
    #--- the one ring writer without it) and re-created every swept icon WITHOUT
    #--- its bg — the bare-glyph ring the user photographed; the open sweep took
    #--- icon+bg but left the badge family; a seat/cell tip could outlive its
    #--- surface. The d..h inverses below lock the cure.
    {
        "id": "P-UI-163a",
        "gate": "regression",
        "rule": "the ring's icon is created-if-missing — never delete+recreate in one tick",
        "what": "CircCreateItem re-creates its glyph every call again (delete+recreate) and drops the failed-create witness",
        "file": "Biotak/BiotakMenu_C.mqh",
        "find": "   string icon = CircIcon(i);\n   if(ObjectFind(0, icon) < 0)\n   {\n      if(!ObjectCreate(0, icon, OBJ_BITMAP_LABEL, 0, 0, 0)) { DrawStripDiagEmit(StringFormat(\"[P-UI-163] icon create FAILED seat=%d feat=%d\", i, feat)); return; }\n   }",
        "replace": "   string icon = CircIcon(i);\n   if(ObjectFind(0, icon) >= 0)\n      ObjectDelete(0, icon);\n   if(!ObjectCreate(0, icon, OBJ_BITMAP_LABEL, 0, 0, 0)) return;   // MUTATION: the same-tick delete+recreate class",
        "expect": "P-UI-163",
    },
    {
        "id": "P-UI-163b",
        "gate": "regression",
        "rule": "the per-tick refresh probes one seat and heals a hole",
        "what": "the CircHealRingStep() call leaves RefreshUIPerTick — holes wait for the next full rebuild again",
        "file": "Biotak/BiotakKit.mqh",
        "find": "   CircHealRingStep();   // P-UI-163: one seat's existence probe per tick (2 ObjectFind, 0 writes while whole)",
        "replace": "   // MUTATION: no per-tick heal probe",
        "expect": "P-UI-163",
    },
    {
        "id": "P-UI-163c",
        "gate": "regression",
        "rule": "the sync pass heals a missing glyph (it used to be the one state it skipped)",
        "what": "CircUpdateItemState drops the missing-icon heal — the pass is exists-only again",
        "file": "Biotak/BiotakMenu_C.mqh",
        "find": "      DrawStripDiagEmit(StringFormat(\"[P-UI-163] icon heal seat=%d feat=%d\", i, feat));",
        "replace": "      // MUTATION: the sync skips a missing glyph again",
        "expect": "P-UI-163",
    },
    {
        "id": "P-UI-163d",
        "gate": "regression",
        "rule": "while the fan is open the probe serves the CELLS (the ring does not exist on purpose)",
        "what": "the tools-cell heal branch leaves CircHealRingStep — cell holes are permanent again AND the probe falls through to the ring block while the fan is open (the resurrection class)",
        "file": "Biotak/BiotakMenu_D.mqh",
        "find": "   if(g_ToolsOpen)\r\n   {\r\n      if(CAT_COUNT <= 0) return;\r\n      static int s_healCell = 0;\r\n      if(s_healCell >= CAT_COUNT) s_healCell = 0;\r\n      int t = s_healCell++;\r\n      if(!SubItemOnPage(t)) return;\r\n      bool bHole = (ObjectFind(0, ToolsBg(t)) < 0 || ObjectFind(0, ToolsIcon(t)) < 0 ||\r\n                    ObjectFind(0, ToolsStar(t)) < 0);\r\n      if(!bHole && CircHasBadge(ToolFeature(t)))\r\n         bHole = (ObjectFind(0, ToolsBadgeBg(t)) < 0 || ObjectFind(0, ToolsBadgeTxt(t)) < 0);\r\n      if(bHole)\r\n      {\r\n         ToolsCreateItem(t);   // the whole cell family; on-page by the gate above\r\n         DrawStripDiagEmit(StringFormat(\"[P-UI-163] tools heal cell=%d\", t));\r\n      }\r\n      return;\r\n   }",
        "replace": "   // MUTATION: the tools-cell heal branch is gone — the probe walks into the ring block while the fan is open and cell holes stay permanent",
        "expect": "P-UI-163",
    },
    {
        "id": "P-UI-163e",
        "gate": "regression",
        "rule": "the sync pass must not rebuild the ring while the Tools fan is open (P-UI-163c, the 17:07 resurrection)",
        "what": "UpdateCircularItemStates loses BOTH guards on its ring loop — a state change while open re-creates the swept icons without their bg (the bare-glyph ring)",
        "file": "Biotak/BiotakMenu_C.mqh",
        "find": "   if(g_UI.menuVisible && !g_ToolsOpen)\n      for(int i = 0; i < CircPlacedCount(); i++)\n         CircUpdateItemState(i);",
        "replace": "   for(int i = 0; i < CircPlacedCount(); i++)   // MUTATION: the guards are gone\n      CircUpdateItemState(i);",
        "expect": "P-UI-163",
    },
    #--- P-UI-201 (2026-10-22) — THE SQUARE SEAT. Every circ_*.bmp shipped halo alpha
    #--- 29..87 (off) / 29..104 (on) at the canvas border; MT4 clips a bitmap label at
    #--- its box, so the cut glow drew four straight edges around the disc. The radial
    #--- window in circSkin must stay, and every baked border must be alpha 0.
    #--- P-UI-202 (2026-10-22, the user's 09:52 frame) — THE BARE-GLYPH SEAT: 11 of 13
    #--- seats drew no bg at all while the icon half healed (P-UI-163); the bg path
    #--- only wrote `if(ObjectFind >= 0)`, so a first-tick create loss was permanent
    #--- until a click rebuilt the ring. The heal must stay on BOTH writers.
    {
        "id": "P-UI-204a",
        "gate": "regression",
        "rule": "the train's pitch is its TILE's width (s + 2*margin); a seat pitch overlaps every bg box (P-UI-204)",
        "what": "the rail step goes back to s + CIRC_GAP while the bg box stays s + 2*margin - each 43px tile overlaps its neighbour on a 41px pitch and the row reads as a comb",
        "file": "Biotak/BiotakMenu_B.mqh",
        "find": "      int step = box + CIRC_GAP;",
        "replace": "      int step = s + CIRC_GAP;   // MUTATION: seat pitch",
        "expect": "P-UI-204",
    },
    {
        "id": "P-UI-204b",
        "gate": "regression",
        "rule": "the census rect is the FAMILY's own box, never the ring's radius (P-UI-204)",
        "what": "the census stops widening its rect by the seat boxes - a 12-seat train runs past the judge and the tail is judged by nothing",
        "file": "Biotak/BiotakMenu_RingCensus.mqh",
        "find": "      x1 = MathMax(x1, bx + bw);      y1 = MathMax(y1, by + bh);",
        "replace": "      x1 = x1;   // MUTATION: radius rect",
        "expect": "P-UI-204",
    },
    {
        "id": "P-UI-207a",
        "gate": "regression",
        "rule": "row B's rail is laid out on the TILE it paints (CIRC_BG_SIZE), never on the 44px seat (P-UI-207)",
        "what": "the row-B paint site goes back to the retired seat arithmetic - a 52px tile on a 50px pitch, tile on tile, and the fits test keeps measuring the shared owner",
        "file": "Biotak/BiotakMenu_B.mqh",
        "find": "      int dist = CircRailLead(tile) + i * CircRailStep(tile);",
        "replace": "      int dist = CIRC_ORB_SIZE / 2 + CIRC_BTN_SIZE / 2 + CIRC_GAP + i * (CIRC_BTN_SIZE + CIRC_GAP);   // MUTATION: the seat pitch",
        "expect": "P-UI-207",
    },
    {
        "id": "P-UI-208a",
        "gate": "regression",
        "rule": "a line projects on the axis it OWNS: a horizontal line borrows a time from the live window, a vertical one a price (P-UI-208)",
        "what": "the missing-axis fallback is removed - an HLINE born with TIME1=0 (every custom-price line) fails DrawAnchorXY, the press names nothing and the strip cannot open it",
        "file": "Biotak/Toolbar_A.mqh",
        "find": "   if((t <= 0 && type == OBJ_HLINE) || (!(p > 0.0) && type == OBJ_VLINE))",
        "replace": "   if(false)   // MUTATION: no missing-axis fallback",
        "expect": "P-UI-208",
    },
    {
        "id": "P-UI-209a",
        "gate": "regression",
        "rule": "the Done press reads the paint's PnlFootBtnW(\"Done\") (P-UI-209)",
        "what": "the press goes back to the 72px floor - at 150%/200% the right band of the painted Done button stops closing the card",
        "file": "Biotak/BiotakPanels_Hit.mqh",
        "find": "   int bw = PnlFootBtnW(\"Done\");",
        "replace": "   int bw = PNL_BTN_W;   // MUTATION: the fixed floor",
        "expect": "P-UI-209",
    },
    {
        "id": "P-UI-210a",
        "gate": "regression",
        "rule": "the closed dropdown paints, hits and anchors its popup from one rect (P-UI-210)",
        "what": "PnlDdRect goes back to the retired 104/190 maxLen rule - the hit grows past the painted button again and the popup opens left of its anchor",
        "file": "Biotak/BiotakPanels_Rows.mqh",
        "find": "   w=MathMax(PNL_BTN_W,50+PnlTextW(PnlDdOptText(item,row),PNL_PT_CTL));",
        "replace": "   w=MathMax(104,MathMin(190,StringLen(PnlDdOptText(item,row))*7+54));   // MUTATION: the retired second width",
        "expect": "P-UI-210",
    },
    {
        "id": "P-UI-210b",
        "gate": "regression",
        "rule": "the closed dropdown paints, hits and anchors its popup from one rect (P-UI-210)",
        "what": "the row paint computes its own dropdown rect again - the hit and the paint are two grids that drift at the next retune",
        "file": "Biotak/BiotakPanels_Build.mqh",
        "find": "         int dx,dy,dw,dh;\n         PnlDdRect(item,row,dx,dy,dw,dh);",
        "replace": "         int dw = 50 + PnlTextW(PnlDdOptText(item,row),PNL_PT_CTL);   // MUTATION: paint's own rect\n         if(dw < 72) dw = 72;\n         int dx = px + PNL_WEL - PNL_PAD_X - dw;\n         int dy = ry + PNL_CTL_Y - 1;\n         int dh = 26;",
        "expect": "P-UI-210",
    },
    {
        "id": "P-UI-213",
        "gate": "regression",
        "rule": "a dropdown-pad press is consumed without applying an option (P-UI-213)",
        "what": "the pad falls through to the first/last row again - the popup's own padding acts like an invisible option",
        "file": "Biotak/BiotakPanels_Hit.mqh",
        "find": "   if(local<0 || local>=g_PnlDdN*PNL_DD_ROW_H) return REFRESH_NONE;   // the popup's own pad is not a row",
        "replace": "   // MUTATION: the pad falls through to a row",
        "expect": "the popup padding still falls through to the first or last option",
    },
    {
        "id": "P-UI-211a",
        "gate": "regression",
        "rule": "a switch press is clamped to its own row (P-UI-211)",
        "what": "the 44px halo is measured past the 42px row again - the last 2px of a row flips the row above",
        "file": "Biotak/BiotakPanels_Hit.mqh",
        "find": "        int y0=MathMax(swY-5,ry), y1=MathMin(swY+PNL_SW_H+2*PNL_SW_PAD+5,ry+PNL_ROW_H-1);",
        "replace": "        int y0=swY-5, y1=swY+PNL_SW_H+2*PNL_SW_PAD+5;   // MUTATION: the unclamped halo",
        "expect": "P-UI-211",
    },
    {
        "id": "P-UI-212a",
        "gate": "regression",
        "rule": "a section band hit-tests the rect it paints (P-UI-212)",
        "what": "the hit goes back inside the painted band - the left/right and top/bottom edges fall through to the card grab",
        "file": "Biotak/BiotakPanels_Rows.mqh",
        "find": "      if(mx >= bx && mx <= bx+PnlCardW(it) && my >= ry && my <= ry+PNL_ROW_H-1)",
        "replace": "      if(mx >= bx+PNL_PAD_X-6 && mx <= bx+PnlCardW(it)-PNL_PAD_X+6 && my >= ry+5 && my <= ry+37)   // MUTATION: the inset band",
        "expect": "P-UI-212",
    },
    {
        "id": "P-PERF-56a",
        "gate": "regression",
        "rule": "a left-down move with no live grip asks the chart nothing (P-PERF-56)",
        "what": "the early return is removed - every left-down move pays two ChartGetInteger reads before the live-flag guards",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "   if(!s_dsGripLive && !s_dsGGripLive) return;\n",
        "replace": "   // MUTATION: no no-grip return\n",
        "expect": "P-PERF-56",
    },
    {
        "id": "P-UI-205a",
        "gate": "regression",
        "rule": "a seat name past the placed set is swept by the heal step (P-UI-205)",
        "what": "the heal step stops looking past the placed count again - the drag-time tail survives the release that shrank the ring",
        "file": "Biotak/BiotakMenu_D.mqh",
        "find": "   if(i >= n)\n   {",
        "replace": "   if(false)\n   {   // MUTATION: no tail sweep",
        "expect": "P-UI-205",
    },
    {
        "id": "P-UI-203a",
        "gate": "regression",
        "rule": "the ring is rebuilt as ONE family: the seats a shrunken mask no longer has leave with it (P-UI-203)",
        "what": "CircRebuildRing creates the live set but never sweeps the tail - removing a star leaves the old seats painted at their old places and the ring reads as two mixed grids",
        "file": "Biotak/BiotakMenu_C.mqh",
        "find": "   for(int i = n; i < RING_MAX_SEATS; i++)",
        "replace": "   for(int i = n; i < n; i++)   // MUTATION: no tail sweep",
        "expect": "P-UI-203",
    },
    {
        "id": "P-UI-201a",
        "gate": "regression",
        "rule": "the seat skin's glow fades to alpha 0 before the canvas edge (P-UI-201)",
        "what": "circSkin's radial window rmax moves out past the margin — the halo reaches the border again and the clipped disc reads as a square",
        "file": "tools/gen-th3-icons.js",
        "find": "  const rmax = r + 2.8;",
        "replace": "  const rmax = r + 4.2;   // MUTATION: the window no longer closes inside the canvas",
        "expect": "P-UI-201",
    },
    {
        "id": "P-UI-202a",
        "gate": "regression",
        "rule": "the ring's bg is created-if-missing on the state pass (P-UI-202)",
        "what": "CircUpdateItemState goes back to writing BMPFILE only when the bg exists — the bare-glyph seat can never heal again",
        "file": "Biotak/BiotakMenu_C.mqh",
        "find": "   CircEnsureBg(i, ix, iy, on);   // P-UI-202: the sheddable half now heals through the create\'s own owner",
        "replace": "   string bg = CircBg(i);\n   if(ObjectFind(0, bg) >= 0)   // MUTATION: exists-only again\n   {\n      string res = CircBgRes(CircSeatSize(i), on);\n      ObjectSetString(0, bg, OBJPROP_BMPFILE, 0, res);\n      ObjectSetString(0, bg, OBJPROP_BMPFILE, 1, res);\n   }",
        "expect": "P-UI-202",
    },
    {
        "id": "P-UI-202b",
        "gate": "regression",
        "rule": "the tools cell's bg is created-if-missing on the state pass (P-UI-202)",
        "what": "ToolsUpdateItemState goes back to the exists-only bg gate — a cell that lost its tile stays a bare glyph",
        "file": "Biotak/BiotakMenu_C.mqh",
        "find": "   ToolsEnsureBg(t, tx, ty, on);",
        "replace": "   string bg = ToolsBg(t);\n   if(ObjectFind(0, bg) >= 0)   // MUTATION: exists-only again\n   {\n      string res = SubBgRes(on);\n      ObjectSetString(0, bg, OBJPROP_BMPFILE, 0, res);\n      ObjectSetString(0, bg, OBJPROP_BMPFILE, 1, res);\n   }",
        "expect": "P-UI-202",
    },
    {
        "id": "P-UI-167a",
        "gate": "regression",
        "rule": "the seat family is born only while the ring is BUILT (P-UI-167)",
        "what": "UpdateCircularItemStates drops the menuVisible half of the guard — a drain while the menu is CLOSED re-creates all twelve glyphs with no disc under them (the reported bare-icon column)",
        "file": "Biotak/BiotakMenu_C.mqh",
        "find": "   if(g_UI.menuVisible && !g_ToolsOpen)",
        "replace": "   if(!g_ToolsOpen)   // MUTATION: the closed-menu guard is gone",
        "expect": "P-UI-167",
    },
    {
        "id": "P-UI-168a",
        "gate": "regression",
        "rule": "the ring's visibility edge names its writer (P-UI-168)",
        "what": "ToggleMenuVisibility drops its flushed witness — a whole-family sweep in the frame can no longer be attributed to the close, and the question the bare-icon report asked (which writer?) is unanswerable again",
        "file": "Biotak/BiotakMenu_D.mqh",
        "find": "   DrawStripDiagEmit(StringFormat(\"[P-UI-168] ring vis=%d tools=%d placed=%d built=%d\", (g_UI.menuVisible ? 1 : 0), (g_ToolsOpen ? 1 : 0), CircPlacedCountLive(), s_circBuiltSeats));",
        "replace": "   // MUTATION: the visibility edge has no witness again",
        "expect": "P-UI-168",
    },
    {
        "id": "P-UI-168b",
        "gate": "regression",
        "rule": "the fan's own open names itself as a ring sweeper (P-UI-168)",
        "what": "CreateToolsMenu drops its witness — its 24-name seat sweep reads as the ring having been closed, which is the mis-attribution the line was added to end",
        "file": "Biotak/BiotakMenu_C.mqh",
        "find": "   DrawStripDiagEmit(StringFormat(\"[P-UI-168] fan open=1 cells=%d placed=%d\", CAT_COUNT, CircPlacedCountLive()));",
        "replace": "   // MUTATION: the fan's open edge has no witness again",
        "expect": "P-UI-168",
    },
    {
        "id": "P-PERF-45e",
        "gate": "regression",
        "rule": "the coop wait is measured in timer periods, not milliseconds (P-PERF-45e)",
        "what": "the ledger's wait half goes back on the 40 ms frame threshold — one normal 250 ms deferral prints a [W][PERF] line again (319 of the 325 measured lines in two days)",
        "file": "Biotak/EventHandlers_Tail.mqh",
        "find": "      if(waited >= COOP_WAIT_WARN_MS || spent >= COOP_WARN_MS)",
        "replace": "      if(waited >= COOP_WARN_MS || spent >= COOP_WARN_MS)   // MUTATION: the wait half is back on the frame threshold",
        "expect": "P-PERF-45e",
    },
    {
        "id": "P-DRAW-145a",
        "gate": "regression",
        "rule": "a Gann is not a level kind (P-DRAW-145)",
        "what": "DK_GANN goes back on the level family — its colour/width/style cells write `DrawLevelsSet*`, a loop over OBJPROP_LEVELS, which a Gann sets to 0: three cells that paint nothing while their read answers the object",
        "file": "Biotak/Toolbar_A.mqh",
        "find": "           k == DK_EXPANSION || k == DK_PITCHFORK);",
        "replace": "           k == DK_EXPANSION || k == DK_GANN || k == DK_PITCHFORK);   // MUTATION: a Gann claims levels",
        "expect": "P-DRAW-145",
    },
    {
        "id": "P-DRAW-145b",
        "gate": "regression",
        "rule": "a Gann's strip offers no second colour and no body seat (P-DRAW-145)",
        "what": "the Gann row wears FILLCLR + BODY again — two extra cells for the same three object properties the colour/width/style cells own, and one act wears two cells",
        "file": "Biotak/Toolbar_A.mqh",
        "find": "      case DK_GANN:      return DRAW_CAP_COMMON;",
        "replace": "      case DK_GANN:      return DRAW_CAP_COMMON | DRAW_CAP_FILLCLR | DRAW_CAP_BODY;   // MUTATION",
        "expect": "P-DRAW-145",
    },
    {
        "id": "P-DRAW-145c",
        "gate": "regression",
        "rule": "a text wears no line width and no line style (P-DRAW-145)",
        "what": "DK_TEXT offers WIDTH and STYLE again — the terminal draws neither for OBJ_TEXT, so two cells promise an act nothing performs (C-04)",
        "file": "Biotak/Toolbar_A.mqh",
        "find": "      case DK_TEXT:      return (DRAW_CAP_COMMON & ~(DRAW_CAP_WIDTH | DRAW_CAP_STYLE)) | DRAW_CAP_FONT;",
        "replace": "      case DK_TEXT:      return DRAW_CAP_COMMON | DRAW_CAP_FONT;   // MUTATION: the two dead cells",
        "expect": "P-DRAW-145",
    },
    {
        "id": "P-DRAW-145d",
        "gate": "regression",
        "rule": "an arrow wears no line style (P-DRAW-145)",
        "what": "DK_ARROW offers STYLE again — an arrow has a code and a size, never a dash, so the cell paints nothing",
        "file": "Biotak/Toolbar_A.mqh",
        "find": "      case DK_ARROW:     return (DRAW_CAP_COMMON & ~DRAW_CAP_STYLE) | DRAW_CAP_GLYPH;",
        "replace": "      case DK_ARROW:     return DRAW_CAP_COMMON | DRAW_CAP_GLYPH;   // MUTATION: the dead dash",
        "expect": "P-DRAW-145",
    },
    {
        "id": "P-PEN-ALLa",
        "gate": "regression",
        "rule": "the shapes are served by the pen (P-PEN-ALL)",
        "what": "PenStackServes drops the shape clause - a thick dashed rect/triangle/ellipse/channel/gann keeps the native solid fold, the exact family left over after the fibo's fix",
        "file": "Biotak/DrawKindProfile.mqh",
        "find": "      case DK_ELLIPSE:\n      case DK_CYCLES:\n         p.geom = DKG_SHAPE;\n         p.pen = DKPEN_OBJECT;\n",
        "replace": "      case DK_ELLIPSE:\n      case DK_CYCLES:\n         p.geom = DKG_SHAPE;\n         p.pen = DKPEN_NONE;   // MUTATION: shapes out of the pen\n",
        "expect": "P-PEN-ALL",
    },
    {
        "id": "P-PEN-ALLb",
        "gate": "regression",
        "rule": "a shape row is born the master's own type (P-PEN-ALL)",
        "what": "the three-point create falls back to OBJ_TREND - a triangle/channel row is drawn as a diagonal line instead of the shape it copies",
        "file": "Biotak/PenStack.mqh",
        "find": "   if(nA >= 3) return ObjectCreate(0, nm, ty, 0, t0, p0, t1c, p1c, t2c, p2c);",
        "replace": "   if(nA >= 3) return ObjectCreate(0, nm, OBJ_TREND, 0, t0, p0, t1c, p1c, t2c, p2c);   // MUTATION: a line where a shape was",
        "expect": "P-PEN-ALL",
    },
    {
        "id": "P-PEN-ALLc",
        "gate": "regression",
        "rule": "the net carries the third anchor and the interior (P-PEN-ALL)",
        "what": "the heal's compare drops the third anchor - a moved corner of a triangle/channel keeps every row on the old seat until the next touch",
        "file": "Biotak/PenStack.mqh",
        "find": "      s_psNetT2[at] == t3 && s_psNetP2[at] == p3 && s_psNetFill[at] == fl)",
        "replace": "      s_psNetFill[at] == fl)   // MUTATION: the third anchor is not compared",
        "expect": "P-PEN-ALL",
    },
    {
        "id": "P-PEN-ALLd",
        "gate": "regression",
        "rule": "a fresh interior rebuilds the rows above it (P-PEN-ALL)",
        "what": "the fill transition never fires - a fill child born after the rows covers the inner half of the thickness (MT4 paints in CREATION order, P-LOG-10)",
        "file": "Biotak/PenStack.mqh",
        "find": "      if(!dropAll && shape && fillNow == 1 && fillWas == 0 && cur > 0)",
        "replace": "      if(false && shape && fillNow == 1 && fillWas == 0 && cur > 0)   // MUTATION: the interior never rebuilds the rows",
        "expect": "P-PEN-ALL",
    },
    {
        "id": "P-PEN-ALLe",
        "gate": "regression",
        "rule": "one owner for the served set (P-PEN-ALL)",
        "what": "the 2 s walk keeps its own type list again - the second owner of 'which kinds the pen serves', which is how the shapes would have been served on write and never healed",
        "file": "Biotak/DrawStrip_Pick.mqh",
        "find": "      if(PenStackServesType(ty)) PenStackHeal(nm);",
        "replace": "      if(ty == OBJ_HLINE || ty == OBJ_VLINE || ty == OBJ_TREND) PenStackHeal(nm);   // MUTATION: a second list",
        "expect": "P-PEN-ALL",
    },
    {
        "id": "P-PEN-ALLf",
        "gate": "regression",
        "rule": "a shape row carries no interior (P-PEN-ALL)",
        "what": "the row is born with MT4's own fill - it covers the very thickness it was born to draw",
        "file": "Biotak/PenStack.mqh",
        "find": "            if(shape) ObjectSetInteger(0, nm2, OBJPROP_FILL, false);",
        "replace": "            if(false) ObjectSetInteger(0, nm2, OBJPROP_FILL, false);   // MUTATION: the row fills",
        "expect": "P-PEN-ALL",
    },
    {
        "id": "P-PEN-ALLg",
        "gate": "regression",
        "rule": "the FILL switch re-states the pen in its own frame (P-PEN-ALL)",
        "what": "the switch drops the rows instead of re-stating them - the interior is born over the rows and the thickness flickers off on every fill pick",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "            PenStackSync(name, false);\r\n            break;\r\n         }\r\n         ObjectSetInteger(0, name, OBJPROP_FILL, f);",
        "replace": "            PenStackSync(name, true);\r\n            break;\r\n         }\r\n         ObjectSetInteger(0, name, OBJPROP_FILL, f);   // MUTATION: dropAll instead of a re-state",
        "expect": "P-PEN-ALL",
    },
    {
        "id": "P-SHOT-1a",
        "gate": "regression",
        "rule": "the shot's marker is flushed, not buffered (P-SHOT-1)",
        "what": "the marker loses its FileFlush - the write sits in the terminal's RAM buffer, which is the very channel this rule replaced (P-DRAW-126)",
        "file": "tests/Biotak_StripShot_Test.mq4",
        "find": "   FileFlush(h);\r\n   FileClose(h);",
        "replace": "   FileClose(h);   // MUTATION: no flush",
        "expect": "P-SHOT-1",
    },
    {
        "id": "P-SHOT-1b",
        "gate": "regression",
        "rule": "the wait reads the flushed marker and ends only on DONE/SKIP (P-SHOT-1)",
        "what": "the wait only reads the journal again - a complete capture whose journal has not been flushed reads as 'never reached DONE'",
        "file": "compile-th3.ps1",
        "find": "            if ($mtxt.StartsWith(\"DONE\") -or $mtxt.StartsWith(\"SKIP\")) { break }",
        "replace": "            if ($mtxt.Length > 0) { break }   # MUTATION: START ends the wait",
        "expect": "P-SHOT-1",
    },
    {
        "id": "P-SHOT-1c",
        "gate": "regression",
        "rule": "the DONE verdict reads the marker (P-SHOT-1)",
        "what": "the verdict goes back to the journal line alone - the false red MEASURED 2026-10-19 09:55 on a full set of PNGs",
        "file": "compile-th3.ps1",
        "find": "    if ($done.Count -eq 0 -and $markerText -notmatch '^DONE') {",
        "replace": "    if ($done.Count -eq 0) {   # MUTATION: the journal is the oracle again",
        "expect": "P-SHOT-1",
    },
    {
        "id": "P-SHOT-1d",
        "gate": "regression",
        "rule": "a stale marker is spent before the launch (P-SHOT-1)",
        "what": "an earlier run's marker survives - it answers DONE for a run that never started (the stale-frame class, P-LOG-2)",
        "file": "compile-th3.ps1",
        "find": "    if (Test-Path -LiteralPath $marker) { Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue }",
        "replace": "    if ($false) { Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue }   # MUTATION",
        "expect": "P-SHOT-1",
    },
    {
        "id": "P-SHOT-1e",
        "gate": "regression",
        "rule": "every exit door of the harness marks itself (P-SHOT-1)",
        "what": "a SKIP door leaves no marker - the build cannot tell 'the harness refused this chart' from 'the harness never ran'",
        "file": "tests/Biotak_StripShot_Test.mq4",
        "find": "      SSMarker(\"SKIP a strip was open on the chart\");\r\n      return;",
        "replace": "      return;   // MUTATION: a skip with no marker",
        "expect": "P-SHOT-1",
    },
    {
        "id": "P-SHOT-1f",
        "gate": "regression",
        "rule": "the shot budget outlasts the harness's own bar wait (P-SHOT-1)",
        "what": "the 120 s budget is back - MEASURED 2026-10-19 11:03: it cut a complete capture off at its LAST state and the build reported 'never reached DONE'",
        "file": "compile-th3.ps1",
        "find": "[int]$ShotTimeoutSec = 300",
        "replace": "[int]$ShotTimeoutSec = 120   # MUTATION: a budget the harness cannot finish in",
        "expect": "P-SHOT-1",
    },
    {
        "id": "P-SHOT-2a",
        "gate": "regression",
        "rule": "the real-pixels gate skips a file that declares itself GENERATED (P-SHOT-2)",
        "what": "the build's own stamp counts as a source again - MEASURED 2026-10-19: the 11:10:37 stamp against the 11:08:09 PNGs read 'fresh 0 - stale 33' with no source edit between",
        "file": "tools/check-shot-freshness.js",
        "find": "    if (head.indexOf('GENERATED FILE') >= 0) {",
        "replace": "    if (false) {   // MUTATION: the stamp dates the pixels",
        "expect": "P-SHOT-2",
    },
    {
        "id": "P-SHOT-2b",
        "gate": "regression",
        "rule": "the generator declares its output GENERATED (P-SHOT-2)",
        "what": "the stamp stops declaring itself generated - the skip would answer to a header the generator no longer writes",
        "file": "tools/gen-build-hash.js",
        "find": "GENERATED FILE. DO NOT EDIT.",
        "replace": "GENERATED OUTPUT. DO NOT EDIT.",
        "expect": "P-SHOT-2",
    },
    {
        "id": "P-SHOT-2c",
        "gate": "regression",
        "rule": "the head is read for the would-be winner only (P-SHOT-2)",
        "what": "every .mqh pays an open on every gate run - 460 opens where one would do",
        "file": "tools/check-shot-freshness.js",
        "find": "    if (st.mtimeMs <= best.mtime) return;",
        "replace": "    // MUTATION: every file pays a head read",
        "expect": "P-SHOT-2",
    },
    {
        "id": "P-PERF-53a",
        "gate": "regression",
        "rule": "the CPU warning prints the flag that armed the frame (P-PERF-53)",
        "what": "the warning keeps the phase and drops the cause - MEASURED 2026-10-19: 49 warnings all `levels=94..125` with no field naming why the frame ran",
        "file": "Biotak/EventHandlers_Objects.mqh",
        "find": "\" why=\" + PerfArmWhy(g_p3ArmMask) + \"]\"",
        "replace": "\"]\"   // MUTATION: the cause",
        "expect": "P-PERF-53",
    },
    {
        "id": "P-PERF-53b",
        "gate": "regression",
        "rule": "every flag that arms a frame is in the mask (P-PERF-53)",
        "what": "the TH flag drops out of the mask - one of the 38 writers of g_redrawTHLevelsNeeded goes back to the dark",
        "file": "Biotak/EventHandlers_Calc.mqh",
        "find": "|(g_redrawTHLevelsNeeded?4:0)",
        "replace": "|(0)   // MUTATION: a flag the ledger cannot name again",
        "expect": "P-PERF-53",
    },
    {
        "id": "P-PERF-53c",
        "gate": "regression",
        "rule": "the mask decodes to the name of every flag it carries (P-PERF-53)",
        "what": "the decoder loses the level-family cause - the one cause 49 of 49 measured warnings actually had",
        "file": "Biotak/GlobalVariables.mqh",
        "find": "   if((m & 16) != 0)  s += \"base \";",
        "replace": "   // MUTATION: the base-boundary cause",
        "expect": "P-PERF-53",
    },
    {
        "id": "P-UNIFY-3a",
        "gate": "regression",
        "rule": "the level pen serves the four kinds whose geometry it states (P-UNIFY-3)",
        "what": "the sync is back on the fibo pair - the pen refuses a kind it can draw",
        "file": "Biotak/FibPen.mqh",
        "find": "   if(!FibPenServesType(DrawObjectType(fibo))) return false;   // P-UNIFY-3: the pen's four kinds \u2014 the kind carries the geometry\r\n",
        "replace": "   if(DrawObjectType(fibo) != OBJ_FIBO && DrawObjectType(fibo) != OBJ_FIBOFAN) return false;   // MUTATION: the pair\r\n",
        "expect": "P-UNIFY-3",
    },
    {
        "id": "P-UNIFY-3b",
        "gate": "regression",
        "rule": "the drag preview serves the same four (P-UNIFY-3)",
        "what": "the preview is back on the fibo pair - a dragged channel keeps a pen the gesture cannot carry",
        "file": "Biotak/FibPen.mqh",
        "find": "   if(!FibPenServesType(DrawObjectType(name))) return;   // P-UNIFY-3: the four kinds whose levels the pen can state\r\n",
        "replace": "   if(DrawObjectType(name) != OBJ_FIBO && DrawObjectType(name) != OBJ_FIBOFAN) return;   // MUTATION: the pair\r\n",
        "expect": "P-UNIFY-3",
    },
    {
        "id": "P-UNIFY-3c",
        "gate": "regression",
        "rule": "the heal serves the same four (P-UNIFY-3)",
        "what": "the heal is back on the fibo pair - a channel moved or reloaded keeps a stale pen",
        "file": "Biotak/FibPen.mqh",
        "find": "   if(!FibPenServesType(ty)) return false;   // P-UNIFY-3: the heal, the pen's own four\r\n",
        "replace": "   if(ty != OBJ_FIBO && ty != OBJ_FIBOFAN) return false;   // MUTATION: the pair\r\n",
        "expect": "P-UNIFY-3",
    },
    {
        "id": "P-UNIFY-3d",
        "gate": "regression",
        "rule": "the style fold asks the served set (P-UNIFY-3)",
        "what": "the fold is back on the fibo pair - a dash pick on a served kind erases the thickness one write before the pen reads it",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "            bool penKind = FibPenServesName(name) || PenStackServes(name);   // P-UNIFY-3: the pen's own four; the other level kinds fall back to the native fold",
        "replace": "            bool penKind = (k == DK_FIBO || k == DK_FIBOFAN) || PenStackServes(name);   // MUTATION: the pair",
        "expect": "P-UNIFY-3",
    },
    {
        "id": "P-UNIFY-3e",
        "gate": "regression",
        "rule": "the pair coercion refuses the served set (P-UNIFY-3)",
        "what": "the coercion is back on the fibo pair - a served kind's memory dies and the thickness with it",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "   if(FibPenServesName(name)) return false;   // P-UNIFY-3: the pen's own four \u2014 its sync owns the visible pair; the other level kinds fall back to the native fold",
        "replace": "   if(k == DK_FIBO || k == DK_FIBOFAN) return false;   // MUTATION: the pair",
        "expect": "P-UNIFY-3",
    },
    {
        "id": "P-UNIFY-3f",
        "gate": "regression",
        "rule": "the picker offers the looks for the served set (P-UNIFY-3)",
        "what": "the style list hides the looks for the served kinds again - the pen can draw them and the strip cannot ask",
        "file": "Biotak/DrawStrip_Pick.mqh",
        "find": "   if(slot == DRAW_SLOT_STYLE) return ((int)STYLE_DASHDOTDOT + 1 + (DrawStripPenLook(k) ? DrawLookCount() : 0));   // P-UNIFY-4: native five + the registry's looks",
        "replace": "   if(slot == DRAW_SLOT_STYLE) return ((k == DK_FIBO || k == DK_FIBOFAN) ? 8 : 5);   // MUTATION: the pair",
        "expect": "P-UNIFY-3",
    },
    {
        "id": "P-UNIFY-3g",
        "gate": "regression",
        "rule": "every look caption carries its gate (P-UNIFY-3)",
        "what": "the Neon caption drops its kind gate - a row the writer refuses reads named",
        "file": "Biotak/DrawStrip_Pick.mqh",
        "find": "      if(lkName != \"\" && DrawStripPenLook(k)) return lkName;",
        "replace": "      if(lkName != \"\") return lkName;   // MUTATION: no kind gate",
        "expect": "P-UNIFY-3",
    },
    {
        "id": "P-UNIFY-3h",
        "gate": "regression",
        "rule": "the 2 s net serves the same four (P-UNIFY-3)",
        "what": "the heal walk is back on the fibo pair - a channel the terminal moves with no event keeps a stale pen",
        "file": "Biotak/DrawStrip_Pick.mqh",
        "find": "      if(FibPenServesType(ty)) FibPenHeal(nm);",
        "replace": "      if(ty == OBJ_FIBO || ty == OBJ_FIBOFAN) FibPenHeal(nm);   // MUTATION: the pair",
        "expect": "P-UNIFY-3",
    },
    {
        "id": "P-UNIFY-3i",
        "gate": "regression",
        "rule": "the geometry owner carries every served kind's own law (P-UNIFY-3)",
        "what": "the channel leaves the geometry owner - its children fall back to the horizontal law the object never draws",
        "file": "Biotak/Toolbar_A.mqh",
        "find": "   if(k == DK_FIBOCHAN)\r\n",
        "replace": "   if(false)   // MUTATION: the channel's own law\r\n",
        "expect": "P-UNIFY-3",
    },
    {
        "id": "P-UNIFY-3j",
        "gate": "regression",
        "rule": "the STYLE writer accepts a look only from the served set (P-UNIFY-3)",
        "what": "the writer accepts a look on any level kind - a tag nothing draws",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "         if(st > (int)STYLE_DASHDOTDOT && FibPenServesName(name))\r\n",
        "replace": "         if(st > (int)STYLE_DASHDOTDOT)   // MUTATION: any kind takes a look\r\n",
        "expect": "P-UNIFY-3",
    },
    {
        "id": "P-UNIFY-4b",
        "gate": "regression",
        "rule": "the kind memory keeps the look's slot and birth re-applies its tag (P-UNIFY-4b)",
        "what": "birth applies the native style but never the tag - Caps/Wash come back solid, Neon comes back with no thickness",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "      if(mlk > 0 && FibPenServesName(name)) { FibPenLookSet(name, mlk); FibPenSync(name, false); }\r\n",
        "replace": "      // MUTATION: birth forgets the tag\r\n",
        "expect": "P-UNIFY-4b",
    },
    {
        "id": "P-UNIFY-2a",
        "gate": "regression",
        "rule": "OBJ_TRENDBYANGLE maps to a kind (P-UNIFY-2)",
        "what": "the by-angle line falls back to DK_NONE - the strip opens on nothing for a drawing MT4's own toolbar offers",
        "file": "Biotak/Toolbar_A.mqh",
        "find": "      case OBJ_TRENDBYANGLE:   return DK_TANGLE;   // P-UNIFY-2",
        "replace": "      case OBJ_TRENDBYANGLE:   return DK_NONE;   // MUTATION: no kind",
        "expect": "P-UNIFY-2",
    },
    {
        "id": "P-UNIFY-2b",
        "gate": "regression",
        "rule": "the two kinds carry their cells (P-UNIFY-2)",
        "what": "the mask falls to 0 - the strip is a name with no controls, which is the report this rule was born from",
        "file": "Biotak/Toolbar_A.mqh",
        "find": "      case DK_TANGLE:\r\n      case DK_CYCLES:    return DRAW_CAP_COMMON;",
        "replace": "      case DK_TANGLE:\r\n      case DK_CYCLES:    return 0;   // MUTATION: no cells",
        "expect": "P-UNIFY-2",
    },
    {
        "id": "P-UNIFY-2c",
        "gate": "regression",
        "rule": "a trend-by-angle answers the pick on its drawn segment (P-UNIFY-2)",
        "what": "the kind leaves the segment group - the hand clicks its own line and the pick finds nothing",
        "file": "Biotak/Toolbar_Hit.mqh",
        "find": "      case DK_TANGLE:   // P-UNIFY-2: the same drawn shape as a trend",
        "replace": "      case DK_NONE:   // MUTATION: the segment group",
        "expect": "P-UNIFY-2",
    },
    {
        "id": "P-UNIFY-2d",
        "gate": "regression",
        "rule": "a cycles object is picked on its own verticals (P-UNIFY-2)",
        "what": "the cursor's period is never asked for - the pick can only test a position it guessed",
        "file": "Biotak/Toolbar_Hit.mqh",
        "find": "         if(!ChartXYToTimePrice(0, px, py, sub, tc, pc)) return false;",
        "replace": "         if(false) return false;   // MUTATION: no period under the cursor",
        "expect": "P-UNIFY-2",
    },
    {
        "id": "P-UNIFY-2e",
        "gate": "regression",
        "rule": "the by-angle line is a LINE pen kind (P-UNIFY-2)",
        "what": "the line family loses the by-angle line - it is served on the write and every row lands ON the master, painting nothing",
        "file": "Biotak/PenStack.mqh",
        "find": "   return (k == DK_LINE || k == DK_TANGLE);",
        "replace": "   return (k == DK_LINE);   // MUTATION: the by-angle line out of the family",
        "expect": "P-UNIFY-2",
    },
    {
        "id": "P-UNIFY-2f",
        "gate": "regression",
        "rule": "a cycles object is a SHAPE pen kind (P-UNIFY-2)",
        "what": "the cycles fan leaves the shape set - a thick dashed cycles object keeps the solid native pair",
        "file": "Biotak/PenStack.mqh",
        "find": "           k == DK_CHANNEL || k == DK_GANN || k == DK_CYCLES);",
        "replace": "           k == DK_CHANNEL || k == DK_GANN);   // MUTATION: cycles out of the shapes",
        "expect": "P-UNIFY-2",
    },
    {
        "id": "P-UNIFY-2g",
        "gate": "regression",
        "rule": "the pen's served TYPES carry the two kinds (P-UNIFY-2)",
        "what": "the type half of the served set loses them - the 2 s walk never heals a moved by-angle line or cycles fan",
        "file": "Biotak/DrawKindProfile.mqh",
        "find": "      case DK_ELLIPSE:\n      case DK_CYCLES:\n",
        "replace": "      case DK_ELLIPSE:\n",
        "expect": "P-UNIFY-2",
    },
    {
        "id": "P-UNIFY-2h",
        "gate": "regression",
        "rule": "the pick owner is a member of the toolbar unit (P-UNIFY-2)",
        "what": "the hub stops including Toolbar_Hit.mqh - the pick the two kinds answer is not in the build at all",
        "file": "Biotak/DrawToolbar.mqh",
        "find": "#include \"Toolbar_Hit.mqh\"",
        "replace": "// MUTATION: the pick owner is not in the unit",
        "expect": "P-UNIFY-2",
    },
    {
        "id": "P-UI-163f",
        "gate": "regression",
        "rule": "the open sweep takes the WHOLE seat family (the badge dies with its disc)",
        "what": "CreateToolsMenu deletes icon+bg only again — a live badge stays floating over the chart while the fan is open",
        "file": "Biotak/BiotakMenu_C.mqh",
        "find": "      // the badge objects (alive while the feature is on) are part of the seat, so\n      // leaving them behind was the same bare-artifact class one layer down. The\n      // restore path is already complete: DeleteToolsMenu's CircCreateItem(i) walks\n      // CircCreateBadge (P-UI-163's own create-if-missing).\n      ObjectDelete(0, CircIcon(i));\n      ObjectDelete(0, CircBg(i));\n      ObjectDelete(0, CircBadgeBg(i));\n      ObjectDelete(0, CircBadgeTxt(i));",
        "replace": "      // MUTATION: the badge family stays behind - icon+bg only again\n      ObjectDelete(0, CircIcon(i));\n      ObjectDelete(0, CircBg(i));",
        "expect": "P-UI-163",
    },
    {
        "id": "P-UI-163g",
        "gate": "regression",
        "rule": "a tip never describes a seat that is being deleted (the open edge)",
        "what": "CreateToolsMenu drops CircTipDisarm() — a shown seat tip (and a pending arm) outlives the ring it describes",
        "file": "Biotak/BiotakMenu_C.mqh",
        "find": "   // P-UI-163c: the ring is deleted below, so a shown seat tip (and a pending arm) must\n   // not outlive the seat it describes. The pinned orb banner survives.\n   CircTipDisarm();",
        "replace": "   // MUTATION: the open edge keeps a seat tip alive over the hidden ring",
        "expect": "P-UI-163",
    },
    {
        "id": "P-UI-163h",
        "gate": "regression",
        "rule": "a tip never describes a cell that is being deleted (the close edge)",
        "what": "DeleteToolsMenu drops CircTipDisarm() — a cell tip keeps describing the deleted cell",
        "file": "Biotak/BiotakMenu_C.mqh",
        "find": "   // P-UI-163c: the twin edge, a cell tip cannot describe a deleted cell.\n   CircTipDisarm();",
        "replace": "   // MUTATION: the close edge keeps a cell tip over the deleted cell",
        "expect": "P-UI-163",
    },
    #--- P-DRAW-131 (2026-10-18) - THE SAVE'S NAME FIELD IS FOCUSED AND THE SAVE
    #--- COMMITS ON EVERY EXIT. Two halves, both named by the code's own call
    #--- graph: nothing wrote OBJPROP_STATE for PnlDrawS_GE3 (the level-note
    #--- field's focus write, P-LVL-TEXT, was never copied), and
    #--- DrawPresetCaptureAndSave's only strip caller stood inside the ENDEDIT
    #--- branch - so tap-Save, type a name, tap anything wrote NOTHING (MT4 drops
    #--- an OBJ_EDIT's focus without firing ENDEDIT). Each inverse must fail 59
    #--- naming P-DRAW-131.
    {
        "id": "P-DRAW-131-a",
        "gate": "regression",
        "rule": "the more popover's Save door focuses the field it arms",
        "what": "the more door arms its field unfocused again - the user must find and click the box before Enter means anything",
        "file": "Biotak/DrawStrip_Tap.mqh",
        "find": "      DrawStripTplNameFocus();   // P-DRAW-131: the field opens FOCUSED ",
        "replace": "      // MUTATION: the more door arms its field unfocused ",
        "expect": "P-DRAW-131",
    },
    {
        "id": "P-DRAW-131-b",
        "gate": "regression",
        "rule": "the Look tab's Save row focuses the field it arms",
        "what": "the row door arms its field unfocused again - the same secret handshake, the other door",
        "file": "Biotak/DrawStrip_Tap.mqh",
        "find": "      DrawStripTplNameFocus();   // P-DRAW-131: the second door focuses the field the same way",
        "replace": "      // MUTATION: the row door arms its field unfocused",
        "expect": "P-DRAW-131",
    },
    {
        "id": "P-DRAW-131-c",
        "gate": "regression",
        "rule": "Enter writes through the ONE commit owner",
        "what": "Enter calls the file write directly again - the write has two owners and the close door can drift from Enter",
        "file": "Biotak/DrawStrip_Tap.mqh",
        "find": "      DrawStripTplCommit(\"enter\");",
        "replace": "      DrawTplSaveAs(s_dsObj, txt);   // MUTATION: Enter writes on its own",
        "expect": "P-DRAW-131",
    },
    {
        "id": "P-DRAW-131-d",
        "gate": "regression",
        "rule": "a group tap commits a pending save before the body goes",
        "what": "a fold/switch drops the armed field without committing it - the save the user asked for evaporates on a header tap",
        "file": "Biotak/DrawStrip_Tap.mqh",
        "find": "   DrawStripTplCommit(\"group\");",
        "replace": "   // MUTATION: the group tap drops the pending save",
        "expect": "P-DRAW-131",
    },
    {
        "id": "P-DRAW-131-e",
        "gate": "regression",
        "rule": "the panel close commits a pending save (the widest door)",
        "what": "every close drops the armed save silently again - the defect the report was about",
        "file": "Biotak/DrawStrip_GearB.mqh",
        "find": "   DrawStripTplCommit(\"close\");   // P-DRAW-131: every close flushes a pending save before the purge eats its field",
        "replace": "   // MUTATION: the close door drops the pending save",
        "expect": "P-DRAW-131",
    },
    {
        "id": "P-DRAW-131-f",
        "gate": "regression",
        "rule": "the close commits BEFORE the purge eats the field",
        "what": "the commit runs after the purge - the field and its typed text are already gone, so the save lands unnamed or not at all",
        "file": "Biotak/DrawStrip_GearB.mqh",
        "find": "   DrawStripTplCommit(\"close\");   // P-DRAW-131: every close flushes a pending save before the purge eats its field\r\n   DrawStripGearObjectsPurge();",
        "replace": "   DrawStripGearObjectsPurge();\r\n   DrawStripTplCommit(\"close\");   // MUTATION: the commit runs after the purge",
        "expect": "P-DRAW-131",
    },
    {
        "id": "P-DRAW-131-g",
        "gate": "regression",
        "rule": "the armed flag has ONE clearer (the commit)",
        "what": "the welded second clear is back in DrawStripGearClose - two writers of one flag (contract 9)",
        "file": "Biotak/DrawStrip_GearB.mqh",
        "find": "   DrawStripGearObjectsPurge();\r\n",
        "replace": "   DrawStripGearObjectsPurge();\r\n   s_dsTplNameArmed = false;   // MUTATION: a second clearer is back\r\n",
        "expect": "P-DRAW-131",
    },
    {
        "id": "P-DRAW-131-h",
        "gate": "regression",
        "rule": "the focus half writes OBJPROP_STATE on the field",
        "what": "the helper exists but writes nothing - the field is born unfocused exactly as in the report",
        "file": "Biotak/DrawStrip_GearA.mqh",
        "find": "   ObjectSetInteger(0, nm, OBJPROP_STATE, true);\n",
        "replace": "   // MUTATION: the field is never focused\n",
        "expect": "P-DRAW-131",
    },
    {
        "id": "P-DRAW-131-i",
        "gate": "regression",
        "rule": "the commit's one call is the save-as",
        "what": "the commit stops writing the file - the witness fires and nothing persists, the exact P-DRAW-05 failure one owner later",
        "file": "Biotak/DrawStrip_GearA.mqh",
        "find": "   int res = (s_dsObj == \"\" ? 0 : DrawTplSaveAs(s_dsObj, t));\n",
        "replace": "   int res = 0;   // MUTATION: the commit writes nothing\n",
        "expect": "P-DRAW-131",
    },
    #--- P-DRAW-131b (2026-10-18) - THE ARMED ROW'S OWN SAVE. «مینویسم ولی چیزی برا
    #--- سیو نداره که» - the focus half worked and the row still offered NOTHING TO
    #--- PRESS. Five laws, five inverses: the button's hit test reads the paint's ONE
    #--- seat owner and commits through the ONE owner; the paint seats it inside the
    #--- row; the router answers the button's native click; and the family is swept
    #--- at the arm's one end (the commit; the gear purge spends the same sweep).
    {
        "id": "P-DRAW-131-j",
        "gate": "regression",
        "rule": "the armed row's Save control commits through the one owner",
        "what": "the button the user presses is inert - the row is back to Enter-only, the exact report",
        "file": "Biotak/DrawStrip_Base.mqh",
        "find": "         if(DrawStripTplSaveHit(e, mx, ex, ew)) return true;\n",
        "replace": "         // MUTATION: the Save button is inert\n",
        "expect": "P-DRAW-131",
    },
    {
        "id": "P-DRAW-131-k",
        "gate": "regression",
        "rule": "the armed row paints its own Save control",
        "what": "the field takes the whole row again and the Save button vanishes from the paint",
        "file": "Biotak/DrawStrip_GearB.mqh",
        "find": "         dirty |= DrawStripTplSavePaint(ex + ew - sw,\r\n",
        "replace": "         // MUTATION: the Save button is never painted\r\n",
        "expect": "P-DRAW-131",
    },
    {
        "id": "P-DRAW-131-l",
        "gate": "regression",
        "rule": "the Save button's native click has its router branch",
        "what": "OBJECT_CLICK on the button reaches no commit - the press the user aims at the button itself evaporates",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "          DrawStripTplCommit(\"save\");\r\n",
        "replace": "          // MUTATION: the router's Save branch commits nothing\r\n",
        "expect": "P-DRAW-131",
    },
    {
        "id": "P-DRAW-131-m",
        "gate": "regression",
        "rule": "the arm's one end sweeps the Save family (the commit)",
        "what": "the committed row leaves its Save button on the plate - a control for an arm that is over",
        "file": "Biotak/DrawStrip_GearA.mqh",
        "find": "   DrawStripTplSaveSweep();   // P-DRAW-131b: the armed row's Save control dies with the arm\n",
        "replace": "   // MUTATION: the arm ends without sweeping its Save control\n",
        "expect": "P-DRAW-131",
    },
    {
        "id": "P-DRAW-131-n",
        "gate": "regression",
        "rule": "the sweep drops every seat of the family (the label included)",
        "what": "the Save label outlives its row on the plate - a word with no button under it",
        "file": "Biotak/DrawStrip_GearA.mqh",
        "find": "   if(ObjectFind(0, sb + \"T\") >= 0) { ObjectDelete(0, sb + \"T\"); dirty = true; }\n",
        "replace": "   // MUTATION: the Save label survives its arm\n",
        "expect": "P-DRAW-131",
    },
    #--- P-DRAW-132 (2026-10-18) - THE NAMED TEMPLATE RACK. The TradingView shape
    #--- («سیو کنم ... به راحیت هر کدوم خواستم فعال کنم») replaced P-DRAW-02's fixed
    #--- six-slot rack. Seven laws, seven inverses: the put refuses a full rack and
    #--- replaces by name; the delete compacts; the name lookup is case-insensitive;
    #--- an apply batches its nine writes into ONE file pass; an empty label gets the
    #--- "My N" fallback; the apply leaves a colour the template never carried alone;
    #--- and boot seeds once, migrates P-DRAW-02's file once and never runs it twice.
    {
        "id": "P-DRAW-132-a",
        "gate": "regression",
        "rule": "an apply writes the whole look with ONE file pass (the batch hold)",
        "what": "the hold is gone - nine slot writes pay nine full-file passes per apply",
        "file": "Biotak/Toolbar_Tpl.mqh",
        "find": "   s_dkTplHold++;\r\n",
        "replace": "   // MUTATION: the batch hold is gone\r\n",
        "expect": "P-DRAW-132",
    },
    {
        "id": "P-DRAW-132-b",
        "gate": "regression",
        "rule": "a full rack REFUSES (0) instead of silently eating the oldest template",
        "what": "a full rack overwrites the oldest row again - the silent loss the rewrite exists against",
        "file": "Biotak/Toolbar_Tpl.mqh",
        "find": "      if(DrawTplCount(k) >= DRAW_TPL_MAX) return 0;\r\n",
        "replace": "      // MUTATION: a full rack overwrites the oldest again\r\n",
        "expect": "P-DRAW-132",
    },
    {
        "id": "P-DRAW-132-c",
        "gate": "regression",
        "rule": "a delete COMPACTS - no hole survives a removal",
        "what": "the rows after the hole stay where they are, so every index past it lies",
        "file": "Biotak/Toolbar_Tpl.mqh",
        "find": "   for(int i = slot; i < n - 1; i++)\r\n",
        "replace": "   for(int i = 0; i < 0; i++)   // MUTATION: a hole survives a delete\r\n",
        "expect": "P-DRAW-132",
    },
    {
        "id": "P-DRAW-132-d",
        "gate": "regression",
        "rule": "the name lookup is case-insensitive - one template, one name",
        "what": "the lookup is case-sensitive again, so 'My Box' and 'my box' stack up as two rows",
        "file": "Biotak/Toolbar_Tpl.mqh",
        "find": "      if(StringCompare(s_dkTpl[k][i].name, nm, false) == 0) return i;\r\n",
        "replace": "      if(s_dkTpl[k][i].name == nm) return i;   // MUTATION: case-sensitive again\r\n",
        "expect": "P-DRAW-132",
    },
    {
        "id": "P-DRAW-132-e",
        "gate": "regression",
        "rule": "P-DRAW-02's file is migrated exactly once on the first run",
        "what": "the legacy file is abandoned unread - every user template of the old build is lost on upgrade",
        "file": "Biotak/Toolbar_Tpl.mqh",
        "find": "   if(FileIsExist(DRAW_TPL_LEGACY)) DrawTplMigrate();\r\n",
        "replace": "   // MUTATION: the legacy file is abandoned, not migrated\r\n",
        "expect": "P-DRAW-132",
    },
    {
        "id": "P-DRAW-132-f",
        "gate": "regression",
        "rule": "an empty label becomes a FINDABLE name (\"My N\")",
        "what": "an unnamed row is stored - a template the user cannot find in any list",
        "file": "Biotak/Toolbar_Tpl.mqh",
        "find": "   if(nm == \"\") nm = \"My \" + IntegerToString(DrawTplCount(k) + 1);\r\n",
        "replace": "   // MUTATION: an empty name survives unnamed\r\n",
        "expect": "P-DRAW-132",
    },
    {
        "id": "P-DRAW-132-g",
        "gate": "regression",
        "rule": "the apply leaves a colour the template never carried alone (presence bit honoured)",
        "what": "the apply writes clrNONE's masked field - a colour nobody chose comes back as white",
        "file": "Biotak/Toolbar_Tpl.mqh",
        "find": "   if((int)L.clr >= 0)\r\n      DrawSlotWrite(name, DRAW_SLOT_COLOR, (double)(int)L.clr);\r\n",
        "replace": "   DrawSlotWrite(name, DRAW_SLOT_COLOR, (double)(int)L.clr);   // MUTATION: a white nobody chose\r\n",
        "expect": "P-DRAW-132",
    },
    #--- P-DRAW-133 (2026-10-18) - NO DEAD RUNG IN THE GEAR ROUTER. A stray
    #--- `return true;` stood between DrawStripGearRowTap's kind-4 and kind-5 rungs:
    #--- kinds 5/6/7/8 painted, hit-tested and answered nothing. The inverse is the
    #--- exact line, back where it stood.
    {
        "id": "P-DRAW-133-a",
        "gate": "regression",
        "rule": "no statement sits between the kind-4 rung and the kind-5 rung",
        "what": "the stray return is back - the level-set, visibility, learn-current and glyph rows answer nothing (the reported defect)",
        "file": "Biotak/DrawStrip_Tap.mqh",
        "find": "   if(kind == 5)",
        "replace": "   return true;   // MUTATION: the dead return is back\r\n   if(kind == 5)",
        "expect": "P-DRAW-133",
    },
    {
        "id": "P-DRAW-133-b",
        "gate": "regression",
        "rule": "the learn-current row (kind 7) has a live rung",
        "what": "the kind-7 rung is renamed away - a painted row with no branch",
        "file": "Biotak/DrawStrip_Tap.mqh",
        "find": "   if(kind == 7)",
        "replace": "   if(kind == -7)   // MUTATION: the learn-current row answers nothing",
        "expect": "P-DRAW-133",
    },
    #--- P-DRAW-134 (2026-10-18) - DELETE IS A BUTTON, NOT A MODIFIER. User order:
    #--- «شیبف کلکی بردار بجاش یک دکمه حذف برای هر کدوم بزار» - the SHIFT+click door on
    #--- template rows is retired and every row wears its own ✕ (button + glyph, on
    #--- the row roster's own entry, answered by its own router branch, deleting
    #--- through the ONE body DrawStripTplRowDelete). Seven inverses: the modifier
    #--- comes back, the ✕ is never painted, its seat moves, its branch or call goes
    #--- inert, the sweep forgets it, and the tooltip promises the dead door.
    {
        "id": "P-DRAW-134-a",
        "gate": "regression",
        "rule": "the row's ✕ answers on its OWN router branch",
        "what": "the ✕ is inert - the click the user aims at the delete button falls through to the row's apply, the exact report",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "         { DrawStripPickTapDel(rd); return DrawStripClickFamily(); }",
        "replace": "         { return DrawStripClickFamily(); }   // MUTATION: the ✕ is inert",
        "expect": "P-DRAW-134",
    },
    {
        "id": "P-DRAW-134-b",
        "gate": "regression",
        "rule": "only a roster TEMPLATE row wears a ✕",
        "what": "the gate is hard-off - no template row ever paints its delete button (the reported defect: no visible door to delete from)",
        "file": "Biotak/DrawStrip_Paint.mqh",
        "find": "         bool isTpl = (s_dsPicker == DSTRIP_MORE && s_dsMoreKind[r] == DSTRIP_MK_PRESET);",
        "replace": "         bool isTpl = false;   // MUTATION: the row never wears its ✕",
        "expect": "P-DRAW-134",
    },
    {
        "id": "P-DRAW-134-c",
        "gate": "regression",
        "rule": "the ✕'s seat is the row's far end, from the ONE width owner",
        "what": "the button moves over the row's own label - text and control fight for one seat",
        "file": "Biotak/DrawStrip_Paint.mqh",
        "find": "            int dx = px + contentW - DSTRIP_PICK_DEL_W;",
        "replace": "            int dx = px;   // MUTATION: the ✕ sits over the label",
        "expect": "P-DRAW-134",
    },
    {
        "id": "P-DRAW-134-d",
        "gate": "regression",
        "rule": "the ✕ deletes through the ONE body",
        "what": "the tap door returns before the delete - a control that paints, hits, and acts at nothing (P-DRAW-84's class)",
        "file": "Biotak/DrawStrip_Tap.mqh",
        "find": "   if(!DrawStripTplRowDelete(s_dsMoreArg[row])) return false;",
        "replace": "   return false;   // MUTATION: the ✕ deletes nothing",
        "expect": "P-DRAW-134",
    },
    {
        "id": "P-DRAW-134-e",
        "gate": "regression",
        "rule": "the MODIFIER delete stays out of the apply path",
        "what": "the SHIFT door returns - the user explicitly ordered delete to be a visible button, never a modifier",
        "file": "Biotak/DrawStrip_Paint.mqh",
        "find": "   if(row < 0 || row >= DRAW_TPL_MAX || DrawTplName(k, row) == \"\") return false;\r\n   DrawStripUndoPush();",
        "replace": "   if(UIMagnetModifierDown()) return false;   // MUTATION: the SHIFT door returns\r\n   if(row < 0 || row >= DRAW_TPL_MAX || DrawTplName(k, row) == \"\") return false;\r\n   DrawStripUndoPush();",
        "expect": "P-DRAW-134",
    },
    {
        "id": "P-DRAW-134-f",
        "gate": "regression",
        "rule": "the open popover's row sweep takes the ✕ family",
        "what": "the button outlives the row it belonged to - a ✕ floating over whatever moved up into the dead row's seat",
        "file": "Biotak/DrawStrip_Paint.mqh",
        "find": "            if(ObjectFind(0, pd) >= 0) { ObjectDelete(0, pd); dirty = true; }",
        "replace": "            // MUTATION: the ✕ button survives its row",
        "expect": "P-DRAW-134",
    },
    {
        "id": "P-DRAW-134-g",
        "gate": "regression",
        "rule": "the tooltip names the door that IS there",
        "what": "the row promises the retired Shift+click again - a hint for a door that does not exist",
        "file": "Biotak/DrawStrip_GearA.mqh",
        "find": "             \" — click to apply the whole look\" + scope + \" — the row's ✕ removes it\";",
        "replace": "             \" — click to apply the whole look\" + scope + \" — Shift+click deletes it\";   // MUTATION",
        "expect": "P-DRAW-134",
    },
    #--- P-DRAW-135 (2026-10-18) - THE TEMPLATE CARRIES THE LEVELS. User order:
    #--- «وقتی تمپلت ذخیره میشه باید با همه چیزش ذخیره بشه دیگه ... با سایر ارزها ...
    #--- باید درست باشه». For the level family the LEVELS ARE THE DRAWING, and the
    #--- nine-value look never carried them. The reserved row (100+slot), its read
    #--- order, the capture, the restore, the delete's compaction, the encoder's two
    #--- separator trades and the toggle's LVLTOG witness each get their inverse back.
    {
        "id": "P-DRAW-135-a",
        "gate": "regression",
        "rule": "the saver writes the level row to the file",
        "what": "the level set never reaches the file - a saved fibo template dies at the next attach while the rack looks saved",
        "file": "Biotak/Toolbar_Tpl.mqh",
        "find": "            FileWrite(h, (int)k, DRAW_TPL_LVL_ROW + i, s_dkTpl[k][i].lvl, \"0\", \"0\");",
        "replace": "            // MUTATION: the level set never reaches the file",
        "expect": "P-DRAW-135",
    },
    {
        "id": "P-DRAW-135-b",
        "gate": "regression",
        "rule": "the loader answers the level rows",
        "what": "the reserved rows are dropped at the load - a saved level set comes back empty",
        "file": "Biotak/Toolbar_Tpl.mqh",
        "find": "      { s_dkTpl[k][i - DRAW_TPL_LVL_ROW].lvl = nm; continue; }",
        "replace": "      { continue; }   // MUTATION: level rows dropped at the load",
        "expect": "P-DRAW-135",
    },
    {
        "id": "P-DRAW-135-c",
        "gate": "regression",
        "rule": "the save captures the level family's own truth",
        "what": "the save stores the nine values alone again - «با همه چیزش ذخیره بشه» regressed to a default fibo on every chart",
        "file": "Biotak/Toolbar_Tpl.mqh",
        "find": "   string lv = DrawTplLevelsOf(name);",
        "replace": "   string lv = \"\";   // MUTATION: the save drops the level set",
        "expect": "P-DRAW-135",
    },
    {
        "id": "P-DRAW-135-d",
        "gate": "regression",
        "rule": "the apply restores the level set",
        "what": "the apply writes the nine slots and never the levels - an applied fibo template comes back default-leveled",
        "file": "Biotak/Toolbar_Tpl.mqh",
        "find": "   if(s_dkTpl[k][slot].lvl != \"\")\r\n      DrawTplLevelsTo(name, s_dkTpl[k][slot].lvl);",
        "replace": "   // MUTATION: the apply never restores the level set",
        "expect": "P-DRAW-135",
    },
    {
        "id": "P-DRAW-135-e",
        "gate": "regression",
        "rule": "a delete moves the level set with its row",
        "what": "the compaction leaves the hole's level set behind - the row below wears the deleted fibo's levels",
        "file": "Biotak/Toolbar_Tpl.mqh",
        "find": "      s_dkTpl[k][i].lvl   = s_dkTpl[k][i + 1].lvl;",
        "replace": "      // MUTATION: the level set does not move with its row",
        "expect": "P-DRAW-135",
    },
    {
        "id": "P-DRAW-135-f",
        "gate": "regression",
        "rule": "the encoder trades the CSV field separator out of the notes",
        "what": "one typed ';' note splits the line - the whole rack file corrupts on the next save",
        "file": "Biotak/Toolbar_Tpl.mqh",
        "find": "      StringReplace(t, \";\", \",\");",
        "replace": "      // MUTATION: the separator rides the note into the file",
        "expect": "P-DRAW-135",
    },
    {
        "id": "P-DRAW-135-g",
        "gate": "regression",
        "rule": "the level toggle witnesses on the flushed channel",
        "what": "the LVLTOG line loses its action field - «کم و زیاد نمیشه» is unprovable again",
        "file": "Biotak/DrawStrip_Tap.mqh",
        "find": "                     \" act=\" + (at >= 0 ? \"del\" : \"add\") + \" n=\" + IntegerToString(n) +",
        "replace": "                     \" act=\" + \"?\" + \" n=\" + IntegerToString(n) +   // MUTATION",
        "expect": "P-DRAW-135",
    },
    #--- The UI/UX hunt of 2026-10-20. Each inverse puts ONE defect back and the
    #--- owning gate must fail WITH ITS OWN MESSAGE (the rule is only gated if the
    #--- inverse fails - contract 6.14).
    {
        "id": "P-DRAW-136",
        "gate": "regression",
        "rule": "the Look tab's page walk wears its OWN row kind",
        "what": "the nav row wears the group header's number again - the header's branch swallows it",
        "file": "Biotak/DrawStrip_GearA.mqh",
        "find": "      if(tpages > 1) DrawStripGearRow(DSTRIP_GRK_TPLNAV, 0, y);",
        "replace": "      if(tpages > 1) DrawStripGearRow(9, 0, y);   // MUTATION: the group header's number",
        "expect": "nav row",
    },
    {
        "id": "P-UI-169",
        "gate": "regression",
        "rule": "a tool that owns NO card answers -1 (the hold opens nobody else's card)",
        "what": "the card-less tools fall through the identity fallback again",
        "file": "Biotak/BiotakMenu_A.mqh",
        "find": "   if(feat == CIR_HRAY || feat == CIR_PATH || feat == CIR_SCALE || feat == CIR_HIDE) return -1;",
        "replace": "   if(feat == CIR_HRAY || feat == CIR_PATH || feat == CIR_SCALE || feat == CIR_HIDE) return feat;   // MUTATION",
        "expect": "FeaturePanel stopped answering",
    },
    {
        "id": "P-UI-170",
        "gate": "regression",
        "rule": "the strip's own text fields own the keyboard",
        "what": "the KEYDOWN guard stops asking the fields' STATE - a letter typed into a name fires a hotkey",
        "file": "Biotak/EventHandlers_Router.mqh",
        "find": "        if(g_PalHexFocus || g_BkTextFocus || AnyStripTextFieldFocused()) return;",
        "replace": "        if(g_PalHexFocus || g_BkTextFocus) return;   // MUTATION",
        "expect": "KEYDOWN guard stopped asking",
    },
    {
        "id": "P-UI-171",
        "gate": "regression",
        "rule": "the DUAL row MEASURES its last caption",
        "what": "the width owner goes back to the literal 12 - the last caption crosses the card edge",
        "file": "Biotak/BiotakPanels_Rows.mqh",
        "find": "      w = (i == cells-1) ? a + PNL_DUAL_SW_W + 6 + PnlTextW(PnlDualCapAt(item,row,i),PNL_PT_CAP) + 12 : b;",
        "replace": "      w = (i == cells-1) ? a + PNL_DUAL_SW_W + 6 + 12 : b;   // MUTATION",
        "expect": "DUAL width stopped measuring",
    },
    {
        "id": "P-UI-172",
        "gate": "regression",
        "rule": "a text anchor is clipped to NOW (a future time has no pixel)",
        "what": "the session labels are anchored at the window's future END again",
        "file": "Biotak/Sessions_Draw.mqh",
        "find": "            SessText(SessWindowName(sl, wins[wLin].stamp, \"HIL\"), SessLabelAnchor(wins[wLin].eU, now), wins[wLin].hi,",
        "replace": "            SessText(SessWindowName(sl, wins[wLin].stamp, \"HIL\"), wins[wLin].eU, wins[wLin].hi,   // MUTATION",
        "expect": "stopped using the anchor owner",
    },
    {
        "id": "P-UI-173",
        "gate": "regression",
        "rule": "the sessions' hash carries the chart period (the numbers are timeframe-derived)",
        "what": "the period leaves the hash - a switch leaves the session high/low on the old timeframe",
        "file": "Biotak/Sessions_Draw.mqh",
        "find": "   h = h * 31 + (long)Period();",
        "replace": "   // MUTATION: the period is gone",
        "expect": "sessions hash lost the chart period",
    },
    {
        "id": "P-UI-174",
        "gate": "regression",
        "rule": "the UI-state reset never takes the PLACED SURFACES with it",
        "what": "the reset sweeps the home keys again - the surfaces jump to the default on the next attach",
        "file": "Biotak/BiotakMenu_A.mqh",
        "find": "      const bool keep = (StringFind(name, \"_HOME_\") >= 0 || StringFind(name, \"STAR\") >= 0 ||",
        "replace": "      const bool keep = (false ||   // MUTATION: the places go with the reset",
        "expect": "UI-state reset wipes the placed surfaces",
    },
    {
        "id": "P-UI-190",
        "gate": "regression",
        "rule": "the UI-state reset never takes the OV_ settings or the panel places",
        "what": "the reset sweeps OV_ and PNL_ again - a version bump reverts every panel-edited setting",
        "file": "Biotak/BiotakMenu_A.mqh",
        "find": "                         StringSubstr(name, len, 3) == \"OV_\" || StringSubstr(name, len, 4) == \"PNL_\" ||",
        "replace": "                         false ||   // MUTATION: the settings go with the reset",
        "expect": "UI-state reset wipes the placed surfaces, their panel positions or the OV_ settings",
    },
    {
        "id": "P-UI-176",
        "gate": "regression",
        "rule": "the merged colour is ONE cell (one row, one switch, one count)",
        "what": "the Row group lists the merged colour twice again",
        "file": "Biotak/DrawStrip_GearA.mqh",
        "find": "         if(mergedRow && s == DRAW_SLOT_COLOR) continue;   // folded into the FILLCLR seat",
        "replace": "         // MUTATION: the merged colour is listed twice",
        "expect": "merged colour twice",
    },
    {
        "id": "P-UI-177",
        "gate": "regression",
        "rule": "the Levels digest states the levels the drawing SHOWS",
        "what": "the digest states the LIST size again - 'No levels' leaves it claiming 9 levels",
        "file": "Biotak/DrawStrip_GearB.mqh",
        "find": "      int n = DrawLevelCount(s_dsObj);",
        "replace": "      int n = DrawStripGearLevelCount();   // MUTATION: the list size",
        "expect": "Levels digest states the LIST size",
    },
    {
        "id": "P-UI-178",
        "gate": "regression",
        "rule": "the accordion reserves the headers that close it",
        "what": "the level list reserves only the headers ABOVE - two groups are never built",
        "file": "Biotak/DrawStrip_GearA.mqh",
        "find": "      int room = DSTRIP_GLIST_MAX - 2 - below - s_dsGRN;   // the two rows below are not optional",
        "replace": "      int room = DSTRIP_GLIST_MAX - 2 - s_dsGRN;   // MUTATION: the closing headers are not reserved",
        "expect": "stopped reserving the closing headers",
    },
    {
        "id": "P-UI-179",
        "gate": "regression",
        "rule": "the chips ride the swatch strip's line, not the caption's",
        "what": "the chip strip is drawn on the caption's line again - the caption lies on the swatches",
        "file": "Biotak/BiotakPanels_Rows.mqh",
        "find": "   cy=PnlRowY(item,row,g_PnlY[item])+PNL_QSW_Y;",
        "replace": "   cy=PnlRowY(item,row,g_PnlY[item]);   // MUTATION",
        "expect": "chips row paints its strip on the caption",
    },
    {
        "id": "P-UI-180",
        "gate": "regression",
        "rule": "the path's preview dies with EVERY deinit reason",
        "what": "the preview survives a timeframe switch again - a stray line stays on the chart",
        "file": "Biotak/PathTool.mqh",
        "find": "   PathSessionClear();\n   if(reason == REASON_REMOVE)",
        "replace": "   // MUTATION: the preview survives\n   if(reason == REASON_REMOVE)",
        "expect": "path's preview survives a timeframe switch",
    },
    {
        "id": "P-UI-181",
        "gate": "regression",
        "rule": "the count digit is centred in its pill and paints above it",
        "what": "the digit is off-centre and paints under its own pill again",
        "file": "Biotak/DrawStrip_GearB.mqh",
        "find": "         dirty |= DrawStripLblAt(clbl, x0 + w - DSTRIP_SEC_CNT_W / 2 - PnlTextW(cs, lpt) / 2,",
        "replace": "         dirty |= DrawStripLblAt(clbl, x0 + w - DSTRIP_SEC_CNT_W / 2 - 2 + PnlTextW(cs, lpt) / 2,   // MUTATION",
        "expect": "count digit is off-centre",
    },
    {
        "id": "P-UI-182",
        "gate": "regression",
        "rule": "a witness goes through the FLUSHED channel, never Print",
        "what": "the row-ceiling witness is a Print again - the journal buffers it",
        "file": "Biotak/DrawStrip_GearA.mqh",
        "find": "         DrawStripDiagEmit(\"[drawstrip] gear row ceiling reached (\" + IntegerToString(DSTRIP_GLIST_MAX) +",
        "replace": "         Print(\"[drawstrip] gear row ceiling reached (\" + IntegerToString(DSTRIP_GLIST_MAX) +   // MUTATION",
        "expect": "row-ceiling witness is a `Print`",
    },
    {
        "id": "P-UI-183",
        "gate": "regression",
        "rule": "the Horizontal Ray's witness is the flushed file",
        "what": "the ray's witness is the journal again - «the ray does nothing» is unprovable",
        "file": "Biotak/HRayTool.mqh",
        "find": "void HRayWitness(const string line) { DrawStripDiagEmit(\"[HRay] \" + line); }",
        "replace": "void HRayWitness(const string line) { Print(\"[HRay] \" + line); }   // MUTATION",
        "expect": "Horizontal Ray's witness is the journal",
    },
    {
        "id": "P-UI-185",
        "gate": "regression",
        "rule": "a hotkey is ONE key, and the conflict is named at the attach",
        "what": "the matcher answers the FIRST CHARACTER again - 'Ctrl+T' fires as plain T",
        "file": "Biotak/EventHandlers_Tail.mqh",
        "find": "    if(StringLen(k) != 1) return false;   // not one key: the terminal cannot deliver it",
        "replace": "    // MUTATION: the first character answers",
        "expect": "hotkey matcher answers the FIRST CHARACTER",
    },
    {
        "id": "P-UI-187",
        "gate": "regression",
        "rule": "the trade card has a WIDTH budget beside its height budget",
        "what": "the width budget is gone - the wide leg row runs off a narrow chart",
        "file": "Biotak/Labels_A.mqh",
        "find": "   int availW = (chartW > 0) ? MathMax(60, chartW - rightEdge - 8) : 0;",
        "replace": "   int availW = 0;   // MUTATION: no width budget",
        "expect": "trade card has no width budget",
    },
    {
        "id": "P-UI-188",
        "gate": "regression",
        "rule": "the palette keeps its FOOT on the chart",
        "what": "the popup keeps its top again - the Done button falls off the bottom",
        "file": "Biotak/BiotakPanels_PalA.mqh",
        "find": "    int maxY=ch-PalFootY()-PAL_FOOT-8;",
        "replace": "    int maxY=ch-h-16;   // MUTATION",
        "expect": "palette keeps its top on a short chart",
    },
    {
        "id": "P-UI-161e",
        "gate": "regression",
        "rule": "a CREATE reads the LIVE seat count, never the frozen paint",
        "what": "the Tools restore lays seats on the frozen built count again instead of rebuilding the ring from the live mask - a close with the orb press on restores the old grid",
        "file": "Biotak/BiotakMenu_C.mqh",
        "find": "   if(restoreRing && g_UI.menuVisible) CircRebuildRing();   // P-UI-203: the shrunken mask's tail leaves with it",
        "replace": "   if(restoreRing && g_UI.menuVisible)\n      for(int i = 0; i < s_circBuiltSeats; i++) CircCreateItem(i);   // MUTATION: frozen restore",
        "expect": "no longer rebuilds the ring from the LIVE mask",
    },
    {
        "id": "P-UI-161f",
        "gate": "regression",
        "rule": "a CREATE notes the LIVE set before it lays a seat",
        "what": "the note lands after the create - CircLayout reads the frozen n and the new seats overlap the old ones",
        "file": "Biotak/BiotakMenu_C.mqh",
        "find": "   CircNoteBuilt(); int n = CircPlacedCount();   // P-UI-206: the count the LAYOUT uses, not the live one\n   for(int i = n; i < RING_MAX_SEATS; i++)\n   {\n      ObjectDelete(0, CircIcon(i)); ObjectDelete(0, CircBg(i));\n      ObjectDelete(0, CircBadgeBg(i)); ObjectDelete(0, CircBadgeTxt(i));\n   }\n   for(int i = 0; i < n; i++) CircCreateItem(i);",
        "replace": "   int n = CircPlacedCount();   // MUTATION: the note lands after the create\n   for(int i = n; i < RING_MAX_SEATS; i++)\n   {\n      ObjectDelete(0, CircIcon(i)); ObjectDelete(0, CircBg(i));\n      ObjectDelete(0, CircBadgeBg(i)); ObjectDelete(0, CircBadgeTxt(i));\n   }\n   for(int i = 0; i < n; i++) CircCreateItem(i);\n   CircNoteBuilt();",
        "expect": "CircRebuildRing creates before noting the LIVE count",
    },
    {
        "id": "P-UI-167b",
        "gate": "regression",
        "rule": "the ring click tail is a birth path, not a paint",
        "what": "the click tail repaints a seat the action just hid - one bare glyph over a closed menu",
        "file": "Biotak/BiotakMenu_D.mqh",
        "find": "   if(g_UI.menuVisible && !g_ToolsOpen)\n   {\n      CircUpdateItemState(idx);",
        "replace": "   if(true)   // MUTATION: the tail births over a closed menu\n   {\n      CircUpdateItemState(idx);",
        "expect": "the ring click tail repaints a seat the action just hid again",
    },
    {
        "id": "P-UI-189",
        "gate": "regression",
        "rule": "a built shape is noted on every exit",
        "what": "the non-paged grid exits without its note - every release rebuilds all 16 cells",
        "file": "Biotak/BiotakMenu_B.mqh",
        "find": "      SubNoteBuilt();\n      return;",
        "replace": "      return;   // MUTATION: no built-shape note",
        "expect": "the non-paged grid exits without SubNoteBuilt",
    },
    {
        "id": "P-UI-191",
        "gate": "regression",
        "rule": "a kept key is read before either branch saves (the STAR mask)",
        "what": "the mask is read after the version branch - the reset path saves CIRC_STAR_DEFAULT over the kept key",
        "file": "Biotak/BiotakMenu_A.mqh",
        "find": "   g_CircStarMask = CircStarLoad(GetGVName(\"STAR\"));   // P-UI-191: read BEFORE either branch can save",
        "replace": "   // MUTATION: the mask is read after the branch",
        "expect": "star mask is read AFTER the version branch",
    },
    {
        "id": "P-UI-192",
        "gate": "regression",
        "rule": "a starred TOOL's ring seat runs the tool's own body, never nothing",
        "what": "RingFeatureClick stops delegating the seven tool codes - the seat answers REFRESH_NONE again (the shipped defect)",
        "file": "Biotak/BiotakMenu_D.mqh",
        "find": "   if(feat == CIR_PIN || feat == CIR_STEP_OVERRIDE || feat == CIR_GENERAL || feat == CIR_HRAY || feat == CIR_PATH || feat == CIR_SCALE || feat == CIR_HIDE)",
        "replace": "   if(false)   // MUTATION: the tool delegation removed",
        "expect": "P-UI-192",
    },
    {
        "id": "P-UI-193",
        "gate": "regression",
        "rule": "the C key is the PIN cell's twin toggle (arm / leave)",
        "what": "the C key arms unconditionally again - the ON state can only be left with ESC (the shipped defect)",
        "file": "Biotak/EventHandlers_Router.mqh",
        "find": "            bool pinActive = (g_customPriceLineCreated || g_waitingForCustomPriceClick ||",
        "replace": "            bool pinActive = false;   // MUTATION: the C key arms unconditionally",
        "expect": "P-UI-193",
    },
    {
        "id": "P-UI-194",
        "gate": "regression",
        "rule": "F masks EVERY prefixed object, not just the cache's whitelist",
        "what": "the hide pass returns to the cache-only walk - unregistered families survive F again (the shipped defect)",
        "file": "Biotak/EventHandlers_CustomPrice.mqh",
        "find": "    VisibilityHideAllLegacyScan();",
        "replace": "    // MUTATION: the full-prefix sweep removed",
        "expect": "P-UI-194",
    },
    {
        "id": "P-LBL-13",
        "gate": "regression",
        "rule": "the TRex superscript is the structure candle's live TrueRange, structure = two fractal rungs up",
        "what": "the superscript falls back to ONE rung (M15 reads H1's high-low) - the shipped 38.3p defect",
        "file": "Biotak/Labels_A.mqh",
        "find": "int str2Idx = TradePlanLadderIndex(Period()) + 2;",
        "replace": "int str2Idx = TradePlanLadderIndex(Period()) + 1;  // MUTATION",
        "expect": "P-LBL-13",
    },
    {
        "id": "P-ANCHOR-LAST",
        "gate": "regression",
        "rule": "the newest committed LegMeasure/BaseKnot owns the one ATR anchor",
        "what": "a committed LegMeasure stops publishing its anchor - the switch has no candidate",
        "file": "Biotak/TH3Tool_C.mqh",
        "find": "    CalcAnchorRemember(LegReadAnchor(t1, t2), base);   // P-ANCHOR-LAST: newest committed leg owns the read",
        "replace": "    // MUTATION: no anchor published",
        "expect": "P-ANCHOR-LAST",
    },
    {
        "id": "P-ANCHOR-LASTb",
        "gate": "regression",
        "rule": "the note never repeats the node's own ATR and percent in an owner row",
        "what": "the owner row prints on a TF whose ATR/% are already on the face - the duplicate info line is back",
        "file": "Biotak/BaseKnot_Note.mqh",
        "find": "   if(tfs[owner] == nd.nodeTF ||\n      (up1 > 0 && nd.abPatRead && nd.abPat > 0.0 && tfs[owner] == up1) ||\n      (up2 > 0 && nd.abStrRead && nd.abStr > 0.0 && tfs[owner] == up2)) return \"\";",
        "replace": "   if(false) return \"\";   // MUTATION: the duplicate row is back",
        "expect": "the duplicate info bar is back",
    },
    # P-BK-115 (2026-10-21) — the note keeper's at-rest loop, the owner pump's per-round
    # measurement, and the story's second publisher. Each one put back by its own spelling.
    {
        "id": "P-BK-115a",
        "gate": "regression",
        "rule": "the note keeper heals a row only while the toast says a note is up",
        "what": "the keeper heals the row the spent toast deleted - a full Sync + ChartRedraw twice a second on a still chart",
        "file": "Biotak/BaseKnot_Note.mqh",
        "find": "      if(!BaseKnotCornerToastIsArmed()) return;   // P-BK-115a: the toast owns the absence",
        "replace": "      // MUTATION: the toast's absence is damage again",
        "expect": "the keeper heals a row the toast deliberately deleted",
    },
    {
        "id": "P-BK-115b",
        "gate": "regression",
        "rule": "the owner-TF pump measures once per question, never once per pump round",
        "what": "the input key stops short-circuiting - nine ATR legs and a 300-candle walk every 500 ms return",
        "file": "Biotak/BaseKnot_Owner.mqh",
        "find": "      barNow == s_bkOwnKeyBar && own == s_bkOwnKeyTF) return;",
        "replace": "      false) return;   // MUTATION: never short-circuit",
        "expect": "the owner pump measures on every 500 ms round",
    },
    {
        "id": "P-BK-115c",
        "gate": "regression",
        "rule": "the note's story has ONE publisher (BaseKnotSync)",
        "what": "the owner pump publishes storyT again - two walks take turns re-keying the note's anchor",
        "file": "Biotak/BaseKnot_Owner.mqh",
        "find": "         g_bkBoxes[k].ownerTFMin = bkOwner;",
        "replace": "         { g_bkBoxes[k].ownerTFMin = bkOwner; g_bkBoxes[k].storyT = osp.tLast; }   // MUTATION: second publisher",
        "expect": "two publishers for the note's anchor key",
    },
    {
        "id": "P-BK-115d",
        "gate": "regression",
        "rule": "the owner-TF walk reads the box' right edge, never storyT (which Sync derives from the owner)",
        "what": "the pump reads storyT again - M5 -> 18:50 -> none -> 05:45 -> M5 every 500 ms on one unchanged box",
        "file": "Biotak/BaseKnot_Owner.mqh",
        "find": "      an = t2;",
        "replace": "      an = g_bkBoxes[k].storyT;",
        "expect": "the owner walk reads storyT",
    },
    # P-BK-116 (2026-10-21) — the line-end column's two laws: ONE selected box, and a size
    # read from the terminal's own tick value instead of a hard-coded dollar per pip.
    {
        "id": "P-BK-116a",
        "gate": "regression",
        "rule": "the line-end column belongs to ONE selected box",
        "what": "every knot wears the column - five rows per box, the clutter the order forbids",
        "file": "Biotak/BaseKnot_Note.mqh",
        "find": "   bool sel = (id == BaseKnotSelectedId());",
        "replace": "   bool sel = true;   // MUTATION: every box wears the column",
        "expect": "the column no longer belongs to ONE selected box",
    },
    {
        "id": "P-BK-116b",
        "gate": "regression",
        "rule": "the pip's money is the terminal's own tick value",
        "what": "the $/pip is a fixed number again - a conversion the account may not agree with",
        "file": "Biotak/BaseKnot_Note.mqh",
        "find": "   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);\n   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);",
        "replace": "   double tv = 1.0, ts = 0.0;   // MUTATION: a hard-coded $ per pip",
        "expect": "the pip money is not the terminal's own tick value",
    },
    {
        "id": "P-ANCHOR-LASTc",
        "gate": "regression",
        "rule": "the active owner follows the story BaseKnotSync just published",
        "what": "BaseKnotSync stops re-anchoring the active owner on the published story - a freshly drawn box keeps the live read",
        "file": "Biotak/BaseKnot_Plan.mqh",
        "find": " if(sp.tLast > 0 && g_calcAnchorOwner == id) CalcAnchorFollow(id, sp.tLast);",
        "replace": "",
        "expect": "P-ANCHOR-LAST",
    },
    # P-ANCHOR-LAST-d/e/f (2026-10-27) - THE FENCE: the LAST OBJECT switch is a LABEL
    # lever. Its inverse is the state this tree shipped before the fence moved - one
    # `CalcAnchorAt()` at the geometry funnel, so a press re-stepped every drawn level.
    # The user's words (that switch used to change only the numbers, and that was
    # correct) are why the inverse is gated by name instead of remembered.
    {
        "id": "P-ANCHOR-LAST-d",
        "gate": "regression",
        "rule": "the LAST OBJECT switch moves labels, never drawn geometry",
        "what": "CalculateWeightedATR reads the anchor again - the TH step, the fractal range, the adaptive shift and the plan re-step on a press",
        "file": "Biotak/ATR_A.mqh",
        "find": "    return CalculateWeightedATRLive(tf);\n}",
        "replace": "    datetime fa = CalcAnchorAt();\n    if(fa > 0) return CalculateWeightedATRAt(tf, fa);\n    return CalculateWeightedATRLive(tf);\n}",
        "expect": "[FAIL] P-ANCHOR-LAST:",
    },
    {
        "id": "P-ANCHOR-LAST-e",
        "gate": "regression",
        "rule": "the plan's ATR is not a source the label switch selects",
        "what": "TradePlanStripPips asks the anchor again - the plan's SL/TP move with a switch that only promises label numbers",
        "file": "Biotak/TradePlanFormulas.mqh",
        "find": "   if(eff <= 0 && inpUseLegATR) eff = TradePlanLegAnchor(tfMinutes);",
        "replace": "   if(eff <= 0 && CalcAnchorAt() <= 0 && inpUseLegATR) eff = TradePlanLegAnchor(tfMinutes);",
        "expect": "[FAIL] P-ANCHOR-LAST:",
    },
    {
        "id": "P-ANCHOR-LAST-f",
        "gate": "regression",
        "rule": "the anchored read has exactly one home - the labels",
        "what": "GetATRForTimeframe stops asking the anchor - the switch would paint, save and move no number",
        "file": "Biotak/ATR_A.mqh",
        "find": "    datetime fa = CalcAnchorAt();\n    if(fa > 0)\n        return CalculateWeightedATRAt(CompatTF(targetMinutes), fa);",
        "replace": "    // MUTATION: the labels read live",
        "expect": "[FAIL] P-ANCHOR-LAST:",
    },
    # P-ANCHOR-LAST-MOVE (2026-10-22) — the switch is on the strip now, and the user's
    # law is «همون لحظه»: the press must land in the SAME pass, and cost nothing at rest.
    {
        "id": "P-ANCHOR-LAST-MOVE-a",
        "gate": "regression",
        "rule": "the strip's anchor press requests the label relayout and the redraw in the same press",
        "what": "CalcAnchorSetOn keeps the state but stops asking for the pass - the labels show the old ATR until the next bar",
        "file": "Biotak/CalcAnchor.mqh",
        "find": "   CalcAnchorSave();\n   g_labelsRelayoutNeeded = true;\n   g_redrawNeeded = true;\n}",
        "replace": "   CalcAnchorSave();\n   // MUTATION: no relayout request\n}",
        "expect": "P-ANCHOR-LAST-MOVE",
    },
    {
        "id": "P-ANCHOR-LAST-MOVE-b",
        "gate": "regression",
        "rule": "the seat flips the anchor through its one owner",
        "what": "the press stops calling CalcAnchorSetOn - a second writer for one state, and no relayout at all",
        "file": "Biotak/DrawStrip_Tap.mqh",
        "find": "      CalcAnchorSetOn(!g_calcAnchorOn);",
        "replace": "      g_calcAnchorOn = !g_calcAnchorOn;   // MUTATION: second writer",
        "expect": "P-ANCHOR-LAST-MOVE",
    },
    {
        "id": "P-ANCHOR-LAST-MOVE-c",
        "gate": "regression",
        "rule": "the entry drains the strip's refresh request into RefreshDisplay (the same-pass half)",
        "what": "the bridge is dead - the press repaints its own row and the ATR numbers wait for the next tick",
        "file": "Biotak Trigger TH3.mq4",
        "find": "  if(dsAsk > 0) RefreshDisplay(REFRESH_ALL);",
        "replace": "  // MUTATION: the bridge is dead",
        "expect": "P-ANCHOR-LAST-MOVE",
    },
    {
        "id": "P-ANCHOR-LAST-MOVE-d",
        "gate": "regression",
        "rule": "the press leaves the refresh request at all",
        "what": "the seat stops asking - CalcAnchorSetOn sets its flags and nothing runs the pass in this event",
        "file": "Biotak/DrawStrip_Tap.mqh",
        "find": "      DrawStripRefreshAsk();",
        "replace": "      // MUTATION: no refresh ask",
        "expect": "P-ANCHOR-LAST-MOVE",
    },
    # P-BK-120 (2026-10-22) — the box' ticks must ride the box' own stop. The user, on a
    # CTR box over an M1 chart: «این تی پی ها رو از کجا اورده به نظر درست نیستش» — the
    # ticks were the base TF's PLAN legs (sized off Eng(M15)) while the drawn stop was
    # Eng(H1). One ruler, or the numbers are nobody's.
    {
        "id": "P-BK-120-a",
        "gate": "regression",
        "rule": "the pump pushes the plan's ratios on the row's OWN EngSL",
        "what": "the pushed legs go back to plan.tp1 - every tick is sized off the structure rung again",
        "file": "Biotak/EventHandlers_Objects.mqh",
        "find": "       tp1[i]  = (double)TradePlanTPFromEng(plan.eng, 1);",
        "replace": "       tp1[i]  = (plan.tp1 > 0 ? (double)plan.tp1 : 0.0);   // MUTATION: the plan's own leg",
        "expect": "[FAIL] P-BK-120",
    },
    {
        "id": "P-BK-120-b",
        "gate": "regression",
        "rule": "every tick is read on the STOP's own time",
        "what": "the level goes back to the base TF - the tick leaves the ruler its stop is on",
        "file": "Biotak/BaseKnot_Plan.mqh",
        "find": "      double lv = (tk <= BaseKnotTPCount() ? BaseKnotTPLevel(entry, dir, mTF, tk, nd.anchor) : 0.0);",
        "replace": "      double lv = (tk <= BaseKnotTPCount() ? BaseKnotTPLevel(entry, dir, baseTF, tk, nd.anchor) : 0.0);   // MUTATION: the base TF",
        "expect": "[FAIL] P-BK-120",
    },
    {
        "id": "P-BK-120-c",
        "gate": "regression",
        "rule": "the lean mover follows the same rung the release Sync lands on",
        "what": "the drag drops the measure TF - every tick jumps when the gesture is released",
        "file": "Biotak/BaseKnot_Plan.mqh",
        "find": "                                  BaseKnotMeasureTFMin(g_bkBoxes[k].nodeKind, g_bkBoxes[k].baseTFMin, BaseKnotBoxHop(k)), tk, an);   // P-BK-120: the stop's own rung; P-BK-125: the SAME hop the stop was drawn on",
        "replace": "                                  g_bkBoxes[k].baseTFMin, tk, an);   // MUTATION: the base TF",
        "expect": "[FAIL] P-BK-120",
    },
    #--- P-BK-79 (2026-10-27) — «زمان گره»: the row is (TF, ANCHOR), and the anchor is the box'
    #--- own story end. The method the user asked to keep, in the gate. Two inverses: the table
    #--- forgets its second key, and the committed read asks for "now".
    {
        "id": "P-BK-79-a",
        "gate": "regression",
        "rule": "the knot's time is its own story end, and the row is keyed on it",
        "what": "the ability table is TF-keyed again - two boxes on one TF share one ATR, the exact defect P-BK-79 replaced",
        "file": "Biotak/BaseKnot_Ability.mqh",
        "find": "      if(s_bkAbTF[i] != tfMin || s_bkAbAnchor[i] != an) continue;\n      atr = s_bkAbATR[i];",
        "replace": "      if(s_bkAbTF[i] != tfMin) continue;   // MUTATION: TF-keyed, the anchor is gone\n      atr = s_bkAbATR[i];",
        "expect": "[FAIL] P-BK-79",
    },
    {
        "id": "P-BK-79-b",
        "gate": "regression",
        "rule": "the knot's time is its own story end, and the row is keyed on it",
        "what": "the committed read asks the live bar - a closed knot changes type as the chart fills",
        "file": "Biotak/BaseKnot_Plan.mqh",
        "find": "   BaseKnotNodeRead((sp.tLast > 0 ? sp.tLast : t2), top, bot, baseTF,",
        "replace": "   BaseKnotNodeRead(TimeCurrent(), top, bot, baseTF,   // MUTATION: read at now",
        "expect": "[FAIL] P-BK-79",
    },
    #--- P-BK-125 (2026-10-27) — THE STOP'S RUNG IS THE NEAREST RUNG, AT THE KNOT'S OWN TIME.
    #--- The decision the user made on the dataset's own twins (BK-0003 32.0 vs BK-0004 72.9 on
    #--- the same box), and the method he refused to move: the row is (TF, ANCHOR) with the
    #--- anchor = the box' story end. Two inverses, one per sentence.
    {
        "id": "P-BK-125-a",
        "gate": "regression",
        "rule": "the stop rides the rung whose leg PACKAGE fits the box (P-BK-128)",
        "what": "the fit is dropped for the raw ATR - a 217-pip box takes the 258.5 pips of legs it cannot hold",
        "file": "Biotak/BaseKnot_Ability.mqh",
        "find": "   if(h >= fit * a2) hop = 2;",
        "replace": "   if(h >= a2) hop = 2;   // MUTATION: the package is not counted",
        "expect": "[FAIL] P-BK-125",
    },
    {
        "id": "P-BK-125-b",
        "gate": "regression",
        "rule": "the ladder is read at the box' own story end, never at now",
        "what": "a box with no story is allowed through - it reads the live row, the exact drift P-BK-79 removed",
        "file": "Biotak/BaseKnot_Ability.mqh",
        "find": "   if(g_bkBoxes[k].storyT <= 0) return -1;",
        "replace": "   if(g_bkBoxes[k].storyT < 0) return -1;   // MUTATION: no story reads the live row",
        "expect": "[FAIL] P-BK-125",
    },
    #--- P-BK-124b (2026-10-27) — THE PRESS HAS TO ANSWER ON THE CHART. P-BK-124 measured the
    #--- folder and left the screen unmeasured, so five complete samples and «چیزی روی صفحه
    #--- نمیاد که سیو شده یا نه» were both true. Four inverses, one per half of the receipt:
    #--- how long it lives, what it says, when it says SAVED, and the clock that clears it.
    {
        "id": "P-BK-124b-a",
        "gate": "regression",
        "rule": "the capture's receipt lives exactly one second, as the user ordered",
        "what": "the hold is zero - the tick after the press deletes the label, so a press answers nothing again",
        "file": "Biotak/BaseKnot_Shot.mqh",
        "find": "#define BK_SHOT_HOLD_SEC  1     //",
        "replace": "#define BK_SHOT_HOLD_SEC  0     // MUTATION: a receipt that clears before it is drawn",
        "expect": "[FAIL] P-BK-124b",
    },
    {
        "id": "P-BK-124b-b",
        "gate": "regression",
        "rule": "the receipt names the knot's type (and its node TF, its height and the clock)",
        "what": "the type is dropped from the receipt - 'saved' with no answer to WHICH knot",
        "file": "Biotak/BaseKnot_Shot.mqh",
        "find": "      receipt = \"SAVED  \" + BaseKnotNodeShort(g_bkBoxes[k].nodeKind) +",
        "replace": "      receipt = \"SAVED  \" + \"CTR\" +   // MUTATION: a fixed name, not the knot's",
        "expect": "[FAIL] P-BK-124b",
    },
    {
        "id": "P-BK-124b-c",
        "gate": "regression",
        "rule": "SAVED is claimed only when BOTH files landed",
        "what": "the screenshot may fail and the label still says SAVED - the one lie a dataset cannot recover from",
        "file": "Biotak/BaseKnot_Shot.mqh",
        "find": "   if(okShot && okTxt)",
        "replace": "   if(okTxt)   // MUTATION: a refused screenshot still reads as saved",
        "expect": "[FAIL] P-BK-124b",
    },
    {
        "id": "P-BK-124b-d",
        "gate": "regression",
        "rule": "the receipt is aged out by the timer too, on the wall clock",
        "what": "OnTimer stops ageing the receipt - a market that stops ticking keeps it on the chart for ever",
        "file": "Biotak Trigger TH3.mq4",
        "find": "    BaseKnotShotFlashTick();",
        "replace": "    // BaseKnotShotFlashTick();   // MUTATION: the timer no longer ages the receipt",
        "expect": "[FAIL] P-BK-124b",
    },
    {
        "id": "P-BK-124b-e",
        "gate": "regression",
        "rule": "the receipt's hold runs on the wall clock, not the server clock",
        "what": "the hold is back on TimeCurrent - a closed market never advances it, so the receipt never clears",
        "file": "Biotak/BaseKnot_Shot.mqh",
        "find": "   if(s_bkShotFlashDue == 0 || TimeLocal() < s_bkShotFlashDue) return;",
        "replace": "   if(s_bkShotFlashDue == 0 || TimeCurrent() < s_bkShotFlashDue) return;   // MUTATION: the server clock",
        "expect": "[FAIL] P-BK-124b",
    },
    #--- P-BK-126b (2026-10-27) — THE KNOT'S TIME IS THE THREE CANDLES, THE ATR RULER IS THE
    #--- FALLBACK. The user's own measurement («این گره ... ۳ کندل درجا زدن ... پس چرا زده برای ۵
    #--- دقیقه») and the offline scan: 3 x M30 = 119.2 pips of a 119.9 box (99.4 %), 32m already
    #--- breaks it (123.4), while the ATR band answered M5 because 119.9 / 34.6 = 3.47 happens to
    #--- sit inside 2.40..3.60. Five inverses, one per half of the answer.
    {
        "id": "P-BK-126b-a",
        "gate": "regression",
        "rule": "the stand-still walk decides the knot's time",
        "what": "the ATR owner is read first again - the walk is never consulted and the M5 band names a 30m box",
        "file": "Biotak/BaseKnot_Plan.mqh",
        "find": "   int baseTF = BaseKnotBaseTFMin(still, bs1, bs2, top, bot, baseReadTF); if(baseTF == 0 && g_bkBoxes[k].ownerTFMin > 0) baseTF = g_bkBoxes[k].ownerTFMin;",
        "replace": "   int baseTF = (g_bkBoxes[k].ownerTFMin > 0 ? g_bkBoxes[k].ownerTFMin : BaseKnotBaseTFMin(still, bs1, bs2, top, bot, baseReadTF));   // MUTATION: the ATR ruler is the knot's time again",
        "expect": "[FAIL] P-BK-126b",
    },
    {
        "id": "P-BK-126b-b",
        "gate": "regression",
        "rule": "a box whose story the walk cannot read still names a time (the owner fallback)",
        "what": "the fallback is deleted - an unreachable story leaves the class at 0 and the box draws no plan at all",
        "file": "Biotak/BaseKnot_Plan.mqh",
        "find": " if(baseTF == 0 && g_bkBoxes[k].ownerTFMin > 0) baseTF = g_bkBoxes[k].ownerTFMin;",
        "replace": " /* MUTATION: no owner fallback */",
        "expect": "[FAIL] P-BK-126b",
    },
    {
        "id": "P-BK-126b-c",
        "gate": "regression",
        "rule": "the pump's ATR rows follow the class, not the owner",
        "what": "the class is overwritten by the ATR owner - an off-ladder class (31m) scales its trigger from M5 instead of the nearest rung below it",
        "file": "Biotak/BaseKnot_Owner.mqh",
        "find": "   if(k >= 0 && g_bkBoxes[k].ownerTFMin > 0) tf = g_bkBoxes[k].ownerTFMin;   // P-BK-115b: the field this pump owns\n   if(k >= 0 && g_bkBoxes[k].baseTFMin > 0) tf = g_bkBoxes[k].baseTFMin;",
        "replace": "   if(k >= 0 && g_bkBoxes[k].baseTFMin > 0) tf = g_bkBoxes[k].baseTFMin;\n   if(k >= 0 && g_bkBoxes[k].ownerTFMin > 0) tf = g_bkBoxes[k].ownerTFMin;   // MUTATION: the ATR owner wins",
        "expect": "[FAIL] P-BK-126b",
    },
    {
        "id": "P-BK-126b-d",
        "gate": "regression",
        "rule": "three stand-still candles IN A ROW name the time",
        "what": "a candle that poked out no longer breaks the run - the same band answers 35..45m instead of the 30..33m the box was drawn around",
        "file": "Biotak/BaseKnot_Nodes.mqh",
        "find": "         else if(cur >= 0) held = 0;                // P-BK-126b: a candle that POKED OUT breaks",
        "replace": "         else if(cur < 0) held = 0;   // MUTATION: a poked-out candle no longer breaks the run",
        "expect": "[FAIL] P-BK-126b",
    },
    {
        "id": "P-BK-126b-e",
        "gate": "regression",
        "rule": "an off-ladder class still reads one continuous curve",
        "what": "the rung below's ATR is used unscaled - a 31m knot sizes as a 15m one, the hole P-BK-126 closed",
        "file": "Biotak/BaseKnot_Ability.mqh",
        "find": "      trig = atr * BaseKnotRungScale(below, tfMin);",
        "replace": "      trig = atr;   // MUTATION: the rung below's own ATR, unscaled",
        "expect": "[FAIL] P-BK-126b",
    },
    #--- P-BK-126c (2026-10-27) - THE STAND-STILL COUNT IS READ ON THE CLOCK's. P-BK-126 cut the
    #--- buckets back from the box' right edge, so one band answered 26..31m for eleven closes and
    #--- two samples of one box 10 s apart read 27m/ETR/SELL beside 13m/CTR/BUY. Two inverses: the
    #--- origin and the window's closing fence.
    {
        "id": "P-BK-126c-a",
        "gate": "regression",
        "rule": "the stand-still bucket is cut on the clock, never on the box' edge",
        "what": "the bucket origin goes back to `s2` - the grid is phase-locked to the drawing and the same band answers 26, 27, 29, 30, 31 minutes for different closes",
        "file": "Biotak/BaseKnot_Nodes.mqh",
        "find": "      int k = (int)(t[i] / step);                   // P-BK-126c: the CLOCK's candle, not the box'",
        "replace": "      int k = (int)((s2 - t[i]) / step);   // MUTATION: the box' right edge is the grid's origin",
        "expect": "[FAIL] P-BK-126c",
    },
    {
        "id": "P-BK-126c-b",
        "gate": "regression",
        "rule": "`s2` closes the window, it never decides a boundary",
        "what": "the fence stops the walk instead of skipping a newer bar - the window is newest-first, so the walk ends on its first bar and no count is ever read",
        "file": "Biotak/BaseKnot_Nodes.mqh",
        "find": "      if(t[i] > s2) continue;                       // newer than the box' right edge",
        "replace": "      if(t[i] > s2) break;   // MUTATION: a newer bar ends the walk",
        "expect": "[FAIL] P-BK-126c",
    },
    #--- P-BK-126d (2026-10-27) - THE COUNT IS THE MEASURE, NO GRID. The user after two builds of
    #--- a grid over the same count: «به ساعت نباید ربط داشته باشه ... بین کندل ورود و خروج سه کندل
    #--- باشه» and «همون کار که تعداد کندل مشخص میکنه ... از همون استفاده بکن». Three inverses: the
    #--- grid coming back, the divisor, and the version that keeps the rows apart.
    {
        "id": "P-BK-126d-a",
        "gate": "regression",
        "rule": "the class is the base's own count over three, never a bucket grid fitted to it",
        "what": "the clock walk is back in front of the count - `Node_TF` follows a grid again instead of the entry..exit count",
        "file": "Biotak/BaseKnot_Nodes.mqh",
        "find": "   int nodeTF = spanMin / 3;                     // «بین ورود و خروج سه کندل» — three candles",
        "replace": "   datetime mt[]; double mh[], ml[]; int mn = BaseKnotM1Window(b1, b2, mt, mh, ml);\n   int nodeTF = spanMin / 3;\n   if(mn > 0) for(int T = nodeTF; T >= 1; T--) if(BaseKnotStillCount(T, b2, mt, mh, ml, mn, top, bot) >= BK_BASE_RUNG_MIN) { nodeTF = T; break; }   // MUTATION: a grid over the count",
        "expect": "[FAIL] P-BK-126d",
    },
    {
        "id": "P-BK-126d-b",
        "gate": "regression",
        "rule": "three candles: the count is divided by three",
        "what": "the span is read whole - `Node_TF` becomes the base's own length, three times the candle the user sees",
        "file": "Biotak/BaseKnot_Nodes.mqh",
        "find": "   int nodeTF = spanMin / 3;                     // «بین ورود و خروج سه کندل» — three candles",
        "replace": "   int nodeTF = spanMin;   // MUTATION: the count is not divided",
        "expect": "[FAIL] P-BK-126d",
    },
    {
        "id": "P-BK-126d-c",
        "gate": "regression",
        "rule": "a v6 row's Type/U/Stop were cut at the arithmetic midpoint and on round(u); it cannot be scored with a v7 row",
        "what": "the formula version goes back to v6 - a knife-edge type and a leg that did not fit its box are scored beside the ratio/capacity ones",
        "file": "Biotak/BaseKnot_Shot.mqh",
        "find": "#define BK_FORMULA_VERSION \"v7\"",
        "replace": "#define BK_FORMULA_VERSION \"v6\"   // MUTATION: two laws under one version",
        "expect": "[FAIL] P-BK-126d",
    },
    #--- P-BK-126e (2026-10-27) - THE ANCHOR IS THE BOX' LEFT EDGE. The class was one number per
    #--- band (P-BK-126d) and the number still moved, because the RUN that fed it was anchored on
    #--- the right edge: 99 right edges over one band read 12/20m, 8/13m, 5/8m and 22/36m. Four
    #--- inverses: the anchor, the scan's direction, the continuation, and the preview's key.
    {
        "id": "P-BK-126e-a",
        "gate": "regression",
        "rule": "the walk anchors on the box' LEFT edge (the entry), never its right edge",
        "what": "the anchor goes back to the right edge - one band holding two runs answers the run the drag brought nearest that edge (12/20m beside 8/13m at 45/46 of 99 positions)",
        "file": "Biotak/BaseKnot_Measure.mqh",
        "find": "   int s = (sh1 > sh2 ? sh1 : sh2);",
        "replace": "   int s = (sh1 < sh2 ? sh1 : sh2);   // MUTATION: the right edge anchors the walk",
        "expect": "[FAIL] P-BK-126e",
    },
    {
        "id": "P-BK-126e-b",
        "gate": "regression",
        "rule": "the search steps FORWARD (newer) from the entry candle",
        "what": "the dead-zone skip steps older - the walk leaves the box to the LEFT and latches onto a run that is not in it",
        "file": "Biotak/BaseKnot_Measure.mqh",
        "find": "      if(!BaseKnotBarBodyInside(s, top, bot, readTF)) { s--; continue; }",
        "replace": "      if(!BaseKnotBarBodyInside(s, top, bot, readTF)) { s++; continue; }   // MUTATION: the scan walks older",
        "expect": "[FAIL] P-BK-126e",
    },
    {
        "id": "P-BK-126e-c",
        "gate": "regression",
        "rule": "a candidate that is not a base sends the search FORWARD past it",
        "what": "the continuation jumps to the walking run's end instead of one bar newer - the next run is never reached and a late knot reads 0 bars",
        "file": "Biotak/BaseKnot_Measure.mqh",
        "find": "      s = head - 1;                                    // a stray body: look FORWARD past it",
        "replace": "      s = t;   // MUTATION: the search steps back into the node walk's end",
        "expect": "[FAIL] P-BK-126e",
    },
    {
        "id": "P-BK-126e-d",
        "gate": "regression",
        "rule": "the drag preview's cache is keyed on the LEFT edge",
        "what": "the preview asks the right edge again - a right-edge drag invalidates the cache and a left-edge drag reuses a run it no longer describes",
        "file": "Biotak/BaseKnot_Nodes.mqh",
        "find": "      int e = iBarShift(_Symbol, 0, t1, false);   // P-BK-126e: the LEFT edge is the anchor",
        "replace": "      int e = iBarShift(_Symbol, 0, t2, false);   // MUTATION: the right edge is the cache key",
        "expect": "[FAIL] P-BK-126e",
    },
    #--- P-BK-126f (2026-10-27) - THE KNOT'S DERIVATION LEAVES ONE FLUSHED LINE. Three inverses:
    #--- the caller (a witness nobody calls), the guard (a witness that fires every frame), and the
    #--- channel (a witness in the buffered journal). Each is a way the line can be absent exactly
    #--- when the user drags, which is the only moment it is read.
    {
        "id": "P-BK-126f-a",
        "gate": "regression",
        "rule": "the witness fires on CHANGE - a still chart builds no string",
        "what": "the guard only compares the chart TF and the count - a DRAG (new t1/t2/band with the same count) prints nothing, which is the moment the line exists for",
        "file": "Biotak/BaseKnot_Shot.mqh",
        "find": "   if(wm[slot].used && wm[slot].id == id && wm[slot].chartTF == chartTF &&\n      wm[slot].bars == bars && wm[slot].still == still && wm[slot].readTF == readTF &&\n      wm[slot].nodeTF == nodeTF && wm[slot].t1 == boxT1 && wm[slot].t2 == boxT2 &&\n      wm[slot].s == tStart && wm[slot].z == tLast && wm[slot].x == tExit &&\n      wm[slot].top == top && wm[slot].bot == bot) return;   // a still chart: no string, no write",
        "replace": "   if(false) return;   // MUTATION: the guard compares nothing",
        "expect": "[FAIL] P-BK-126f",
    },
    {
        "id": "P-BK-126f-b",
        "gate": "regression",
        "rule": "the witness writes through the FLUSHED channel (DrawStripDiagEmit), never Print",
        "what": "the line goes to the journal - MT4 buffers it in RAM (P-DRAW-126: seven minutes of silence while clicks arrived), so the user's drag reads as nothing happened",
        "file": "Biotak/BaseKnot_Shot.mqh",
        "find": "   DrawStripDiagEmit(\"[BK-KNOT] formula=\" + BK_FORMULA_VERSION +",
        "replace": "   Print(\"[BK-KNOT] formula=\" + BK_FORMULA_VERSION +   // MUTATION: the buffered journal",
        "expect": "[FAIL] P-BK-126f",
    },
    {
        "id": "P-BK-126f-c",
        "gate": "regression",
        "rule": "BaseKnotSync calls the witness with the box, the run and the published class",
        "what": "nothing calls it - the line is never written, so a report reads «no line» for a box that is on the chart",
        "file": "Biotak/BaseKnot_Plan.mqh",
        "find": "BaseKnotKnotWitness(id, nd.kind, hop, t1, t2, top, bot, bars, still, baseReadTF, baseTF, sp.tStart, sp.tLast, sp.tExit);",
        "replace": "/* MUTATION: the witness is never called */",
        "expect": "[FAIL] P-BK-126f",
    },
    {
        "id": "P-BK-126f-d",
        "gate": "regression",
        "rule": "the witness memo is per BOX - the attach loop over every box is not a change",
        "what": "the memo shrinks to ONE slot - the attach re-sync loop (every box, one call each) is read as changed, changed, so an untouched chart prints a line per box per pass",
        "file": "Biotak/BaseKnot_Shot.mqh",
        "find": "   static BKWitnessMemo wm[BK_WITNESS_SLOTS];",
        "replace": "   static BKWitnessMemo wm[1];   // MUTATION: one shared memo for every box",
        "expect": "[FAIL] P-BK-126f",
    },
    #--- P-BK-127 (2026-10-27) - ONE RULER: THE ENTRY IS THE CARD'S TRIGGER CELL. The user's own
    #--- box read `Trigger 84.5` on the card and drew 41.6, because only the STOP took the type's
    #--- rung. Five inverses: the owner, the two geometry sites, the hover, and the harness.
    {
        "id": "P-BK-127-a",
        "gate": "regression",
        "rule": "the entry's rung IS the stop's rung (BaseKnotEntryTFMin answers BaseKnotMeasureTFMin)",
        "what": "the entry answers the node's own TF again - the exact 41.6 the user reported beside a card's Trigger 84.5",
        "file": "Biotak/BaseKnot_Measure.mqh",
        "find": "   return BaseKnotMeasureTFMin(kind, tf, hop);",
        "replace": "   return tf;   // MUTATION: the node's own time",
        "expect": "[FAIL] P-BK-127",
    },
    {
        "id": "P-BK-127-b",
        "gate": "regression",
        "rule": "the geometry hands the entry the hop it gives the stop",
        "what": "BaseKnotLegPair asks the entry owner without the box' hop - on a CTR box the entry stays one rung while the stop climbs two",
        "file": "Biotak/BaseKnot_Measure.mqh",
        "find": "   int    etf   = BaseKnotEntryTFMin(kind, tfMin, hop);",
        "replace": "   int    etf   = BaseKnotEntryTFMin(kind, tfMin);   // MUTATION: the name's hop only",
        "expect": "[FAIL] P-BK-127",
    },
    {
        "id": "P-BK-127-c",
        "gate": "regression",
        "rule": "the committed Sync names both legs on the SAME rung",
        "what": "the Sync's own eTF drops the hop - the note prints one rung and the line draws another",
        "file": "Biotak/BaseKnot_Plan.mqh",
        "find": "    int    eTF       = BaseKnotEntryTFMin(nd.kind, baseTF, hop);",
        "replace": "    int    eTF       = BaseKnotEntryTFMin(nd.kind, baseTF);   // MUTATION: a second rung for the text",
        "expect": "[FAIL] P-BK-127",
    },
    {
        "id": "P-BK-127-d",
        "gate": "regression",
        "rule": "the knot's hover reads the entry on the rung the stop is drawn on",
        "what": "the hover's wTF drops the hop - the hover names a depth the drawn line does not use",
        "file": "Biotak/BaseKnot_Nodes.mqh",
        "find": "   int    wTF  = BaseKnotEntryTFMin(nd.kind, nd.baseTF, hop);",
        "replace": "   int    wTF  = BaseKnotEntryTFMin(nd.kind, nd.baseTF);   // MUTATION: the hover's own rung",
        "expect": "[FAIL] P-BK-127",
    },
    {
        "id": "P-BK-127-e",
        "gate": "regression",
        "rule": "the harness expects the RUNG's leg, and the entry's TF to be the stop's",
        "what": "the harness goes back to the base TF's HuntSL - a green -Tests run would have blessed the 41.6",
        "file": "tests/Biotak_BaseKnot_Lines_Test.mq4",
        "find": "   double wantOff  = (kind == BK_NODE_FTR ? BkRowEng(mtf) : BkRowHunt(mtf));",
        "replace": "   double wantOff  = (kind == BK_NODE_FTR ? BkRowEng(5) : BkRowHunt(5));   // MUTATION: the base TF's leg",
        "expect": "[FAIL] P-BK-127",
    },
    #--- P-BK-128 (2026-10-27) - ONE BOX, ONE ANSWER: RATIO TYPE, CAPACITY RUNG. The report was
    #--- one box printing ETR and FTR a nudge apart («این یک بار etr نشون میده یک بار ftr»), because
    #--- the type was cut at (a+b)/2 and the leg at round(u): both sat at 218.0 on rows
    #--- 135.2/300.8, 0.3 % from his 217.3-pip box. Six inverses, one per half.
    {
        "id": "P-BK-128-a",
        "gate": "regression",
        "rule": "the FTR/ETR edge is the ladder's RATIO midpoint",
        "what": "the arithmetic midpoint returns - the boundary lands 0.3 % from his box and a 2-pip nudge flips the type again",
        "file": "Biotak/BaseKnot_Nodes.mqh",
        "find": "    if(h <= MathSqrt(trig * pat)) return BK_NODE_FTR;",
        "replace": "    if(h <= (trig + pat) * 0.5) return BK_NODE_FTR;   // MUTATION: the price midpoint",
        "expect": "[FAIL] P-BK-128",
    },
    {
        "id": "P-BK-128-b",
        "gate": "regression",
        "rule": "the boundary the HOVER prints is the boundary the type is cut at",
        "what": "the tooltip prints √(pat·str) while the type is still cut at (a+b)/2 - two places on one box",
        "file": "Biotak/BaseKnot_Nodes.mqh",
        "find": "   return MathSqrt(pat * str);    // P-BK-128: ... and the same for pattern | structure",
        "replace": "   return (pat + str) * 0.5;   // MUTATION: the tooltip names another boundary",
        "expect": "[FAIL] P-BK-128",
    },
    {
        "id": "P-BK-128-c",
        "gate": "regression",
        "rule": "the CTR ceiling is the structure ability itself (the user's OTR rule)",
        "what": "CTR runs 50 % past the structure ability - «بیشتر از توان حرکتی تایم ساختار» stops being OTR",
        "file": "Biotak/BaseKnot_Nodes.mqh",
        "find": "    if(h <= str)                  return BK_NODE_CTR;   // the structure band itself",
        "replace": "    if(h <= str * 1.5)            return BK_NODE_CTR;   // MUTATION: the ceiling moved",
        "expect": "[FAIL] P-BK-128",
    },
    {
        "id": "P-BK-128-d",
        "gate": "regression",
        "rule": "the rung is the deepest leg PACKAGE the box can hold (55/64 of the rung's ATR)",
        "what": "the fit becomes the rung's raw ATR - a 217-pip box takes 258.5 pips of legs it cannot hold",
        "file": "Biotak/BaseKnot_Ability.mqh",
        "find": "   if(h >= fit * a1) hop = 1;",
        "replace": "   if(h >= a1) hop = 1;   // MUTATION: the package is not counted",
        "expect": "[FAIL] P-BK-125",
    },
    {
        "id": "P-BK-128-e",
        "gate": "regression",
        "rule": "the sample's U is the SAME ratio coordinate the type is cut at",
        "what": "U goes back to the linear position - the sample's fraction and the printed bands disagree",
        "file": "Biotak/BaseKnot_Shot.mqh",
        "find": "   if(h <= a1) return MathLog(h / a0) / MathLog(a1 / a0);",
        "replace": "   if(h <= a1) return (h - a0) / (a1 - a0);   // MUTATION: the arithmetic position",
        "expect": "[FAIL] P-BK-128",
    },
    {
        "id": "P-BK-128-f",
        "gate": "regression",
        "rule": "the fit constant IS the legs' own arithmetic (55/64 = 5/8 + 15/64)",
        "what": "the fit is retuned to 50/64 while the legs still spend 55/64 - the gate's own proof is what must catch it",
        "file": "Biotak/BaseKnot_Ability.mqh",
        "find": "#define BK_AB_FIT_NUM 55.0",
        "replace": "#define BK_AB_FIT_NUM 50.0   // MUTATION: a package smaller than the legs",
        "expect": "[FAIL] P-BK-128",
    },
    {
        "id": "P-BK-128-g",
        "gate": "regression",
        "rule": "the [P-BK-107] line prints the boundary the type is cut at (it asks the owners)",
        "what": "the journal line goes back to its own (atr+pat)*0.5 - the log quotes an edge the type stopped using, and two drags are compared by that line",
        "file": "Biotak/BaseKnot_Witness.mqh",
        "find": "\" bands FTR<\" + DoubleToString(BaseKnotToPips(BaseKnotNodeBandFtrEtr(nodeTF, an)), 1) +",
        "replace": "\" bands FTR<\" + DoubleToString(BaseKnotToPips((atr + pat) * 0.5), 1) +   // MUTATION: a second copy of the rule",
        "expect": "[FAIL] P-BK-128",
    },
    #--- P-BK-129 (2026-10-27) - ONE TF, TWO SPELLINGS: the machine name and the clock. He read
    #--- `35 bars · 700m base · FTR` / `ATR 700m:313.5` and asked for hours («این 700 m به ساعت و
    #--- دقیقه و غیره بنویس که سریع بفهمیم»); 700m is 11h40m of market. Three inverses: the clock
    #--- must be computed, the note must wear it, and the machine fields must NOT.
    {
        "id": "P-BK-129-a",
        "gate": "regression",
        "rule": "the display name is a clock (700m -> 11h40m), not a minute count",
        "what": "the hour term is dropped - the face prints `40m` for a 700-minute span",
        "file": "Biotak/BaseKnot_Base.mqh",
        "find": "   int d = tfMin / 1440, h = (tfMin % 1440) / 60, m = tfMin % 60;",
        "replace": "   int d = tfMin / 1440, h = 0, m = tfMin % 60;   // MUTATION: no hours",
        "expect": "[FAIL] P-BK-129",
    },
    {
        "id": "P-BK-129-b",
        "gate": "regression",
        "rule": "the witness fields keep the MACHINE spelling the tools parse",
        "what": "`[BK-KNOT] nodeTF=` wears the clock - every sample line reads `11h40m` and no tool can size it",
        "file": "Biotak/BaseKnot_Shot.mqh",
        "find": "                     \" nodeTF=\" + BaseKnotTFName(nodeTF) +",
        "replace": "                     \" nodeTF=\" + BaseKnotTFHuman(nodeTF) +   // MUTATION: the witness wears the clock",
        "expect": "[FAIL] P-BK-129",
    },
    {
        "id": "P-BK-129-c",
        "gate": "regression",
        "rule": "the note's ATR cell reads the clock",
        "what": "the cell goes back to the machine name - the face shows `700m:160%` beside an `11h40m base`",
        "file": "Biotak/BaseKnot_Note.mqh",
        "find": "   return BaseKnotTFHuman(tf) + \":\" + IntegerToString((int)MathRound(boxPips / a * 100.0)) + \"%\";",
        "replace": "   return BaseKnotTFName(tf) + \":\" + IntegerToString((int)MathRound(boxPips / a * 100.0)) + \"%\";   // MUTATION: the machine name on the face",
        "expect": "[FAIL] P-BK-129",
    },
    #--- P-BE-08 (2026-10-22) - ONE OWNER FOR THE ROW'S Y. The formula was spelled
    #--- eleven times in four files; PnlRowY is the owner now and the gate counts.
    {
        "id": "P-BE-08-a",
        "gate": "regression",
        "rule": "a hit test asks PnlRowY for the row's y",
        "what": "a second spelling is back - the hit rect sits on its own arithmetic again",
        "file": "Biotak/BiotakPanels_Hit.mqh",
        "find": "        int ry=PnlRowY(g_PnlOpen,r,py);",
        "replace": "        int ry=py+PNL_HEAD_H+PnlRowLine(g_PnlOpen,r)*PNL_ROW_H;   // MUTATION: a second grid",
        "expect": "P-BE-08",
    },
    {
        "id": "P-BE-08-b",
        "gate": "regression",
        "rule": "PnlRowY owns the head band and the row pitch",
        "what": "the owner returns the bare top edge - every row of every card lands on the header",
        "file": "Biotak/BiotakPanels_Rows.mqh",
        "find": "   return py + PNL_HEAD_H + PnlRowLine(item,row)*PNL_ROW_H;",
        "replace": "   return py;   // MUTATION: the owner lost the arithmetic",
        "expect": "P-BE-08",
    },
    #--- P-TH3-DEL4 (2026-10-24) - the readout the hand deleted stays deleted.
    #--- The plate is the readout's ONE selectable member (the rows stay
    #--- non-selectable), the hand is told from our own drops by STATE, and the
    #--- dismissal latches the family off for that base. Each half fails alone.
    {
        "id": "P-TH3-DEL4-a",
        "gate": "regression",
        "rule": "the plate is the readout's ONE selectable member",
        "what": "the plate is born unselectable again - the terminal cannot name the caption, so no Delete reaches it",
        "file": "Biotak/TH3/TH3Renderer_A.mqh",
        "find": "        ObjectSetInteger(0, plate, OBJPROP_SELECTABLE,  true);",
        "replace": "        ObjectSetInteger(0, plate, OBJPROP_SELECTABLE,  false);   // MUTATION: unnameable",
        "expect": "P-TH3-DEL4",
    },
    {
        "id": "P-TH3-DEL4-b",
        "gate": "regression",
        "rule": "a hand's delete is told from our own drops by STATE",
        "what": "the state test goes back to a clock - a rebuild's own event dismisses a healthy caption",
        "file": "Biotak/TH3/TH3Renderer_A.mqh",
        "find": "    if(!TH3InfoRowsLit(base)) return;          // our own drop: the rows went dark first",
        "replace": "    // MUTATION: no state test",
        "expect": "P-TH3-DEL4",
    },
    #--- P-UI-214 / P-UI-216 (2026-10-22) - the parity gate now reads NAMES on both
    #--- sides. Moving one side must show up as a DIFF, not as a green "ok".
    {
        "id": "P-UI-214-a",
        "gate": "parity",
        "rule": "the gear row's chip is the cards' chip",
        "what": "the strip's chip grows 2px - every gear row's glyph leaves the card's seat",
        "file": "Biotak/DrawStrip_Head.mqh",
        "find": "#define DSTRIP_CARD_CHIP_VIS 22   // = PNL_CHIP_VIS, the cards' own row glyph",
        "replace": "#define DSTRIP_CARD_CHIP_VIS 24   // MUTATION: the chip left the card's seat",
        "expect": "seat(s) differ",
    },
    {
        "id": "P-UI-216-a",
        "gate": "parity",
        "rule": "the head's mark canvas is the cards' disc plus its glow",
        "what": "the canvas is retuned alone - the head's mark no longer sits on the card's own seat",
        "file": "Biotak/DrawStrip_Head.mqh",
        "find": "#define DSTRIP_MARK_CANVAS   (DSTRIP_CARD_MARK_VIS + 2*DSTRIP_CARD_MARK_PAD)   // 44, the baked art",
        "replace": "#define DSTRIP_MARK_CANVAS   (DSTRIP_CARD_MARK_VIS + 2*DSTRIP_CARD_MARK_PAD + 2)   // MUTATION: 46",
        "expect": "seat(s) differ",
    },
    #--- P-TH3-PARK-01 (2026-10-24) - the ABCD drawing tool is parked, and ONLY it.
    #--- Four mutations put the tool back on sale one door at a time; the fifth is
    #--- the INVERSE half - it proves the gate also refuses an editor who kills the
    #--- dispatcher the leg meter and the caption delete ride.
    {
        "id": "P-TH3-PARK-01a",
        "gate": "regression",
        "rule": "the ABCD drawing tool has no catalog seat, no grid slot, no V arm and no ring press - all COMMENTED, while the dispatcher and the leg meter stay live (P-TH3-PARK-01)",
        "what": "CircCatRetired stops naming CAT_TH3 - the parked cell is back in the catalog, so the ring and the Tools grid can seat it again",
        "file": "Biotak/BiotakMenu_Ring.mqh",
        "find": "   return (cat == CAT_TH3);   // [TH3-TOOLS-DISABLED] ABCD drawing tool: parked, not deleted",
        "replace": "   return false;   // MUTATION: the parked cell is on sale again",
        "expect": "P-TH3-PARK-01",
    },
    {
        "id": "P-TH3-PARK-01b",
        "gate": "regression",
        "rule": "the ABCD drawing tool has no catalog seat, no grid slot, no V arm and no ring press - all COMMENTED, while the dispatcher and the leg meter stay live (P-TH3-PARK-01)",
        "what": "the star's retirement guard is dropped - a saved STAR mask bit re-seats the parked tool even though the catalog retired it",
        "file": "Biotak/BiotakMenu_Ring.mqh",
        "find": "   if(CircCatRetired(cat)) return false;   // TH3TOOL-OFF: no star, so the ring cannot re-seat it",
        "replace": "   // MUTATION: the star guard is gone",
        "expect": "P-TH3-PARK-01",
    },
    {
        "id": "P-TH3-PARK-01c",
        "gate": "regression",
        "rule": "the ABCD drawing tool has no catalog seat, no grid slot, no V arm and no ring press - all COMMENTED, while the dispatcher and the leg meter stay live (P-TH3-PARK-01)",
        "what": "the V key's arm is uncommented - the one hotkey that can start a draw session is live again",
        "file": "Biotak/EventHandlers_Router.mqh",
        "find": "        //    ToggleTH3Tool();",
        "replace": "        ToggleTH3Tool();   // MUTATION: the V arm is live",
        "expect": "P-TH3-PARK-01",
    },
    {
        "id": "P-TH3-PARK-01d",
        "gate": "regression",
        "rule": "the ABCD drawing tool has no catalog seat, no grid slot, no V arm and no ring press - all COMMENTED, while the dispatcher and the leg meter stay live (P-TH3-PARK-01)",
        "what": "CircCatCell stops skipping retired cells - the grid lays the parked tile on a slot and leaves the hole the slot mapping exists to avoid",
        "file": "Biotak/BiotakMenu_Ring.mqh",
        "find": "      if(!CircCatRetired(c)) cell++;",
        "replace": "      cell++;   // MUTATION: retired cells take a slot",
        "expect": "P-TH3-PARK-01",
    },
    {
        "id": "P-TH3-PARK-01e",
        "gate": "regression",
        "rule": "the ABCD drawing tool has no catalog seat, no grid slot, no V arm and no ring press - all COMMENTED, while the dispatcher and the leg meter stay live (P-TH3-PARK-01)",
        "what": "the INVERSE half: the ABCD dispatcher is commented out - the leg meter (P-LM-17) and the caption delete (P-TH3-DEL4) ride that call and go dark, which is the over-reach the user's scope forbade",
        "file": "Biotak/EventHandlers_Router.mqh",
        "find": "        OnABCDMouseEvent(id, lparam, dparam, sparam);",
        "replace": "        //OnABCDMouseEvent(id, lparam, dparam, sparam);   // MUTATION: the dispatcher is off",
        "expect": "P-TH3-PARK-01",
    },
    #--- P-BK-121/122/123 (2026-10-24) - a knot line is deleted only by its OWNER.
    #--- The user: «باگ ui داریم یا نه براش حلش بکن که الکی حذف و رسم بشه». Three
    #--- owners were measured in the terminal's journal; each mutation below puts one
    #--- of them back and the gate must refuse it.
    {
        "id": "P-BK-121a",
        "gate": "regression",
        "rule": "a knot line is deleted only by its owner: the note family is never swept, a leg that stopped being drawn is deleted, and a missed owner measurement keeps the published fact and retries (P-BK-121/122/123)",
        "what": "the orphan sweep stops asking the note predicate - a row tail parses as bid=\"NOTE\" and one row delete wipes the whole readout (journal: DELFLUSH obj=\"THLevels_BK_NOTE_*\")",
        "file": "Biotak/BaseKnot_Drag.mqh",
        "find": "else if(bid != \"\" && !BaseKnotNoteStemIs(bid))",
        "replace": "else if(bid != \"\")   // MUTATION: the note family is swept as an orphan box",
        "expect": "P-BK-121/122/123",
    },
    {
        "id": "P-BK-121b",
        "gate": "regression",
        "rule": "a knot line is deleted only by its owner: the note family is never swept, a leg that stopped being drawn is deleted, and a missed owner measurement keeps the published fact and retries (P-BK-121/122/123)",
        "what": "the predicate forgets what a note stem is - the handler's guard is called but never answers, so the sweep is back on",
        "file": "Biotak/BaseKnot_Note.mqh",
        "find": "   return (bid != \"\" && StringFind(BK_NOTE_CORNER, bid) == 0);",
        "replace": "   return false;   // MUTATION: no stem is recognised",
        "expect": "P-BK-121/122/123",
    },
    {
        "id": "P-BK-122a",
        "gate": "regression",
        "rule": "a knot line is deleted only by its owner: the note family is never swept, a leg that stopped being drawn is deleted, and a missed owner measurement keeps the published fact and retries (P-BK-121/122/123)",
        "what": "the committed tick walk stops at the TP COUNT again - a tick drawn by an earlier round is never reached, so a lowered count leaves its line on the chart",
        "file": "Biotak/BaseKnot_Plan.mqh",
        "find": "   for(int tk = 1; tk <= BK_TP_PLAN_MAX; tk++)\n   {\n      double lv = (tk <= BaseKnotTPCount() ? BaseKnotTPLevel(entry, dir, mTF, tk, nd.anchor) : 0.0);",
        "replace": "   for(int tk = 1; tk <= BaseKnotTPCount(); tk++)   // MUTATION: the walk shrinks to the count\n   {\n      double lv = BaseKnotTPLevel(entry, dir, mTF, tk, nd.anchor);",
        "expect": "P-BK-121/122/123",
    },
    {
        "id": "P-BK-122b",
        "gate": "regression",
        "rule": "a knot line is deleted only by its owner: the note family is never swept, a leg that stopped being drawn is deleted, and a missed owner measurement keeps the published fact and retries (P-BK-121/122/123)",
        "what": "an absent leg is skipped instead of deleted - the plan goes cold and the old line stays at its old price, a level the knot no longer claims",
        "file": "Biotak/BaseKnot_Plan.mqh",
        "find": "      if(lv <= 0.0) { ObjectDelete(0, BaseKnotTPTickName(pfx, tk)); continue; }",
        "replace": "      if(lv <= 0.0) continue;   // MUTATION: the ghost tick survives",
        "expect": "P-BK-121/122/123",
    },
    {
        "id": "P-BK-123a",
        "gate": "regression",
        "rule": "a knot line is deleted only by its owner: the note family is never swept, a leg that stopped being drawn is deleted, and a missed owner measurement keeps the published fact and retries (P-BK-121/122/123)",
        "what": "a missed owner measurement zeroes the published owner again - one unmeasurable round re-types the knot and redraws its family off the box' height until the next round",
        "file": "Biotak/BaseKnot_Owner.mqh",
        "find": "      else\n         s_bkOwnKeyId = \"\";   // P-BK-123:",
        "replace": "      else\n         g_bkBoxes[k].ownerTFMin = 0;   // MUTATION: a miss un-publishes the owner (and no retry)\n         // P-BK-123:",
        "expect": "P-BK-121/122/123",
    },
    {
        "id": "P-BK-123b",
        "gate": "regression",
        "rule": "a knot line is deleted only by its owner: the note family is never swept, a leg that stopped being drawn is deleted, and a missed owner measurement keeps the published fact and retries (P-BK-121/122/123)",
        "what": "the retry is dropped while the fact is kept - the key never changes again, so a one-round miss becomes the box' permanent reading",
        "file": "Biotak/BaseKnot_Owner.mqh",
        "find": "      else\n         s_bkOwnKeyId = \"\";   // P-BK-123:",
        "replace": "      else\n         { }   // MUTATION: the miss is never retried\n         // P-BK-123:",
        "expect": "P-BK-121/122/123",
    },
]

#--- the register's own entries, so "no mutation yet" is a NUMBER and not a feeling.
SECTION_RX = r"//\s*--\s*\d+\.\s*(P-[A-Z0-9]+(?:-\d+)?)"


def short_list(ids, cap=14):
    return ", ".join(ids[:cap]) + (" (+%d more)" % (len(ids) - cap) if len(ids) > cap else "")


def sha(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def run_gate(key):
    runner, rel_path, _label = GATES[key]
    cmd = [runner, os.path.join(ROOT, rel_path)]
    try:
        #--- P-LOG-11 (2026-10-04): the gates print the user's own words, curly quotes
        #--- included; on a non-UTF-8 console `text=True` alone decodes them with the
        #--- locale codec and RAISES inside the reader thread, so `p.stdout` came back
        #--- empty and a real kill was reported as "SURVIVED (wrong reason)" — measured
        #--- on P-DRAW-INK-a, whose message says “no colour of its own”. The bytes are
        #--- UTF-8; read them as such and never let a console codec swallow a proof.
        p = subprocess.run(cmd, cwd=ROOT, capture_output=True, timeout=600)
        out = (p.stdout or b"").decode("utf-8", "replace") + (p.stderr or b"").decode("utf-8", "replace")
    except (OSError, subprocess.TimeoutExpired) as e:
        return None, str(e)
    return p.returncode, out


def register_entries():
    import re
    try:
        with open(os.path.join(ROOT, REGISTER), encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError:
        return set()
    return {m.group(1) for m in re.finditer(SECTION_RX, text)}


def ascii_safe(s):
    """A gate may print a real em dash; this console is not UTF-8, so never echo bytes
    back raw — a proof line that renders as a question mark is not a proof line."""
    return "".join(c if ord(c) < 128 else "-" for c in s)


def proof_line(out, needle):
    for ln in out.splitlines():
        if needle in ln:
            return ascii_safe(ln.strip())[:150]
    tail = out.strip().splitlines()
    return ascii_safe(tail[-1])[:150] if tail else "(no output)"


def main():
    #--- P-DRAGF4 (2026-10-17): a `what` may carry Persian — «یک فریم عقب» killed the
    #--- census itself with UnicodeEncodeError on a cp1252 console (MEASURED, the first
    #--- run of P-DRAGF4-l). Replace the unencodable, never crash the census.
    try:
        sys.stdout.reconfigure(errors="replace")
    except Exception:
        pass
    argv = [a for a in sys.argv[1:]]
    picked = [a for a in argv if not a.startswith("-")]
    entries = register_entries()
    #--- P-DRAGF3 (2026-10-17): a register tag is covered when a mutation's `expect`
    #--- NAMES it — the id may carry a suffix (P-DRAGF3-a, P-UI-162e) and the tag
    #--- never does. MEASURED: exact-id matching listed P-DRAGF3 as "without one"
    #--- while all six of its mutations were KILLED (exit was right, the census read
    #--- as a contradiction).
    #--- P-BK-120 (2026-10-22): `expect` may carry the gate's own prefix (`[FAIL] P-…`)
    #--- so a kill cannot be claimed by a PASS line that merely names the rule. The
    #--- census below still reads the RULE, so the prefix is stripped here, once.
    witnessed = {m["expect"].replace("[FAIL] ", "").strip() for m in MUTATIONS}

    if "--list" in argv:
        print("MUTATIONS (one rule each)")
        for m in MUTATIONS:
            print("  %-13s %-11s %s" % (m["id"], GATES[m["gate"]][2], m["rule"]))
            print("                %s: %s" % (m["file"], m["what"]))
        print("")
        print("register entries: %d, with a kill witness: %d"
              % (len(entries), len(witnessed & entries)))
        print("without one: %s" % (short_list(sorted(entries - witnessed))))
        return 0

    todo = [m for m in MUTATIONS if not picked or any(p in m["id"] for p in picked)]
    if not todo:
        print("no mutation matches %s" % ", ".join(picked))
        return 2

    touched = sorted({m["file"] for m in todo})
    before = {f: sha(os.path.join(ROOT, f)) for f in touched}

    print("=" * 72)
    print("MUTATION GATE  (a rule is only gated if its inverse fails a gate)")
    print("=" * 72)
    killed, survived, stale = [], [], []  # killed / not gated / anchor gone
    for m in todo:
        path = os.path.join(ROOT, m["file"])
        with open(path, encoding="utf-8", newline="") as fh:
            orig = fh.read()
        #--- the anchor is matched LINE-ENDING INSENSITIVE: the tree mixes CRLF and
        #--- LF files (a tool writes one, another writes the other), and an anchor
        #--- spelled with "\n" must not go stale just because the file it names is
        #--- a CRLF one. The RAW bytes are kept for the restore, so the file comes
        #--- back byte-identical whatever the mutation did.
        norm = orig.replace("\r\n", "\n")
        find = m["find"].replace("\r\n", "\n")
        repl = m["replace"].replace("\r\n", "\n")
        hits = norm.count(find)
        label = "%-13s %-11s" % (m["id"], GATES[m["gate"]][2])
        if hits != 1:
            stale.append(m)
            print("  %s STALE   anchor found %d time(s) in %s — the rule moved or the "
                  "spelling changed" % (label, hits, m["file"]))
            print("                %s" % m["what"])
            continue
        try:
            mutated = norm.replace(find, repl)
            if "\r\n" in orig:
                mutated = mutated.replace("\n", "\r\n")
            with open(path, "w", encoding="utf-8", newline="") as fh:
                fh.write(mutated)
            rc, out = run_gate(m["gate"])
        finally:
            with open(path, "w", encoding="utf-8", newline="") as fh:
                fh.write(orig)
        if rc is None:
            survived.append(m)
            print("  %s ERROR   gate did not run: %s" % (label, ascii_safe(out)))
            continue
        if rc != 0 and m["expect"] in out:
            killed.append(m)
            print("  %s KILLED  %s" % (label, m["what"]))
            print("                proof: %s" % proof_line(out, m["expect"]))
        elif rc == 0:
            survived.append(m)
            print("  %s SURVIVED the gate passed with the defect back: %s" % (label, m["what"]))
            print("                rule: %s" % m["rule"])
        else:
            survived.append(m)
            print("  %s SURVIVED (wrong reason) the gate failed without naming the rule "
                  "(%r)" % (label, m["expect"]))
            print("                proof: %s" % proof_line(out, "FAIL"))

    #--- the tree must be exactly as we found it, or nothing here is trustworthy.
    after = {f: sha(os.path.join(ROOT, f)) for f in touched}
    drifted = [f for f in touched if before[f] != after[f]]
    print("")
    if drifted:
        print("TREE NOT RESTORED — %s" % ", ".join(drifted))
        return 2
    missing = sorted(entries - witnessed)
    print("mutations: %d  killed: %d  survived: %d  stale: %d   (tree restored, %d file(s) "
          "byte-identical)" % (len(todo), len(killed), len(survived), len(stale),
                               len(touched)))
    print("register entries: %d, covered by a mutation: %d%s"
          % (len(entries), len(witnessed & entries),
             ("\nwithout one: " + short_list(missing)) if missing else ""))
    if survived or stale:
        print("")
        print("FAIL: %d rule(s) are not gated (survived) and %d mutation(s) no longer "
              "apply (stale)." % (len(survived), len(stale)))
        return 1
    print("")
    print("PASS - every mutation was killed by the gate that owns its rule, and the tree "
          "is byte-identical to how it was found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
