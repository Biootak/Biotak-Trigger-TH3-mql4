// BiotakPanels_Apply.mqh - BiotakPanels split 2026-09-29: exact lines 3819-4850 of BiotakPanels.mqh, byte-identical, zero renames.
#ifndef BIOTAK_PANELS_APPLY_MQH
#define BIOTAK_PANELS_APPLY_MQH

string g_BkMiniBox = "";

//+------------------------------------------------------------------+
//| Base Box STYLE presets — one tap applies a curated full look      |
//| (border + R + 3 line colors). Custom = manual edits (selector     |
//| only, tapping it is a no-op). Same mirrors as card 12 — the mini |
//| and full PRESET rows delegate here, never duplicated.             |
//+------------------------------------------------------------------+
struct BkPreset
{
   color border;
   int   style;   // native ENUM_LINE_STYLE value
   int   width;
   int   tr;
   int   rr;
   color entry;
   color sl;
   color tp;
   color fill;    // TV-parity 2026-09-07: Style-tab bucket
   int   fillTr;  // (the shipped preset = 100 invisible = the hollow look)
   color text;    // TV-parity: Text-tab color
   int   textSize;
   int   bi;      // 0 Reg · 1 Bold · 2 Italic · 3 B+I
   int   align;   // 0 Left · 1 Center · 2 Right
   int   valign;  // 0 Top · 1 Inside · 2 Bottom (TV Inside-dropdown)
};
void BkPresetGet(const int i, BkPreset &p)
{
   if(i == 1)         // Ocean
   {
      p.border=C'41,182,246'; p.style=STYLE_SOLID; p.width=2; p.tr=0; p.rr=BK_TP_PLAN_MAX;   // P-BK-50: all three plan legs (the shipped look)
      p.entry=C'41,182,246'; p.sl=C'240,98,146'; p.tp=C'102,187,106';
      p.fill=C'41,182,246'; p.fillTr=80;
      p.text=C'255,255,255'; p.textSize=10; p.bi=0; p.align=2; p.valign=1;
   }
   else if(i == 2)    // Mono
   {
      p.border=C'176,190,197'; p.style=STYLE_DASH; p.width=1; p.tr=0; p.rr=BK_TP_PLAN_MAX;   // P-BK-50
      p.entry=C'144,164,174'; p.sl=C'120,144,156'; p.tp=C'207,216,220';
      p.fill=C'176,190,197'; p.fillTr=88;
      p.text=C'207,216,220'; p.textSize=10; p.bi=0; p.align=2; p.valign=1;
   }
   else               // 0 Navy (the shipped look — P-BK-69)
   {
      p.border=C'0,0,139'; p.style=STYLE_SOLID; p.width=2; p.tr=0; p.rr=BK_TP_PLAN_MAX;   // P-BK-69: the mark's ink (and its points') — dark blue
      p.entry=C'46,139,87'; p.sl=C'220,50,50'; p.tp=C'30,144,255';
      p.fill=BIO_CLR_BRAND; p.fillTr=100;   // P-UI-117: the brand token, not a second literal
      p.text=C'255,255,255'; p.textSize=10; p.bi=0; p.align=2; p.valign=1;
   }
}
int BkPresetMatch()   // 0/1/2 = preset, 3 = Custom (manual edits)
{
   for(int i = 0; i < 3; i++)
   {
      BkPreset p; BkPresetGet(i, p);
      if(g_boxBorderColor==p.border && (int)g_boxBorderStyle==p.style &&
         g_boxBorderWidth==p.width && g_boxBorderTransparency==p.tr &&
         g_bkTargetR==p.rr && g_bkEntryColor==p.entry &&
         g_bkStopColor==p.sl && g_bkTargetColor==p.tp &&
         g_boxFillColor==p.fill && g_boxFillTransparency==p.fillTr &&
         g_bkTextColor==p.text && g_bkTextSize==p.textSize &&
         BkBIFromMirrors()==p.bi && ClampInt(g_bkAlign,0,2)==p.align && ClampInt(g_bkVAlign,0,2)==p.valign) return i;
   }
   return 3;
}
int BkApplyPreset(const int i)   // apply + restyle live boxes + persist via flags
{
   if(i < 0 || i > 2) return REFRESH_NONE;   // Custom — nothing to apply
   BkPreset p; BkPresetGet(i, p);
   g_boxBorderColor=p.border; g_boxBorderStyle=(ENUM_LINE_STYLE)ClampInt(p.style,0,4);
   g_boxBorderWidth=ClampInt(p.width,1,5); g_boxBorderTransparency=ClampInt(p.tr,0,100);
   g_bkTargetR=ClampInt(p.rr,1,BK_TP_PLAN_MAX);   // P-BK-50: TP COUNT
   g_bkEntryColor=p.entry; g_bkStopColor=p.sl; g_bkTargetColor=p.tp;
   g_boxFillColor=p.fill; g_boxFillTransparency=ClampInt(p.fillTr,0,100);
   g_bkTextColor=p.text; g_bkTextSize=ClampInt(p.textSize,8,24);
   BkBIToMirrors(ClampInt(p.bi,0,3)); g_bkAlign=ClampInt(p.align,0,2); g_bkVAlign=ClampInt(p.valign,0,2);
   BaseKnotRestyleAll();
   return REFRESH_BUFFERS;   // OV_ persist rides via ApplyRefreshFlags
}

//+------------------------------------------------------------------+
//| Factory default for a row.                                        |
//| NOTE: must NOT read inpX — the RuntimeSettings #defines redirect    |
//| inpX to the CURRENT runtime copy (self-assign → Reset no-op).    |
//| Returns FactoryDefault() captures from RuntimeSettingsInit instead.|
//+------------------------------------------------------------------+
// ══════════════════════════════════════════════════════════════════════════
// PnlDefVal / PnlCurrent / PnlApply — PUBLIC entry points are DISPLAY-row
// keyed (that is what the renderer, the hit-tests and the click handler
// hold). Each one translates to the SETTING row first and delegates to its
// *Set twin below, which keeps the original per-card switch untouched. A
// section band owns no setting, so it answers a neutral value and applies
// nothing (PnlResetItem skips bands explicitly).
// ══════════════════════════════════════════════════════════════════════════
double PnlDefVal(const int item,const int row)
{
   int s = PnlSetRow(item,row);
   if(s < 0) return 0.0;
   return PnlDefValSet(item,s);
}

double PnlCurrent(const int item,const int row)
{
   int s = PnlSetRow(item,row);
   if(s < 0) return 0.0;
   return PnlCurrentSet(item,s);
}

int PnlApply(const int item,const int row,const double v)
{
   int s = PnlSetRow(item,row);
   if(s < 0) return REFRESH_NONE;      // a section band is not a control
   return PnlApplySet(item,s,v);
}

