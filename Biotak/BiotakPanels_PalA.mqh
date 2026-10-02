// BiotakPanels_PalA.mqh - BiotakPanels split 2026-09-29: exact lines 1098-2441 of BiotakPanels.mqh, byte-identical, zero renames.
#ifndef BIOTAK_PANELS_PALA_MQH
#define BIOTAK_PANELS_PALA_MQH

void SavePalRecent()
{
   // P-PERF-27c: the palette only changes when the user picks a colour, yet the
   // teardown wrote all 13 keys and flushed the terminal's ENTIRE
   // global-variable table for them on every timeframe switch. Change-guarded
   // like the override and UI-state blocks so an untouched session costs zero.
   static double s_palShadow[PAL_RECENT_MAX/2 + 1];
   static bool   s_palKnown[PAL_RECENT_MAX/2 + 1];
   static int    s_palEpoch = -1;
   int palChanged = 0;
   // P-PERF-44: PER KEY. The old pass wrote all 13 keys whenever ONE of them
   // moved (and only reported how MANY slots differed), so the write count and
   // the block's own line could disagree.
   if(GVSlotChanged(s_palEpoch, s_palKnown, s_palShadow, 0, g_PalRecentCount))
      { GlobalVariableSet(GetGVName("PALN"), g_PalRecentCount); palChanged++; }
   for(int j = 0; j < PAL_RECENT_MAX/2; j++)
   {
      double packed = g_PalRecent[2*j] + g_PalRecent[2*j+1]*16777216.0;
      if(!GVSlotChanged(s_palEpoch, s_palKnown, s_palShadow, j + 1, packed)) continue;
      GlobalVariableSet(GetGVName("PALR"+IntegerToString(j)), packed);
      palChanged++;
   }
   // P-PERF-44 (3): report BEFORE the early return - see SaveUIStates.
   GVLedgerReport(GV_BLOCK_PALETTE, palChanged, PAL_RECENT_MAX/2 + 1);
   if(palChanged == 0) return;   // nothing changed - no writes, no disk flush
   GVFlushRequest();   // P-PERF-44 (2): ASK; the one owner commits the disk copy
}

// P-PERF-44 (1): prime the palette shadow from its own LOAD pass. This is the
// block that produced the unattributed `save=125ms`: its shadow learned its first
// value inside the teardown itself, so every timeframe switch paid 13 writes plus
// a terminal-wide GlobalVariablesFlush on a chart whose palette was never touched.
void PrimePalRecentShadow()
{
   GVShadowDryRun(true);
   SavePalRecent();
   GVShadowDryRun(false);
}

// P-PERF-44 (2): an INTERACTIVE save (a colour pick, a closing palette) is its own
// transaction - no teardown is coming to commit it - so it asks AND commits.
void SavePalRecentDurable()
{
   SavePalRecent();
   GVFlushCommit();
}

void LoadPalRecent()
{
   for(int i = 0; i < PAL_RECENT_MAX; i++) g_PalRecent[i] = clrNONE;
   g_PalRecentCount = 0;
   string n = GetGVName("PALN");
   if(GlobalVariableCheck(n))
   {
      g_PalRecentCount = ClampInt((int)GlobalVariableGet(n), 0, PAL_RECENT_MAX);
      int cnt = 0;
      for(int i = 0; i < PAL_RECENT_MAX/2 && cnt < g_PalRecentCount; i++)
      {
         string vn = GetGVName("PALR"+IntegerToString(i));
         if(!GlobalVariableCheck(vn)) continue;
         double packed = GlobalVariableGet(vn);
         int c1 = (int)MathMod(packed, 16777216.0);
         int c2 = (int)MathMod(packed / 16777216.0, 16777216.0);
         if(cnt < g_PalRecentCount) g_PalRecent[cnt++] = (color)c1;
         if(cnt < g_PalRecentCount) g_PalRecent[cnt++] = (color)c2;
      }
      g_PalRecentCount = cnt;
   }
   // P-PERF-44 (1): the shadow learns HERE, never at the teardown - including the
   // empty case (an unused palette primes "nothing to write", the same equivalence
   // an absent key has for the override table: what we would write IS what the
   // load just produced). The early return that used to sit above is what left
   // the never-primed path reachable on the commonest chart of all.
   PrimePalRecentShadow();
}

void PushPalRecent(const color clr)
{
   // P-UI-131h: clrNONE is not a colour anyone picked — it is the AUTO state (the HTF
   // wick/border overrides and the two edge halves). Pushing it put a cell nobody chose
   // into the user's own recents ring whenever a colour row was Reset.
   if(clr == clrNONE) return;
   for(int i = 0; i < g_PalRecentCount; i++)
   {
      if(g_PalRecent[i] != clr) continue;
      for(int j = i; j > 0; j--) g_PalRecent[j] = g_PalRecent[j-1];
      g_PalRecent[0] = clr;
      PalRecentPersistThrottled();
      return;
   }
   for(int i = PAL_RECENT_MAX-1; i > 0; i--) g_PalRecent[i] = g_PalRecent[i-1];
   g_PalRecent[0] = clr;
   if(g_PalRecentCount < PAL_RECENT_MAX) g_PalRecentCount++;
   PalRecentPersistThrottled();
}

// mixers fire per mouse-move → cap GlobalVariablesFlush rate; PalClose forces
// the final save so the last drag position is always persisted.
void PalRecentPersistThrottled()
{
   static uint s_LastSave = 0;
   uint now = GetTickCount();
   if(now - s_LastSave >= 400) { s_LastSave = now; SavePalRecentDurable(); }
}

//--- "RRGGBB" / "#RRGGBB" / "0xRRGGBB" → color (clrNONE when invalid)
color ParseHexColor(const string txt)
{
   string t = txt;
   StringTrimLeft(t);
   StringTrimRight(t);
   if(StringFind(t, "0x") == 0 || StringFind(t, "0X") == 0) t = StringSubstr(t, 2);
   else if(StringGetCharacter(t, 0) == '#') t = StringSubstr(t, 1);
   if(StringLen(t) != 6) return clrNONE;
   int val = 0;
   for(int i = 0; i < 6; i++)
   {
      int ch = StringGetCharacter(t, i);
      int d;
      if(ch >= '0' && ch <= '9')      d = ch - '0';
      else if(ch >= 'a' && ch <= 'f') d = ch - 'a' + 10;
      else if(ch >= 'A' && ch <= 'F') d = ch - 'A' + 10;
      else return clrNONE;
      val = val * 16 + d;
   }
   int r = val / 65536;
   int g = (val / 256) % 256;
   int b = val % 256;
   return (color)(r + g*256 + b*65536);
}

//+------------------------------------------------------------------+
//| Runtime colors are persisted by RuntimeSettings.mqh (save overrides:|
//|  OV_TC/OV_TL/OV_SC/OV_LC/OV_C3/OV_P3/OV_CC/OV_FC) and by the HTF   |
//|  engine (Biotak_HTF_* GVs) — no duplicated legacy saver needed.    |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Color palette popup — complete picker with best-practice layout  |
//|   · PALETTE tab: RECENT strip on top (no tab switch needed) + a   |
//|     the user's own palette chart (8 x 8 = 64 cells, one tap, big  |
//|     targets, a cell captioned by its own hex — P-DRAW-46)         |
//|   · MIXER tab: R/G/B sliders + hex input (MT4 ships NO native    |
//|     color picker dialog, so this replaces it entirely)           |
//|   · RECENT colors persist across reloads (PushPalRecent on every  |
//|     pick, incl. the panel-row quick swatches)                     |
//|   · APPLY TO selector: any color target — trigger, SS/LS, TH3,    |
//|     HTF candles, custom price or factor. Stays open for live     |
//|     trials; Done/Esc/click-away closes.                          |
//+------------------------------------------------------------------+
//==============================================================================
// P-DRAW-49 (2026-09-27) — THE POPUP, REDRAWN. ITS GEOMETRY IS ONE TABLE HERE
// AND THE BANDS ARE ONE ORDER, because the old popup had five numbers living at
// the paint site (`ry+5`, `+8`, `+16`, `PAL_PREV`, `PAL_TGT` from the bottom)
// and two of them had already drifted out of the card: the footer's TR track
// started at px+106 and was 100px wide inside a 201px card, so 5px of it and
// then the value label (px+212) hung on the chart.
//
// The order, top to bottom: header · READOUT · tabs · RECENT · the page's grid ·
// HEX · APPLY TO · footer. The readout is the new band and the reason the popup
// is worth reopening: the value under the pointer is IN the popup, so the pick
// never depends on a native tooltip (which also covers the cells, hides the
// chart, and arrives late).
//==============================================================================
#define PAL_W        268      // 16 + 8*26 + 7*4 + 16 — the preview's own #pop width
#define PAL_PAD      16
#define PAL_COLS     BIOPICK_COLS
#define PAL_ROWS     BIOPICK_PAGE_ROWS    // 8 — a PAGE of the 16-family table (P-DRAW-50)
#define PAL_CELLGAP  4
#define PAL_CELL_BIG 26      // the shape-A cell
#define PAL_CELL_SML 22      // the shape-B cell, for a window the big one does not fit
#define PAL_REC      22      // the recents' cell: the SAME size as a small grid cell
//--- TV parity board (2026-09-26): the HEX row's own band. It is drawn on BOTH
//--- tabs (the reference keeps the exact value beside the grid), which is why
//--- `PalH()` carries it and why the card bake (`tools/gen-th3-icons.js`, PAL_H)
//--- must be regenerated with it.
#define PAL_HX    28
#define PAL_RSHOW 8            // recents visible inline (no tab switch)
#define PAL_READ  32            // the live readout — P-DRAW-49
#define PAL_HEAD  28
#define PAL_TABS  24
#define PAL_SECL  12            // a section caption's own line
#define PAL_TGT   26
#define PAL_FOOT  30
//--- the footer's own columns: Done · TR · track · value. The TRACK is the only
//--- flexible one, and it is measured from what is left — which is the whole
//--- repair: a track with a hard-coded width inside a card that changed width is
//--- how 11px of popup ended up on the chart.
#define PAL_FT_DONE 72
#define PAL_FT_GAP  10
#define PAL_FT_TRW  18
#define PAL_FT_VALW 34
//--- P-UI-69: the recents strip can be repainted from a LIVE path, because a
//--- mixer drag shifts the list on every 30 ms tick - so its repaint is
//--- coalesced to this window WHILE a drag is live. A click repaints at once,
//--- and the mixer's release flushes the tail, so no colour is left unpainted.
#define PAL_RECENTS_MS 150
//--- P-DRAW-46/50: the grid's shape IS the owner's (8 columns of the user's own
//--- table), so these are aliases — a second pair of numbers here would be a
//--- second palette.

