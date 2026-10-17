// BiotakPanels_DynDef.mqh - split from BiotakPanels_PalB.mqh 2026-10-17 (P-SIZE-1500,
// contract item 7 "one file = one owner"): the DYNAMIC cards' row mints - the Step
// card's synthesized section rows and the Base Box tabs' row definitions (kind,
// label, value per section). Moved byte-identical, zero renames. The static 17-card
// table (PnlSetDef) and the display-row translation (PnlRowDef) stay in PalB.
#ifndef BIOTAK_PANELS_DYNDEF_MQH
#define BIOTAK_PANELS_DYNDEF_MQH

//+------------------------------------------------------------------+
//| Row descriptor — settings panels (0=Trigger Zones, 1=ZONES &     |
//| LEVELS, 2=ATR, 3=TH, 4=retired (was View Lock), 5=TH3, 6=HTF, 7=LINES (unified), |
//| 8=Custom price, 9=Step mode, 10=Factor, 11=STRUCTURE sub-card)    |
//+------------------------------------------------------------------+
void PnlStepSectionRowDef(const int s,int &kind,string &label,
                int &minV,int &maxV,double &step,string &unit,string &opts)
{
   kind=0; label=""; minV=0; maxV=100; step=1; unit=""; opts="";
   int mode=(int)g_stepCalculationMode;
   // NOTE: TH mode has no section (count 0) — it owns no level settings.
   if(mode==1)   // SS-LS — the SAME setting as Zones setting 8 (its only home now)
   {
      // P-UI-67: ONE owner for the caption (PNL_LBL_SSLS_ORDER). It used to be
      // spelled here as well as in `PnlSetDef(1,8)`, so the two surfaces could
      // drift, and the old spelling named the switch's ON state instead of the
      // question the switch answers.
      kind=1; label=PNL_LBL_SSLS_ORDER;
   }
   else if(mode==2)   // COMBO — preset or advanced components
   {
      if(s==0)      { kind=2; label="MODE"; opts="Preset|Advanced"; minV=0; maxV=1; }
       else if(s==1) { kind=2; label="PRESET"; opts="B-Med|B-Long|B-Trip|Cons|Aggr|Trend|SS|4/3|5/3"; minV=0; maxV=8; }
       else if(s==2) { kind=2; label="COMP1 TF"; opts="Sub|Trigger|Pattern|Struct"; minV=0; maxV=3; }
       else if(s==3) { kind=2; label="COMP1 STEP"; opts="TH|SS|LS|4/3|5/3"; minV=0; maxV=4; }
      else if(s==4) { kind=2; label="OP"; opts="Avg|Add|Sub|Mul|Min|Max|Wtd"; minV=0; maxV=6; }
      else if(s==5) { kind=1; label="COMP2"; }
      else if(s==6) { kind=2; label="COMP2 TF"; opts="Sub|Trigger|Pattern|Struct"; minV=0; maxV=3; }
       else          { kind=2; label="COMP2 STEP"; opts="TH|SS|LS|4/3|5/3"; minV=0; maxV=4; }
   }
   else   // FACTOR — same rows as FACTOR card 10 rows 0..6
   {
      if(s==0)      { kind=2; label="MODE"; opts="Auto|Manual"; minV=0; maxV=1; }
      else if(s==1) { kind=2; label="DISPLAY"; opts="Classic|Direct"; minV=0; maxV=1; }
      else if(s==2) { kind=2; label="BASIS"; opts="Control|SS|LS|TH|Trigger|Pattern|Structure|Combo"; minV=0; maxV=7; }
      else if(s==3) { label="VALUE"; minV=1; maxV=500; }
      else if(s==4) { label="WIDTH"; minV=1; maxV=5; }
      else if(s==5) { kind=2; label="STYLE"; opts="Solid|Dash|Dot|DashDot|DashDotDot"; minV=0; maxV=ILS_COUNT-1; }   // redesign: dropdown, not a slider
      else          { kind=4; label="COLOR"; }
   }
}