double PnlDefValSet(const int item,const int row)
{
   switch(item)
   {
      case 0: if(row==0) return FactoryDefault(FF_TRIGGER_TRANSPARENCY);
              if(row==1 || row==2) return 3;   // COLOR rows → palette sentinel
              if(row==4) return -1;            // P-UI-131j: LABEL OPACITY — AUTO
              return (FactoryDefault(FF_TRIGGER_SHOW)>0.5)?1.0:0.0;   // row 3 — SHOW
      case 1: if(row==0) return (FactoryDefault(FF_SHOW_MIDZONES)>0.5)?1.0:0.0;
              if(row==1) return (FactoryDefault(FF_SHOW_LINES)>0.5)?1.0:0.0;
              if(row==2) return (int)FactoryDefault(FF_MIDZONE_STYLE);
              if(row==3) return FactoryDefault(FF_MIDZONE_TRANSPARENCY);
              if(row==4) return FactoryDefault(FF_MIDZONE_HEIGHT);
              if(row==5) return (int)FactoryDefault(FF_MIDZONE_BORDER_STYLE);
              if(row==6) return FactoryDefault(FF_MIDZONE_BORDER_WIDTH);
              if(row==7) return FactoryDefault(FF_MIDZONE_BORDER_TRANSPARENCY);   // P-UI-63
              // P-UI-131h: the sentinel shape card 0 uses for its COLOR rows, and -1 =
              // AUTO for the two opacities — the factory look IS the derivation, so
              // Reset returns to the soft, surface-anchored edge and to nothing pinned.
              if(row==14 || row==15) return 3;   // COLOR rows → palette sentinel
              if(row==16 || row==17) return -1;  // AUTO
              if(row==8) return (FactoryDefault(FF_LS_FIRST)>0.5)?1.0:0.0;
              if(row==9) return (FactoryDefault(FF_SHOW_MIDPOINT)>0.5)?1.0:0.0;
              return 0;                        // rows 10-11 = NAV rows
      case 2: if(row==0) return (FactoryDefault(FF_SHOW_COUNTDOWN)>0.5)?1.0:0.0;
              if(row==1) return 3;   // COLOR row → palette sentinel
              if(row==2) return FactoryDefault(FF_COUNTDOWN_SIZE);
              if(row==3) return FactoryDefault(FF_COUNTDOWN_GAP);
              if(row==4) return (FactoryDefault(FF_SHOW_ATR)>0.5)?1.0:0.0;
              if(row==5) return (FactoryDefault(FF_ATR_TARGETS)>0.5)?1.0:0.0;
              if(row==6) return (FactoryDefault(FF_ATR_TRADE)>0.5)?1.0:0.0;
              if(row==7) return (FactoryDefault(FF_ATR_TRADE_SL)>0.5)?1.0:0.0;
              if(row==8) return (FactoryDefault(FF_ATR_TRADE_TP)>0.5)?1.0:0.0;
              if(row==9) return (FactoryDefault(FF_PIP_LABELS)>0.5)?1.0:0.0;
              if(row==10) return FactoryDefault(FF_ATR_ROW_GAP);
              if(row==11) return FactoryDefault(FF_TRADE_SIZE);
              if(row==12) return FactoryDefault(FF_STAMP_ROWS);
              if(row==13) return FactoryDefault(FF_TRADE_MARGIN);
              // P-UI-70d: the colour cells are palette-only rows - the sentinel
              // mirrors the COUNT COLOR row above (PnlColorKindSet owns the
              // colour itself, so the reset path goes through PnlSetColor).
              if(row>=14 && row<=18) return 3;
              return FactoryDefault(FF_TRADE_MARGIN);
      case 3: if(row==0) return (FactoryDefault(FF_SHOW_TH_LABELS)>0.5)?1.0:0.0;
              if(row==1) return (FactoryDefault(FF_TH_FRACTAL)>0.5)?1.0:0.0;
              if(row==2) return (FactoryDefault(FF_TH_STANDARD)>0.5)?1.0:0.0;
              if(row==3) return (FactoryDefault(FF_TH_TARGETS)>0.5)?1.0:0.0;
              if(row==4) return 40;                    // default margin bottom
              if(row==5) return FactoryDefault(FF_TH_PERCENT);   // P-TH-01 — 0 = professor's table
              return 40;                               // default margin bottom
       // VIEWLOCK-OFF: case 4: return 0.0;   // view lock off by default
       // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
       case 5: if(row==0) return (FactoryDefault(FF_ENABLE_TH3)>0.5)?1.0:0.0;
               if(row==1) return (int)FactoryDefault(FF_TH3_DRAW_MODE);
               if(row==2) return FactoryDefault(FF_TH3_BASE_STEP);
               if(row==3) return FactoryDefault(FF_TH3_WIDTH);
               if(row==4) return (int)FactoryDefault(FF_TH3_STYLE);
               if(row==7) return (FactoryDefault(FF_TH3_SHOW_LABELS)>0.5)?1.0:0.0;
               if(row==8) return FactoryDefault(FF_TH3_PIVOT_BASE);   // P-TH3-PB-MAN (0 = OFF, the pattern TF's own ATR)
               return 3;
       case 6: if(row==0) return 0.0;                   // HTF off by default
              if(row==1)
              {
                 // P-UI-92: factory default = the Structure rung, or the
                 // fixed ladder entry InpHTFTimeframe names (option 2+).
                 if(InpHTFAutoMode==HTF_AUTO_FRACTAL) return 0.0;
                 int vals[7]={240,60,30,15,1440,10080,43200};
                 for(int i=0;i<7;i++) if(vals[i]==(int)InpHTFTimeframe) return i+2;
                 return 0.0;
              }
               if(row==2) return 100-ClampInt(InpHTFOpacity,MIN_OPACITY_PCT,MAX_OPACITY_PCT);
              if(row==3) return 3; // BULL COLOR
              if(row==4) return 3; // BEAR COLOR
              if(row==5) return 3; // WICK COLOR
              if(row==6) return 3; // BORDER COLOR
              if(row==7) return ClampInt(InpHTFWickWidth,MIN_WIDTH,MAX_WIDTH);
              if(row==8) return ClampInt(InpHTFBorderWidth,MIN_WIDTH,MAX_WIDTH);
              if(row==9) return InpHTFShowWicks?1.0:0.0;
              if(row==10) return (int)InpHTFBoxMode;
              if(row==11) return ClampInt(InpHTFShadowPct,HTF_SHADOW_PCT_MIN,HTF_SHADOW_PCT_MAX);
              return ClampInt(InpHTFGapPct,HTF_GAP_PCT_MIN,HTF_GAP_PCT_MAX);
      case 7: if(row==0) return 0.0;                       // BACK nav row
              if(row==1) return (FactoryDefault(FF_SHOW_LINES)>0.5)?1.0:0.0;
              if(row==2) return FactoryDefault(FF_LINE_WIDTH);
              if(row==3) return (int)FactoryDefault(FF_LINE_STYLE);
              if(row==4) return FactoryDefault(FF_LINE_TRANSPARENCY);
              return 3;   // row 5 = COLOR row → palette sentinel
      case 8: if(row==0) return FactoryDefault(FF_CUSTOM_WIDTH);
              // P-UI-101: row 2 is the LOCK now (the magnet's retired row). Its
              // factory default is "unlocked" — a fresh placement is free.
              if(row==2) return 0.0;
              if(row==3) return FactoryDefault(FF_MAGNET_SENS);
              return 3;   // COLOR row → palette sentinel
      case 9: if(row==0) return (int)FactoryDefault(FF_STEP_CALC_MODE);
              if(row==PnlStepMaxLevelsRow()) return FactoryDefault(FF_MAX_LEVELS);
              return PnlStepSectionDefVal(row-1);
      case 11: if(row==0) return 0.0;                   // BACK nav row
              if(row==1) return (FactoryDefault(FF_SHOW_STRUCTURE)>0.5)?1.0:0.0;
              if(row==2) return (FactoryDefault(FF_SHOW_STRUCTURE_L1)>0.5)?1.0:0.0;
              if(row==3) return (FactoryDefault(FF_SHOW_STRUCTURE_L2)>0.5)?1.0:0.0;
              if(row==4) return (FactoryDefault(FF_SHOW_STRUCTURE_L3)>0.5)?1.0:0.0;
              if(row==5) return (FactoryDefault(FF_SHOW_STRUCTURE_L4)>0.5)?1.0:0.0;
              return (FactoryDefault(FF_SHOW_STRUCTURE_L5)>0.5)?1.0:0.0;
      case 10: if(row==0) return (int)FactoryDefault(FF_FACTOR_MODE);
               if(row==1) return (int)FactoryDefault(FF_FACTOR_DISPLAY);
               if(row==2) return (int)FactoryDefault(FF_FACTOR_BASIS);
               if(row==3) return FactoryDefault(FF_FACTOR_VALUE);
               if(row==4) return FactoryDefault(FF_FACTOR_WIDTH);
               if(row==5) return (int)FactoryDefault(FF_FACTOR_STYLE);
               return 3;
      case 12: if(row==0) return g_BkTab;   // TAB segments
               return BkSecDefVal(row-1);
      case 13: if(row==0) return 3;   // Mini BORDER COLOR → palette sentinel
               if(row==1) return FactoryDefault(FF_BK_TARGET_R);
               if(row==2) return FactoryDefault(FF_BK_SHOW_INFO);
               if(row==3) return 0;   // Mini PRESET (Navy shipped — P-BK-69)
               if(row==4) return 0;   // Mini LOCK off
               return 0;                        // action/nav rows
      // P-UI-131: a moved row reads the address it moved FROM (one default owner),
      // the grid's own rows are the new FF_ keys.
      case 14: if(row==0)  return PnlDefValSet(9, PnlStepMaxLevelsRow());
               if(row==1)  return FactoryDefault(FF_LABEL_SIZE);
               if(row==2)  return FactoryDefault(FF_LABEL_ROW_GAP);
               if(row==3)  { double df=FactoryDefault(FF_LABEL_FONT); return (df < 0 ? 0 : df); }
               if(row==4)  return FactoryDefault(FF_MARGIN_TOP);
               if(row==5)  return FactoryDefault(FF_MARGIN_LEFT);
               if(row==6)  return FactoryDefault(FF_COLUMN_GAP);
               if(row==7)  return FactoryDefault(FF_SECTION_GAP);
               if(row==8)  return FactoryDefault(FF_MAX_LABEL_W);
               if(row==9)  return PnlDefValSet(2, 13);   // CARD MARGIN
               if(row==10) return PnlDefValSet(3, 4);    // TH MARGIN
               if(row==11) return PnlDefValSet(2, 10);   // TRADE ROW GAP
               if(row==12) return PnlDefValSet(2, 11);   // TRADE SIZE
               if(row==13) return PnlDefValSet(2, 12);   // STAMP GAP
               return 0;                        // row 14 = NAV (a door resets nothing)
  }
  return 0;
}

