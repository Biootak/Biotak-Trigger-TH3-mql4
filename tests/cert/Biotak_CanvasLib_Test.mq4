//+------------------------------------------------------------------+
//| Biotak_CanvasLib_Test.mq4                                        |
//| P-DRAW-50, library half (2026-10-17). The CCanvas MetaQuotes     |
//| installed into this terminal's MQL4 Include tree with its own    |
//| 2026-10-07 update batch must COMPILE for an MQL4 unit - canvas   |
//| engine or nothing. This harness is the certificate: the ex4      |
//| built from it IS the proof (compiled by compile-th3.ps1).        |
//|                                                                  |
//| WHY tests\cert\ AND NOT tests\ ROOT: <Canvas\Canvas.mqh> is an   |
//| angle include, and metaeditor resolves those under               |
//| <include-root>\Include\ - for a repo unit Get-IncludePath hands  |
//| the repo root, which has no Include\. MEASURED 2026-10-17:       |
//| compiled from tests\ => error 106; a byte-identical copy under   |
//| <MQL4>\Scripts\ => 0 errors, 0 warnings, 186 msec, ex4 16,502    |
//| bytes, resolving Canvas.mqh + Files\FileBin.mqh +                |
//| Controls\Rect.mqh from <MQL4>\Include. So the procedure is:      |
//|   copy to <MQL4>\Scripts\ then                                   |
//|   compile-th3.ps1 -SourceFile "...\Scripts\Biotak_CanvasLib_Test.mq4"
//| `-Tests` skips this subfolder on purpose (its sweep is           |
//| Get-ChildItem -Filter *.mq4, no -Recurse, compile-th3.ps1:1986). |
//| It is never run; the run half is tests\Biotak_CanvasProbe.mq4.   |
//+------------------------------------------------------------------+
#property strict
#include <Canvas\Canvas.mqh>

//+------------------------------------------------------------------+
void OnStart()
{
   CCanvas canvas;
   if(!canvas.CreateBitmapLabel("TH3CanvasLibProbe", 0, 0, 64, 64, COLOR_FORMAT_ARGB_NORMALIZE))
      return;
   canvas.Erase(ColorToARGB(clrNONE, 0));
   canvas.FillRectangle(8, 8, 56, 56, ColorToARGB(C'30,144,255', 128));
   canvas.LineAA(0, 0, 63, 63, ColorToARGB(clrWhite, 255));
   canvas.Update();
   canvas.Destroy();
   ObjectDelete(0, "TH3CanvasLibProbe");
}
//+------------------------------------------------------------------+