bool g_PalOpen = false;
int  g_PalKind = PAL_TRIGGER;      // target being edited
int  g_PalTgt  = 0;                 // cycle index of g_PalKind
int  g_PalTab  = 0;                 // 0 palette · 1 mixer · 2 recent
int  g_PalX = 0, g_PalY = 0;        // popup position
// TV parity: the title band carries the popup (same press/move/release law as
// the cards, popup-scoped state). Manual spot is parked on the first proven
// move and reused while the anchor matches; typing never lives here.
static bool s_palMoveArmed=false;
static int  s_palMoveGX=0, s_palMoveGY=0, s_palMoveLX=0, s_palMoveLY=0;
static bool s_palMoveMoved=false;
static uint s_palMoveTick=0;
static bool s_palManual=false;
static int  s_palMX=0, s_palMY=0, s_palMAnchor=-1;
int  g_PalAnchorItem = 0;           // panel the popup hangs next to
int  g_PalMixDrag = 0;              // 0 none · 1 R · 2 G · 3 B · 4 the mixer TR
                                   // · 5 the footer TR (P-UI-131k: one channel —
                                   // `PaletteMixHit` → `PaletteMixFromX`)
bool g_PalHexFocus = false;         // hex edit box has keyboard focus
int  s_PalRecentPainted = -1;       // P-UI-69: the list the recents strip shows
uint s_PalRecentAt      = 0;        // last recents repaint (drag coalescer)

int PalW() { return PAL_W; }

//--- P-DRAW-49: THE CELL SIZE IS CHOSEN, NOT ASSUMED. 26px cells are the design
//--- (30 % bigger than the 20px they replace, so they are easy to hit); 22px is
//--- the same layout 32px shorter, for a chart window the big one does not fit.
//--- ONE reader of the window height, so the card can never be taller than the
//--- window it has to live in — the old popup was a fixed 408 and simply did
//--- not fit a short chart either.
int PalCellSize()
{
   int ch=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   if(ch <= 0) ch=1080;
   return (PalHFor(PAL_CELL_BIG) + 80 <= ch) ? PAL_CELL_BIG : PAL_CELL_SML;
}

//--- the band arithmetic, ONE order, every offset from py (P-DRAW-49). The
//--- paint, the live update, the hover regions and the hit tests all read these
//--- five functions; a sixth copy of a band offset is how the footer left the
//--- card in the first place.
int PalHFor(const int cell)
{
   int gridH = PAL_ROWS*(cell+PAL_CELLGAP) - PAL_CELLGAP;
   return PAL_HEAD + PAL_READ + 8 + PAL_TABS      // header, readout, tabs
        + 10 + PAL_SECL + 5 + PAL_REC             // RECENT caption + cells
        + 10 + PAL_SECL + 16 + gridH             // the page caption + the grid
        + 10 + PAL_HX + PAL_TGT + PAL_FOOT;      // HEX, APPLY TO, footer
}
int PalH() { return PalHFor(PalCellSize()); }

int PalReadY()  { return PAL_HEAD; }
int PalTabsY()  { return PalReadY() + PAL_READ + 8; }
int PalRecCapY(){ return PalTabsY() + PAL_TABS + 10; }
int PalRecY()   { return PalRecCapY() + PAL_SECL + 5; }
int PalFamY()   { return PalRecY() + PAL_REC + 10; }
int PalGridY()  { return PalFamY() + PAL_SECL + 16; }
int PalGridH(const int cell) { return PAL_ROWS*(cell+PAL_CELLGAP) - PAL_CELLGAP; }
int PalHxY()    { return PalGridY() + PalGridH(PalCellSize()) + 10; }
int PalTgtY()   { return PalHxY() + PAL_HX; }
int PalFootY()  { return PalTgtY() + PAL_TGT; }
//--- the footer's TR track: the one flexible column, measured from what is left.
int PalTrX() { return g_PalX + PAL_PAD + PAL_FT_DONE + PAL_FT_GAP + PAL_FT_TRW + PAL_FT_GAP; }
int PalTrW() { return PAL_W - 2*PAL_PAD - (PAL_FT_DONE + PAL_FT_GAP + PAL_FT_TRW + PAL_FT_GAP + PAL_FT_VALW); }

//--- P-DRAW-46: one implementation, never a second — `BioPickColor` (include #1)
//--- owns the user's chart; this is its face for the panels' code.
color PalPickColor(const int r, const int c) { return BioPickColor(r, c); }

string PalColorText(const color clr)
{
   int r=clr%256, g=(clr/256)%256, b=clr/65536;
   return "R"+IntegerToString(r)+" G"+IntegerToString(g)+" B"+IntegerToString(b);
}

//--- P-DRAW-49: THE HEX IS #RRGGBB, LIKE EVERY OTHER HEX ON EARTH. It was not:
//--- this walked the packed MQL colour (0x00BBGGRR) from the top, so the caption
//--- and the field both showed BBGGRR — the screenshot's own proof, a red chip
//--- captioned "#5F45F0" next to "R240 G69 B95" (those two are each other's
//--- reverse) — while `ParseHexColor` below parses standard RRGGBB. So the two
//--- ends of the same field disagreed, and anything pasted from outside the
//--- popup landed reversed. One owner, one order, and the order is the LOW byte
//--- first: in MQL the low byte IS the red (C'255,0,0' is 0x0000FF), so i=2..0
//--- prints the colour backwards and i=0..2 prints what the parser reads.
string PalHexText(const color clr)
{
   string hx="";
   for(int i=0;i<3;i++) hx += PalHexByte(((int)clr>>(8*i))&0xFF);
   return hx;
}
string PalHexByte(const int v)
{
   string digits="0123456789ABCDEF";
   return StringSubstr(digits,(v>>4)&15,1) + StringSubstr(digits,v&15,1);
}

//--- DISPLAY-row spec machinery lives HERE (not beside the renderer) because
//--- MQL4 is define-before-use: the palette section below (PalKindRow /
//--- PalOpenForItem / PalUpdateLive) converts setting rows to display rows.
//--- Moved as one block 2026-09-11; no logic changed.

//+------------------------------------------------------------------+
//| STEP card (9) inline mode section — the SELECTED step mode's own  |
//| settings live right below the STEP MODE segments ("same below").  |
//| Row 0 = STEP MODE segments; rows 1..K = section; last = MAX LEVELS|
//|   TH (0):    no rows — TH has no level settings of its own (its    |
//|              FRACTAL/STANDARD flags are LABEL settings, not levels)|
//|   SS-LS (1): 1 row  — the SS/LS ORDER switch (card 1 setting 8)   |
//|   Combo (2): 8 rows — MODE/PRESET/COMP1 TF+STEP/OP/COMP2 ON+TF+STEP|
//|   Factor(3): 7 rows — mirrors of Factor card 10 rows 0..6         |
//+------------------------------------------------------------------+
int PnlStepSectionRows()
{
   switch((int)g_stepCalculationMode)
   {
      case 0:  return 0;   // TH_STEP has no level settings of its own
      case 1:  return 1;   // SS_LS_STEP
      case 2:  return 8;   // COMBO_STEP
      default: return 7;   // FACTOR_STEP
   }
}
int PnlStepMaxLevelsRow()
{
   return 1 + PnlStepSectionRows();
}

//--- one DISPLAY row of a card
struct PnlRowSpec
{
   int    kind;    // PNL_K_* (PNL_K_LEGACY = take the setting's own kind)
   int    s0;      // first SETTING index this row renders (-1 on a band)
   int    n;       // consecutive settings folded into this row (1 normally)
   string sec;     // band title           (PNL_K_SEC only)
   int    cnt;     // band counter         (PNL_K_SEC only)
   string ico;     // glyph NAME (gl_<ico>_<accent>.bmp / gl_<ico>_m.bmp)
   string key;     // hotkey badge letter ("" = none)
   string ext;     // kind-specific payload (nav text, tab icons, dual "ALL", ...)
};
#define PNL_SPEC_MAX 32                    // display rows per card (BASE BOX is the
                                           // worst static at 24 — the old 24 was
                                           // one added row away from PnlSpecAdd's
                                           // silent `return`, which DROPS the row
                                           // with no error anywhere. The gate reads
                                           // every card's spec from the source and
                                           // refuses a ceiling below it.)
PnlRowSpec g_PnlSpec[PNL_COUNT*PNL_SPEC_MAX];
int  g_PnlSpecStart[PNL_COUNT];
int  g_PnlSpecCount[PNL_COUNT];
int  g_PnlSpecStamp[PNL_COUNT];
//--- collapsible section bands (preview .acc/.collapsed intent): bit b of
//--- g_PnlCollapsed[item] hides band b's members (the band row itself stays).
//--- Session-only, all open by default = the preview. Max 4 bands per card.
int  g_PnlCollapsed[PNL_COUNT];

// ══════════════════════════════════════════════════════════════════════════
// THE DISPLAY-ROW SPEC — one entry per row the user SEES, transcribed 1:1
// from panel_all_redesign_preview.html `const CARDS`. A section band is a
// real 42px row, exactly like the preview's `.row.sec`:
//     header 56  +  rows*42  +  footer 48        (geometry LOCKED)
// so the preview's "N ROWS / M TOTAL" pairs come out as M*42.
//   PNL_K_LEGACY  = "use the setting's own kind" (PnlSetDef decides).
// A row with n>1 folds several SETTINGS into one visible row (the preview's
// `.cset` colour set and `.dual` switch pair). No setting is ever dropped:
// every setting index 0..g_PnlRows[item]-1 appears in exactly one row.
// ══════════════════════════════════════════════════════════════════════════
void PnlSpecAdd(const int item,const int kind,const int s0,const int n,
                const string ico="",const string key="",const string sec="",
                const int cnt=0,const string ext="")
{
   if(g_PnlSpecCount[item] >= PNL_SPEC_MAX) return;   // full — never overflow the slice
   int i = g_PnlSpecStart[item] + g_PnlSpecCount[item];
   g_PnlSpec[i].kind = kind;
   g_PnlSpec[i].s0   = s0;
   g_PnlSpec[i].n    = n;
   g_PnlSpec[i].sec  = sec;
   g_PnlSpec[i].cnt  = cnt;
   g_PnlSpec[i].ico  = ico;
   g_PnlSpec[i].key  = key;
   g_PnlSpec[i].ext  = ext;
   g_PnlSpecCount[item]++;
}