//+------------------------------------------------------------------+
//| P-UI-93 — WHICH ROWS DISPLAY THE F MUTE.                          |
//|                                                                   |
//| Reported: «این روشن و خاموش کردن سطوح روی بقیه لیبلها چرا تاثیر    |
//| میزاره ... این دکمه های با پنل هماهنگ نیستش همه رو هماهنگ کن».     |
//|                                                                   |
//| The mute is ONE master and the ENGINE already shares it: every     |
//| family writer spells `... && !IsIndicatorHidden()` (labels, zones, |
//| the level writer, the countdown). That is the honest answer to the |
//| first half of the report — the F press reaching the labels is by   |
//| design, not a leak.                                                |
//|                                                                   |
//| What was NOT harmonised is the PANEL: these rows answered the      |
//| STORED switch alone, so after an F press every row still claimed   |
//| its family was painted while the chart was blank.                  |
//|                                                                   |
//| ONE OWNER for the list. Two spellings of the same set (one in the  |
//| display layer, one in the apply layer) drift the day a family is   |
//| added — the class of bug P-PERF-41 fixed for the zone walk.        |
//|                                                                   |
//| The RULE, applied mechanically, is one line: a row is gated iff the  |
//| writer its switch feeds already spells `!IsIndicatorHidden()` AND    |
//| the switch is the TOP of its own visibility family. The second half  |
//| is what keeps the sub-rows out — a piece of another row's family     |
//| (ATR TARGETS / TRADE SL / TRADE TP, TH FRACTAL / STANDARD / TARGETS) |
//| does not gate anything by itself, so a mute term on it would claim a |
//| control the F walk never reads.                                      |
//|                                                                     |
//| Verified writers, one per entry:                                     |
//|   trigger overlay  → LevelPipeline's zone mask                      |
//|   MID ZONES        → VisibilityZoneMask / GetZoneColorForLevel       |
//|   SHOW LINES       → LevelPipeline:803,1069 (the L switch)           |
//|   COUNTDOWN        → LiveCountdownEnabled()                          |
//|   ATR LABELS       → SetATRLabelsVisibility (`shouldShow`)           |
//|   TRADE LABELS     → SetATRLabelsVisibility (`cardOn`, P-UI-84)      |
//|   H/L PIP LABELS   → LevelPipeline:1102                              |
//|   TH LABELS        → SetTHLabelsVisibility (`shouldShow`)            |
//|   STRUCTURE L1-L5  → LevelPipeline:802 (`visible && !hidden`)        |
//+------------------------------------------------------------------+
bool PnlSettingIsMuteGated(const int item,const int row)
{
   if(item==0)  return (row==3);              // trigger overlay
   if(item==1)  return (row==0 || row==1);    // MID ZONES · SHOW LINES
   if(item==2)  return (row==0 || row==4 || row==6 || row==9);
                                              // COUNTDOWN · ATR LABELS ·
                                              // TRADE LABELS · H/L PIP LABELS
   if(item==3)  return (row==0);              // TH LABELS (the family's master)
   if(item==7)  return (row==1);              // SHOW LINES (same switch, other card)
   if(item==11) return (row>=1 && row<=6);    // SHOW STRUCTURE + L1..L5
   return false;
}

// The displayed value of a mute-gated row: the family's own switch AND the
// master mute. `storedOn` is passed in, never re-read, so this stays a pure
// fold of the two terms and cannot become a third owner of either.
double PnlMuteGatedValue(const bool storedOn)
{
   if(!storedOn) return 0.0;
   return IsIndicatorHidden() ? 0.0 : 1.0;
}

//+------------------------------------------------------------------+
//| Current displayed value of a row                                  |
//+------------------------------------------------------------------+
double PnlCurrentSet(const int item,const int row)
{
   switch(item)
   {
      case 0: if(row==0) return g_triggerTransparency;
              if(row==1 || row==2) return 0;   // COLOR rows (palette only)
              if(row==4) return g_triggerLabelTransparency;   // P-UI-131j
              // P-UI-93: row 3 is this card's TOP address, so the muted form rides
              // the trailing statement — the wiring audit reads the trailing
              // statement as answering exactly `top`, and rows 0..2 above are
              // already explicit, so no address moves and no branch is added.
              return PnlMuteGatedValue(g_triggerLevelsEnabled);   // row 3 — SHOW
      case 1: if(row==0) return PnlMuteGatedValue(g_showMidZones);   // P-UI-93
              if(row==1) return PnlMuteGatedValue(g_showLines);      // P-UI-93
              if(row==2) return (int)g_midZoneStyle;
              if(row==3) return g_midZoneTransparency;
              if(row==4) return g_midZoneHeightPercent;
              if(row==5) return (int)g_midZoneBorderStyle;
              if(row==6) return g_midZoneBorderWidth;
              if(row==7) return g_midZoneBorderTransparency;   // P-UI-63
              if(row==8) return g_lsFirst?1.0:0.0;
              if(row==9) return g_showMidpointLine?1.0:0.0;
              if(row==14 || row==15) return 0;                 // P-UI-131h: colour rows
              if(row==16) return g_zoneEdgeTopTransparency;
              if(row==17) return g_zoneEdgeBottomTransparency;
              return 0;                        // rows 10-11 = NAV rows
      case 2: if(row==0) return PnlMuteGatedValue(g_showLiveCountdown);   // countdown's own layer · P-UI-93
              if(row==1) return 0;   // COUNT COLOR (palette only)
              if(row==2) return g_countdownFontSize;
              if(row==3) return g_countdownGapPx;
              // P-UI-93: the ATR block and the TRADE CARD are each their own
              // family top (the trade card owns its master switch alone, P-UI-84),
              // so those two rows answer the mute. Rows 5 / 7 / 8 are PIECES of
              // one of those families - a mute term on them would claim a control
              // the F walk never reads (see PnlSettingIsMuteGated).
              if(row==4) return PnlMuteGatedValue(g_showATRLabels);
              if(row==5) return g_showATRTargets?1.0:0.0;
              if(row==6) return PnlMuteGatedValue(g_showATRTradeLabels);
              if(row==7) return g_showATRTradeSLLabels?1.0:0.0;
              if(row==8) return g_showATRTradeTPLabels?1.0:0.0;
              // H/L pip labels are their own family (LevelPipeline:1102 writes the
              // mask with the mute as one of its two terms), so this row answers it.
              if(row==9) return PnlMuteGatedValue(g_showPipDistanceLabels);
              if(row==10) return g_atrLabelRowGap;
              if(row==11) return g_atrTradeFontSize;
              if(row==12) return g_trexStampGapRows;
              if(row==13) return g_tradeMarginBottom;
              if(row>=14 && row<=18) return 0;   // palette-only (P-UI-70d)
              return g_tradeMarginBottom;
      case 3: // P-UI-93: SetTHLabelsVisibility spells its mask
              // `(mode != 0) && !IsIndicatorHidden()`, so the TH family's master
              // row answers the mute. Rows 1/2/3 are the mode's SOURCES and the
              // targets piece inside that one family, so they stay as they were.
              if(row==0) return PnlMuteGatedValue(g_showTHLabels);
              if(row==1) return g_showFractalTHs?1.0:0.0;
              if(row==2) return g_showStandardTHs?1.0:0.0;
              if(row==3) return g_showTHTargets?1.0:0.0;
              // P-TH-01: row 4 is spelled out rather than left to the trailing
              // `return` below, because the wiring audit reads the trailing
              // statement as answering only the card's TOP address (setting 5).
              if(row==4) return g_thLabelsMarginBottom;
              if(row==5) return g_thPercentOverride;   // P-TH-01 (0 = OFF)
              return g_thLabelsMarginBottom;
       case 4: if(row==0) return g_UI.tipPin?1.0:0.0;   // P-UI-126: ALWAYS SHOWN
               return 0.0;
       // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
       case 5: if(row==0) return g_enableTH3Tool?1.0:0.0;
               if(row==1) return (int)g_th3DrawingMode;
               if(row==2) return g_th3BaseStepPercent;
               if(row==3) return g_th3Width;
               if(row==4) return (int)g_th3Style;
               if(row==7) return g_showTH3Labels?1.0:0.0;
               if(row==8) return g_th3PivotBasePips;   // P-TH3-PB-MAN (0 = OFF, the pattern TF's own ATR)
               return 0;
       case 6: if(row==0) return g_UI.showHTF?1.0:0.0;
               if(row==1) return HTFOptionFromPeriod(g_HTFPeriod);
               if(row==2) return 100-g_HTFOpacity;   // stored as opacity, shown as transparency
              if(row==7) return g_HTFWickWidth;
              if(row==8) return g_HTFBorderWidth;
              if(row==9) return g_HTFShowWicks?1.0:0.0;
              if(row==10) return g_HTFBoxMode;
              if(row==11) return g_HTFShadowPct;
              return g_HTFGapPct;
      case 7: if(row==0) return 0;            // BACK nav row
              if(row==1) return PnlMuteGatedValue(g_showLines);   // P-UI-93 (same switch as card 1 row 1)
              if(row==2) return g_lineWidth;
              if(row==3) return (int)g_lineStyle;
              if(row==4) return g_lineTransparency;
              return 0;   // row 5 = COLOR row (palette only)
      case 8: if(row==0) return g_customPriceLevelWidth;
              if(row==2) return g_customPriceLocked ? 1.0 : 0.0;   // P-UI-101
              return g_magnetSensitivityPips;
      case 9: if(row==0) return (int)g_stepCalculationMode;
              if(row==PnlStepMaxLevelsRow()) return g_maxLevels;
              return PnlStepSectionCurrent(row-1);
      case 11: if(row==0) return 0;            // BACK nav row
              // P-UI-93: the structure zones and their five rungs are all zone
              // objects, and LevelPipeline writes their mask as
              // `visible && !IsIndicatorHidden()` (line 802) — so the mute is one
              // of their two terms and every row here answers both.
              if(row==1) return PnlMuteGatedValue(g_showStructure);
              if(row==2) return PnlMuteGatedValue(g_showStructureL1);
              if(row==3) return PnlMuteGatedValue(g_showStructureL2);
              if(row==4) return PnlMuteGatedValue(g_showStructureL3);
              if(row==5) return PnlMuteGatedValue(g_showStructureL4);
              return PnlMuteGatedValue(g_showStructureL5);
      case 10: if(row==0) return (int)g_factorMode;
               if(row==1) return (int)g_factorDisplayMode;
               if(row==2) return (int)g_factorAutoBasis;
               if(row==3) return g_factorValue;
               if(row==4) return g_factorLevelWidth;
               if(row==5) return (int)g_factorLevelStyle;
               return 0;
      case 12: if(row==0) return g_BkTab;   // TAB segments
               return BkSecCurrent(row-1);
      case 13: if(row==0) return 0;   // Mini BORDER COLOR (palette only)
               if(row==1) return g_bkTargetR;
               if(row==2) return g_bkShowInfo;
               if(row==3) return BkPresetMatch();
               if(row==4) return (BaseKnotLocked(g_BkMiniBox) ? 1 : 0);
               return 0;                        // action/nav rows
      case 14: if(row==0)  return PnlCurrentSet(9, PnlStepMaxLevelsRow());
               if(row==1)  return g_labelFontSize;
               if(row==2)  return g_labelRowGap;
               if(row==3)  return (g_labelFontIdx < 0 ? 0 : g_labelFontIdx);
               if(row==4)  return g_labelsMarginTop;
               if(row==5)  return g_labelsMarginLeft;
               if(row==6)  return g_labelColumnGap;
               if(row==7)  return g_sectionGap;
               if(row==8)  return g_maxLabelWidth;
               if(row==9)  return PnlCurrentSet(2, 13);   // CARD MARGIN
               if(row==10) return PnlCurrentSet(3, 4);    // TH MARGIN
               if(row==11) return PnlCurrentSet(2, 10);   // TRADE ROW GAP
               if(row==12) return PnlCurrentSet(2, 11);   // TRADE SIZE
               if(row==13) return PnlCurrentSet(2, 12);   // STAMP GAP
               return 0;                        // row 14 = NAV
  }
  return 0;
}

