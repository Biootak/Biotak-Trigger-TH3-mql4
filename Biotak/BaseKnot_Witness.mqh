//+------------------------------------------------------------------+
//| BaseKnot_Witness.mqh                                            |
//| P-BK-107 (2026-10-09) — THE KNOT'S OWN READ, WITNESSED.          |
//|                                                                  |
//| The user's question, measured rather than argued: «الان atr همون  |
//| گره رو نشون میده یا … atr هایی که برای لایو ما در لیبلها محاسبه    |
//| کردیم». The note's hover prints the bands but NEVER the bar they  |
//| were read at, so the ONE pair of numbers that answers it — the   |
//| ATR of the knot's own anchor bar beside the ATR of the LIVE row   |
//| on the same rung — was unreadable from the chart and could only  |
//| be claimed. It is on the FLUSHED channel now (P-LOG-3: never      |
//| `Print` alone — the journal is a cache and reads as «nothing       |
//| happened»).                                                       |
//|                                                                  |
//| WHAT IT READS BACK: the registry's published facts (id, type,    |
//| node time, anchor) and the ability table's OWN (TF, anchor) row — |
//| the very row the type was decided against — plus the live row of  |
//| the same rung for the comparison. NOTHING is derived here a      |
//| second time, so this witness can never describe a measurement    |
//| the box did not use.                                             |
//|                                                                  |
//| LAYER: this is the ONE BaseKnot file the entry compiles AFTER    |
//| DrawStrip.mqh, because `DrawStripDiagEmit` is declared there and  |
//| MQL4 resolves top-down: nothing inside BaseKnotTool (included at  |
//| line 52) may call it. The hub that owns the call is               |
//| EventHandlers.mqh, and this file must precede the caller in it    |
//| (the same law as P-SIZE-SPLIT's halves).                          |
//|                                                                  |
//| COST: one bounded walk of the registry and one compare per box   |
//| per pump round (500 ms); a still frame writes NOTHING. The line  |
//| fires once per box per CHANGE — a new bar, a moved ATR, a new    |
//| anchor — exactly when the note itself would rewrite.             |
//+------------------------------------------------------------------+
#ifndef BASE_KNOT_WITNESS_MQH
#define BASE_KNOT_WITNESS_MQH

// P-BK-107c (2026-10-09): 48 SEATS, A DELETED BOX GIVES ITS SEAT BACK, AND A FULL
// TABLE IS SILENT — NEVER A DUPLICATE. The table used to hold 16 and, when full,
// wrote into seat 0 (`if(slot < 0) slot = 0`), so on a chart with more than 16 live
// boxes the two oldest boxes STOLE each other's seat every pump round and each wrote
// a line for a type that had not moved — the exact noise P-BK-107b removed. So:
//   * the bound is the SAME 48 the ability table and the pump's ask list use, which is
//     the most rows one chart's boxes can ask for (BK_ENG_ROW_MAX);
//   * a seat whose box is no longer in the registry is RELEASED first, every round —
//     deleting a box frees its seat, and so does a registry wipe at attach, with no
//     cross-layer call (this file sits ABOVE BaseKnotTool, so it may not call into it);
//   * a table that is genuinely full of LIVE boxes writes NOTHING for the newcomer
//     rather than evicting a live row. A bounded refusal is an absence the reader can
//     see is missing; a duplicated line is a lie about what changed.
#define BK_TW_MAX 48
struct BaseKnotTwRow
{
   string   id;
   int      kind;
   int      tf;
   datetime an;
   double   atr;
   double   step;
   bool     used;
};
static BaseKnotTwRow s_bkTw[BK_TW_MAX];
// A seat whose box left the registry is released. One bounded walk of the (tiny) seat
// table against the registry, per pump round — the same "a stale row cannot answer" law
// the ability table obeys (P-BK-79), kept here so a deleted box costs nothing later.
void BaseKnotTwReclaim()
{
   for(int e = 0; e < BK_TW_MAX; e++)
   {
      if(!s_bkTw[e].used) continue;
      if(BaseKnotFind(s_bkTw[e].id) >= 0) continue;   // still ours
      s_bkTw[e].used = false;
      s_bkTw[e].id = "";
   }
}