void PnlSpecBuild(const int item)
{
   g_PnlSpecStart[item] = item * PNL_SPEC_MAX;
   g_PnlSpecCount[item] = 0;
   if(item == 0)   // TRIGGER ZONES (cyan) — 5 settings / 7 display rows
   {
      // P-UI-131j: the card's SECOND surface gets its pair. TRANSPARENCY + COLOR own the
      // trigger ZONE; LABEL COLOR + LABEL OPACITY own the pip label on the trigger
      // family's levels. The opacity is APPENDED (address 4) so addresses 0..3 and every
      // persisted OV_ key keep their meaning; it RENDERS beside the colour row because
      // the spec order — not the address — is what the user sees.
      PnlSpecAdd(0, PNL_K_SEC, -1, 0, "", "", "ZONE APPEARANCE", 4);
      PnlSpecAdd(0, PNL_K_LEGACY, 0, 1, "contrast");
      PnlSpecAdd(0, PNL_K_LEGACY, 1, 1, "droplet");
      PnlSpecAdd(0, PNL_K_LEGACY, 2, 1, "tag");
      PnlSpecAdd(0, PNL_K_LEGACY, 4, 1, "contrast");   // LABEL OPACITY (-1 = AUTO)
      PnlSpecAdd(0, PNL_K_SEC, -1, 0, "", "", "VISIBILITY", 1);
      PnlSpecAdd(0, PNL_K_LEGACY, 3, 1, "eye");   // hotkey T lives in the header badge only
   }
   else if(item == 1)   // ZONES & LEVELS (gold) — 11 settings / 18 display rows
                        // (P-UI-131k retired the BORDER TRANSPARENCY row from the display:
                        // the two per-half opacities own the edge now. Address 7 lives on.)
   {
      PnlSpecAdd(1, PNL_K_SEC, -1, 0, "", "", "ZONES", 4);
      PnlSpecAdd(1, PNL_K_LEGACY, 0, 1, "layers");
      PnlSpecAdd(1, PNL_K_LEGACY, 1, 1, "line", "L");
      PnlSpecAdd(1, PNL_K_LEGACY, 2, 1, "square");
      PnlSpecAdd(1, PNL_K_LEGACY, 3, 1, "contrast");
      PnlSpecAdd(1, PNL_K_SEC, -1, 0, "", "", "GEOMETRY", 7);
      PnlSpecAdd(1, PNL_K_LEGACY, 4, 1, "valign");
      PnlSpecAdd(1, PNL_K_LEGACY, 5, 1, "linestyle");
      PnlSpecAdd(1, PNL_K_LEGACY, 6, 1, "weight");
      // P-UI-63's BORDER TRANSPARENCY row is RETIRED FROM THE CARD (P-UI-131k, user:
      // «اون ترنسپریتی بورد شاید لازم نباشه چون هر کدوم جدا هستش»). It was the ONE value
      // both halves fell back to, and the two per-half opacities below now own the edge;
      // the address (7), its input and its `ZBT` key all stay, so nothing renumbers and
      // the AUTO end keeps meaning what it meant (the MIDPOINT row is the precedent for
      // a setting that keeps its address and loses only its display row).
      // P-UI-131h: the EDGE's two HALVES as surfaces — the same shape the Trigger card has
      // used since the beginning (a COLOR row beside the opacity that owns that line).
      // APPENDED, so addresses 0..13 keep theirs and every persisted OV_ key still lands
      // on the row it was written for (the P-UI-131/126 precedent).
      PnlSpecAdd(1, PNL_K_LEGACY, 14, 1, "droplet");
      PnlSpecAdd(1, PNL_K_LEGACY, 15, 1, "droplet");
      PnlSpecAdd(1, PNL_K_LEGACY, 16, 1, "contrast");
      PnlSpecAdd(1, PNL_K_LEGACY, 17, 1, "contrast");
      // P-UI-67: the ORDER band held exactly ONE row — the SS/LS sequence order —
      // and that question belongs to the SS-LS STEP MODE, not to Zones & Levels:
      // `def.lsFirst` is assigned in ModeDefinitions ONLY for `SS_LS_STEP`, so in
      // TH (the shipped default) / Combo / Factor the switch could not change one
      // pixel, and the user's words were «باید در مود SS/LS باشه اینجا چیکار میکنه».
      // The row now lives ONLY inside the Step card's SS-LS ENGINE section, which
      // is the one surface that exists exactly when the setting is read; the
      // setting keeps address 8 (nothing else moved), so the Step card's
      // delegation `PnlApplySet(1, 8, v)` and the persisted `LF` key are unchanged.
      //
      // MIDPOINT-OFF (2026-09-13): the midpoint LINE is retired — the pipeline
      // deletes every `_Midpoint_` object on each render (CleanupSurplusPipeline
      // "legacy cleanup", LevelPipeline), so its switch wrote a flag that NO
      // module reads and changed nothing on the chart (P-UI-47). That row is gone
      // too; setting 9 stays persisted and inert so the addresses above it do not
      // move.
      PnlSpecAdd(1, PNL_K_SEC, -1, 0, "", "", "SUB-CARDS", 4);
      PnlSpecAdd(1, PNL_K_LEGACY, 10, 1, "steps", "", "", 0, "5 LEVELS");
      PnlSpecAdd(1, PNL_K_LEGACY, 11, 1, "line", "", "", 0, "ONE STYLE");
      // P-UI-126: APPENDED (row 12), so every address above keeps its number and a
      // persisted override from an older build still loads into the row it was
      // written for. It is the hover chip's only door — the card itself is reached
      // from here.
      PnlSpecAdd(1, PNL_K_LEGACY, 12, 1, "tag", "", "", 0, "HOVER CHIP");
      // P-UI-131: the GENERAL card's door on the main card, APPENDED (row 13) the
      // same way P-UI-126 added the row above.
      PnlSpecAdd(1, PNL_K_LEGACY, 13, 1, "info", "", "", 0, "GENERAL");
   }
   else if(item == 2)   // ATR LABELS (gold) — 14 display rows, 19 addresses: 10..13
                        // (the trade card's grid) render on the GENERAL card now
                        // (P-UI-131) while their addresses stay here.
   {
      PnlSpecAdd(2, PNL_K_SEC, -1, 0, "", "", "COUNTDOWN", 4);
      PnlSpecAdd(2, PNL_K_LEGACY, 0, 1, "timer", "C");
      PnlSpecAdd(2, PNL_K_LEGACY, 1, 1, "droplet");
      PnlSpecAdd(2, PNL_K_LEGACY, 2, 1, "textsize");
      PnlSpecAdd(2, PNL_K_LEGACY, 3, 1, "gap");
      PnlSpecAdd(2, PNL_K_SEC, -1, 0, "", "", "ATR BLOCK", 2);
      PnlSpecAdd(2, PNL_K_DUAL, 4, 2, "gauge");   // ATR LABELS · ATR TARGETS in one row (15→14 rows)
      PnlSpecAdd(2, PNL_K_SEC, -1, 0, "", "", "TRADE PLAN ROWS", 4);
      PnlSpecAdd(2, PNL_K_LEGACY, 6, 1, "tag", "T");
      PnlSpecAdd(2, PNL_K_LEGACY, 7, 1, "crosshair", "H");
      PnlSpecAdd(2, PNL_K_LEGACY, 8, 1, "flag", "P");
      PnlSpecAdd(2, PNL_K_LEGACY, 9, 1, "ruler");
      // P-UI-70d: the trade card's personalisation band. The four rows below
      // write the SAME settings the group-13 dialog inputs write (ROW GAP ->
      // P-UI-131: the whole TRADE CARD band moved to the GENERAL card (ROW GAP,
      // TRADE SIZE, STAMP GAP — plus CARD MARGIN before it). All four addresses
      // stay HERE and the GENERAL rows delegate to them (PnlApplySet(2, 10..13)),
      // so the persisted OV_AG/ATS/ASG/AMB keys keep their meaning. This card
      // keeps what only this card owns: the countdown tag, the label switches and
      // the five colours — folded into ONE .cset row the way the HTF card folds
      // its four (P-UI-70d). The order is the drawing order (TR, ex, Hunter,
      // #SL/TP, spread) and the addresses are consecutive, so the palette's cell
      // ring and the persisted keys stay readable.
      PnlSpecAdd(2, PNL_K_SEC, -1, 0, "", "", "CARD COLORS", 1);
      PnlSpecAdd(2, PNL_K_CSET, 14, 5);
   }
   else if(item == 3)   // TH LABELS (ember) — 6 addresses / 8 display rows
                        // (P-UI-131: MARGIN BOTTOM renders on the GENERAL card)
   {
      PnlSpecAdd(3, PNL_K_SEC, -1, 0, "", "", "TH SOURCES", 3);
      PnlSpecAdd(3, PNL_K_LEGACY, 0, 1, "wave");
      PnlSpecAdd(3, PNL_K_LEGACY, 1, 1, "steps");
      PnlSpecAdd(3, PNL_K_LEGACY, 2, 1, "wave");
      PnlSpecAdd(3, PNL_K_SEC, -1, 0, "", "", "TARGETS", 1);
      PnlSpecAdd(3, PNL_K_LEGACY, 3, 1, "target");
      // P-TH-01: TH PERCENT lives here, not in a band of its own, on purpose:
      // the card is 8 display rows and `PNL_WIDE_MIN_ROWS` is 10, so a ninth
      // row keeps it NARROW. A tenth would flip the whole card to the
      // two-column layout — a redesign, not a research knob.
      // P-UI-131: MARGIN BOTTOM (address 4) moved to the GENERAL card's grid — it
      // is a label-grid floor, not a TH-source setting — so this band is one row
      // and the card is EIGHT display rows (a ninth would flip it to two columns).
      PnlSpecAdd(3, PNL_K_SEC, -1, 0, "", "", "LAYOUT", 1);
      PnlSpecAdd(3, PNL_K_LEGACY, 5, 1, "sigma");
   }
    // TH3TOOL-ON (2026-09-19): the TH3 card is back. Its 8 settings keep their
    // addresses (g_PnlRows[5] was left dormant at 8), so a persisted OV/GV from
    // before the retirement still loads into the row it was written for.
    // P-TH3-PB-MAN (2026-09-21): row 8 APPENDED — the hand-typed pivot base, in
    // pips. Appended last, so rows 0..7 keep their addresses AND their display
    // order; the BASE band renders after LABELS.
    // P-UI-126 (2026-09-25): the retired VIEW LOCK card (slot 4, one dormant row kept
   // for the address space) is REVIVED as the hover chip's own card. The chip stopped
   // chasing the orb («این حالت‌ها گوشه هم باید درست بشه») and got a place and a mode
   // of its own; both are user settings, so they belong on a card — and this one is
   // reached from the main card's SUB-CARDS band (its own NAV row), so the option is
   // findable without inventing a ring item.
   else if(item == 4)   // HOVER CHIP — 1 setting / 2 display rows
   {
      PnlSpecAdd(4, PNL_K_SEC, -1, 0, "", "", "THE CHIP", 1);
      PnlSpecAdd(4, PNL_K_LEGACY, 0, 1, "tag");
   }
   else if(item == 5)   // TH3 TOOL (violet) — 9 settings / 13 display rows
    {
       PnlSpecAdd(5, PNL_K_SEC, -1, 0, "", "", "ENGINE", 3);
       PnlSpecAdd(5, PNL_K_LEGACY, 0, 1, "power");
       PnlSpecAdd(5, PNL_K_LEGACY, 1, 1, "swap");
       PnlSpecAdd(5, PNL_K_LEGACY, 2, 1, "sigma");
       PnlSpecAdd(5, PNL_K_SEC, -1, 0, "", "", "LOOK", 2);
       PnlSpecAdd(5, PNL_K_LEGACY, 3, 1, "weight");
       PnlSpecAdd(5, PNL_K_LEGACY, 4, 1, "linestyle");
       PnlSpecAdd(5, PNL_K_SEC, -1, 0, "", "", "COLORS", 2);
       PnlSpecAdd(5, PNL_K_LEGACY, 5, 1, "droplet");
       PnlSpecAdd(5, PNL_K_LEGACY, 6, 1, "droplet");
       PnlSpecAdd(5, PNL_K_SEC, -1, 0, "", "", "LABELS", 1);
       PnlSpecAdd(5, PNL_K_LEGACY, 7, 1, "tag");
       PnlSpecAdd(5, PNL_K_SEC, -1, 0, "", "", "BASE", 1);
       PnlSpecAdd(5, PNL_K_LEGACY, 8, 1, "sigma");
    }
   else if(item == 6)   // HTF CANDLES — 13 settings / 14 display rows
   {                    // the 4 colours fold into ONE .cset row
      PnlSpecAdd(6, PNL_K_SEC, -1, 0, "", "", "SOURCE", 2);
      PnlSpecAdd(6, PNL_K_LEGACY, 0, 1, "power");
      PnlSpecAdd(6, PNL_K_LEGACY, 1, 1, "clock");
      PnlSpecAdd(6, PNL_K_SEC, -1, 0, "", "", "COLORS", 4, "strip");
      PnlSpecAdd(6, PNL_K_CSET, 3, 4);
      PnlSpecAdd(6, PNL_K_SEC, -1, 0, "", "", "APPEARANCE", 3);
      PnlSpecAdd(6, PNL_K_LEGACY, 2, 1, "contrast");
      PnlSpecAdd(6, PNL_K_LEGACY, 7, 1, "weight");
      PnlSpecAdd(6, PNL_K_LEGACY, 8, 1, "weight");
      // P-UI-68: the band is the CANDLE (body + shadow + the gap between two
      // candles), not just the body, because the shadow is now a BOX whose
      // geometry is a first-class setting. Two rows APPENDED (11, 12): every
      // address above them keeps its number, so a persisted OV/GV from an
      // older build still loads into the setting it was written for.
      PnlSpecAdd(6, PNL_K_SEC, -1, 0, "", "", "CANDLE", 2);
      PnlSpecAdd(6, PNL_K_LEGACY, 9, 1, "wick");
      PnlSpecAdd(6, PNL_K_LEGACY, 10, 1, "squarefill");
      PnlSpecAdd(6, PNL_K_LEGACY, 11, 1, "candle");
      PnlSpecAdd(6, PNL_K_LEGACY, 12, 1, "gap");
   }
   else if(item == 7)   // LINES (jade) — 6 settings / 11 display rows
   {
      PnlSpecAdd(7, PNL_K_LEGACY, 0, 1, "back", "", "", 0, "ZONES & LEVELS");
      PnlSpecAdd(7, PNL_K_SEC, -1, 0, "", "", "VISIBILITY", 1);
      PnlSpecAdd(7, PNL_K_LEGACY, 1, 1, "eye");
      PnlSpecAdd(7, PNL_K_SEC, -1, 0, "", "", "APPEARANCE", 3);
      PnlSpecAdd(7, PNL_K_LEGACY, 2, 1, "weight");
      PnlSpecAdd(7, PNL_K_LEGACY, 3, 1, "linestyle");
      PnlSpecAdd(7, PNL_K_LEGACY, 4, 1, "contrast");
      PnlSpecAdd(7, PNL_K_SEC, -1, 0, "", "", "COLOR", 1);
      PnlSpecAdd(7, PNL_K_LEGACY, 5, 1, "droplet");
   }
   else if(item == 8)   // CUSTOM PRICE (violet) — 4 settings / 2 bands + 4 rows
   {
      // P-UI-101 (2026-09-22): THE LOCK COMES FIRST. The user reaches this card
      // by holding the line («روی خط کاستوم پرایس که هولد کردم پنل تنظیماتش بازه
      // بشه و بشه از اونجا قفلش کرد»), and the one thing that gesture is for is
      // the lock — so it is the first row, above the look settings. It has no
      // glyph chip on purpose: the padlock art belongs to the box strip
      // (bk_lock_*.bmp), and a row may carry none (PnlPaintChip returns early).
      PnlSpecAdd(8, PNL_K_SW, 2, 1, "");
      PnlSpecAdd(8, PNL_K_SEC, -1, 0, "", "", "PIN", 2);
      PnlSpecAdd(8, PNL_K_LEGACY, 0, 1, "weight");
      PnlSpecAdd(8, PNL_K_LEGACY, 1, 1, "droplet");
      // BKMAGNET2-OFF (2026-09-15, user decision): the MAGNET band and its two
      // rows are hidden again — the engine is commented, so the rows have no
      // reader by construction (P-UI-47's shape). Setting 3 stays persisted and
      // inert; setting 2 is the LOCK's now (P-UI-101), never the magnet's.
   }
   else if(item == 9)   // STEP MODE (violet) — TAB row + the OPEN MODE's section
   {                    // (MAX LEVELS moved to the GENERAL card — P-UI-131).
      int mode = (int)g_stepCalculationMode;
      PnlSpecAdd(9, PNL_K_LEGACY, 0, 1, "steps", "", "", 0, "wave|swap|fn|sigma");
      int base    = 1;
      if(mode == 2)   // COMBO — the 8 component rows
      {
         PnlSpecAdd(9, PNL_K_SEC, -1, 0, "", "", "COMPONENT 1", 5);
         PnlSpecAdd(9, PNL_K_LEGACY, base+0, 1, "fn");
         PnlSpecAdd(9, PNL_K_LEGACY, base+1, 1, "sparkles");
         PnlSpecAdd(9, PNL_K_LEGACY, base+2, 1, "clock");
         PnlSpecAdd(9, PNL_K_LEGACY, base+3, 1, "sigma");
         PnlSpecAdd(9, PNL_K_LEGACY, base+4, 1, "fn");
         PnlSpecAdd(9, PNL_K_SEC, -1, 0, "", "", "COMPONENT 2", 3);
         PnlSpecAdd(9, PNL_K_LEGACY, base+5, 1, "layers");
         PnlSpecAdd(9, PNL_K_LEGACY, base+6, 1, "clock");
         PnlSpecAdd(9, PNL_K_LEGACY, base+7, 1, "sigma");
      }
      else if(mode == 1)   // SS-LS — one row (the SS/LS ORDER switch)
      {
         PnlSpecAdd(9, PNL_K_SEC, -1, 0, "", "", "ENGINE", 1);
         PnlSpecAdd(9, PNL_K_LEGACY, base, 1, "swap");
      }
      else if(mode == 3)   // FACTOR — mirrors card 10 rows 0..6
      {
         PnlSpecAdd(9, PNL_K_SEC, -1, 0, "", "", "ENGINE", 3);
         PnlSpecAdd(9, PNL_K_LEGACY, base+0, 1, "fn");
         PnlSpecAdd(9, PNL_K_LEGACY, base+1, 1, "eye");
         PnlSpecAdd(9, PNL_K_LEGACY, base+2, 1, "layers");
         PnlSpecAdd(9, PNL_K_SEC, -1, 0, "", "", "LEVEL LOOK", 3);
         PnlSpecAdd(9, PNL_K_LEGACY, base+3, 1, "sigma");
         PnlSpecAdd(9, PNL_K_LEGACY, base+4, 1, "weight");
         PnlSpecAdd(9, PNL_K_LEGACY, base+5, 1, "linestyle");
         PnlSpecAdd(9, PNL_K_SEC, -1, 0, "", "", "COLOR", 1);
         PnlSpecAdd(9, PNL_K_LEGACY, base+6, 1, "droplet");
      }
      // P-UI-131: MAX LEVELS and its LIMIT band live on the GENERAL card now (an
      // engine ceiling is not a step mode), so TH mode — the shipped default — is a
      // lone TAB row. Its branch in PnlSetDef/DefVal/Current/Apply STAYS: the GENERAL
      // row delegates to `PnlStepMaxLevelsRow()`.
   }
   else if(item == 10)  // FACTOR (ember) — 7 settings / 10 display rows
   {
      PnlSpecAdd(10, PNL_K_SEC, -1, 0, "", "", "ENGINE", 3);
      PnlSpecAdd(10, PNL_K_LEGACY, 0, 1, "fn");
      PnlSpecAdd(10, PNL_K_LEGACY, 1, 1, "eye");
      PnlSpecAdd(10, PNL_K_LEGACY, 2, 1, "layers");
      PnlSpecAdd(10, PNL_K_SEC, -1, 0, "", "", "LEVEL LOOK", 3);
      PnlSpecAdd(10, PNL_K_LEGACY, 3, 1, "sigma");
      PnlSpecAdd(10, PNL_K_LEGACY, 4, 1, "weight");
      PnlSpecAdd(10, PNL_K_LEGACY, 5, 1, "linestyle");
      PnlSpecAdd(10, PNL_K_SEC, -1, 0, "", "", "COLOR", 1);
      PnlSpecAdd(10, PNL_K_LEGACY, 6, 1, "droplet");
   }
   else if(item == 11)  // STRUCTURE LEVELS (ember) — 5 toggles in 3 dual rows
   {
      PnlSpecAdd(11, PNL_K_LEGACY, 0, 1, "back", "", "", 0, "ZONES & LEVELS");
      PnlSpecAdd(11, PNL_K_SEC, -1, 0, "", "", "STRUCTURE", 1);
      PnlSpecAdd(11, PNL_K_LEGACY, 1, 1, "steps");
      PnlSpecAdd(11, PNL_K_SEC, -1, 0, "", "", "LEVEL TOGGLES", 5);
      PnlSpecAdd(11, PNL_K_DUAL, 2, 2, "layers");            // L1 · L2
      PnlSpecAdd(11, PNL_K_DUAL, 4, 2, "layers");            // L3 · L4
      PnlSpecAdd(11, PNL_K_DUAL, 6, 1, "layers", "", "", 0, "ALL");  // L5 · ALL
   }
   else if(item == 12)  // BASE BOX (gold) — TAB row + the open tab's section
   {                    // (+ the redesign's .cset for the Setup leg colours)
      PnlSpecAdd(12, PNL_K_LEGACY, 0, 1, "box", "", "", 0, "square|type|target");
      if(g_BkTab == 1)        // TEXT — 6 rows
      {
         PnlSpecAdd(12, PNL_K_SEC, -1, 0, "", "", "CONTENT", 1);
         PnlSpecAdd(12, PNL_K_LEGACY, 1, 1, "type");
         PnlSpecAdd(12, PNL_K_SEC, -1, 0, "", "", "TYPOGRAPHY", 5);
         PnlSpecAdd(12, PNL_K_LEGACY, 2, 1, "textsize");
         PnlSpecAdd(12, PNL_K_LEGACY, 3, 1, "bold");
         PnlSpecAdd(12, PNL_K_LEGACY, 4, 1, "alignC");
         PnlSpecAdd(12, PNL_K_LEGACY, 5, 1, "valign");
         PnlSpecAdd(12, PNL_K_LEGACY, 6, 1, "droplet");
      }
      else if(g_BkTab == 2)   // SETUP — 7 rows, the 3 leg colours in ONE row
                              // (P-BK-27 added INFO SIZE to the EXTRAS band)
      {
         PnlSpecAdd(12, PNL_K_SEC, -1, 0, "", "", "RISK / REWARD", 1);
         PnlSpecAdd(12, PNL_K_LEGACY, 1, 1, "target");
         PnlSpecAdd(12, PNL_K_SEC, -1, 0, "", "", "LEG COLORS", 3, "strip");
         PnlSpecAdd(12, PNL_K_CSET, 2, 3);
         PnlSpecAdd(12, PNL_K_SEC, -1, 0, "", "", "EXTRAS", 3);
         PnlSpecAdd(12, PNL_K_LEGACY, 5, 1, "info");
         PnlSpecAdd(12, PNL_K_LEGACY, 7, 1, "textsize");   // P-BK-27 INFO SIZE
         PnlSpecAdd(12, PNL_K_LEGACY, 6, 1, "template");
      }
      else                    // STYLE — 6 rows
      {
         PnlSpecAdd(12, PNL_K_SEC, -1, 0, "", "", "BORDER", 3);
         PnlSpecAdd(12, PNL_K_LEGACY, 1, 1, "droplet");
         PnlSpecAdd(12, PNL_K_LEGACY, 2, 1, "weight");
         PnlSpecAdd(12, PNL_K_LEGACY, 3, 1, "linestyle");
         PnlSpecAdd(12, PNL_K_SEC, -1, 0, "", "", "FILL", 3);
         PnlSpecAdd(12, PNL_K_LEGACY, 4, 1, "contrast");
         PnlSpecAdd(12, PNL_K_LEGACY, 5, 1, "droplet");
         PnlSpecAdd(12, PNL_K_LEGACY, 6, 1, "contrast");
      }
   }
   // P-UI-131 — GENERAL SETTINGS: the settings no single drawing owns, grouped by
   // the question they answer. 15 rows in 4 bands — over PNL_WIDE_MIN_ROWS, so the
   // card is the TWO-COLUMN 624px layout and its pair-lines (14) set the skin.
   else if(item == 14)
   {
      PnlSpecAdd(14, PNL_K_SEC, -1, 0, "", "", "ENGINE", 1);
      PnlSpecAdd(14, PNL_K_LEGACY, 0, 1, "steps");
      PnlSpecAdd(14, PNL_K_SEC, -1, 0, "", "", "LABEL GRID", 10);
      PnlSpecAdd(14, PNL_K_LEGACY, 1, 1, "textsize");
      PnlSpecAdd(14, PNL_K_LEGACY, 2, 1, "gap");
      PnlSpecAdd(14, PNL_K_LEGACY, 3, 1, "type");    // FONT — the list, as a dropdown
      PnlSpecAdd(14, PNL_K_LEGACY, 4, 1, "valign");
      PnlSpecAdd(14, PNL_K_LEGACY, 5, 1, "alignL");
      PnlSpecAdd(14, PNL_K_LEGACY, 6, 1, "gap");
      PnlSpecAdd(14, PNL_K_LEGACY, 7, 1, "layers");
      PnlSpecAdd(14, PNL_K_LEGACY, 8, 1, "ruler");
      // CARD MARGIN and TH MARGIN read the addresses they were WRITTEN AT (cards 2
      // and 3) — the rows left those cards, the values did not move.
      PnlSpecAdd(14, PNL_K_LEGACY, 9, 1, "valign");
      PnlSpecAdd(14, PNL_K_LEGACY, 10, 1, "valign");
      PnlSpecAdd(14, PNL_K_SEC, -1, 0, "", "", "TRADE CARD", 3);
      PnlSpecAdd(14, PNL_K_LEGACY, 11, 1, "gap");
      PnlSpecAdd(14, PNL_K_LEGACY, 12, 1, "textsize");
      PnlSpecAdd(14, PNL_K_LEGACY, 13, 1, "valign");
      PnlSpecAdd(14, PNL_K_SEC, -1, 0, "", "", "INTERFACE", 1);
      // the chip's own card OWNS its mode, so this band is a DOOR: the NAV row
      // keeps ONE home for the mode and makes card 4 reachable from here too.
      PnlSpecAdd(14, PNL_K_LEGACY, 14, 1, "tag", "", "", 0, "HOVER CHIP");
   }
}

