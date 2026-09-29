// BaseKnot_Nodes.mqh - BaseKnotTool split 2026-09-29: exact lines 2763-4052 of BaseKnotTool.mqh, byte-identical, zero renames.
#ifndef BASE_KNOT_NODES_MQH
#define BASE_KNOT_NODES_MQH

// P-BK-30: the count is the ONLY part of the SIZING preview that costs a bar walk
// (two series reads per bar over the base run, on a 30 ms cursor path), so
// it gets its own cadence: the box' geometry and the rays stay pixel-live, the
// NUMBER is refreshed at most every BK_LIVE_COUNT_MS. What the user is aiming at
// is the rectangle, not the digits — and the digits are always exact on the frame
// that matters, because the commit runs the authoritative `BaseKnotSync` (plain
// BaseKnotBarCount). Measured effect on the sizing path: ~33 Hz -> ~8 Hz walks,
// with no visible difference in the label.
#define BK_LIVE_COUNT_MS 120
//--- P-BK-45 (2026-09-15) — WHILE THE USER DRAWS: THE BAND IS THE QUESTION, THE EDGES
//--- ARE POINTERS, SO AN EDGE THAT MOVES INSIDE THE RUN THE BAND ALREADY FOUND COSTS
//--- NOTHING. «همون جای که کاربر داره رسم میکنم … بهترن کار چیه که فشار الکی هم نیاد و
//--- اینکه درست هم تشخیص داده بشه».
//---
//--- The walk's own law (P-BK-44) says the answer is a property of the BAND plus the run
//--- that band holds: the box' right edge only says WHERE to start looking, and once the
//--- run is found, sliding the edge over it cannot change the run, its entry, its exit,
//--- its class or its node story. Measured on the user's own EURUSD M15 tape for his
//--- box (band 1.16060..1.16165): sliding the edge from 09-11 00:15 to 05:00 (20
//--- positions, inside the run) and on to 08:00 (12 more, over the dead zone) returned
//--- the IDENTICAL reading — 20 bars · H1 base · CTR — at all 32 positions, and the
//--- first position that changed it was 08:15, where the edge itself lands inside a
//--- LATER base (9 bars · M15). That window is not a tolerance: it is exactly between
//--- the run's own oldest candle and the first in-band candle NEWER than its newest
//--- one, because that candle is what a walk started at the edge would anchor on.
//---
//--- So the cache is keyed on the BAND (top, bot, the newest closed candle, this chart)
//--- and stores that window. A horizontal drag — the common gesture, the one that used
//--- to pay a full walk every BK_LIVE_COUNT_MS — reads the cached span outright; a band
//--- change (a vertical drag) is the only thing that can move the base, and it pays one
//--- walk per cadence exactly as before. The commit still runs the authoritative plain
//--- `BaseKnotBarCount` (P-BK-30), so the preview being cheap never becomes the reading's
//--- source of truth. The class rides the same reuse for free: its memo (P-BK-36) is
//--- keyed on the span's own two ends, which a reused span does not change.
static double   s_bkLiveTop = 0.0;      // the BAND the cached run was found with
static double   s_bkLiveBot = 0.0;
static datetime s_bkLiveBar = 0;        // ... and the newest closed candle it was read on
static int      s_bkLiveLo  = 0;        // the EDGE WINDOW it stays valid for (shifts,
static int      s_bkLiveHi  = -1;       // 0/-1 = no window: nothing to reuse)
int BaseKnotLiveBarCount(const datetime t1, const datetime t2, const double top, const double bot,
                         BaseKnotSpan &sp)
{
   static uint s_ms = 0;
   static int  s_n  = 0;
   static BaseKnotSpan s_sp;   // P-BK-41: the WHOLE span is memoised, not only its count
   uint now = GetTickCount();
   datetime lastClosed = iTime(_Symbol, 0, 1);
   if(s_n > 0 && top == s_bkLiveTop && bot == s_bkLiveBot && lastClosed == s_bkLiveBar &&
      s_bkLiveHi > 0)
   {
      int e = iBarShift(_Symbol, 0, t2, false);
      if(e == 0) e = 1;    // P-BK-34: the edge is read at the newest CLOSED candle
      if(e >= s_bkLiveLo && e <= s_bkLiveHi) { sp = s_sp; return s_n; }   // P-BK-45
   }
   if(now - s_ms < BK_LIVE_COUNT_MS) { sp = s_sp; return s_n; }
   s_ms = now;
   s_n  = BaseKnotBarCount(t1, t2, top, bot, s_sp);
   sp = s_sp;
   if(s_n > 0)
   {
      s_bkLiveTop = top; s_bkLiveBot = bot; s_bkLiveBar = lastClosed;
      int head = iBarShift(_Symbol, 0, s_sp.tLast, false);    // the run's own right side
      int old  = iBarShift(_Symbol, 0, s_sp.tStart, false);   // ... and its oldest candle
      int lo   = 1;
      if(head > BK_BASE_SKIP) lo = head - BK_BASE_SKIP + 1;   // past the budget the walk finds nothing
      for(int e = head - 1; e >= lo; e--)                     // the first in-band candle NEWER
         if(BaseKnotBarBodyInside(e, top, bot)) { lo = e + 1; break; }   // anchors a DIFFERENT run
      s_bkLiveLo = lo;
      s_bkLiveHi = (old > 0 ? old : head);
   }
   else { s_bkLiveLo = 0; s_bkLiveHi = -1; }
   return s_n;
}
//+------------------------------------------------------------------+
//| P-BK-28 — THE BASE'S SIZE CLASS (2026-09-15)                     |
//|                                                                  |
//| The course the user works from defines the base by CANDLE COUNT,  |
//| not by pips: «سه کندل درجا زدن تعریف بیس هستش» — three candles    |
//| going nowhere ARE the base — «و ۹ الی ۱۲ کندل میره برای تایم       |
//| بالاتر») — and the SAME three candles of the time frame above are |
//| 9..12 of ours (3 x M15 = 12 x M5, 3 x H1 = 12 x M15). So the whole|
//| rule is one arithmetic line: the base belongs to the HIGHEST rung |
//| still holding 3 candles inside the box, and the count of OUR bars |
//| that means is 3 * rung / chartTF.                                 |
//|                                                                  |
//|   bars 1..2   -> structure — a knot read as one or two candles    |
//|                  belongs to the STRUCTURE TF, not to a base       |
//|                  («کندل تک یا دو کندل = ساختار»), so it is named  |
//|                  in the note, never silently read as a base;      |
//|   bars 3..8   -> a base of THIS chart's TF (3 candles = a base);  |
//|   bars 9..12  -> the base is one rung up (M5 chart -> M15 base);  |
//|   bars 12+    -> the same rule upward (M15 chart -> H1 base).     |
//|                                                                  |
//| It counts the bars the note ALREADY counts (BaseKnotBarCount —    |
//| P-BK-31/32: the base run — candle BODIES inside the ceiling/floor,|
//| ending at the break, a lone poke stepped over, never the box; and  |
//| P-BK-37: the number is that run's START up to the box' right edge,|
//| so the count and the class describe ONE object), and P-BK-36       |
//| CONFIRMS the rung on the RUNG'S OWN candles: one bounded walk of   |
//| the rung's bars (early exit at 3 confirmations, memoised per Sync),|
//| so the 500 ms pump pays no HTF fetch per box per round.            |
//| ATR is not a class input: it lives ABOVE this layer and only SIZES |
//| the node's numbers (P-BK-35).                                      |
//+------------------------------------------------------------------+
// P-BK-32: BK_BASE_MIN_BARS now sits with the count's own budgets (above
// `BaseKnotBarCount`) because the WALK reads it — candles found past a tolerated
// gap are counted only once a full base's length holds the band. Same value and
// same meaning as here: under 3 candles inside, it is structure, not a base.
// Next rung up MT4's own ladder (0 = already at MN1). Same shape as
// BaseKnotTFName / BaseKnotTFMask above, so an exotic chart TF can never
// name a rung those two do not know.
// P-BK-43 (2026-09-15) — THE BASE'S LADDER IS THE PROJECT'S LADDER: M1 · M5 · M15 · H1 ·
// H4 · D1 · W1 · MN1 — the SAME eight the ATR warm-up queue walks
// (`g_atrWarmupQueue[] = {1, 5, 15, 60, 240, 1440, 10080, 43200}`, ATRCalculations.mqh) and
// the same eight his own label row prints. «هنوز سی دقیقه نشون میده چرا» — M30 is not one
// of our TFs, so «7 bars · M30 base» on an M15 box was a class the ladder had no business
// naming: `3 * 30 / 15 = 6 <= 7` admitted M30 over a base barely three M30 candles long,
// and the rung read then found those three lying inside the band. The ladder steps
// 15 -> 60 now. An M30 CHART still names M30, and it names it as `Period()` — the base's
// own TF — never as a rung.
// P-BK-82 (2026-09-17) — AND M1 IS A RUNG. The user: «چرا تایم گره رو درست و اصولی تشخیص
// نمیده، گره که مال یک دقیقه هستش رو مال پانزده دقیقه نشون میده». The steps above start at
// 5, so a walk that STARTS at 0 — `BaseKnotLadderAll`, i.e. the CLASS read's own ladder —
// could never reach M1: a base whose candles stand still on M1 fell past every rung, and the
// read then named the SPAN's own rung instead (the user's box: 17 minutes wide around a
// 5-bar M1 base — `3 * 15 > 17` refused M15, and the fallback `rungs[i] <= spanMin` named it
// anyway -> «M15 base»). The floor is the ATR queue's own first member (P-BK-43's
// `g_atrWarmupQueue[]` starts at 1) and the eight names above. NOTHING ELSE MOVES: every
// other caller hands a tfMin >= 1, where `tfMin < 5` still answers 5 — the ladder's own walk
// is the only caller that starts from 0, so it is the only one that gains the rung.
int BaseKnotNextTFMin(const int tfMin)
{
   if(tfMin < 1)     return 1;       // P-BK-82: the FLOOR — M1 is a rung of our ladder
   if(tfMin < 5)     return 5;
   if(tfMin < 15)    return 15;
   if(tfMin < 60)    return 60;      // P-BK-43: 30 is NOT in our ladder
   if(tfMin < 240)   return 240;
   if(tfMin < 1440)  return 1440;
   if(tfMin < 10080) return 10080;
   if(tfMin < 43200) return 43200;
   return 0;
}
// P-BK-36 (2026-09-15) — «سه کندل درجا زدن برای مشخص کردن تایم بیس باید مولتی تایم
// باهش تشخیصش … این گره باید برای تایم پایین باهش چون سه کندل درجا زدن نداره»:
// THE RUNG IS CONFIRMED ON THE RUNG'S OWN CANDLES.
//
// P-BK-28's ladder is arithmetic on OUR bars (3 x rung / chartTF <= bars) and that
// is the rung's DISPLACEMENT, nothing more: it says "three candles of that TF fit
// inside this number", never "three candles of that TF stood still here". The two
// part ways whenever the base and the rung are not aligned — 12 M15 candles sitting
// in the upper half of one H1 candle are a base whose H1 candle poked out of the
// band — and the same box then names a different class depending on the chart it is
// read on. So the highest rung the ladder admits is used only when ITS OWN candles
// hold the band: >= BK_BASE_RUNG_MIN of the rung's candles overlapping the box keep
// their BODIES inside [bot,top] — the same criterion the count walks with, spelled
// once, never a margin.
//
// The read is bounded and cheap (the user: «همین که فشار به سیستم نیاد از محاسبات
// الکی»): only the rungs the ladder already admitted are read at all, the scan stops
// on the first BK_BASE_RUNG_MIN confirmations, it examines at most BK_BASE_RUNG_MAX
// rung candles, and the answer is MEMOISED on the exact question (edges, band,
// count, chart TF, newest closed bar) because the note, its hover and the box
// tooltip all ask for the class inside one Sync — one rung read per Sync, not three.
//
// Nothing is ever invented: when the rung's series is not there to be read (offline
// history, a rung the terminal never downloaded) the arithmetic ladder answers,
// exactly as it did before this rule; when a rung's candles do NOT stand still, the
// next rung down is tried; and a base whose rungs never stand still is a base of
// THIS chart's TF.
#define BK_BASE_RUNG_MIN 3     // «سه کندل درجا زدن» — on the RUNG's OWN candles
#define BK_BASE_RUNG_MAX 60    // rung candles examined per rung (a bounded read)
// The rung's series is there to be read at all? (a rung == this chart's TF always is)
bool BaseKnotRungLoaded(const int tfMin)
{
   if(tfMin <= 0) return false;
   if(tfMin == Period()) return true;
   return (iBars(_Symbol, tfMin) > 0);
}
// Does the rung STAND STILL in this band? The number of the rung's candles
// overlapping the box whose BODIES are inside [bot,top]. Bounded: it stops on the
// first BK_BASE_RUNG_MIN confirmations and never reads more than BK_BASE_RUNG_MAX
// rung candles. -1 = the rung's series is not readable (never a 0 dressed up as an
// answer, because 0 and "cannot tell" must not read the same).
// P-BK-41: the span every one of these reads is the BASE'S OWN STORY (its first candle
// to the candle that closed outside the band) — passed in as `s1..s2` so a caller cannot
// quietly hand in the box' own rectangle instead. The note's number and the class are
// read from the SAME span, which is why they can never describe two different objects.
int BaseKnotRungHoldCount(const int tfMin, const datetime s1, const datetime s2,
                          const double top, const double bot)
{
   if(tfMin <= 0 || s2 <= 0 || top <= bot) return -1;
   // P-BK-77 (2026-09-17): THIS CHART'S OWN TF IS READ LIKE ANY OTHER RUNG. It used to
   // answer BK_BASE_RUNG_MIN without reading a single candle ("the walk already did it"),
   // which made the CHART decide the class: on an M15 chart the M15 rung confirmed itself
   // and a box that stood still on M5 was called an «M15 base». The walk is still the
   // chart's, but the RUNG's own candles are the only thing this count may read.
   if(!BaseKnotRungLoaded(tfMin)) return -1;
   int sh1 = iBarShift(_Symbol, CompatTF(tfMin), s1, false);
   int sh2 = iBarShift(_Symbol, CompatTF(tfMin), s2, false);
   if(sh1 < 0 || sh2 < 0) return -1;                // the box is older than this series
   int newer = (sh1 < sh2 ? sh1 : sh2);             // smaller shift = newer candle
   int older = (sh1 < sh2 ? sh2 : sh1);
   if(older - newer + 1 > BK_BASE_RUNG_MAX) older = newer + BK_BASE_RUNG_MAX - 1;
   int held = 0;
   for(int s = newer; s <= older; s++)
   {
      double o = iOpen(_Symbol, tfMin, s);
      double c = iClose(_Symbol, tfMin, s);
      if(o <= 0 || c <= 0) continue;                // series not ready — never invented
      if(o >= bot && o <= top && c >= bot && c <= top)
      {
         held++;
         if(held >= BK_BASE_RUNG_MIN) return held;  // bounded: enough to confirm
      }
   }
   return held;
}
// Minutes of the TF this base belongs to; 0 = unmeasurable (series not
// ready), -1 = structure (1-2 candles — not a base at all).
// P-BK-36: THE LADDER PROPOSES, THE RUNG'S OWN CANDLES DECIDE.
//
// P-BK-77 (2026-09-17, user: «باید تایم گره صد در صد درست تشخیص داده بشه، مهم نیست روی چه
// تایمی هستیم»): THE WHOLE LADDER IS SEARCHED, AND THE SPAN IS COUNTED IN MINUTES. The
// user draws the box with the MEASURING TOOL, so neither the chart's TF nor the box' own
// commit TF is evidence of anything: his node's three candles may belong to a HIGHER time
// than the box was drawn on, or to a LOWER one. The read therefore:
//   * measures the span in MINUTES (`(s2 - s1)/60 + one chart candle`), so no rung is
//     admitted or refused because of which chart happens to be open;
//   * walks the PROJECT'S WHOLE LADDER (M1·M5·M15·H1·H4·D1·W1·MN1), BOTH WAYS — the
//     rungs below the box' TF are candidates exactly like the ones above it;
//   * reads every rung on its OWN candles (P-BK-77's other half lives in
//     BaseKnotRungHoldCount: this chart's TF no longer confirms itself for free);
//   * names the NODE'S TIME as the HIGHEST rung with three of its own candles standing
//     still — the user's own definition of «تایم گره» («سه کندل درجا زدن»): the biggest
//     time in which the three candles are still visible.
// A rung whose series cannot be read is REMEMBERED, not returned on the spot: the walk
// keeps looking for a rung that really stands still and only falls back to it when none
// does (P-BK-36's promise — a class is never dropped because a series is not loaded).
// When NO rung stands still, the answer is the LARGEST rung one candle of which still
// fits the span (a 40-minute band -> M15), never the open chart's TF.
//
// P-BK-80 (2026-09-17) — AND THE CHART CONTRIBUTES NOTHING AT ALL. The user: «تایم گره
// توی یکساعته درست تشخیص داده ... ولی تایم بالا که میریم میزنه ftr، کلا یک گره فقط یک
// تایم میتونه داشته باشه متعلق به یک تایم هستش». The span was still the CHART's: its two
// ends were chart-TF candle times (P-BK-41's walk) and `chartMin` was ADDED to the span
// («the exit candle's own width»), so `3 * rung <= spanMin` admitted a rung on an H4 chart
// that the very same box refused on H1 — 480..660 minutes of base read H1 on H1 and H4 on
// H4, and the taller rung's ATRs then typed a short box FTR. The span is now the BOX' OWN,
// `(t2 - t1) / 60` minutes, and the stand-still walk reads the rung's own candles over that
// same span: the box' two anchors are stored on the OBJECT, so the answer is bit-identical
// on every chart TF — the promise P-BK-77 made and P-BK-41's chart read was still breaking.
// The box' own span is also the honest input: «تایم گره» is a property of what the user
// DREW (the band and the range), never of the chart he happens to look through.
//
// P-BK-82 (2026-09-17) — AND THE LADDER HAS TO REACH M1 (the floor itself lives in
// `BaseKnotNextTFMin`). The walk below starts at the ladder's HIGHEST rung and comes down,
// so a floor at M5 meant a base standing still on M1 could never be NAMED M1: every rung was
// refused and the "nothing stood still" fallback named the span's own rung instead — which
// is exactly how the user's 17-minute box around a 5-bar M1 base came out as «M15 base»
// («گره که مال یک دقیقه هستش رو مال پانزده دقیقه نشون میده»). With M1 in the ladder the
// chart's own TF is always a candidate, so a base of >= 3 stand-still candles confirms a rung
// instead of falling through to the span — and the fallback below is the last resort it was
// always meant to be.
int BaseKnotLadderAll(int &rungs[])
{
   int all[9];
   ArrayInitialize(all, 0);   // explicit: the loop fills it in order, the copy below reads `n` of them
   int n = 0;
   int r = 0;
   for(int i = 0; i < 9; i++)
   {
      r = BaseKnotNextTFMin(r);   // the ONE owner of the ladder's steps
      if(r <= 0) break;
      all[n] = r;
      n++;
   }
   ArrayResize(rungs, n);
   for(int i = 0; i < n; i++) rungs[i] = all[i];
   return n;
}
int BaseKnotBaseTFRead(const int bars, const datetime b1, const datetime b2,
                       const double top, const double bot)
{
   if(bars <= 0) return 0;
   if(bars < BK_BASE_MIN_BARS) return -1;
   // P-BK-80: NO CHART TERM, EVER. The chart TF used to add its own candle width here
   // (`+ chartMin`) and to supply the span's two ends; both are gone, so `3 * rung <= spanMin`
   // answers the same on M1 and on MN1.
   // P-BK-84: and the span is the BASE'S OWN entry..exit, unioned with the box' two anchors
   // (BaseKnotClassSpan — the box is a FLOOR, never the measurement). No chart term anywhere.
   int spanMin = (int)((b2 > b1 ? (b2 - b1) / 60 : 0));
   int rungs[9];
   int n = BaseKnotLadderAll(rungs);
   if(n <= 0) return 1;   // no ladder at all — M1 is the only rung left to name
   // P-BK-84 (2026-09-18) — THE LENGTH IS THE CRITERION (BKHOLD-OFF). The user: «اون سه
   // کندل درجا زدن یکم قانونش خیلی سخت و خشک هستش اگر این سه کندل ملاک بشه عالی میشه ولی
   // مولتی تایم که هر گره یک تایم بیشتر نداشته باشه در هر تایم فریمی که بودیم». The walk
   // returns the HIGHEST rung whose THREE candles fit inside the base — «سه کندل» of the
   // rung, exactly as the user's own rule spells it — and NOTHING ELSE. It reads no series
   // at all, so the answer is pure arithmetic on the span: one knot, ONE time, on every
   // chart TF (P-BK-77's promise), and the class' cost on the Sync path is now zero bars.
   for(int i = n - 1; i >= 0; i--)
      if(3 * rungs[i] <= spanMin) return rungs[i];   // three of its candles fit -> THE NODE'S TIME
   // P-BK-77: the span is shorter than three M1 candles — the span's OWN rung, the largest
   // one a single candle of which still fits in it. A real TF of THIS span, on every chart.
   // P-BK-80: and a degenerate span (a box narrower than one M1 candle) ends at the
   // ladder's own first rung — never at the open chart's TF, which is what leaked before.
   for(int i = n - 1; i >= 0; i--)
      if(rungs[i] <= spanMin) return rungs[i];
   return rungs[0];
   // BKHOLD-OFF (P-BK-84, 2026-09-18): THE STAND-STILL VETO IS RETIRED IN PLACE. It asked
   // the rung's OWN candles to keep their bodies inside the band and only named the rung
   // when >= BK_BASE_RUNG_MIN of them did (P-BK-36's «سه کندل درجا زدن»). The user's own
   // call is that the rule is «خیلی سخت و خشک»: a 17-minute base overlaps FOUR M5 candles,
   // and the two on the span's edges start before the base or close after it, so the count
   // could never reach three however still the base was — the veto was reading the SPAN'S
   // EDGES, not the base. The count is still read and still REPORTED (the hover prints it,
   // BaseKnotRungHoldCount is its one owner), it just no longer decides. Restore by putting
   // the three commented lines back and re-teaching base-count-audit's RUNG gate — never
   // by rewriting the length walk above, which owns the class now.
   //
   // int unread = 0;
   // for(int i = n - 1; i >= 0; i--)
   // {
   //    int rung = rungs[i];
   //    if(3 * rung > spanMin) continue;
   //    int held = BaseKnotRungHoldCount(rung, b1, b2, top, bot);
   //    if(held < 0) { if(unread <= 0) unread = rung; continue; }
   //    if(held >= BK_BASE_RUNG_MIN) return rung;
   // }
   // if(unread > 0) return unread;
}
// The memo (P-BK-36): the answer is closed-bar data, so it can only change when the
// QUESTION changes — the box' two anchors, its band, the count it was computed from, or a
// new closed bar. P-BK-80: the chart TF is NO LONGER part of the key, because it is no
// longer part of the question — that is the whole promise, and a key that carried it could
// only ever hand the same box two different answers on two charts.
static int      s_bkRungBars   = -1;
static datetime s_bkRungB1     = 0;   // P-BK-80: the BOX' left anchor
static datetime s_bkRungB2     = 0;   // ... and its right anchor (never the story's ends)
static double   s_bkRungTop    = 0.0;
static double   s_bkRungBot    = 0.0;
static datetime s_bkRungBar    = 0;
static int      s_bkRungAnswer = 0;
// P-BK-80: the question is the BOX' OWN geometry alone — its two anchors, its band, and the
// base count it was computed from. No box TF, no chart TF, no chart candle width.
int BaseKnotBaseTFMin(const int bars, const datetime b1, const datetime b2,
                      const double top, const double bot)
{
   datetime lastClosed = iTime(_Symbol, 0, 1);
   if(bars == s_bkRungBars && b1 == s_bkRungB1 && b2 == s_bkRungB2 &&
      top == s_bkRungTop && bot == s_bkRungBot &&
      lastClosed == s_bkRungBar)
      return s_bkRungAnswer;
   int answer = BaseKnotBaseTFRead(bars, b1, b2, top, bot);
   s_bkRungBars = bars; s_bkRungB1 = b1; s_bkRungB2 = b2;
   s_bkRungTop = top; s_bkRungBot = bot;
   s_bkRungBar = lastClosed; s_bkRungAnswer = answer;
   return answer;
}
// Compact note suffix: " · M15 base" / " · H1 base" / " · struct" / "".
// P-BK-80: `b1..b2` = the BOX' OWN two anchors — the only input the class has.
string BaseKnotBaseTag(const int bars, const datetime b1, const datetime b2,
                       const double top, const double bot)
{
   int tf = BaseKnotBaseTFMin(bars, b1, b2, top, bot);
   if(tf == 0) return "";   // unmeasurable — the bars part is omitted too
   if(tf <  0) return " · struct";
   return " · " + BaseKnotTFName(tf) + " base";
}
// The same read spelled out for the hover line (the note's full sentence).
string BaseKnotBaseLine(const int bars, const datetime b1, const datetime b2,
                        const double top, const double bot)
{
   int tf = BaseKnotBaseTFMin(bars, b1, b2, top, bot);
   if(tf == 0) return "\nBase: size not measurable yet";
   if(tf <  0) return "\nBase: " + IntegerToString(bars) +
                      " bars -> structure (a base needs " + IntegerToString(BK_BASE_MIN_BARS) + " candles inside)";
   // P-BK-84: THE LENGTH IS THE CRITERION, and the stand-still count is REPORTED beside it —
   // it no longer decides anything (BKHOLD-OFF). The sentence states the rule it was named by.
   int spanMin = (int)((b2 > b1 ? (b2 - b1) / 60 : 0));
   if(3 * tf > spanMin)   // the span's own rung: no rung's three candles fit it
      return "\nBase: " + IntegerToString(bars) + " bars -> " + BaseKnotTFName(tf) +
             " base (no rung's " + IntegerToString(BK_BASE_RUNG_MIN) + " candles fit the span — the span's own rung)";
   int held = BaseKnotRungHoldCount(tf, b1, b2, top, bot);   // P-BK-84: REPORTED, never a decider
   return "\nBase: " + IntegerToString(bars) + " bars -> " + BaseKnotTFName(tf) +
          " base (" + IntegerToString(BK_BASE_RUNG_MIN) + " candles of " + BaseKnotTFName(tf) +
          " fit the span" +
          (held > 0 ? "; " + IntegerToString(held) + " of them stood still in the band" : "") + ")";
}
//+------------------------------------------------------------------+
//| P-BK-47 — THE NOTE'S NODE TYPE IS THE NODE'S LENGTH (the user's own  |
//| rule, 2026-09-15: «دسته بندی گره های معاملاتی براساس طول گره: FTR گرهی |
//| که طولش مساوی تایم تریگر تایمی باشد که گره در آن دیده میشود سه کندل · |
//| ETR گرهی که طولش مساوی تایم پترن باشد · CTR گرهی که طولش مساوی تایم    |
//| ساختار باشد · OTR گرهی که طولش بیشتر از تایم ساختار باشد»).            |
//|                                                                  |
//| The length is read on the PROJECT'S ladder (P-BK-43's own eight),  |
//| and the class P-BK-36 already confirmed IS that length: a node     |
//| reaching the rung one step up holds THREE candles of that rung,    |
//| which IS the pattern time («سه کندل درجا زدن … تایم بالاتر»), two   |
//| steps up is the structure time. So the whole rule is one count of   |
//| RUNGS between the TF the node is SEEN ON (the box' commit TF — a   |
//| property of the BOX) and its class:                                 |
//|                                                                  |
//|   0 rungs  -> FTR — the trigger length: 3 candles of its own TF     |
//|   1 rung   -> ETR — the pattern time (3 candles of the rung above)  |
//|   2 rungs  -> CTR — the structure time (3 candles two rungs above)  |
//|   3+ rungs -> OTR — LONGER than the structure time                  |
//|                                                                  |
//| WHAT PRICE DID NO LONGER NAMES THE TYPE (BKNODEKIND-OFF retires the |
//| P-BK-29/35 read that did: the box' far edge, the second break and   |
//| the "never returned" test). The break's story is still read — on    |
//| the CLASS's own candles, as P-BK-38 read it — but it now names only |
//| the SIDE the trade comes in on (P-BK-46) and the step numbers that  |
//| size it. Two questions, one record, one read: the note, its hover,  |
//| the box tooltip and the pump's shadow can never describe two        |
//| different objects.                                                 |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
// P-BK-77: `BaseKnotNodeTFMin` IS GONE (it read the box' own commit TF, its id TF, or this
// chart). It existed so the TYPE could be read on "the TF the node is seen on" — and the
// user draws the box with the MEASURING TOOL, so that TF was never evidence of anything: a
// node seen on M5 whose three candles belong to H1 is an H1 node. The node's TIME is now
// found from the box' own geometry (BaseKnotBaseTFRead, the whole ladder) and is the only
// TF the type is read against. The TF a box LIVES on is still a fact — the TF mask and the
// pump's id read own it — it just no longer names the node's time.
//+------------------------------------------------------------------+
//| P-BK-75 (2026-09-17) — THE TYPE IS THE BOX' HEIGHT AGAINST THE     |
//| MOVEMENT ABILITIES OF THE NODE'S OWN TF.                           |
//|                                                                  |
//| The user restated his own rule («باید اینطوری باشه»):              |
//|   «دسته بندی گره های معاملاتی براساس طول گره … اف تی ار (FTR):      |
//|   گرهی که طولش مساوی توان حرکتی تایمی باشد که گره در آن دیده        |
//|   میشود · ای تی ار(ETR): مساوی توان حرکتی تایم پترن · سی تی ار     |
//|   (CTR): مساوی توان حرکتی تایم ساختار · او تی ار (OTR): بیشتر از    |
//|   توان حرکتی تایم ساختار» + «تایم گره هم که باید سه کندل دیده بشه   |
//|   میشه تایم گره سه کندل درجا زدن» + «طول گره باید با th هر تایم     |
//|   مقایسه بکنی» + «ارتفاع باکس».                                    |
//|                                                                  |
//| «توان حرکتی تایم» IS THAT TIMEFRAME'S ATR (user decision,          |
//| 2026-09-17: «به جای th از atr استفاده بشه» — TH was the first      |
//| answer, ATR replaced it) — the PROJECT'S OWN composite ATR          |
//| (`CalculateWeightedATR`, ATRCalculations.mqh: the weighted SMA      |
//| blend over 5/10/21/66/132/264, the very number the strip and the    |
//| trade plan already read per TF). P-BK-78 (2026-09-17, user:        |
//| «اندازه گره متعلق به تایم بالاتر از تایم گره هستش پس باید ETR        |
//| بشه»): THE THREE ABILITIES ARE THREE TFs' OWN TH (P-BK-92, was ATR) — the node's     |
//| TIME (P-BK-77: the rung whose own three candles stood still), the   |
//| PATTERN time ONE rung above it, and the STRUCTURE time TWO rungs    |
//| above it. So "the size belongs to a higher time than the node's     |
//| time" IS the ETR reading, exactly as the user's own rule spells it  |
//| («مساوی توان حرکتی تایم پترن»), and the 0.25/0.50/1.00 ratios of    |
//| one ATR are gone: they could never say that.                       |
//|                                                                  |
//| THE LENGTH IS THE BOX' HEIGHT (top - bot, the user: «ارتفاع باکس») |
//| and the four names are the four bands that height falls in:        |
//|   h <= trigger   -> FTR — the node's own time's ability            |
//|   h <= pattern   -> ETR — the PATTERN time's (one rung above)      |
//|   h <= structure -> CTR — the STRUCTURE time's (two rungs above)   |
//|   h >  structure -> OTR — LONGER than the structure time's ability |
//| The bands ARE the levels because no name exists BELOW the trigger: |
//| the shortest node there is, IS the trigger length.                 |
//|                                                                  |
//| WHAT THIS REPLACED (BKNODERUNG-OFF, below): the rung count named   |
//| the type by a DURATION — the class the base was GIVEN (P-BK-36:   |
//| three candles of a higher rung standing still inside the band) —   |
//| while the user's rule names it by a PRICE. On one box the two      |
//| could disagree, and the class itself is read against the OPEN      |
//| CHART's TF (BaseKnotBaseTFMin takes no TF), so a TF switch could   |
//| move a type. The height read below takes the NODE's own TF and     |
//| nothing else.                                                      |
//|                                                                  |
//| P-BK-92: the user reversed P-BK-75/78 (TH instead of ATR) - history above kept.
//| LAYER LAW: TH lives in THCalculations below this module, so the three numbers   |
//| are PUSHED IN per TF exactly like the EngSL table (P-BK-46/50/51)  |
//| — `BaseKnotEngPump` (EventHandlers) computes one row per TF the    |
//| live boxes ask for and hands it back here. A TF with no row is an  |
//| ABSENCE (0 = "never pushed"), never a guess: the type then stays   |
//| BK_NODE_NONE and every text says so.                               |
//|                                                                  |
//| THE RULE LIVES HERE, NOT AT THE PUSH SITE: the pump hands in ONE   |
//| number per TF — that TF's TH, nothing else — and this table       |
//| resolves the three abilities from the LADDER. A second place that  |
//| picked a rung or scaled a TH would be a second owner of the rule.|
//+------------------------------------------------------------------+
#define BK_AB_TF_MAX BK_ENG_ROW_MAX
static int      s_bkAbTF[BK_AB_TF_MAX];
static datetime s_bkAbAnchor[BK_AB_TF_MAX];   // P-BK-79: the bar this TH was read at
static double   s_bkAbTH[BK_AB_TF_MAX];   // that TF's own TH points, price units
static int      s_bkAbN = 0;
// One round of the pump opens with this, so a TF nobody asks for any more cannot
// answer a later question with a stale row.
void BaseKnotAbilityReset() { s_bkAbN = 0; }
// One row per (TF, ANCHOR) — the pump's own ask list (BaseKnotEngNeeds) is the list, so
// the ask and the answer can never disagree about which TFs a box draws with, nor about
// the bar. P-BK-79: the anchor is why this table needed a second key at all — two boxes
// on one TF whose bases ended on two bars must type against two different THs, and the
// live row (anchor 0) is the sizing preview's own. A repeated pair overwrites (the newest
// round wins) and a full table refuses quietly: both are bounded refusals, never an
// eviction that would silently drop another box's row.
//
// `th` is that TF's TH points in PRICE units (P-BK-92, was composite ATR). 0 is
// the absence ("not warm"), and it is stored AS an absence: the row stays 0
// and BaseKnotAbilityRow refuses it, so a cold rung can never become a threshold of zero.
void BaseKnotAbilityPush(const int tfMin, const datetime anchor, const double th)
{
   if(tfMin <= 0) return;
   datetime an = (anchor > 0 ? anchor : 0);   // 0 = the live row (P-BK-79)
   double v = (th > 0.0) ? th : 0.0;   // P-BK-78: ONE number per TF - the raw TH
   for(int i = 0; i < s_bkAbN; i++)
   {
      if(s_bkAbTF[i] != tfMin || s_bkAbAnchor[i] != an) continue;
      s_bkAbTH[i] = v;
      return;
   }
   if(s_bkAbN >= BK_AB_TF_MAX) return;
   s_bkAbTF[s_bkAbN]     = tfMin;
   s_bkAbAnchor[s_bkAbN] = an;
   s_bkAbTH[s_bkAbN]    = v;
   s_bkAbN++;
}
// ONE (TF, anchor) row's raw TH. false = never pushed, or pushed while its TH was not
// warm — an absence the caller reports, never a zero dressed up as a threshold.
bool BaseKnotAbilityRow(const int tfMin, const datetime anchor, double &th)
{
   th = 0.0;
   if(tfMin <= 0) return false;
   datetime an = (anchor > 0 ? anchor : 0);
   for(int i = 0; i < s_bkAbN; i++)
   {
      if(s_bkAbTF[i] != tfMin || s_bkAbAnchor[i] != an) continue;
      th = s_bkAbTH[i];
      return (th > 0.0);
   }
   return false;
}
// P-BK-78 — THE THREE ABILITIES, OFF THE LADDER. `tfMin` is the NODE'S TIME (P-BK-77's
// own answer), and the three numbers are the TH of THAT rung, of the rung ONE step above
// it (the PATTERN time, «تایم پترن») and of the rung TWO steps above it (the STRUCTURE
// time, «تایم ساختار»). P-BK-79: `anchor` is the bar all three are read at — the box' own
// story end — so one box has ONE type for ever once its base is closed. false = the node's
// time is unknown, the ladder has no rung above it (a MN1 node has no pattern time), or one
// of the three TFs was never pushed warm — an absence the caller turns into BK_NODE_NONE,
// never a band out of thin air.
bool BaseKnotAbilityGet(const int tfMin, const datetime anchor,
                        double &trig, double &pat, double &str)
{
   trig = 0.0; pat = 0.0; str = 0.0;
   if(tfMin <= 0) return false;
   int up1 = BaseKnotNextTFMin(tfMin);                          // the pattern time
   int up2 = (up1 > 0 ? BaseKnotNextTFMin(up1) : 0);            // the structure time
   if(up1 <= 0 || up2 <= 0) return false;                       // no rung above — nothing to compare against
   if(!BaseKnotAbilityRow(tfMin, anchor, trig)) return false;
   if(!BaseKnotAbilityRow(up1, anchor, pat)) return false;
   if(!BaseKnotAbilityRow(up2, anchor, str)) return false;
   return true;
}
// P-BK-75/76/78 — THE ONLY PLACE THE FOUR NAMES ARE SPELLED. `h` is the box' height (the
// length the user's rule compares); `nodeTFMin` is the NODE'S TIME (P-BK-77: the rung whose
// own three candles stood still), and the three thresholds are the THs of that rung and
// the two rungs above it (P-BK-78) — so no chart TF, drag or warm-up can move the type.
// BK_NODE_NONE = nothing to compare against (the node's time is unknown, the ladder has no
// rung above it, or one of the three THs is not warm) — an absence, never a band.
//
// P-BK-76 (2026-09-17, user: «هر کدوم از توان حرکتی به اندازه تایم تریگرش محدوده داره
// دیگه … توی مقایسه ها در نظر بگیرش زیاد خشک نباشه در مقایسات»): THE BOUNDARIES ARE THE
// MIDPOINTS, NOT THE LEVELS THEMSELVES. Each ability OWNS A RANGE around itself — half a
// trigger below its own level to half a trigger above — so a box landing a hair either
// side of an ability answers the ability it is NEAREST to instead of flipping on a knife
// edge. The midpoints are computed from the pushed abilities themselves, so nothing is
// hardcoded and a different TH table moves them with it. OTR keeps the boundary the user
// named for it — «بیشتر از توان حرکتی تایم ساختار» — so the structure ability is CTR's
// ceiling and anything above it is OTR.
// P-BK-79: `anchor` is the bar the three abilities are read at — the box' own story end.
// 0 = the live row, which is what the sizing preview asks for before it has a base.
int BaseKnotNodeKindOfLength(const int nodeTFMin, const double h, const datetime anchor = 0)
{
   double trig = 0.0, pat = 0.0, str = 0.0;
   if(h <= 0.0) return BK_NODE_NONE;
   if(!BaseKnotAbilityGet(nodeTFMin, anchor, trig, pat, str)) return BK_NODE_NONE;
   if(h <= (trig + pat) * 0.5) return BK_NODE_FTR;   // midpoint of trigger | pattern
   if(h <= (pat + str) * 0.5)  return BK_NODE_ETR;   // midpoint of pattern | structure
   if(h <= str)                return BK_NODE_CTR;   // the structure ability itself
   return BK_NODE_OTR;
}
// P-BK-76: THE TWO BOUNDARIES, for the texts — the same midpoints the read above uses,
// so a tooltip cannot print a band the type was not decided by. P-BK-79: read at the SAME
// anchor the type was, or the printed band would describe another bar's TH.
double BaseKnotNodeBandFtrEtr(const int nodeTFMin, const datetime anchor = 0)
{
   double trig = 0.0, pat = 0.0, str = 0.0;
   if(!BaseKnotAbilityGet(nodeTFMin, anchor, trig, pat, str)) return 0.0;
   return (trig + pat) * 0.5;
}
double BaseKnotNodeBandEtrCtr(const int nodeTFMin, const datetime anchor = 0)
{
   double trig = 0.0, pat = 0.0, str = 0.0;
   if(!BaseKnotAbilityGet(nodeTFMin, anchor, trig, pat, str)) return 0.0;
   return (pat + str) * 0.5;
}
//--- BKNODERUNG-OFF (P-BK-75, 2026-09-17): THE RUNG COUNT THAT NAMED THE TYPE.
//--- It read how many ladder rungs the base's class sat above the TF the node is seen
//--- on (P-BK-47). Retired IN PLACE because the user's rule names the type by the box'
//--- HEIGHT against the TH abilities, not by a rung distance — restore by uncommenting
//--- the pair below, putting the two calls back into BaseKnotNodeRead and the live read
//--- (the sites BaseKnotNodeKindOfLength now occupies), and re-teaching
//--- base-count-audit's length cases to strip_comments() — never by rewriting the height
//--- read above, which owns the type now. `BK_NODE_RUNG_*` and the `nd.rungs` field stay
//--- as the retired pair's own vocabulary (they are the numbers the pair below compares
//--- against), but NOTHING reads them any more: the field is initialised to -1 and never
//--- set, and the audit's own mirror of the pair is retired the same way.
//
// int BaseKnotNodeRungs(const int nodeTFMin, const int classMin)
// {
//    if(nodeTFMin <= 0 || classMin == 0) return -1;   // no class measured -> no length
//    if(classMin < 0) return -1;                      // structure (1-2 candles): not a base
//    if(classMin == nodeTFMin) return BK_NODE_RUNG_FTR;
//    int rung = nodeTFMin;
//    for(int i = 0; i < 8; i++)                       // the ladder's own eight, bounded
//    {
//       rung = BaseKnotNextTFMin(rung);
//       if(rung <= 0) break;                          // the top of the ladder
//       if(rung == classMin) return i + 1;
//       if(rung > classMin) break;                    // a class the ladder cannot name
//    }
//    return -1;
// }
// int BaseKnotNodeKindOf(const int rungs)
// {
//    if(rungs == BK_NODE_RUNG_FTR) return BK_NODE_FTR;
//    if(rungs == BK_NODE_RUNG_ETR) return BK_NODE_ETR;
//    if(rungs == BK_NODE_RUNG_CTR) return BK_NODE_CTR;
//    if(rungs >  BK_NODE_RUNG_CTR) return BK_NODE_OTR;
//    return BK_NODE_NONE;
// }
// P-BK-48 — L4: the class rung's OWN drift, read closed-bar only and bounded to
// BK_BIAS_CTX_BARS of its bars. +1 = the rung drifts WITH this side, -1 = against it,
// 0 = unknown (no side to compare, series not ready). It is a LABEL, so a chart TF that
// never loads its rung costs one 0 and nothing else — it never decides a side on its own.
int BaseKnotCtxAlign(const int ctxTF, const int side)
{
   if(side == 0) return 0;
   int tf = (ctxTF > 0 && ctxTF != Period() ? ctxTF : 0);
   if(tf > 0 && !BaseKnotRungLoaded(tf)) return 0;
   double now  = iClose(_Symbol, tf, 1);                     // closed bars only
   double then = iClose(_Symbol, tf, BK_BIAS_CTX_BARS);
   if(now <= 0 || then <= 0 || now == then) return 0;         // never invented
   int drift = (now > then ? 1 : -1);
   return (drift == side ? 1 : -1);
}
// ONE read, TWO halves (P-BK-47 + P-BK-29/38 + P-BK-48 + P-BK-81): the LENGTH names the
// type, the base's own EXIT CANDLE names the direction. Fills `nd` — never returns early
// half-filled.
//
// P-BK-38 (2026-09-15) — THE STORY IS TOLD IN THE BASE'S OWN TF's CANDLES, and the
// window is expressed in THAT TF's bars. «از تایم بزرگ به کوچیک و از کوچیک به بزرگ
// باید همون etr نشون بده» is only true if the events are the SAME events: with the
// chart's closes a D1 base was read as "broke, returned, broke again" on H1 (the
// level is crossed all day long) and as "broke, returned, stayed" on D1, and the
// 128-bar window meant five days of story on H1 against six months on D1 — one box,
// two different SIDES, decided by which chart happened to be open. The candidate is
// the class P-BK-36 just confirmed (or this chart's TF when the box has no class
// yet), so the side belongs to the BASE, like its length and its class, and
// switching TFs on one box cannot rewrite it. A rung whose series is not loaded
// falls back to the chart's own closes, exactly as before.
//
// P-BK-81 (2026-09-17) — AND THE WALK NO LONGER STARTS AT THE DRAWN RECTANGLE. It starts
// at the base's OWN EXIT CANDLE (`tExit` — the candle that closed outside the band, the
// very candle the note's number is counted to). That single change is what the user's two
// reports asked for: «کمی که جابجا میکن نوع گره عوض میشه چرا» — the old start was the box'
// right edge, so nudging the box moved the first close the walk examined and the direction
// flipped; and «چرا جهت درست تشخیص نمیده» — on a chart coarser than the node's own time that
// edge sat a whole bar PAST the exit, so the walk's first close was a much later candle
// (often a return) and named the opposite side. One candle, one answer, on every chart.
void BaseKnotNodeRead(const datetime t2, const double top, const double bot,
                      const int nodeTimeMin, const datetime tExit,
                      const datetime anchor,   // P-BK-79: the bar the type's THs were pushed at
                      BaseKnotNode &nd)   // P-BK-81: tExit = the base's OWN exit candle
{
   // P-BK-78: ONE TF, TWO JOBS. `nodeTimeMin` is the NODE'S TIME — P-BK-77's answer, the
   // rung whose own three candles stood still — and it is BOTH the TF the type is read
   // against (P-BK-78: its TH, the rung above's, the rung two above's) and the TF the
   // story is read on (P-BK-38). The box' own commit TF is no longer a separate fact here:
   // the user draws with the measuring tool, so the box' TF never named the node's time.
   // P-BK-79: `anchor` is the BOX' OWN STORY END — the bar the pump read the three THs at.
   // It must be handed in, never re-derived here: the pump keyed its rows on exactly this
   // value, and a second derivation (the box' right edge, `Period()`, "now") would ask for
   // a row nobody pushed and type every box BK_NODE_NONE. 0 = no story yet, which IS the
   // live row the sizing preview is answered by.
   nd.anchor = (anchor > 0 ? anchor : 0);
   nd.kind = BK_NODE_NONE; nd.rungs = -1; nd.nodeTF = nodeTimeMin; nd.baseTF = nodeTimeMin;
   nd.side = 0; nd.barsAgo = 0; nd.rebreaks = 0; nd.returned = false; nd.crossed = false;
   nd.baseStep = 0.0; nd.breakStep = 0.0; nd.retStep = 0.0; nd.storyTF = 0;
   nd.height = 0.0; nd.abTrig = 0.0; nd.abPat = 0.0; nd.abStr = 0.0;   // P-BK-75
   //--- (a) THE TYPE — the node's LENGTH against the TH abilities of the node's own TIME
   //--- (P-BK-75/78). Read FIRST, because it needs nothing this module has to fetch: the TF
   //--- is P-BK-77's answer and the three thresholds were pushed in by the pump.
   //--- The rung count that used to name it is retired (BKNODERUNG-OFF).
   nd.height = top - bot;   // «طول گره» — the box' own height, in price units
   nd.kind = BaseKnotNodeKindOfLength(nodeTimeMin, nd.height, nd.anchor);
   BaseKnotAbilityGet(nodeTimeMin, nd.anchor, nd.abTrig, nd.abPat, nd.abStr);   // published so the tooltip can spell the compare
   //--- (b) THE DIRECTION — P-BK-81: THE BASE'S OWN EXIT CANDLE. A box nobody has left
   //--- still answers 0, and the live price then decides the trade exactly as it did before
   //--- P-BK-46. The story walk below runs FORWARD from this same candle and only measures
   //--- the node's life (return, revisit, second break, far-edge close) — it can never name
   //--- a direction, which is the whole point of the change.
   if(top <= bot || t2 <= 0) return;
   if(s_bkStepTH > 0) nd.baseStep = (top - bot) / s_bkStepTH;
   int tfRead = 0;                        // 0 = this chart (MQL4's own "current" series)
   if(nodeTimeMin > 0 && nodeTimeMin != Period() && BaseKnotRungLoaded(nodeTimeMin))
      tfRead = nodeTimeMin;
   nd.storyTF = (tfRead > 0 ? tfRead : Period());
   int s2 = iBarShift(_Symbol, CompatTF(tfRead), t2, false);
   if(s2 <= 0) return;                    // the edge IS the newest candle — nothing happened after it
   // P-BK-48 — THE WHOLE PAST MARKET OF THIS NODE, from its right side to the newest
   // CLOSED candle, capped by BK_BIAS_MAX bars of the class' TF (the read stays bounded;
   // it is closed-bar data, so a new bar is the only thing that can move it).
   nd.lifeBars = (s2 > 1 ? s2 - 1 : 0);
   int oldest = s2 - BK_BIAS_MAX;
   if(oldest < 1) oldest = 1;             // shift 1 = the newest CLOSED candle (P-BK-34)
   // P-BK-81: WHERE THE WALK STARTS. The base's own exit candle, mapped onto the story TF —
   // `tExit` is the candle that closed outside the band (P-BK-44 reads it off the RUN, so it
   // is the base's own and never the drawn rectangle's). The box' right side is only the
   // FALLBACK: it is used when the base published no exit candle at all (a box whose story
   // has not been read yet) or when that candle is not a CLOSED bar of this TF.
   int start = s2 - 1;
   if(tExit > 0)
   {
      int sX = iBarShift(_Symbol, CompatTF(tfRead), tExit, false);
      if(sX >= 1) start = sX;
   }
   if(start < 1) return;                  // nothing closed to read — never invent a bar
   int    side = 0, brokeAt = 0, rebreaks = 0, revisits = 0, lastSide = 0;
   int    depBars = 0;
   bool   returned = false, insideBefore = true;
   double maxBreak = 0.0, maxRet = 0.0;
   for(int s = start; s >= oldest; s--)   // shifts fall as time grows — this IS chronological
   {
      double c = iClose(_Symbol, tfRead, s);
      if(c <= 0) continue;                // series not ready — skip, never invent a close
      bool inside = (c >= bot && c <= top);
      if(side == 0)
      {
         if(c > top)      { side =  1; maxBreak = c - top; brokeAt = s; depBars = 1; }
         else if(c < bot) { side = -1; maxBreak = bot - c; brokeAt = s; depBars = 1; }
         continue;                        // the break bar is not also a return
      }
      // P-BK-48: the DEPARTURE's own length — the leg that left the base, counted until
      // price first came back inside (it is «طول حرکت» the user reads the node by).
      if(!returned) depBars++;
      if(inside)
      {
         if(!insideBefore) revisits++;    // P-BK-48: a REVISIT — the market came back in
         insideBefore = true;
      }
      else
      {
         lastSide = (c > top ? 1 : -1);   // P-BK-48: the NEWEST close outside the band
         insideBefore = false;
      }
      if(side > 0)
      {
         if(c > top)           { maxBreak = MathMax(maxBreak, c - top); if(returned) rebreaks++; }
         else if(c < top)
         {
            returned = true; maxRet = MathMax(maxRet, top - c);
            // P-BK-35/47: back inside — and if it closed BELOW the box' floor it came
            // out the FAR edge. That is the story's own fact (it sends the trade to the
            // far side, BaseKnotNodeDir); it names no type any more.
            if(c < bot) nd.crossed = true;
         }
      }
      else
      {
         if(c < bot)           { maxBreak = MathMax(maxBreak, bot - c); if(returned) rebreaks++; }
         else if(c > bot)
         {
            returned = true; maxRet = MathMax(maxRet, c - bot);
            if(c > top) nd.crossed = true;   // the mirror image (broke down, ran out the top)
         }
      }
   }
   nd.side = side; nd.barsAgo = brokeAt; nd.rebreaks = rebreaks; nd.returned = returned;
   // BKPAT-OFF (P-BK-81): THE APPROACH LEG AND THE FOUR PATTERN NAMES LIVED HERE. The
   // approach walk read the last close outside the band before the base's own entry
   // (`tFrom`, P-BK-49) and `nd.pattern` was assigned from it and `side` — RBR/RBD/DBR/DBD.
   // Both are gone: RBR and DBR are the SAME direction (Buy) and RBD and DBD are the same
   // (Sell), so the approach could only ever have split continuation from reversal and the
   // four names carried no directional information the exit candle did not already carry.
   // The user's own call: «کلا از شر این rbr , dbd rbd خلاص بشیم و جهت سل و بای به صورت
   // صدردصدی درست تشخیص داده بشه». Restoring them means putting the walk, the two
   // assignments, `BaseKnotPatternName/Tag/Line`, the `BK_PAT_*` defines, the struct's
   // `approach`/`pattern`, the registry's `baseT` and the `tFrom` parameter back, AND
   // re-teaching the audit's gates named "the four names are GONE" — never by rewriting
   // the exit-candle start above, which owns the direction now.
   nd.depBars = depBars; nd.revisits = revisits; nd.lastSide = lastSide;
   if(s_bkStepTH > 0)
   {
      nd.breakStep = maxBreak / s_bkStepTH;
      nd.retStep   = maxRet   / s_bkStepTH;
   }
   // P-BK-48 — THE LIFE STATE (what the market DID with this node since it formed), and
   // the ladder that reads the side off it: CONSUMED first (the interest is spent, and
   // the knot then claims NO trade at all), then the departure, and only when the node's
   // own life says nothing does the LIVE price speak (P-BK-13's rule, sideLevel NONE).
   // P-BK-81: the state is a REPORT about the node's life — it never rewrites the side the
   // exit candle named (BKNODEDIR-OFF already retired the read that let it).
   if(side != 0)
   {
      if(nd.crossed)      nd.state = BK_STATE_CONSUMED;
      else if(returned)   nd.state = BK_STATE_TESTED;
      else                nd.state = BK_STATE_FRESH;
      nd.sideLevel = BK_SIDE_ZONE;
   }
   // P-BK-48 — L4, THE CONTEXT LABEL: whether the class rung the node belongs to is
   // drifting WITH the trade or AGAINST it. It is REPORTED, never a decider on its own.
   nd.ctxAlign = BaseKnotCtxAlign((nodeTimeMin > 0 ? nodeTimeMin : Period()), nd.side);
   // P-BK-48/81: the SIDE half is what makes a node readable on the PAST MARKET («برای
// اینکه سفارش گره بتونم پیدا کنم … شاید در گذشته مارکت هم تست کنمش»): the base's own exit
// candle says which way the orders were left, and the state says whether any of them
// survived.
// P-BK-47 — THE STORY ENDS HERE AND THE TYPE IS NOT ITS TO REWRITE. This is the
   // line the retired P-BK-29/35 rule lived on (BKNODEKIND-OFF): it set `nd.kind`
   // from `!returned` (FTR), `nd.crossed` (OTR), `rebreaks` (CTR) and otherwise ETR.
   // Restoring it means putting `nd.kind = ...` back into the branches below AND
   // re-teaching this audit's length cases — never by rewriting the length read
   // above, which owns the type now. Everything the walk found is still handed out:
   // it is what the life state and the hover's numbers are read from.
}

