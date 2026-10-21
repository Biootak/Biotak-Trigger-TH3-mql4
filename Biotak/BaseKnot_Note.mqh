//+------------------------------------------------------------------+
//| BaseKnot_Note.mqh                                               |
//| P-BK-104 / P-BK-109 — THE NOTE'S OWN TEXT FIELDS.                |
//|                                                                  |
//| Three builders, one job: the fields the base note PRINTS on its   |
//| face. Each one is a NAME for a number the geometry already        |
//| produced, never a second measurement — so the face can carry the |
//| trade's two legs and the type's own ATR without any of them       |
//| becoming a number of its own.                                    |
//|                                                                  |
//| WHY ITS OWN FILE: the note's text owners drifted over the         |
//| 1500-line ceiling (contract §7). The seam was already here — the  |
//| fields are read by exactly ONE writer (`BaseKnotWriteInfo`,       |
//| BaseKnot_Plan.mqh) and read nothing of each other, so cutting    |
//| them out is a cut along an owner, not along a call. MQL4         |
//| resolves top-down, so this half is included ABOVE its caller       |
//| (BaseKnotTool.mqh's own order), exactly like P-SIZE-SPLIT's.     |
//+------------------------------------------------------------------+
#ifndef BASE_KNOT_NOTE_MQH
#define BASE_KNOT_NOTE_MQH