//--- which cards have a display spec at all (item 13 is the mini STRIP — it
//--- renders no rows, so its row space stays IDENTITY-mapped. Never give 13
//--- a spec: PnlColorKind(13,0) = PAL_BOX depends on the identity fallback.)
bool PnlSpecCard(const int item)
{
   if(item==0 || item==1 || item==2 || item==3) return true;
   if(item==4) return true;   // P-UI-126: the hover chip's card (was the retired VIEW LOCK)
   if(item==5) return true;   // TH3TOOL-ON (2026-09-19): the TH3 card has a spec now
   if(item==6 || item==7 || item==8) return true;
   if(item==9 || item==10 || item==11 || item==12) return true;
   if(item==14) return true;   // P-UI-131: the GENERAL card
   return false;
}

//--- the dynamic cards (9 Step, 12 Base Box) rebuild when their input changes
void PnlEnsureSpec(const int item)
{
   if(item < 0 || item >= PNL_COUNT) return;
   if(!PnlSpecCard(item)) { g_PnlSpecCount[item] = 0; return; }
   int stamp = 1;
   if(item == 9)  stamp = 1 + (int)g_stepCalculationMode;   // section swaps with mode
   if(item == 12) stamp = 10 + g_BkTab;                     // tab swaps the section
   if(g_PnlSpecStamp[item] != stamp)
   {
      PnlSpecBuild(item);
      g_PnlSpecStamp[item] = stamp;
   }
   // collapse: drop members of collapsed bands (bands always stay visible).
   // Runs on the same rebuild so every row engine (counts, hits, palette map)
   // sees the short card with zero extra branches.
   if(g_PnlCollapsed[item] != 0 && g_PnlSpecCount[item] > 0)
   {
      PnlRowSpec kept[PNL_SPEC_MAX];
      int nk = 0, b = -1;
      for(int r=0;r<g_PnlSpecCount[item];r++)
      {
         int si = g_PnlSpecStart[item] + r;
         if(g_PnlSpec[si].kind == PNL_K_SEC) b++;
         if(g_PnlSpec[si].kind == PNL_K_SEC || !PnlBandCollapsed(item,b))
            kept[nk++] = g_PnlSpec[si];
      }
      for(int w=0;w<nk;w++) g_PnlSpec[g_PnlSpecStart[item]+w] = kept[w];
      g_PnlSpecCount[item] = nk;
   }
}

