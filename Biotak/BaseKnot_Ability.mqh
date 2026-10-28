//+------------------------------------------------------------------+
//| BaseKnot_Ability.mqh                                             |
//| P-BK-106 / P-BK-125 — THE LADDER'S ROWS, AND WHAT THEY ANSWER.   |
//|                                                                  |
//| SPLIT OUT OF BaseKnot_Nodes.mqh on 2026-10-27 (P-SIZE-1500,      |
//| contract §7). Nodes sat exactly on the 1500-line ceiling, and the |
//| stop's new ladder read (P-BK-125) had no room; this is the seam   |
//| the file already had: the (TF, anchor) table the pump PUSHES, the |
//| four reads that answer from it, and the stop's rung on top. The   |
//| type's own read (BaseKnotNodeKindOfLength) stayed in Nodes, one   |
//| file above its callers. Nothing moved changed meaning.            |
//|                                                                  |
//| INCLUDE ORDER IS NOT LOAD-BEARING for CALLS (MQL4 resolves a      |
//| function across the whole unit), which is why this file may be    |
//| included ABOVE BaseKnot_Nodes.mqh and still be called from it.    |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| P-BK-106 (2026-10-09, user: «به جای th باید از atr استفاده بشه  |
//| اوکی اگر» + «اگر atr استفاده بشه دیگه نیازی به فراکتال جامپ هم    |
//| برای بیس نات نیستش») — THE TYPE IS ONE ANCHORED ATR, AND THE      |
//| LADDER IS NOT WALKED FOR IT ANY MORE.                            |
//|                                                                  |
//| The ability table used to hold ONE row per (TF, anchor) — the    |
//| rung's TH — and the type read THREE of them: the node's own time,|
//| the pattern time one rung above and the structure time two      |
//| above (P-BK-78). Two rows nobody else needed were pushed every   |
//| round to answer a question the ladder can answer itself.        |
//|                                                                  |
//| WHAT IT IS NOW: ONE number per (TF, anchor) — the node's OWN     |
//| rung's ATR (the anchor's own composite: `plan.ownPips`,          |
//| TradePlanFormulas — `TradePlanStripPips(chartMin, anchor)`, the  |
//| weighted 5/10/21/66/132/264 blend the trade plan divides), and   |
//| the two upper bands are THAT ATR multiplied by the ladder's own  |
//| √-law (BaseKnotRungScale). No rung above is read, no `iClose`,   |
//| no second row.                                                  |
//|                                                                  |
//| THE STEP KEEPS ITS OWN NUMBER IN THE SAME ROW. It is the rung's  |
//| TH at the same (TF, anchor) (P-BK-105) and it stays TH: this     |
//| edit changes the TYPE's measure, not the steps the course counts |
//| the break story in. One key space, two columns, so a row the     |
//| type was decided against is the row the step came from — the two |
//| can never name two bars.                                        |
//+------------------------------------------------------------------+
#define BK_AB_TF_MAX BK_ENG_ROW_MAX
static int      s_bkAbTF[BK_AB_TF_MAX];
static datetime s_bkAbAnchor[BK_AB_TF_MAX];   // P-BK-79: the bar this row was read at
static double   s_bkAbATR[BK_AB_TF_MAX];      // P-BK-106: the rung's OWN ATR, price units (was its TH)
static double   s_bkAbStep[BK_AB_TF_MAX];     // P-BK-106: the STEP's own number — the rung's TH, price units
static int      s_bkAbN = 0;
// One round of the pump opens with this, so a TF nobody asks for any more cannot
// answer a later question with a stale row.
void BaseKnotAbilityReset() { s_bkAbN = 0; }
// One row per (TF, ANCHOR) — the pump's own ask list (BaseKnotEngNeeds) is the list, so
// the ask and the answer can never disagree about which TFs a box draws with, nor about
// the bar. P-BK-79: the anchor is why this table needed a second key at all — two boxes
// on one TF whose bases ended on two bars must type against two different ATRs («با گذشت
// زمان ممکن 40 بشه یا 10 بشه»), and the live row (anchor 0) is the sizing preview's own.
// A repeated pair overwrites (the newest round wins) and a full table refuses quietly: both
// are bounded refusals, never an eviction that would silently drop another box's row.
//
// P-BK-106: `atr` is the rung's OWN ATR in PRICE units (the pump converts plan.ownPips,
// which is in PIPS — the conversion is at the push site and nowhere else) and `step` is
// the rung's TH in the same units. 0 is the ABSENCE ("not warm") for either, and it is
// stored AS an absence: the row keeps it and the readers refuse it, so a cold rung can
// never become a threshold of zero.
void BaseKnotAbilityPush(const int tfMin, const datetime anchor,
                         const double atr, const double step)
{
   if(tfMin <= 0) return;
   datetime an = (anchor > 0 ? anchor : 0);   // 0 = the live row (P-BK-79)
   double a = (atr > 0.0 ? atr : 0.0);
   double s = (step > 0.0 ? step : 0.0);
   for(int i = 0; i < s_bkAbN; i++)
   {
      if(s_bkAbTF[i] != tfMin || s_bkAbAnchor[i] != an) continue;
      s_bkAbATR[i]  = a;
      s_bkAbStep[i] = s;
      return;
   }
   if(s_bkAbN >= BK_AB_TF_MAX) return;
   s_bkAbTF[s_bkAbN]     = tfMin;
   s_bkAbAnchor[s_bkAbN] = an;
   s_bkAbATR[s_bkAbN]    = a;
   s_bkAbStep[s_bkAbN]   = s;
   s_bkAbN++;
}
// P-BK-106: the ATR column. false = never pushed, or pushed while its ATR was not
// warm — an absence the caller reports, never a zero dressed up as a threshold.
bool BaseKnotAbilityRow(const int tfMin, const datetime anchor, double &atr)
{
   atr = 0.0;
   if(tfMin <= 0) return false;
   datetime an = (anchor > 0 ? anchor : 0);
   for(int i = 0; i < s_bkAbN; i++)
   {
      if(s_bkAbTF[i] != tfMin || s_bkAbAnchor[i] != an) continue;
      atr = s_bkAbATR[i];
      return (atr > 0.0);
   }
   return false;
}
// P-BK-106: the STEP's own column — the rung's TH at the SAME (TF, anchor), the number the
// break story's steps are counted in (P-BK-105). A separate column, not a second read: the
// step must stay the rung's TH while the type reads that rung's ATR.
bool BaseKnotStepRow(const int tfMin, const datetime anchor, double &step)
{
   step = 0.0;
   if(tfMin <= 0) return false;
   datetime an = (anchor > 0 ? anchor : 0);
   for(int i = 0; i < s_bkAbN; i++)
   {
      if(s_bkAbTF[i] != tfMin || s_bkAbAnchor[i] != an) continue;
      step = s_bkAbStep[i];
      return (step > 0.0);
   }
   return false;
}
// P-BK-106 — THE THREE BANDS, OFF THE TABLE. `tfMin` is the NODE'S TIME (P-BK-77's own
// answer) and the three numbers are the ATR of THAT rung and of the two rungs above it,
// EACH READ at the box' own anchor (the pump asks all three pairs, P-BK-106b). The old
// √-law (`pattern = trigger x scale`) is only the cold fallback: it assumed every ladder
// step scales by the same square root, which is false for H4 -> D1 (x2.449) and D1 -> W1
// (x2.236), and the user's own report («178.3 x 2 = 356.6 … لزوما این نیست که همیشه ضرب
// دو باشه») is that assumption showing on the chart. A real upper row always wins.
// P-BK-79: `anchor` is the bar the rows are read at — the box' own story end — so one box
// has ONE type for ever once its base is closed. false = the node's time is unknown, the
// ladder has no rung above it (a MN1 node has no pattern time), or the trigger ATR was
// never pushed warm — an absence the caller turns into BK_NODE_NONE, never a band.
bool BaseKnotAbilityGet(const int tfMin, const datetime anchor,
                        double &trig, double &pat, double &str)
{
   trig = 0.0; pat = 0.0; str = 0.0;
   if(tfMin <= 0) return false;
   if(!BaseKnotAbilityRow(tfMin, anchor, trig))   // the ONE required read
   {
      // P-BK-126 (2026-10-27) — A KNOT'S TIME IS NOT A RUNG. The scan names 2, 8, 9 and 45
      // minutes on the four seed rows, and the table can only hold the rungs the pump asked
      // for, so an off-ladder time is scaled from the nearest rung BELOW it by the project's
      // own √-law (`BaseKnotRungScale`) — the same law this function already falls back on
      // when an upper row is cold. An 8-minute knot therefore reads one continuous curve
      // instead of a hole, and a time the table has no rung under still answers false.
      int below = 0;
      double atr = 0.0;
      datetime an = (anchor > 0 ? anchor : 0);
      for(int i = 0; i < s_bkAbN; i++)
      {
         if(s_bkAbAnchor[i] != an || s_bkAbTF[i] > tfMin || s_bkAbTF[i] <= below) continue;
         if(!(s_bkAbATR[i] > 0.0)) continue;      // a cold row is an absence, never a zero
         below = s_bkAbTF[i];
         atr   = s_bkAbATR[i];
      }
      if(below <= 0) return false;                // no rung under it — nothing to scale from
      trig = atr * BaseKnotRungScale(below, tfMin);
      if(!(trig > 0.0)) return false;
   }
   int up1 = BaseKnotNextTFMin(tfMin);                          // the pattern time
   int up2 = (up1 > 0 ? BaseKnotNextTFMin(up1) : 0);            // the structure time
   double s1 = BaseKnotRungScale(tfMin, up1);
   double s2 = (up1 > 0 ? BaseKnotRungScale(up1, up2) : 0.0);
   if(s1 <= 0.0 || s2 <= 0.0) return false;   // no rung above — nothing to compare against
   if(!BaseKnotAbilityRow(up1, anchor, pat))  // the pattern rung's own ATR at the same bar
      pat = trig * s1;                        // cold: the old √-law, only until its row is warm
   if(!BaseKnotAbilityRow(up2, anchor, str))  // the structure rung's own ATR at the same bar
      str = pat * s2;                         // cold: the old √-law, only until its row is warm
   return (trig > 0.0 && pat > 0.0 && str > 0.0);
}
// P-BK-106b: the SAME read, plus the two flags the face uses to print only a REAL upper row.
// The fallback values stay in nd.abPat/abStr when a row is cold; the flags say which is which.
void BaseKnotAbilityRead(const int tfMin, const datetime anchor, BaseKnotNode &nd)
{
   BaseKnotAbilityGet(tfMin, anchor, nd.abTrig, nd.abPat, nd.abStr);
   nd.abPatRead = false; nd.abStrRead = false;
   int up1 = BaseKnotNextTFMin(tfMin);
   int up2 = (up1 > 0 ? BaseKnotNextTFMin(up1) : 0);
   double tmp = 0.0;
   if(up1 > 0 && BaseKnotAbilityRow(up1, anchor, tmp)) { nd.abPat = tmp; nd.abPatRead = true; }
   if(up2 > 0 && BaseKnotAbilityRow(up2, anchor, tmp)) { nd.abStr = tmp; nd.abStrRead = true; }
}