// BKPAT-OFF (P-BK-81): THE FOUR NAMES' OWN TEXT LIVED HERE — `BaseKnotPatternName`
// ("RBR"/"RBD"/"DBR"/"DBD"), `BaseKnotPatternTag` (the note's " · RBR" suffix) and
// `BaseKnotPatternLine` (the hover's "Pattern: RBR — price rallied into the base …"
// sentence). All three are gone, with the four defines they printed and the approach leg
// that fed them. The direction is now the base's own exit candle's close against the band
// (P-BK-81) and it is spelled by `BaseKnotExitLine` below — one bit, no name to get wrong.
// Restoring the names means restoring the whole BKPAT-OFF block, never re-adding them here
// alone (the audit's "the four names are GONE" gate is the reason).
// P-BK-81: the DIRECTION's own sentence — the ONE candle it was read from, and the promise
// that nothing the node did afterwards can move it. Same text on every chart TF and on the
// past market alike, because the candle is the base's own.
string BaseKnotExitLine(BaseKnotNode &nd)
{
   if(nd.side == 0) return "";
   string legOut = (nd.side > 0 ? "ABOVE the ceiling" : "BELOW the floor");
   return "\nDirection: " + (nd.side > 0 ? "BUY" : "SELL") + " — the base's own EXIT candle closed " +
          legOut +
          "\n      one candle, one answer: a return into the base, a second break of the edge and a" +
          "\n      close through the far edge are the node's LIFE (reported below), never its direction";
}
// The note's short name for a type ("FTR"), or "" for none.
string BaseKnotNodeShort(const int kind)
{
   if(kind == BK_NODE_FTR) return "FTR";
   if(kind == BK_NODE_ETR) return "ETR";
   if(kind == BK_NODE_CTR) return "CTR";
   if(kind == BK_NODE_OTR) return "OTR";
   return "";
}
// P-BK-46/81 — THE BASE'S OWN EXIT CANDLE NAMES THE SIDE, AND THE TRADE RIDES IT (user
// decision 2026-09-15: «براساس نوع گره ورود و تارگت ها مشخص بشه»):
//   * the exit candle CLOSED ABOVE the ceiling — the base was left upward, so the trade
//     comes in on the TOP edge (a buy above a broken ceiling);
//   * it CLOSED BELOW the floor — the base was left downward, so the trade comes in on
//     the BOTTOM edge.
// P-BK-47 moved the TYPE off the story (it is the node's length now) and P-BK-81 moved the
// SIDE onto the ONE candle the base actually left on: the walk's other facts — `returned`,
// `rebreaks`, `crossed` — are the node's LIFE and are REPORTED, never a direction. The
// order the retired read used (the far edge first, then the second break, then the return)
// is what BKNODEDIR-OFF retired: it let price REWRITE the side, which is exactly what the
// user's «کمی که جابجا میکن نوع گره عوض میشه» and «جهت درست تشخیص نمیده» were.
// 0 = the exit candle named nothing (no close outside the band yet, or no exit read): the
// live price decides instead, exactly as it did before P-BK-46. +1 = Buy, -1 = Sell.
int BaseKnotNodeDir(BaseKnotNode &nd)
{
   return nd.side;   // P-BK-81: the base's own EXIT CANDLE's close vs the band (ONE bit, FIXED)
   // BKNODEDIR-OFF (P-BK-49): the P-BK-46/48 read that let price REWRITE the side —
   // restore by uncommenting the four lines below.
   // BKNODEDIR-OFF: if(nd.state == BK_STATE_CONSUMED) return 0;   // P-BK-48: the orders are SPENT
   // BKNODEDIR-OFF: if(nd.rebreaks > 0) return nd.side;          // the same edge broke again
   // BKNODEDIR-OFF: if(nd.returned) return -nd.side;            // a return that stayed inside
   // BKNODEDIR-OFF: return nd.side;                              // never came back (FRESH)
}
// The name the course lists. P-BK-47: the PAIRS beside it (ABO/EBO/CBO/OBO) described
// the break's story — which named the type until the length rule and now names the
// trade's SIDE (BaseKnotNodeDir) — so the type answers the short name alone.
string BaseKnotNodeName(const int kind)
{
   return BaseKnotNodeShort(kind);
}
// Note suffix: " · FTR" / "" (nothing claimed — the note stays short).
string BaseKnotNodeTag(BaseKnotNode &nd)
{
   string s = BaseKnotNodeShort(nd.kind);
   return (s == "" ? "" : " · " + s);
}
// Hover sentence: the claim (the LENGTH), the story that named the side, and the step
// those numbers are in — a type without its numbers is a claim nobody can check.
string BaseKnotNodeLine(BaseKnotNode &nd, const double top, const double bot)
{
   if(nd.kind == BK_NODE_NONE) return "";
   string t = "\nNode: " + BaseKnotNodeShort(nd.kind) + " — ";
   if(nd.kind == BK_NODE_FTR)      t += "the node is as long as its own time's TRIGGER ability";
   else if(nd.kind == BK_NODE_ETR) t += "the node is as long as the PATTERN time's ability";
   else if(nd.kind == BK_NODE_CTR) t += "the node is as long as the STRUCTURE time's ability";
   else                            t += "the node is LONGER than the STRUCTURE time's ability";
   // P-BK-75/78: the length spelled the way it was MEASURED — the box' own HEIGHT against
   // the three TH abilities of the LADDER: the node's own time (P-BK-77's answer), the
   // PATTERN time one rung above it, and the STRUCTURE time two rungs above it. Each number
   // is named with the TF it was read on, so the compare can be checked against the ladder.
   // The rung count that used to sit here is retired (BKNODERUNG-OFF); the class the base
   // was GIVEN (P-BK-36) still rides `nd.baseTF` and the note's own "… base" suffix.
   t += "\n      length: " + DoubleToString(BaseKnotToPips(nd.height), 1) + " pips (the box' height)";
   if(nd.abStr > 0.0)
   {
      int up1 = BaseKnotNextTFMin(nd.nodeTF);                      // the pattern time
      int up2 = (up1 > 0 ? BaseKnotNextTFMin(up1) : 0);            // the structure time
      t += " vs " + BaseKnotTFName(nd.nodeTF) + " TH (trigger " + DoubleToString(BaseKnotToPips(nd.abTrig), 1) + ")" +
           " · " + BaseKnotTFName(up1) + " TH (pattern " + DoubleToString(BaseKnotToPips(nd.abPat), 1) + ")" +
           " · " + BaseKnotTFName(up2) + " TH (structure " + DoubleToString(BaseKnotToPips(nd.abStr), 1) + "), in pips";
      // P-BK-76: the bands the height fell in, spelled as the MIDPOINTS they are — so a box
      // a hair either side of an ability can be seen to still answer that ability.
      t += "\n      bands: FTR < " + DoubleToString(BaseKnotToPips(BaseKnotNodeBandFtrEtr(nd.nodeTF, nd.anchor)), 1) +
           " · ETR < " + DoubleToString(BaseKnotToPips(BaseKnotNodeBandEtrCtr(nd.nodeTF, nd.anchor)), 1) +
           " · CTR <= " + DoubleToString(BaseKnotToPips(nd.abStr), 1) + " · OTR above";
   }
   else
      t += " — the TH of " + BaseKnotTFName(nd.nodeTF) + " (or of the rung above it) is not warm yet, so no type is claimed";
   t += "\n      the type is the HEIGHT against those three — the same on every chart TF";
   // P-BK-46/81: WHAT THE EXIT CANDLE DOES TO THE TRADE — the same rule BaseKnotNodeDir
   // and BaseKnotCalcLevels apply, spelled for the user: which edge the entry sits on
   // (the edge the base was LEFT by) and that the stop is one EngSL behind it.
   // P-BK-51: the placement — the edge is the SIDE's, BOTH legs sit inside it, and the
   // penetration's measure follows the node's TYPE (EngSL for FTR, HuntSL for the longer
   // ones). Built from the SAME two owners the geometry reads, so hover and drawing part not.
   // P-BK-83: AND THE TWO LEGS READ TWO TIMES — the entry the NODE'S OWN (the class), the stop
   // the TYPE'S OWN (the rung the length matched). Both are named here, so a reader can check
   // each line against the time it was really measured on.
   int    wTF  = BaseKnotEntryTFMin(nd.kind, nd.baseTF);     // P-BK-83: the ENTRY's own time
   int    sTF  = BaseKnotMeasureTFMin(nd.kind, nd.baseTF);   // ... and the STOP's own time
   bool   wHu  = BaseKnotOffsetIsHunt(nd.kind, wTF, nd.anchor);   // P-BK-79: the box' own anchor
   string wTag = BaseKnotEntryOffsetTag(wHu);
   string wSrc = "ONE EngSL" + (sTF > 0 && sTF != wTF ? " of " + BaseKnotTFName(sTF) : "");
   if(nd.side == 0)
      t += "\n      trade: the live price names the side (the exit candle closed inside the band) — the entry waits ONE " +
           wTag + " INSIDE that edge, the stop " + wSrc + " behind it" + BaseKnotCapClause(wTF, wHu, top, bot, nd.anchor);
   // BKNODEDIR-OFF (P-BK-49): else if(nd.crossed || (nd.returned && nd.rebreaks == 0))
   // BKNODEDIR-OFF (P-BK-49):   t += "\n      trade: the return's own side — entry ONE R INSIDE the FAR edge, stop 1 EngSL behind it";
   else
      t += "\n      trade: the side the base was LEFT by — entry ONE " + wTag +
           " INSIDE the edge the exit candle closed past, the stop " + wSrc + " behind it" +
           BaseKnotCapClause(wTF, wHu, top, bot, nd.anchor) + BaseKnotExitLine(nd);
    // BKE2-OFF: no 2nd-entry line here.
    if(nd.side != 0)
   {
      t += "\n      exit candle " + (nd.side > 0 ? "UP " : "DOWN ") + IntegerToString(nd.barsAgo) + " bars ago";
      if(nd.breakStep > 0) t += " · " + DoubleToString(nd.breakStep, 1) + "x step";
      if(nd.retStep > 0)   t += " · returned " + DoubleToString(nd.retStep, 1) + "x step";
      if(nd.crossed)       t += " · ran out the FAR edge";
      if(nd.rebreaks > 0)  t += " · " + IntegerToString(nd.rebreaks) + " re-break(s) of the edge";
   }
   if(nd.baseStep > 0)  t += " · base " + DoubleToString(nd.baseStep, 1) + "x step";
   if(s_bkStepTH > 0)
      t += "\n      step (TH " + BaseKnotTFName(Period()) + ") = " + DoubleToString(BaseKnotToPips(s_bkStepTH), 1) + " pips";
   else
      t += "\n      step: unknown (TH not warm yet)";
   // P-BK-38/81: and the EVENTS are the base's own TF's candles, not this chart's.
   if(nd.storyTF > 0)
      t += "\n      story read on " + BaseKnotTFName(nd.storyTF) +
           " candles (the base's own TF) — every chart reads the same side";
   return t;
}
// P-BK-29 — the ONLY way the step gets in (see the statics' note at the top).
// The change guard IS the design: a pump pushing the same TH every round must
// re-read no note at all, while a value that really moved re-arms the pump's
// gate, so the new numbers land on their own — no flip and no tap needed to see
// them. P-BK-47: the step sizes the BREAK's story (and the R the trade is built
// in, P-BK-46) — it never decides the type, which is the node's LENGTH.
void BaseKnotStepPush(const double th)
  {
     double v = (th > 0 ? th : 0.0);
     if(v == s_bkStepTH) return;
     s_bkStepTH = v;
     s_bkNodeBar = 0;   // stale: the next pump re-reads every box' two answers
  }
