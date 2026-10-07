# P-LOOK-RAY2 splice (2026-10-04). Applied once, then this directory is deleted.
import sys

FIB = "Biotak/FibPen.mqh"
PICK = "Biotak/DrawStrip_Pick.mqh"


def load(p):
    raw = open(p, "rb").read().decode("utf-8")
    txt = raw.replace("\r\n", "\n")
    if "\r" in txt:
        print("!! stray CR in " + p)
        sys.exit(1)
    return txt


def save(p, txt):
    if "\r" in txt:
        print("!! stray CR in " + p)
        sys.exit(1)
    open(p, "wb").write(txt.replace("\n", "\r\n").encode("utf-8"))


def apply(txt, edits, who):
    lines = txt.split("\n")
    for i, e in enumerate(edits):
        if e[0] is None and e[1] == "MARK":
            _, _, marker, span, new = e
            hits = [k for k, l in enumerate(lines) if marker in l]
            if len(hits) != 1:
                print("!! %s edit %d: marker %r hit %d times" % (who, i, marker, len(hits)))
                sys.exit(1)
            k = hits[0]
            lines[k:k + span] = new.split("\n")
            txt = "\n".join(lines)
            continue
        old, new = e
        c = txt.count(old)
        if c != 1:
            print("!! %s edit %d matched %d times" % (who, i, c))
            print(old[:200])
            sys.exit(1)
        txt = txt.replace(old, new, 1)
    return txt


BLOCK = open("tools/.patch/block.txt", "rb").read().decode("utf-8").replace("\r\n", "\n")
if not BLOCK.endswith("\n"):
    BLOCK += "\n"

E1 = ("//--- the FIBPEN witness channel (PathTool.mqh:31 is the precedent): Full borrows",
      BLOCK + "//--- the FIBPEN witness channel (PathTool.mqh:31 is the precedent): Full borrows")

E2 = ("   bool anchorsOk = (ta > 0 && tb > 0 && p1 > 0.0 && p2 > 0.0);\n",
      "   bool anchorsOk = (ta > 0 && tb > 0 && p1 > 0.0 && p2 > 0.0);\n"
      "   //--- P-LOOK-RAY2: the pen mirrors the master's own level rays (one read per sync).\n"
      "   bool penRL = false, penRR = false;\n"
      "   FibPenRayPair(fibo, penRL, penRR);\n")

#--- line-based anchors: the source uses em dashes in those comments, so match by marker.
E3 = (None,
      "MARK",
      "// P-LOOK-RAY (2026-10-03)",
      5,
      '''            // P-LOOK-RAY2: the pen is as wide as the LINE, not wider. The fibo's own
            // level-ray pair is read once above; a level line that stops at its anchors
            // gets a pen that stops with it, one that runs edge to edge gets a pen that
            // does the same.
            ObjectSetInteger(0, nm2, OBJPROP_RAY_LEFT, penRL);
            ObjectSetInteger(0, nm2, OBJPROP_RAY_RIGHT, penRR);''')

E3_UNUSED = ('''x''',
      '''            // P-LOOK-RAY2: the pen is as wide as the LINE, not wider. The fibo's own
            // level-ray pair is read once above; a level line that stops at its anchors
            // gets a pen that stops with it, one that runs edge to edge gets a pen that
            // does the same.
            ObjectSetInteger(0, nm2, OBJPROP_RAY_LEFT, penRL);
            ObjectSetInteger(0, nm2, OBJPROP_RAY_RIGHT, penRR);''')

E4 = (None,
      "MARK",
      "// P-LOOK-RAY: raise the segments this fix was born with",
      5,
      '''         // P-LOOK-RAY2: heal the mirror - guarded, and in BOTH directions, because a
         // fibo whose levels ray was turned off must take its pen back to the anchors
         // (the case the old heal could not express: it only ever raised).
         if(((int)ObjectGetInteger(0, nm2, OBJPROP_RAY_LEFT) != 0) != penRL)
            ObjectSetInteger(0, nm2, OBJPROP_RAY_LEFT, penRL);
         if(((int)ObjectGetInteger(0, nm2, OBJPROP_RAY_RIGHT) != 0) != penRR)
            ObjectSetInteger(0, nm2, OBJPROP_RAY_RIGHT, penRR);''')

E4_UNUSED = ('''x''',
      '''         // P-LOOK-RAY2: heal the mirror - guarded, and in BOTH directions, because a
         // fibo whose levels ray was turned off must take its pen back to the anchors
         // (the case the old heal could not express: it only ever raised).
         if(((int)ObjectGetInteger(0, nm2, OBJPROP_RAY_LEFT) != 0) != penRL)
            ObjectSetInteger(0, nm2, OBJPROP_RAY_LEFT, penRL);
         if(((int)ObjectGetInteger(0, nm2, OBJPROP_RAY_RIGHT) != 0) != penRR)
            ObjectSetInteger(0, nm2, OBJPROP_RAY_RIGHT, penRR);''')

