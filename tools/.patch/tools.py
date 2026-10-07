# Restate P-DRAW-74b/P-DRAGF2's ray assertions to the P-LOOK-RAY2 law, and swap the
# P-DRAW-74b-d mutation for the three P-LOOK-RAY2 ones. Temporary; deleted after the build.
import sys


def load(p):
    txt = open(p, "rb").read().decode("utf-8").replace("\r\n", "\n")
    if "\r" in txt:
        print("!! stray CR in " + p)
        sys.exit(1)
    return txt


def save(p, txt):
    open(p, "wb").write(txt.replace("\n", "\r\n").encode("utf-8"))


def patch(p, edits):
    txt = load(p)
    for i, (old, new) in enumerate(edits):
        c = txt.count(old)
        if c != 1:
            print("!! %s edit %d matched %d times" % (p, i, c))
            print(old[:200])
            sys.exit(1)
        txt = txt.replace(old, new, 1)
    save(p, txt)
    print("ok %s: %d edits" % (p, len(edits)))


REG = "tools/check-regressions.js"
MUT = "tools/mutation_gate.py"

# --- 1. the old ray assertions out (P-DRAW-74b's "always edge to edge")
OLD_RAY = '''    if (!/ObjectSetInteger\\(0, nm2, OBJPROP_RAY_RIGHT, true\\)/.test(fib))
      broken.push('the stack rides a segment \u2014 a fibo level spans edge to edge, rays carry the thickness with it (P-DRAW-74b)');
    // P-DRAW-74b-d's inverse, and the reason it went UNGATED: the born-with write is
    // followed by a self-heal (`if RAY == 0 -> true`), so "the true write exists
    // somewhere" is blind to a run that LOWERS the ray \u2014 measured 2026-10-04, the
    // P-DRAW-74b-d mutation (true -> false) survived that assertion. A level's own ray
    // is therefore never allowed to be set false, in any writer.
    if (/ObjectSetInteger\\(0, nm2, OBJPROP_RAY_(LEFT|RIGHT), false\\)/.test(fib))
      broken.push('a level\\'s own ray is LOWERED \u2014 the stack rides a segment and thick ink lands on the anchors alone (P-DRAW-74b)');
'''

NEW_RAY = '''    // P-LOOK-RAY2 (2026-10-04) \u2014 THE PEN MIRRORS THE MASTER, IT IS NOT ALWAYS WIDER.
    // P-DRAW-74b-d's rule ("the stack always rides rays") rested on a premise that was
    // measured FALSE on the hand's own chart: MT4's fibo owns its level-ray flag
    // (`levels_ray`), the strip's RAY cell writes it, and with it OFF the level lines
    // stop AT THE ANCHORS \u2014 measured 2026-10-04 on `Fibo 54705`: its level rows ran
    // x=681..1079 while the pen's four rows still ran x=59..721, i.e. the style hung in
    // empty space on the left and stopped 40px short of the line on the right, which is
    // the report this gate now owns («\u0686\u0631\u0627 \u0627\u0633\u062a\u0627\u06cc\u0644 \u0647\u0627 \u0628\u0631\u0627 \u0633\u0645\u062a \u0631\u0627\u0633\u062a \u0627\u0639\u0645\u0627\u0644 \u0646\u0634\u062f\u0647 \u0628\u0627\u06cc\u062f \u0647\u0631 \u062c\u0627 \u0647\u0633\u062a\u0634 \u0627\u0639\u0645\u0627\u0644 \u0634\u0647 \u062f\u06cc\u06af\u0647»).
    // The law: the children wear the MASTER's own pair \u2014 read once, at birth and on
    // every heal, in BOTH directions (a turned-off level ray must take the pen back to
    // the anchors; the old heal could only ever raise).
    if (!/void FibPenRayPair\\([^)]*\\)\\s*\\{[\\s\\S]{0,400}?OBJPROP_RAY_LEFT\\) != 0\\)/.test(fib) ||
        !/void FibPenRayPair\\([^)]*\\)\\s*\\{[\\s\\S]{0,400}?OBJPROP_RAY_RIGHT\\) != 0\\)/.test(fib))
      broken.push('the pen no longer READS the master\\'s own level rays \u2014 it can only be right by accident (P-LOOK-RAY2)');
    if (!/FibPenRayPair\\(fibo, penRL, penRR\\);/.test(fib))
      broken.push('the mirror pair is read nowhere \u2014 the children\\'s span is a guess again (P-LOOK-RAY2)');
    if (!/ObjectSetInteger\\(0, nm2, OBJPROP_RAY_LEFT, penRL\\)/.test(fib) ||
        !/ObjectSetInteger\\(0, nm2, OBJPROP_RAY_RIGHT, penRR\\)/.test(fib))
      broken.push('a child is born with a fixed ray \u2014 the pen\\'s width must mirror the level line\\'s span (P-LOOK-RAY2)');
    if (!/\\(\\(int\\)ObjectGetInteger\\(0, nm2, OBJPROP_RAY_RIGHT\\) != 0\\) != penRR/.test(fib))
      broken.push('the mirror is only ever RAISED \u2014 a fibo whose levels ray was turned off keeps a pen hanging past the line (P-LOOK-RAY2)');
    if (/ObjectSetInteger\\(0, nm2, OBJPROP_RAY_(LEFT|RIGHT), true\\)/.test(fib))
      broken.push('a hardcoded TRUE ray is back on the stack \u2014 the pen covers a span the line does not have (P-LOOK-RAY2)');
'''

