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
//| SCOPE. TH label columns + the TH/SS-LS drawn steps (both through |
//| the same V). Factor/Combo modes and the mode readout own their    |
//| own basis and are untouched. The drawn levels ladder is rebuilt   |
//| only when V moves half a percent (frame-cache key below).         |
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
#define THVOLNORM_COLS     12    // per-TF cache slots (9 fractal rungs fit)

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
static string s_tvnWit[THVOLNORM_COLS];

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
   string tfTag = IntegerToString(tfMinutes) + "|";
   for(int s = 0; s < THVOLNORM_COLS; s++)
   {
      string k = s_tvnKey[s];
      if(StringLen(k) == 0) { if(freeSlot < 0) freeSlot = s; continue; }
      if(StringFind(k, tfTag) == 0) { slot = s; break; }
   }
   if(slot < 0) slot = freeSlot;
   if(slot < 0) return 1.0;   // cache full (12 slots, 9 rungs max): absence, never a guess

   datetime bt0 = iTime(NULL, tfMinutes, 0);
   string fullKey = tfTag + TimeToString(bt0) + "|" + DoubleToString(pctRung, 6);
   if(s_tvnKey[slot] == fullKey) return s_tvnV[slot];

   double prevV = s_tvnV[slot];
   bool hadPrev = (StringLen(s_tvnKey[slot]) > 0);
   double v = 1.0;
   double rv = 0.0;
   int n = 0;
   int avail = iBars(NULL, tfMinutes);
   int want = (tfMinutes >= THVOLNORM_BIG_TF ? THVOLNORM_LOOKBACK_BIG : THVOLNORM_LOOKBACK);
   if(avail < want) want = avail;
   if(want > avail - 1) want = avail - 1;   // gap leg reads i+1: keep it inside history
   if(want >= THVOLNORM_MIN_BARS && bt0 > 0)
   {
      double sum = 0.0;
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
         sum += MathLog(hh / ll);
         n++;
      }
      if(n >= THVOLNORM_MIN_BARS)
         rv = sum / (double)n;
      else
      {
         n = 0;
         rv = 0.0;
      }
      v = THVolNormVFromMean(rv, pctRung);
   }

   s_tvnKey[slot] = fullKey;
   s_tvnV[slot] = v;
   s_tvnRV[slot] = rv;
   s_tvnN[slot] = n;

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