// P-BK-125 (2026-10-27) — THE STOP'S RUNG IS THE NEAREST RUNG, NOT THE NAME'S.
// The type names a BAND of `u` (P-BK-76: the midpoints), but the STOP used to jump a whole
// rung at the band's edge, because BaseKnotMeasureHops answered by NAME (FTR 0 / ETR 1 /
// CTR 2 / OTR 3). A box landing a hair above the CTR ceiling therefore wore the OTR stop:
// measured on the dataset's own twins, BK-0003 (u = 1.884) wore 32.0 pips and BK-0004 — the
// SAME box 4 s later, +7.8 pips, u = 2.003 — wore 72.9, a 2.28x jump on a 6 % taller box.
// That is P-BK-76's own sentence («a box landing a hair either side of a boundary answers the
// one it is NEAREST to instead of flipping on a knife edge») applied to the LEG instead of
// the name: the rung is read from the box, not from its label.
//
// P-BK-128 (2026-10-27) — "NEAREST" IS THE WRONG COMPARISON; CAPACITY IS THE RIGHT ONE.
// The user's report: «این یک بار etr نشون میده یک بار ftr» on ONE box. A ladder's rungs are
// MULTIPLICATIVE (x2.22 then x3.23 on his own rows), and a leg is a PACKAGE that must sit INSIDE
// the box, so the question is not which rung the height is CLOSE to — it is which rung the box
// can HOLD. MEASURED, his box: 217.3 pips against ATR 135.2 / 300.8 / 970.4 (node 235m, H4, D1).
// The old linear u = (h-a0)/(a1-a0) reads 0.496 -> hop 0, and the same box at 219.5 reads 0.509
// -> hop 1: a 1 % nudge charged Trigger 84.5 or 188.0, and 188.0 + the stop 70.5 = 258.5 pips of
// legs inside a 217-pip box — the stop drawn OUTSIDE the box the trade is in. The boundary sat at
// (a0+a1)/2 = 218.0, 0.3 % from the box: that is the "تنگ" he reports.
// SO: hop = THE DEEPEST RUNG WHOSE WHOLE LEG PACKAGE STILL FITS (55/64 x a_k <= h). The package is
// the product's own identity (off 5/8 + risk 15/64 = BK_NODE_HUNT_NUM/DEN + BK_NODE_POWER_DIV,
// BaseKnot_Measure), so "fits" is the same sentence the legs are drawn by: both legs inside the
// box on every sample. MEASURED on the same box: 0.859375 x 300.8 = 258.5 > 217.3, so the pattern
// rung cannot be held and the box keeps the node's own (135.2) — Eng 31.7, Trigger 84.5 — and
// 219.5 answers the SAME, because the flip is 41 pips away instead of 0.7. The twins P-BK-125 was
// written for (u 1.884 / 2.003) now read ONE rung too (both hold the structure's package), so the
// 32.0 / 72.9 split is gone. Monotone, and still no per-box state (P-BK-79).
// READ AT THE SAME (TF, ANCHOR) AS THE TYPE — P-BK-79's rule, and the reason this function
// takes `anchor` at all: the ladder is a row of (TF, anchor), never "now", or the stop would
// drift while the box sits still (the user's own report: «atr یک دقیقه زمان گره بوده مثلا 20
// … با گذشت زمان ممکن 40 بشه یا 10 بشه»).
// -1 = the ladder cannot answer (no node TF, no height, a cold row, or an OTR box whose fourth
// rung was never pushed) — the caller then keeps the name's hop, exactly as before. An
// absence never becomes a rung.
#define BK_AB_FIT_NUM 55.0   // off (5/8) + risk (15/64) of ONE rung's ATR — the whole leg package
#define BK_AB_FIT_DEN 64.0   // == BK_NODE_HUNT_NUM/DEN + 1/BK_NODE_POWER_DIV (Measure; gate P-BK-128)
int BaseKnotLadderHopAt(const int nodeTFMin, const double h, const datetime anchor)
{
   if(nodeTFMin <= 0 || h <= 0.0) return -1;
   double a0 = 0.0, a1 = 0.0, a2 = 0.0;
   if(!BaseKnotAbilityGet(nodeTFMin, anchor, a0, a1, a2)) return -1;
   if(!(a0 > 0.0) || !(a1 > a0) || !(a2 > a1)) return -1;
   double fit = BK_AB_FIT_NUM / BK_AB_FIT_DEN;
   int hop = 0;                 // the node's own rung always stands: its package is the smallest
   if(h >= fit * a1) hop = 1;   // the pattern rung, once its package fits inside the box
   if(h >= fit * a2) hop = 2;   // the structure rung
   if(h > a2)
   {
      // past the structure: only the FOURTH rung can place it, and only a real row counts
      // (the √-law would guess the step, and the step is not constant — D1 -> W1 is x2.236).
      // THREE hops: u = 0 is the node's own rung, 1 is up1, 2 is up2, 3 is up3. MEASURED
      // 2026-10-27 by the harness: two hops named the STRUCTURE rung as `a3`, so every OTR
      // box fell out of the ladder read and kept the name's hop — the exact bug this
      // function exists to remove, hidden one rung lower.
      int up1 = BaseKnotNextTFMin(nodeTFMin);
      int up2 = (up1 > 0 ? BaseKnotNextTFMin(up1) : 0);
      int up3 = (up2 > 0 ? BaseKnotNextTFMin(up2) : 0);
      double a3 = 0.0;
      if(up3 <= 0 || !BaseKnotAbilityRow(up3, anchor, a3) || !(a3 > a2)) return -1;
      if(h >= fit * a3) hop = 3;
   }
   return hop;
}
// ... and the same answer for a registry row, so the geometry, the pump's ask list and every
// text that names the stop's TF ask ONE function and cannot name two different rungs.
// The registry keeps no height (`BaseKnotBox` is the box' IDENTITY; top/bot are the
// rectangle's, P-BK-77), so the height is read off the ink exactly as the texts do — two
// property reads, once per box per round.
// NO STORY, NO LADDER: a box whose base has not published `storyT` answers -1 and keeps the
// name's hop. Reading the LIVE row here instead would be "now", which is the one thing
// P-BK-79 forbids (the stop would drift while the box sits still).
int BaseKnotBoxHop(const int k)
{
   if(k < 0 || k >= ArraySize(g_bkBoxes)) return -1;
   if(g_bkBoxes[k].storyT <= 0) return -1;
   string box = BaseKnotBoxName(BaseKnotPrefix(g_bkBoxes[k].id));
   if(ObjectFind(0, box) < 0) return -1;
   double h = MathAbs(ObjectGetDouble(0, box, OBJPROP_PRICE, 0) -
                      ObjectGetDouble(0, box, OBJPROP_PRICE, 1));
   return BaseKnotLadderHopAt(g_bkBoxes[k].baseTFMin, h, g_bkBoxes[k].storyT);
}
// P-BK-132 (2026-10-27) - THE BOX' OWN POWER IS THE FLOOR OF THE LEG.
//
// P-BK-126/130/131 made a knot's price a continuous function of its TIME. The user's remaining case
// is the same question one axis over: an FTR box that has drifted a short step (or a C step) past
// its own time's ability but has NOT reached the next rung's range. The type ladder still prices it
// on its own rung, so its entry, its stop and its three targets keep the size of a box it no longer
// is - the one thing a "knot that is between two rungs" must not do.
//
// THE RULE. `boxLegPips` is the leg the BOX itself asks for (its height through the product's own
// divisor: BaseKnotNodeEngPips for EngSL, BaseKnotNodeHuntPips for HuntSL); `legPips` is the leg the
// rung pushed. The factor is their ratio, clamped at 1: the plan's pushed leg is never SHRUNK
// (BKCAP-OFF's rule, kept) and the box only ever LIFTS it.
//
// WHY THIS IS THE LOGARITHMIC ANSWER AND NOT A SECOND MODEL. Interpolate the leg in log space
// between the rung's a_k and the next rung's a_k+1, parameterised by the box' height h:
//   t = ln(h/a_k) / ln(a_k+1/a_k),   leg = leg_k * (leg_k+1/leg_k)^t
// Every leg is `a / BK_NODE_POWER_DIV`, so leg = h / BK_NODE_POWER_DIV EXACTLY - the parameter and
// the curve cancel. The height-graded leg therefore needs no logarithm and no interpolation table:
// it IS the box' own power, and this factor is its ratio to the rung's leg.
//
// ONE FACTOR FOR BOTH LEGS (P-BK-127). The Hunt leg is 8/3 of the EngSL it shares a row with, so
// one factor keeps that ratio and every R multiple on a tick stays put. The graded pair always
// fits, and this is arithmetic, not a hope: off + risk = (1 + off/risk) x h x 15/64 - 30/64 of the
// box when the entry is the TRex (off/risk = 1) and exactly 55/64 when it is the Hunt (8/3), the
// ladder's own fit constant (BK_AB_FIT_NUM/DEN, P-BK-128), so the deepest pair lands on the same
// 55/64 the hop test reserves and no height can push a stop out of its own box.
double BaseKnotLegGrade(const double boxLegPips, const double legPips)
{
   if(boxLegPips <= 0.0 || legPips <= 0.0) return 1.0;   // an absence grades nothing
   double g = boxLegPips / legPips;
   return (g > 1.0 ? g : 1.0);                           // never below 1: BKCAP-OFF's rule survives
}
// P-BK-134 (2026-10-28) — "DOES THE ENTRY RIDE THE STOP'S RULER?" IS ONE QUESTION.
//
// P-BK-132/133 answered it THREE times, in three spellings: the geometry
// (`BaseKnotIsLadderRung(stf) || kind == BK_NODE_FTR || kind == BK_NODE_NONE`, BaseKnot_Measure 861),
// the hover's clause (`isHunt && !BaseKnotIsLadderRung(measureTF)`, Measure 900) and the card's
// Trigger cell (`!BaseKnotIsLadderRung(engTF)`, BaseKnot_Note 119). Three spellings of one fence is
// the class P-BK-127 removed from the geometry: the first time one answers differently, the card
// prints a number over a line drawn at another — a split no gate can see and the user reads as
// «sometimes works».
// THE FENCE, in the unit the legs are actually read in: the ENTRY rides the box' power when it is
// the SAME leg the stop is (an EngSL — FTR, no type yet, or a row whose HuntSL was never pushed),
// OR when both legs are read on a ladder rung (a rung's Hunt scales with its own ATR). The one case
// it does NOT ride is an off-ladder knot WITH a HuntSL: that Hunt is the knot's own time's number,
// and the box' power would relabel it (P-BK-133: 142.5, never 214.6).
// IT ASKS THE PICK, NOT THE TYPE: `isHunt` is `BaseKnotOffsetIsHunt`'s own answer — the flag the
// entry was picked with — so the card, the geometry and the hover cannot describe two rulers.
// (The old kind test is the same answer wherever it was reachable: FTR / no-type are isHunt=false.)
bool BaseKnotEntryRidesStop(const bool isHunt, const int stopTF)
{
   return (BaseKnotIsLadderRung(stopTF) || !isHunt);
}
// P-BK-135 (2026-10-28) - THE FACTOR BELONGS TO THE PAIR, NOT TO ONE LEG.
//
// MEASURED on his 2h20m ETR box (h 343.3, own ATR 228.0, off the ladder): BaseKnotLegPair graded
// the STOP (53.4 x 1.506 = 80.5) and left the ENTRY at the knot's own Hunt (142.5), so the pair
// read 142.5 / 80.5 = 1.77 while the plan's own law is Trigger / TRex = 8/3 = 2.67 - a 34 % short
// ratio, with the three targets still 5x and 12x the GRADED stop. One factor on one leg is a
// second ruler: the entry line and every R were read in two regimes.
//
// THE RULE. `g` is a property of the PAIR: on a ladder rung (and on every FTR, whose two legs are
// one EngSL) the box' power lifts BOTH legs; off the ladder, with a HuntSL, it lifts NEITHER -
// there is no rung above the knot's own time to grade against (P-BK-133), and grading one leg is
// what counted the growth twice. Same fence `BaseKnotEntryRidesStop` already asks; the answer now
// multiplies both numbers or neither, so entry / stop is 8/3 (Hunt) or 1 (FTR) for EVERY knot and
// every leg is `a x g x constant` - one ATR, five constants, no second multiplication.
// THE READERS: BaseKnotLegPair (the lines), BaseKnotRiskPips (the note's number), the targets and
// the card all derive their factor from the DRAWN pair, so no reader can spell a ratio of its own.
double BaseKnotPairGrade(const bool isHunt, const int legTF,
                         const double boxEngPips, const double legEngPips)
{
   if(!BaseKnotEntryRidesStop(isHunt, legTF)) return 1.0;   // off-ladder Hunt: the pair rides the knot's own time
   return BaseKnotLegGrade(boxEngPips, legEngPips);         // a rung (or an FTR): both legs, one factor
}