int PnlSpecRows(const int item)
{
   if(item < 0 || item >= PNL_COUNT) return 0;
   PnlEnsureSpec(item);
   return g_PnlSpecCount[item];
}

//--- display row -> its spec slot (-1 when out of range)
int PnlSpecIdx(const int item,const int dispRow)
{
   if(item < 0 || item >= PNL_COUNT) return -1;
   PnlEnsureSpec(item);
   if(dispRow < 0 || dispRow >= g_PnlSpecCount[item]) return -1;
   return g_PnlSpecStart[item] + dispRow;
}

//--- display row -> FIRST SETTING it renders (-1 = section band, no setting)
//--- A card without a spec (item 13 mini strip) is IDENTITY-mapped.
int PnlSetRow(const int item,const int dispRow)
{
   if(item < 0 || item >= PNL_COUNT) return -1;
   PnlEnsureSpec(item);
   if(g_PnlSpecCount[item] == 0) return dispRow;
   int si = PnlSpecIdx(item,dispRow);
   if(si < 0) return -1;
   return g_PnlSpec[si].s0;
}

//--- ordinal of the section band at/before a display row (-1 = none yet).
//--- Counts SEC slots directly (no PnlSetDef) so it works from anywhere.
int PnlBandIndex(const int item,const int dispRow)
{
   if(item < 0 || item >= PNL_COUNT) return -1;
   PnlEnsureSpec(item);
   int b = -1;
   for(int r=0;r<=dispRow && r<g_PnlSpecCount[item];r++)
   {
      int si = g_PnlSpecStart[item] + r;
      if(g_PnlSpec[si].kind == PNL_K_SEC) b++;
   }
   return b;
}
bool PnlBandCollapsed(const int item,const int band)
{
   if(item < 0 || item >= PNL_COUNT || band < 0 || band > 30) return false;
   return ((g_PnlCollapsed[item] >> band) & 1) != 0;
}
//--- flip a band + force the spec to rebuild (stamp 0 always rebuilds)
void PnlToggleBand(const int item,const int band)
{
   if(item < 0 || item >= PNL_COUNT || band < 0 || band > 30) return;
   if(PnlBandCollapsed(item,band)) g_PnlCollapsed[item] &= ~(1 << band);
   else                             g_PnlCollapsed[item] |=  (1 << band);
   g_PnlSpecStamp[item] = 0;
}

//--- palette kind → the panel COLOR row that shows it (for live refresh)
bool PalKindRow(const int kind,int &item,int &row)
{
   switch(kind)
   {
      case PAL_TRIGGER:        item=0;  row=1; return true;
      case PAL_TRIGGER_LABEL:  item=0;  row=2; return true;
      // PAL_SS / PAL_LS have no panel COLOR row anymore (lines are unified
      // on the Lines card; the SS/LS inputs are legacy) — no live row to refresh.
      case PAL_TH3:            item=5;  row=5; return true;
      case PAL_TH3_PIP:        item=5;  row=6; return true;
      case PAL_HTF_BULL:       item=6;  row=3; return true;
      case PAL_HTF_BEAR:       item=6;  row=4; return true;
      case PAL_HTF_WICK:       item=6;  row=5; return true;
      case PAL_HTF_BORDER:     item=6;  row=6; return true;
      case PAL_LINE:           item=7;  row=5; return true;
      case PAL_BOX:            if(g_PnlOpen==13) { item=13; row=0; return true; }
                                   if(g_PnlOpen==12 && g_BkTab==0) { item=12; row=1; return true; }
                                   return false;   // other tab open — nothing to refresh there
      case PAL_BOX_FILL:       if(g_PnlOpen==13) { item=13; row=0; return true; }   // strip bucket: refresh TBbar1 underline too
                                   if(g_PnlOpen==12 && g_BkTab==0) { item=12; row=5; return true; }
                                   return false;
      case PAL_BK_TEXT:        if(g_PnlOpen==12 && g_BkTab==1) { item=12; row=6; return true; }
                                   return false;
      case PAL_BK_ENTRY:       if(g_PnlOpen==12 && g_BkTab==2) { item=12; row=2; return true; }
                                   return false;
      case PAL_BK_SL:          if(g_PnlOpen==12 && g_BkTab==2) { item=12; row=3; return true; }
                                   return false;
      case PAL_BK_TP:          if(g_PnlOpen==12 && g_BkTab==2) { item=12; row=4; return true; }
                                   return false;
      case PAL_CUSTOM_PRICE:   item=8;  row=1; return true;
      case PAL_FACTOR:         if(g_PnlOpen==9 && (int)g_stepCalculationMode==3) { item=9; row=7; return true; }
                               item=10; row=6; return true;
      case PAL_COUNTDOWN:      item=2;  row=1; return true;
      case PAL_ZONE_EDGE_TOP:    item=1; row=14; return true;   // P-UI-131h
      case PAL_ZONE_EDGE_BOTTOM: item=1; row=15; return true;
      case PAL_ATR_TR:
      case PAL_ATR_EX:
      case PAL_ATR_HUNTER:
      case PAL_ATR_TRADE:
      case PAL_ATR_SPREAD:     if(g_PnlOpen==2) { item=2; row=14+(kind-PAL_ATR_TR); return true; }
                               return false;   // card not open - nothing to refresh there
   }
   return false;
}