//+------------------------------------------------------------------+
//| P-BK-104 (2026-10-09, user: «اینو کنار بزار محاسباتشو و از همون  |
//| engsl, huntsl که هستش استفاده بکنه») — THE NOTE'S SECOND LEG.    |
//|                                                                  |
//| The note printed ONE size — the stop's EngSL — while the entry   |
//| ray is sized by the OTHER leg (HuntSL for ETR/CTR/OTR, EngSL for |
//| FTR, P-BK-51/83). The user reads the note to check the box, so   |
//| the leg that places the ENTRY rode nowhere on its face. It is     |
//| here now, printed from the SAME pushed EngSL / HuntSL the         |
//| geometry draws with — BaseKnotCalcLevels publishes it (P-BK-93), |
//| so this is a name for a number, never a second measurement.      |
//|                                                                  |
//| ONE LAW, BORROWED FROM P-BK-57: the note never prints the SAME   |
//| size twice. So the field stays EMPTY when the first field already|
//| IS this leg — an FTR node reads its EngSL on the stop's own TF,  |
//| and nothing pushed falls back to the box height the first field  |
//| already carries. That is also what keeps a box being SIZED (the  |
//| FTR preview, one EngSL for both legs) byte-identical on its face.|
//|                                                                  |
//| NO TF ON THE NAME, AND THAT IS NOT AN OMISSION: the entry's leg  |
//| is read on the NODE'S OWN time (P-BK-83 — BaseKnotEntryTFMin     |
//| never hops), which is exactly the class the note already prints  |
//| in the SAME line («H1 base»). Spelling it a second time would   |
//| name one rung twice. The stop's field is the one that carries a  |
//| TF («EngSL M15») because it is the leg that hops.                |
//+------------------------------------------------------------------+
string BaseKnotEntryTag(const bool offIsHunt, const double offPips,
                        const int entryTF, const int riskTF, const string riskTag)
{
   if(offPips <= 0.0) return "";                     // absence: the hover names it, the face does not guess
   if(!offIsHunt)
   {
      if(riskTag == BaseKnotBoxHeightTag()) return "";                       // the first field IS the height
      if(entryTF > 0 && riskTF > 0 && entryTF == riskTF) return "";          // the SAME EngSL, already printed
   }
   return " | " + BaseKnotEntryOffsetTag(offIsHunt) + " " + DoubleToString(offPips, 1);
}
//+------------------------------------------------------------------+
//| P-TP4 (2026-10-19) — THE CARD'S FOUR LEGS AT THE KNOT'S OWN ROW. |
//| The old face carried two (`EngSL`, `HuntSL`); the master's card  |
//| carries four (`TRex`, `Trigger`, `Pricicle`, `Classic`). This is  |
//| the one row the note prints, read from the plan row the pump     |
//| already pushed for the same (TF, anchor) — never a second read.  |
//+------------------------------------------------------------------+
static int      s_bkLegN = 0;
static int      s_bkLegTF[BK_ENG_ROW_MAX];
static datetime s_bkLegAnchor[BK_ENG_ROW_MAX];
static double   s_bkLegPric[BK_ENG_ROW_MAX];
static double   s_bkLegClas[BK_ENG_ROW_MAX];
void BaseKnotPlanLegsPush(const int &mins[], const datetime &anchors[],
                          const double &pric[], const double &clas[], const int n)
{
   int m = 0;
   for(int i = 0; i < n && m < BK_ENG_ROW_MAX; i++)
   {
      if(mins[i] <= 0) continue;
      s_bkLegTF[m] = mins[i];
      s_bkLegAnchor[m] = (anchors[i] > 0 ? anchors[i] : 0);
      s_bkLegPric[m] = (pric[i] > 0.0 ? pric[i] : 0.0);
      s_bkLegClas[m] = (clas[i] > 0.0 ? clas[i] : 0.0);
      m++;
   }
   s_bkLegN = m;
}
double BaseKnotPlanPriciclePips(const int tfMin, const datetime anchor = 0)
{
   int tf = (tfMin > 0 ? tfMin : Period());
   for(int i = 0; i < s_bkLegN; i++)
      if(s_bkLegTF[i] == tf && s_bkLegAnchor[i] == anchor) return s_bkLegPric[i];
   return 0.0;
}
double BaseKnotPlanClassicPips(const int tfMin, const datetime anchor = 0)
{
   int tf = (tfMin > 0 ? tfMin : Period());
   for(int i = 0; i < s_bkLegN; i++)
      if(s_bkLegTF[i] == tf && s_bkLegAnchor[i] == anchor) return s_bkLegClas[i];
   return 0.0;
}
string BaseKnotLegPipsText(const double v)
{
   if(v <= 0.0) return "--";
   if(MathAbs(v - MathRound(v)) < 0.05) return IntegerToString((int)MathRound(v));
   return DoubleToString(v, 1);
}
string BaseKnotLegsTag(const int engTF, const double engPips,
                       const datetime anchor = 0)
{
   if(engPips <= 0.0) return "";
   return "TRex " + BaseKnotLegPipsText(engPips) +
          " | Trigger " + BaseKnotLegPipsText(BaseKnotHuntPips(engTF, anchor)) +
          " | Pricicle " + BaseKnotLegPipsText(BaseKnotPlanPriciclePips(engTF, anchor)) +
          " | Classic " + BaseKnotLegPipsText(BaseKnotPlanClassicPips(engTF, anchor));
}
//+------------------------------------------------------------------+
//| P-BK-109 (2026-10-09, user: «اینجا که نیومده هنوز») — THE TYPE'S  |
//| OWN ATRS, IN LADDER ORDER, ON THE FACE.                           |
//|                                                                  |
//| The face said `EngSL 17.1 | 67.0 | 9 bars · M15 base · FTR` —     |
//| three numbers, none of which is the ATR that decided the type.    |
//| P-BK-106b: the face now prints the three bands the type reads,    |
//| in the leg ruler's own compact form:                             |
//| `· FTR · ATR H1:178.3 | H4:371.0 | D1:...`.                      |
//| The bar stays in the hover, never on the face.                    |
//|                                                                  |
//| IT READS THE PUBLISHED RECORD, NEVER A SECOND MEASUREMENT:        |
//| `nd.abTrig` is the node's own row and `nd.abPat` is the next     |
//| rung's OWN row — both read by BaseKnotNodeRead at `nd.anchor` —   |
//| so the numbers and the bar here are the SAME pair the bands were  |
//| built from, and they can never disagree with the hover.           |
//|                                                                  |
//| NO UNIT WORD (P-BK-54's own law, the same one the height field   |
//| obeys) and no target list: one name, one number, one moment.      |
//| `abTrig <= 0` is the ABSENCE (the plan is not warm for that bar) —|
//| the field stays out and the hover is where that is said.           |
//+------------------------------------------------------------------+
string BaseKnotATRTag(BaseKnotNode &nd)
{
   if(nd.abTrig <= 0.0) return "";   // absence: the hover names it, the face does not guess
   // P-BK-106b: the leg ruler's compact shape — ONE `ATR` label, three `TF:value` cells,
   // ascending ladder order (node, pattern, structure). No bar on the face: the hover
   // carries the moment (P-BK-108). Only REAL rows are printed; a cold row stays in hover.
   string s = " · ATR " + BaseKnotTFName(nd.nodeTF) + ":" + DoubleToString(BaseKnotToPips(nd.abTrig), 1);
   int up1 = BaseKnotNextTFMin(nd.nodeTF);
   int up2 = (up1 > 0 ? BaseKnotNextTFMin(up1) : 0);
   if(up1 > 0 && nd.abPatRead && nd.abPat > 0.0)
      s += " | " + BaseKnotTFName(up1) + ":" + DoubleToString(BaseKnotToPips(nd.abPat), 1);
   if(up2 > 0 && nd.abStrRead && nd.abStr > 0.0)
      s += " | " + BaseKnotTFName(up2) + ":" + DoubleToString(BaseKnotToPips(nd.abStr), 1);
   return s;
}
string BaseKnotATRPctCell(const int tf, const double atr, const double boxPips)
{
   double a = BaseKnotToPips(atr);
   if(a <= 0.0 || boxPips <= 0.0) return "";
   return BaseKnotTFName(tf) + ":" + IntegerToString((int)MathRound(boxPips / a * 100.0)) + "%";
}
string BaseKnotATRPctTag(BaseKnotNode &nd, const double boxPips)
{
   string s = BaseKnotATRPctCell(nd.nodeTF, nd.abTrig, boxPips);
   if(s == "") return "";
   s = " · " + s;
   int up1 = BaseKnotNextTFMin(nd.nodeTF);
   int up2 = (up1 > 0 ? BaseKnotNextTFMin(up1) : 0);
   string c = (up1 > 0 && nd.abPatRead ? BaseKnotATRPctCell(up1, nd.abPat, boxPips) : "");
   if(c != "") s += " | " + c;
   c = (up2 > 0 && nd.abStrRead ? BaseKnotATRPctCell(up2, nd.abStr, boxPips) : "");
   if(c != "") s += " | " + c;
   return s;
}
//--- P-BK-113/114: the leg ruler's owner-TF line, on the note. The owner is the
//--- ladder rung whose own ATR makes the box 240%..360%; for the 248-pip box
//--- that is M15 (301%), and P-BK-114 makes that same TF the knot's time. The
//--- lower rungs are pushed by the pump (ATR is above this module); this builder
//--- only reads the published cache.
int BaseKnotPrevTFMin(const int tfMin)
{
   if(tfMin <= 1) return 0;
   int rungs[]; int n = BaseKnotLadderAll(rungs);
   int prev = 0;
   for(int i = 0; i < n; i++)
   {
      if(rungs[i] >= tfMin) break;
      prev = rungs[i];
   }
   return prev;
}
#define BK_OWNER_LO 2.40
#define BK_OWNER_HI 3.60
string BaseKnotOwnerTag(BaseKnotNode &nd, const double boxPips)
{
   if(nd.nodeTF <= 0 || boxPips <= 0.0 || nd.abTrig <= 0.0) return "";
   int tfs[6]; double atrs[6]; int n = 0;
   int d1 = BaseKnotPrevTFMin(nd.nodeTF);
   int d2 = (d1 > 0 ? BaseKnotPrevTFMin(d1) : 0);
   int d3 = (d2 > 0 ? BaseKnotPrevTFMin(d2) : 0);
   int down[3]; down[0] = d3; down[1] = d2; down[2] = d1;
   for(int i = 0; i < 3; i++)
   {
      double a = 0.0;
      if(down[i] > 0 && BaseKnotOwnerATRGet(down[i], nd.anchor, a) && a > 0.0)
      {
         tfs[n] = down[i]; atrs[n] = a; n++;
      }
   }
   tfs[n] = nd.nodeTF; atrs[n] = nd.abTrig; n++;
   int up1 = BaseKnotNextTFMin(nd.nodeTF);
   int up2 = (up1 > 0 ? BaseKnotNextTFMin(up1) : 0);
   if(up1 > 0 && nd.abPatRead && nd.abPat > 0.0)
   {
      tfs[n] = up1; atrs[n] = nd.abPat; n++;
   }
   if(up2 > 0 && nd.abStrRead && nd.abStr > 0.0)
   {
      tfs[n] = up2; atrs[n] = nd.abStr; n++;
   }
   int start = -1;
   for(int i = 0; i < n; i++) if(tfs[i] == nd.nodeTF) { start = i; break; }
   if(start < 0) return "";
   int owner = -1;
   int idx = start;
   for(int step = 0; step < 6; step++)
   {
      double ap = BaseKnotToPips(atrs[idx]);
      if(ap <= 0.0) break;
      double r = boxPips / ap;
      if(r >= BK_OWNER_LO && r <= BK_OWNER_HI) { owner = idx; break; }
      int nxt = (r > BK_OWNER_HI ? idx + 1 : idx - 1);
      if(nxt < 0 || nxt >= n || nxt == idx) break;
      idx = nxt;
   }
   if(owner < 0) return "";
   // A TF already printed by BaseKnotATRTag (its ATR) and BaseKnotATRPctTag
   // (its %) would repeat both fields on the owner row: the node's own rung,
   // plus the pattern/structure rungs when those reads exist. Only a LOWER
   // owner rung is new information (it is pumped, not on the face).
   if(tfs[owner] == nd.nodeTF ||
      (up1 > 0 && nd.abPatRead && nd.abPat > 0.0 && tfs[owner] == up1) ||
      (up2 > 0 && nd.abStrRead && nd.abStr > 0.0 && tfs[owner] == up2)) return "";
   double ap = BaseKnotToPips(atrs[owner]);
   if(ap <= 0.0) return "";
   return "TF " + BaseKnotTFName(tfs[owner]) + " | ATR " + DoubleToString(ap, 1) +
          " | Leg " + IntegerToString((int)MathRound(boxPips / ap * 100.0)) + "%";
}
//+------------------------------------------------------------------+
//| BKCORNER-ON (2026-10-20) — THE FACE IS SPLIT, NEVER CUT.          |
//|                                                                  |
//| MT4 keeps 63 characters of OBJPROP_TEXT and drops the rest, and |
//| the note's last field IS the node type (P-BK-29/109). The face   |
//| therefore becomes as many rows as it needs, cut at its own       |
//| " | " boundaries first (then at a space) so no field is halved.  |
//| The wrapper is text-only: the caller owns the plate's geometry.  |
//+------------------------------------------------------------------+
int BaseKnotNoteRows(const string text, string &rows[])
{
   ArrayResize(rows, 0);
   string rest = text;
   int guard = 0;
   while(StringLen(rest) > 0 && guard < BK_INFO_MAX_ROWS)
   {
      guard++;
      int n = ArraySize(rows);
      // P-BK-106b: an explicit newline is a row the writer already decided — keep it whole.
      // The old " | " wrap stays as the fallback for a line that is still too long.
      int nl = StringFind(rest, "\n");
      if(nl >= 0 && nl <= BK_INFO_TEXT_MAX)
      {
         string rowTxt = StringSubstr(rest, 0, nl);
         StringTrimRight(rowTxt);
         if(StringLen(rowTxt) > 0) { ArrayResize(rows, n + 1); rows[n] = rowTxt; }
         rest = StringSubstr(rest, nl + 1);
         continue;
      }
      if(StringLen(rest) <= BK_INFO_TEXT_MAX || n >= BK_INFO_MAX_ROWS - 1)
      {
         ArrayResize(rows, n + 1);
         rows[n] = rest;
         break;
      }
      // the last " | " that still fits; a cut that leaves too little on the row is skipped
      int cut = -1, from = 0;
      while(true)
      {
         int p = StringFind(rest, " | ", from);
         if(p < 0 || p > BK_INFO_TEXT_MAX) break;
         cut = p;
         from = p + 1;
      }
      if(cut > 0 && cut < BK_INFO_TEXT_MAX / 5) cut = -1;
      if(cut <= 0)
      {
         cut = BK_INFO_TEXT_MAX;
         for(int i = BK_INFO_TEXT_MAX; i >= 1; i--)
            if(StringGetCharacter(rest, i - 1) == 32) { cut = i - 1; break; }
      }
      if(cut <= 0) cut = BK_INFO_TEXT_MAX;
      if(cut > StringLen(rest)) cut = StringLen(rest);
      string rowTxt = StringSubstr(rest, 0, cut);
      StringTrimRight(rowTxt);
      ArrayResize(rows, n + 1);
      rows[n] = rowTxt;
      rest = StringSubstr(rest, cut);
      while(StringLen(rest) > 0)
      {
         int lead = StringGetCharacter(rest, 0);
         if(lead != 32 && lead != 124) break;   // skip the separator the break consumed
         rest = StringSubstr(rest, 1);
      }
   }
   return ArraySize(rows);
}
int BaseKnotNoteLineCount(const string text)
{
   int n = 1;
   for(int i = 0; i < StringLen(text); i++)
      if(StringGetCharacter(text, i) == 10) n++;
   return n;
}
int BaseKnotNoteMaxLineW(const string text, const int fontPt)
{
   int best = 0, start = 0, len = StringLen(text);
   for(int i = 0; i <= len; i++)
   {
      if(i == len || StringGetCharacter(text, i) == 10)
      {
         int w = PnlRawTextW(StringSubstr(text, start, i - start), fontPt);
         if(w > best) best = w;
         start = i + 1;
      }
   }
   return best;
}
//--- BKCORNER-ON (2026-10-20) — THE FAMILY'S NAMES AND ITS SWEEPS. ----------------------
//--- Row 0 keeps the historical row's name; the wrapped rows carry their ordinal, and the
//--- plate is row 0 + BK_NOTE_PLATE. The wipes are the only owners that enumerate the whole
//--- family, so a shorter note can never leave a longer one's ghost behind.
string BaseKnotCornerRowName(const int row)
{
   string nm = BaseKnotCornerName();
   if(nm == "") return "";   // no prefix: no family, and never a bare "R2" on the chart
   if(row <= 0) return nm;
   return nm + "R" + IntegerToString(row + 1);
}
string BaseKnotCornerPlateName()
{
   string nm = BaseKnotCornerName();
   if(nm == "") return "";
   return nm + BK_NOTE_PLATE;
}
void BaseKnotCornerFamilyWipe()
{
   for(int i = 0; i < BK_INFO_MAX_ROWS; i++)
   {
      string nm = BaseKnotCornerRowName(i);
      if(nm != "") ObjectDelete(0, nm);
   }
   string pn = BaseKnotCornerPlateName();
   if(pn != "") ObjectDelete(0, pn);
}
//--- BKCORNER-TOAST (2026-10-20) — THE READOUT IS A TOAST, NOT A BADGE. ----------------
//--- The user's report: the note stayed on the chart and read as clutter. It now lives
//--- BK_CORNER_TOAST_MS (3 s) from the last user action, then the family is deleted —
//--- the same shape as a web toast. The key is the box-side note name (`in`), so a tap
//--- on the SAME box re-arms it, a new box replaces it, and a still frame writes nothing.
static uint   s_bkToastUntil   = 0;
static bool   s_bkToastArmed   = false;   // inside the 3 s window
static bool   s_bkToastVisible = false;   // the family is on the chart
static string s_bkToastKey     = "";      // the box the window belongs to
static bool   s_bkToastPaused  = false;   // the cursor is on the toast: its clock is stopped
static int    s_bkToastRemain  = 0;       // ms left when the pause began
static int    s_bkToastX = 0, s_bkToastY = 0, s_bkToastW = 0, s_bkToastH = 0;   // last painted rect
void BaseKnotCornerToastArm()
{
   s_bkToastArmed  = true;
   s_bkToastPaused = false;
   s_bkToastRemain = BK_CORNER_TOAST_MS;
   s_bkToastUntil  = GetTickCount() + BK_CORNER_TOAST_MS;
}
void BaseKnotCornerToastReset()
{
   s_bkToastArmed   = false;
   s_bkToastVisible = false;
   s_bkToastPaused  = false;
   s_bkToastRemain  = 0;
   s_bkToastKey     = "";
   s_bkToastUntil   = 0;
   s_bkToastX = 0; s_bkToastY = 0; s_bkToastW = 0; s_bkToastH = 0;
}
void BaseKnotCornerToastRect(const int x, const int y, const int w, const int h)
{
   s_bkToastX = x; s_bkToastY = y; s_bkToastW = w; s_bkToastH = h;
}
//--- Hover = pause. Called from the shared router on MOUSE_MOVE; four int compares
//--- while a toast is up, and the clock is read only on the enter/leave transition.
void BaseKnotCornerToastHover(const int x, const int y)
{
   if(!s_bkToastVisible || s_bkToastW <= 0 || s_bkToastH <= 0) return;
   bool inside = (x >= s_bkToastX && x < s_bkToastX + s_bkToastW &&
                  y >= s_bkToastY && y < s_bkToastY + s_bkToastH);
   if(inside == s_bkToastPaused) return;
   if(inside)
   {
      int rem = (int)(s_bkToastUntil - GetTickCount());
      if(rem <= 0) return;   // already spent: the tick takes it, hover cannot revive it
      s_bkToastRemain = rem;
      s_bkToastPaused = true;
   }
   else
   {
      s_bkToastUntil  = GetTickCount() + (uint)s_bkToastRemain;
      s_bkToastPaused = false;
   }
}
void BaseKnotCornerToastTick()
{
   if(!s_bkToastArmed) return;
   if(s_bkToastPaused) return;   // the cursor owns the clock
   if((int)(s_bkToastUntil - GetTickCount()) > 0) return;
   if(s_bkToastVisible) { BaseKnotCornerFamilyWipe(); s_bkToastVisible = false; BaseKnotCornerToastRect(0, 0, 0, 0); }
   s_bkToastArmed = false;
}
void BaseKnotCornerWipe()
{
   BaseKnotCornerFamilyWipe();
   BaseKnotCornerToastReset();
   s_bkCornerId    = "";
   s_bkCornerDirty = true;
}

#endif // BASE_KNOT_NOTE_MQH
