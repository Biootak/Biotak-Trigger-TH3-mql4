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

#endif // BASE_KNOT_NOTE_MQH
