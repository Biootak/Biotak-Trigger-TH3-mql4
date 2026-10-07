//+------------------------------------------------------------------+
//|                                        HTFCandles_Life.mqh       |
//|                                                                  |
//| P-HTF-SPLIT (2026-09-30): the overlay's BIRTH + PERSISTENCE owner —|
//| what the attach resolves, the 15 keys the teardown writes, and the |
//| cleanup. Part 3 of 3 (last); see HTFCandles_Geom.mqh for the map.  |
//+------------------------------------------------------------------+
#ifndef HTF_CANDLES_LIFE_MQH
#define HTF_CANDLES_LIFE_MQH

// P-UI-142: "does this key family exist here" — the restart layer picks the
// chart prefix when it has any key, else the symbol twin, else inputs.
bool HTFHasKeys(const string pfx)
{
   string sfx[15];
   sfx[0]="TfMode"; sfx[1]="IsAuto"; sfx[2]="Period"; sfx[3]="BullColor"; sfx[4]="BearColor";
   sfx[5]="WickColor"; sfx[6]="BorderColor"; sfx[7]="Opacity"; sfx[8]="ShowWicks"; sfx[9]="WickWidth";
   sfx[10]="GapPct"; sfx[11]="ShadowPct"; sfx[12]="BorderWidth"; sfx[13]="BoxMode"; sfx[14]="ShowBody";
   for(int i = 0; i < 15; i++)
      if(GlobalVariableCheck(pfx + sfx[i])) return true;
   return false;
}