# --- 2. the P-DRAGF2 landing-probe assertion (the span is the master's now)
OLD_PROBE = '''    if (!/p1 != s_fibProbeP\\[0\\]/.test(fib) || !/s_fibCurP0 = cp; s_fibCurT0 = ct;/.test(fib))
      broken.push('no landing probe \u2014 the snapshot drifts against the master until release instead of resyncing (P-DRAGF2)');
'''

NEW_PROBE = '''    if (!/p1 != s_fibProbeP\\[0\\]/.test(fib) || !/s_fibCurP0 = cp;/.test(fib))
      broken.push('no landing probe \u2014 the snapshot drifts against the master until release instead of resyncing (P-DRAGF2)');
    // P-LOOK-RAY2: and the SPAN is never the chase's own. The children's times are the
    // two anchors the master has right now \u2014 an estimated span (dtS) is what let a pen
    // stop short of the line it is the style of. The PRICES ride ahead; the span does not.
    if (!/datetime ta = t1, tb = t2;/.test(fib))
      broken.push('the chase writes its own span into the children \u2014 the pen\\'s extent then drifts from the line\\'s (P-LOOK-RAY2)');
    if (/dtS/.test(fib))
      broken.push('an estimated span is back in the chase \u2014 the pen\\'s times are the master\\'s own (P-LOOK-RAY2)');
'''

# --- 3. the pen's own net (assertions ride the P-DRAW-74b block, where `pk` is in scope)
OLD_TAIL = '''    if (!/PICK slot=/.test(tpt))
      broken.push('taps leave no number \u2014 slot, row, object and read-back ride the flushed channel (P-DRAW-74b)');
'''

NEW_TAIL = OLD_TAIL + '''    // P-LOOK-RAY2 \u2014 AND THE PEN'S OWN NET. Every follower in this repo has one seat that
    // needs no event (the interior and the 50 % line ride this 2 s pass). The pen had only
    // event paths, so a master the terminal landed after the last event kept a stale pen
    // FOREVER: the very scene above, still stale hours later. The pass that already pays
    // one type read per object now asks each fibo \u2014 and the orphan rule rides it too.
    if (!/if\\(ty == OBJ_FIBO \\|\\| ty == OBJ_FIBOFAN\\) FibPenHeal\\(nm\\);/.test(pk))
      broken.push('the pen has no net \u2014 a master the terminal moves with no event keeps a stale pen until the next touch (P-LOOK-RAY2)');
    if (!/bool FibPenHeal\\([^)]*\\)\\s*\\{[\\s\\S]{0,900}?FibPenNetFind\\(fibo\\)/.test(fib) ||
        !/bool FibPenHeal\\([^)]*\\)\\s*\\{[\\s\\S]{0,1400}?return FibPenSync\\(fibo, false\\);/.test(fib))
      broken.push('`FibPenHeal` stopped comparing the master against the memo before it syncs \u2014 the net becomes an unconditional sync (P-LOOK-RAY2)');
    if (!/FibPenNetWrite\\(fibo, \\(long\\)ta, \\(long\\)tb, p1, p2, FibPenRayBits\\(fibo\\), FibPenHasPen\\(fibo\\)\\);/.test(fib))
      broken.push('the sync never writes the memo \u2014 every 2 s pass would re-run the whole sync per fibo (P-LOOK-RAY2)');
    if (!/FibPenIsChild\\(nm\\) \\|\\| FibPenFamIsChild\\(nm\\)/.test(pk) || !/string FibPenChildParent\\(/.test(fib))
      broken.push('the pen\\'s children have no parent oracle \u2014 a band whose fibo is gone survives a reattach (P-LOOK-RAY2)');
'''

