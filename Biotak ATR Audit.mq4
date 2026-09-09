//+------------------------------------------------------------------+
//| Biotak ATR Audit - one-shot diagnostic (NOT product code)        |
//|                                                                  |
//| Run: drag from Navigator -> Scripts onto any chart. Prints       |
//| per-TF iATR legs (13 periods x shift 0/1) + bar counts to the    |
//| Experts log. Send the log + professor's strip screenshot taken   |
//| the SAME minute on the SAME symbol: the legs identify the        |
//| professor's exact ATR recipe (periods / weights / shift).        |
//| No trade calls - safe to run with AutoTrading off.               |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

void OnStart()
{
   string sym = Symbol();
   int digits = (int)MarketInfo(sym, MODE_DIGITS);
   double pt = MarketInfo(sym, MODE_POINT);
   Print("ATR-AUDIT symbol=", sym,
         " digits=", digits,
         " point=", DoubleToString(pt, 8),
         " time=", TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));

   int tfMin[8] = {1, 5, 15, 60, 240, 1440, 10080, 43200};
   string tfName[8] = {"M1", "M5", "M15", "H1", "H4", "D1", "W1", "MN1"};
   int periods[13] = {5, 10, 14, 21, 34, 55, 66, 89, 100, 132, 144, 200, 264};

   for(int t = 0; t < 8; t++)
   {
      int bars = iBars(sym, tfMin[t]);
      string line = "ATR-AUDIT " + tfName[t] + " bars=" + IntegerToString(bars);
      for(int s = 0; s <= 1; s++)
      {
         line += " shift" + IntegerToString(s) + "=[";
         for(int p = 0; p < 13; p++)
         {
            double v = iATR(sym, tfMin[t], periods[p], s);
            if(p > 0) line += ",";
            if(v == EMPTY_VALUE) line += "EMPTY";
            else line += DoubleToString(v, digits);
         }
         line += "]";
      }
      Print(line);
   }
   Print("ATR-AUDIT done.");
}
//+------------------------------------------------------------------+