double BaseKnotStepTH() { return s_bkStepTH; }
// P-BK-46 — WHAT THE PUMP LAYERS HAVE TO COMPUTE: the (TF, ANCHOR) PAIRS the live boxes
// call their own. A box whose class is not published yet (and the box being SIZED, which
// has no registry row at all) answers THIS chart's TF at anchor 0, because that is the TF
// and the row the note and the sizing preview would name. Deduped and bounded, so the
// caller computes one EngSL per DISTINCT pair and nothing else: no box, no Eng beyond the
// chart's own.
// P-BK-79 (2026-09-17) — A PAIR, NOT A TF. Two boxes on the SAME TF whose bases ended on
// DIFFERENT bars read DIFFERENT EngSL / HuntSL / TP and are typed against DIFFERENT ladder
// THs, so a TF-keyed ask could only ever have one of them answered (the other would fall
// to `0` — the absence — and be sized by its own height). The anchor is the box' own
// `storyT`, the bar its story ended on, and it is the SAME value `BaseKnotNodeRead` is
// handed, so the ask and the read cannot key different rows. `storyT <= 0` (the base has
// not formed yet) asks the LIVE row, which is the row the sizing preview itself reads.
int BaseKnotEngNeeds(int &mins[], datetime &anchors[])
{
   int chartTF = Period();
   if(chartTF <= 0) chartTF = 1;
   int n = 0;
   mins[n] = chartTF; anchors[n] = 0; n++;     // the live sizing preview's own risk (P-BK-79: the LIVE row)
   for(int i = 0; i < ArraySize(g_bkBoxes); i++)
   {
      int tf = g_bkBoxes[i].baseTFMin;
      if(tf <= 0) tf = chartTF;                // no class published yet — the chart's own
      datetime an = (g_bkBoxes[i].storyT > 0 ? g_bkBoxes[i].storyT : 0);   // P-BK-79: the bar the story ended on
      // P-BK-78: AND THE TWO RUNGS ABOVE THE CLASS. The type compares the box' height
      // against the TH of the node's own TIME, of the PATTERN time (one rung above) and of
      // the STRUCTURE time (two rungs above), so a box whose class sits at the ladder's foot
      // would otherwise have no row to be typed against and would answer BK_NODE_NONE for
      // ever. This is the ask side of the SAME rule BaseKnotAbilityGet applies, so the two
      // cannot drift apart. (Before P-BK-78 the slot carried the box' own TF, which stopped
      // naming anything once the type moved onto the class P-BK-77 finds.)
      // P-BK-51/83: the knot's OWN TF is the class (P-BK-46) and it is the ENTRY's own time,
      // while the STOP is read on the TYPE'S own time — the rung its LENGTH matched, at most
      // THREE rungs above the class (OTR) — so ONE box can ask for FOUR TFs. They all go
      // through the same dedup, and every one of them is a rung of the same ladder, so the
      // table can never be asked for more than the eight per anchor.
      int asked[4];
      asked[0] = tf;
      asked[1] = BaseKnotNextTFMin(tf);
      asked[2] = (asked[1] > 0 ? BaseKnotNextTFMin(asked[1]) : 0);
      asked[3] = BaseKnotMeasureTFMin(g_bkBoxes[i].nodeKind, tf);
      for(int a = 0; a < 4; a++)
      {
         if(asked[a] <= 0) continue;
         // P-BK-79: the dedup is on the PAIR. The chart's own live row is (chartTF, 0) and
         // the loop below finds it, so the old `asked[a] == chartTF` shortcut is subsumed —
         // and it HAD to go: a box whose story ended on a bar asks (chartTF, storyT), which
         // is a different row and must survive.
         bool dup = false;
         for(int j = 0; j < n; j++) if(mins[j] == asked[a] && anchors[j] == an) { dup = true; break; }
         if(dup) continue;
         if(n >= BK_ENG_ROW_MAX) break;        // bounded: the rest waits for the next round
         mins[n] = asked[a]; anchors[n] = an; n++;
      }
   }
   return n;
}
// THE PUSH. The table is replaced wholesale and the EPOCH moves only when a stored
// row (TF or value) really differs from the last round — so a warm, unchanged chart
// pays a compare per entry and triggers no rebuild at all, while a new bar's EngSL
// (or a box that just published a class) re-arms the pump's gate. P-BK-50: the SAME
// row now carries the plan's three target legs, so ONE round hands over the risk AND
// the targets, and a leg that MOVED re-arms the gate exactly like a moved EngSL.
void BaseKnotEngPush(const int &mins[], const datetime &anchors[], const double &pips[],
                     const double &hunts[], const double &tp1[], const double &tp2[],
                     const double &tp3[], const int n)
{
   int      tfNew[BK_ENG_ROW_MAX];
   datetime anNew[BK_ENG_ROW_MAX];
   double pNew[BK_ENG_ROW_MAX];
   double hNew[BK_ENG_ROW_MAX];
   double t1New[BK_ENG_ROW_MAX];
   double t2New[BK_ENG_ROW_MAX];
   double t3New[BK_ENG_ROW_MAX];
   ArrayInitialize(tfNew, 0);        // explicit: the compare below reads the whole
   ArrayInitialize(anNew, 0);        // table even when this round pushed nothing
   ArrayInitialize(pNew, 0.0);       // P-BK-51: the Hunter leg, same rule
   ArrayInitialize(hNew, 0.0);
   ArrayInitialize(t1New, 0.0);
   ArrayInitialize(t2New, 0.0);
   ArrayInitialize(t3New, 0.0);
   int m = 0;
   for(int i = 0; i < n && m < BK_ENG_ROW_MAX; i++)
   {
      if(mins[i] <= 0) continue;
      tfNew[m] = mins[i];
      anNew[m] = (anchors[i] > 0 ? anchors[i] : 0);   // P-BK-79: 0 = the live row
      pNew[m]  = (pips[i] > 0.0 ? pips[i] : 0.0);   // <= 0 = not pushed, never a size
      hNew[m]  = (hunts[i] > 0.0 ? hunts[i] : 0.0); // P-BK-51: HuntSL, same absence rule
      t1New[m] = (tp1[i] > 0.0 ? tp1[i] : 0.0);     // P-BK-50: the plan's legs — an
      t2New[m] = (tp2[i] > 0.0 ? tp2[i] : 0.0);     // unpushed leg stays ABSENT
      t3New[m] = (tp3[i] > 0.0 ? tp3[i] : 0.0);
      m++;
   }
   bool moved = (m != s_bkEngN);
   for(int i = 0; !moved && i < m; i++)
      if(tfNew[i] != s_bkEngTF[i] || anNew[i] != s_bkEngAnchor[i] ||
         pNew[i] != s_bkEngPips[i] || hNew[i] != s_bkEngHunt[i] ||
         t1New[i] != s_bkEngTP1[i] || t2New[i] != s_bkEngTP2[i] || t3New[i] != s_bkEngTP3[i]) moved = true;
   for(int i = 0; i < m; i++)
   {
      s_bkEngTF[i] = tfNew[i]; s_bkEngAnchor[i] = anNew[i];
      s_bkEngPips[i] = pNew[i]; s_bkEngHunt[i] = hNew[i];
      s_bkEngTP1[i] = t1New[i]; s_bkEngTP2[i] = t2New[i]; s_bkEngTP3[i] = t3New[i];
   }
   s_bkEngN = m;
   if(moved) s_bkEngEpoch++;
}
// The pushed EngSL of one TF AT ONE ANCHOR, in pips. 0 = the pump has no value for that
// (TF, anchor) pair (never invented); tfMin <= 0 means THIS chart's TF (the sizing
// preview's question), and anchor 0 means the LIVE row (P-BK-79: a box with no story yet
// falls back to it rather than inventing a bar).
double BaseKnotEngPips(const int tfMin, const datetime anchor = 0)
{
   int tf = (tfMin > 0 ? tfMin : Period());
   if(tf <= 0) tf = 1;
   for(int i = 0; i < s_bkEngN; i++)
      if(s_bkEngTF[i] == tf && s_bkEngAnchor[i] == anchor) return s_bkEngPips[i];
   return 0.0;
}
bool BaseKnotRiskIsEng(const int tfMin, const datetime anchor = 0)
{ return (BaseKnotEngPips(tfMin, anchor) > 0.0); }
// P-BK-51 — THE HUNTER LEG, read back the same way: the pushed HuntSL of one TF at one
// anchor in pips, 0 = the pump has no value for it (never invented). It is what an
// ETR/CTR/OTR node's ENTRY waits for («به اندازه huntsl محل ورود»), while every stop stays
// ONE EngSL long.
double BaseKnotHuntPips(const int tfMin, const datetime anchor = 0)
{
   int tf = (tfMin > 0 ? tfMin : Period());
   if(tf <= 0) tf = 1;
   for(int i = 0; i < s_bkEngN; i++)
      if(s_bkEngTF[i] == tf && s_bkEngAnchor[i] == anchor) return s_bkEngHunt[i];
   return 0.0;
}
// P-BK-50 — THE PLAN'S OWN TARGET LEGS, per TF and anchor, exactly as the pump pushed
// them: TP1..TP3 in pips counted FROM THE ENTRY, which is how the label's `#TPn+` row
// counts them (the plan's legs are entry-relative by construction — the `#` field
// of that row is entry-to-level, and the stop is one of those legs). 0 = the pump
// has no value for that leg: an ABSENCE, never a guess.
double BaseKnotPlanTPPips(const int tfMin, const int k, const datetime anchor = 0)
{
   if(k < 1 || k > BK_TP_PLAN_MAX) return 0.0;
   int tf = (tfMin > 0 ? tfMin : Period());
   if(tf <= 0) tf = 1;
   for(int i = 0; i < s_bkEngN; i++)
      if(s_bkEngTF[i] == tf && s_bkEngAnchor[i] == anchor)
         return (k == 1 ? s_bkEngTP1[i] : (k == 2 ? s_bkEngTP2[i] : s_bkEngTP3[i]));
   return 0.0;
}
bool BaseKnotPlanWarm(const int tfMin, const datetime anchor = 0)
{ return (BaseKnotPlanTPPips(tfMin, 1, anchor) > 0.0); }
// HOW MANY plan legs a box draws. This IS the old `TARGET R` state (`g_bkTargetR` —
// same chart GV key `BXR`, same FF_ address, so a saved chart keeps its number), and
// P-BK-50 gave the same number a job that is still true: the row reads `TP COUNT`
// (1..3), and the old maximum 4 clamps into it instead of losing the setting.
int BaseKnotTPCount()
{
   int n = g_bkTargetR;
   if(n < 1) n = 1;
   if(n > BK_TP_PLAN_MAX) n = BK_TP_PLAN_MAX;
   return n;
}
// ONE plan target's LEVEL: the plan's pip leg of the knot's TF, measured from the
// ENTRY line — the line the user sees is the entry, so the target is where THAT
// line's own plan puts it. 0 = no level (leg absent, or no entry yet).
double BaseKnotTPLevel(const double entry, const int dir, const int tfMin, const int k,
                       const datetime anchor = 0)
{
   double p = BaseKnotPlanTPPips(tfMin, k, anchor);
   if(p <= 0.0 || entry <= 0.0) return 0.0;
   return (dir >= 0 ? entry + p * BaseKnotPipSize() : entry - p * BaseKnotPipSize());
}
// BKTAGTP-OFF (P-BK-54): THE NOTE'S TARGET FIELD IS RETIRED IN PLACE. The user: «تی پی رو
// … در اطلاعات نشون نده» — the note is read at a glance, the targets are drawn as ticks
// (P-BK-50) and spelled leg by leg in the hover (BaseKnotTPPlanTip, still live), so the
// field was three numbers between the risk and the bar count and nothing else. Restore by
// feeding this tag back into BaseKnotWriteInfo's text (the marked site in the note).
// P-BK-50 — the note's own field: the plan's targets in pips, as drawn. A plan that
// is not warm SAYS SO instead of printing a number nobody can check.
string BaseKnotTPPlanTag(const int tfMin, const datetime anchor = 0)
{
   int n = BaseKnotTPCount();
   string s = "";
   for(int k = 1; k <= n; k++)
   {
      double p = BaseKnotPlanTPPips(tfMin, k, anchor);
      if(p <= 0.0) continue;
      s += (StringLen(s) == 0 ? "" : "/") + DoubleToString(p, 0);
   }
   if(StringLen(s) == 0) return " | TP plan not warm yet";
   return " | TP " + s;
}
// ... and the hover's version: every drawn leg with its LEVEL and its pips from the
// entry, plus what those pips are in R (the box' stop is 1 R), so the tick on the
// chart can be checked against the plan row in the corner.
string BaseKnotTPPlanTip(const int tfMin, const double entry, const int dir, const double rPips,
                         const datetime anchor = 0)
{
   int n = BaseKnotTPCount();
   int dg = GetCachedDigits();
   string t = "";
   for(int k = 1; k <= n; k++)
   {
      double p = BaseKnotPlanTPPips(tfMin, k, anchor);
      double lv = BaseKnotTPLevel(entry, dir, tfMin, k, anchor);
      if(p <= 0.0 || lv <= 0.0) continue;
      // P-BK-50: BOTH readings are spelled out — pips from the ENTRY (how the plan row
      // counts them) and pips from the STOP line plus the R multiple that implies, so a
      // reader can check the tick against whichever of the two he has in mind.
      t += "\n     TP" + IntegerToString(k) + " " + DoubleToString(lv, dg) + " (+" +
           DoubleToString(p, 0) + " pips from the entry" +
           (rPips > 0.0 ? " = " + DoubleToString(p + rPips, 0) + " from the stop, " +
                          DoubleToString(p / rPips, 1) + "R" : "") + ")";
   }
   if(StringLen(t) == 0)
      t = "\n     the plan's targets are not warm yet (nothing pushed for " + BaseKnotTFName(tfMin) + ")";
   return t;
}
// BKE2-OFF: 2nd entry retired — "" (set 1 already says warm/not-warm).
string BaseKnotTPPlanTip2(const int tfMin, const double entry2, const int dir, const double rPips,
                          const datetime anchor = 0)
{
   return "";
}
// P-BK-46 — R: THE PIPS EVERY LEG OF THE KNOT'S TRADE IS MEASURED IN. THE PLAN's EngSL of
// the knot's measure TF, BOUNDED by the node's own power (P-BK-52 — the plan's leg while it
// is no deeper than the node, the node's own EngSL when it is: the TH cold case, a rung the
// terminal never loaded, a node smaller than the leg); the box' own height only when NEITHER
// answered. Never <= 0 for a real box, the SAME BaseKnotLegPick rule the geometry is drawn
// with (one owner), and the caller ALWAYS shows which of the three it got
// (BaseKnotRiskTag / BaseKnotStopWhy).
double BaseKnotRiskPips(const int tfMin, const double top, const double bot, const datetime anchor = 0)
{
   double p = BaseKnotLegPick(BaseKnotEngPips(tfMin, anchor), BaseKnotNodeEngPips(top, bot));
   if(p > 0.0) return p;
   return BaseKnotToPips(top - bot);
}
// How the risk is NAMED wherever it is shown — the badge's number and every stop /
// target tooltip: a size without its source is a number nobody can check.
// P-BK-52: the name is decided by the SAME rule the number was picked with, over the SAME
// pair, so a hover can never describe another measurement than the line it sits on.
// P-BK-53: and the name itself is the SHORT one (BaseKnotCapTag) — this is the string that
// reaches the chart-side note, so it says WHICH source spoke and nothing more.
// P-BK-57: the name the LAST rung wears (neither leg answered) has ONE owner here, because
// the note's own height field tests itself against it (see BaseKnotHeightTag): a renamed
// fallback could otherwise print the box' height twice in the same line.
string BaseKnotBoxHeightTag() { return "box height"; }
string BaseKnotRiskTag(const int measureTF, const int baseTF, const double top, const double bot,
                       const datetime anchor = 0)
{
   double plan = BaseKnotEngPips(measureTF, anchor);
   double cap  = BaseKnotNodeEngPips(top, bot);
   if(BaseKnotLegCapped(plan, cap)) return BaseKnotCapTag(false);
   if(plan > 0.0)
   {
      // P-BK-51: a CTR/OTR knot's numbers are read ONE TF HIGHER than its own class, and a
      // size without its source is a number nobody can check — so the reading TF rides
      // beside the name whenever it is not the class the note already prints.
      if(measureTF > 0 && baseTF > 0 && measureTF != baseTF)
         return "EngSL " + BaseKnotTFName(measureTF);
      return "EngSL";
   }
   return BaseKnotBoxHeightTag();
}
// P-BK-57 (2026-09-16, user: «مقدار حرکت رو هم به صورت عدد فقط نمایش بده بفهمیم چقدره»):
// THE NOTE'S SECOND NUMBER IS THE BOX' OWN HEIGHT IN PIPS, AND IT IS BARE. WHY: the risk
// says how big the STOP is, and the note never said how big the BOX is — the one size the
// whole box is read against (the step multiples, the candle count, the class). The user
// asked for the number on its own («به صورت عدد فقط»), so there is no name and no unit
// word on the chart face (P-BK-54's own rule); the HOVER names it, its arithmetic and its
// reading, so P-BK-46's promise (a size without its source is a number nobody can check)
// is kept where there is room for it.
// ONE OWNER: the number is `BaseKnotToPips(top - bot)` — the very expression the risk falls
// back to (BaseKnotRiskPips), so "the box' height" means ONE thing in this module.
// WRITTEN ONCE: when that fallback IS the risk (neither the plan nor the node's own leg
// answered) the first number already carries the height, so this field stays EMPTY and the
// note never prints the same size twice; the test is on the SOURCE (BaseKnotBoxHeightTag),
// never on the two values happening to be equal.
// THE GATE: tools/base-count-audit.py [note height] reads this body AND the note's own text
// expression — a name or unit word in the field, a second copy beside the fallback risk, or
// a box height that stopped coming from BaseKnotToPips fails the build.
string BaseKnotHeightTag(const double top, const double bot, const string riskTag)
{
   if(riskTag == BaseKnotBoxHeightTag()) return "";   // the risk already IS this height
   double p = BaseKnotToPips(top - bot);
   if(p <= 0.0) return "";                            // no box, no number
   return " | " + DoubleToString(p, 1);
}
// ... and the HOVER's own version of the SAME number — the split P-BK-53 made for the risk
// name (the chart face gets the NAME, the hover gets the proof), here for the box' size: one
// line that names it, spells the arithmetic (`top - bottom`) and gives its pips, so P-BK-46's
// promise is kept where there is room for it. The SAME test the field uses (`BaseKnotBoxHeightTag`)
// decides the wording, so a reader is never told to look for a second number the note did not
// print — the number itself and the test both stay owned here, and no caller spells either.
string BaseKnotHeightTip(const double top, const double bot, const string riskTag)
{
   double p = BaseKnotToPips(top - bot);
   if(p <= 0.0) return "";
   return "\n     box height (top - bottom) = " + DoubleToString(p, 1) + " pips - " +
          (riskTag == BaseKnotBoxHeightTag()
           ? "and it IS the risk above: the note prints it once"
           : "the note's own second number, in pips");
}
#endif // BASE_KNOT_NODES_MQH