// Factory default of a STEP-card section row (s = row-1). Direct FF_ reads
// only (no PnlDefVal cross-call — this sits above it in the file).
double PnlStepSectionDefVal(const int s)
{
   int mode=(int)g_stepCalculationMode;
   // NOTE: TH mode has no section (count 0).
   if(mode==1) return (FactoryDefault(FF_LS_FIRST)>0.5)?1.0:0.0;   // SS/LS ORDER
   if(mode==2)   // COMBO
   {
      if(s==0) return (int)FactoryDefault(FF_COMBO_MODE);
      if(s==1) return (int)FactoryDefault(FF_COMBO_PRESET);
      if(s==2) return (int)FactoryDefault(FF_COMBO_C1TF);
      if(s==3) return (int)FactoryDefault(FF_COMBO_C1STEP);
      if(s==4) return (int)FactoryDefault(FF_COMBO_OP1);
      if(s==5) return (FactoryDefault(FF_COMBO_C2ON)>0.5)?1.0:0.0;
      if(s==6) return (int)FactoryDefault(FF_COMBO_C2TF);
      return (int)FactoryDefault(FF_COMBO_C2STEP);
   }
   // FACTOR — same defaults as FACTOR card 10 rows 0..6
   if(s==0) return (int)FactoryDefault(FF_FACTOR_MODE);
   if(s==1) return (int)FactoryDefault(FF_FACTOR_DISPLAY);
   if(s==2) return (int)FactoryDefault(FF_FACTOR_BASIS);
   if(s==3) return FactoryDefault(FF_FACTOR_VALUE);
   if(s==4) return FactoryDefault(FF_FACTOR_WIDTH);
   if(s==5) return (int)FactoryDefault(FF_FACTOR_STYLE);
   return 3;   // COLOR row → palette sentinel
}

// Live value of a STEP-card section row. Direct g_ reads only.
double PnlStepSectionCurrent(const int s)
{
   int mode=(int)g_stepCalculationMode;
   // NOTE: TH mode has no section (count 0).
   if(mode==1) return g_lsFirst?1.0:0.0;   // SS/LS ORDER
   if(mode==2)   // COMBO
   {
      if(s==0) return (int)g_comboMode;
      if(s==1) return (int)g_comboPreset;
      if(s==2) return (int)g_comboComp1TF;
      if(s==3) return (int)g_comboComp1Step;
      if(s==4) return (int)g_comboOp1;
      if(s==5) return g_comboComp2Enabled?1.0:0.0;
      if(s==6) return (int)g_comboComp2TF;
      return (int)g_comboComp2Step;
   }
   // FACTOR
   if(s==0) return (int)g_factorMode;
   if(s==1) return (int)g_factorDisplayMode;
   if(s==2) return (int)g_factorAutoBasis;
   if(s==3) return g_factorValue;
   if(s==4) return g_factorLevelWidth;
   if(s==5) return (int)g_factorLevelStyle;
   return 0;   // COLOR row (palette only)
}

