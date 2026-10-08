//| P-TH-VOLNORM (2026-10-08, user: TH شارپ/کم‌نوسان به ATR نزدیک     |
//| نیست، بدون ATR، فقط از خود قیمت).                                |
//|                                                                  |
//| THE GAP. `CalculateTH` is `price * pct / 100`                      |
//| (THCalculations.mqh:80) with a FIXED pct per rung                 |
//| (ConstantsAndEnums.mqh:322). So `TH / price` is one number for    |
//| every symbol on a timeframe, while `ATR / price` is one number    |
//| PER symbol. A sharp pair and a calm pair can never share the      |
//| same fixed pct and both sit near their own ATR.                   |
//|                                                                  |
//| THE FIX, FROM THE PRICE ALONE. For small moves                    |
//| `MathLog(H / L)` is `(H - L) / price`, so                        |
//| `RV = mean(log(H/L))` over a rung's own bars IS the market's own  |
//| relative range — the same family as ATR, read from H/L/C only.   |
//| The gap leg (previous close) counts exactly like ATR counts it.  |
//| No `iATR` call anywhere in this file.                            |
//| `V = RV / (pct / 100)` per column; the professor's table itself   |
//| is the anchor, so no second constant is introduced. OFF returns   |
//| exactly 1.0 BEFORE any series read: zero reads, zero writes,     |
//| byte-identical numbers.                                          |
//|                                                                  |
//| P-TH-VOLNORM-COL (user: «تایم فریم که عوض میکنم اعداد TH خیلی     |
//| باهم فرق میکنه»). V was read from the CHART's timeframe, so one  |
//| block wore two lenses. Now each column wears ITS OWN rung TF,    |
//| and the block reads no chart TF at all. A rung's true span       |
//| (1/4/16/64/256/1024/4096/16384/65536 min) has no MT4 history     |
//| except M1, so each rung maps to its NEAREST standard TF in       |
//| log-time (table below IS that mapping: one owner).               |
//|                                                                  |
//| WHY NOT TICKS (measured 2026-10-08, then reverted). A tick EMA    |
//| estimates close-to-close sigma; TH/ATR compare HIGH-LOW ranges,  |
//| which run ~2x above it (plus tick noise). Live gold printed      |
//| V=0.76 where bars read 2.2 — further FROM ATR, not closer. The   |
//| bar path below measured within 2% on intraday TFs, so it stays.  |
//|                                                                  |
//| SCOPE. TH label columns + the TH/SS-LS drawn steps (drawn steps    |
//| through the block-adopted DrawnV: plates move at most 2x/hour, on  |
//| the base price's own clock; labels wear the live column). Factor/ |
//| own basis and are untouched. The drawn levels ladder is rebuilt   |
//| only when V moves half a percent (frame-cache key below).         |
//|                                                                  |
//| STABILITY (the mean shook: one spike moved the ladder). Three     |
//| steadies, all inside this file: TRIM drops the top 10% of ranges  |
//| per recompute, GEARS mesh each column with its bigger and smaller|
//| neighbour (weighted median, log-time weights), QUANT answers V   |
//| on a 0.05 grid, NEEDLE bends                                     |
//| the base 0.35 toward the last 10 bars (fast/slow split: the base  |
//| holds the regime, the needle shows the moment, both dimensionless |
//| so forex, gold and indices wear the same math). The pure core     |
//| (VFromMean) is untouched: the harness pins it exactly.            |
//|                                                                  |
//| DEPENDENCY-FREE by construction: no settings, no UI, no cache    |
//| module — harnesses include this file alone. Callers pass         |
//| `enabled` in (they read `inpTHVolNorm` themselves).              |
//+------------------------------------------------------------------+
#ifndef TH_VOLNORM_MQH
#define TH_VOLNORM_MQH

#property strict

#define THVOLNORM_LOOKBACK 100   // bars read per recompute (bounded walk)
#define THVOLNORM_LOOKBACK_BIG 14 // weekly+: long bars drift across regimes, so the
                                 // window reads 14 like ATR itself (gold MN: 100-bar
                                 // mean mixes 8 years, 14-bar tracks the rally)