E5 = ('''            ObjectSetInteger(0, cnm, OBJPROP_RAY_LEFT, true);   // P-LOOK-RAY: the tube rides the full width too
            ObjectSetInteger(0, cnm, OBJPROP_RAY_RIGHT, true);''',
      '''            ObjectSetInteger(0, cnm, OBJPROP_RAY_LEFT, penRL);   // P-LOOK-RAY2: the tube rides the line's own span
            ObjectSetInteger(0, cnm, OBJPROP_RAY_RIGHT, penRR);''')

E6 = ('''      if((int)ObjectGetInteger(0, cnm, OBJPROP_RAY_LEFT) == 0)
         ObjectSetInteger(0, cnm, OBJPROP_RAY_LEFT, true);
      if((int)ObjectGetInteger(0, cnm, OBJPROP_RAY_RIGHT) == 0)
         ObjectSetInteger(0, cnm, OBJPROP_RAY_RIGHT, true);''',
      '''      if(((int)ObjectGetInteger(0, cnm, OBJPROP_RAY_LEFT) != 0) != penRL)
         ObjectSetInteger(0, cnm, OBJPROP_RAY_LEFT, penRL);
      if(((int)ObjectGetInteger(0, cnm, OBJPROP_RAY_RIGHT) != 0) != penRR)
         ObjectSetInteger(0, cnm, OBJPROP_RAY_RIGHT, penRR);''')

E7 = ('''            ObjectSetInteger(0, wnm, OBJPROP_RAY_LEFT, true);   // P-LOOK-RAY: the halo hugs the whole level
            ObjectSetInteger(0, wnm, OBJPROP_RAY_RIGHT, true);''',
      '''            ObjectSetInteger(0, wnm, OBJPROP_RAY_LEFT, penRL);   // P-LOOK-RAY2: the halo hugs the level's own span
            ObjectSetInteger(0, wnm, OBJPROP_RAY_RIGHT, penRR);''')

E8 = ('''      if((int)ObjectGetInteger(0, wnm, OBJPROP_RAY_LEFT) == 0)
         ObjectSetInteger(0, wnm, OBJPROP_RAY_LEFT, true);
      if((int)ObjectGetInteger(0, wnm, OBJPROP_RAY_RIGHT) == 0)
         ObjectSetInteger(0, wnm, OBJPROP_RAY_RIGHT, true);''',
      '''      if(((int)ObjectGetInteger(0, wnm, OBJPROP_RAY_LEFT) != 0) != penRL)
         ObjectSetInteger(0, wnm, OBJPROP_RAY_LEFT, penRL);
      if(((int)ObjectGetInteger(0, wnm, OBJPROP_RAY_RIGHT) != 0) != penRR)
         ObjectSetInteger(0, wnm, OBJPROP_RAY_RIGHT, penRR);''')

E9 = ('''      bool dd = FibPenStraysDrop(fibo);
      if(dd || dirty)
         DrawStripDiagEmit("[drawstrip] FIBPEN fibo=\\"" + fibo + "\\" dropall=1 look=" + IntegerToString(lk));
      return (dd || dirty);''',
      '''      bool dd = FibPenStraysDrop(fibo);
      if(dd || dirty)
         DrawStripDiagEmit("[drawstrip] FIBPEN fibo=\\"" + fibo + "\\" dropall=1 look=" + IntegerToString(lk));
      //--- P-LOOK-RAY2: the net's memo follows the truth - no pen stands here now, so the
      //--- next pass asks the master (and only a master that asks for one is served).
      FibPenNetWrite(fibo, (long)ObjectGetInteger(0, fibo, OBJPROP_TIME, 0),
                     (long)ObjectGetInteger(0, fibo, OBJPROP_TIME, 1),
                     ObjectGetDouble(0, fibo, OBJPROP_PRICE, 0),
                     ObjectGetDouble(0, fibo, OBJPROP_PRICE, 1),
                     FibPenRayBits(fibo), false);
      return (dd || dirty);''')

E10 = ('''   return dirty;
}
#endif // FIBPEN_MQH''',
       '''   //--- P-LOOK-RAY2: the pen just built IS the pen this master asks for - the net's
   //--- memo records the master it was built from, so the next 2 s pass is one compare.
   FibPenNetWrite(fibo, (long)ta, (long)tb, p1, p2, FibPenRayBits(fibo), FibPenHasPen(fibo));
   return dirty;
}
#endif // FIBPEN_MQH''')

