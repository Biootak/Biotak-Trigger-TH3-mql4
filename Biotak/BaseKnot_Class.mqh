//+------------------------------------------------------------------+
//| BaseKnot_Class.mqh                                               |
//| P-BK-142 — THE KNOT'S TIME: THE LADDER, THE COUNT, THE RUNG.      |
//|                                                                  |
//| SPLIT OUT OF BaseKnot_Nodes.mqh on 2026-11-01 (P-SIZE-1500,      |
//| contract §7). The snap P-BK-142 added pushed Nodes to 1530 lines, |
//| so the block the file already owned as ONE thing — the ladder's   |
//| walk, the base's own count, and the three spellings of the same   |
//| answer (read / memo / tag / line) — moved here whole, byte for    |
//| byte. Nothing moved changed meaning: same names, same order, same |
//| output; the reader still receives the class of a box, not a new     |
//| number. INCLUDE ORDER is BaseKnot_Nodes.mqh FIRST (this file asks   |
//| it for BaseKnotNextTFMin, BK_KNOT_TF_MAX, BK_BASE_RUNG_MIN and     |
//| BaseKnotRungHoldCount).                                          |
//+------------------------------------------------------------------+
#ifndef BASE_KNOT_CLASS_MQH
#define BASE_KNOT_CLASS_MQH

