//+------------------------------------------------------------------+
//| BaseKnot_Shot.mqh                                                |
//|                                                                  |
//| P-BK-124 (2026-10-27) — ONE PRESS, ONE SAMPLE FOLDER.            |
//|                                                                  |
//| The user: «من اسکرین شات نمونه‌ها رو چطور باید بگیرم و اینکه در   |
//| لاگ هم اسکرین شات بگیر بزار دیگه که من مثلا یک دکمه رو زدم سیو    |
//| بشه» — a key press has to leave a folder behind that the site    |
//| can read, with the picture and the numbers in it.                |
//|                                                                  |
//| THE NUMBERS ARE READ BACK FROM THE INK, NOT RE-DERIVED. The plan |
//| already drew the box, the ENTRY ray, the SL ray and the TP ticks |
//| at the prices it decided; this file opens those objects and      |
//| reads their prices. So a sidecar cannot describe a stop the      |
//| chart is not drawing — the one failure a dataset can never       |
//| recover from, because the picture and the row would disagree and |
//| nothing would say which one lied. The only arithmetic added here |
//| is `u` (the ladder coordinate) and its margin, which are a       |
//| MEASUREMENT of the read-back numbers, not a second decision:     |
//| they are printed, never used to pick a level.                    |
//|                                                                  |
//| WHY A FOLDER AND NOT A LOG LINE. `[BK-SHOT]` goes to the flushed |
//| channel for the human trail, but the record itself is a folder:  |
//| `shot.png` + `sample.txt`, self-describing, one per press. The   |
//| sync tool then only has to look at which folders it has not      |
//| filed yet — no journal parsing, no line-wrapping, and a press    |
//| that happened while the terminal was closed is still a folder.   |
//+------------------------------------------------------------------+
#ifndef BASE_KNOT_SHOT_MQH
#define BASE_KNOT_SHOT_MQH