// (THModeFromFlags / SyncTHFlagsFromMode live in GlobalVariables.mqh — the
//  TH labels state model is single-sourced on g_thLabelsMode.)

//+------------------------------------------------------------------+
//| Apply a new value for a row → returns REFRESH_* flags             |
//+------------------------------------------------------------------+
int PnlApplySet(const int item,const int row,const double v)
{
   int rk=0; string rl="",ru="",ro=""; int rMin=0,rMax=0; double rst=1;
   PnlSetDef(item,row,rk,rl,rMin,rMax,rst,ru,ro);
   if(rk==4) return REFRESH_NONE;   // COLOR rows change only via the palette popup
   if(rk==5) return REFRESH_NONE;   // NAV rows only open another card (PnlHandleClick)
   // P-UI-93: while the chart is muted every gated row READS OFF (PnlCurrentSet),
   // so the press arrives here as v=1 for a family that is already stored ON and
   // would paint the moment the mute went. Writing the switch alone would change
   // nothing the user can see - the row would snap straight back to OFF and the
   // two controls would still disagree. The press releases the mute instead, and
   // then the switch below is written normally (a family stored OFF comes ON in
   // the same press, which is what the OFF row promised).
   //
   // The `v>0.5` term is what keeps this to the PRESS paths: while muted every
   // gated row displays 0, so any press computes 1. A reset that restores an
   // ON-by-default family passes 1 too - and a reset that leaves the chart blank
   // would be the same lie in the other direction.
   if(v>0.5 && PnlSettingIsMuteGated(item,row) && IsIndicatorHidden())
      ReleaseIndicatorMute();   // P-UI-93: one owner, shared with the ring
   int flags=REFRESH_NONE;
   switch(item)
   {
      case 0:   // TRIGGER ZONES — zone appearance + overlay toggle only.
                // Unified line look lives on the LINES card (7).
         if(row==0)       { g_triggerTransparency=ClampInt((int)MathRound(v),0,100); flags=REFRESH_BUFFERS; }
         // P-UI-131j: the LABEL's own opacity — the LABEL COLOR row's pair. -1 is the
         // AUTO end the slider reaches at its far left, so the clamp floor is -1.
         else if(row==4)  { g_triggerLabelTransparency=ClampInt((int)MathRound(v),-1,100); flags=REFRESH_BUFFERS; }
         else             { // row 3 — SHOW. P-PERF-32b: ONE owner paints it - the
                            // state, the persisted key, the family's own mask walk
                            // and the discrete repaint (the T hotkey and the ring's
                            // TRIGGER light call the same owner). This row used to
                            // return REFRESH_BUFFERS: the pixels were the RENDER's,
                            // so the press waited for a heavy frame. P-PERF-21 still
                            // holds: NO force-clear, the overlay owns one family.
                            SetTriggerLevelsVisible(v>0.5);
                            flags=REFRESH_NONE; }
         break;
      case 1:   // ZONES & LEVELS — main card. Row 0 = MID ZONES (ring master).
         if(row==0)       { g_showMidZones=(v>0.5);
                            // P-PERF-41: the ring's Zones & Levels light is this row
                            // AND row 1, so the ring must be repainted too.
                            RequestUISync();
                            flags=REFRESH_BUFFERS; }
         else if(row==1)  // SHOW LINES — master visibility. P-PERF-29: one owner
                          // writes the state, the mirror, the persisted key AND the
                          // object mask. This row used to skip the mask, and the
                          // P-PERF-25 render skip then trusted that: the switch did
                          // nothing until a timeframe switch rebuilt the chart.
                         { g_showLines=(v>0.5);
                           SetLinesVisible(g_showLines, true);
                           RequestUISync();   // P-PERF-41: the ring light reads this row too
                           flags=REFRESH_BUFFERS; }
         else if(row==2)  // ZONE STYLE — the picture itself (P-UI-62: Filled / Empty /
                          // Outlined, i.e. WHICH halves of the zone are drawn)
                         { ENUM_ZONE_STYLE newPicture=(ENUM_ZONE_STYLE)(int)MathRound(v);
                           // P-UI-64: A PICTURE THAT DRAWS AN EDGE BRINGS A VISIBLE WIDTH.
                           // The edge is created UNDER the band and painted OVER it (they
                           // share Z_CHART_ZONE), so at the older default of 1px half the
                           // line is covered by the band and the combined picture reads as
                           // the filled one - exactly «در حالت ترکیب خطوط سایز 5 باشن پیش
                           // فرض که دیده بشه». It fires ONLY while the width is still that
                           // older default, so a width the user chose is never overwritten,
                           // and the BORDER WIDTH row shows the value it lands on.
                           if(newPicture != ZONE_STYLE_BOX_FILLED && g_midZoneBorderWidth <= 1)
                              g_midZoneBorderWidth = MIDZONE_EDGE_VISIBLE_WIDTH;
                           g_midZoneStyle=newPicture; flags=REFRESH_BUFFERS; }
         else if(row==3)  { g_midZoneTransparency=ClampInt((int)MathRound(v),0,100); flags=REFRESH_BUFFERS; }
         else if(row==4)  { g_midZoneHeightPercent=ClampInt((int)MathRound(v),1,100); flags=REFRESH_BUFFERS; }
         else if(row==5)  { g_midZoneBorderStyle=NativeStyleFromIdx((int)MathRound(v)); flags=REFRESH_BUFFERS; }
         else if(row==6)  { g_midZoneBorderWidth=ClampInt((int)MathRound(v),1,5); flags=REFRESH_BUFFERS; }
         // P-UI-63: the EDGE's transparency - the same shape as the band's row above,
         // one owner per value (the band row writes g_midZoneTransparency, this one
         // writes the edge's). P-UI-64 rides along in the ZONE STYLE row below.
         else if(row==7)  { g_midZoneBorderTransparency=ClampInt((int)MathRound(v),0,100); flags=REFRESH_BUFFERS; }
         // P-UI-131h: the two halves' opacity. -1 is kept as the AUTO state, so the
         // clamp is its own (-1..100) and never the slider's left end.
         else if(row==16) { g_zoneEdgeTopTransparency=ClampInt((int)MathRound(v),-1,100); flags=REFRESH_BUFFERS; }
         else if(row==17) { g_zoneEdgeBottomTransparency=ClampInt((int)MathRound(v),-1,100); flags=REFRESH_BUFFERS; }
         else if(row==8)  {
                            // P-UI-67: ONE ANSWER PER QUESTION. This flag has TWO
                            // owners that both answer "which of SS/LS comes first":
                            // the chart prompt's per-chart OVERRIDE and this switch.
                            // The override WINS, so pressing the switch while a stale
                            // override existed wrote `g_lsFirst` and changed NOTHING on
                            // the chart — a dead-looking row. A press here is the
                            // user's latest explicit answer FOR THIS CHART, so it
                            // takes the question over and the override dies with it;
                            // the prompt owns the opposite direction.
                            SSLSOrderOverrideClear();
                            g_lsFirst=(v>0.5);
                            g_forceClearOnNextDraw=true; g_redrawTHLevelsNeeded=true;
                            flags=REFRESH_RECALC; }
         else if(row==9) { g_showMidpointLine=(v>0.5); flags=REFRESH_BUFFERS; }
         break;
      case 2:   // ATR LABELS — rows 0-3 are the countdown tag's OWN layer (own
                // switch/color/size/gap, independent of the ATR block); rows
                // 4-10 are the ATR block itself (g_atrLabelsVisible, hotkey A).
         if(row==0)       { g_showLiveCountdown=(v>0.5);
                            RuntimeSettingsSaveOverridesThrottled();   // OV_CD
                            RefreshLiveCountdown();
                            g_labelsRelayoutNeeded=true; flags=REFRESH_ALL; }
         else if(row==1)  { /* COUNT COLOR — the palette owns this row */ }
         else if(row==2)  { g_countdownFontSize=ClampInt((int)MathRound(v),0,24);
                            RuntimeSettingsSaveOverridesThrottled();   // OV_CDS
                            RefreshLiveCountdown();
                            g_labelsRelayoutNeeded=true; flags=REFRESH_ALL; }
         else if(row==3)  { g_countdownGapPx=ClampInt((int)MathRound(v),0,40);
                            RuntimeSettingsSaveOverridesThrottled();   // OV_CDG
                            RefreshLiveCountdown();
                            g_labelsRelayoutNeeded=true; flags=REFRESH_ALL; }
         else if(row==4)  { g_showATRLabels=(v>0.5);
                            g_atrLabelsVisible=g_showATRLabels;
                            GlobalVariableSet("Biotak_ATRLabels_"+GetCachedChartIdStr(),
                                              g_atrLabelsVisible?1.0:0.0);
                            string opA=GetLevelObjectPrefix();
                            SetATRLabelsVisibility(opA,g_atrLabelsVisible);
                            g_labelsRelayoutNeeded=true; flags=REFRESH_ALL; }
         else if(row==5)  { g_showATRTargets=(v>0.5);
                            string opB=GetLevelObjectPrefix();
                            SetATRLabelsVisibility(opB,g_atrLabelsVisible);
                            g_labelsRelayoutNeeded=true; flags=REFRESH_ALL; }
         else if(row==6)  { g_showATRTradeLabels=(v>0.5);
                            string opC=GetLevelObjectPrefix();
                            SetATRLabelsVisibility(opC,g_atrLabelsVisible);
                            g_labelsRelayoutNeeded=true; flags=REFRESH_ALL; }
         else if(row==7)  { g_showATRTradeSLLabels=(v>0.5);
                            string opD=GetLevelObjectPrefix();
                            SetATRLabelsVisibility(opD,g_atrLabelsVisible);
                            g_labelsRelayoutNeeded=true; flags=REFRESH_ALL; }
         else if(row==8)  { g_showATRTradeTPLabels=(v>0.5);
                            string opE=GetLevelObjectPrefix();
                            SetATRLabelsVisibility(opE,g_atrLabelsVisible);
                            g_labelsRelayoutNeeded=true; flags=REFRESH_ALL; }
         else if(row==9)  { g_showPipDistanceLabels=(v>0.5); g_labelsRelayoutNeeded=true; flags=REFRESH_ALL; }
         // P-UI-70d — the trade card's four knobs. Every write is clamped by the
         // SAME named bound the card's owner applies, so the slider's travel and
         // the engine's clamp cannot disagree (P-LBL-11's rule, on the panel
         // side), and every row asks for a label RELAYOUT: the card's geometry is
         // read by the label pass, so a value with no relayout is a control that
         // moves nothing until an unrelated repaint.
         else if(row==10) { g_atrLabelRowGap=ClampInt((int)MathRound(v),0,TREX_CARD_MAX_ROW_GAP);
                            g_labelsRelayoutNeeded=true; flags=REFRESH_ALL; }
         else if(row==11) { g_atrTradeFontSize=ClampInt((int)MathRound(v),0,24);
                            g_labelsRelayoutNeeded=true; flags=REFRESH_ALL; }
         else if(row==12) { g_trexStampGapRows=ClampInt((int)MathRound(v),0,TREX_CARD_MAX_GAP_ROWS);
                            g_labelsRelayoutNeeded=true; flags=REFRESH_ALL; }
         else             { g_tradeMarginBottom=ClampInt((int)MathRound(v),0,TREX_CARD_MAX_MARGIN_BOTTOM);
                            g_labelsRelayoutNeeded=true; flags=REFRESH_ALL; }
         break;
      case 3:   // TH LABELS — single source of truth is g_thLabelsMode;
                // flags are derived back from it via SyncTHFlagsFromMode()
         if(row==0)
         {
            // P-UI-44 (2026-09-13) — THE MASTER ROW WAS DEAD IN ITS OFF DIRECTION.
            // `g_showTHLabels` is NOT an independent mute: SyncTHFlagsFromMode()
            // re-derives it (and rows 1/2's mirrors) FROM `g_thLabelsMode`, so the only
            // thing this row can actually write is the MODE. Reading the mode back out
            // of the source mirrors while switching OFF is what killed the press: with
            // STANDARD on, THModeFromFlags() returned 2, the mode was re-derived to 2,
            // SyncTHFlagsFromMode() set g_showTHLabels = (mode != 0) = true again and
            // the switch snapped back ON with nothing changed. OFF is now mode 0 — the
            // same value the ring's TH cycle and the S key produce for "off" — and ON
            // restores the remembered selection, defaulting to STANDARD when none is set.
            bool masterOn=(v>0.5);
            int m0 = masterOn ? THModeFromFlags() : 0;
            if(masterOn && m0==0) { m0=g_thLastOnMode; if(m0==0) m0=2; }
            g_showTHLabels=masterOn;
            g_thLabelsMode=m0;
            SyncTHFlagsFromMode();
            GlobalVariableSet("Biotak_THLabels_"+GetCachedChartIdStr(),(double)m0);
            // Rows 1/2 DISPLAY the mirrors this press just re-derived, and a press
            // normally repaints only its OWN row (PnlUpdateRow(item,row)) — the same
            // asymmetry P-UI-40 fixed for the hotkeys. The drain repaints the open card
            // and the ring's light in this same event, so the card cannot be left
            // showing a source that is no longer drawn.
            RequestUISync();
            string opT=GetLevelObjectPrefix();
            SetTHLabelsVisibility(opT,m0);
            g_labelsRelayoutNeeded=true; flags=REFRESH_ALL;
         }
         else if(row==1 || row==2)
         {
            // P-UI-46 (2026-09-13) — rows 1/2 were the SAME one-way control row 0
            // was (P-UI-44), one line down. `if(g_showTHLabels && m1==0) m1=1;`
            // re-derived the mode the press was about to write: switching the LAST
            // lit source off left m1==0, the guard forced it back to 1, and
            // SyncTHFlagsFromMode() re-lit the switch the user had just pressed —
            // so "the last source cannot be switched off" (the residual P-UI-44
            // recorded; the user asked for it here).
            // Mode 0 IS the honest state for "no source": the ring's TH cycle, the
            // S key and the master row already write exactly that, and
            // SyncTHFlagsFromMode() then reports the master row OFF too, so the card
            // can no longer show a source that is not drawn. Switching a source ON
            // from the both-off state re-lights the master the same way.
            // Exclusive radio: one source ON turns the other OFF, never both.
            if(row==1) { bool on1=(v>0.5); g_showFractalTHs=on1; if(on1) g_showStandardTHs=false; }
            else       { bool on2=(v>0.5); g_showStandardTHs=on2; if(on2) g_showFractalTHs=false; }
            int m1=THModeFromFlags();
            g_thLabelsMode=m1;
            SyncTHFlagsFromMode();
            GlobalVariableSet("Biotak_THLabels_"+GetCachedChartIdStr(),(double)m1);
            // Row 0 (and the ring's light) display the master this press just
            // re-derived; a press repaints only its OWN row, so the other surface
            // must be asked explicitly (same asymmetry P-UI-40/44 fixed).
            RequestUISync();
            string opT2=GetLevelObjectPrefix();
            SetTHLabelsVisibility(opT2,m1);
            g_labelsRelayoutNeeded=true; flags=REFRESH_ALL;
         }
         else if(row==3)  { g_showTHTargets=(v>0.5);
                            string opT3=GetLevelObjectPrefix();
                            SetTHLabelsVisibility(opT3,g_thLabelsMode);
                            g_labelsRelayoutNeeded=true; flags=REFRESH_ALL; }
         // P-TH-01: row 4 (MARGIN BOTTOM) is spelled out rather than left to the
         // trailing `else` below, because the wiring audit reads the trailing
         // statement as answering only the card's TOP address (setting 5).
         else if(row==4)  { g_thLabelsMarginBottom=ClampInt((int)MathRound(v),10,200); g_labelsRelayoutNeeded=true; flags=REFRESH_ALL; }
         // P-TH-01 (2026-09-18) — THE TH PERCENTAGE, LIVE.
         //
         // User: «این درصد محاسبات هم th هم بشه تنظیم کرد برای تحقیقات لازم
         // دارمش» + «پنل، زنده», with the limit «بقیه دست نمیخوره روابطه به
         // جایی 66 دیگه چیزها میاد».
         //
         // The row writes ONE number, `g_thPercentOverride`, and NOTHING else:
         // every derived value (the drawn TH step, Pattern, Trigger, the label
         // strip) re-resolves through `FractalPercentScale()` on the next pass,
         // so the ladder's internal relationships cannot be broken by an edit
         // here. 0 = OFF = the professor's table, unchanged.
         //
         // THE CACHE IS THE TRAP. `CalculateTimeframeTH` stores the percentage
         // it resolved, so a knob change that did not invalidate the cache
         // would keep drawing the OLD ladder until some unrelated event (a TF
         // switch, a re-attach) happened to clear it — the classic "the slider
         // moves and nothing changes". `InvalidateTimeframeDependentCaches()`
         // is the existing owner of exactly that invalidation.
         //
         // The write is guarded by `!=` so a drag that lands on the value it
         // already holds returns REFRESH_NONE and costs nothing: a live gesture
         // sends a batch per frame, and repainting a 43200-bar chart for a
         // no-op frame is the one way this row could make the panel feel slow.
         else if(row==5)
         {
            double nv = ClampSettingDbl(v, 0.0, TH_PERCENT_OVERRIDE_MAX);
            if(nv != g_thPercentOverride)
            {
               g_thPercentOverride = nv;
               InvalidateTimeframeDependentCaches();
               g_labelsRelayoutNeeded=true; flags=REFRESH_ALL;
            }
         }
         else             { g_thLabelsMarginBottom=ClampInt((int)MathRound(v),10,200); g_labelsRelayoutNeeded=true; flags=REFRESH_ALL; }
         break;
       case 4:   // P-UI-126 — HOVER CHIP: the mode, and nothing else. The chip is a
                 // chart surface, so the switch needs no recalc (REFRESH_NONE);
                 // `CircTipModeChanged` raises or parks the banner itself.
          if(row==0) { g_UI.tipPin=(v>0.5); CircTipModeChanged(); }
          break;
       //   flags=REFRESH_NONE;
       //   break;
       // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
       case 5:   // TH3 TOOL
         if(row==0)       { g_enableTH3Tool=(v>0.5); flags=REFRESH_ALL; }
         else if(row==1)  { g_th3DrawingMode=(ENUM_TH3_DRAWING_MODE)(int)MathRound(v); flags=REFRESH_TH3; }
         else if(row==2)  { g_th3BaseStepPercent=MathMax(0.5,v); flags=REFRESH_TH3; }
         else if(row==3)  { g_th3Width=ClampInt((int)MathRound(v),1,5); flags=REFRESH_TH3; }
         else if(row==4)  { g_th3Style=NativeStyleFromIdx((int)MathRound(v)); flags=REFRESH_TH3; }
         else if(row==7)  { g_showTH3Labels=(v>0.5); flags=REFRESH_TH3; }
         // P-TH3-PB-MAN: the hand-typed pivot base, in pips. 0 = OFF (the
         // pattern TF's own ATR). A ladder input, so it re-steps every
         // pattern exactly like the rows above (REFRESH_TH3 owns the redraw
         // AND the throttled OV_ persist in ApplyRefreshFlags).
         // P-TH3-PB-UI: typing also re-projects the editor band around its
         // own centre (0 deletes it) — the band and the row never disagree.
         else if(row==8)  { g_th3PivotBasePips=MathMax(0.0,v); TH3BaseEditorSync(); flags=REFRESH_TH3; }
         break;
       case 6:   // HTF CANDLES
         // P-HTF-PROBE (2026-09-30, Touch rule 5): "the shadow vanished and the body
         // has no fill" is a LOOK, and a look only moves when one of the three flags
         // below moves. The card is the only writer, so ONE change-gated line names
         // the row and the resolved triple whenever a press really changed
         // something — a press that changed nothing stays silent.
         {
            double htfBefore = PnlCurrent(6, row);
         if(row==0)       { g_UI.showHTF=(v>0.5); flags=REFRESH_HTF; }
         else if(row==1)
         {
            // P-UI-92: option 0/1 are the DYNAMIC rungs (they follow the
            // chart TF), 2+ is a fixed period. The mode is the state; the
            // period is mirrored here only so the ring badge has a value
            // before the next resolve (ResolveHTFPeriod() recomputes).
            int opt=(int)MathRound(v);
            if(opt<=0)      { g_HTFTfMode=HTF_TF_STRUCTURE; g_HTFPeriod=ResolveAutoHTFPeriod(); }
            else if(opt==1) { g_HTFTfMode=HTF_TF_PATTERN;   g_HTFPeriod=ResolvePatternHTFPeriod(); }
            else            { g_HTFTfMode=HTF_TF_FIXED;     g_HTFPeriod=HTFPeriodFromOption(opt); }
            flags=REFRESH_HTF;
         }
          else if(row==2)  { g_HTFOpacity=100-(int)MathRound(v); flags=REFRESH_HTF; }
         else if(row==7)  { g_HTFWickWidth=ClampInt((int)MathRound(v),MIN_WIDTH,MAX_WIDTH); flags=REFRESH_HTF; }
         else if(row==8)  { g_HTFBorderWidth=ClampInt((int)MathRound(v),1,5); flags=REFRESH_HTF; }
         else if(row==9)  { g_HTFShowWicks=(v>0.5); flags=REFRESH_HTF; }
         else if(row==10) { g_HTFBoxMode=ClampInt((int)MathRound(v),0,2); flags=REFRESH_HTF; }
         // P-UI-68: the two geometry rows write through the SAME clamp the
         // engine applies on load — a slider is not the only way in (a GV from
         // another build is the other), so the bound lives in one place and
         // both callers use it.
         else if(row==11) { g_HTFShadowPct=ClampInt((int)MathRound(v),HTF_SHADOW_PCT_MIN,HTF_SHADOW_PCT_MAX); flags=REFRESH_HTF; }
         else             { g_HTFGapPct=ClampInt((int)MathRound(v),HTF_GAP_PCT_MIN,HTF_GAP_PCT_MAX); flags=REFRESH_HTF; }
         if(htfBefore != v)
            HTFProbeSettings("apply row=" + IntegerToString(row) + " v=" + DoubleToString(v, 0));
         }
         break;
      case 7:   // LINES — unified [08.4] appearance. Row 1 SHOW mirrors the
                // Zones card row 1 (same g_showLines / g_linesVisible pair).
          if(row==1)       { g_showLines=(v>0.5);
                             SetLinesVisible(g_showLines, true);   // P-PERF-29: mask included
                             flags=REFRESH_BUFFERS; }
         else if(row==2)  { g_lineWidth=ClampInt((int)MathRound(v),1,5); flags=REFRESH_BUFFERS; }
         else if(row==3)  { g_lineStyle=NativeStyleFromIdx((int)MathRound(v)); flags=REFRESH_BUFFERS; }
         else if(row==4)  { g_lineTransparency=ClampInt((int)MathRound(v),0,100); flags=REFRESH_BUFFERS; }
         break;
      case 8:   // CUSTOM PRICE PIN — the pin only
         if(row==0)       { g_customPriceLevelWidth=ClampInt((int)MathRound(v),1,5); flags=REFRESH_BUFFERS; }
         // P-UI-101: row 2 is the LOCK — the one control the hold-on-line gesture
         // exists for. It goes through the ONE owner, which is also where the
         // lock is ENFORCED (a locked line never arms) and persisted.
         else if(row==2)  { CustomPriceLineOwnLock(v > 0.5); flags=REFRESH_BUFFERS; }
         else             { g_magnetSensitivityPips=ClampInt((int)MathRound(v),0,100); RuntimeSettingsSaveOverridesThrottled(); }
         break;
      case 9:   // STEP MODE — mode segments + the SELECTED mode's own
                // settings inline below + MAX LEVELS last. Section rows
                // delegate to their home cards so behavior never diverges.
         if(row==0)
         {
            g_stepCalculationMode=(ENUM_STEP_CALCULATION_MODE)(int)MathRound(v);
            // Same confirmation the E key shows: the redraw below only
            // repositions it (RepositionAllOverlayLabels), never deletes it.
            UpdateStepModeLabel();
            g_forceClearOnNextDraw=true; g_redrawTHLevelsNeeded=true;
            flags=REFRESH_ALL;
         }
         else if(row==PnlStepMaxLevelsRow())
         {
            g_maxLevels=ClampInt((int)MathRound(v),1,500);
            g_redrawTHLevelsNeeded=true; flags=REFRESH_RECALC;
         }
         else
         {
            int sec=row-1, md=(int)g_stepCalculationMode;
            // NOTE: TH mode has no section rows (count 0).
            if(md==1) return PnlApplySet(1, 8, v);       // SS/LS ORDER (card 1 setting 8)
            if(md==3) return PnlApplySet(10, sec, v);    // Factor rows 0..6
            // COMBO section — same rails as the Factor rows above
            // (OV_CM/CP/... persist via ApplyRefreshFlags).
            if(sec==0)      { g_comboMode=(ENUM_COMBO_MODE)(int)MathRound(v); }
            else if(sec==1) { g_comboPreset=(ENUM_COMBO_PRESET)(int)MathRound(v); }
            else if(sec==2) { g_comboComp1TF=(ENUM_COMBO_TIMEFRAME_TYPE)(int)MathRound(v); }
            else if(sec==3) { g_comboComp1Step=(ENUM_COMBO_STEP_TYPE)(int)MathRound(v); }
            else if(sec==4) { g_comboOp1=(ENUM_COMBO_OPERATION)(int)MathRound(v); }
            else if(sec==5) { g_comboComp2Enabled=(v>0.5); }
            else if(sec==6) { g_comboComp2TF=(ENUM_COMBO_TIMEFRAME_TYPE)(int)MathRound(v); }
            else            { g_comboComp2Step=(ENUM_COMBO_STEP_TYPE)(int)MathRound(v); }
            g_redrawTHLevelsNeeded=true; flags=REFRESH_RECALC;
         }
         break;
       case 11:  // STRUCTURE sub-card (opened from Zones & Levels)
         // P-PERF-32: recolour-only owner (no recompute, no render — the
         // level SET is switch-invariant). REFRESH_NONE: the owner persists
         // the OV_ key and forces the discrete repaint itself (P-UI-02).
         if(row==1)       { SetStructureVisible(0, (v>0.5)); flags=REFRESH_NONE; }
         else if(row==2)  { SetStructureVisible(1, (v>0.5)); flags=REFRESH_NONE; }
         else if(row==3)  { SetStructureVisible(2, (v>0.5)); flags=REFRESH_NONE; }
         else if(row==4)  { SetStructureVisible(3, (v>0.5)); flags=REFRESH_NONE; }
         else if(row==5)  { SetStructureVisible(4, (v>0.5)); flags=REFRESH_NONE; }
         else if(row==6)  { SetStructureVisible(5, (v>0.5)); flags=REFRESH_NONE; }
         break;
      case 10:  // FACTOR
         if(row==0)       { g_factorMode=(ENUM_FACTOR_MODE)(int)MathRound(v); g_redrawTHLevelsNeeded=true; flags=REFRESH_RECALC; }
         else if(row==1)  { g_factorDisplayMode=(ENUM_FACTOR_DISPLAY_MODE)(int)MathRound(v); g_redrawTHLevelsNeeded=true; flags=REFRESH_RECALC; }
         else if(row==2)  { g_factorAutoBasis=(ENUM_FACTOR_AUTO_BASIS)(int)MathRound(v); g_redrawTHLevelsNeeded=true; flags=REFRESH_RECALC; }
         else if(row==3)  { g_factorValue=MathMax(1.0,(double)MathRound(v)); g_redrawTHLevelsNeeded=true; flags=REFRESH_RECALC; }
         else if(row==4)  { g_factorLevelWidth=ClampInt((int)MathRound(v),1,5); flags=REFRESH_BUFFERS; }
         else             { g_factorLevelStyle=NativeStyleFromIdx((int)MathRound(v)); flags=REFRESH_BUFFERS; }
         break;
       case 12:  // BASE BOX — tabbed card (row 0 = TAB). Section rows delegate
                 // to BkSecApply (same mirrors as the strip — never duplicated);
                 // OV_ persist rides on REFRESH_BUFFERS via ApplyRefreshFlags.
          if(row==0)       { g_BkTab=ClampInt((int)MathRound(v),0,2); }
          else             { flags=BkSecApply(row-1,v); }
          break;
       case 13:  // BASE BOX MINI — same mirrors as card 12, never duplicated.
          if(row==1)       { g_bkTargetR=ClampInt((int)MathRound(v),1,BK_TP_PLAN_MAX); BaseKnotRestyleAll(); flags=REFRESH_BUFFERS; }   // P-BK-50: TP COUNT
          else if(row==2)  { g_bkShowInfo=ClampInt((int)MathRound(v),0,2); BaseKnotRestyleAll(); flags=REFRESH_BUFFERS; }   // P-BK-58
          else if(row==3)  { flags=BkApplyPreset((int)MathRound(v)); }
          else if(row==4)  { if(g_BkMiniBox!="" && BaseKnotFind(g_BkMiniBox)>=0) BaseKnotSetLocked(g_BkMiniBox, v>0.5); }
          break;
      case 14:  // P-UI-131 — GENERAL SETTINGS. A MOVED row delegates to the address it
                // moved from (one clamp, one refresh flag, one OV_ key per value); a
                // GRID row writes its own mirror and asks for the relayout the label
                // pass reads.
         if(row==0)       { return PnlApplySet(9, PnlStepMaxLevelsRow(), v); }
         else if(row==1)  { g_labelFontSize=ClampSettingInt((int)MathRound(v),4,24);
                            g_labelsRelayoutNeeded=true; flags=REFRESH_ALL; }
         else if(row==2)  { g_labelRowGap=ClampSettingInt((int)MathRound(v),0,TREX_CARD_MAX_ROW_GAP);
                            g_labelsRelayoutNeeded=true; flags=REFRESH_ALL; }
         else if(row==3)  { g_labelFontIdx=ClampSettingInt((int)MathRound(v),0,LABEL_FONT_N-1);
                            g_labelsRelayoutNeeded=true; flags=REFRESH_ALL; }
         else if(row==4)  { g_labelsMarginTop=ClampSettingInt((int)MathRound(v),0,200);
                            g_labelsRelayoutNeeded=true; flags=REFRESH_ALL; }
         else if(row==5)  { g_labelsMarginLeft=ClampSettingInt((int)MathRound(v),0,300);
                            g_labelsRelayoutNeeded=true; flags=REFRESH_ALL; }
         else if(row==6)  { g_labelColumnGap=ClampSettingInt((int)MathRound(v),0,200);
                            g_labelsRelayoutNeeded=true; flags=REFRESH_ALL; }
         else if(row==7)  { g_sectionGap=ClampSettingInt((int)MathRound(v),0,200);
                            g_labelsRelayoutNeeded=true; flags=REFRESH_ALL; }
         else if(row==8)  { g_maxLabelWidth=ClampSettingInt((int)MathRound(v),50,600);
                            g_labelsRelayoutNeeded=true; flags=REFRESH_ALL; }
         else if(row==9)  { return PnlApplySet(2, 13, v); }   // CARD MARGIN
         else if(row==10) { return PnlApplySet(3, 4, v); }    // TH MARGIN
         else if(row==11) { return PnlApplySet(2, 10, v); }   // TRADE ROW GAP
         else if(row==12) { return PnlApplySet(2, 11, v); }   // TRADE SIZE
         else if(row==13) { return PnlApplySet(2, 12, v); }   // STAMP GAP
         break;   // row 14 = NAV (PnlApplySet returns before the switch for kind 5)
   }
   if(flags!=REFRESH_NONE)
   {
      UpdateCircularItemStates();
      UpdateCircularBadges();
      SaveUIStates();
   }
   return flags;
}