#property strict

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
//
// P-BK-126d (2026-10-27) — AND THE CLASS WALKS NOTHING. The user, after two builds of a grid
// that kept moving the answer: «به ساعت نباید ربط داشته باشه دیگه سه کندل ملاک هستش ... کندل
// ورود به باکس و کندل خروج از باکس میشه و بین کندل ورود و خروج سه کندل باشه» — then «همون کار
// که تعداد کندل مشخص میکنه درست هستش دیگه از همون استفاده بکن که ببین کجا سه کندل داریم». So
// the three paragraphs above are the HISTORY of a walk the class no longer performs: the time
// is the base's own entry..exit count over three (`BaseKnotBaseTFRead`), which is one number
// per band and has no grid to phase. `BaseKnotLadderAll` stays because the note's own sentences
// (`BaseKnot_Note.mqh`) still name a rung, and `BaseKnotStillCount` stays as the hover's count.
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
                       const double top, const double bot, const int tf = 0)
{
   if(bars <= 0) return 0;
   if(bars < BK_BASE_MIN_BARS) return -1;
   // P-BK-80: NO CHART TERM, EVER. The chart TF used to add its own candle width here
   // (`+ chartMin`) and to supply the span's two ends; both are gone, so `3 * rung <= spanMin`
   // answers the same on M1 and on MN1.
   // P-BK-112 (2026-10-21, user: «این گره زده مال چهار ساعته در صورتی که گره در تایم یک ساعته
   // دیده میشه») — THE CLASS' SPAN IS THE BASE'S OWN CANDLES IN MARKET TIME, NEVER CALENDAR
   // MINUTES. MEASURED on the live XAUUSD box 18..21 Sep 2026: its own life is 7 H1 candles,
   // yet the face read «7 bars · H4 base · FTR». The span was `(b2 - b1) / 60` over the base's
   // entry..exit unioned with the drawn box, and that run crossed the Fri->Mon close: 7
   // candles of Friday evening plus Monday morning are ~55 wall-clock hours, so 3 x H4 = 720
   // minutes "fit" a gap in which only 7 H1 candles exist. A closed market has no candles, so
   // it may add no minutes. `bars` IS the base's own length (BaseKnotBarCount's `still`,
   // P-BK-40/84) and `tf` is the box' commit TF that run was counted on, so `bars * tf` is its
   // market span — chart-free (P-BK-80) and candle-true (the user's 3-candles-per-rung rule).
   // The drawn box is no longer a term at all: P-BK-84's floor only ever WIDENED the read, and
   // a box wider than its base is how the H4 label replaced an H1 one.
   int tfMin = (tf > 0 ? tf : Period());
   if(tfMin < 1) tfMin = 1;
   int spanMin = bars * tfMin;
   // P-BK-126d (2026-10-27) — THE BASE'S OWN CANDLE COUNT IS THE MEASURE, AND THERE IS NO GRID.
   // The user: «به ساعت نباید ربط داشته باشه دیگه سه کندل ملاک هستش ... کندل ورود به باکس و کندل
   // خروج از باکس میشه و بین کندل ورود و خروج سه کندل باشه» and then «همون کار که تعداد کندل
   // مشخص میکنه درست هستش دیگه از همون استفاده بکن که ببین کجا سه کندل داریم».
   // So the ENTRY..EXIT run IS the knot (`bars` is BaseKnotBarCount's `still`, P-BK-40/42/44), and
   // ONE candle of the knot's time is that run's own span OVER THREE. Both earlier reads put a
   // bucket grid on top of this exact count — P-BK-126 cut the buckets back from the box' edge,
   // P-BK-126c cut them on the clock — and every grid is a SECOND ruler that can only disagree
   // with the count it was handed. MEASURED (XAUUSD M1, band 3999.52..4012.14, tMax 31, eleven
   // closes): the edge grid answered 26..31m and the clock grid 30m for the SAME band, while the
   // count answers one number. Live: `15_22269312` twice 4 s apart (17:05:52 / 17:05:56, v4, one
   // geometry) read 20m both; the 17:06:02 press read 11m because the BOX had moved (120.4 ->
   // 113.1 pips) — the band is the user's own input and the only thing allowed to move it.
   // `bars >= BK_BASE_MIN_BARS` and `tfMin >= 1` above, so this is always >= 1 — never a 0 dressed
   // up as an answer.
   int nodeTF = spanMin / 3;                     // «بین ورود و خروج سه کندل» — three candles
   // P-BK-142 (2026-11-01) — AND THAT NUMBER IS A LADDER RUNG, NEVER `spanMin / 3` ITSELF.
   // The user, with three screenshots of ONE box (EURUSD M15, 24 pips, band 1.11331..1.11575):
   // «این گره الان یک ساعته خورده … الان که جابجا کردم زده 5 ساعته … باید در هر حالت همون نشون
   // بده … نمیشه روی اعدادش اطمینان کرد برای ترید» — `2h base` / `1h10m base` / `H1 base` for the
   // SAME range, and the whole trade card (`TRex 3.6|9.6|18|43` / `2.7|7.2|14|33` / `5.5|14.5|27|65`)
   // moved with it, because the entry, the stop and every TP are read on the knot's own time
   // (BaseKnotEntryTFMin / BaseKnotMeasureTFMin / the plan's TP1..TP4).
   // THE CAUSE IS THE ARITHMETIC, NOT THE COUNT: `spanMin / 3` is a CONTINUOUS function of an
   // integer count, so ONE more in-band candle walks the answer by `tfMin / 3` — 5 minutes on M15,
   // and an off-ladder time (70, 105, 215 ...) names no candles at all, so the node TYPE reads
   // `hop=-1 type=` and the card has no legs to draw. MEASURED (the same box, jitter of +/-2 candles
   // per edge and +/-0.5 pip per band side, 1 650 states, replayed on the terminal's own
   // EURUSD15.hst): `spanMin / 3` answered 41 DISTINCT knot times (15m, 20m, 25m, 55m, 60m, 65m,
   // 70m, 95m, 100m, 105m, 110m, 120m, 185m, 205m, 210m, 215m, 220m, 225m, 255m ...); the rung
   // below answers 8. The three reported frames read `24 bars -> 120m`, `14 -> 70m`, `12 -> 60m`;
   // they now read H1, H1, H1 — the user's own rule («تایم گره سه کندل درجا زدن») on a time that
   // HAS three candles, instead of a 2h20m clock nobody can chart.
   // SO: the largest rung whose THREE candles still fit inside the base's own span — `3 * rung
   // <= bars * tf`, i.e. `rung <= spanMin / 3`, walked on the ladder's ONE owner (BaseKnotNextTFMin,
   // P-BK-82). It is not a second ruler over the count (P-BK-126d's law holds — the count still
   // decides, nothing is re-counted and no bucket grid returns): it is the ROUNDING of that one
   // answer onto the eight times this project trades, and it can only round DOWN, so every named
   // rung still fits the base three times.
   int rung = 0;
   for(int i = 0; i < 9; i++)
   {
      int up = BaseKnotNextTFMin(rung);
      if(up <= 0 || up > BK_KNOT_TF_MAX) break;   // the ladder's top / the class' own cap (D1)
      if(3 * up > spanMin) break;                 // this rung's three candles no longer fit
      rung = up;
   }
   if(rung > 0) nodeTF = rung;                    // M1 always fits (bars >= 3, tfMin >= 1)
   if(nodeTF > BK_KNOT_TF_MAX) nodeTF = BK_KNOT_TF_MAX;
   return nodeTF;
}
// The memo (P-BK-36): the answer is closed-bar data, so it can only change when the
// QUESTION changes — the box' two anchors, its band, the count it was computed from, or a
// new closed bar. P-BK-80: the chart TF is NO LONGER part of the key, because it is no
// longer part of the question — that is the whole promise, and a key that carried it could
// only ever hand the same box two different answers on two charts.
static int      s_bkRungTF     = 0;   // the series the span was read on (the box' commit TF)
static int      s_bkRungBars   = -1;
static datetime s_bkRungB1     = 0;   // P-BK-80: the BOX' left anchor
static datetime s_bkRungB2     = 0;   // ... and its right anchor (never the story's ends)
static double   s_bkRungTop    = 0.0;
static double   s_bkRungBot    = 0.0;
static datetime s_bkRungBar    = 0;
static int      s_bkRungAnswer = 0;
// P-BK-80: the question is the BOX' OWN geometry and the count it was computed from — no
// chart TF, no chart candle width. P-BK-112: `bars` (the base's own still count) is now the
// measurement and `tf` (the box' commit TF) is its unit; the two anchors stay in the key
// because a new run can start on the same count, and the band is part of the run's identity.
int BaseKnotBaseTFMin(const int bars, const datetime b1, const datetime b2,
                      const double top, const double bot, const int tf = 0)
{
   datetime lastClosed = iTime(_Symbol, tf, 1);
   if(tf == s_bkRungTF && bars == s_bkRungBars && b1 == s_bkRungB1 && b2 == s_bkRungB2 &&
      top == s_bkRungTop && bot == s_bkRungBot &&
      lastClosed == s_bkRungBar)
      return s_bkRungAnswer;
   int answer = BaseKnotBaseTFRead(bars, b1, b2, top, bot, tf);
   s_bkRungTF = tf; s_bkRungBars = bars; s_bkRungB1 = b1; s_bkRungB2 = b2;
   s_bkRungTop = top; s_bkRungBot = bot;
   s_bkRungBar = lastClosed; s_bkRungAnswer = answer;
   return answer;
}
// Compact note suffix: " · M15 base" / " · H1 base" / " · struct" / "".
// P-BK-112: `bars` (the base's own still count) and `readTF` (the box' commit TF) own the
// class; `b1..b2` are the display span the hover reports its stand-still count on.
string BaseKnotBaseTag(const int bars, const datetime b1, const datetime b2,
                       const double top, const double bot, const int readTF = 0, const int baseTF = 0)
{
   if(bars <= 0) return "";
   if(bars < BK_BASE_MIN_BARS) return " · struct";
   int tf = (baseTF > 0 ? baseTF : BaseKnotBaseTFMin(bars, b1, b2, top, bot, readTF));
   if(tf == 0) return "";   // unmeasurable — the bars part is omitted too
   if(tf <  0) return " · struct";
   return " · " + BaseKnotTFHuman(tf) + " base";   // P-BK-129: the face says the clock (11h40m), never 700m
}
// The same read spelled out for the hover line (the note's full sentence).
string BaseKnotBaseLine(const int bars, const datetime b1, const datetime b2,
                        const double top, const double bot, const int readTF = 0, const int baseTF = 0)
{
   if(bars <= 0) return "\nBase: size not measurable yet";
   if(bars < BK_BASE_MIN_BARS) return "\nBase: " + IntegerToString(bars) +
                      " bars -> structure (a base needs " + IntegerToString(BK_BASE_MIN_BARS) + " candles inside)";
   int tf = (baseTF > 0 ? baseTF : BaseKnotBaseTFMin(bars, b1, b2, top, bot, readTF));
   if(tf == 0) return "\nBase: size not measurable yet";
   if(tf <  0) return "\nBase: " + IntegerToString(bars) +
                      " bars -> structure (a base needs " + IntegerToString(BK_BASE_MIN_BARS) + " candles inside)";
   // P-BK-84: THE LENGTH IS THE CRITERION, and the stand-still count is REPORTED beside it —
   // it no longer decides anything (BKHOLD-OFF). P-BK-112: and the length is the base's own
   // candles in MARKET time (`bars × commitTF`), so a weekend gap cannot buy a rung.
   int tfMin = (baseTF > 0 ? baseTF : (readTF > 0 ? readTF : Period()));
   if(tfMin < 1) tfMin = 1;
   int spanMin = bars * tfMin;
   if(3 * tf > spanMin)   // a count under a base's length (unreachable for bars >= 3)
      return "\nBase: " + IntegerToString(bars) + " bars -> " + BaseKnotTFHuman(tf) +
             " base (no rung's " + IntegerToString(BK_BASE_RUNG_MIN) + " candles fit the base's own candles — the span's own rung)";
   int held = BaseKnotRungHoldCount(tf, b1, b2, top, bot);   // P-BK-84: REPORTED, never a decider
   return "\nBase: " + IntegerToString(bars) + " bars -> " + BaseKnotTFHuman(tf) +
          " base (" + IntegerToString(BK_BASE_RUNG_MIN) + " candles of " + BaseKnotTFHuman(tf) +
          " fit the base's own candles" +
          (held > 0 ? "; " + IntegerToString(held) + " of them stood still in the band" : "") + ")";
}
#endif // BASE_KNOT_CLASS_MQH