#define THVOLNORM_BIG_TF 10080   // W1 and above use the short window
#define THVOLNORM_MIN_BARS 10    // fewer = absence: answer 1.0, never a guess
#define THVOLNORM_VMIN     0.20  // clamp: a dead chart must not flatten the ladder
#define THVOLNORM_VMAX     5.00  // clamp: a news spike must not blow it out
#define THVOLNORM_COLS     20    // per-(TF,pct) cache slots: 9 fractal rungs +
                                 // 8 standard columns = 17 pairs max (rungs 6+7
                                 // share W1 with different pcts — one slot per
                                 // TF thrashed them into alternating answers)
#define THVOLNORM_QUANT    0.05  // output grid: V moves in 5c steps, not dust
#define THVOLNORM_CONSENSUS 0.30 // gear pull toward the weighted median
#define THVOLNORM_TRIM     10    // top percentiles dropped per recompute
#define THVOLNORM_FAST     10    // needle window: the moment, in bars
#define THVOLNORM_FAST_MIN  5    // fewer = no needle: the base stands alone
#define THVOLNORM_NEEDLE  0.35   // needle weight: base owns 0.65, moment bends 0.35
#define THVOLNORM_BLOCK   1800   // drawn-V clock: 30-min blocks, the SAME clock the
                                 // base price moves on (BLOCK_MINUTES, BasePrice_A.mqh:12
                                 // — mirrored here, not included: Lite has no domain half)
#define THVOLNORM_BLOCK_SPIKE 0.15 // jump cuts the queue: a single step this big
                                   // adopts at once (blocks have thresholds too:
                                   // inpBasePriceThresholdPercent, BasePrice_B.mqh:194)

//+------------------------------------------------------------------+
//| Pure core: V from an already-measured mean log-range.            |
//| `rvMean` dimensionless, `pctRung` in table units (e.g. 0.1666).   |
//| 1.0 = OFF/absence.                                               |
//+------------------------------------------------------------------+
double THVolNormVFromMean(const double rvMean, const double pctRung)
{
   if(!(rvMean > 0.0) || !(pctRung > 0.0)) return 1.0;
   double ref = pctRung / 100.0;
   if(!(ref > 0.0)) return 1.0;
   double v = rvMean / ref;
   if(!MathIsValidNumber(v)) return 1.0;
   if(v < THVOLNORM_VMIN) return THVOLNORM_VMIN;
   if(v > THVOLNORM_VMAX) return THVOLNORM_VMAX;
   return v;
}

//--- last recompute per TF slot, for the change-gated witness below
static string s_tvnKey[THVOLNORM_COLS];
static double s_tvnV[THVOLNORM_COLS];
static double s_tvnRV[THVOLNORM_COLS];
static int    s_tvnN[THVOLNORM_COLS];
static int    s_tvnTF[THVOLNORM_COLS];
static string s_tvnWit[THVOLNORM_COLS];

//--- last read's SLOW (pre-needle) V, TF and bar count: the jump gate and
//--- the cold door below watch the base, which cannot whip — the needle can
//--- (±35% bends on a 10-bar window flip-flop past the 15% gate in
//--- single-column sim: 105 jumps vs 5 block adoptions over 49h of XAUUSD
//--- M1). Set on every ColumnV read (hit or recompute); DrawnV reads it only
//--- when the TF matches its own.
static int    s_tvnLastTF = 0;
static double s_tvnLastSlow = 1.0;
static int    s_tvnLastN = 0;

//+------------------------------------------------------------------+
//| Fractal rung index -> nearest standard TF minutes (table above). |
//| Out of range = -1 (absence: the caller answers 1.0).             |
//+------------------------------------------------------------------+
int THVolNormTFForFractalRung(const int rungIdx)
{
   static int s_map[9] = {1, 5, 15, 60, 240, 1440, 10080, 10080, 43200};
   if(rungIdx < 0 || rungIdx > 8) return -1;
   return s_map[rungIdx];
}

//+------------------------------------------------------------------+
//| Output grid: V is answered on a 5c lattice (1.0 exact stays).    |
//| Pure: the harness pins it without a chart.                       |
//+------------------------------------------------------------------+
double THVolNormQuantize(const double v)
{
   if(v == 1.0) return 1.0;
   if(!(v > 0.0)) return 1.0;
   double q = MathFloor(v / THVOLNORM_QUANT + 0.5) * THVOLNORM_QUANT;
   if(q < THVOLNORM_VMIN) return THVOLNORM_VMIN;
   if(q > THVOLNORM_VMAX) return THVOLNORM_VMAX;
   return q;
}