void BaseKnotTypeWitness()
{
   BaseKnotTwReclaim();
   int boxes = ArraySize(g_bkBoxes);
   for(int i = 0; i < boxes; i++)
   {
      string   id     = g_bkBoxes[i].id;
      int      nodeTF = g_bkBoxes[i].baseTFMin;
      datetime an     = (g_bkBoxes[i].storyT > 0 ? g_bkBoxes[i].storyT : 0);
      if(id == "") continue;
      // P-BK-107a: A BOX WITH NO CLASS PUBLISHED YET IS A STATE, NOT A SKIP.
      // `BaseKnotRegister` opens baseTFMin at 0 and only `BaseKnotSync` publishes it, so an
      // INHERITED box (a chart reopened from a previous session) has a registry row and no
      // class until something Syncs it. Printing the chart's own rung in its place would
      // name a TF the knot never used; printing nothing is indistinguishable from "no box",
      // which is exactly the confusion this witness exists to remove. So it says so.
      if(nodeTF <= 0)
      {
         string pend = " [P-BK-107] box=" + id + " pending: no class published yet (no Sync has run for this box)";
         // P-BK-107b: once per box, like the typed branch — a box whose class never arrives
         // must not write a line every 500 ms.
         bool seenPend = false;
         for(int e = 0; e < BK_TW_MAX; e++)
         {
            if(!s_bkTw[e].used || s_bkTw[e].id != id) continue;
            if(s_bkTw[e].kind < 0) seenPend = true;
            else s_bkTw[e].kind = -1;   // the class left: stay in the pending seat, stay quiet
            break;
         }
         if(seenPend) continue;
         int slotP = -1;
         for(int e = 0; e < BK_TW_MAX; e++) if(!s_bkTw[e].used) { slotP = e; break; }
         if(slotP < 0) continue;   // P-BK-107c: same bounded refusal as the typed branch
         s_bkTw[slotP].used = true; s_bkTw[slotP].id = id; s_bkTw[slotP].kind = -1;
         s_bkTw[slotP].tf = 0; s_bkTw[slotP].an = 0; s_bkTw[slotP].atr = 0.0; s_bkTw[slotP].step = 0.0;
         DrawStripDiagEmit(pend);
         continue;
      }
      double atr = 0.0, pat = 0.0, str = 0.0, step = 0.0, label = 0.0;
      bool warm = BaseKnotAbilityGet(nodeTF, an, atr, pat, str);   // the row the TYPE was decided against
      BaseKnotStepRow(nodeTF, an, step);
      // THE LIVE NUMBER THE LABELS PRINT for this very rung — `GetATRForTimeframe` is the
      // ATR column's own owner (Labels_A.mqh: `CalculateWeightedATRForTimeframe` under a
      // 30 s cache), so the comparison is the one that was asked for: the knot's bar against
      // today's row of the SAME formula, not a second reading of ours. The ability table's
      // live row is NOT used here: the pump asks (class, anchor) for a typed box and the
      // chart's own rung at anchor 0, so (nodeTF, 0) is usually absent and would read 0.
      double labelPrice = GetATRForTimeframe(nodeTF);
      double pip = BaseKnotPipSize();
      if(labelPrice > 0.0 && pip > 0.0) label = labelPrice / pip;
      // P-BK-107b (2026-10-09): THE GUARD IS THE TYPE, AND ONLY THE TYPE. It used to be
      // (type, anchor, ATR, step) — every field — and the base's own right side moves
      // whenever its walk re-reads the band (`11:15 → 13:35 → 16:15 → 19:20 → 23:10` on
      // one box, ATR 71.3 → 65.6), so a single box that never changed type wrote a dozen
      // lines and the type's actual moves were lost in the noise. The question this
      // witness exists for is «which type, against which bar» — a bar that moved without
      // moving the type is the note's business (it prints it), not the log's. So the line
      // fires on a type change and on the first sight of a box, and a still type is silent.
      bool seen = false;
      for(int e = 0; e < BK_TW_MAX; e++)
      {
         if(!s_bkTw[e].used || s_bkTw[e].id != id) continue;
         if(s_bkTw[e].kind == g_bkBoxes[i].nodeKind) seen = true;
         else s_bkTw[e].kind = g_bkBoxes[i].nodeKind;   // the type moved — refresh the seat in place
         break;
      }
      if(seen) continue;
      int slot = -1;
      for(int e = 0; e < BK_TW_MAX; e++) if(!s_bkTw[e].used) { slot = e; break; }
      // P-BK-107c: FULL OF LIVE BOXES = SAY NOTHING. The old `slot = 0` overwrote the
      // oldest row and made two live boxes evict each other forever. A witness that skips
      // is missing a line; one that duplicates invents a change that never happened.
      if(slot < 0) continue;
      s_bkTw[slot].used = true; s_bkTw[slot].id = id;
      s_bkTw[slot].kind = g_bkBoxes[i].nodeKind; s_bkTw[slot].tf = nodeTF;
      s_bkTw[slot].an = an; s_bkTw[slot].atr = atr; s_bkTw[slot].step = step;
      DrawStripDiagEmit("[P-BK-107] box=" + id + " chart=" + BaseKnotTFName(Period()) +
                        " commit=" + BaseKnotTFName(g_bkBoxes[i].tfMin) +
                        " type=" + BaseKnotNodeShort(g_bkBoxes[i].nodeKind) +
                        " node=" + BaseKnotTFName(nodeTF) + " anchor=" +
                        (an > 0 ? TimeToString(an, TIME_DATE | TIME_MINUTES) : "live") +
                        " ATR=" + DoubleToString(warm ? BaseKnotToPips(atr) : 0.0, 1) +
                        " pattern=" + DoubleToString(warm ? BaseKnotToPips(pat) : 0.0, 1) +
                        " structure=" + DoubleToString(warm ? BaseKnotToPips(str) : 0.0, 1) +
                        // P-BK-128: the boundaries are the owners', never a second copy of the
                        // rule — this line was the page's own arithmetic ((atr+pat)*0.5) and it
                        // would have kept printing a boundary the type no longer uses.
                        " bands FTR<" + DoubleToString(BaseKnotToPips(BaseKnotNodeBandFtrEtr(nodeTF, an)), 1) +
                        " ETR<" + DoubleToString(BaseKnotToPips(BaseKnotNodeBandEtrCtr(nodeTF, an)), 1) +
                        " CTR<" + DoubleToString(BaseKnotToPips(str), 1) +
                        " stepTH=" + DoubleToString(BaseKnotToPips(step), 1) +
                        " labelATR=" + DoubleToString(label, 1) +
                        " gap=" + DoubleToString(label > 0.0 ? label - BaseKnotToPips(atr) : 0.0, 1) +
                        " gv=" + (CalcAnchorAt() > 0 ? TimeToString(CalcAnchorAt(), TIME_DATE | TIME_MINUTES) : "live") +
                        " owner=" + g_calcAnchorOwner +
                        " last=" + (g_calcAnchorLastTime > 0 ? TimeToString(g_calcAnchorLastTime, TIME_DATE | TIME_MINUTES) : "live") +
                        " lastOwner=" + g_calcAnchorLastOwner);
   }
}