//--- the record's own layout, relative to MQL4\Files (MT4's sandbox)
#define BK_SHOT_ROOT      "BK_Dataset"
#define BK_SHOT_SAMPLES   "BK_Dataset\\Samples"
#define BK_SHOT_FLASH     "BKSHOT_FLASH"
//--- P-BK-124b (2026-10-27) - THE RECEIPT'S OWN THREE NUMBERS.
//--- MEASURED on the reporting chart: five `K` presses wrote five COMPLETE folders
//--- (shot.png 73 KB + a 38-key sample.txt each, `node tools/bk-shot-sync.js --list`
//--- verified all five `png=y txt=y`) and the user still reported «چیزی روی صفحه نمیاد
//--- که سیو شده یا نه». The receipt existed and answered nothing: one second of 13 px
//--- ink carrying neither the knot's type nor its time, so a press that filed a sample
//--- and a press that did nothing looked identical. A receipt that has to be caught
//--- mid-blink is not a receipt (P-TH3-REC-03's lesson, relearned at 18 px).
//--- P-BK-124b (2026-10-27, second round): ONE SECOND IS WHAT THE USER ORDERED — «یک ثانیه بس
//--- هستش برای این». The 1 s hold that failed before failed at 13 px with a bare "saved"; the
//--- three things that made it unreadable are the FACE, the TEXT and the WITNESS, and all three
//--- are pinned above and below this line. The hold follows the order, not the old defect.
#define BK_SHOT_HOLD_SEC  1     // how long the receipt stays; cleared by its own tick, never slept for
#define BK_SHOT_FACE_PX   18    // the face's size (the 13 px face was read as "nothing appeared")
#define BK_SHOT_FACE_W    10    // px/char at 18 px - 7 px/char at 13 px, the same measurement
//--- bumped when a FORMULA changes, never when the reader changes: it is the
//--- column a row is re-scored against (docs/bk-dataset.md §6)
//--- v2 (2026-10-27, P-BK-125): the stop's rung is hop = round(u) — the NEAREST rung of the
//--- ladder — instead of the type name's fixed hop. v1 rows (BK-0001..0004) were read off the
//--- log and keep their own numbers; they are the evidence v2 was chosen on, not a sample of
//--- it. Never mix the two in one score.
//--- v3 (2026-10-27, P-BK-126b): THE KNOT'S TIME IS THE THREE CANDLES, NOT THE ATR BAND. v2 read
//--- the class off the ATR ruler (`h / ATR` in 240%..360%) and every off-ladder time was a size
//--- coincidence; v3 lets the stand-still walk decide and keeps the ATR owner only as the
//--- fallback. A row's `Node_TF`, its type and its stop are therefore NOT comparable with a v2
//--- row's: MEASURED on the reporting box the M5 class becomes the 3-candle one and CTR becomes
//--- ETR (three M30 candles = 99.4 % of the box; M5's ATR ratio was 3.47 only because 5 minutes
//--- is where the band 2.40..3.60 happens to fall).
//--- v4 (2026-10-27, P-BK-126c): THE STAND-STILL GRID IS THE CLOCK's. v3 cut its buckets back
//--- from the box' right edge, so the SAME band answered a different knot for every date the
//--- edge sat on — MEASURED, one band, eleven closes: 26m..31m; clock-aligned, all eleven but
//--- the two whose window ends early read 30m. A v3 row's `Node_TF` is that edge read, so it is
//--- not comparable with a v4 row's; the two live rows of one box 10 s apart (`27m · ETR ·
//--- SELL` beside `13m · CTR · BUY`) are v3's own proof and both were re-baselined under v4.
//--- v5 (2026-10-27, P-BK-126d): THE COUNT IS THE MEASURE. v4 still cut a grid over the base's
//--- own candle count (the clock's), and the user rejected any grid at all: «به ساعت نباید ربط
//--- داشته باشه ... بین کندل ورود و خروج سه کندل باشه». The class is now the entry..exit count
//--- over three, so a v4 row's `Node_TF` (a grid the count was fitted to) is not comparable with
//--- a v5 row's (the count itself, divided once).
//--- v6 (2026-10-27, P-BK-126e): AND THE COUNT IS THE RUN THE BOX' LEFT EDGE NAMES. v5 divided
//--- a run that `BaseKnotBarCount` had anchored on the RIGHT edge, so one band holding two runs
//--- answered whichever the drag brought nearest that edge — MEASURED, one band, 99 right edges:
//--- 12/20m at 45 of them, 8/13m at 46, 5/8m at 7, 22/36m at 1. The walk starts at the entry
//--- candle now and steps forward, so a v5 row's count (and its `Node_TF`, its bars and its type)
//--- can be a different run's and is not comparable with a v6 row's.
//--- v7 (2026-10-27, P-BK-128): AND THE TYPE'S BOUNDARIES ARE RATIOS, NOT PRICE MIDPOINTS.
//--- (a+b)/2 is "nearest" only for an additive ladder; these rungs grow x2.22 and x3.23, so the
//--- boundary is √(a·b) — MEASURED, 135.2/300.8 gives 218.0 arithmetically and 201.7 in ratio,
//--- which is why ONE 217-pip box printed FTR at 217.3 and ETR at 219.5. The leg's rung moved in
//--- the same version (BaseKnotLadderHopAt: the deepest package that FITS, not round(u)) and the
//--- `U` column is now the same ratio coordinate, so a v7 row's Type/U/Stop are not comparable
//--- with a v6 row's — the three numbers were cut at different places.
//--- v8 (2026-10-28, P-BK-132): a box taller than the EngSL of its chosen rung grades the entry,
//--- stop and targets by one shared box-to-rung factor, clamped at 1. v7 rows do not contain that
//--- adjustment, so entry/stop/target outcomes must not be scored together across versions.
//--- v9 (2026-10-28, P-BK-133): a time the ladder does not carry is ITS OWN RUNG — the knot's
//--- entry reads that time's HuntSL instead of the next rung's (his 2h20m box: 142.5, not the
//--- H4-graded 214.6), while the stop and the targets keep the box' power grade. v8 rows of an
//--- off-ladder box were read on H4, so their entry/stop/target outcomes must not be scored
//--- beside v9's; a ladder rung and every FTR are byte-identical to v8.
//--- v10 (2026-10-28, P-BK-135): THE FACTOR IS THE PAIR'S. An off-ladder Hunt knot no longer
//--- grades its stop against the box: his 2h20m box reads stop 53.4 (not 80.5) and the three
//--- targets 5x / 12x THAT stop, so entry/stop = 8/3 on every knot. A v9 row of such a box has a
//--- stop and a target set read in two regimes (142.5 / 80.5 = 1.77) and must not be scored
//--- beside a v10 row; a ladder rung and every FTR are byte-identical to v9.
#define BK_FORMULA_VERSION "v10"