//+------------------------------------------------------------------+
//| Gear weight (pure): 1.0 at home, heavy for neighbours, a whisper |
//| for distant rungs. Log-time distance: M1-M5 ~0.38, M1-MN1 ~0.09. |
//| Pure: the harness pins it without a chart.                       |
//+------------------------------------------------------------------+
double THVolNormGearW(const int tfA, const int tfB)
{
   if(tfA <= 0 || tfB <= 0) return 0.0;
   double hi = (tfA > tfB) ? (double)tfA : (double)tfB;
   double lo = (tfA > tfB) ? (double)tfB : (double)tfA;
   return 1.0 / (1.0 + MathLog(hi / lo));
}

//+------------------------------------------------------------------+
//| Gear vote: weighted median of the live columns pulls one column.  |
//| Each rung meshes with its bigger and smaller neighbour like      |
//| clockwork; distant rungs only whisper. Only measured slots vote  |
//| (s_tvnN > 0): absence is silent, calm 1.0s count. The column's   |
//| own slot is skipped (it votes fresh below, weight 1.0). Alone    |
//| (fewer than 2 votes) the column stands as read.                  |
//+------------------------------------------------------------------+
double THVolNormConsensus(const double rawV, const int tfMinutes, const int skipSlot)
{
   double vv[];
   double ww[];
   ArrayResize(vv, THVOLNORM_COLS + 1);
   ArrayResize(ww, THVOLNORM_COLS + 1);
   int m = 0;
   for(int s = 0; s < THVOLNORM_COLS; s++)
   {
      if(s == skipSlot) continue;
      if(StringLen(s_tvnKey[s]) == 0 || s_tvnN[s] <= 0) continue;
      if(!(s_tvnV[s] > 0.0) || s_tvnTF[s] <= 0) continue;
      vv[m] = s_tvnV[s];
      ww[m] = THVolNormGearW(tfMinutes, s_tvnTF[s]);
      m++;
   }
   vv[m] = rawV;
   ww[m] = 1.0;
   m++;
   if(m < 2) return rawV;
   int i, j;
   for(i = 1; i < m; i++)   // insertion sort by value, weights follow (m <= 13)
   {
      double tv = vv[i];
      double tw = ww[i];
      j = i - 1;
      while(j >= 0 && vv[j] > tv) { vv[j + 1] = vv[j]; ww[j + 1] = ww[j]; j--; }
      vv[j + 1] = tv;
      ww[j + 1] = tw;
   }
   double total = 0.0;
   for(int k = 0; k < m; k++) total += ww[k];
   double med = vv[m - 1];
   double acc = 0.0;
   for(int k2 = 0; k2 < m; k2++)
   {
      acc += ww[k2];
      if(acc >= total / 2.0) { med = vv[k2]; break; }
   }
   return rawV * (1.0 - THVOLNORM_CONSENSUS) + med * THVOLNORM_CONSENSUS;
}

//+------------------------------------------------------------------+
//| Needle mix (pure): base owns 0.65, the moment bends 0.35. Dead   |
//| leg (-1/0) leaves the other standing: sideways keeps the base,  |
//| a spike bends it the same bar, the regime takes over after.      |
//+------------------------------------------------------------------+
double THVolNormBlend(const double slowV, const double fastV)
{
   if(!(slowV > 0.0)) return fastV;
   if(!(fastV > 0.0)) return slowV;
   return slowV * (1.0 - THVOLNORM_NEEDLE) + fastV * THVOLNORM_NEEDLE;
}

//+------------------------------------------------------------------+
//| Needle mean: plain mean log-range over the last FAST bars. No    |
//| trim here (the window IS the moment: trimming it would blunt it) |
//| and no cache of its own: it is read only when the base above     |
//| recomputes, so a still frame still costs nothing. -1 = absence.  |
//+------------------------------------------------------------------+
double THVolNormFastMean(const int tfMinutes)
{
   if(tfMinutes <= 0) return -1.0;
   if(iTime(NULL, tfMinutes, 0) <= 0) return -1.0;
   int avail = iBars(NULL, tfMinutes);
   int want = THVOLNORM_FAST;
   if(avail < want) want = avail;
   if(want > avail - 1) want = avail - 1;   // gap leg reads i+1
   if(want < THVOLNORM_FAST_MIN) return -1.0;
   double sum = 0.0;
   int k = 0;
   for(int i = 0; i < want; i++)
   {
      double h = iHigh(NULL, tfMinutes, i);
      double l = iLow(NULL, tfMinutes, i);
      double c = iClose(NULL, tfMinutes, i + 1);
      if(!(h > 0.0) || !(l > 0.0) || !(c > 0.0)) continue;
      double hh = (h > c) ? h : c;
      double ll = (l < c) ? l : c;
      sum += MathLog(hh / ll);
      k++;
   }
   if(k < THVOLNORM_FAST_MIN) return -1.0;
   return sum / (double)k;
}