// P-BK-111 (2026-10-09): THE FLIP'S WITNESS — ON THE FLUSHED CHANNEL, WITH A READ-BACK.
// The direction cell is the one control whose whole claim is «it changed something the chart
// shows», and the two ways it can be wrong are silent: the side does not move (a write aimed
// at a field nobody re-reads) or it moves and the next 500 ms pump puts it straight back (a
// lock the follow does not honour). Both read as «کلیک کردم هیچی نشد» and neither is visible
// from the chart, because the note's own caption is a lie the chart believes. So the line
// carries the box, the side BEFORE and AFTER, the lock, and the GlobalVariable's own value —
// and it reads the OBJECT's value back, not the field it just wrote.
void BaseKnotDirWitness()
{
   string id; int was = 0, now = 0, lock = 0;
   while(BaseKnotDirFlipTake(id, was, now, lock))
   {
      int k = BaseKnotFind(id);
      double gv = GlobalVariableCheck(BaseKnotDirLockGV(id))
                   ? GlobalVariableGet(BaseKnotDirLockGV(id)) : 0.0;
      DrawStripDiagEmit("[P-BK-111] dir box=" + id +
                        " was=" + (was >= 0 ? "BUY" : "SELL") +
                        " now=" + (now >= 0 ? "BUY" : "SELL") +
                        " lock=" + IntegerToString(lock) +
                        " read=" + (k < 0 ? "gone" : (g_bkBoxes[k].dir >= 0 ? "BUY" : "SELL")) +
                        " gv=" + DoubleToString(gv, 0));
   }
}

