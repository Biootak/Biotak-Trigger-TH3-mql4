//+------------------------------------------------------------------+
//| Biotak_CanvasProbe.mq4                                           |
//| P-DRAW-50 probe. v1 (script) 2026-09-26 (commit 57711c3);        |
//| v2 (indicator) 2026-10-17. ONE question, and it is the question  |
//| every modern panel skin rests on: does MT4 composite a bitmap    |
//| label that was CREATED AT RUNTIME (ResourceCreate +              |
//| COLOR_FORMAT_ARGB_NORMALIZE) with its per-pixel alpha, and what  |
//| does one 312x384 build cost on the weakest machine?              |
//|                                                                  |
//| Deliberately includes NOTHING from Biotak/: this measures the    |
//| PLATFORM, not the product, so a product bug cannot mask it.      |
//| No #resource either, so it needs no tests\Files junction         |
//| (P-BUILD-03).                                                    |
//|                                                                  |
//| WHY AN INDICATOR (v2): a script unloads the moment OnStart       |
//| returns, and a runtime resource dies with its program - the      |
//| plate would go blank before the user could look at it and read   |
//| as "alpha failed". An indicator stays attached: the plate lives  |
//| until the instrument is removed, and OnDeinit purges object +    |
//| resource in one sweep. No Sleep() anywhere (MQL4 forbids it in   |
//| indicators).                                                     |
//|                                                                  |
//| WITNESS (never Print - P-DRAW-126): <data>\MQL4\Files\           |
//| biotak_canvasprobe.txt, flushed per line, FILE_SHARE_READ        |
//| (P-LOG-3). EVIDENCE: ChartScreenShot -> <data>\MQL4\Files\       |
//| biotak_canvasprobe.png - the terminal's own pixels, so the       |
//| fillets and the ramp can be MEASURED, not just looked at.        |
//|                                                                  |
//| HOW TO RUN: drag onto any chart from the Navigator. The plate    |
//| sits at (40,40) above the bottom-left corner, 312x384.           |
//| PASS: rounded corners with the chart visible through them, a     |
//| smooth blue ramp, four gold patches of clearly different         |
//| strength. FAIL: black square corners or a flat ramp (alpha was   |
//| ignored). Remove the indicator to clean up.                      |
//+------------------------------------------------------------------+
#property strict
#property version "2.00"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots 0

#define PROBE_W    312        // = DSTRIP_GEAR_W / PNL narrow content box
#define PROBE_H    384        // = DSTRIP_GEAR_BASE_H + 5 * ROW_H (a real panel)
#define PROBE_RAD   14        // = PNL_RAD in tools/gen-th3-icons.js
#define PROBE_SUB    4        // sub-pixel samples per axis, corner pixels only
#define PROBE_OBJ  "TH3ProbePlate"
#define PROBE_LOG  "biotak_canvasprobe.txt"
#define PROBE_PNG  "biotak_canvasprobe.png"

// Plate body #171C25 at the competitor's own 0.92, and the four ladder
// levels the panel already ships (0 / 30 / 60 / 90 %).
#define PROBE_PLATE_A 235
#define PROBE_LADDER  4

uint   g_px[];
string g_res = "th3probe";
double g_buildMs = 0.0;
int    g_log = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| The witness channel: flushed per line, shared for reading         |
//| (P-LOG-3). A Print here would sit in MT4's RAM journal (P-DRAW-126).|
//+------------------------------------------------------------------+
void ProbeEmit(const string line)
{
   if(g_log == INVALID_HANDLE) return;
   FileWrite(g_log, line);
   FileFlush(g_log);
}

//+------------------------------------------------------------------+
uint ProbePx(const int a, const int r, const int g, const int b)
{
   return ((uint)a << 24) | ((uint)r << 16) | ((uint)g << 8) | (uint)b;
}

// Source-over one pixel; dst = 0 means "nothing there yet".
uint ProbeOver(const uint dst, const uint src)
{
   const double sa = (double)((src >> 24) & 0xFF) / 255.0;
   if(sa <= 0.0) return dst;
   const double da = (double)((dst >> 24) & 0xFF) / 255.0;
   const double oa = sa + da * (1.0 - sa);
   if(oa <= 0.0) return 0;
   const int channels[3] = {16, 8, 0};
   uint out = ((uint)(int)(oa * 255.0 + 0.5)) << 24;
   for(int i = 0; i < 3; i++)
   {
      const double s = (double)((src >> channels[i]) & 0xFF) / 255.0;
      const double d = (double)((dst >> channels[i]) & 0xFF) / 255.0;
      out |= (uint)(int)((s * sa + d * da * (1.0 - sa)) / oa * 255.0 + 0.5) << (16 - 8 * i);
   }
   return out;
}