E11 = ('''   double dp = cp - s_fibCurP0;
   int    dtS = (int)(ct - s_fibCurT0);
   double pa = 0.0, pb = 0.0;
   datetime ta = 0, tb = 0;
   if(s_fibGrab == FIBPEN_GRAB_BODY)
   {
      pa = s_fibP0[0] + dp; pb = s_fibP0[1] + dp;
      ta = (datetime)((long)s_fibT0[0] + dtS);
      tb = (datetime)((long)s_fibT0[1] + dtS);
   }
   else if(s_fibGrab == 0) { pa = cp; ta = ct; pb = s_fibP0[1]; tb = s_fibT0[1]; }
   else                    { pa = s_fibP0[0]; ta = s_fibT0[0]; pb = cp; tb = ct; }
   if(!(pa > 0.0) || !(pb > 0.0) || ta <= 0 || tb <= 0) return;''',
       '''   //--- (3) THE GEOMETRY: the snapshot plus the hand's own delta since it. A body drag
   //--- translates the WHOLE pair (the only shape that can keep a translated drawing a
   //--- drawing); an anchor drag is a single side riding the cursor.
   //--- AND THE SPAN IS THE MASTER'S OWN (P-LOOK-RAY2). The children's TIMES are the two
   //--- anchors the master has RIGHT NOW - never an estimate: the pen must cover the span
   //--- the line covers (a level line that stops at its anchors, `levels_ray` off, would
   //--- otherwise get a pen that stops somewhere else - the very defect the mirror rule
   //--- exists to end). The PRICES ride ahead (that is the drag event's own lag, and the
   //--- reason the chase exists); the span never does.
   double dp = cp - s_fibCurP0;
   double pa = 0.0, pb = 0.0;
   if(s_fibGrab == FIBPEN_GRAB_BODY) { pa = s_fibP0[0] + dp; pb = s_fibP0[1] + dp; }
   else if(s_fibGrab == 0)           { pa = cp;            pb = s_fibP0[1]; }
   else                              { pa = s_fibP0[0];    pb = cp; }
   if(!(pa > 0.0) || !(pb > 0.0)) return;
   datetime ta = t1, tb = t2;''')

E12 = ('''                           " g=" + IntegerToString(s_fibGrab) + " dp=" + DoubleToString(dp, _Digits) +
                           " dt=" + IntegerToString(dtS) + " s=" + IntegerToString((int)GetTickCount()));''',
       '''                           " g=" + IntegerToString(s_fibGrab) + " dp=" + DoubleToString(dp, _Digits) +
                           " s=" + IntegerToString((int)GetTickCount()));''')

E13 = ("static double   s_fibCurP0  = 0.0;            // the cursor that resync was taken at\n"
       "static datetime s_fibCurT0  = 0;\n",
       "static double   s_fibCurP0  = 0.0;            // the cursor that resync was taken at\n")

E14 = ("   s_fibCurP0 = 0.0; s_fibCurT0 = 0;\n", "   s_fibCurP0 = 0.0;\n")

FIB_EDITS = [E1, E2, E3, E4, E5, E6, E7, E8, E9, E10, E11, E12, E13, E14]

txt = load(FIB)
txt = apply(txt, FIB_EDITS, "FibPen")
c = txt.count("      s_fibCurP0 = cp; s_fibCurT0 = ct;\n")
if c < 1:
    print("!! resync seats not found")
    sys.exit(1)
txt = txt.replace("      s_fibCurP0 = cp; s_fibCurT0 = ct;\n", "      s_fibCurP0 = cp;\n")
for gone in ("s_fibCurT0", "dtS"):
    if gone in txt:
        print("!! %s survives" % gone)
        sys.exit(1)
save(FIB, txt)
print("ok FibPen.mqh: %d edits + %d resync seats" % (len(FIB_EDITS), c))

# ------------------------------------------------------- DrawStrip_Pick.mqh (2 s pass)
P1 = ('''      if(BoxIsMidChild(nm))
      {
         string par = BoxMidParent(nm);
         if(par == "" || ObjectFind(0, par) < 0) ObjectDelete(0, nm);
         continue;
      }''',
      '''      if(BoxIsMidChild(nm))
      {
         string par = BoxMidParent(nm);
         if(par == "" || ObjectFind(0, par) < 0) ObjectDelete(0, nm);
         continue;
      }
      //--- P-LOOK-RAY2: the pen's children answer for their own parent too (the same
      //--- orphan rule, one family over). A fibo deleted while the indicator was off
      //--- leaves `_FSD/_FSC/_FSW` bands whose master is gone - a styled line drawn on
      //--- nothing is exactly what "strays" means here, and nothing else knew them.
      if(FibPenIsChild(nm) || FibPenFamIsChild(nm))
      {
         string par = FibPenChildParent(nm);
         if(par == "" || ObjectFind(0, par) < 0) ObjectDelete(0, nm);
         continue;
      }''')

P2 = ("      if(ty != OBJ_RECTANGLE) continue;\n",
      '''      //--- P-LOOK-RAY2 (2026-10-04) - THE PEN'S NET RIDES THE PASS THAT ALREADY PAYS
      //--- THE TYPE READ. The pen had only event paths, so a master the terminal landed
      //--- after the last event kept a stale pen forever (measured: the pen ran x=59..721
      //--- against level lines at x=681..1079 - "the styles are not applied on the right
      //--- side"). `FibPenHeal` is one memo compare while the pen matches the master it
      //--- was built from, and the sync only on a mismatch.
      if(ty == OBJ_FIBO || ty == OBJ_FIBOFAN) FibPenHeal(nm);
      if(ty != OBJ_RECTANGLE) continue;
''')

txt = load(PICK)
txt = apply(txt, [P1, P2], "Pick")
save(PICK, txt)
print("ok DrawStrip_Pick.mqh: 2 edits")