//+------------------------------------------------------------------+
//| Initialize HTF Candles                                           |
//+------------------------------------------------------------------+
void InitializeHTFCandles()
{
   g_HTFPrefix = HTF_PREFIX_BASE + IntegerToString(ChartID()) + "_";
   // P-DRAW-87 (2026-09-30): PUBLISH the namespace, do not re-declare it. The
   // draw-strip's `DrawIsIndicatorObject` (DrawToolbar, included before this file)
   // is the ONE owner of "this object is the product's, not the user's drawing",
   // and it could not see this family: the strip's `BoxExtrasPump` then split each
   // shadow's interior into an invisible `<name>_FL` child and cleared its FILL.
   // The value stays `g_HTFPrefix` and this module stays its only writer.
   g_OverlayNameRoot = g_HTFPrefix;
   g_HTFBullColor = InpHTFBullColor;
   g_HTFBearColor = InpHTFBearColor;
   g_HTFWickColor = InpHTFWickColor;
   g_HTFBorderColor = InpHTFBorderColor;
   g_HTFOpacity = InpHTFOpacity;
   g_HTFShowWicks = InpHTFShowWicks;
   g_HTFWickWidth = InpHTFWickWidth;
   g_HTFGapPct = InpHTFGapPct;
   g_HTFShadowPct = InpHTFShadowPct;
   HTFRefreshPixelMetrics();   // the panel can open before the first draw pass
   g_HTFBorderWidth = InpHTFBorderWidth;
   g_HTFBoxMode = InpHTFBoxMode;
   g_HTFShowBody = InpHTFShowBody;

   string chartIdStr = GetCachedChartIdStr();
   string prefix = "Biotak_HTF_" + chartIdStr + "_";
   // P-UI-142: restart layer — chart ids are per-session, so when this window has
   // no keys of its own the symbol twin (written beside every chart write below)
   // answers instead of the inputs. Chart keys always win when present.
   string twinPfx = "Biotak_HTFSym_" + GetCachedSymbol() + "_";
   if(!HTFHasKeys(prefix) && HTFHasKeys(twinPfx)) prefix = twinPfx;

   // P-UI-92: the MODE is the restored state (0 Structure · 1 Pattern · 2
   // fixed). A chart saved by a build that only knew the bool reads through
   // the old "IsAuto" key ONCE — dynamic maps to Structure, manual to fixed
   // with its own "Period" — so nobody's choice is silently reset by an
   // upgrade. "TfMode" wins whenever it exists, and there is no third state
   // for a value a foreign build might have written: out of range = Structure.
   g_HTFTfMode = HTF_TF_STRUCTURE;
   g_HTFPeriod = 240;   // R-TF-UNIT: minutes (H4)
   if(GlobalVariableCheck(prefix + "TfMode"))
      g_HTFTfMode = (int)GlobalVariableGet(prefix + "TfMode");
   else if(GlobalVariableCheck(prefix + "IsAuto"))
      g_HTFTfMode = (GlobalVariableGet(prefix + "IsAuto") > 0.5) ? HTF_TF_STRUCTURE
                                                                 : HTF_TF_FIXED;
   if(g_HTFTfMode < HTF_TF_STRUCTURE || g_HTFTfMode > HTF_TF_FIXED)
      g_HTFTfMode = HTF_TF_STRUCTURE;
   if(GlobalVariableCheck(prefix + "Period"))
   {
      int savedTf = (int)GlobalVariableGet(prefix + "Period");
      if(savedTf > 0) g_HTFPeriod = savedTf;
   }

   if(GlobalVariableCheck(prefix + "BullColor"))   g_HTFBullColor   = (color)(int)GlobalVariableGet(prefix + "BullColor");
   if(GlobalVariableCheck(prefix + "BearColor"))   g_HTFBearColor   = (color)(int)GlobalVariableGet(prefix + "BearColor");
   if(GlobalVariableCheck(prefix + "WickColor"))   g_HTFWickColor   = (color)(int)GlobalVariableGet(prefix + "WickColor");
   if(GlobalVariableCheck(prefix + "BorderColor")) g_HTFBorderColor = (color)(int)GlobalVariableGet(prefix + "BorderColor");
   if(GlobalVariableCheck(prefix + "Opacity"))     g_HTFOpacity     = (int)GlobalVariableGet(prefix + "Opacity");
   if(GlobalVariableCheck(prefix + "ShowWicks"))   g_HTFShowWicks   = (GlobalVariableGet(prefix + "ShowWicks") > 0.5);
   if(GlobalVariableCheck(prefix + "WickWidth"))   g_HTFWickWidth   = (int)GlobalVariableGet(prefix + "WickWidth");
   // P-UI-68: the two geometry numbers are CLAMPED on the way in, not merely at
   // the UI edge — a chart saved by another build, or by a future one with a
   // wider range, must never be able to inject a gap that eats the body.
   if(GlobalVariableCheck(prefix + "GapPct"))
      g_HTFGapPct = (int)MathMax(HTF_GAP_PCT_MIN, MathMin(HTF_GAP_PCT_MAX, (int)GlobalVariableGet(prefix + "GapPct")));
   if(GlobalVariableCheck(prefix + "ShadowPct"))
      g_HTFShadowPct = (int)MathMax(HTF_SHADOW_PCT_MIN, MathMin(HTF_SHADOW_PCT_MAX, (int)GlobalVariableGet(prefix + "ShadowPct")));
   if(GlobalVariableCheck(prefix + "BorderWidth")) g_HTFBorderWidth = (int)GlobalVariableGet(prefix + "BorderWidth");
   if(GlobalVariableCheck(prefix + "BoxMode"))     g_HTFBoxMode     = (int)GlobalVariableGet(prefix + "BoxMode");
   if(GlobalVariableCheck(prefix + "ShowBody"))    g_HTFShowBody    = (GlobalVariableGet(prefix + "ShowBody") > 0.5);

   if(HTFTfIsDynamic()) g_HTFPeriod = HTFResolveRung();
   else if(g_HTFPeriod <= 0) { g_HTFTfMode = HTF_TF_STRUCTURE; g_HTFPeriod = HTFResolveRung(); }

   g_HTFLastFormOpen = 0;
   g_HTFLastFormO = 0; g_HTFLastFormH = 0;
   g_HTFLastFormL = 0; g_HTFLastFormC = 0;
   HTFRefreshBlendBackground();   // P-PERF-08: seed the blend cache

   // P-PERF-44 (1): the HTF shadow learns what this LOAD just resolved - not what
   // the first teardown would have written. Without it the 15 keys were written
   // again on every timeframe switch even when the card had never been opened.
   HTFPrimeCandleSettings();
   HTFProbeSettings("init");   // P-HTF-PROBE: what this attach RESOLVED (inputs + GVs)
}

//+------------------------------------------------------------------+
//| Save HTF Candles Settings                                        |
//+------------------------------------------------------------------+
#define HTF_SAVE_SLOTS 15

