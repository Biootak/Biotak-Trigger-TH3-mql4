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
//| P-BK-109 (2026-10-09, user: «اینجا که نیومده هنوز») — THE TYPE'S  |
//| OWN ATR AND THE BAR IT CAME FROM, ON THE FACE.                   |
//|                                                                  |
//| The hover could name the bar (P-BK-108) but the FACE is what the |
//| user reads, and the face said `EngSL 17.1 | 67.0 | 9 bars · M15  |
//| base · FTR` — three numbers, none of which is the ATR that        |
//| decided the type, and none of which says WHEN. The type is the    |
//| one claim on that line, so the measure behind it belongs beside   |
//| it: `· FTR · ATR 73.1 (2026.10.06 10:13)`.                        |
//|                                                                  |
//| IT READS THE PUBLISHED RECORD, NEVER A SECOND MEASUREMENT:        |
//| `nd.abTrig` is the row `BaseKnotNodeRead` already read for the    |
//| type, and `nd.anchor` is the bar it read it at — so the number    |
//| and the bar here are the SAME pair the bands were built from, and |
//| they can never disagree with the hover that spells them out.      |
//|                                                                  |
//| NO UNIT WORD (P-BK-54's own law, the same one the height field   |
//| obeys) and no target list: one name, one number, one moment.      |
//| `abTrig <= 0` is the ABSENCE (the plan is not warm for that bar) —|
//| the field stays out and the hover is where that is said.           |
//+------------------------------------------------------------------+
string BaseKnotATRTag(BaseKnotNode &nd)
{
   if(nd.abTrig <= 0.0) return "";   // absence: the hover names it, the face does not guess
   string bar = (nd.anchor > 0 ? TimeToString(nd.anchor, TIME_DATE | TIME_MINUTES) : "live");
   return " · ATR " + DoubleToString(BaseKnotToPips(nd.abTrig), 1) + " (" + bar + ")";
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