//+------------------------------------------------------------------+
//| Coverage of one pixel: 1.0 inside, 0.0 outside, and 4x4 sub-pixel |
//| samples ONLY where the fillet lives (the box's own edge pixels).   |
//+------------------------------------------------------------------+
double ProbeCover(const double px, const double py, const int w, const int h, const int rad)
{
   const double x0 = 0.0, y0 = 0.0, x1 = (double)w, y1 = (double)h;
   const double cxL = x0 + rad, cxR = x1 - rad, cyT = y0 + rad, cyB = y1 - rad;
   double cx = -1.0, cy = -1.0;
   if(px < cxL && py < cyT)      { cx = cxL; cy = cyT; }
   else if(px > cxR && py < cyT) { cx = cxR; cy = cyT; }
   else if(px < cxL && py > cyB) { cx = cxL; cy = cyB; }
   else if(px > cxR && py > cyB) { cx = cxR; cy = cyB; }
   if(cx < 0.0)
   {
      if(px < x0 || px > x1 || py < y0 || py > y1) return 0.0;
      return 1.0;
   }
   const double r2 = (double)rad * rad, step = 1.0 / (double)PROBE_SUB;
   const double dx = px - cx, dy = py - cy, dist = MathSqrt(dx * dx + dy * dy);
   if(dist <= rad - 1.0) return 1.0;
   if(dist > rad + 1.0) return 0.0;
   int inside = 0;
   for(int sy = 0; sy < PROBE_SUB; sy++)
      for(int sx = 0; sx < PROBE_SUB; sx++)
      {
         const double sdx = dx - 0.5 + (sx + 0.5) * step;
         const double sdy = dy - 0.5 + (sy + 0.5) * step;
         if(sdx * sdx + sdy * sdy <= r2) inside++;
      }
   return (double)inside / (double)(PROBE_SUB * PROBE_SUB);
}

//+------------------------------------------------------------------+
//| Paint the plate into the buffer. Body = one flat fill, fillets =   |
//| sub-pixel, then the alpha ladder and the ramp, so a missing alpha  |
//| channel shows as a hard staircase instead of a curve.              |
//+------------------------------------------------------------------+
void ProbePaint(const int plateA)
{
   ArrayInitialize(g_px, 0);
   for(int y = 0; y < PROBE_H; y++)
      for(int x = 0; x < PROBE_W; x++)
      {
         const double cov = ProbeCover((double)x + 0.5, (double)y + 0.5, PROBE_W, PROBE_H, PROBE_RAD);
         if(cov <= 0.0) continue;
         g_px[y * PROBE_W + x] = ProbePx((int)(plateA * cov + 0.5), 0x17, 0x1C, 0x25);
      }
   // 1px hairline, inset 1px, white at alpha 20 = the modern rim.
   const uint hair = ProbePx(20, 0xFF, 0xFF, 0xFF);
   for(int x = PROBE_RAD; x < PROBE_W - PROBE_RAD; x++)
   {
      g_px[1 * PROBE_W + x] = ProbeOver(g_px[1 * PROBE_W + x], hair);
      g_px[(PROBE_H - 2) * PROBE_W + x] = ProbeOver(g_px[(PROBE_H - 2) * PROBE_W + x], hair);
   }
   for(int y = PROBE_RAD; y < PROBE_H - PROBE_RAD; y++)
   {
      g_px[y * PROBE_W + 1] = ProbeOver(g_px[y * PROBE_W + 1], hair);
      g_px[y * PROBE_W + PROBE_W - 2] = ProbeOver(g_px[y * PROBE_W + PROBE_W - 2], hair);
   }
   // Header and footer bands at their real heights (56 / 42) and the
   // seam a flat baked plate cannot move: these three are the whole test
   // of "any radius, any alpha, at any size".
   for(int y = 0; y < 56; y++)
      for(int x = 0; x < PROBE_W; x++)
         if((g_px[y * PROBE_W + x] >> 24) > 0)
            g_px[y * PROBE_W + x] = ProbePx(plateA, 0x1D, 0x22, 0x2C);
   for(int y = PROBE_H - 42; y < PROBE_H; y++)
      for(int x = 0; x < PROBE_W; x++)
         if((g_px[y * PROBE_W + x] >> 24) > 0)
            g_px[y * PROBE_W + x] = ProbePx(plateA, 0x12, 0x16, 0x1D);
   // The ladder: the SAME colour at the panel's four levels, as patches.
   const int px0 = 20, py0 = 96, pw = 60, ph = 40, gap = 14;
   const int levels[PROBE_LADDER] = {255, 179, 102, 26}; // 0 / 30 / 60 / 90 %
   for(int i = 0; i < PROBE_LADDER; i++)
      for(int y = 0; y < ph; y++)
         for(int x = 0; x < pw; x++)
         {
            const int dx = px0 + i * (pw + gap) + x, dy = py0 + y;
            if(dx >= PROBE_W || dy >= PROBE_H) continue;
            g_px[dy * PROBE_W + dx] = ProbePx(levels[i], 0xFF, 0xC2, 0x47);
         }
   // The ramp: alpha 0 -> 255 across one band. A smooth fade means the
   // channel is REAL; a hard edge means it was flattened.
   for(int y = 0; y < 46; y++)
      for(int x = 0; x < PROBE_W - 40; x++)
      {
         const int dx = 20 + x, dy = 170 + y;
         if(dx >= PROBE_W || dy >= PROBE_H) continue;
         const int a = (int)(255.0 * (double)x / (double)(PROBE_W - 40) + 0.5);
         g_px[dy * PROBE_W + dx] = ProbePx(a, 0x4C, 0x8D, 0xFF);
      }
}