// P-BK-116 (2026-10-21): the line-end column's own arithmetic, on the flushed channel — the
// lot the risk % bought, the pip's money, the balance it was sized from, and every leg's
// pips + money. It reads the numbers the PAINT used (`BaseKnotPipWitTake`), so the log and the
// ink can never describe different sizes, and a still frame says nothing (the string is
// compared first). Emitted from both pumps, right after the note's own pulse.
void BaseKnotPipWitness()
{
   string w = BaseKnotPipWitTake();
   if(w == "") return;
   DrawStripDiagEmit("[BK-PIP] " + w);
}

// P-BK-115a (2026-10-21): THE KEEPER'S OWN PULSE — AND IT IS SILENT WHEN THE CHART IS STILL.
// «مدام روی چارت بیس نات حذف و رسم میشه و اپدیت میشه» is a claim about FREQUENCY, and the one
// instrument that can settle it is the keeper's own count: `BaseKnotNoteCornerRefresh` shares
// the 500 ms pump, so a tree that Syncs on every round prints two lines a second for ever
// with nothing on the chart changing, and a tree that respects §5 prints NONE.
// The read-back is the keeper's (`BaseKnotNoteSyncTake`, BaseKnot_Measure.mqh) and the line
// carries what a reader needs to tell the two apart: how many Syncs, the worst one's ms (the
// full family rewrite is the expensive half), the box, and whether a note is even supposed to
// be up. Called AFTER the pump's own SyncBadges, from both entries' pump (BiotakKit / the Lite
// tick pump) — the same place the keeper runs.
void BaseKnotNoteWitness()
{
   uint ms = 0;
   int  n  = BaseKnotNoteSyncTake(ms);
   if(n <= 0) return;   // the still chart: no line, which IS the proof
   string id = BaseKnotSelectedId();
   DrawStripDiagEmit("[BK-NOTE] sync=" + IntegerToString(n) +
                     " worstMs=" + IntegerToString((int)ms) +
                     " armed=" + IntegerToString(BaseKnotCornerToastIsArmed() ? 1 : 0) +
                     " boxes=" + IntegerToString(ArraySize(g_bkBoxes)) +
                     " id=" + (id == "" ? "-" : id) +
                     " rows=" + IntegerToString(ObjectFind(0, BaseKnotCornerRowName(0)) >= 0 ? 1 : 0) +
                     " plate=" + IntegerToString(ObjectFind(0, BaseKnotCornerPlateName()) >= 0 ? 1 : 0));
}

#endif // BASE_KNOT_WITNESS_MQH
