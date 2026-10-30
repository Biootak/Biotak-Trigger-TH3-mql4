//+------------------------------------------------------------------+
//| Labels_Countdown.mqh - the live price + close-in countdown tag   |
//| (split owner, contract 7).                                       |
//|                                                                  |
//| Labels_A.mqh sits at its grandfathered baseline and never grows, |
//| so the countdown surface lives here: the close-in text, its own  |
//| object name, the switch, the hit test and the painter. It is its |
//| own LAYER (own switch, colour, size and gap; a name free of      |
//| "ATR_" so the periodic janitor never eats it) - an owner, not a  |
//| helper of the card.                                              |
//|                                                                  |
//| Include AFTER Labels_A.mqh (InitATRChartLabel / LblMark /        |
//| SetLabelFont are its helpers there). Wired in LabelFunctions.mqh.|
//+------------------------------------------------------------------+
#ifndef LABELS_COUNTDOWN_MQH
#define LABELS_COUNTDOWN_MQH

//--- The trade card's face text (moved here from Labels_A, P-SIZE-SPLIT-LBL). -----------
// The card's two measured rows - ONE text owner each (P-LBL-08). The layout has
// to MEASURE a row before it can centre it, and the row it draws has to be the
// same string: two StringFormats of the same thing is how a card ends up
// centred on a width it never draws (P-UI-30's lesson on the chart side).
string TradePlanTPRowText(const STradePlan &plan)
{
   // TWO spaces between the tokens (2026-09-14 user: "the bottom row reads
   // stuck together"). The tokens themselves are the professor's format.
   // P-TP4 (2026-10-19): FOUR targets, and `#SL` left this row. The four legs are
   // the Eng multiples - `Pricicle` is 5 x Eng, NOT the stop (the witness has it).
   return StringFormat("#TP1:+%d  #TP2:+%d  #TP3:+%d  #TP4:+%d",
                       plan.tp1, plan.tp2, plan.tp3, plan.tp4);
}

// ONE leg formatter for the two 0.1-pip legs (P-TRADEPLAN-DEC, user 2026-09-16):
// a leg with no tenth prints as the INTEGER the professor's own card shows
// (`Hunter SL: 44`, `Eng.SL: 600`), and a leg that carries one prints it —
// XAUUSD M15 `Eng.SL: 16.5` (his unrounded value is 16.515, his card rounds it to
// 17), EURUSD M1 `Eng.SL: 0.3`. The card's width is MEASURED from this same string
// (TRexTradeCardLayout), so the variable width is what the centring already
// expects. The [SNAP]/[TRADEPLAN] logs print DoubleToString(x, 1) instead: a
// diagnostic shows the value the engine used, not the card's face.
string TradePlanLegText(const double v)
{
   if(MathAbs(v - MathRound(v)) < 0.05) return IntegerToString((int)MathRound(v));
   return DoubleToString(v, 1);
}

// P-TP4 (2026-10-19): the card's upper row is FOUR legs now, in the master's
// own order and with his own names:
//   `TRex: 4  Trigger: 10  Pricicle: 19  Classic: 46`
// What each one is:
//   TRex     = plan.eng      (was `Eng.SL:`)   — the knot's risk, 0.1 pip
//   Trigger  = plan.hunter   (was `Hunter SL:`) — the ETR/CTR/OTR entry, 0.1 pip
//   Pricicle = plan.pricicle (was `#SL:-n` in the target row) — whole pips
//   Classic  = plan.classic  (new)                            — whole pips
// The two 0.1-pip legs keep TradePlanLegText (P-TRADEPLAN-DEC, user 2026-09-16);
// the two new legs are whole pips like SL/TP/SB.
string TradePlanLegsText(const STradePlan &plan)
{
   return "TRex: " + TradePlanLegText(plan.eng)
        + "  Trigger: " + TradePlanLegText(plan.hunter)
        + "  Pricicle: " + IntegerToString(plan.pricicle)
        + "  Classic: " + IntegerToString(plan.classic);
}

