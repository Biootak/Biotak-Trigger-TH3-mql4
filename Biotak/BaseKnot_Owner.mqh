//+------------------------------------------------------------------+
//| BaseKnot_Owner.mqh                                              |
//| P-BK-114 — the selected knot's owner TF, measured before Sync.    |
//|                                                                  |
//| The ruler's law: the box height belongs to the TF whose own ATR   |
//| makes it 240%..360%. That TF is the knot's time now, so the pump  |
//| measures it first, recounts the base on that TF, and publishes    |
//| both before the ability rows are asked for.                      |
//+------------------------------------------------------------------+
#ifndef BASE_KNOT_OWNER_MQH
#define BASE_KNOT_OWNER_MQH

//--- P-BK-115b (2026-10-21): the question this pump answers, as its own key — the selected
//--- box, its two corners, its price band, its story bar, the newest closed bar, and the
//--- owner TF it last published. Every one of them is an INPUT of `BaseKnotOwnerTFWalk` or of
//--- the story it is read at, so an unchanged key means an unchanged answer. Compared as
//--- numbers (no string built per round).
static string   s_bkOwnKeyId    = "";
static datetime s_bkOwnKeyT1    = 0;
static datetime s_bkOwnKeyT2    = 0;
static datetime s_bkOwnKeyStory = 0;
static datetime s_bkOwnKeyBar   = 0;
static double   s_bkOwnKeyTop   = 0.0;
static double   s_bkOwnKeyBot   = 0.0;
static int      s_bkOwnKeyTF    = 0;

int BaseKnotOwnerTFWalk(const double boxPips, const datetime an)
{
   if(boxPips <= 0.0) return 0;
   int tf = Period();
   if(tf <= 0) tf = 60;
   int visited[9];
   ArrayInitialize(visited, 0);
   int nv = 0;
   for(int w = 0; w < 9; w++)
   {
      double atr = CalculateWeightedATRAt(CompatTF(tf), an);
      double a = BaseKnotToPips(atr);
      if(a <= 0.0) break;
      double r = boxPips / a;
      if(r >= BK_OWNER_LO && r <= BK_OWNER_HI) return tf;
      int nxt = (r > BK_OWNER_HI ? BaseKnotNextTFMin(tf) : BaseKnotPrevTFMin(tf));
      if(nxt <= 0 || nxt == tf) break;
      bool seen = false;
      for(int v = 0; v < nv; v++) if(visited[v] == nxt) { seen = true; break; }
      if(seen) break;
      if(nv < 9) { visited[nv] = tf; nv++; }
      tf = nxt;
   }
   return 0;
}