//+------------------------------------------------------------------+
//| Restore every row of an item to factory defaults → OR'd flags     |
//+------------------------------------------------------------------+
int PnlResetItem(const int item)
{
   int flags=REFRESH_NONE;
   int savedMask=g_PnlCollapsed[item];   // reset touches HIDDEN members too
   g_PnlCollapsed[item]=0;
   g_PnlSpecStamp[item]=0;
   int rowsCount=PnlRowsCount(item);
   for(int r=0;r<rowsCount;r++)
   {
      int rk=0; string rl="",ru="",ro=""; int rMin=0,rMax=0; double rst=1;
      PnlRowDef(item,r,rk,rl,rMin,rMax,rst,ru,ro);
      if(rk==PNL_K_SEC) continue;   // a section band restores nothing
      int f;
      if(rk==8 || rk==9)   // folded row: restore EVERY member, not just s0
      {
         f=REFRESH_NONE;
         int nm=PnlRowMembers(item,r);
         for(int mi2=0;mi2<nm;mi2++)
         {
            int sr=PnlMemberRow(item,r,mi2);
            if(sr<0) continue;
            int mk=PnlMemberKind(item,r,mi2);
            if(mk==4)
            {
               int ckind=PnlColorKindSet(item,sr);
               if(ckind>=0) f|=PaletteApplyColor(ckind,PnlDefColorSet(item,sr));
            }
            else f|=PnlApplySet(item,sr,PnlDefValSet(item,sr));
         }
      }
      else if(rk==4) f = PnlSetColor(item,r,PnlDefColor(item,r));   // restore default color
      else      f = PnlApply(item,r,PnlDefVal(item,r));
      flags|=f;
      // STEP card: restoring row 0 can switch the mode, which reshapes the
      // rows below — recount before continuing so every new row is restored.
      // Same for the Base Box TAB row (Style|Text|Setup reshape the card).
      if(item==9 && r==0) rowsCount=PnlRowsCount(item);
      if(item==12 && r==0) rowsCount=PnlRowsCount(item);
   }
   UpdateCircularItemStates();
   UpdateCircularBadges();
   SaveUIStates();
   g_PnlCollapsed[item]=savedMask;   // restore the user's collapse state…
   g_PnlSpecStamp[item]=0;            // …but rebuild through it
   if(g_PnlOpen==item) PnlRebuildKeepSpot(item);   // rebuild so widgets show restored values
   return flags;
}

