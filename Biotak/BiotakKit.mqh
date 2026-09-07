//+------------------------------------------------------------------+
//|                                              BiotakKit.mqh     |
//|  UI support module for the Biotak Trigger TH3 circular menu:     |
//|    · REFRESH_* flags + ApplyRefreshFlags dispatcher              |
//|    · shared UI state (g_UI / GetGVName / panel geometry)         |
//|    · palette color kinds + factory default colors                |
//|    · wiring to RuntimeSettings.mqh (persistence owner)          |
//|  (No Biotak drawing — the panels edit THIS indicator's own     |
//|   runtime globals, which the base logic consumes via macros.)    |
//+------------------------------------------------------------------+
#ifndef BIOTAK_KIT_MQH
#define BIOTAK_KIT_MQH

#property strict

//==============================================================================
// REFRESH FLAGS — OR-able; returned by the menu/panels, consumed by
// RefreshDisplay(). REFRESH_ALL = every indicator subsystem except HTF.
//==============================================================================
#define REFRESH_NONE    0
#define REFRESH_BUFFERS 1    // line style/width/visibility changed → redraw
#define REFRESH_RECALC  2    // periods/steps/factor changed → recompute levels
#define REFRESH_LABELS  4    // ATR/TH label layout changed
#define REFRESH_HTF     8    // HTF candles changed
#define REFRESH_TH3     16   // TH3 tool settings changed
#define REFRESH_ALL     23   // BUFFERS|RECALC|LABELS|TH3

//==============================================================================
// Small helpers
//==============================================================================
int ClampInt(const int v, const int lo, const int hi)
{
   if(v < lo) return lo;
   if(v > hi) return hi;
   return v;
}

//--- line style indices shown in the panel STYLE steppers. 0-4 map 1:1 to
//    MT4 native ENUM_LINE_STYLE values (names via StyleName in panels).
#define ILS_SOLID        0
#define ILS_DASH         1
#define ILS_DOT          2
#define ILS_DASH_DOT     3
#define ILS_DASH_DOT_DOT 4
#define ILS_COUNT        5

ENUM_LINE_STYLE NativeStyleFromIdx(const int idx)
{
   switch(ClampInt(idx, 0, ILS_COUNT - 1))
   {
      case ILS_DASH:         return STYLE_DASH;
      case ILS_DOT:          return STYLE_DOT;
      case ILS_DASH_DOT:     return STYLE_DASHDOT;
      case ILS_DASH_DOT_DOT: return STYLE_DASHDOTDOT;
   }
   return STYLE_SOLID;
}

//==============================================================================
// UI STATE — shared by the circular menu and the settings panels
//==============================================================================
struct UIState {
   string btnPrefix;
   string gvPrefix;
   bool   menuVisible;
   int    menuX;            // orb center (pixels, top-left origin)
   int    menuY;
   bool   showHTF;
};
static UIState g_UI;

string GetGVName(string key) { return g_UI.gvPrefix + key; }

//--- settings-panel geometry (drag-to-move persistence; panel slots 0..12,
//     1 = the main Zones & Levels card; 12 = Base Box card).
//     PNL_COUNT lives here (Kit is included before Panels) so every loop
//     and slot array in both files stays in sync from one define.
#define PNL_COUNT 14
static int  g_PnlX[PNL_COUNT] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0};
static int  g_PnlY[PNL_COUNT] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0};
static bool g_PnlManualPos[PNL_COUNT] = {false,false,false,false,false,false,false,false,false,false,false,false,false,false};

//==============================================================================
// PALETTE COLOR KINDS — one kind per colorable setting of THIS indicator.
// Names/labels for the "Apply to" cycler live in BiotakPanels.mqh.
//==============================================================================
#define PAL_TRIGGER       0   // Trigger base color
#define PAL_TRIGGER_LABEL 1   // Trigger label color
#define PAL_SS            2   // SS level color
#define PAL_LS            3   // LS level color
#define PAL_TH3           4   // TH3 line color
#define PAL_TH3_PIP       5   // TH3 pip text color
#define PAL_HTF_BULL      6   // HTF bullish candle
#define PAL_HTF_BEAR      7   // HTF bearish candle
#define PAL_HTF_WICK      8   // HTF wick
#define PAL_HTF_BORDER    9   // HTF border
#define PAL_CUSTOM_PRICE 10   // Custom price line
#define PAL_FACTOR       11   // Factor level color
#define PAL_LINE         12   // Unified [08.4] line color (ALL pipeline lines)
#define PAL_BOX          13   // Base box border color (card 12)
#define PAL_BK_ENTRY       14   // Base box Entry line color (card 12)
#define PAL_BK_SL          15   // Base box Stop line color (card 12)
#define PAL_BK_TP          16   // Base box Target line color (card 12)
#define PAL_BOX_FILL       17   // Base box FILL color (TV-parity 2026-09-07 — bucket button)
#define PAL_BK_TEXT        18   // Base box user-TEXT color (TV-parity 2026-09-07 — T button)
#define PAL_BASE_TARGETS 19