// P-PERF-44: these 15 keys used to be written UNCONDITIONALLY on every teardown -
// the one saver in that window with no shadow at all, and the reason the P-PERF-37
// line could report `save writes=0/106 flushed=0` while the phase still cost a
// hundred milliseconds: that counter covered the override table only. Same guard,
// same sink, same report as every other block now, and primed at init
// (HTFPrimeCandleSettings) so an untouched session writes nothing.
void SaveHTFCandlesSettings()
{
   static double s_htfShadow[HTF_SAVE_SLOTS];
   static bool   s_htfKnown[HTF_SAVE_SLOTS];
   static int    s_htfEpoch = -1;
   int htfChanged = 0;
   string chartIdStr = GetCachedChartIdStr();
   string prefix = "Biotak_HTF_" + chartIdStr + "_";
   // P-UI-142: the symbol twin rides every chart write (same guard: same value),
   // so a restart restores it when the chart id is new. Teardown-only writes.
   string twin = "Biotak_HTFSym_" + Symbol() + "_";
   // P-UI-92: "TfMode" is the state; "IsAuto" is still written (1 = either
   // dynamic rung) so ONE downgrade to a previous build keeps its own
   // Auto/Manual meaning instead of reading Structure as a manual period.
   if(GVSlotChanged(s_htfEpoch, s_htfKnown, s_htfShadow, 0, (double)g_HTFTfMode))
      { GlobalVariableSet(prefix + "TfMode",      (double)g_HTFTfMode); GlobalVariableSet(twin + "TfMode", (double)g_HTFTfMode); htfChanged++; }
   if(GVSlotChanged(s_htfEpoch, s_htfKnown, s_htfShadow, 1, HTFTfIsDynamic() ? 1.0 : 0.0))
      { GlobalVariableSet(prefix + "IsAuto",      HTFTfIsDynamic() ? 1.0 : 0.0); GlobalVariableSet(twin + "IsAuto", HTFTfIsDynamic() ? 1.0 : 0.0); htfChanged++; }
   if(GVSlotChanged(s_htfEpoch, s_htfKnown, s_htfShadow, 2, (double)g_HTFPeriod))
      { GlobalVariableSet(prefix + "Period",      (double)g_HTFPeriod); GlobalVariableSet(twin + "Period", (double)g_HTFPeriod); htfChanged++; }
   if(GVSlotChanged(s_htfEpoch, s_htfKnown, s_htfShadow, 3, (double)g_HTFBullColor))
      { GlobalVariableSet(prefix + "BullColor",   (double)g_HTFBullColor); GlobalVariableSet(twin + "BullColor", (double)g_HTFBullColor); htfChanged++; }
   if(GVSlotChanged(s_htfEpoch, s_htfKnown, s_htfShadow, 4, (double)g_HTFBearColor))
      { GlobalVariableSet(prefix + "BearColor",   (double)g_HTFBearColor); GlobalVariableSet(twin + "BearColor", (double)g_HTFBearColor); htfChanged++; }
   if(GVSlotChanged(s_htfEpoch, s_htfKnown, s_htfShadow, 5, (double)g_HTFWickColor))
      { GlobalVariableSet(prefix + "WickColor",   (double)g_HTFWickColor); GlobalVariableSet(twin + "WickColor", (double)g_HTFWickColor); htfChanged++; }
   if(GVSlotChanged(s_htfEpoch, s_htfKnown, s_htfShadow, 6, (double)g_HTFBorderColor))
      { GlobalVariableSet(prefix + "BorderColor", (double)g_HTFBorderColor); GlobalVariableSet(twin + "BorderColor", (double)g_HTFBorderColor); htfChanged++; }
   if(GVSlotChanged(s_htfEpoch, s_htfKnown, s_htfShadow, 7, (double)g_HTFOpacity))
      { GlobalVariableSet(prefix + "Opacity",     (double)g_HTFOpacity); GlobalVariableSet(twin + "Opacity", (double)g_HTFOpacity); htfChanged++; }
   if(GVSlotChanged(s_htfEpoch, s_htfKnown, s_htfShadow, 8, g_HTFShowWicks ? 1.0 : 0.0))
      { GlobalVariableSet(prefix + "ShowWicks",   g_HTFShowWicks ? 1.0 : 0.0); GlobalVariableSet(twin + "ShowWicks", g_HTFShowWicks ? 1.0 : 0.0); htfChanged++; }
   if(GVSlotChanged(s_htfEpoch, s_htfKnown, s_htfShadow, 9, (double)g_HTFWickWidth))
      { GlobalVariableSet(prefix + "WickWidth",   (double)g_HTFWickWidth); GlobalVariableSet(twin + "WickWidth", (double)g_HTFWickWidth); htfChanged++; }
   if(GVSlotChanged(s_htfEpoch, s_htfKnown, s_htfShadow, 10, (double)g_HTFGapPct))
      { GlobalVariableSet(prefix + "GapPct",      (double)g_HTFGapPct); GlobalVariableSet(twin + "GapPct", (double)g_HTFGapPct); htfChanged++; }
   if(GVSlotChanged(s_htfEpoch, s_htfKnown, s_htfShadow, 11, (double)g_HTFShadowPct))
      { GlobalVariableSet(prefix + "ShadowPct",   (double)g_HTFShadowPct); GlobalVariableSet(twin + "ShadowPct", (double)g_HTFShadowPct); htfChanged++; }
   if(GVSlotChanged(s_htfEpoch, s_htfKnown, s_htfShadow, 12, (double)g_HTFBorderWidth))
      { GlobalVariableSet(prefix + "BorderWidth", (double)g_HTFBorderWidth); GlobalVariableSet(twin + "BorderWidth", (double)g_HTFBorderWidth); htfChanged++; }
   if(GVSlotChanged(s_htfEpoch, s_htfKnown, s_htfShadow, 13, (double)g_HTFBoxMode))
      { GlobalVariableSet(prefix + "BoxMode",     (double)g_HTFBoxMode); GlobalVariableSet(twin + "BoxMode", (double)g_HTFBoxMode); htfChanged++; }
   if(GVSlotChanged(s_htfEpoch, s_htfKnown, s_htfShadow, 14, g_HTFShowBody ? 1.0 : 0.0))
      { GlobalVariableSet(prefix + "ShowBody",    g_HTFShowBody ? 1.0 : 0.0); GlobalVariableSet(twin + "ShowBody", g_HTFShowBody ? 1.0 : 0.0); htfChanged++; }
   GVLedgerReport(GV_BLOCK_HTF, htfChanged, HTF_SAVE_SLOTS);
   if(htfChanged == 0) return;
   GVFlushRequest();   // P-PERF-44 (2): ASK; the teardown's one commit pays for it
}