//--- P-BK-126f (2026-10-27) — THE KNOT'S OWN DERIVATION, ON THE FLUSHED CHANNEL.
//--- The user, after two drag rounds: «روش که مطمعن باشه رو پیدا کن» — a method that leaves
//--- nothing arguable. A screenshot argues about which candle and which edge; a LINE does not.
//--- So the count, the unit it was counted on and the answer it produced are ONE line, and two
//--- drags are compared by reading their own numbers:
//---   [BK-KNOT] formula=v8 box=5_22269312 chart=M5 band=3999.52..4012.14 dg=2
//---             boxT=08:45..10:00 still=12 bars=12 readTF=M5 nodeTF=20m cap=1440
//---             h=217.3 type=ETR hop=0 entry=08:55 last=09:50 exit=09:55
//--- (`h`/`type`/`hop` are P-BK-128's: the height the type was cut at, the name it got and the
//--- rung the legs were read on — the three numbers a "one time ETR one time FTR" report turns
//--- into one line.)
//--- (that line is the measured band of docs/bk-dataset.md §15: the same 12 candles from 08:55 to
//--- 09:50 with the exit at 09:55, one answer for 99 right edges.)
//--- READ IT THIS WAY (the whole method):
//---   * `nodeTF` is `still * readTF / 3`, capped at `cap` (P-BK-126d's one division) — the
//---     arithmetic is on the line, so nothing has to be trusted;
//---   * `still` is the candles whose BODIES sat inside the band between `entry` (the box' LEFT
//---     edge candle — P-BK-126e's anchor, NOT counted) and `exit` (the candle that CLOSED
//---     outside it, counted); `bars` is that same run's life;
//---   * `boxT` is the DRAWN rectangle. A drag moves `boxT` and nothing else: if `still`,
//---     `readTF` and `nodeTF` are the same on both lines, the knot did not move;
//---   * `chart` is the TF the chart was on, so a TF switch prints a second line that must
//---     differ in `chart` ALONE.
//--- Emit-on-CHANGE only, ONE MEMO PER BOX (the slot table below): a still chart compares a few
//--- scalars, builds no string and writes no byte. The memo is per BOX and not one shared pair of
//--- scalars, because `BaseKnotSync` is also called in a LOOP over every box (the attach re-sync,
//--- BaseKnot_Measure.mqh) and a single memo would read that loop as "changed, changed" and print
//--- two lines for an untouched chart. Four slots, reused round-robin — a chart with more than four
//--- live knots re-prints one line when a box comes back, never a line per pass.
#define BK_WITNESS_SLOTS 4
struct BKWitnessMemo
{
   bool     used;
   string   id;
   int      chartTF, bars, still, readTF, nodeTF;
   datetime t1, t2, s, z, x;
   double   top, bot;
};
string BaseKnotWitnessT(const datetime t) { return (t > 0 ? TimeToString(t, TIME_DATE | TIME_MINUTES) : "-"); }
void BaseKnotKnotWitness(const string id,
                         const int kind, const int hop,
                         const datetime boxT1, const datetime boxT2,
                         const double top, const double bot,
                         const int bars, const int still,
                         const int readTF, const int nodeTF,
                         const datetime tStart, const datetime tLast, const datetime tExit)
{
   static BKWitnessMemo wm[BK_WITNESS_SLOTS];
   static int wNext = 0;
   int chartTF = Period();
   int slot = -1;
   for(int i = 0; i < BK_WITNESS_SLOTS; i++)
   {
      if(!wm[i].used) { slot = i; break; }                      // a free slot, first pass for this box
      if(wm[i].id == id) { slot = i; break; }                   // this box' own memo
   }
   if(slot < 0)   // every slot holds a live box: take the next one round-robin, so no box is pinned
   {
      slot = wNext;
      wNext = (wNext + 1) % BK_WITNESS_SLOTS;
   }
   if(wm[slot].used && wm[slot].id == id && wm[slot].chartTF == chartTF &&
      wm[slot].bars == bars && wm[slot].still == still && wm[slot].readTF == readTF &&
      wm[slot].nodeTF == nodeTF && wm[slot].t1 == boxT1 && wm[slot].t2 == boxT2 &&
      wm[slot].s == tStart && wm[slot].z == tLast && wm[slot].x == tExit &&
      wm[slot].top == top && wm[slot].bot == bot) return;   // a still chart: no string, no write
   wm[slot].used = true; wm[slot].id = id; wm[slot].chartTF = chartTF;
   wm[slot].bars = bars; wm[slot].still = still; wm[slot].readTF = readTF; wm[slot].nodeTF = nodeTF;
   wm[slot].t1 = boxT1; wm[slot].t2 = boxT2; wm[slot].s = tStart; wm[slot].z = tLast; wm[slot].x = tExit;
   wm[slot].top = top; wm[slot].bot = bot;
   int dg = GetCachedDigits();
   int readUsed = (readTF > 0 ? readTF : chartTF);   // BaseKnotBaseTFRead's own fallback, printed as used
   DrawStripDiagEmit("[BK-KNOT] formula=" + BK_FORMULA_VERSION +
                     " box=" + id +
                     " chart=" + BaseKnotTFName(chartTF) +
                     " band=" + DoubleToString(bot, dg) + ".." + DoubleToString(top, dg) +
                     " dg=" + IntegerToString(dg) +
                     " boxT=" + BaseKnotWitnessT(boxT1) + ".." + BaseKnotWitnessT(boxT2) +
                     " still=" + IntegerToString(still) +
                     " bars=" + IntegerToString(bars) +
                     " readTF=" + BaseKnotTFName(readUsed) +
                     " nodeTF=" + BaseKnotTFName(nodeTF) +
                     " cap=" + IntegerToString(BK_KNOT_TF_MAX) +
                     " h=" + DoubleToString(BaseKnotToPips(MathAbs(top - bot)), 1) +
                     " type=" + BaseKnotNodeShort(kind) + " hop=" + IntegerToString(hop) +
                     " entry=" + BaseKnotWitnessT(tStart) +
                     " last=" + BaseKnotWitnessT(tLast) +
                     " exit=" + BaseKnotWitnessT(tExit));
}
//+------------------------------------------------------------------+
//| P-BK-133 (2026-10-28) — THE OFF-LADDER DECISION, FLUSHED.        |
//|                                                                  |
//| `[BK-KNOT]` names the knot's TIME and the type; it cannot show    |
//| which ruler the two LEGS were read on, and the user's report was  |
//| exactly that gap: a 2h20m box whose entry was drawn on H4. This   |
//| line answers the pair the geometry produced — the entry (`off`),  |
//| the stop (`risk`) and the ratio between them — so the law          |
//| `entry / stop = 8/3 (Hunt) or 1 (FTR)` is readable off a frame    |
//| instead of argued from code. P-BK-135: EVERY knot writes it (a    |
//| rung included — that is where the rule is easiest to break), and  |
//| `own=1` says the legs were read on the knot's own time.            |
//| Emit-on-change, four seats reused by id (P-BK-107c's law: a full  |
//| table is SILENT, never a stolen seat).                             |
//+------------------------------------------------------------------+
#define BK_PAIR_SLOTS 4
void BaseKnotPairWitness(const string id, const int nodeTF, const int legTF,
                         const double offPips, const double riskPips)
{
   static string   wid[BK_PAIR_SLOTS];
   static int      wnode[BK_PAIR_SLOTS], wleg[BK_PAIR_SLOTS];
   static double   woff[BK_PAIR_SLOTS], wrisk[BK_PAIR_SLOTS];
   static bool     wused[BK_PAIR_SLOTS];
   int slot = -1;
   for(int i = 0; i < BK_PAIR_SLOTS; i++)
   {
      if(!wused[i]) { slot = i; break; }              // a free seat
      if(wid[i] == id) { slot = i; break; }           // this box' own memo
   }
   if(slot < 0) return;                               // full of live boxes: bounded silence
   if(wused[slot] && wid[slot] == id && wnode[slot] == nodeTF && wleg[slot] == legTF &&
      MathAbs(woff[slot] - offPips) < 0.05 && MathAbs(wrisk[slot] - riskPips) < 0.05) return;
   wused[slot] = true; wid[slot] = id; wnode[slot] = nodeTF; wleg[slot] = legTF;
   woff[slot] = offPips; wrisk[slot] = riskPips;
   DrawStripDiagEmit("[P-BK-135] box=" + id +
                     " node=" + BaseKnotTFName(nodeTF) +
                     " leg=" + BaseKnotTFName(legTF) +
                     " own=" + (legTF == nodeTF ? "1" : "0") +
                     " off=" + DoubleToString(offPips, 1) +
                     " risk=" + DoubleToString(riskPips, 1) +
                     " r=" + DoubleToString(riskPips > 0.0 ? offPips / riskPips : 0.0, 2));
}