// ══════════════════════════════════════════════════════════════════════════
// P-UI-131h — THE COLOUR GRID PREVIEWS UNDER THE POINTER, AT ZERO READ COST.
//
// «موس که روی رنگها رفت اعمال بشه سریع ... که کاربر سریع تغییرات ببینه و فکر نکنه که
// درست کار نمیکنه»: the grid answered only on a PRESS, so sweeping it showed nothing
// until the click. It is P-DRAW-27's one-event preview on the cards' palette: hit-test
// the ALREADY-PAINTED cells, apply there, write NOTHING while the pointer stays on the
// same cell, and put back the colour that was there when it leaves — so a sweep is a
// preview and a CLICK is the commitment.
//
// The cell geometry is RECORDED BY THE PAINT (P-UI-79: the pixels that were painted
// answer where they are), so a moving pointer costs ZERO chart reads — the hit-test is
// integer arithmetic over at most two regions.
// ══════════════════════════════════════════════════════════════════════════
#define PAL_HOVER_REGIONS 2
struct SPalHoverRegion { int x, y, cols, rows, size, pitch, tab, src; };
static SPalHoverRegion s_palRegion[PAL_HOVER_REGIONS];
static int   s_palRegionN   = 0;
static int   s_palHoverCell = -1;      // -1 = nothing is being previewed
static color s_palHoverWas  = clrNONE; // the colour the preview must put back
static int   s_palHoverKind = -1;

//--- called by the PAINT, once per painted block of cells. `src`: 0 = the colour grid,
//--- 1 = the recents strip. `tab` = the palette tab the grid belongs to (a stale tab's
//--- recorded geometry must never answer for the open one).
void PalHoverRegionAdd(const int x,const int y,const int cols,const int rows,
                       const int size,const int pitch,const int tab,const int src)
{
   if(s_palRegionN >= PAL_HOVER_REGIONS) return;
   s_palRegion[s_palRegionN].x=x;       s_palRegion[s_palRegionN].y=y;
   s_palRegion[s_palRegionN].cols=cols; s_palRegion[s_palRegionN].rows=rows;
   s_palRegion[s_palRegionN].size=size; s_palRegion[s_palRegionN].pitch=pitch;
   s_palRegion[s_palRegionN].tab=tab;   s_palRegion[s_palRegionN].src=src;
   s_palRegionN++;
}

//--- the cell under the pointer → the region index, or -1 when the pointer is in a gap,
//--- off the grid, or over a tab that did not paint this geometry.
int PalHoverCellAt(const int mx,const int my,int &col,int &rowv)
{
   for(int i=0;i<s_palRegionN;i++)
   {
      if(s_palRegion[i].tab != g_PalTab) continue;
      int dx=mx-s_palRegion[i].x, dy=my-s_palRegion[i].y;
      if(dx < 0 || dy < 0) continue;
      int c=dx/s_palRegion[i].pitch, r=dy/s_palRegion[i].pitch;
      if(c >= s_palRegion[i].cols || r >= s_palRegion[i].rows) continue;
      if(dx-c*s_palRegion[i].pitch >= s_palRegion[i].size) continue;   // the seam between cells
      if(dy-r*s_palRegion[i].pitch >= s_palRegion[i].size) continue;
      col=c; rowv=r; return i;
   }
   return -1;
}

//--- the colour the PAINT put in that cell, by the same two mappings it used.
color PalHoverColorAt(const int region,const int c,const int r)
{
   if(s_palRegion[region].src == 1)                   // recents: the list is the paint
   {
      int i=r*s_palRegion[region].cols+c;
      return (i < g_PalRecentCount) ? g_PalRecent[i] : clrNONE;
   }
   // P-DRAW-50: row from y, column from x — the paint's own mapping, on the
   // PAGE the paint showed (the ids and the regions are both page-local).
   return PalPickColor(BioPickPageRow0()+r, c);
}

//--- a CLICK is the commitment: the previewed value stays and nothing is put back.
void PalHoverCommit() { s_palHoverCell=-1; s_palHoverKind=-1; }

void PalMoveDisarm()
{
   if(!s_palMoveArmed) return;
   s_palMoveArmed=false; s_palMoveMoved=false;
   DragReleaseIf(DRAG_PANEL_MOVE);
   CircUnlockChart();
}
void PalMovePark()
{
   s_palManual=true; s_palMX=g_PalX; s_palMY=g_PalY; s_palMAnchor=g_PalAnchorItem;
}
// Press in the title band (close seat keeps its click) arms the carry.
bool PalTitleGrab(const int mx,const int my)
{
   if(!g_PalOpen || s_palMoveArmed) return false;
   //--- one move at a time: a live card move owns DRAG_PANEL_MOVE already, and a
   //--- knob/mixer/menu gesture owns the pointer — arming a second carry would
   //--- starve the first and jump it on finish (stale anchor).
   if(g_PnlMoveItem>=0 || !DragCanGrab(DRAG_PANEL_MOVE)) return false;
   int w=PalW();
   if(mx < g_PalX || mx > g_PalX+w || my < g_PalY || my > g_PalY+PAL_HEAD) return false;
   if(mx >= g_PalX+w-PAL_PAD-20 && my >= g_PalY+3 && my <= g_PalY+21) return false;
   s_palMoveArmed=true;
   s_palMoveGX=mx; s_palMoveGY=my; s_palMoveLX=mx; s_palMoveLY=my;
   s_palMoveMoved=false; s_palMoveTick=0;
   DragClaim(DRAG_PANEL_MOVE);
   CircLockChart();
   return true;
}
void PalMoveStep(const int mx,const int my)
{
   if(!s_palMoveArmed || !g_PalOpen) return;
   uint now=GetTickCount();
   if(s_palMoveTick != 0 && now-s_palMoveTick < (uint)s_PnlMoveFrameMs) return;
   if(mx == s_palMoveLX && my == s_palMoveLY) return;
   if(!s_palMoveMoved &&
      MathAbs(mx-s_palMoveGX) <= PnlDragThreshPx() &&
      MathAbs(my-s_palMoveGY) <= PnlDragThreshPx())
   {
      s_palMoveLX=mx; s_palMoveLY=my;
      return;
   }
   s_palMoveTick=now;
   int cw=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0); if(cw<=0) cw=1920;
   int ch=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0); if(ch<=0) ch=1080;
   int nx=g_PalX+mx-s_palMoveLX, ny=g_PalY+my-s_palMoveLY;
   int w=PalW(), h=PalH();
   if(nx<4) nx=4; if(ny<4) ny=4;
   if(nx>cw-w-4) nx=MathMax(4,cw-w-4);
   if(ny>ch-h-4) ny=MathMax(4,ch-h-4);
   s_palMoveLX=mx; s_palMoveLY=my;
   if(nx==g_PalX && ny==g_PalY) return;
   g_PalX=nx; g_PalY=ny;
   if(!s_palMoveMoved) PalMovePark();
   s_palMoveMoved=true;
   PalDraw();
}
void PalMoveFinish()
{
   if(!s_palMoveArmed) return;
   bool mv=s_palMoveMoved;
   if(mv) PalMovePark();
   PalMoveDisarm();
   if(mv) UISuppressNextClick();
}

void PalComputePos()
{
   int cw=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
   int ch=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   if(cw<=0) cw=1920;
   if(ch<=0) ch=1080;
   int w=PalW(), h=PalH();
   // Anchor to the OPEN panel (the strip opens the fill palette with anchor
   // item 12 while item 13 is open — stale g_PnlX[12] would park it top-left).
   int ai = (g_PnlOpen >= 0 ? g_PnlOpen : g_PalAnchorItem);
   if(g_PalKind == PAL_DRAW_BORDER || g_PalKind == PAL_DRAW_FILL)
      ai = -1;   // P-PAL-19: a drawing has no card row; the strip's spot is the anchor
   if(s_palManual && s_palMAnchor == ai)   // hand spot wins while the anchor matches
    {
       int mx2=MathMax(4,MathMin(s_palMX,cw-PalW()-4));
       int my2=MathMax(4,MathMin(s_palMY,ch-PalH()-4));
       g_PalX=mx2; g_PalY=my2;
       return;
    }
   //--- P-PAL-19b (2026-10-02) — A DRAWING HAS NO CARD ROW, AND INDEXING ONE IS A
   //--- CRASH, NOT A BAD POSITION. `g_PnlX`/`g_PnlY` are `static int[…]` arrays, so
   //--- `g_PnlX[-1]` is an out-of-range read: MEASURED, the first bridge build died
   //--- on the tap («پالت باز نمیشه کرش میکنه») with the indicator gone from the
   //--- chart. The anchor for a drawing is therefore NEVER an index — it is the
   //--- STRIP's own rect, read through the accessors the bridge added, and the
   //--- hand's spot still wins when it matches. ONE owner for the placement: the
   //--- caller sets the KIND, this decides where.
   if(ai < 0)
   {
      int sw = DrawStripPlateW();
      int dx = (sw > 0) ? DrawStripPlateX() + sw + 8 : MathMax(4, cw - w - 24);
      if(dx + w > cw - 4) dx = MathMax(4, (sw > 0 ? DrawStripPlateX() : cw - w - 24) - w - 8);
      int dy = (sw > 0) ? DrawStripPlateY() : MathMax(4, (ch - h) / 2);
      int maxDy = ch - h - 16;
      if(dy > maxDy) dy = MathMax(4, maxDy);
      g_PalX = MathMax(4, dx); g_PalY = dy;
      return;
   }
    s_palManual=false;
    int px=g_PnlX[ai]+PnlPanelW(ai)+8;                    // right of the panel
   if(px+w>cw-4) px=g_PnlX[ai]-w-8;                      // flip left on overflow
   px=MathMax(4,px);
   int py=g_PnlY[ai];
   int maxY=ch-h-16;
   if(py>maxY) py=MathMax(4,maxY);
   g_PalX=px; g_PalY=py;
}

