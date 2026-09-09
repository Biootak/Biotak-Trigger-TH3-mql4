//+------------------------------------------------------------------+
//| ReloadBiotak.mq4 — drops and re-attaches Biotak Trigger TH3     |
//| on every chart that currently has it, then deletes itself.       |
//| Run once from MT4 Navigator > Scripts (drag to ANY chart).       |
//+------------------------------------------------------------------+
#property strict
#property show_inputs

input bool inp_ReloadAll = true; // Reload on ALL open charts (not just this one)

void OnStart()
{
   string indName = "BiotakProject\\Biotak Trigger TH3";

   // Iterate all open charts
   long chartId = ChartFirst();
   int  reloaded = 0;

   while(chartId >= 0)
   {
      int total = ChartIndicatorsTotal(chartId, 0); // main window subwindow 0
      for(int i = total - 1; i >= 0; i--)
      {
         string name = ChartIndicatorName(chartId, 0, i);
         // Match by short name prefix (handles both Full and Lite)
         if(StringFind(name, "Biotak Trigger TH3") >= 0)
         {
            // Save current chart symbol/period for the log
            string sym = ChartSymbol(chartId);
            int    per = (int)ChartPeriod(chartId);

            // Remove — MT4 unloads the ex4 from memory for this chart
            ChartIndicatorDelete(chartId, 0, name);
            ChartRedraw(chartId);
            Sleep(200);

            // Re-add — MT4 re-reads the .ex4 file from disk (picks up new build)
            // ChartIndicatorAdd requires iCustom-style name
            // Use full path relative to MQL4/Indicators
            long h = ChartIndicatorAdd(chartId, 0,
                        iCustom(sym, per, indName));
            if(h >= 0) reloaded++;

            ChartRedraw(chartId);
            break; // only one instance per chart expected
         }
      }

      if(!inp_ReloadAll) break;
      chartId = ChartNext(chartId);
   }

   string msg = "ReloadBiotak: reloaded " + IntegerToString(reloaded) + " chart(s).";
   Print(msg);
   Alert(msg);
}