// P-PERF-44 (1): prime the HTF shadow from its own load pass (the end of
// InitializeHTFCandles), by replaying this write order in dry-run.
void HTFPrimeCandleSettings()
{
   GVShadowDryRun(true);
   SaveHTFCandlesSettings();
   GVShadowDryRun(false);
}

//+------------------------------------------------------------------+
//| Cleanup HTF Candles GlobalVariables                              |
//+------------------------------------------------------------------+
void CleanupHTFCandlesGVs()
{
   string chartIdStr = GetCachedChartIdStr();
   string prefix = "Biotak_HTF_" + chartIdStr + "_";
   GlobalVariableDel(prefix + "TfMode");
   GlobalVariableDel(prefix + "IsAuto");
   GlobalVariableDel(prefix + "Period");
   GlobalVariableDel(prefix + "BullColor");
   GlobalVariableDel(prefix + "BearColor");
   GlobalVariableDel(prefix + "WickColor");
   GlobalVariableDel(prefix + "BorderColor");
   GlobalVariableDel(prefix + "Opacity");
   GlobalVariableDel(prefix + "ShowWicks");
   GlobalVariableDel(prefix + "WickWidth");
   GlobalVariableDel(prefix + "GapPct");
   GlobalVariableDel(prefix + "ShadowPct");
   GlobalVariableDel(prefix + "BorderWidth");
   GlobalVariableDel(prefix + "BoxMode");
   GlobalVariableDel(prefix + "ShowBody");
   // P-UI-142: the symbol twins die with the uninstall too.
   string twin = "Biotak_HTFSym_" + Symbol() + "_";
   GlobalVariableDel(twin + "TfMode");
   GlobalVariableDel(twin + "IsAuto");
   GlobalVariableDel(twin + "Period");
   GlobalVariableDel(twin + "BullColor");
   GlobalVariableDel(twin + "BearColor");
   GlobalVariableDel(twin + "WickColor");
   GlobalVariableDel(twin + "BorderColor");
   GlobalVariableDel(twin + "Opacity");
   GlobalVariableDel(twin + "ShowWicks");
   GlobalVariableDel(twin + "WickWidth");
   GlobalVariableDel(twin + "GapPct");
   GlobalVariableDel(twin + "ShadowPct");
   GlobalVariableDel(twin + "BorderWidth");
   GlobalVariableDel(twin + "BoxMode");
   GlobalVariableDel(twin + "ShowBody");
}

#endif // HTF_CANDLES_LIFE_MQH