static datetime s_bkShotFlashDue = 0;
//--- the leaf the last capture wrote ("" = none yet). The harness reads it because the leaf
//--- carries a second-resolution stamp and a test cannot re-derive it without a race.
string g_bkShotLastDir = "";

//--- A FOLDER NAME IS A FILENAME, NOT A SENTENCE. Box ids are "<tf>_<tick>"
//--- today, but a legacy id or a hand-edited chart can carry anything, and one
//--- illegal character turns FolderCreate into a silent `false`.
string BaseKnotShotSafe(const string src)
{
   string out = src;
   StringReplace(out, ":", "-");
   StringReplace(out, ".", "-");
   StringReplace(out, " ", "_");
   StringReplace(out, "\\", "-");
   StringReplace(out, "/", "-");
   StringReplace(out, "*", "-");
   StringReplace(out, "?", "-");
   StringReplace(out, "\"", "-");
   StringReplace(out, "<", "-");
   StringReplace(out, ">", "-");
   StringReplace(out, "|", "-");
   return out;
}

string BaseKnotShotStamp()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return StringFormat("%04d%02d%02d-%02d%02d%02d", dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);
}

//--- THE LADDER COORDINATE. `BaseKnotNodeKindOfLength` cuts the box' height at the RATIO
//--- midpoints of three abilities read at one anchor (P-BK-128), which are exactly the knots of
//--- one piecewise-LOG coordinate: u=0 at ATR(node rung), 1 at +1, 2 at +2, 3 at +3, and u is
//--- interpolated in ln(h). So FTR is u<=0.5, ETR <=1.5, CTR <=2.0, OTR above — the SAME rule,
//--- spelled as a position instead of a name. Printing it makes every future sample carry the
//--- fraction the type throws away (measured: BK-0004 sits 0.003 rung past the CTR edge and pays
//--- a stop 2.28x wider for it). Nothing reads this back: it is a witness.
//--- v6 printed the ARITHMETIC position here; v7 is the ratio one, so u = 0.5 IS the printed
//--- FTR/ETR boundary and the two numbers on the sample cannot disagree.
//--- -1 = no ladder to stand on (a cold rung), never a guessed 0.
double BaseKnotLadderU(const double h, const double a0, const double a1,
                       const double a2, const double a3)
{
   if(h <= 0.0 || a0 <= 0.0 || a1 <= a0) return -1.0;
   if(h <= a1) return MathLog(h / a0) / MathLog(a1 / a0);          // the 0..1 segment (also below a0)
   if(h <= a2) return 1.0 + MathLog(h / a1) / MathLog(a2 / a1);    // the 1..2 segment
   if(a3 > a2) return 2.0 + MathLog(h / a2) / MathLog(a3 / a2);    // the 2..3 segment
   return -1.0;                                                    // no fourth rung: unknown, not 2.0
}

