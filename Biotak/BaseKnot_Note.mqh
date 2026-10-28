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
//| NO TF ON THE NAME, AND THAT IS NOT AN OMISSION: the entry hops  |
//| with the type now (P-BK-127), and the risk field beside it      |
//| already names that rung («TRex H1»). Spelling it a second time  |
//| would name one ruler twice - the one thing P-BK-57 forbids.     |
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
                       const double offPips, const bool isHunt, const datetime anchor = 0)
{
   if(engPips <= 0.0) return "";
   // P-BK-132: `engPips` is the TRex the box DRAWS - the three cells under it are that same rung's
   // pushes, so they ride the SAME factor: the ratio between the stop handed in here and the rung's
   // own EngSL. 1.0 whenever the box is no taller than its rung, so every other box is unchanged.
   // P-BK-134: and that ratio IS `BaseKnotLegGrade` - the ONE clamp (BaseKnot_Ability), not a
   // second spelling of it here. Two spellings of one factor is the class this file has already
   // been fixed for once (P-BK-127); a hand-written ratio is how it comes back.
   double rung = BaseKnotEngPips(engTF, anchor);
   double g    = BaseKnotLegGrade(engPips, rung);
   // P-BK-133 (2026-10-28) — THE TRIGGER CELL IS THE DRAWN ENTRY, ALWAYS. On a ladder rung that is
   // the rung's Hunt x g (P-BK-132); OFF the ladder the entry is the knot's own time's Hunt and the
   // box' power never touched it (BaseKnotLegPair) — so multiplying it here too would print 214.6
   // over a line drawn at 142.5, the very split P-BK-127 removed. `offPips` is the entry the
   // geometry produced, handed in so the cell and the line are ONE number.
   // P-BK-134: WHICH of the two it is, is `BaseKnotEntryRidesStop`'s answer — the same fence the
   // geometry multiplied under, asked with the same flag (`isHunt`). A kind test here could answer
   // differently from the line and print a number the box does not draw.
   string trig;
   if(!BaseKnotEntryRidesStop(isHunt, engTF) && offPips > 0.0 && MathAbs(offPips - engPips) > 0.05)
      trig = BaseKnotLegPipsText(offPips);
   else
      trig = BaseKnotLegPipsText(BaseKnotHuntPips(engTF, anchor) * g);
   return "TRex " + BaseKnotLegPipsText(engPips) +
          " | Trigger " + trig +
          " | Pricicle " + BaseKnotLegPipsText(BaseKnotPlanPriciclePips(engTF, anchor) * g) +
          " | Classic " + BaseKnotLegPipsText(BaseKnotPlanClassicPips(engTF, anchor) * g);
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
   string s = " · ATR " + BaseKnotTFHuman(nd.nodeTF) + ":" + DoubleToString(BaseKnotToPips(nd.abTrig), 1);
   int up1 = BaseKnotNextTFMin(nd.nodeTF);
   int up2 = (up1 > 0 ? BaseKnotNextTFMin(up1) : 0);
   if(up1 > 0 && nd.abPatRead && nd.abPat > 0.0)
      s += " | " + BaseKnotTFHuman(up1) + ":" + DoubleToString(BaseKnotToPips(nd.abPat), 1);
   if(up2 > 0 && nd.abStrRead && nd.abStr > 0.0)
      s += " | " + BaseKnotTFHuman(up2) + ":" + DoubleToString(BaseKnotToPips(nd.abStr), 1);
   return s;
}
string BaseKnotATRPctCell(const int tf, const double atr, const double boxPips)
{
   double a = BaseKnotToPips(atr);
   if(a <= 0.0 || boxPips <= 0.0) return "";
   return BaseKnotTFHuman(tf) + ":" + IntegerToString((int)MathRound(boxPips / a * 100.0)) + "%";
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
   return "TF " + BaseKnotTFHuman(tfs[owner]) + " | ATR " + DoubleToString(ap, 1) +
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
//--- P-BK-121 (2026-10-24) — THE FAMILY IS NOT A BOX' CHILD, AND ITS NAME SAYS SO TOO LATE.
//--- The rows are named off the CHART-WIDE prefix (`…_BK_NOTE_CORNER`, `…_NOTE_CORNERR2`), so
//--- the delete handler — whose "an orphan box' children are still here" branch splits the tail
//--- at its LAST underscore — parsed a row's tail into bid="NOTE" and swept
//--- `ObjectsDeleteAll(0, prefix("NOTE"))`: THE WHOLE READOUT, plate included, on the ONE event a
//--- shorter note makes (its writer deletes the rows beyond the new count). MEASURED in the
//--- journal: `[drawstrip] DELFLUSH obj="THLevels_BK_NOTE_*"` fires on every drag release and on
//--- every 3 s toast expiry — write, wipe by an unrelated sweep, write again by the keeper, i.e.
//--- exactly the «الکی حذف و رسم» the user reported. This is the answer the handler asks BEFORE
//--- any sweep: a note stem is not an id, and the family owns its own deletes.
bool BaseKnotNoteStemIs(const string bid)
{
   return (bid != "" && StringFind(BK_NOTE_CORNER, bid) == 0);   // "NOTE" (a row) / "NOTE_CORNER" (the plate)
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
//--- P-BK-115a (2026-10-21): THE TOAST OWNS THE FAMILY'S OWNERSHIP, so its state is asked,
//--- never inferred. The keeper (`BaseKnotNoteCornerRefresh`, this file) used to
//--- read "the row is gone" as damage — the same read that is TRUE the moment the window
//--- spends and the family is deleted — so it Synced and redrew the chart twice a second for
//--- ever on a still chart. One question, one answer, answered here.
bool BaseKnotCornerToastIsArmed() { return s_bkToastArmed; }
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
//--- P-BK-115a (2026-10-21): THE KEEPER LIVES HERE NOW — with the state it reads. §7 sent it
//--- out of BaseKnot_Measure.mqh the day this change pushed that file past the 1500 ceiling;
//--- same name, same body, same output. It shares the 500 ms pump (`BaseKnotSyncBadges`), so the
//--- corner follows a selection change, a mode change, a pushed slot or a box that left this TF
//--- without a new event path of its own. NOTHING IS WRITTEN while nothing changed.
//--- `s_bkNoteSyncN` / `s_bkNoteSyncMs` are the witness' own numbers (BaseKnot_Witness.mqh).
static int  s_bkNoteSyncN  = 0;
static uint s_bkNoteSyncMs = 0;   // the WORST Sync of the window, not the last
int BaseKnotNoteSyncTake(uint &msWorst)
{
   int n = s_bkNoteSyncN;
   msWorst = s_bkNoteSyncMs;
   s_bkNoteSyncN = 0;
   s_bkNoteSyncMs = 0;
   return n;
}
void BaseKnotNoteCornerRefresh()
{
   string nm = BaseKnotCornerName();
   if(nm == "") return;
   BaseKnotCornerToastTick();   // BKCORNER-TOAST: the 3 s life is served by the same pump
   if(!BaseKnotNoteInCorner())
   {
      BaseKnotCornerFamilyWipe();   // the box-side home owns the note now
      s_bkCornerId    = "";
      s_bkCornerDirty = false;      // nothing is owed while the rung is not the corner one
      return;
   }
   if(g_bkState == BK_PREVIEW)
   {
      s_bkCornerDirty = true;   // the live writer owns the row while the user draws — the NEXT round
      return;                    // re-decides, so a cancelled BAND cannot leave its preview text behind
   }
   string id = BaseKnotSelectedId();
   if(id != "" && !BaseKnotVisibleNow(id)) id = "";   // a box hidden on this TF claims no row
   if(id == s_bkCornerId && !s_bkCornerDirty)
   {
      // Steady state: not one chart write. The heal reads the row and its plate — something
      // else (a chart-wide cleanup, the user's own delete) may have taken the family away,
      // and a readout that silently disappears is the bug this keeper exists for.
      // P-BK-115a — BUT ONLY WHILE A NOTE IS SUPPOSED TO BE UP. The toast DELETES the family
      // when its 3 s window ends, so from that moment "the row is missing" is the note's own
      // state, not damage — and this test read it as damage on every round: `BaseKnotSync`
      // (one bar walk + the node read + the whole family's writes) plus `ChartRedraw()`,
      // twice a second, for ever, with nothing on the chart changing. MEASURED by
      // construction, not by eye: once `s_bkToastArmed` is false `BaseKnotWriteInfo`'s toast
      // branch can NEVER repaint (its key is unchanged, so nothing re-arms it), while this
      // line re-set `s_bkCornerDirty` every 500 ms — a write loop with no writer, and §5's
      // "at rest: zero writes, zero polling" broken. The question is the TOAST's, so the
      // keeper asks it: a spent window means the family's ABSENCE is the state, and a still
      // chart pays one bool.
      if(id == "") return;
      if(!BaseKnotCornerToastIsArmed()) return;   // P-BK-115a: the toast owns the absence
      if(ObjectFind(0, nm) >= 0 && ObjectFind(0, BaseKnotCornerPlateName()) >= 0) return;
      s_bkCornerDirty = true;   // rebuild it below
   }
   s_bkCornerId = id;
   s_bkCornerDirty = false;
   if(id == "")
   {
      BaseKnotCornerFamilyWipe();   // nothing answers: a stale note is worse than none
      BaseKnotCornerToastReset();   // a later selection of the same box is a NEW toast
      return;
   }
   uint bkKeeperT0 = GetTickCount();
   BaseKnotSync(id);   // the ONE writer rebuilds the box AND its note — into the row
   {   // P-BK-115a: the witness' own number — how many Syncs this keeper issued, and the worst
      uint bkKeeperD = GetTickCount() - bkKeeperT0;
      s_bkNoteSyncN++;
      if(bkKeeperD > s_bkNoteSyncMs) s_bkNoteSyncMs = bkKeeperD;
   }
   ChartRedraw();
}
void BaseKnotCornerWipe()
{
   BaseKnotCornerFamilyWipe();
   BaseKnotCornerToastReset();
   s_bkCornerId    = "";
   s_bkCornerDirty = true;
}
//+------------------------------------------------------------------+
//| P-BK-116 (2026-10-21) — THE END OF EVERY LINE SAYS WHAT IT IS    |
//| WORTH: pips, then money.                                         |
//|                                                                  |
//| User order, on a knot whose Entry/SL/TP lines carry a tooltip    |
//| only: «مقدار پیپ و دلاری هر کدوم در آخر هر خط بنویس ولی جوری باشه    |
//| که چارت رو شلوغ نکنه». So the ink is a COLUMN at the right edge  |
//| (the very edge the TP ticks hug, P-BK-50), one 7 pt row per line, |
//| in the LINE'S OWN ink — and it exists for ONE box: the selected  |
//| one (or the newest while nothing is selected), the same answer   |
//| the corner note already uses (BaseKnotSelectedId). A box that   |
//| does not answer deletes its own rows, so a selection change      |
//| leaves no ghost column behind.                                   |
//|                                                                  |
//| WHERE THE MONEY COMES FROM (one basis, stated once): the STOP's  |
//| pips ARE the risk (hPips), so the position is sized from          |
//| `inpBKRiskPct` of the balance — lot = risk / (stop pips x pip    |
//| value) — and every other line is its own pips at that lot. No    |
//| second size, no second risk: one lot, one account currency, and  |
//| the terminal's own tick value does the conversion (never a        |
//| hard-coded $10). 0% = the ink is off and NOTHING is guessed.     |
//|                                                                  |
//| COST: writes only on a real change (name/text/x/y/ink compared   |
//| first), one ChartTimePriceToXY per row, at most five rows, and   |
//| only while a box is selected — a still frame writes nothing.     |
//+------------------------------------------------------------------+
static string s_bkPipOwner = "";   // the box whose column is on the chart ("" = none)
//--- The column's own numbers, for the flushed witness (`BaseKnotPipWitness`, BaseKnot_Witness).
//--- This file sits inside BaseKnotTool and may not call `DrawStripDiagEmit`; the pair below is
//--- WRITE-then-read, and the reader says a line only when the string MOVED — so a still chart
//--- is silent and every real recompute is one line with its own arithmetic.
static string s_bkPipWitLive = "";
static string s_bkPipWitSeen = "";
string BaseKnotPipWitTake()
{
   if(s_bkPipWitLive == s_bkPipWitSeen) return "";
   s_bkPipWitSeen = s_bkPipWitLive;
   return (s_bkPipWitSeen == "" ? "none" : s_bkPipWitSeen);
}
string BaseKnotPipInkName(const string pfx, const int kind, const int k = 0)
{
   if(pfx == "") return "";
   if(kind == 0) return pfx + "PIPENTRY";
   if(kind == 1) return pfx + "PIPSL";
   return pfx + "PIPTP" + IntegerToString(k);
}
void BaseKnotPipInkWipe(const string pfx)
{
   if(pfx == "") return;
   ObjectDelete(0, BaseKnotPipInkName(pfx, 0));
   ObjectDelete(0, BaseKnotPipInkName(pfx, 1));
   for(int k = 1; k <= BK_TP_PLAN_MAX; k++) ObjectDelete(0, BaseKnotPipInkName(pfx, 2, k));
}
// Account currency per ONE pip at 1.00 lot — the terminal's own tick value, scaled to the
// chart's own pip (the same BaseKnotPipSize every other number on the knot is measured in).
double BaseKnotMoneyPerPip()
{
   double pip = BaseKnotPipSize();
   if(pip <= 0.0) return 0.0;
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tv > 0.0 && ts > 0.0) return tv * (pip / ts);
   double cs = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   return (cs > 0.0 ? cs * pip : 0.0);
}
// The lot the risk % buys for THIS stop, on the symbol's own step/min/max.
double BaseKnotRiskLot(const double slPips)
{
   if(slPips <= 0.0 || inpBKRiskPct <= 0.0) return 0.0;
   double per = BaseKnotMoneyPerPip();
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(per <= 0.0 || bal <= 0.0) return 0.0;
   double risk = bal * inpBKRiskPct / 100.0;
   if(risk <= 0.0) return 0.0;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;
   double lot = MathFloor(risk / (slPips * per) / step) * step;
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(mx > 0.0 && lot > mx) lot = mx;
   if(mn > 0.0 && lot < mn) lot = mn;
   return (lot > 0.0 ? NormalizeDouble(lot, 2) : 0.0);
}
string BaseKnotMoneyText(const double money)
{
   if(money <= 0.0) return "";
   string cur = AccountInfoString(ACCOUNT_CURRENCY);
   string sym = (cur == "USD" ? "$" : (cur == "" ? "$" : cur + " "));
   return sym + DoubleToString(money, money < 100.0 ? 1 : 0);
}
// Does a row at `y` land on one already placed? `lineH` is the font's own leading, so two
// rows closer than that would print through each other.
bool BaseKnotPipClash(const int y, const int &used[], const int n, const int lineH)
{
   for(int u = 0; u < n; u++) if(MathAbs(y - used[u]) < lineH - 2) return true;
   return false;
}
// One row: pips + money, written only when it moved.
bool BaseKnotPipInkRow(const string nm, const int x, const int y, const string txt, const color clr)
{
   if(nm == "" || txt == "") return false;
   bool have = (ObjectFind(0, nm) >= 0);
   if(have && (int)ObjectGetInteger(0, nm, OBJPROP_TYPE) != OBJ_LABEL) { ObjectDelete(0, nm); have = false; }
   if(have &&
      (int)ObjectGetInteger(0, nm, OBJPROP_XDISTANCE) == x &&
      (int)ObjectGetInteger(0, nm, OBJPROP_YDISTANCE) == y &&
      (int)ObjectGetInteger(0, nm, OBJPROP_COLOR) == (int)clr &&
      ObjectGetString(0, nm, OBJPROP_TEXT) == txt) return true;
   if(!have && !ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0)) return false;
   ObjectSetString(0, nm, OBJPROP_TEXT, txt);
   ObjectSetString(0, nm, OBJPROP_FONT, inpFontName);
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, PnlPt(BK_PT_PIP));
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);   // the projection's own pixel, never a right-edge distance
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nm, OBJPROP_ANCHOR, ANCHOR_RIGHT_LOWER);   // the ink sits ON the line, inside the plot
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, nm, OBJPROP_ZORDER, Z_CHART_LABEL);
   return true;
}
// The column. `dir` + `tpTF` + `anchor` are the SAME owners the drawn legs were read from,
// so the ink can never name a level the lines did not draw (the tick loop asks
// BaseKnotTPLevel exactly as the Sync did). P-BK-120: `tpTF` is the STOP's own time —
// the rung the plan's ratios were applied to — never the box' base TF.
void BaseKnotPipInk(const string id, const double entry, const double sl, const double offPips,
                   const double hPips, const int dir, const int tpTF, const datetime anchor)
{
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return;
   bool sel = (id == BaseKnotSelectedId());
   if(!sel)
   {
      if(s_bkPipOwner == id) { BaseKnotPipInkWipe(pfx); s_bkPipOwner = ""; }
      s_bkPipWitLive = "";
      return;   // one box wears the column, and a selection change takes the old one with it
   }
   if(s_bkPipOwner != "" && s_bkPipOwner != id) BaseKnotPipInkWipe(BaseKnotPrefix(s_bkPipOwner));
   s_bkPipOwner = id;
   double per = BaseKnotMoneyPerPip();
   double lot = BaseKnotRiskLot(hPips);
   datetime edge = BaseKnotTPEdgeTime();
   int ex = 0, ey = 0;
   if(entry <= 0.0 || sl <= 0.0 || per <= 0.0 || lot <= 0.0 || edge <= 0 ||
      !ChartTimePriceToXY(0, 0, edge, entry, ex, ey))
   {
      BaseKnotPipInkWipe(pfx);   // no size, no money, no ink — never a guessed number
      s_bkPipWitLive = "";
      return;
   }
   s_bkPipWitLive = "id=" + id + " lot=" + DoubleToString(lot, 2) +
                    " perPip=" + DoubleToString(per, 2) +
                    " balance=" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 0) +
                    " riskPct=" + DoubleToString(inpBKRiskPct, 2) +
                    " stop=" + DoubleToString(hPips, 1) + "p " + BaseKnotMoneyText(hPips * per * lot) +
                    " off=" + DoubleToString(offPips, 1) + "p";
   // the anchor x: the right edge of the plot, a hair inside it (the price axis owns the rest)
   int x = ex - 4;
   int ax = ex;
   int lineH = PnlRawLineH(PnlPt(BK_PT_PIP));
   if(lineH < 1) lineH = 1;
   int used[6]; ArrayInitialize(used, -9999); int nu = 0;   // the column never stacks two rows on one pixel row
   //--- PRIORITY IS THE ORDER THE TRADE IS READ IN: the STOP first (it IS the risk), then the
   //--- ENTRY's own leg, then the plan's targets. A row that would land on a row already taken
   //--- is dropped, never nudged: the tooltip still carries that number, and a tight knot then
   //--- reads three clean rows instead of five smudged ones.
   int yy = 0;
   if(hPips > 0.0 && ChartTimePriceToXY(0, 0, edge, sl, ax, yy))
   {
      BaseKnotPipInkRow(BaseKnotPipInkName(pfx, 1), x, yy, "-" + DoubleToString(hPips, 1) + "p " + BaseKnotMoneyText(hPips * per * lot), g_bkStopColor);
      used[nu] = yy; nu++;
   }
   else ObjectDelete(0, BaseKnotPipInkName(pfx, 1));
   if(offPips > 0.0 && ChartTimePriceToXY(0, 0, edge, entry, ax, yy) && !BaseKnotPipClash(yy, used, nu, lineH))
   {
      BaseKnotPipInkRow(BaseKnotPipInkName(pfx, 0), x, yy, DoubleToString(offPips, 1) + "p " + BaseKnotMoneyText(offPips * per * lot), g_bkEntryColor);
      used[nu] = yy; nu++;
   }
   else ObjectDelete(0, BaseKnotPipInkName(pfx, 0));
   for(int tk = 1; tk <= BK_TP_PLAN_MAX; tk++)
   {
      string nm = BaseKnotPipInkName(pfx, 2, tk);
      double lv = (tk <= BaseKnotTPCount() ? BaseKnotTPLevel(entry, dir, tpTF, tk, anchor, hPips) : 0.0);   // P-BK-132: the ink rides the graded stop, so its pips match the tick
      if(lv > 0.0 && ChartTimePriceToXY(0, 0, edge, lv, ax, yy) && !BaseKnotPipClash(yy, used, nu, lineH))
      {
         double pp = BaseKnotToPips(MathAbs(lv - entry));
         BaseKnotPipInkRow(nm, x, yy, "+" + DoubleToString(pp, 1) + "p " + BaseKnotMoneyText(pp * per * lot), g_bkTargetColor);
         s_bkPipWitLive += " tp" + IntegerToString(tk) + "=" + DoubleToString(pp, 1) + "p " + BaseKnotMoneyText(pp * per * lot);
         used[nu] = yy; nu++;
      }
      else ObjectDelete(0, nm);
   }
}

#endif // BASE_KNOT_NOTE_MQH