//--- P-UI-137 (2026-10-02) — THE CENSUS EPOCH. One popup census per OPEN, never per
//--- repaint (MEASURED: on every pass the popup walked the chart and wrote ~55
//--- flushed lines, and PalDraw runs on every chip / tab / pager click — the popup
//--- became visibly slow). Paint order and ink are identical in every pass, so one
//--- answer per open is the whole answer. The flag lives HERE because PalA is
//--- compiled before PalB, where the census reads it.
static bool s_palDiagDone = false;
void PalDiagEpoch() { s_palDiagDone = false; }

void PalClose()
{
    UIDragBudgetEnd();   // P-UI-33: a mixer gesture cannot outlive its palette (idempotent)
    PalMoveDisarm();     // the title carry ends with its popup (spot stays parked)
    PalHoverRestore();   // P-UI-131h: a close while previewing must not leave the colour picked
   if(!g_PalOpen) return;
   SavePalRecentDurable();   // P-PERF-44: flush the throttled mixer drag tail (own transaction)
   ObjectsDeleteAll(0, g_UI.btnPrefix+"Pal_", 0, -1);
   PalDiagEpoch();   // P-UI-137: the next open is a new census
   g_PalOpen=false; g_PalMixDrag=0; g_PalHexFocus=false;
   // P-UI-98r: palette gone - republish (invalidates) and uncover now.
   PnlPublishCover();
   HTFCardCullRefresh();
   ChartRedraw();
}

//--- P-UI-69: ONE owner for the RECENT strip. It was painted inline inside
//--- PalDraw() only, so applying a colour that was not already in the list left
//--- the strip SHOWING A DIFFERENT SET than the picker had just produced - the
//--- "I picked a color and nothing in here changed" half of «رنگ ها کار نمی‌کنه».
//--- The strip is now a function of the list (colour + legibility border per
//--- cell), the list is the only thing PushPalRecent mutates, and the paint
//--- records the list it painted so a repaint can be skipped when nothing moved.
int PalRecentsSig()
{
   int s=g_PalRecentCount;
   for(int i=0;i<PAL_RECENT_MAX;i++) s=s*31+(int)g_PalRecent[i];
   return s;
}

//--- TV parity board: the face one colour CELL wears. The colour the target
//--- holds now gets the RING bake, every other the flat cell bake — one asset
//--- each, baked at BOTH cell sizes (MT4 crops a bitmap label, never scales it,
//--- so 22px and 26px are two files and not one scaled).
string PalCellFaceRes(const color sw, const color cur)
{
   string big = "::Files\\Icons\\pal_cell26.bmp";
   string bigR= "::Files\\Icons\\pal_ring26.bmp";
   string sml = "::Files\\Icons\\pal_cell22.bmp";
   string smlR= "::Files\\Icons\\pal_ring22.bmp";
   bool sel = (cur != clrNONE && sw == cur);
   if(PalCellSize() >= PAL_CELL_BIG) return sel ? bigR : big;
   return sel ? smlR : sml;
}

void PalPaintRecents(const int px,const int syTop)
{
   string p=g_UI.btnPrefix+"Pal_";
   color cur=PaletteKindColor(g_PalKind);
   int cell=PAL_REC, pitch=cell+PAL_CELLGAP;
   int nshow=MathMin(g_PalRecentCount,PAL_RSHOW);
   for(int i=0;i<PAL_RSHOW;i++)
   {
      string n=p+"r"+IntegerToString(i);
       // prune past the end (the strip can only shrink on a load)
       if(i>=nshow) { ObjectDelete(0,n); ObjectDelete(0,n+"G"); continue; }
      int sx=px+PAL_PAD+i*pitch;
      int sy=syTop;
      if(i == 0) PalHoverRegionAdd(px+PAL_PAD, sy, PAL_RSHOW, 1, cell, pitch, 0, 1);
       PnlSetButton(n, sx, sy, cell, cell, "", g_PalRecent[i],
                    PnlSwatchBorder(g_PalRecent[i],PNL_CLR_FIELD), true);
       ObjectSetInteger(0,n,OBJPROP_ZORDER,Z_PANEL_POP_CTL);
       ObjectSetString(0,n,OBJPROP_TOOLTIP, "#"+PalHexText(g_PalRecent[i])+"  ("+PalColorText(g_PalRecent[i])+")");
       string nr=n+"G";
       PnlSetBitmap(nr, sx, sy, cell, cell, PalCellFaceRes(g_PalRecent[i], cur), Z_PANEL_POP_FG);
       ObjectSetString(0,nr,OBJPROP_TOOLTIP, "#"+PalHexText(g_PalRecent[i])+"  ("+PalColorText(g_PalRecent[i])+")");
   }
   if(nshow==0)
   {
      PnlSetLabel(p+"rempty", px+PAL_PAD, syTop+4, "Pick any color — it appears here for reuse.", PNL_CLR_MUTED, 7);
      ObjectSetInteger(0,p+"rempty",OBJPROP_ZORDER,Z_PANEL_POP_BG);
   }
   else ObjectDelete(0,p+"rempty");
   s_PalRecentPainted=PalRecentsSig();
}

//--- repaint the strip when its LIST moved. Coalesced ONLY while a mixer drag
//--- is live (there the list can change on every 30 ms tick); the release path
//--- flushes the tail, so a click is never left one colour behind.
void PalRefreshRecents(const bool force)
{
   if(!g_PalOpen || g_PalTab!=0) return;
   if(!force && PalRecentsSig()==s_PalRecentPainted) return;
   uint now=GetTickCount();
   if(!force && g_PalMixDrag>0 && now-s_PalRecentAt<PAL_RECENTS_MS) return;
   s_PalRecentAt=now;
   PalPaintRecents(g_PalX, g_PalY+PalRecY());
}

//--- open the palette on an explicit kind (cset cells address their own
//--- target; the anchor item only positions the popup)
//--- P-PAL-19 (2026-10-02) — OPEN ON A DRAWING. The strip has no board of its own any
//--- more, so its colour tap lands here: the same popup every card opens, the same
//--- recents, the same mixer, the same hex field. `slot` is DRAW_SLOT_COLOR or
//--- DRAW_SLOT_FILLCLR — the strip's OWN vocabulary, read through its two accessors,
//--- so the panels never name a drawing slot directly. The anchor is the STRIP's own
//--- plate: a drawing is not a card, so `g_PnlX[]` has no row for it, and a stale
//--- index parked the popup top-left (P-UI-98r's own finding, one surface over).
void PalOpenDraw(const int stripX,const int stripY,const int stripW)
{
   //--- P-PAL-19: the placement is NOT this function's business — `PalComputePos`
   //--- owns it and reads the strip's own rect (P-PAL-19b). Passing the rect here and
   //--- re-solving it would be a second grid, which is the class this whole move
   //--- deletes; the three parameters stay because the bridge already has them, and
   //--- they are the fallback a future caller may need. One owner, one answer.
   PalOpenKind(-1, (DrawStripPalTargetSlot() == DRAW_SLOT_FILLCLR) ? PAL_DRAW_FILL
                                                                   : PAL_DRAW_BORDER);
}

void PalOpenKind(const int anchorItem,const int kind)
{
   PalClose();
   BkDdClose();   // mutually exclusive floaters — a hanging dropdown never survives under the palette
   g_PalOpen=true;
   g_PalAnchorItem=anchorItem;
   g_PalKind=kind;
   g_PalTgt=PalTgtIndexOfKind(g_PalKind);
   g_PalTab=0;
   g_PalMixDrag=0; g_PalHexFocus=false;
   PalComputePos();
   PalDraw();
   // P-UI-98r: the palette hangs next to the card - same cover rule.
   PnlPublishCover();
   HTFCardCullRefresh();
   ChartRedraw();
}

//--- open the palette on an explicit kind (cset cells address their own
//--- target; the anchor item only positions the popup)
void PalOpen(const int item, const int row)
{
   int k=PnlColorKind(item,row);
   PalOpenKind(item,(k>=0)?k:PAL_TRIGGER);
}

//--- header picker button → open with the panel's primary COLOR target
//--- (setting rows → display rows; PnlColorKind is display-keyed)
void PalOpenForItem(const int item)
{
   int srow=-1;
   if(item==0)       srow=1;   // Trigger COLOR
   else if(item==2)  srow=1;   // Countdown COLOR
   else if(item==5)  srow=5;   // TH3 COLOR
   else if(item==6)  srow=3;   // HTF Bull COLOR
   else if(item==7)  srow=5;   // Lines COLOR
   else if(item==8)  srow=1;   // Custom Price COLOR
   else if(item==10) srow=6;  // Factor COLOR
   else if(item==12) srow=(g_BkTab==0 ? 1 : (g_BkTab==1 ? 6 : 2));   // open tab's first COLOR
   else if(item==13) srow=0;  // Mini BORDER COLOR
   // P-UI-131h: card 1 had NO entry here, so its header palette button was DEAD (the
   // handler found the button, pressed it, and `PalOpenForItem` returned). The main card
   // now owns colours of its own — the edge's two halves — so the button opens on the
   // first of them.
   else if(item==1)  srow=14; // MID ZONE EDGE TOP
   if(srow<0) return;
   int drow=PnlDispRowOfSet(item,srow);
   if(drow<0) return;
   PalOpen(item,drow);
}