//+------------------------------------------------------------------+
//| Round-trip: read the resource back so the alpha byte is PROVEN,    |
//| not assumed. Returns the alpha of the ladder's first patch.        |
//+------------------------------------------------------------------+
int ProbeReadBack()
{
   uint back[], rw = 0, rh = 0;
   ResetLastError();
   if(!ResourceReadImage("::" + g_res, back, rw, rh))
   {
      ProbeEmit(StringFormat("[PROBE] readback FAILED err=%d", GetLastError()));
      return -1;
   }
   const int idx = (96 + 20) * (int)rw + 20;
   if(idx < 0 || idx >= ArraySize(back))
   {
      ProbeEmit(StringFormat("[PROBE] readback size mismatch %dx%d", (int)rw, (int)rh));
      return -1;
   }
   const int a = (int)((back[idx] >> 24) & 0xFF);
   ProbeEmit(StringFormat("[PROBE] readback %dx%d, ladder patch A=%d (wrote 255)", (int)rw, (int)rh, a));
   ArrayFree(back);
   return a;
}

//+------------------------------------------------------------------+
//| The terminal's own pixels, for measuring the verdict later.        |
//+------------------------------------------------------------------+
void ProbeShoot()
{
   ChartRedraw(0);
   const int w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   const int h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   ResetLastError();
   const bool ok = ChartScreenShot(0, PROBE_PNG, w, h, ALIGN_LEFT);
   ProbeEmit(StringFormat("[PROBE] screenshot %s %dx%d err=%d", ok ? "OK" : "FALSE", w, h, GetLastError()));
}