//+------------------------------------------------------------------+
//| ONE column's V: the traded range of ITS OWN rung timeframe over   |
//| the professor's own pct for that rung. Cached per (TF, TF-bar-0, |
//| pct): a still frame costs scalar compares only. OFF short-       |
//| circuits before any series read.                                 |
//+------------------------------------------------------------------+
double THVolNormColumnV(const bool enabled, const int tfMinutes, const double pctRung)
{
   if(!enabled) return 1.0;
   if(tfMinutes <= 0 || !(pctRung > 0.0)) return 1.0;

    int slot = -1;
    int freeSlot = -1;
    // Pair tag: rungs 6+7 share W1 with DIFFERENT pcts — a TF-only tag made
    // them thrash one slot (log: same rv, v 1.75/3.15 alternating forever).
    string tfTag = IntegerToString(tfMinutes) + "|" + DoubleToString(pctRung, 6) + "|";
    for(int s = 0; s < THVOLNORM_COLS; s++)
    {
       string k = s_tvnKey[s];
       if(StringLen(k) == 0) { if(freeSlot < 0) freeSlot = s; continue; }
       if(StringFind(k, tfTag) == 0) { slot = s; break; }
    }
    if(slot < 0) slot = freeSlot;
    if(slot < 0) return 1.0;   // cache full (20 slots, 17 pairs max): absence, never a guess

     datetime bt0 = iTime(NULL, tfMinutes, 0);
     string fullKey = tfTag + TimeToString(bt0);
    if(s_tvnKey[slot] == fullKey)
    {
       // Cache hit: still the column just read — report its warmth too.
       s_tvnLastTF = tfMinutes;
       s_tvnLastSlow = THVolNormVFromMean(s_tvnRV[slot], pctRung);
       s_tvnLastN = s_tvnN[slot];
       return s_tvnV[slot];
    }

    double prevV = s_tvnV[slot];
    bool hadPrev = (StringLen(s_tvnKey[slot]) > 0);
    double v = 1.0;
    double slowRaw = 1.0;
    double rv = 0.0;
    int n = 0;
   int avail = iBars(NULL, tfMinutes);
   int want = (tfMinutes >= THVOLNORM_BIG_TF ? THVOLNORM_LOOKBACK_BIG : THVOLNORM_LOOKBACK);
   if(avail < want) want = avail;
   if(want > avail - 1) want = avail - 1;   // gap leg reads i+1: keep it inside history
    if(want >= THVOLNORM_MIN_BARS && bt0 > 0)
    {
       // Trimmed mean: the top 10% of log-ranges (news spikes) are dropped,
       // the regime is read from the rest. Sorted ascending, head is kept.
       double lrs[];
       ArrayResize(lrs, want);
       int k = 0;
       for(int i = 0; i < want; i++)
       {
          double h = iHigh(NULL, tfMinutes, i);
          double l = iLow(NULL, tfMinutes, i);
          double c = iClose(NULL, tfMinutes, i + 1);   // previous close: the gap leg
          if(!(h > 0.0) || !(l > 0.0) || !(c > 0.0)) continue;
          // Log-space TrueRange: max/min against the previous close, so an
          // overnight/weekend gap counts exactly like ATR counts it.
          double hh = (h > c) ? h : c;
          double ll = (l < c) ? l : c;
          lrs[k] = MathLog(hh / ll);
          k++;
       }
       if(k >= THVOLNORM_MIN_BARS)
       {
          ArrayResize(lrs, k);
          ArraySort(lrs);
          int drop = k * THVOLNORM_TRIM / 100;
          int keep = k - drop;
          if(keep < THVOLNORM_MIN_BARS) { drop = 0; keep = k; }
          double sum = 0.0;
          for(int j = 0; j < keep; j++) sum += lrs[j];
          rv = sum / (double)keep;
          n = keep;
       }
       else
       {
          n = 0;
          rv = 0.0;
       }
       v = THVolNormVFromMean(rv, pctRung);
       slowRaw = v;   // the base, pre-needle: the jump gate's own read
       if(n > 0 && v != 1.0)
       {
          double frv = THVolNormFastMean(tfMinutes);
          if(frv > 0.0)
          {
             double fastV = THVolNormVFromMean(frv, pctRung);
             v = THVolNormBlend(v, fastV);   // needle bends the base, never owns it
          }
          v = THVolNormConsensus(v, tfMinutes, slot);   // gears mesh: neighbours weigh more
          v = THVolNormQuantize(v);    // ...and the grid eats the dust
       }
    }

    s_tvnKey[slot] = fullKey;
    s_tvnV[slot] = v;
    s_tvnRV[slot] = rv;
    s_tvnN[slot] = n;
    s_tvnTF[slot] = tfMinutes;
    s_tvnLastTF = tfMinutes;
    s_tvnLastSlow = (n > 0 ? slowRaw : 1.0);
    s_tvnLastN = n;

   // Change-gated witness (same Print family as the [P-LBL] TH mask probe,
   // Labels_B.mqh:147 — the strip's flushed channel lives in DrawStrip,
   // which Lite does not include, so a shared module must not call it).
   // Prints on a fresh key only when V really moved (>0.5%) or first seen.
   bool moved = (!hadPrev || !(prevV > 0.0) ||
                 MathAbs(v - prevV) / MathMax(prevV, 0.000001) > 0.005);
   string wit = "tf=" + IntegerToString(tfMinutes) +
                " v=" + DoubleToString(v, 4) +
                " rv=" + DoubleToString(rv, 6) +
                " refpct=" + DoubleToString(pctRung, 4) +
                " n=" + IntegerToString(n);
   if(moved && wit != s_tvnWit[slot])
   {
      s_tvnWit[slot] = wit;
      Print("[P-LBL] TH volnorm col ", wit);
   }
   return v;
}

