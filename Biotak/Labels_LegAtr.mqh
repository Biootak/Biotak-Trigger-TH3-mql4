//+------------------------------------------------------------------+
//| Labels_LegAtr.mqh — P-LEGATR X-dump witness (split owner, §7)    |
//|                                                                  |
//| Labels_A.mqh is grandfathered at 1576 lines and never grows, so  |
//| the leg-ATR witness lives here: the switch state plus live-vs-leg|
//| per plan TF (chart/struct/trig), so an "ON changes nothing"      |
//| report names its anchor and run instead of guessing. On-demand    |
//| only (X hotkey, beside TradePlanDumpNow) — never background.     |
//|                                                                  |
//| Include AFTER Labels_A.mqh (TpxLine's home): MQL4 resolves top-   |
//| down, so this file must see TpxLine, STradePlan and the leg      |
//| reader before it. Wired in Biotak/LabelFunctions.mqh.            |
//+------------------------------------------------------------------+
#ifndef LABELS_LEGATR_MQH
#define LABELS_LEGATR_MQH

void TradePlanLegAtrDump()
{
   STradePlan plan;
   if(!TradePlanComputeLive(Period(), plan)) return;
   double pip = GetCachedPipSize();
   if(!MathIsValidNumber(pip) || IsZero(pip, EPSILON_PRICE)) return;
   string sw = "OFF";
   if(inpUseLegATR) sw = "ON";
   string out[4];
   out[0] = "[LEGATR] switch=" + sw;
   int tfMins[3]; tfMins[0] = plan.chartMin; tfMins[1] = plan.strMin; tfMins[2] = plan.trigMin;
   for(int i = 0; i < 3; i++)
   {
      string role = "trig";
      if(i == 0) role = "chart";
      else if(i == 1) role = "struct";
      ENUM_TIMEFRAMES tf = CompatTF(tfMins[i]);
      double live = CalculateWeightedATR(tf);
      datetime raw = TradePlanLegAnchorRaw(tfMins[i]);
      int run = TradePlanLegRunBars(tfMins[i]);
      double leg = live;
      if(raw > 0) leg = CalculateWeightedATRAt(tf, raw);
      string used = "live";
      if(inpUseLegATR && raw > 0) used = "leg";
      string at = "none";
      if(raw > 0) at = TimeToString(raw, TIME_DATE | TIME_MINUTES);
      out[i + 1] = "[LEGATR] " + role + " TF=" + IntegerToString(tfMins[i])
                 + " live=" + DoubleToString(live / pip, 1) + "p"
                 + " run=" + IntegerToString(run)
                 + " anchor=" + at
                 + " leg=" + DoubleToString(leg / pip, 1) + "p"
                 + " used=" + used;
   }
   for(int i = 0; i < 4; i++) TpxLine(out[i]);
   // The auto-export file is already closed by TradePlanDumpNow (same X press),
   // so append here instead of reopening it: the file stays the reliable read
   // (the journal is a cache, P-DRAW-126) and Print above stays the live one.
   int h = FileOpen(TradePlanExportFileName(), FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h != INVALID_HANDLE)
   {
      FileSeek(h, 0, SEEK_END);
      for(int i = 0; i < 4; i++) FileWriteString(h, out[i] + "\n");
      FileClose(h);
   }
}

#endif // LABELS_LEGATR_MQH