void BaseKnotOwnerATRPump()
{
   int k = BaseKnotFind(BaseKnotSelectedId());
   int tf = Period();
   if(tf <= 0) tf = 1;
   datetime an = 0;
   datetime t1 = 0, t2 = 0;
   double top = 0.0, bot = 0.0;
   if(k >= 0)
   {
      string pfx = BaseKnotPrefix(g_bkBoxes[k].id);
      string box = (pfx == "" ? "" : BaseKnotBoxName(pfx));
      if(box != "" && ObjectFind(0, box) >= 0)
      {
         t1 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 0);
         t2 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 1);
         if(t2 < t1) { datetime tt = t1; t1 = t2; t2 = tt; }
         double p1 = ObjectGetDouble(0, box, OBJPROP_PRICE, 0);
         double p2 = ObjectGetDouble(0, box, OBJPROP_PRICE, 1);
         top = MathMax(p1, p2); bot = MathMin(p1, p2);
      }
      an = g_bkBoxes[k].storyT;
   }
   //--- P-BK-115b (2026-10-21) — THE MEASUREMENT IS A QUESTION, SO IT IS ASKED ONCE PER ANSWER.
   //--- MEASURED, by the call graph: this function ran on EVERY 500 ms pump and performed, per
   //--- round, `BaseKnotSelectedId()` (a walk of every box with three property reads each), up
   //--- to nine `CalculateWeightedATRAt` legs (the `BaseKnotOwnerTFWalk` ladder), one
   //--- `BaseKnotBarCount` (up to BK_BASE_SKIP = 300 candles, two series reads each), and three
   //--- more ATR legs below — for a question whose every input (the box' two corners, its price
   //--- band, its story bar, the newest closed bar) had not moved. On the weakest machine this
   //--- is the «گیر میکنه»: the chart stutters twice a second with nothing on it changing.
   //--- The key is those inputs and nothing else, so a still chart pays one compare.
   datetime barNow = iTime(_Symbol, 0, 0);
   string   bid    = (k >= 0 ? g_bkBoxes[k].id : "");
   int      own    = (k >= 0 ? g_bkBoxes[k].ownerTFMin : 0);
   if(bid == s_bkOwnKeyId && t1 == s_bkOwnKeyT1 && t2 == s_bkOwnKeyT2 &&
      top == s_bkOwnKeyTop && bot == s_bkOwnKeyBot && an == s_bkOwnKeyStory &&
      barNow == s_bkOwnKeyBar && own == s_bkOwnKeyTF) return;
   s_bkOwnKeyId = bid; s_bkOwnKeyT1 = t1; s_bkOwnKeyT2 = t2;
   s_bkOwnKeyTop = top; s_bkOwnKeyBot = bot; s_bkOwnKeyStory = an;
   s_bkOwnKeyBar = barNow; s_bkOwnKeyTF = own;
   uint bkOwnT0 = GetTickCount();
   double bkOwnPips = BaseKnotToPips(top - bot);
   int    bkOwner   = 0;
   if(k >= 0 && bkOwnPips > 0.0)
   {
      bkOwner = BaseKnotOwnerTFWalk(bkOwnPips, an);
      BaseKnotSpan osp;
      //--- P-BK-115b — AND THE STORY HAS ONE PUBLISHER. This block used to write `baseTFMin`,
      //--- `storyT` and `exitT` too, while `BaseKnotSync` (BaseKnot_Plan.mqh) publishes the
      //--- same three fields from its OWN walk. `storyT` is the anchor key of every ability row
      //--- and the `CalcAnchor` owner time, so two walks that can disagree (Sync falls back to
      //--- the box' commit TF when the owner TF answers 0 bars) took turns re-keying the note —
      //--- the second live writer the touch rule names. The pump measures the OWNER TF, which
      //--- is the field it owns (P-BK-114); the story stays the Sync's.
      if(bkOwner > 0 && BaseKnotBarCount(t1, t2, top, bot, osp, bkOwner) > 0)
         g_bkBoxes[k].ownerTFMin = bkOwner;
      else
         g_bkBoxes[k].ownerTFMin = 0;
   }
   if(k >= 0 && g_bkBoxes[k].baseTFMin > 0) tf = g_bkBoxes[k].baseTFMin;
   if(k >= 0 && g_bkBoxes[k].ownerTFMin > 0) tf = g_bkBoxes[k].ownerTFMin;   // P-BK-115b: the field this pump owns
   if(k >= 0) an = g_bkBoxes[k].storyT;
   int down = BaseKnotPrevTFMin(tf);
   for(int i = 0; i < 3 && down > 0; i++)
   {
      double atr = CalculateWeightedATRAt(CompatTF(down), an);
      BaseKnotOwnerATRPush(down, an, atr);
      down = BaseKnotPrevTFMin(down);
   }
   //--- P-BK-115b: the witness — one line per REAL measurement, zero on a still chart. It names
   //--- the ratio the walk judged (`box / atr`), because 2.40..3.60 (BK_OWNER_LO/HI) is the
   //--- whole claim, and the bar it was read at — the anchor that must not move by itself.
   uint bkOwnD = GetTickCount() - bkOwnT0;
   double bkOwnATR = (bkOwner > 0 ? CalculateWeightedATRAt(CompatTF(bkOwner), an) : 0.0);
   DrawStripDiagEmit("[BK-OWNER] box=" + (bid == "" ? "-" : bid) +
                     " boxPips=" + DoubleToString(bkOwnPips, 1) +
                     " owner=" + (bkOwner > 0 ? BaseKnotTFName(bkOwner) : "none") +
                     " read=" + (bkOwner > 0 ? BaseKnotTFName(g_bkBoxes[k].ownerTFMin) : "none") +
                     " atr=" + DoubleToString(BaseKnotToPips(bkOwnATR), 1) +
                     " r=" + DoubleToString(bkOwnATR > 0.0 ? bkOwnPips / BaseKnotToPips(bkOwnATR) : 0.0, 2) +
                     " anchor=" + (an > 0 ? TimeToString(an, TIME_DATE | TIME_MINUTES) : "live") +
                     " ms=" + IntegerToString((int)bkOwnD));
}

#endif // BASE_KNOT_OWNER_MQH
