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
        "find": "   if(k == DK_FIBO || k == DK_FIBOFAN) return false;\r\n",
        "replace": "   // MUTATION: pen kinds coerced again\r\n",
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
        "find": "      if(ty == OBJ_FIBO || ty == OBJ_FIBOFAN) FibPenHeal(nm);\r\n",
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
    #--- flush puts it on screen.
    {
        "id": "P-DRAW-74b-g",
        "gate": "regression",
        "rule": "the release that re-stamps the followers flushes one frame",
        "what": "the release flush goes back out (the last frame settles late)",
        "file": "Biotak/DrawStrip_Router.mqh",
        "find": "            FibPenSync(relPressObj, false);   // P-DRAW-74b: the release re-states the pair too\r\n"
                "            FibPenDragDisarm();   // P-DRAGF: the gesture is over, the chase stands down\r\n"
                "            ChartRedraw();   // P-DRAW-74b-f: the release flushes the re-stamp\r\n",
        "replace": "            FibPenSync(relPressObj, false);   // P-DRAW-74b: the release re-states the pair too\r\n"
                   "            FibPenDragDisarm();   // P-DRAGF: the gesture is over, the chase stands down\r\n",
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
        "file": "Biotak/Toolbar_B.mqh",
        "find": "      FileWrite(h, (int)k, DRAW_LASTLOOK_SLOT,\r\n                DoubleToString(DrawStylePackB(k), 0), DoubleToString(DrawStylePackA(k), 0));\r\n",
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
        "file": "Biotak/Toolbar_B.mqh",
        "find": "      if(i == DRAW_LASTLOOK_SLOT) { DrawStyleUnpack(k, StringToDouble(pk), StringToDouble(nm)); continue; }\r\n",
        "replace": "      // MUTATION: the last look is read and thrown away\r\n",
        "expect": "P-DRAW-09c",
    },
    #--- P-DRAW-09c-c — THE WRITER PERSISTS WHAT IT LEARNED. One write per user
    #--- act, from the same tail that sets `s_dkValid[k]`: a look learned and not
    #--- saved is the exact sentence the entry is about.
    {
        "id": "P-DRAW-09c-c",
        "gate": "regression",
        "rule": "the ONE slot writer persists the look it just learned",
        "what": "learning stops saving (the look is remembered until the next attach and no further)",
        "file": "Biotak/Toolbar_B.mqh",
        "find": "   DrawPresetsSave();\r\n   return true;\r\n}\r\n\r\n//--- THE STYLE THE USER LAST USED FOR THIS KIND",
        "replace": "   return true;\r\n}\r\n\r\n//--- THE STYLE THE USER LAST USED FOR THIS KIND",
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
        "file": "Biotak/Toolbar_B.mqh",
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
        "file": "Biotak/Toolbar_B.mqh",
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
        "file": "Biotak/Toolbar_B.mqh",
        "find": "   if((int)s_dkAnyClr >= 0)\r\n      FileWrite(h, 1, DRAW_LASTINK_SLOT, IntegerToString((int)s_dkAnyClr), \"0\");\r\n",
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
    argv = [a for a in sys.argv[1:]]
    picked = [a for a in argv if not a.startswith("-")]
    entries = register_entries()
    covered = {m["id"] for m in MUTATIONS}

    if "--list" in argv:
        print("MUTATIONS (one rule each)")
        for m in MUTATIONS:
            print("  %-13s %-11s %s" % (m["id"], GATES[m["gate"]][2], m["rule"]))
            print("                %s: %s" % (m["file"], m["what"]))
        print("")
        print("register entries: %d, with a kill witness: %d"
              % (len(entries), len(covered & entries)))
        print("without one: %s" % (short_list(sorted(entries - covered))))
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
        hits = orig.count(m["find"])
        label = "%-13s %-11s" % (m["id"], GATES[m["gate"]][2])
        if hits != 1:
            stale.append(m)
            print("  %s STALE   anchor found %d time(s) in %s — the rule moved or the "
                  "spelling changed" % (label, hits, m["file"]))
            print("                %s" % m["what"])
            continue
        try:
            with open(path, "w", encoding="utf-8", newline="") as fh:
                fh.write(orig.replace(m["find"], m["replace"]))
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
    missing = sorted(entries - covered)
    print("mutations: %d  killed: %d  survived: %d  stale: %d   (tree restored, %d file(s) "
          "byte-identical)" % (len(todo), len(killed), len(survived), len(stale),
                               len(touched)))
    print("register entries: %d, covered by a mutation: %d%s"
          % (len(entries), len(covered & entries),
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