//--- the distance from u to the nearest band edge, in rungs. -1 = no u.
double BaseKnotLadderUMargin(const double u)
{
   if(u < 0.0) return -1.0;
   double d = MathAbs(u - 0.5);
   d = MathMin(d, MathAbs(u - 1.5));
   d = MathMin(d, MathAbs(u - 2.0));
   return d;
}

//--- P-TH3-REC-05's lesson, kept: a LABEL centres its text on the anchor, so the box is
//--- sized FROM the string and the anchor is then placed at the middle of what is left.
//--- A fixed width put the text off-centre; a proportional face made the arithmetic a
//--- guess. 7 px/char at the 13px face, the product's own mono face.
//---
//--- P-BK-124b: AND THE RECEIPT IS A CLAIM ABOUT A PIXEL, SO IT IS READ BACK. The label is
//--- answered by `ObjectFind` + `OBJPROP_TEXT` the moment it is born, and the answer goes to
//--- the FLUSHED channel (P-LOG-3): `flash obj=0` is a capture that wrote a folder and showed
//--- nothing, which is a different bug from a label that exists and is not painted (P-LOG-10's
//--- class). Without this line those two are one symptom - the exact trap that cost
//--- «هیچی نمیاد» a whole round here.
void BaseKnotShotFlash(const string msg, const int holdSec = BK_SHOT_HOLD_SEC)
{
   int w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   if(w <= 0 || h <= 0) { w = 1024; h = 768; }

   if(ObjectFind(0, BK_SHOT_FLASH) >= 0) ObjectDelete(0, BK_SHOT_FLASH);   // a re-press never stacks

   int tw = (StringLen(msg) * BK_SHOT_FACE_W) + 34;
   if(tw < 140) tw = 140;
   if(tw > w - 20) tw = w - 20;
   int th = BK_SHOT_FACE_PX + 22;
   if(ObjectCreate(0, BK_SHOT_FLASH, OBJ_LABEL, 0, 0, 0))
   {
      ObjectSetInteger(0, BK_SHOT_FLASH, OBJPROP_CORNER, 0);
      ObjectSetInteger(0, BK_SHOT_FLASH, OBJPROP_XDISTANCE, (w - tw) / 2);
      ObjectSetInteger(0, BK_SHOT_FLASH, OBJPROP_YDISTANCE, (h - th) / 2);
      ObjectSetInteger(0, BK_SHOT_FLASH, OBJPROP_ANCHOR, ANCHOR_CENTER);
      ObjectSetInteger(0, BK_SHOT_FLASH, OBJPROP_FONTSIZE, BK_SHOT_FACE_PX);
      ObjectSetString(0, BK_SHOT_FLASH, OBJPROP_FONT, BioChromeFont(true));   // the product's own bold face
      ObjectSetInteger(0, BK_SHOT_FLASH, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, BK_SHOT_FLASH, OBJPROP_BGCOLOR, clrBlack);
      ObjectSetInteger(0, BK_SHOT_FLASH, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, BK_SHOT_FLASH, OBJPROP_WIDTH, 3);
      ObjectSetInteger(0, BK_SHOT_FLASH, OBJPROP_BACK, false);
      ObjectSetInteger(0, BK_SHOT_FLASH, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, BK_SHOT_FLASH, OBJPROP_HIDDEN, true);
      ObjectSetString(0, BK_SHOT_FLASH, OBJPROP_TEXT, msg);
      ChartRedraw();
      s_bkShotFlashDue = TimeLocal() + holdSec;   // WALL clock: a closed market never ages TimeCurrent
   }

   //--- the receipt's own witness, read back off the object the chart now carries
   bool there = (ObjectFind(0, BK_SHOT_FLASH) >= 0);
   string back = (there ? ObjectGetString(0, BK_SHOT_FLASH, OBJPROP_TEXT) : "");
   DrawStripDiagEmit("[BK-SHOT] flash obj=" + (there ? "1" : "0") +
                     " px=" + IntegerToString(BK_SHOT_FACE_PX) +
                     " hold=" + IntegerToString(holdSec) +
                     " text=\"" + back + "\"");
}

//--- THE FLASH'S KEEPER. One compare when nothing is armed, which is every round but one
//--- per press. Called from the pump AND from OnTimer (P-BK-124b): the pump rides the ticks,
//--- so a market that stops ticking would otherwise keep a receipt on the chart for ever -
//--- the same debt P-TH3-REC-04 paid for the `M` receipt.
void BaseKnotShotFlashTick()
{
   if(s_bkShotFlashDue == 0 || TimeLocal() < s_bkShotFlashDue) return;
   s_bkShotFlashDue = 0;
   if(ObjectFind(0, BK_SHOT_FLASH) >= 0) ObjectDelete(0, BK_SHOT_FLASH);
   ChartRedraw();
}