//--- factory default colors (Reset actions)
color DefTriggerColor()      { return clrBlack; }
color DefTriggerLabelColor() { return clrBlack; }
color DefSSLevelColor()      { return clrGoldenrod; }
color DefLSLevelColor()      { return clrOrange; }
color DefTH3Color()          { return clrDarkBlue; }
color DefTH3PipColor()       { return clrDarkBlue; }
color DefCustomPriceColor()  { return clrDodgerBlue; }
color DefFactorColor()       { return C'0,100,0'; }
color DefLineColor()         { return clrBlack; }
color DefBoxBorderColor()    { return C'255,171,0'; }   // amber — the shipped Base Box look
color DefBoxFillColor()      { return C'255,171,0'; }   // amber fill (invisible until FILL TR < 100)
color DefBKTextColor()       { return C'255,255,255'; } // white user text inside the box
color DefBKEntryColor()      { return C'30,144,255'; }    // dodger blue Entry ray
color DefBKStopColor()       { return C'220,50,50'; }     // red Stop ray
color DefBKTargetColor()     { return C'46,139,87'; }     // sea green Target ray

//==============================================================================
// REFRESH DISPATCHER — applies REFRESH_* flags returned by the menu/panels
//==============================================================================
void ApplyRefreshFlags(const int flags)
{
   if(flags == REFRESH_NONE) return;

   if((flags & REFRESH_HTF) != 0)
   {
      static uint s_LastHtfRefresh = 0;
      uint now = GetTickCount();
      if(now - s_LastHtfRefresh >= 50)
      {
         s_LastHtfRefresh = now;
         RefreshHTFCandles();
      }
   }
   if((flags & (REFRESH_ALL | REFRESH_BUFFERS | REFRESH_RECALC | REFRESH_LABELS | REFRESH_TH3)) != 0)
   {
      if((flags & (REFRESH_LABELS | REFRESH_ALL)) != 0) g_labelsRelayoutNeeded = true;
      // TH3TOOL-OFF:
      //if((flags & (REFRESH_TH3 | REFRESH_ALL)) != 0)
      //{
      //   UpdateAllTH3Objects();
      //}
      g_redrawTHLevelsNeeded = true;
      RedrawAllObjects(true);
   }
   RuntimeSettingsSaveOverridesThrottled();
   ChartRedraw();
}

//--- alias used by the panels' internal calls
void RefreshDisplay(const int flags)
{
   ApplyRefreshFlags(flags);
}

//==============================================================================
// INIT / SAVE / PER-TICK
//==============================================================================
void InitializeUISupport()
{
   RuntimeSettingsLoadOverrides();
   SyncTHFlagsFromMode();   // OV-loaded flags must match the restored g_thLabelsMode
   LoadPalRecent();

   // panel drag positions (persisted per chart)
   for(int i = 0; i < PNL_COUNT; i++)
   {
      string vn = GetGVName("PNLP" + IntegerToString(i));
      if(GlobalVariableCheck(vn))
      {
         double packed = GlobalVariableGet(vn);
         g_PnlX[i] = (int)(packed / 10000.0);
         g_PnlY[i] = (int)MathMod(packed, 10000.0);
         g_PnlManualPos[i] = true;
      }
   }
}

void SaveUISupport()
{
   RuntimeSettingsSaveOverrides();
   SavePalRecent();
}

//--- per-tick UI refresh: live update of the forming HTF candle (cheap)
//     + throttled menu sync so hotkey toggles (T/L/A/S keys) and any state
//     change made outside the menu are reflected in the icons/badges.
// PERF: the icon sync lives in BiotakMenu.mqh (needs RING_COUNT) and is
// change-guarded there — re-pushing OBJPROP_BMPFILE forces MT4 to re-decode
// each bitmap, so it must only run when a feature actually flipped.
void RefreshUIPerTick()
{
   UpdateHTFFormingCandle();
   HTFEnsureDrawn();   // self-healing full HTF draw after TF switch / missing data (O(1) steady state)
   CircTipTick();   // armed hover tooltip (dwell-gated, ungated cheap checks)

   static uint s_LastMenuSync = 0;
   uint now = GetTickCount();
   if(now - s_LastMenuSync >= 500)
   {
      s_LastMenuSync = now;
      UpdateMenuSyncIfChanged();
      BaseKnotSyncBadges();   // pixel badges re-glued after scroll/zoom (cheap, runs only with boxes)
      BaseKnotHintTick();     // result-hint auto-hide pump
   }
}

#endif // BIOTAK_KIT_MQH