# --- 4. the mutation: P-DRAW-74b-d -> the three P-LOOK-RAY2 ones
OLD_MUT = '''    #--- P-DRAW-74b-d \u2014 P-LOOK-RAY: THE STACK RIDES THE LEVEL. A fibo level
    #--- spans edge to edge (the hand's own screenshot proves it); segment
    #--- children thicken only their anchors and read as "no effect".
    {
        "id": "P-DRAW-74b-d",
        "gate": "regression",
        "rule": "the stacked children ride rays, edge to edge with the level",
        "what": "the stack goes back to a segment (thick nowhere but the anchors)",
        "file": "Biotak/FibPen.mqh",
        "find": "            ObjectSetInteger(0, nm2, OBJPROP_RAY_LEFT, true);\\r\\n"
                "            ObjectSetInteger(0, nm2, OBJPROP_RAY_RIGHT, true);\\r\\n",
        "replace": "            ObjectSetInteger(0, nm2, OBJPROP_RAY_LEFT, false);   // MUTATION: segment again\\r\\n"
                   "            ObjectSetInteger(0, nm2, OBJPROP_RAY_RIGHT, false);\\r\\n",
        "expect": "P-DRAW-74b",
    },
'''

NEW_MUT = '''    #--- P-LOOK-RAY2 \u2014 THE PEN MIRRORS THE MASTER (2026-10-04). P-LOOK-RAY's "a level is
    #--- full width" was measured FALSE on the hand's own chart: the fibo carries its own
    #--- level-ray flag (`levels_ray`), and with it off the level lines stop AT THE
    #--- ANCHORS (`Fibo 54705`, x=681..1079) while a hardcoded-both-rays pen ran x=59..721
    #--- \u2014 the style hung in empty space on the left and stopped 40px short of the line
    #--- on the right («\u0686\u0631\u0627 \u0627\u0633\u062a\u0627\u06cc\u0644 \u0647\u0627 \u0628\u0631\u0627 \u0633\u0645\u062a \u0631\u0627\u0633\u062a \u0627\u0639\u0645\u0627\u0644 \u0646\u0634\u062f\u0647»). This mutation puts the hardcoded
    #--- TRUE pair back, the shape that produced it.
    {
        "id": "P-LOOK-RAY2-a",
        "gate": "regression",
        "rule": "the stacked children mirror the fibo's own level rays",
        "what": "a fixed both-rays child comes back (the pen covers a span the line has not)",
        "file": "Biotak/FibPen.mqh",
        "find": "            ObjectSetInteger(0, nm2, OBJPROP_RAY_LEFT, penRL);\\r\\n"
                "            ObjectSetInteger(0, nm2, OBJPROP_RAY_RIGHT, penRR);\\r\\n",
        "replace": "            ObjectSetInteger(0, nm2, OBJPROP_RAY_LEFT, true);   // MUTATION: the old fixed ray\\r\\n"
                   "            ObjectSetInteger(0, nm2, OBJPROP_RAY_RIGHT, true);\\r\\n",
        "expect": "P-LOOK-RAY2",
    },
    #--- P-LOOK-RAY2-b \u2014 THE PEN'S OWN NET. The pen had only event paths, so a master the
    #--- terminal landed after the last event kept a stale pen forever (the scene above,
    #--- hours old). The 2 s pass asks each fibo now; this mutation takes the seat away.
    {
        "id": "P-LOOK-RAY2-b",
        "gate": "regression",
        "rule": "the pen has its own net on the 2 s chart-side pass",
        "what": "the net seat is gone (a stale pen stays stale until the next touch)",
        "file": "Biotak/DrawStrip_Pick.mqh",
        "find": "      if(ty == OBJ_FIBO || ty == OBJ_FIBOFAN) FibPenHeal(nm);\\r\\n",
        "replace": "      // MUTATION: no net\\r\\n",
        "expect": "P-LOOK-RAY2",
    },
    #--- P-LOOK-RAY2-c \u2014 THE HEAL COMPARES BEFORE IT SYNCS, or the net is a full sync of
    #--- every fibo on every pass (this repo's law: a still frame pays reads, writes none).
    {
        "id": "P-LOOK-RAY2-c",
        "gate": "regression",
        "rule": "FibPenHeal is a memo compare first, the sync only on a mismatch",
        "what": "the memo compare goes out (every pass syncs every fibo)",
        "file": "Biotak/FibPen.mqh",
        "find": "   int    at  = FibPenNetFind(fibo);\\r\\n",
        "replace": "   int    at  = -1;   // MUTATION: no memo\\r\\n",
        "expect": "P-LOOK-RAY2",
    },
'''

patch(REG, [(OLD_RAY, NEW_RAY), (OLD_PROBE, NEW_PROBE), (OLD_TAIL, NEW_TAIL)])
patch(MUT, [(OLD_MUT, NEW_MUT)])