// P-ANCHOR-CARD (2026-10-28) - THE CARD IS A LABEL, SO IT WEARS THE LABEL'S ONE BAR.
//
// MEASURED 2026-10-28 on the user's XAUUSD M15 chart with LAST OBJECT armed at 2026.10.22
// 17:00: the card printed `82.0` above `TRex 12.8 | Trigger 34.3 | Pricicle 64 | Classic
// 154`. `82.0` is the AS-OF M15 ATR (GetATRForTimeframe -> CalcAnchorAt), and 82.0 / 4.266666
// = 19.2, not 12.8: the four legs had been computed on the LIVE ATR (12.8 x 4.266666 = 54.6).
// ONE card, TWO moments - its superscript as-of, its legs live - which is what the user's
// report ("these do not update") was pointing at. The fence is untouched: `TradePlanFormulas`
// still never reads the switch itself (P-ANCHOR-LAST), the card HANDS it the bar as an
// argument, so only the TEXT moves and every drawn level stays on its own anchor.
//
// The range below is the other half of the same moment: the spread row read the LIVE structure
// bar's high-low and divided it by the AS-OF ATR (his `111.9 (136.5%)` = 111.9 / 82.0), a
// percentage of two different bars. Reading the range at the anchor's bar makes the pair one
// measurement again.
//
// The answer is the TrueRange, or -1.0 when the bar has no usable prices - a sentinel, not 0.0,
// so a genuinely FLAT bar still prints `0.0 (0.0%)` exactly as it did before this move (the old
// caller's own `hi > 0 && lo > 0` gate).
double TradePlanStructureRange(const ENUM_TIMEFRAMES stf)
{
   if(stf == PERIOD_CURRENT) return -1.0;
   datetime fa = CalcAnchorAt();
   int shift = 0;
   if(fa > 0)
   {
      shift = iBarShift(Symbol(), stf, fa, false);   // the bar the ATR was read on, never a shift
      if(shift < 0) shift = 0;                       // not loaded yet: the live bar, the old read
   }
   double hi = iHigh(NULL, stf, shift), lo = iLow(NULL, stf, shift), pc = iClose(NULL, stf, shift + 1);
   if(hi <= 0.0 || lo <= 0.0 || hi < lo) return -1.0;
   double rng = hi - lo;
   if(pc > 0.0) rng = MathMax(rng, MathMax(MathAbs(hi - pc), MathAbs(lo - pc)));
   return rng;
}

// The card's own witness has to say WHICH bar it read: an as-of card and a live one print the
// same field names, and a reader of `tradeplan-witness-<symbol>.log` cannot tell them apart.
string TradePlanAnchorText()
{
   datetime fa = CalcAnchorAt();
   return (fa > 0 ? TimeToString(fa, TIME_DATE | TIME_MINUTES) : (string)"live");
}

// Countdown to the current chart bar close. Default = the long corner form
// ("Close in : 22d 12h 32m 13s"); compact = the live-candle tag form with no
// prefix and no spaces ("22d12h32m13s"). Units below the leading non-zero one
// are skipped either way (H1 shows "17m 51s" / "17m51s").
string TradePlanCloseInText(const bool compact = false)
{
   datetime bt = iTime(Symbol(), Period(), 0);
   if(bt <= 0) return compact ? "--" : "Close in : --";
   long left = (long)(bt + PeriodSeconds() - TimeCurrent());
   if(left < 0) left = 0;
   long d = left / 86400; left -= d * 86400;
   long h = left / 3600;  left -= h * 3600;
   long m = left / 60;
   long s = left - m * 60;
   string sep = compact ? "" : " ";
   string t = "";
   if(d > 0) t = t + IntegerToString(d) + "d" + sep;
   if(d > 0 || h > 0) t = t + IntegerToString(h) + "h" + sep;
   if(d > 0 || h > 0 || m > 0) t = t + IntegerToString(m) + "m" + sep;
   t = t + IntegerToString(s) + "s";
   return compact ? t : ("Close in : " + t);
}

//+------------------------------------------------------------------+
//| Live countdown tag — its OWN layer (2026-09-11, user request):     |
//| own switch (inpShowLiveCountdown), own color/size/gap, and a name  |
//| deliberately free of "ATR_" so the periodic object janitor (which  |
//| hides every "ATR_" object while the ATR block is off) never eats   |
//| it. Turn the ATR labels off and the countdown stays.               |
//+------------------------------------------------------------------+
string LiveCountdownObjName()
{
   return GetLevelObjectPrefix() + "LBL_" + LIVE_COUNTDOWN_NAME;
}

bool LiveCountdownEnabled()
{
   return (inpShowLiveCountdown && !IsIndicatorHidden());
}
// P-PERF-51: per-call dirtiness of the countdown tag. CreateLivePriceCountdown
// sets it: true when it wrote (or removed) anything, false when a still second
// compared equal and cost reads only. The 1 Hz caller repaints only on true.
static bool s_cdDirty = false;