//+------------------------------------------------------------------+
//| BASE BOX card (12) section rows — sec = row-1 (row 0 is the TAB). |
//| Style (TV Style tab): BORDER/WIDTH/STYLE/BORDER-TR/FILL/FILL-TR.   |
//| Text (TV Text tab): TEXT edit + SIZE + B|I + ALIGN + VALIGN + COLOR|
//| (VALIGN = TV's Inside-dropdown: Top|Inside|Bottom).                |
//| Setup: TP COUNT + ENTRY/STOP/TARGET + INFO + INFO SIZE (P-BK-27)   |
//| + TEMPLATE (= TV Template dropdown). Coords = drag natively,       |
//| tooltip shows live                                                |
//| (TV Coordinates); visibility automatic commit-TF + lower (TV       |
//| Visibility). kind 6 = TEXT edit field (OBJ_EDIT, MT4's one text   |
//| control — same as the palette hex field).                         |
//+------------------------------------------------------------------+
void BkSecRowDef(const int sec,int &kind,string &label,
                 int &minV,int &maxV,double &step,string &unit,string &opts)
{
   kind=0; label=""; minV=0; maxV=100; step=1; unit=""; opts="";
   if(g_BkTab == 1)   // TEXT
   {
      if(sec==0)       { kind=6; label="TEXT"; }
      else if(sec==1)  { label="SIZE"; minV=8; maxV=24; }
      else if(sec==2)  { kind=2; label="B | I"; opts="Reg|Bold|Italic|B+I"; minV=0; maxV=3; }
      else if(sec==3)  { kind=2; label="ALIGN"; opts="Left|Center|Right"; minV=0; maxV=2; }
      else if(sec==4)  { kind=2; label="VALIGN"; opts="Top|Inside|Bottom"; minV=0; maxV=2; }
      else             { kind=4; label="COLOR"; }
   }
   else if(g_BkTab == 2)   // SETUP
   {
      // P-BK-50: the box' targets are the TRADE PLAN's own TP1..TP3 now, so this row is
      // no longer an R multiple — it is HOW MANY of the plan's legs are DRAWN. Same
      // state, same GV key, same enum address: a saved chart keeps its number (4 clamps
      // into 1..3).
      if(sec==0)       { label="TP COUNT"; minV=1; maxV=BK_TP_PLAN_MAX; }
      else if(sec==1)  { kind=4; label="ENTRY COLOR"; }
      else if(sec==2)  { kind=4; label="STOP COLOR"; }
      else if(sec==3)  { kind=4; label="TARGET COLOR"; }
      // P-BK-58: three rungs — where the note LIVES is the user's own choice («بین «چسبیده به
      // باکس» و «گوشهٔ ثابت» یکی را انتخاب کند»): Auto/Show keep it on the box (they differ only
      // in the Auto grace), Corner moves it to the label family's column (`BK_NOTE_CHART`).
      else if(sec==4)  { kind=2; label="INFO"; opts="Auto|Show|Corner"; minV=0; maxV=2; }
      // P-BK-27: the readout's own size — «اطلاعات بیس نوت خیلی ریزه».
      // Same shape as the ATR card's COUNT SIZE / TRADE SIZE rows: 0 = follow
      // the card's own text size, so the freed number is the user's.
      else if(sec==6)  { label="INFO SIZE"; minV=0; maxV=24; unit="pt"; }
      else             { kind=2; label="TEMPLATE"; opts="Navy|Ocean|Mono|Custom"; minV=0; maxV=3; }
   }
   else   // STYLE
   {
      if(sec==0)       { kind=4; label="BORDER COLOR"; }
      else if(sec==1)  { label="WIDTH"; minV=1; maxV=5; }
      else if(sec==2)  { kind=2; label="STYLE"; opts="Solid|Dash|Dot|DashDot|DashDotDot"; minV=0; maxV=ILS_COUNT-1; }   // redesign: dropdown, not a slider
      else if(sec==3)  { label="BORDER TR"; unit="%"; minV=0; maxV=100; }
      else if(sec==4)  { kind=4; label="FILL COLOR"; }
      else             { label="FILL TR"; unit="%"; minV=0; maxV=100; }
   }
}
// B|I segments (0 Reg · 1 Bold · 2 Italic · 3 B+I) ↔ mirrors.
int BkBIFromMirrors() { return (g_bkBold ? 1 : 0) + (g_bkItalic ? 2 : 0); }
void BkBIToMirrors(const int i)
{
   g_bkBold = (i == 1 || i == 3);
   g_bkItalic = (i >= 2);
}
double BkSecCurrent(const int sec)
{
   if(g_BkTab == 1)
   {
      if(sec==1) return g_bkTextSize;
      if(sec==2) return BkBIFromMirrors();
      if(sec==3) return ClampInt(g_bkAlign, 0, 2);
      if(sec==4) return ClampInt(g_bkVAlign, 0, 2);
      return 0;   // TEXT edit + COLOR rows (palette/edit only)
   }
   if(g_BkTab == 2)
   {
      if(sec==0) return g_bkTargetR;
      if(sec==4) return g_bkShowInfo;
      if(sec==5) return BkPresetMatch();
      if(sec==6) return g_bkInfoFontSize;   // P-BK-27
      return 0;   // COLOR rows (palette only)
   }
   if(sec==1) return g_boxBorderWidth;
   if(sec==2) return (int)g_boxBorderStyle;
   if(sec==3) return g_boxBorderTransparency;
   if(sec==5) return g_boxFillTransparency;
   return 0;   // COLOR rows (palette only)
}
int BkSecApply(const int sec,const double v)
{
   int flags = REFRESH_NONE;
   if(g_BkTab == 1)
   {
      if(sec==1)      { g_bkTextSize=ClampInt((int)MathRound(v),8,24); BaseKnotRestyleAll(); flags=REFRESH_BUFFERS; }
      else if(sec==2) { BkBIToMirrors(ClampInt((int)MathRound(v),0,3)); BaseKnotRestyleAll(); flags=REFRESH_BUFFERS; }
      else if(sec==3) { g_bkAlign=ClampInt((int)MathRound(v),0,2); BaseKnotRestyleAll(); flags=REFRESH_BUFFERS; }
      else if(sec==4) { g_bkVAlign=ClampInt((int)MathRound(v),0,2); BaseKnotRestyleAll(); flags=REFRESH_BUFFERS; }
   }
   else if(g_BkTab == 2)
   {
      if(sec==0)      { g_bkTargetR=ClampInt((int)MathRound(v),1,BK_TP_PLAN_MAX); BaseKnotRestyleAll(); flags=REFRESH_BUFFERS; }   // P-BK-50: TP COUNT
      else if(sec==4) { g_bkShowInfo=ClampInt((int)MathRound(v),0,2); BaseKnotRestyleAll(); flags=REFRESH_BUFFERS; }   // P-BK-58: the third rung
      else if(sec==5) { flags=BkApplyPreset((int)MathRound(v)); }
      else if(sec==6) { g_bkInfoFontSize=ClampInt((int)MathRound(v),0,24); BaseKnotRestyleAll(); flags=REFRESH_BUFFERS; }   // P-BK-27
   }
   else
   {
      if(sec==1)      { g_boxBorderWidth=ClampInt((int)MathRound(v),1,5); BaseKnotRestyleAll(); flags=REFRESH_BUFFERS; }
      else if(sec==2) { g_boxBorderStyle=NativeStyleFromIdx((int)MathRound(v)); BaseKnotRestyleAll(); flags=REFRESH_BUFFERS; }
      else if(sec==3) { g_boxBorderTransparency=ClampInt((int)MathRound(v),0,100); BaseKnotRestyleAll(); flags=REFRESH_BUFFERS; }
      else if(sec==5) { g_boxFillTransparency=ClampInt((int)MathRound(v),0,100); BaseKnotRestyleAll(); flags=REFRESH_BUFFERS; }
   }
   return flags;
}
double BkSecDefVal(const int sec)
{
   if(g_BkTab == 1)
   {
      if(sec==1) return FactoryDefault(FF_BK_TEXT_SIZE);
      if(sec==2) return ((FactoryDefault(FF_BK_BOLD)>0.5)?1:0) + ((FactoryDefault(FF_BK_ITALIC)>0.5)?2:0);
      if(sec==3) return FactoryDefault(FF_BK_ALIGN);
      if(sec==4) return FactoryDefault(FF_BK_VALIGN);
      return 0;
   }
   if(g_BkTab == 2)
   {
      if(sec==0) return FactoryDefault(FF_BK_TARGET_R);
      if(sec==4) return FactoryDefault(FF_BK_SHOW_INFO);
      if(sec==5) return 0;   // TEMPLATE (Navy shipped — P-BK-69)
      if(sec==6) return FactoryDefault(FF_BK_INFO_SIZE);   // P-BK-27 (Reset → follow)
      return 3;              // COLOR rows → palette sentinel
   }
   if(sec==1) return FactoryDefault(FF_BOX_WIDTH);
   if(sec==2) return (int)FactoryDefault(FF_BOX_STYLE);
   if(sec==3) return FactoryDefault(FF_BOX_TRANSPARENCY);
   if(sec==5) return FactoryDefault(FF_BOX_FILL_TR);
   return 3;                 // COLOR rows → palette sentinel
}
int BkSecColorKind(const int row)
{
   if(row <= 0) return -1;
   int sec = row - 1;
   if(g_BkTab == 1) return (sec == 5 ? PAL_BK_TEXT : -1);
   if(g_BkTab == 2)
   {
      if(sec==1) return PAL_BK_ENTRY;
      if(sec==2) return PAL_BK_SL;
      if(sec==3) return PAL_BK_TP;
      return -1;
   }
   if(sec==0) return PAL_BOX;
   if(sec==4) return PAL_BOX_FILL;
   return -1;
}
color BkSecDefColor(const int row)
{
   if(row <= 0) return clrNONE;
   int sec = row - 1;
   if(g_BkTab == 1) return (sec == 5 ? DefBKTextColor() : clrNONE);
   if(g_BkTab == 2)
   {
      if(sec==1) return DefBKEntryColor();
      if(sec==2) return DefBKStopColor();
      if(sec==3) return DefBKTargetColor();
      return clrNONE;
   }
   if(sec==0) return DefBoxBorderColor();
   if(sec==4) return DefBoxFillColor();
   return clrNONE;
}


#endif