//+------------------------------------------------------------------+
//| Object factories                                                  |
//+------------------------------------------------------------------+
void PnlSetLabel(const string n,const int x,const int y,const string txt,const color clr,const int sz)
{
   if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
   ObjectSetString(0,n,OBJPROP_TEXT,txt);
   ObjectSetString(0,n,OBJPROP_FONT,BioChromeFont(false));
   // P-UI-30: `sz` is a NOMINAL design size (px * 3/4); the terminal renders
   // fonts at ITS dpi, so the point size is re-expressed here once for every
   // caption in the panel.
   ObjectSetInteger(0,n,OBJPROP_FONTSIZE,PnlPt(sz));
   ObjectSetInteger(0,n,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,n,OBJPROP_ZORDER,Z_PANEL_TEXT);
}

void PnlSetRect(const string n,const int x,const int y,const int w,const int h,const color clr)
{
   if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,n,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,n,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,n,OBJPROP_BGCOLOR,clr);
   ObjectSetInteger(0,n,OBJPROP_ZORDER,Z_PANEL_BASE);
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
}

void PnlSetButton(const string n,const int x,const int y,const int w,const int h,
                  const string txt,const color bg,const color border,const bool selectable)
{
   if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,n,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,n,OBJPROP_YSIZE,h);
   ObjectSetString(0,n,OBJPROP_TEXT,txt);
   ObjectSetString(0,n,OBJPROP_FONT,BioChromeFont());
   ObjectSetInteger(0,n,OBJPROP_FONTSIZE,PnlPt(PNL_PT_CTL));   // P-UI-30
   ObjectSetInteger(0,n,OBJPROP_COLOR,PNL_CLR_TITLE);
   ObjectSetInteger(0,n,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,n,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,n,OBJPROP_BORDER_COLOR,border);
   ObjectSetInteger(0,n,OBJPROP_STATE,false);
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,selectable);
   ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,n,OBJPROP_ZORDER,Z_PANEL_CTL);
}