// Paints the tag when its own switch is on, removes it (plus the retired
// "...ATR_Trade_Current_CloseIn" of older builds) when it is off.
void RefreshLiveCountdown()
{
   string nm = LiveCountdownObjName();
   // P-PERF-172 (2026-10-30): A SWITCHED-OFF TAG WRITES NOTHING, SO IT MUST NOT
   // ASK FOR A FRAME. `s_cdDirty` is the 1 Hz caller's repaint gate
   // (`TradePlanLiveTick` -> `if(s_cdDirty) ThrottledChartRedraw()`), and it
   // used to be raised BEFORE the switch below was read, on the assumption
   // that the two deletes are always "changes". They are changes only when the
   // object is really there: on a chart where the tag was already removed both
   // `ObjectDelete` calls are no-ops, and the flag then bought a FULL ChartRedraw
   // of every object on the chart once per second - 60 a minute, 3,600 an hour -
   // for a label nothing draws. MEASURED by construction: the 1 Hz gate at
   // Labels_A.mqh:1378 is 1000 ms and CHART_REDRAW_THROTTLE_MS is 100, so the
   // throttle never swallows it; the branch is reached every second while
   // `inpShowLiveCountdown` is off or the indicator is F-muted.
   // The flag now answers its own question - did a delete really delete? - so
   // the steady case costs two probes, zero writes, zero frames.
   s_cdDirty = false;
   if(!LiveCountdownEnabled())
   {
      if(ObjectFind(0, nm) >= 0) { ObjectDelete(0, nm); s_cdDirty = true; }
      string legacy = GetLevelObjectPrefix() + "LBL_" + LIVE_COUNTDOWN_LEGACY_NAME;
      if(ObjectFind(0, legacy) >= 0) { ObjectDelete(0, legacy); s_cdDirty = true; }
      g_cdTagValid = false;
      return;
   }
   CreateLivePriceCountdown(nm);
}

// Chart click router: is this point on the tag's last painted rect?
bool LiveCountdownPointInside(const int mx, const int my)
{
   if(!g_cdTagValid || !LiveCountdownEnabled()) return false;
   int h = (g_cdTagH > 0) ? g_cdTagH : (inpFontSize + 4);
   return (mx >= g_cdTagX - 2 && mx <= g_cdTagX + g_cdTagW + 2 &&
           my >= g_cdTagY - 2 && my <= g_cdTagY + h + 2);
}