//--- TV parity board: THE HEX ROW (P-UI-91's field, drawn and applied once). The
//--- reference keeps the exact value beside the grid, so BOTH tabs seat it: the
//--- mixer under its tracks, the palette tab in the band above APPLY TO. An AUTO
//--- target shows an EMPTY field — FFFFFF would claim a colour nobody chose.
//--- P-DRAW-49: the field is 88 wide and its value is #RRGGBB, the order
//--- `ParseHexColor` reads — the two ends used to disagree (see `PalHexText`).
void PalDrawHexRow(const int px,const int hy)
{
   string p=g_UI.btnPrefix+"Pal_";
   color cur=PaletteKindColor(g_PalKind);
   int fx=px+PAL_PAD+30;
   PnlSetLabel(p+"hl", px+PAL_PAD, hy+6, "HEX", PNL_CLR_LABEL, 7);
   ObjectSetInteger(0,p+"hl",OBJPROP_ZORDER,Z_PANEL_POP_BG);
   string en=p+"hex";
   ObjectCreate(0,en,OBJ_EDIT,0,0,0);
   ObjectSetInteger(0,en,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,en,OBJPROP_XDISTANCE,fx);
   ObjectSetInteger(0,en,OBJPROP_YDISTANCE,hy+3);
   ObjectSetInteger(0,en,OBJPROP_XSIZE,88);
   ObjectSetInteger(0,en,OBJPROP_YSIZE,20);
   ObjectSetString(0,en,OBJPROP_TEXT,(cur==clrNONE ? "" : PalHexText(cur)));
   ObjectSetString(0,en,OBJPROP_FONT,BIO_FONT_MONO);
   ObjectSetInteger(0,en,OBJPROP_FONTSIZE,PnlPt(PNL_PT_CTL));   // P-UI-30
   ObjectSetInteger(0,en,OBJPROP_COLOR,PNL_CLR_TITLE);
   //--- P-UI-137 (2026-10-02, user: the HEX field's value is not visible): the ink is
   //--- PNL_CLR_TITLE = #F3F6FB, near-WHITE. This row was the ONE OBJ_EDIT in the
   //--- product born on a pure-white face (`C'255,255,255'`), so the value was
   //--- near-white ink on white — invisible for every target, not just a drawing.
   //--- Every other field in the product wears PNL_CLR_FIELD (#181D27) under the
   //--- same light ink (BiotakPanels_Build:288, DrawStrip_GearB:718); this one does
   //--- too now. One ink, one face, every field.
   ObjectSetInteger(0,en,OBJPROP_BGCOLOR,PNL_CLR_FIELD);
   ObjectSetInteger(0,en,OBJPROP_BORDER_COLOR,PNL_CLR_FIELD_BD);
   ObjectSetInteger(0,en,OBJPROP_ALIGN,ALIGN_CENTER);
   ObjectSetInteger(0,en,OBJPROP_ZORDER,Z_PANEL_POP_FG);
   ObjectSetInteger(0,en,OBJPROP_HIDDEN,true);
   PnlSetLabel(p+"hl2", fx+96, hy+8, "ENTER applies", PNL_CLR_MUTED, 7);
   ObjectSetInteger(0,p+"hl2",OBJPROP_ZORDER,Z_PANEL_POP_BG);
}

//--- flush a pending hex edit (called before focus is lost)
void FlushPalHex()
{
   if(!g_PalHexFocus) return;
   g_PalHexFocus=false;
   string t=ObjectGetString(0, g_UI.btnPrefix+"Pal_hex", OBJPROP_TEXT);
   color c=ParseHexColor(t);
   if(c!=clrNONE)
   {
      int flags=PaletteApplyColor(g_PalKind,c);
      PalUpdateLive();
      if(flags!=REFRESH_NONE) RefreshDisplay(flags);
   }
}

//--- the mixer's four rows, ONE geometry for paint + hit + knob: the rows are
//--- centred in the band the tabs leave above the HEX row, 30px apart. The hit
//--- test used to re-derive this as +i*26 from the tabs, so R/G/B/TR grabbed
//--- each other's channel («اشتباهی درگ میکنه»).
int PalMixTop()
{
   int contY=g_PalY+PalTabsY()+PAL_TABS;
   int bandH=PAL_HX+10+(PalHxY()-(contY+2));
   return contY+2+MathMax(0,(bandH-4*30)/2);
}
int PalMixRowY(const int i){ return PalMixTop()+i*30; }

//--- P-DRAW-49: the MIXER keeps its four channels (R · G · B · TR) and gains the
//--- popup's new room: the block is CENTRED in the band between the tabs and the
//--- HEX row instead of hanging from the tabs with a hole under it, and the HEX
//--- row is seated on the SAME band the palette tab uses (`PalHxY`) so the two
//--- tabs share the bottom three bands — the mixer is the same card with a
//--- different middle, not a different card.
void PalDrawMixer(const int contY)
{
   int px=g_PalX;
   string p=g_UI.btnPrefix+"Pal_";
   color cur=PaletteKindColor(g_PalKind);
   int cv=(int)cur;
   int comps[3];
   comps[0]=cv%256; comps[1]=(cv/256)%256; comps[2]=cv/65536;
   string cl[3]={"R","G","B"};
   color fill[3]={C'255,99,99',C'102,187,106',C'92,145,255'};
   int trackX=px+PAL_PAD+30;
   int trackW=PalW()-2*PAL_PAD-34;
    //--- the four rows, centred in the band the tabs leave above the HEX row
    const int PITCH=30;
    int top=PalMixTop();
    for(int i=0;i<3;i++)
    {
       int y=PalMixRowY(i);

      PnlSetLabel(p+"ml"+IntegerToString(i), px+PAL_PAD, y, cl[i], PNL_CLR_LABEL, PNL_PT_PAL);
      ObjectSetInteger(0,p+"ml"+IntegerToString(i),OBJPROP_ZORDER,Z_PANEL_POP_BG);
      PnlSetRect(p+"mtg"+IntegerToString(i), trackX, y+2, trackW, 8, PNL_CLR_TRACK_BD);
      ObjectSetInteger(0,p+"mtg"+IntegerToString(i),OBJPROP_ZORDER,Z_PANEL_POP_BG);
      int kx=trackX+(int)MathRound(comps[i]/255.0*(trackW-10));
      PnlSetRect(p+"mf"+IntegerToString(i), trackX, y+2, kx-trackX+10, 8, fill[i]);
      ObjectSetInteger(0,p+"mf"+IntegerToString(i),OBJPROP_ZORDER,Z_PANEL_POP_CTL);
       PnlSetButton(p+"mknb"+IntegerToString(i), kx, y, 10, 12, "", fill[i], PNL_CLR_TRACK_BD, true);
      ObjectSetInteger(0,p+"mknb"+IntegerToString(i),OBJPROP_ZORDER,Z_PANEL_POP_FG);
       PnlSetLabel(p+"mv"+IntegerToString(i), px+PalW()-PAL_PAD, y, IntegerToString(comps[i]), PNL_CLR_VALUE, PNL_PT_PAL);
       // P-UI-26: ANCHOR_RIGHT_UPPER, not ANCHOR_RIGHT (middle-right sat a
       // half line below its label — every other right-aligned panel text
       // uses RIGHT_UPPER).
       ObjectSetInteger(0,p+"mv"+IntegerToString(i),OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
      ObjectSetInteger(0,p+"mv"+IntegerToString(i),OBJPROP_ZORDER,Z_PANEL_POP_BG);
   }
   // 4th channel: TRANSPARENCY (percent; 0=solid, 100=invisible —
   // same language as the panel TRANSPARENCY sliders).
   // Targets without a transparency setting show it greyed.
   int tr = PaletteKindTransparency(g_PalKind);
   bool trOk = (tr >= 0);
    int oy = PalMixRowY(3);
   PnlSetLabel(p+"ml3", px+PAL_PAD, oy, "TR", PNL_CLR_LABEL, PNL_PT_PAL);
   ObjectSetInteger(0,p+"ml3",OBJPROP_ZORDER,Z_PANEL_POP_BG);
   ObjectSetString(0,p+"ml3",OBJPROP_TOOLTIP,"Transparency — blends the color toward the chart background");
   color trFill = trOk ? PNL_CLR_ACCENT : PNL_CLR_DISABLED;
   PnlSetRect(p+"mtg3", trackX, oy+2, trackW, 8, PNL_CLR_TRACK_BD);
   ObjectSetInteger(0,p+"mtg3",OBJPROP_ZORDER,Z_PANEL_POP_BG);
   int tkx = trackX + (int)MathRound((trOk ? ClampInt(tr,0,100) : 0) / 100.0 * (trackW-10));
   PnlSetRect(p+"mf3", trackX, oy+2, MathMax(0, tkx-trackX+10), 8, trFill);
   ObjectSetInteger(0,p+"mf3",OBJPROP_ZORDER,Z_PANEL_POP_CTL);
   PnlSetButton(p+"mknb3", tkx, oy, 10, 12, "", trFill, trOk ? PNL_CLR_ACCENT : PNL_CLR_DIS_BD, true);
   ObjectSetInteger(0,p+"mknb3",OBJPROP_ZORDER,Z_PANEL_POP_FG);
    PnlSetLabel(p+"mv3", px+PalW()-PAL_PAD, oy, trOk ? IntegerToString(tr)+"%" : "--", PNL_CLR_VALUE, PNL_PT_PAL);
    ObjectSetInteger(0,p+"mv3",OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0,p+"mv3",OBJPROP_ZORDER,Z_PANEL_POP_BG);

   // TV parity board: the HEX row, seated on the band the palette tab uses
   // (one owner, one seat — see PalDrawHexRow). It used to hang 4px under the
   // last track, which on the taller card left a hole between them.
   PalDrawHexRow(px, g_PalY+PalHxY());
}

//--- P-DRAW-50 caption deleted by user order 2026-09-27: the 8-family
//--- string overflowed the 268px card — pager + tooltips keep the names.

//--- P-DRAW-49: THE READOUT, ONE OWNER. It answers "what am I about to pick",
//--- and it takes the HOVERED cell when there is one: the hover state is already
//--- current by the time any caller gets here (a preview applies the colour, then
//--- asks for the live paint), so the band costs three compares and no new state.
//--- An AUTO target has no colour of its own and wears the AUTO face, exactly as
//--- the row and the cset cells do (P-UI-131h) — clrNONE would paint ink-black
//--- and claim a colour nobody chose.
void PalPaintReadout(const color cur)
{
   string p=g_UI.btnPrefix+"Pal_";
   color show=cur;
   if(s_palHoverCell >= 0)
   {
      int cell=s_palHoverCell;
      int reg=cell/1000, row=(cell-reg*1000)/100, col=cell%100;
      if(reg>=0 && reg<s_palRegionN)
      {
         color h=PalHoverColorAt(reg,col,row);
         if(h!=clrNONE) show=h;
      }
   }
   color vis=(show==clrNONE)?PNL_CLR_AUTO_CELL:show;
   int ry=g_PalY+PalReadY();
   PnlSetRect(p+"cur", g_PalX+PAL_PAD, ry+4, 24, 24, vis);
   ObjectSetInteger(0,p+"cur",OBJPROP_BORDER_COLOR,PnlSwatchBorder(vis,PNL_CLR_FIELD));
   ObjectSetInteger(0,p+"cur",OBJPROP_ZORDER,Z_PANEL_POP_BG);
   string hx=(show==clrNONE)?"AUTO":("#"+PalHexText(show));
   PnlSetLabel(p+"curtx", g_PalX+PAL_PAD+32, ry+8, hx, PNL_CLR_TITLE, PNL_PT_PAL);
   ObjectSetInteger(0,p+"curtx",OBJPROP_ZORDER,Z_PANEL_POP_BG);
   //--- the RGB line is RIGHT-aligned on the band's own edge, so the two texts
   //--- can never collide however long the target's name is.
   string rgt=(show==clrNONE)?"follows the card":PalColorText(show);
   PnlSetLabel(p+"curtr", g_PalX+PalW()-PAL_PAD, ry+10, rgt, PNL_CLR_MUTED, 7);
   ObjectSetInteger(0,p+"curtr",OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0,p+"curtr",OBJPROP_ZORDER,Z_PANEL_POP_BG);
}

#endif // BIOTAK_PANELS_PALA_MQH