//+------------------------------------------------------------------+
//| Block clock (pure): the 30-min block a time sits in. Server-time |
//| aligned like the base price blocks (00/30). Pure: pinned below.  |
//+------------------------------------------------------------------+
datetime THVolNormBlockStart(const datetime t)
{
   if(t <= 0) return 0;
   return t - (t % THVOLNORM_BLOCK);
}

//+------------------------------------------------------------------+
//| Jump gate (pure): a single step of SPIKE or more cuts the block  |
//| queue. Calm dance (2-7% quanta) waits for the block; a real      |
//| break (news, regime flip) adopts the same tick. Pinned below.    |
//+------------------------------------------------------------------+
bool THVolNormJumpCuts(const double live, const double adopted)
{
   if(!(live > 0.0) || !(adopted > 0.0)) return false;
   if(live == adopted) return false;
   return MathAbs(live - adopted) / adopted >= THVOLNORM_BLOCK_SPIKE;
}

//+------------------------------------------------------------------+
//| Last slow read: the base of the most recent recompute, or -1     |
//| when the TF is not the one just read. No guessing across TFs.    |
//+------------------------------------------------------------------+
double THVolNormLastSlow(const int tfMinutes)
{
   if(tfMinutes <= 0 || tfMinutes != s_tvnLastTF) return -1.0;
   return s_tvnLastSlow;
}

//+------------------------------------------------------------------+
//| Last bar count: bars the most recent recompute measured, or -1   |
//| when the TF is not the one just read. Below MIN_BARS the column  |
//| answered absence (1.0) — the drawn door must not adopt it.       |
//+------------------------------------------------------------------+
int THVolNormLastN(const int tfMinutes)
{
   if(tfMinutes <= 0 || tfMinutes != s_tvnLastTF) return -1;
   return s_tvnLastN;
}