//--- THE CAPTURE. True = a folder was written (the shot or the text may still have
//--- failed independently — `shot=` in the line says which). One press, one sample.
bool BaseKnotCaptureSample()
{
   string id = BaseKnotSelectedId();
   if(id == "")
   {
      DrawStripDiagEmit("[BK-SHOT] refused: no box on the chart");
      BaseKnotShotFlash("NOT SAVED  no knot selected");
      return false;
   }
   int k = BaseKnotFind(id);
   if(k < 0)
   {
      DrawStripDiagEmit("[BK-SHOT] refused: box=" + id + " is not in the registry");
      BaseKnotShotFlash("NOT SAVED  knot not registered");
      return false;
   }
   string pfx = BaseKnotPrefix(id);
   string box = (pfx == "" ? "" : BaseKnotBoxName(pfx));
   if(box == "" || ObjectFind(0, box) < 0)
   {
      DrawStripDiagEmit("[BK-SHOT] refused: box=" + id + " has no rectangle on the chart");
      BaseKnotShotFlash("NOT SAVED  knot has no rectangle");
      return false;
   }

   //--- the box, read off its own rectangle (the same two corners the owner pump reads)
   double p1 = ObjectGetDouble(0, box, OBJPROP_PRICE, 0);
   double p2 = ObjectGetDouble(0, box, OBJPROP_PRICE, 1);
   double top = MathMax(p1, p2), bot = MathMin(p1, p2);
   datetime t1 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 0);
   datetime t2 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 1);
   if(t2 < t1) { datetime tt = t1; t1 = t2; t2 = tt; }
   if(top <= bot)
   {
      DrawStripDiagEmit("[BK-SHOT] refused: box=" + id + " has no height");
      BaseKnotShotFlash("NOT SAVED  knot has no height");
      return false;
   }
   double hPips = BaseKnotToPips(top - bot);

   //--- the ladder the TYPE was decided on: the node's rung and the three above it, all
   //--- at the story anchor (P-BK-79) — the same rows `BaseKnotAbilityGet` reads, plus the
   //--- fourth rung the OTR stop reads and the reader above never asked for.
   int nodeTF = g_bkBoxes[k].baseTFMin;
   datetime an = (g_bkBoxes[k].storyT > 0 ? g_bkBoxes[k].storyT : 0);
   double a0 = 0.0, a1 = 0.0, a2 = 0.0, a3 = 0.0;
   bool warm = (nodeTF > 0 && BaseKnotAbilityGet(nodeTF, an, a0, a1, a2));
   int up1 = (nodeTF > 0 ? BaseKnotNextTFMin(nodeTF) : 0);
   int up2 = (up1 > 0 ? BaseKnotNextTFMin(up1) : 0);
   int up3 = (up2 > 0 ? BaseKnotNextTFMin(up2) : 0);
   if(up3 > 0) BaseKnotAbilityRow(up3, an, a3);   // cold is a real answer: a3 stays 0

   double p0 = BaseKnotToPips(a0), p1v = BaseKnotToPips(a1), p2v = BaseKnotToPips(a2);
   double p3v = BaseKnotToPips(a3);
   double u  = (warm ? BaseKnotLadderU(hPips, p0, p1v, p2v, p3v) : -1.0);
   double um = BaseKnotLadderUMargin(u);
   double bFtr = (warm ? (p0 + p1v) * 0.5 : 0.0);
   double bEtr = (warm ? (p1v + p2v) * 0.5 : 0.0);
   double bCtr = (warm ? p2v : 0.0);
   //--- the margin in PIPS is what a trader reads; the margin in RUNGS is what the type
   //--- was actually decided by. Both are printed because they are not the same question.
   double mPips = -1.0;
   if(warm)
   {
      mPips = MathAbs(hPips - bFtr);
      mPips = MathMin(mPips, MathAbs(hPips - bEtr));
      mPips = MathMin(mPips, MathAbs(hPips - bCtr));
   }

   //--- the legs, read back from the rays and ticks the plan drew
   int    side   = (g_bkBoxes[k].dir >= 0 ? 1 : -1);
   double edge   = (side >= 0 ? top : bot);
   string entryN = BaseKnotEntryName(pfx);
   string slN    = BaseKnotSLName(pfx);
   double entry  = (ObjectFind(0, entryN) >= 0 ? ObjectGetDouble(0, entryN, OBJPROP_PRICE, 0) : 0.0);
   double sl     = (ObjectFind(0, slN) >= 0 ? ObjectGetDouble(0, slN, OBJPROP_PRICE, 0) : 0.0);
   double offPips  = (entry > 0.0 ? BaseKnotToPips(MathAbs(entry - edge)) : 0.0);
   //--- P-BK-125 (2026-10-27): THE STOP IS ENTRY -> SL, NOT EDGE -> SL. It was measured from
   //--- the edge, which folded the entry's own penetration into the risk: the harness read
   //--- 59.0 pips on a box whose stop is 31.9 (27.1 + 31.9). Every seed row in the CSV means
   //--- entry -> SL (BK-0003 = 32.0), so the two halves of the dataset were not the same
   //--- number, and a re-score would have compared a risk against a risk-plus-offset.
   //--- The edge distance is still here, in its own column: Entry_Off_Pips above.
   double stopPips = ((sl > 0.0 && entry > 0.0) ? BaseKnotToPips(MathAbs(sl - entry)) : 0.0);
   double tpPips[BK_TP_PLAN_MAX + 1];
   ArrayInitialize(tpPips, 0.0);
   for(int tk = 1; tk <= BK_TP_PLAN_MAX; tk++)
   {
      string nm = BaseKnotTPTickName(pfx, tk);
      if(ObjectFind(0, nm) < 0) continue;
      double lv = ObjectGetDouble(0, nm, OBJPROP_PRICE, 0);
      if(lv <= 0.0 || entry <= 0.0) continue;
      tpPips[tk] = BaseKnotToPips(MathAbs(lv - entry));   // the note's own measure (P-BK-116)
   }

   double perPip = BaseKnotMoneyPerPip();
   double lot    = (stopPips > 0.0 ? BaseKnotRiskLot(stopPips) : 0.0);
   double bal    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskUsd = stopPips * perPip * lot;

   //--- P-BK-125 / the 20-sample checkpoint: WHAT v1 WOULD HAVE CHARGED FOR THIS SAME BOX.
   //--- v2 sizes the stop on the NEAREST rung; v1 sized it on the TYPE NAME's fixed hop. The
   //--- two differ only near a band edge, and only a row that carries BOTH numbers can be
   //--- re-scored without a second capture session — the ATR rows of a closed box are not
   //--- reproducible from the log a week later. Asked of the SAME geometry owner, at the SAME
   //--- anchor, with the name's own hop (hop = -1), so the two numbers cannot come from two
   //--- different readings of the box.
   double stopV1 = stopPips;
   if(nodeTF > 0 && hPips > 0.0)
   {
      double e1 = 0.0, s1 = 0.0, o1 = 0.0, r1 = 0.0;
      BaseKnotCalcLevels(top, bot, side, g_bkBoxes[k].nodeKind, nodeTF, e1, s1, o1, r1, an, -1);
      if(r1 > 0.0) stopV1 = r1;
   }

   //--- THE FOLDER. FolderCreate makes one level at a time, so the parents are named first.
   //--- The leaf carries the timestamp to the SECOND, so `false` here means a real refusal
   //--- (a name the filesystem will not take), not "already there" — a re-press in the same
   //--- second IS the same sample and must not be filed twice.
   string stamp = BaseKnotShotStamp();
   string leaf  = BaseKnotShotSafe(id) + "_" + stamp;
   string dir   = BK_SHOT_SAMPLES + "\\" + leaf;
   FolderCreate(BK_SHOT_ROOT);
   FolderCreate(BK_SHOT_SAMPLES);
   if(!FolderCreate(dir))
   {
      DrawStripDiagEmit("[BK-SHOT] refused: FolderCreate failed for " + dir);
      BaseKnotShotFlash("NOT SAVED  cannot create the folder");
      return false;
   }
   g_bkShotLastDir = leaf;

   //--- THE PICTURE. 1:1 with the chart, never stretched (P-TH3-REC-04: a fixed 1920x1080
   //--- upscaled the capture and made the prices illegible, which defeats a dataset whose
   //--- numbers must be checkable against the pixels). `start_bar=0` pins the frame to the
   //--- bars currently on screen, so the frame the trader framed is the frame written.
   //--- MQL4 cannot reach the toolbar or the desktop — the chart area is the whole capture.
   ChartRedraw();   // one redraw away, no Sleep: a still chart needs no settle
   int shotW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int shotH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   if(shotW <= 0) shotW = 1920;
   if(shotH <= 0) shotH = 1080;
   string shotName = "shot.png";
   bool okShot = WindowScreenShot(dir + "\\" + shotName, shotW, shotH, 0);

   //--- THE RECORD. Key names are the Dataset.csv column names, one to one, so the sync
   //--- tool is a copy and not a translation. ANSI: every value here is ASCII by design.
   string txt = dir + "\\sample.txt";
   int fh = FileOpen(txt, FILE_WRITE | FILE_TXT | FILE_ANSI);
   bool okTxt = (fh != INVALID_HANDLE);
   if(okTxt)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      FileWrite(fh, "Folder: " + leaf);
      FileWrite(fh, "Capture_Date: " + StringFormat("%04d-%02d-%02d", dt.year, dt.mon, dt.day));
      FileWrite(fh, "Capture_Clock: " + StringFormat("%02d:%02d:%02d", dt.hour, dt.min, dt.sec));
      FileWrite(fh, "Symbol: " + Symbol());
      FileWrite(fh, "Chart_TF: " + BaseKnotTFName(Period()));
      FileWrite(fh, "Node_TF: " + (nodeTF > 0 ? BaseKnotTFName(nodeTF) : ""));
      FileWrite(fh, "Box_ID: " + id);
      FileWrite(fh, "Story_Anchor: " + (an > 0 ? TimeToString(an, TIME_DATE | TIME_MINUTES) : ""));
      FileWrite(fh, "Edge_Anchor: " + (t2 > 0 ? TimeToString(t2, TIME_DATE | TIME_MINUTES) : ""));
      FileWrite(fh, "Box_Pips: " + DoubleToString(hPips, 1));
      FileWrite(fh, "ATR_Trig: " + DoubleToString(p0, 1));
      FileWrite(fh, "ATR_Pat: " + DoubleToString(p1v, 1));
      FileWrite(fh, "ATR_Str: " + DoubleToString(p2v, 1));
      FileWrite(fh, "ATR_Fourth: " + DoubleToString(p3v, 1));
      FileWrite(fh, "Band_FTR: " + DoubleToString(bFtr, 1));
      FileWrite(fh, "Band_ETR: " + DoubleToString(bEtr, 1));
      FileWrite(fh, "Band_CTR: " + DoubleToString(bCtr, 1));
      FileWrite(fh, "Type: " + BaseKnotNodeShort(g_bkBoxes[k].nodeKind));
      FileWrite(fh, "Edge_Margin_Pips: " + DoubleToString(mPips, 1));
      FileWrite(fh, "U: " + DoubleToString(u, 3));
      FileWrite(fh, "U_Margin: " + DoubleToString(um, 3));
      FileWrite(fh, "Entry_Off_Pips: " + DoubleToString(offPips, 1));
      FileWrite(fh, "Stop_Pips: " + DoubleToString(stopPips, 1));
      FileWrite(fh, "Stop_V1_Pips: " + DoubleToString(stopV1, 1));
      FileWrite(fh, "TP1_Pips: " + DoubleToString(tpPips[1], 1));
      FileWrite(fh, "TP2_Pips: " + DoubleToString(tpPips[2], 1));
      FileWrite(fh, "TP3_Pips: " + DoubleToString(tpPips[3], 1));
      FileWrite(fh, "PerPip: " + DoubleToString(perPip, 2));
      FileWrite(fh, "Balance: " + DoubleToString(bal, 0));
      FileWrite(fh, "Risk_Pct: " + DoubleToString(inpBKRiskPct, 2));
      FileWrite(fh, "Lot: " + DoubleToString(lot, 2));
      FileWrite(fh, "Risk_USD: " + DoubleToString(riskUsd, 1));
      FileWrite(fh, "Direction: " + (side >= 0 ? "BUY" : "SELL"));
      FileWrite(fh, "Formula_Version: " + BK_FORMULA_VERSION);
      FileWrite(fh, "Screenshot: " + shotName);
      FileWrite(fh, "Shot_Ok: " + (okShot ? "1" : "0"));
      FileWrite(fh, "Shot_Px: " + IntegerToString(shotW) + "x" + IntegerToString(shotH));
      FileWrite(fh, "Chart_ID: " + IntegerToString(ChartID()));
      FileClose(fh);
   }

   //--- the human trail: short, ASCII, one line — the folder is the record, this is the receipt
   DrawStripDiagEmit("[BK-SHOT] id=" + id + " dir=" + leaf +
                     " shot=" + (okShot ? "1" : "0") + " txt=" + (okTxt ? "1" : "0") +
                     " type=" + BaseKnotNodeShort(g_bkBoxes[k].nodeKind) +
                     " h=" + DoubleToString(hPips, 1) +
                     " u=" + DoubleToString(u, 3) +
                     " stop=" + DoubleToString(stopPips, 1) +
                     " off=" + DoubleToString(offPips, 1));
   //--- the flash is drawn AFTER the shot so the receipt is never in the picture
   //--- THE RECEIPT (P-BK-124b): WHAT was filed, in the order a trader reads it - did it land,
   //--- what kind of knot, how tall - and the second the record itself carries, so the label and
   //--- the folder name (`<box id>_<yyyymmdd-hhmmss>`) can be compared at a glance. Latin only,
   //--- for the reason P-TH3-REC-05 wrote down: MT4 does not render Persian in OBJ_LABEL, and a
   //--- receipt a trader cannot read is no receipt.
   //--- `SAVED` is claimed only when BOTH files landed. It used to say "saved" whenever the
   //--- folder existed, so a refused WindowScreenShot (a locked desktop, a minimised terminal)
   //--- still read as a good sample - the one lie a dataset could never recover from.
   MqlDateTime rdt;
   TimeToStruct(TimeCurrent(), rdt);
   string receipt = "";
   if(okShot && okTxt)
      receipt = "SAVED  " + BaseKnotNodeShort(g_bkBoxes[k].nodeKind) +
                " " + (nodeTF > 0 ? BaseKnotTFName(nodeTF) : "?") +
                " " + DoubleToString(hPips, 1) + "p " +
                StringFormat("%02d:%02d:%02d", rdt.hour, rdt.min, rdt.sec);
   else
      receipt = "NOT SAVED  png=" + (okShot ? "1" : "0") + " txt=" + (okTxt ? "1" : "0");
   BaseKnotShotFlash(receipt);
   return true;
}

#endif // BASE_KNOT_SHOT_MQH