void PnlSetBitmap(const string n,const int x,const int y,const int w,const int h,
                  const string res,const int z)
{
   if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_BITMAP_LABEL,0,0,0);
   ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,n,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,n,OBJPROP_YSIZE,h);
   ObjectSetString(0,n,OBJPROP_BMPFILE,0,res);
   ObjectSetString(0,n,OBJPROP_BMPFILE,1,res);
   ObjectSetInteger(0,n,OBJPROP_STATE,false);
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,n,OBJPROP_BACK,false);
   ObjectSetInteger(0,n,OBJPROP_ZORDER,z);
}

//+------------------------------------------------------------------+
//| BASE BOX MINI — obsidian floating strip (item 13)                     |
//| A dark-glass toolbar (bk_strip.bmp, 380px) with light outlined      |
//| glyphs, slot-for-slot like TV's floating drawing toolbar:           |
//| [pencil → border color+TR][bucket → fill color+TR][T → Text tab]  |
//| [style ▾][width Npx ▾][padlock][trash][••• → full card 12].      |
//| Pencil/bucket/T carry a LIVE color underline bar (TV's            |
//| current-color underlines, a PnlSetRect recolored in BkMiniRefresh)|
//| STYLE/WIDTH are dropdown selectors (obsidian popovers bk_dds.bmp /|
//| bk_ddw.bmp, content-fitted widths, gold-pill selection;          |
//| the ▾ chevron is the bk_chev.bmp bitmap — a text "▼" label renders|
//| as "?" in MT4/Wine fonts); LOCK/trash act on the HELD box        |
//| (g_BkMiniBox); the strip dismisses                               |
//| TV-like via outside chart click / Esc. Same mirrors as card 12 —  |
//| never duplicated. R-BKSTRIP 2026-09-07; TV-parity 2026-09-07.     |
//+------------------------------------------------------------------+
#endif // BIOTAK_PANELS_APPLY_MQH