//+------------------------------------------------------------------+
//| Drawn-levels V: the LIVE column above, adopted once per block —  |
//| one slot per (TF,pct) pair, like the live columns. Unless the   |
//| SLOW base jumps (15%+), which cuts the queue. The needle never  |
//| decides: it only rides along inside the adopted live value. OFF |
//| answers 1.0 at once and resets the adoption.                    |
//+------------------------------------------------------------------+
double THVolNormDrawnV(const bool enabled, const int tfMinutes, const double pctRung)
{
   // ONE slot per TF: the ability ladder asks several TFs through this same
   // door (EventHandlers_Objects:279) — a single shared adoption answered
   // every TF with the FIRST caller's value and poisoned the knot types.
   static datetime s_dbBlk[THVOLNORM_COLS];
   static double s_dbV[THVOLNORM_COLS];
    static double s_dbSlow[THVOLNORM_COLS];
    static int s_dbTF[THVOLNORM_COLS];
    static double s_dbPct[THVOLNORM_COLS];
    if(!enabled)
    {
       for(int z = 0; z < THVOLNORM_COLS; z++)
       {
          s_dbBlk[z] = 0; s_dbV[z] = 1.0; s_dbSlow[z] = 1.0; s_dbTF[z] = 0; s_dbPct[z] = 0.0;
       }
       return 1.0;
    }
    int slot = -1;
    int freeSlot = -1;
    for(int s = 0; s < THVOLNORM_COLS; s++)
    {
       // Pair identity like the live columns: rungs 6+7 share W1.
       if(s_dbTF[s] == tfMinutes && s_dbPct[s] == pctRung) { slot = s; break; }
       if(s_dbTF[s] == 0 && freeSlot < 0) freeSlot = s;
    }
    if(slot < 0) slot = freeSlot;
    if(slot < 0) return THVolNormColumnV(true, tfMinutes, pctRung);   // full: live, never stale
   double live = THVolNormColumnV(true, tfMinutes, pctRung);
   double slow = THVolNormLastSlow(tfMinutes);
   int ln = THVolNormLastN(tfMinutes);
   // Cold door: the column answered absence (too few bars — attach, TF
   // switch, weekend gap). Adopting 1.0 would freeze the raw table for a
   // whole block (the "tiny levels until TF switch" report). Track live
   // instead; adoption starts with the first warm recompute.
   if(ln < THVOLNORM_MIN_BARS) return live;
   datetime blk = THVolNormBlockStart(TimeCurrent());
   if(blk != s_dbBlk[slot])
   {
      double oldV = s_dbV[slot];
      bool first = (s_dbTF[slot] == 0);
      s_dbV[slot] = live;
      s_dbSlow[slot] = (slow > 0.0 ? slow : live);
      s_dbBlk[slot] = blk;
      s_dbTF[slot] = tfMinutes;
      s_dbPct[slot] = pctRung;
      // Adoption witness (ungated, like the column probe above): at most one
      // line per block per pair, only when the adopted value really moved.
      if(first || live != oldV)
         Print("[P-LBL] TH drawnV adopt tf=", tfMinutes,
               " blk=", TimeToString(blk, TIME_MINUTES),
               " was=", DoubleToString(oldV, 4),
               " now=", DoubleToString(live, 4), " why=block");
   }
   else if(slow > 0.0 && THVolNormJumpCuts(slow, s_dbSlow[slot]))
   {
      Print("[P-LBL] TH drawnV adopt tf=", tfMinutes,
            " blk=", TimeToString(blk, TIME_MINUTES),
            " was=", DoubleToString(s_dbV[slot], 4),
            " now=", DoubleToString(live, 4), " why=jump");
      s_dbV[slot] = live;   // the moment rides along; the slow decided
      s_dbSlow[slot] = slow;
   }
   return s_dbV[slot];
}

//+------------------------------------------------------------------+
//| Deadband guard for the drawn-levels frame: rebuild only when V   |
//| moved 2% from the ADOPTED value — not on a fixed grid (a grid    |
//| straddles: choppy ±0.5%/min noise rebuilds every minute, which   |
//| is the measured 400 ms freeze while ON). A genuine jump crosses  |
//| immediately (no delay); drift pays nothing until 2% cumulative.  |
//| OFF (1.0) and first adoption flip at once.                       |
//+------------------------------------------------------------------+
#define THVOLNORM_LEVEL_DEADBAND 0.02
static double s_lvAdopted = 1.0;

bool THVolNormLevelChanged(const double v)
{
   if(v == 1.0)
   {
      if(s_lvAdopted == 1.0) return false;
      s_lvAdopted = 1.0;
      return true;
   }
   if(s_lvAdopted == 1.0) { s_lvAdopted = v; return true; }
   if(MathAbs(v - s_lvAdopted) / s_lvAdopted >= THVOLNORM_LEVEL_DEADBAND)
   {
      s_lvAdopted = v;
      return true;
   }
   return false;
}

#endif // TH_VOLNORM_MQH