//+------------------------------------------------------------------+
//| Bar-close countdown tag beside the LIVE CANDLE, at the LIVE PRICE.|
//| Both axes are derived in pixels every refresh: Y from               |
//| ChartTimePriceToXY(quote) (quote = bid/ask mid) so the text sits on |
//| the level the terminal's price lines are drawn at, X from the live |
//| bar's right edge + a few px, so the tag hugs the candle and moves   |
//| with it as the price runs. When the right side runs out of room it  |
//| flips to the candle's left instead of sliding under the price       |
//| scale. Cost per call = 2-3 ChartTimePriceToXY + a handful of         |
//| property sets, cheap enough for the 1 Hz path in TradePlanLiveTick  |
//| (P-PERF-01) and for the scroll/zoom hook.                           |
//+------------------------------------------------------------------+
bool CreateLivePriceCountdown(const string name)
{
   LblMark(name);   // P-PERF-38g: produced by this pass, even on the hidden/clean exits below
   s_cdDirty = true;   // the clean-skip below is the only path that clears it
   // Own switch only — never the ATR block's flags (that is the whole point).
   if(!LiveCountdownEnabled())
   {
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      g_cdTagValid = false;
      return false;
   }

   double point = GetCachedPoint();
   if(IsZero(point, EPSILON_PRICE)) { s_cdDirty = false; return false; }
   datetime bt = iTime(Symbol(), Period(), 0);
   if(bt <= 0) { s_cdDirty = false; return false; }

   // The quote the tag rides: the bid/ask mid, so it sits exactly on the level
   // the terminal's own price lines are drawn at. Bar close covers the very
   // first ticks of a chart, before a quote exists.
   double bid = MarketInfo(GetCachedSymbol(), MODE_BID);
   double ask = MarketInfo(GetCachedSymbol(), MODE_ASK);
   double price = 0.0;
   if(bid > 0.0 && ask > 0.0) price = (bid + ask) / 2.0;
   else if(bid > 0.0)         price = bid;
   else                       price = iClose(Symbol(), Period(), 0);
   if(price <= 0.0) { s_cdDirty = false; return false; }

   // Bar-0 pixel X (its LEFT edge) + the quote's pixel Y. A chart scrolled
   // away from the live bar has no candle to sit next to, so park the tag
   // rather than draw it at a made-up level — the next refresh brings it back.
   int barX = 0, priceY = 0;
   if(!ChartTimePriceToXY(0, 0, bt, price, barX, priceY)) barX = -1;
   if(barX < 0 || priceY < 0)
   {
      if(ObjectFind(0, name) >= 0)
         ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      g_cdTagValid = false;   // no stale rect for the click hit-test
      return false;
   }

   // Bar width in pixels comes from the previous bar's X, so the gap scales
   // with the zoom instead of being a fixed guess.
   int prevX = 0, prevY = 0;
   int barPx = 8;   // safe default for a chart that cannot resolve bar 1
   if(ChartTimePriceToXY(0, 0, bt - PeriodSeconds(), price, prevX, prevY) && barX > prevX)
      barPx = barX - prevX;

   string text = TradePlanCloseInText(true);
   // Own size (0 = follow the shared label size) — resolved BEFORE measuring:
   // the width estimate is cached for inpFontSize, so scale it to the
   // RENDERED size (P-UI-26/F17), or the edge-flip and click rect drift.
   int fsz = (inpCountdownFontSize > 0) ? inpCountdownFontSize : inpFontSize;
   if(fsz <= 0) fsz = 8;
   int tagW = (int)(CalculateTextWidth(text) * fsz / MathMax(1, inpFontSize));
   // Hand-clamped on purpose: ClampInt() lives in BiotakKit.mqh, which this
   // file (included earlier) cannot see in the Lite build (P-ARCH-02).
   int gap = inpCountdownGapPx;                     // "یک کم فاصله"
   if(gap < 0) gap = 0;
   if(gap > 40) gap = 40;
   int x    = barX + barPx + gap;                   // just off the candle's right
   int cw   = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   // The right margin the corner labels already live in is the boundary the tag
   // may not cross (beyond it sits the price scale).
   int rightLimit = (cw > 0) ? (cw - MathMax(8, inpLabelsMarginLeft)) : 0;
   if(cw > 0 && x + tagW > rightLimit)
   {
      x = barX - tagW - gap;                      // no room right → hug its left
      if(x < 4) x = 4;
   }

   // Earlier builds drew this same name in the corner and on the candle as an
   // OBJ_TEXT; a same-name ObjectCreate of another type does not replace the
   // old object, so retire it first.
   if(ObjectFind(0, name) >= 0 && ObjectType(name) != OBJ_LABEL)
      ObjectDelete(0, name);
   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) { s_cdDirty = false; return false; }
      ObjectSetString(0, name, OBJPROP_TEXT, "");   // no default "Label" text
   }

   // Own color. Center the row on the quote level (Y is measured from the
   // top edge here); clamp the bottom too so the tag never sinks under the
   // date scale when price hugs the chart's lower edge (P-UI-26/L4).
   int chTag = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   if(chTag <= 0) chTag = 1080;
   int xLeft = MathMax(4, x);
   int yTop = MathMax(2, MathMin(priceY - fsz / 2, chTag - (fsz + 2) - 20));

   // P-PERF-51: compare first. A still second (same quote, same seats, same
   // ink) costs ~12 reads and zero writes; the caller repaints only on dirty.
   if(g_cdTagValid && ObjectFind(0, name) >= 0
      && ObjectGetString(0, name, OBJPROP_FONT) == inpFontName
      && ObjectGetInteger(0, name, OBJPROP_FONTSIZE) == fsz
      && ObjectGetInteger(0, name, OBJPROP_CORNER) == CORNER_LEFT_UPPER
      && ObjectGetInteger(0, name, OBJPROP_ANCHOR) == ANCHOR_LEFT_UPPER
      && ObjectGetInteger(0, name, OBJPROP_SELECTABLE) == false
      && ObjectGetInteger(0, name, OBJPROP_HIDDEN) == false
      && ObjectGetInteger(0, name, OBJPROP_ZORDER) == Z_CHART_LABEL
      && ObjectGetString(0, name, OBJPROP_TEXT) == text
      && ObjectGetInteger(0, name, OBJPROP_COLOR) == inpCountdownColor
      && ObjectGetInteger(0, name, OBJPROP_XDISTANCE) == xLeft
      && ObjectGetInteger(0, name, OBJPROP_YDISTANCE) == yTop
      && ObjectGetInteger(0, name, OBJPROP_TIMEFRAMES) == OBJ_ALL_PERIODS)
   {
      s_cdDirty = false;
      return true;
   }

   SetLabelFont(name);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fsz);   // own size over the shared one
   InitATRChartLabel(name, CORNER_LEFT_UPPER, ANCHOR_LEFT_UPPER);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, inpCountdownColor);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, xLeft);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, yTop);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);

   // Remember the painted rect: the chart click router hit-tests it to open the
   // settings card. The object itself stays UNSELECTABLE so it can never be
   // grabbed/dragged by accident.
   g_cdTagX = xLeft; g_cdTagY = yTop; g_cdTagW = tagW; g_cdTagH = fsz + 2;
   g_cdTagValid = true;
   return true;
}

#endif // LABELS_COUNTDOWN_MQH