//+------------------------------------------------------------------+
void ProbeRun()
{
   g_res = "th3probe_" + IntegerToString((int)ChartID());
   g_log = FileOpen(PROBE_LOG, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   ProbeEmit(StringFormat("[PROBE] start: %dx%d, radius %d, plate alpha %d, resource '%s'",
                          PROBE_W, PROBE_H, PROBE_RAD, PROBE_PLATE_A, g_res));
   ProbeEmit("[PROBE] env: sym=" + Symbol() + " tf=" + IntegerToString(_Period) +
             " corner=LEFT_LOWER x=40 y=40");

   ArrayResize(g_px, PROBE_W * PROBE_H);
   const ulong t0 = GetMicrosecondCount();
   ProbePaint(PROBE_PLATE_A);
   const ulong t1 = GetMicrosecondCount();
   ProbePaint(PROBE_PLATE_A);
   const ulong t2 = GetMicrosecondCount();
   g_buildMs = (double)(t2 - t1) / 1000.0;
   const double nsPerPx = (double)(t2 - t1) * 1000.0 / (double)(PROBE_W * PROBE_H);
   ProbeEmit(StringFormat("[PROBE] build: cold %.2f ms, warm %.2f ms => %.1f ns/px",
                          (double)(t1 - t0) / 1000.0, g_buildMs, nsPerPx));
   // The honest comparison: a 4x supersample of the WHOLE box, not just
   // its fillets. Extrapolated from the measured ns/px (never run here -
   // 1.9M pixels at this rate would wedge the terminal).
   ProbeEmit(StringFormat("[PROBE] ESTIMATE: full 4x supersample body = %.0f ms (312*384*16 = %d px)",
                          nsPerPx * (double)PROBE_W * (double)PROBE_H * 16.0 / 1000000.0,
                          PROBE_W * PROBE_H * 16));

   ResetLastError();
   ResourceFree("::" + g_res);
   ResetLastError();
   const ulong t3 = GetMicrosecondCount();
   const bool ok = ResourceCreate("::" + g_res, g_px, PROBE_W, PROBE_H, 0, 0,
                                  PROBE_W, COLOR_FORMAT_ARGB_NORMALIZE);
   const ulong t4 = GetMicrosecondCount();
   ProbeEmit(StringFormat("[PROBE] ResourceCreate: %s err=%d in %.3f ms",
                          ok ? "OK" : "FALSE", GetLastError(), (double)(t4 - t3) / 1000.0));
   if(!ok) return;

   const int readA = ProbeReadBack();

   ObjectDelete(0, PROBE_OBJ);
   ResetLastError();
   const bool made = ObjectCreate(0, PROBE_OBJ, OBJ_BITMAP_LABEL, 0, 0, 0);
   if(!made)
   {
      ProbeEmit(StringFormat("[PROBE] ObjectCreate FAILED err=%d", GetLastError()));
      return;
   }
   ObjectSetInteger(0, PROBE_OBJ, OBJPROP_CORNER, CORNER_LEFT_LOWER);
   ObjectSetInteger(0, PROBE_OBJ, OBJPROP_XDISTANCE, 40);
   ObjectSetInteger(0, PROBE_OBJ, OBJPROP_YDISTANCE, 40);
   ObjectSetInteger(0, PROBE_OBJ, OBJPROP_XSIZE, PROBE_W);
   ObjectSetInteger(0, PROBE_OBJ, OBJPROP_YSIZE, PROBE_H);
   ObjectSetInteger(0, PROBE_OBJ, OBJPROP_BACK, false);
   ObjectSetInteger(0, PROBE_OBJ, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, PROBE_OBJ, OBJPROP_ZORDER, 1000);
   ResetLastError();
   const bool bound = ObjectSetString(0, PROBE_OBJ, OBJPROP_BMPFILE, 0, "::" + g_res);
   ObjectSetString(0, PROBE_OBJ, OBJPROP_BMPFILE, 1, "::" + g_res);
   ProbeEmit(StringFormat("[PROBE] BMPFILE bind: %s err=%d, XSIZE reads %d, YSIZE %d",
                          bound ? "OK" : "FALSE", GetLastError(),
                          (int)ObjectGetInteger(0, PROBE_OBJ, OBJPROP_XSIZE),
                          (int)ObjectGetInteger(0, PROBE_OBJ, OBJPROP_YSIZE)));

   ProbeEmit("[PROBE] NOW LOOK at the plate. Pass = rounded corners with the");
   ProbeEmit("[PROBE]   chart visible through them, a smooth blue ramp, and four");
   ProbeEmit("[PROBE]   gold patches of clearly different strength. Fail = black");
   ProbeEmit("[PROBE]   square corners or a flat ramp (alpha was ignored).");
   ProbeEmit("[PROBE] readback alpha A=" + IntegerToString(readA) + " (255 = the resource kept it)");
   ProbeEmit("[PROBE] done. Remove: right-click > Indicators List > Biotak_CanvasProbe.");

   ProbeShoot();
   FileClose(g_log);
   g_log = INVALID_HANDLE;
}

//+------------------------------------------------------------------+
int OnInit()
{
   ProbeRun();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   return(rates_total);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectDelete(0, PROBE_OBJ);
   ResourceFree("::" + g_res);
}
//+------------------------------------------------------------------+
