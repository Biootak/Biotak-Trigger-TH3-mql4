// BiotakPanels_Rows.mqh - BiotakPanels split 2026-09-29: exact lines 4851-5983 of BiotakPanels.mqh, byte-identical, zero renames.
#ifndef BIOTAK_PANELS_ROWS_MQH
#define BIOTAK_PANELS_ROWS_MQH

#define PNL_TB_ICON   24      // glyph size (OBJ_BITMAP_LABEL renders native)
#define BK_TB_N       8       // strip slots (0..7)
//--- dropdown popover geometry (content box + 8px baked shadow margin;
//--- bk_dds.bmp = STYLE menu, bk_ddw.bmp = WIDTH menu — content-fitted
//--- widths so the longest label ("Dash-Dot-Dot") never truncates)
#define BK_DD_H       192
#define BK_DD_ROWS    5
#define BK_DD_PAD     10      // content inset inside the popover
#define BK_DD_ROW_H   32
#define BK_DD_WID     1       // g_BkDd: width dropdown
#define BK_DD_STY     2       // g_BkDd: style dropdown
#define BK_DD_WWID    120     // WIDTH menu content width (short "Npx" rows)
#define BK_DD_WSTY    216     // STYLE menu content width (fits "Dash-Dot-Dot")
#define BK_CLR_DD_TX   C'203,212,226'    // obsidian row text (--lbl)
#define BK_CLR_DD_TXHI C'26,18,6'       // selected-row text (--aInk on gold)
#define BK_CLR_DD_SEL  C'255,194,71'    // selected-row pill (gold accent)
//--- dropdown Z-stack: every layer sits ABOVE the strip buttons (1541) but
//--- the obsidian backdrop must stay BEHIND its own rows (P-UI-06: a backdrop
//--- Z above the labels buries the text/pill under the card)
#define BK_DD_Z_BG    Z_PANEL_DD_BG    // obsidian popover card
#define BK_DD_Z_SEL   Z_PANEL_DD_SEL   // selected-row dark pill
#define BK_DD_Z_LBL   Z_PANEL_DD_LBL   // row labels
#define BK_DD_Z_ICO   Z_PANEL_DD_ICO   // row glyphs (top)
#define BK_CHEV_SZ    16      // bk_chev.bmp glyph size (OBJ_BITMAP_LABEL native)
#define BK_WTXT_X     16      // WIDTH "Npx" text offset inside its 74px slot (centered pair)
#define BK_WTXT_W     22      // generous "Npx" width estimate (Arial Bold 8); chevron glues after
static int  g_BkDd  = 0;      // 0 none · 1 WIDTH dropdown · 2 STYLE dropdown
static int  g_BkDdX = 0, g_BkDdY = 0, g_BkDdW = 0;   // popover rect (W set at open)

int BkMiniStyleIdx()   // 0..4 = ILS index; native STYLE_* values are 1:1
{
   return ClampInt((int)g_boxBorderStyle, 0, ILS_COUNT - 1);
}
string BkMiniBtn(const string kind) { return PnlHead(13, kind); }
string BkMiniSlotName(const int idx)
{
   switch(idx)
   {
      case 0: return "TBborder";   // pencil → border color + TR
      case 1: return "TBfill";     // bucket → fill color + TR
      case 2: return "TBtext";     // T → Text tab of card 12
      case 3: return "TBstyle";    // STYLE ▾ dropdown
      case 4: return "TBwidth";    // WIDTH Npx ▾ dropdown
      case 5: return "TBlock";     // padlock (held box)
      case 6: return "TBdel";      // trash (held box)
      default: return "TBmore";    // ••• → full Base Box card 12
   }
}

// Slot rects (shared by draw + hit-test so they can never drift). Index:
// 0 pencil · 1 bucket · 2 T · 3 STYLE ▾ · 4 WIDTH ▾ · 5 LOCK · 6 DELETE · 7 MORE.
void BkMiniSlot(const int idx, int &x, int &y, int &w, int &h)
{
   int px = g_PnlX[13], py = g_PnlY[13];
   h = PNL_TB_BTN_H;
   y = py + PNL_TB_TOP;
   switch(idx)
   {
      case 0:  x = px + 8;   w = 36; break;   // pencil (border)
      case 1:  x = px + 48;  w = 36; break;   // bucket (fill)
      case 2:  x = px + 88;  w = 36; break;   // T (text)
       case 3:  x = px + 128; w = 68; break;   // STYLE dropdown (hit rect; chevron
                                             // drawn glued to glyph, P-UI-07)
       case 4:  x = px + 200; w = 74; break;   // WIDTH dropdown (hit rect; visual is
                                             // centered "Npx" + glued chevron, P-UI-08 —
                                             // TBwidth bitmap retired, delete kept as purge)
      case 5:  x = px + 278; w = 32; break;   // LOCK
      case 6:  x = px + 314; w = 32; break;   // DELETE
      default: x = px + 350; w = 24; break;   // MORE (full card)
   }
}

// Icon resource of one strip control in its CURRENT state (style/width/lock
// variants swap at runtime, exactly like the ring menu's _on/_off skins).
string BkMiniIconRes(const int idx)
{
   switch(idx)
   {
      case 0:  return "::Files\\Icons\\bk_pencil.bmp";
      case 1:  return "::Files\\Icons\\bk_bucket.bmp";
      case 2:  return "::Files\\Icons\\bk_text.bmp";
      case 3:  return "::Files\\Icons\\bk_style" + IntegerToString(BkMiniStyleIdx()) + ".bmp";
      case 4:  return "::Files\\Icons\\bk_w" + IntegerToString(ClampInt(g_boxBorderWidth,1,5)) + ".bmp";
      case 5:  return (BaseKnotLocked(g_BkMiniBox) ? "::Files\\Icons\\bk_lock_on.bmp"
                                                    : "::Files\\Icons\\bk_lock_off.bmp");
      case 6:  return "::Files\\Icons\\bk_del.bmp";
      default: return "::Files\\Icons\\bk_more.bmp";
   }
}
// Native tooltip (fallback readout) of one strip control.
string BkMiniSlotTip(const int idx)
{
   switch(idx)
   {
      case 0:  return "Border color + transparency (Style tab)";
      case 1:  return "Fill color + transparency (Style tab)";
      case 2:  return "Box text (Text tab)";
      case 3:  return "Border style: " + BkMiniDdStyleName(BkMiniStyleIdx());
      case 4:  return "Border width: " + IntegerToString(ClampInt(g_boxBorderWidth,1,5)) + "px";
      case 5:  return (BaseKnotLocked(g_BkMiniBox) ? "Unlock this box" : "Lock this box");
      case 6:  return "Delete this box";
      default: return "All Base Box settings";
   }
}

// Dropdown row label — TV's own words for the first three (the screenshots:
// "Line", "Dashed line", "Dotted line"); width rows are just "Npx".
string BkMiniDdStyleName(const int row)
{
   if(row == 1) return "Dashed line";
   if(row == 2) return "Dotted line";
   if(row == 3) return "Dash-Dot";
   if(row == 4) return "Dash-Dot-Dot";
   return "Line";
}

// Content width + skin of the open popover (STYLE is wide, WIDTH narrow).
int BkDdCurW() { return (g_BkDd == BK_DD_WID ? BK_DD_WWID : BK_DD_WSTY); }
string BkDdRes()
{
   if(g_BkDd == BK_DD_WID) return "::Files\\Icons\\bk_ddw.bmp";
   return "::Files\\Icons\\bk_dds.bmp";
}

// --- dropdown popover (width / style selector) ---
void BkDdClose()
{
   if(g_BkDd == 0) return;
   g_BkDd = 0;   string h = g_UI.btnPrefix + "Pnl13_";
   ObjectDelete(0, h + "TBdd");
   for(int r = 0; r < BK_DD_ROWS; r++)
   {
      ObjectDelete(0, h + "DD" + IntegerToString(r) + "s");
      ObjectDelete(0, h + "DD" + IntegerToString(r) + "i");
      ObjectDelete(0, h + "DD" + IntegerToString(r) + "l");
   }
   ChartRedraw();   // closes via padding/Esc return REFRESH_NONE — no ghost till next tick
}
void BkDdOpen(const int type)
{
   BkDdClose();
   PalClose();   // mutually exclusive floaters — never bury the dropdown under the palette
   g_BkDd = type;
   g_BkDdW = BkDdCurW();
   int x, y, w, h;
   BkMiniSlot((type == BK_DD_WID) ? 4 : 3, x, y, w, h);
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0); if(cw <= 0) cw = 1920;
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0); if(ch <= 0) ch = 1080;
   // P-UI-26/F6/F7: clamp against the SKIN extents (content ±8 fringe),
   // not the content box — and flip against the skin bottom (Y+H+8).
   // Skin must fit X-8..X+W+8 × Y-8..Y+H+8 inside the 4px margins.
   g_BkDdX = MathMax(12, MathMin(cw - g_BkDdW - 12, x + w / 2 - g_BkDdW / 2));
   g_BkDdY = y + h + 8;
   if(g_BkDdY + BK_DD_H + 8 > ch - 8) g_BkDdY = y - BK_DD_H - 8;   // flip above
   if(g_BkDdY < 12) g_BkDdY = 12;
   string hh = g_UI.btnPrefix + "Pnl13_";
   PnlSetBitmap(hh + "TBdd", g_BkDdX - 8, g_BkDdY - 8, g_BkDdW + 16, BK_DD_H + 16,
                BkDdRes(), BK_DD_Z_BG);
   for(int r = 0; r < BK_DD_ROWS; r++)
   {
      int ry = g_BkDdY + BK_DD_PAD + r * BK_DD_ROW_H;
      bool sel = false;
      string label = "", icon = "";
      if(type == BK_DD_WID)
      {
         sel = (r + 1 == g_boxBorderWidth);
         label = IntegerToString(r + 1) + "px";
         icon = "::Files\\Icons\\bk_w" + IntegerToString(r + 1) + ".bmp";
      }
      else
      {
         sel = (r == BkMiniStyleIdx());
         label = BkMiniDdStyleName(r);
         icon = "::Files\\Icons\\bk_style" + IntegerToString(r) + ".bmp";
      }
      string sN = hh + "DD" + IntegerToString(r) + "s";
      string iN = hh + "DD" + IntegerToString(r) + "i";
      string lN = hh + "DD" + IntegerToString(r) + "l";
      if(sel)   // selected row — dark pill, TV-style (above the backdrop)
      {
         PnlSetRect(sN, g_BkDdX + 6, ry + 2, g_BkDdW - 12, BK_DD_ROW_H - 6, BK_CLR_DD_SEL);
         ObjectSetInteger(0, sN, OBJPROP_ZORDER, BK_DD_Z_SEL);
      }
      // P-UI-132: the icon seat follows the art. bk_w*/bk_style* are 24px bakes
      // now (tools/icon-sheet.py: they were the only 16px art in a row whose
      // every neighbour is 24, i.e. 16px of air against 8). Seat 24 keeps the
      // centred glyph where it was — old centre x = 18+8 = 26, new 14+12 = 26 —
      // and inside the 32px row the seat's own centre is ry+16 (was ry+15).
      PnlSetBitmap(iN, g_BkDdX + 14, ry + 4, PNL_TB_ICON, PNL_TB_ICON, icon, BK_DD_Z_ICO);
      PnlSetLabel(lN, g_BkDdX + 46, ry + 10, label,
                  sel ? BK_CLR_DD_TXHI : BK_CLR_DD_TX, 8);
      ObjectSetInteger(0, lN, OBJPROP_ZORDER, BK_DD_Z_LBL);
   }
   ChartRedraw();
}
// Returns: -1 = press NOT inside the dropdown; otherwise the action's
// refresh flags (REFRESH_NONE = consumed, just closed). TV-like: choosing
// a row applies it live; pressing the padding closes the menu.
int BkDdHit(const int mx, const int my)
{
   if(g_BkDd == 0) return -1;
   if(mx < g_BkDdX - 8 || mx > g_BkDdX + g_BkDdW + 8 || my < g_BkDdY - 8 || my > g_BkDdY + BK_DD_H + 8)
      return -1;   // outside the full skin rect (incl. the 8px fringe) — not ours at all
   // Inside the skin but off the rows = padding: close AND consume (falls into
   // the row-miss path below — never through to the strip slots underneath).
   int row = (my - (g_BkDdY + BK_DD_PAD)) / BK_DD_ROW_H;
   if(row >= 0 && row < BK_DD_ROWS)
   {
      if(g_BkDd == BK_DD_WID)      { g_boxBorderWidth = row + 1; BaseKnotRestyleAll(); }
      else                         { g_boxBorderStyle = NativeStyleFromIdx(row); BaseKnotRestyleAll(); }
      BkMiniRefresh();
      BkDdClose();
      return REFRESH_BUFFERS;
   }
   BkDdClose();
   return REFRESH_NONE;
}

// Repaint the toolbar from the live mirrors + the held box's lock state.
// Called after every strip action AND from PnlUpdateRow(13,row) (palette
// color / transparency picks land here) — the strip never needs row-level
// updates, one whole-toolbar repaint is cheaper and always consistent.
void BkMiniRefresh()
{
   if(g_PnlOpen != 13) return;
   // state-swapping icons (style/width/lock variants) + tooltips
   for(int i = 0; i < BK_TB_N; i++)
   {
      string nm = BkMiniBtn(BkMiniSlotName(i));
      if(ObjectFind(0, nm) >= 0)
      {
         string res = BkMiniIconRes(i);
         ObjectSetString(0, nm, OBJPROP_BMPFILE, 0, res);
         ObjectSetString(0, nm, OBJPROP_BMPFILE, 1, res);
      if(i != 4)   // WIDTH tooltips live on TBwlabel + TBchev2 (set below)
         ObjectSetString(0, nm, OBJPROP_TOOLTIP, BkMiniSlotTip(i));
      }
   }
   // width button label "1px".."5px"
   string wl = BkMiniBtn("TBwlabel");
   if(ObjectFind(0, wl) >= 0)
      ObjectSetString(0, wl, OBJPROP_TEXT,
                      IntegerToString(ClampInt(g_boxBorderWidth,1,5)) + "px");
   // WIDTH tooltips live here (not on the slot bitmap) — refresh with the value
   string wt = BkMiniSlotTip(4);
   if(ObjectFind(0, wl) >= 0) ObjectSetString(0, wl, OBJPROP_TOOLTIP, wt);
   string wc = BkMiniBtn("TBchev2");
   if(ObjectFind(0, wc) >= 0) ObjectSetString(0, wc, OBJPROP_TOOLTIP, wt);
   // TV current-color underlines: border / fill / text live colors
   string b0 = BkMiniBtn("TBbar0");
   if(ObjectFind(0, b0) >= 0) ObjectSetInteger(0, b0, OBJPROP_BGCOLOR, g_boxBorderColor);
   string b1 = BkMiniBtn("TBbar1");
   if(ObjectFind(0, b1) >= 0) ObjectSetInteger(0, b1, OBJPROP_BGCOLOR, g_boxFillColor);
   string b2 = BkMiniBtn("TBbar2");
   if(ObjectFind(0, b2) >= 0) ObjectSetInteger(0, b2, OBJPROP_BGCOLOR, g_bkTextColor);
}

// Point inside the strip band, its dropdown popover, or the hanging palette
// (outside-click dismissal guard — TV-like: anything else dismisses).
bool BkMiniStripPointInside(const int mx, const int my)
{
   if(g_PnlOpen != 13) return false;
   if(mx >= g_PnlX[13] - 4 && mx <= g_PnlX[13] + PNL_TB_W + 4 &&
      my >= g_PnlY[13] - 4 && my <= g_PnlY[13] + PNL_TB_H + 4) return true;
   if(g_BkDd != 0 && mx >= g_BkDdX && mx <= g_BkDdX + g_BkDdW &&
      my >= g_BkDdY && my <= g_BkDdY + BK_DD_H) return true;
   if(g_PalOpen && mx >= g_PalX && mx <= g_PalX + PalW() &&
      my >= g_PalY && my <= g_PalY + PalH()) return true;
   return false;
}

// Draw the strip. Called from PnlCreate(13) via PnlOpen(13) — the anchor
// was already set by BkHoldFire (above the held box's top-right corner);
// we only clamp it on-screen. PnlDestroy removes the TB* objects by name.
void BkMiniStripCreate()
{
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0); if(cw <= 0) cw = 1920;
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0); if(ch <= 0) ch = 1080;
   g_PnlX[13] = MathMax(4, MathMin(cw - PNL_TB_W - 4, g_PnlX[13]));
   g_PnlY[13] = MathMax(4, MathMin(ch - PNL_TB_H - PNL_BOTTOM_SAFE, g_PnlY[13]));
    BkDdClose();   // fresh strip — purge an open STYLE/WIDTH popover (guards g_BkDd==0, never orphan TBdd/DD*)
   int px = g_PnlX[13], py = g_PnlY[13];
   // Obsidian strip backdrop — dark-glass card (baked shadow margin)
   PnlSetBitmap(PnlHead(13, "card"), px - PNL_MARGIN, py - PNL_MARGIN,
                PNL_TB_W + 2 * PNL_MARGIN, PNL_TB_H + 2 * PNL_MARGIN,
                "::Files\\Icons\\bk_strip.bmp", Z_STRIP);
   for(int i = 0; i < BK_TB_N; i++)
   {
      int sx, sy, sw, sh;
      BkMiniSlot(i, sx, sy, sw, sh);
      string nm = BkMiniBtn(BkMiniSlotName(i));
       if(i == 3)   // STYLE selector: sample glyph + chevron glued to it
       {              // (bitmap chevron — a text "▼" renders as "?" in MT4;
                      //  P-UI-07: a right-aligned chevron floats 21px off its glyph
                      //  and reads as a separate item — it must sit 4px right of
                      //  the glyph so the pair reads as ONE control)
          int ix = sx + 6;
          int iy = sy + (sh - PNL_TB_ICON) / 2 - 2;
          PnlSetBitmap(nm, ix, iy, PNL_TB_ICON, PNL_TB_ICON, BkMiniIconRes(i), Z_STRIP_ICON);
          PnlSetBitmap(BkMiniBtn("TBchev1"), ix + PNL_TB_ICON + 4,
                       sy + (sh - BK_CHEV_SZ) / 2,
                       BK_CHEV_SZ, BK_CHEV_SZ,
                       "::Files\\Icons\\bk_chev.bmp", Z_STRIP_OVER);
       }
       else if(i == 4)   // WIDTH selector: "Npx" text + chevron glued to it (P-UI-08:
       {                 // the sample glyph read like a stray "H" next to the text,
                         // so three bits looked like three items — the closed control
                         // is text-only now; samples live in the dropdown rows)
          PnlSetBitmap(BkMiniBtn("TBchev2"), sx + BK_WTXT_X + BK_WTXT_W + 4,
                       sy + (sh - BK_CHEV_SZ) / 2,
                       BK_CHEV_SZ, BK_CHEV_SZ,
                       "::Files\\Icons\\bk_chev.bmp", Z_STRIP_OVER);
       }
      else
      {
         int ix = sx + (sw - PNL_TB_ICON) / 2;
         int iy = sy + (sh - PNL_TB_ICON) / 2 - 2;
         PnlSetBitmap(nm, ix, iy, PNL_TB_ICON, PNL_TB_ICON, BkMiniIconRes(i), Z_STRIP_ICON);
      }
      ObjectSetString(0, nm, OBJPROP_TOOLTIP, BkMiniSlotTip(i));
      if(i <= 2)   // TV current-color underline under pencil/bucket/T
      {
         int bx = sx + (sw - PNL_TB_ICON) / 2;
         int by = sy + (sh + PNL_TB_ICON) / 2 + 1;
         color bc = (i == 0 ? g_boxBorderColor : (i == 1 ? g_boxFillColor : g_bkTextColor));
         PnlSetRect(BkMiniBtn("TBbar" + IntegerToString(i)), bx, by, PNL_TB_ICON, 3, bc);
      }
   }
   // WIDTH "Npx" text — centered pair with its chevron (P-UI-08, text-only control)
   int wx, wy, ww, wh;
   BkMiniSlot(4, wx, wy, ww, wh);
   PnlSetLabel(BkMiniBtn("TBwlabel"), wx + BK_WTXT_X, wy + 13, "1px", BK_CLR_DD_TX, 8);
   ObjectSetString(0, BkMiniBtn("TBwlabel"), OBJPROP_FONT, BioChromeFont());
   ObjectSetString(0, BkMiniBtn("TBwlabel"), OBJPROP_TOOLTIP, BkMiniSlotTip(4));
   ObjectSetString(0, BkMiniBtn("TBchev2"), OBJPROP_TOOLTIP, BkMiniSlotTip(4));
   BkMiniRefresh();
}

//+------------------------------------------------------------------+
//| Value formatting                                                  |
//+------------------------------------------------------------------+
string PnlFormat(const int item,const int row,const double v)
{
   string unit="";
   int kind=0; string label=""; string opts=""; int minV=0,maxV=0; double step=1;
   PnlRowDef(item,row,kind,label,minV,maxV,step,unit,opts);
   // P-UI-131h/j/k: -1 is the AUTO end of every OPACITY slider that has one — the two
   // EDGE OPACITY rows (follow the shared BORDER TRANSPARENCY) and the Trigger card's
   // LABEL OPACITY (follow the Lines TR). Asked by `minV`, NEVER by an item/row list:
   // this function's `row` is a DISPLAY row and 16/17/4 are ADDRESSES, which is exactly
   // why the first cut of this guard never fired and the two chips kept reading "-1%".
   // A slider parked at its own left end would otherwise read as a deliberate 0% —
   // the one thing it is not.
   if(v < 0 && minV < 0) return "AUTO";
   if(PnlIsStyleRow(item,row)) return StyleName((int)MathRound(v));
   if(unit=="%") return IntegerToString((int)MathRound(v))+"%";
   if(unit=="x") return DoubleToStr(v,1);
   // P-UI-26: unit-suffixed chips (COUNT SIZE 12pt, COUNT GAP 6px, MAGNET
   // SENS 50p) — the chip is 46px, longest live value "100%"
   // is 4 chars, so suffixed values always fit; bare numbers hid the unit.
   if(unit=="pt" || unit=="px" || unit=="p" || unit=="R")
      return IntegerToString((int)MathRound(v))+unit;
   return IntegerToString((int)MathRound(v));
}

int PnlSplit(const string opts,string &arr[],const int maxLen=8)
{
   string tmp[];
   int cnt=StringSplit(opts,'|',tmp);
   int n=MathMin(cnt,maxLen);
   ArrayResize(arr,n);
   for(int i=0;i<n;i++) arr[i]=tmp[i];
   return n;
}

// ══════════════════════════════════════════════════════════════════════════
// P-UI-91 (2026-09-14) — WHERE THE CANDLES ARE, AND WHY THE CARD MUST CARE.
//
// «حالا که جابجایی دستی حذف شده، جای باز شدن کارت را هوشمند کن تا با منوی رینگ و
// کندل‌ها اورلپ نکند» — asked while the card-move gesture was retired (PANELDRAG-OFF,
// P-UI-90; reversed by P-UI-127), and it stands on its own: the OPENING spot has
// to be right the FIRST time. Placement already avoided the
// ring/orb rect (`PnlComputeMenuBounds`); the price action — the far bigger
// obstacle on a live chart — was never consulted at all.
//
// THE BAND IS MEASURED, NEVER ASSUMED. The candles of the VISIBLE bars occupy
// exactly the Y range of the window's lowest low .. highest high (a candle
// pixel cannot exist outside it: wicks are included by construction), and one
// price maps to one Y through the terminal's own `ChartTimePriceToXY` — the
// same function the box tool and the TV strip already talk pixels with. No
// "the candles live in the middle third" constant, because that is the exact
// class of guess this project keeps paying for (P-UI-69, P-UI-71c, P-UI-79).
//
// COST, stated once so nobody re-derives it: ONE pass over the visible bars per
// card OPEN. `PnlComputePosition` runs from `PnlCreate` only — never per tick,
// never per mouse event — and the gate asserts the band has exactly ONE caller.
// ══════════════════════════════════════════════════════════════════════════
//--- The vertical band the VISIBLE candles occupy, in pixels (full width by
//--- construction: every visible bar has a candle). Returns false when there is
//--- nothing to measure (no history yet), and the caller then places the card
//--- exactly as it did before this rule — a placement that cannot measure the
//--- chart must not invent a band.
bool PnlCandleBandPx(int &top,int &bot)
{
   top = 0; bot = 0;
   int first = WindowFirstVisibleBar();
   if(first < 0) return false;                  // no history yet
   int bars = first + 1;
   int vis  = WindowBarsPerChart();
   if(vis > 0 && bars > vis) bars = vis;        // the WINDOW, never all history
   if(bars < 1) return false;
   double hi = 0.0, lo = 0.0;
   bool seen = false;
   for(int i = 0; i < bars; i++)
   {
      // `_Symbol` explicit: `iHigh(0, …)` handed the COMPILER a number where the
      // signature wants a symbol string (warning 181) - the symbol is ours, the
      // period is the chart's own.
      double h = iHigh(_Symbol, 0, i);
      double l = iLow(_Symbol, 0, i);
      if(h <= 0.0 || l <= 0.0) continue;        // an empty slot is not a price
      if(!seen || h > hi) hi = h;
      if(!seen || l < lo) lo = l;
      seen = true;
   }
   if(!seen) return false;
   // One bar we KNOW is on screen supplies the X (the mapping is defined there);
   // only its Y is used, and both extremes come through the same call so the
   // band can never be half-mapped.
   datetime tmid = iTime(_Symbol, 0, bars / 2);
   if(tmid <= 0) return false;
   int xa = 0, ya = 0, xb = 0, yb = 0;
   if(!ChartTimePriceToXY(0, 0, tmid, hi, xa, ya)) return false;
   if(!ChartTimePriceToXY(0, 0, tmid, lo, xb, yb)) return false;
   int y1 = (int)MathMin(ya, yb);
   int y2 = (int)MathMax(ya, yb);
   if(y2 <= y1) y2 = y1 + 1;                    // a flat window still owns a band
   top = y1 - PNL_CANDLE_PAD;
   bot = y2 + PNL_CANDLE_PAD;
   return true;
}

//--- P-UI-91: the vertical overlap (px) of [a, a+ah) with [b, b+bh). ZERO is the
//--- answer placement actually wants, so the function returns the SCORE itself
//--- instead of a boolean: the caller minimises a measured number, which is what
//--- makes "no clean spot exists" (a card taller than the free space) degrade
//--- into "the smallest overlap" instead of into a coin flip.
int PnlIntervalOverlap(const int a,const int ah,const int b,const int bh)
{
   int lo = (int)MathMax(a, b);
   int hi = (int)MathMin(a + ah, b + bh);
   return (hi > lo ? hi - lo : 0);
}

//--- P-DRAW-31 (2026-09-24): do two rects share a pixel? The MENU test above is
//--- written out longhand because its bounds are asymmetric (PNL_PAD_X on each
//--- side of the ring box); a published SURFACE (the draw-strip's plate, the
//--- palette) is a plain rect, and two panels on one pixel is the user's own
//--- complaint («جایی که روی هم نیافتن»), so it gets the honest test.
bool PnlRectHits(const int ax,const int ay,const int aw,const int ah,
                 const int bx,const int by,const int bw,const int bh,const int pad)
{
   if(aw <= 0 || ah <= 0 || bw <= 0 || bh <= 0) return false;
   return !(ax + aw <= bx - pad || ax >= bx + bw + pad ||
            ay + ah <= by - pad || ay >= by + bh + pad);
}

//+------------------------------------------------------------------+
//| Compute safe zone: the rectangle that all ring items + orb occupy |
//+------------------------------------------------------------------+
void PnlComputeMenuBounds(int &bx, int &by, int &bw, int &bh)
{
   int mx = 999999, my = 999999;
   int Mx = -999999, My = -999999;

   mx = MathMin(mx, g_UI.menuX - CIRC_ORB_SIZE/2);
   my = MathMin(my, g_UI.menuY - CIRC_ORB_SIZE/2);
   Mx = MathMax(Mx, g_UI.menuX + CIRC_ORB_SIZE/2);
   My = MathMax(My, g_UI.menuY + CIRC_ORB_SIZE/2);

   if(g_UI.menuVisible)
   {
      for(int i = 0; i < CIRC_ITEM_COUNT; i++)
      {
         int ix, iy;
         CircLayout(i, ix, iy);
         mx = MathMin(mx, ix - CIRC_BTN_SIZE/2);
         my = MathMin(my, iy - CIRC_BTN_SIZE/2);
         Mx = MathMax(Mx, ix + CIRC_BTN_SIZE/2);
         My = MathMax(My, iy + CIRC_BTN_SIZE/2);
      }
   }
   bx = mx; by = my;
   bw = Mx - mx;
   bh = My - my;
}

//+------------------------------------------------------------------+
//| Find the best position for the panel that avoids the menu        |
//+------------------------------------------------------------------+
// (PnlComputePosition moved below the WIDE block — it sizes with PnlPanelW.)

//+------------------------------------------------------------------+
//| WIDE CARDS (2026-09-11, user order) — tall cards go two-column   |
//| instead of running 700px+ down the chart. A wide card is 624px:  |
//| two full 312 slots side by side (16+280+16 | 16+280+16) with    |
//| byte-identical row geometry to a 312 card: the row body only     |
//| ever sees its own column origin, so every kind paints unchanged,|
//| only shifted +312) sharing one header/footer. SEC bands + TAB   |
//| rows span full width and restart the pairing. Cards with <=10    |
//| display rows stay narrow — zero behavior change for them. Pairing|
//| /line/base-X come from ONE simulation here: paint + hit + update |
//| all derive from it, so they can never disagree.                  |
//+------------------------------------------------------------------+
#define PNL_WIDE_WEL     624      // two full 312 slots side by side
                                 // (16+280+16 | 16+280+16): right-aligned
                                 // control glows (6px pads) stay inside the
                                 // card exactly like on a narrow card
#define PNL_COL_DX       312      // right-column x shift (= one narrow card)
#define PNL_WIDE_MIN_ROWS 10      // display rows > this → wide
// ICON-DIET 2026-09-27: PNL_WIDE_ROWS_MAX is retired. It named the pnl_cardW{1..12}[f]
// range, which produced nothing after P-UI-71 composed the wide body from
// top/mid/bot per pair-line — a 14-line card (the GENERAL card, P-UI-131) has
// always needed no skin of its own. Its 24 files were 25.4 MB.

// moved up: the wide simulation needs it, MQL4 needs define-before-use
bool IsTabRow(const int item,const int row)
{
   return ((item==12 || item==9) && row==0);
}
bool PnlIsWide(const int item)
{
   if(item < 0 || item >= PNL_COUNT || item == 13) return false;
   return (PnlRowsCount(item) > PNL_WIDE_MIN_ROWS);
}
bool PnlRowFull(const int item,const int row)   // spans both columns
{
   if(!PnlIsWide(item)) return false;
   if(IsTabRow(item,row)) return true;
   int kind; string label,unit,opts; int minV,maxV; double step;
   PnlRowDef(item,row,kind,label,minV,maxV,step,unit,opts);
   return (kind == PNL_K_SEC);
}
// column of a display row: 0 left · 1 right. Full-width rows are ALWAYS
// col 0 — they never inherit the toggle (P-UI-25: ORDER/SUB-CARDS bands
// inherited col 1 and painted 296px past the card edge).
int PnlRowCol(const int item,const int row)
{
   if(!PnlIsWide(item)) return 0;
   if(PnlRowFull(item,row)) return 0;
   int col = 0;
   int n = PnlRowsCount(item);
   for(int r=0; r<row && r<n; r++)
   {
      if(PnlRowFull(item,r)) col = 0;
      else col = 1 - col;
   }
   return col;
}
// pair-line of a display row (the Y index). A full-width row owns its line:
// following a half-filled pair it SKIPS to a fresh line (P-UI-25), so a
// band can never share a line with a control.
int PnlRowLine(const int item,const int row)
{
   if(!PnlIsWide(item)) return row;
   int line = 0, col = 0;
   int n = PnlRowsCount(item);
   for(int r=0; r<=row && r<n; r++)
   {
      bool full = PnlRowFull(item,r);
      int slot = line + ((full && col == 1) ? 1 : 0);
      if(r == row) return slot;
      if(full) { line = slot + 1; col = 0; }
      else { if(col == 1) line++; col = 1 - col; }
   }
   return line;
}
int PnlPairRows(const int item)   // total pair-lines (height + skin select)
{
   if(!PnlIsWide(item)) return PnlRowsCount(item);
   int n = PnlRowsCount(item);
   if(n <= 0) return 0;
   return PnlRowLine(item,n-1) + 1;
}
int PnlRowBaseX(const int item,const int row)   // absolute column origin
{
   return g_PnlX[item] + (PnlRowCol(item,row) == 1 ? PNL_COL_DX : 0);
}
int PnlCardW(const int item)   // card width for header/footer/skin math
{
   return PnlIsWide(item) ? PNL_WIDE_WEL : PNL_WEL;
}

// PnlComputePosition lives here (not with the other placement helpers):
// it sizes candidates with PnlPanelW, which needs the wide simulation above.
void PnlComputePosition(const int item,const int ph,int &px,int &py)
{
   int cw = (int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
   int ch = (int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   if(cw<=0) cw=1920;
   if(ch<=0) ch=1080;
   int pw = PnlPanelW(item);

   // P-UI-91: the two rects every spot must clear — the ring/orb box, and the
   // band the VISIBLE price action occupies (measured once per open; `false`
   // when the chart is too young to measure, and then this card behaves exactly
   // as it did before the rule existed — a placement that cannot measure the
   // chart must not invent a band).
   int mbx, mby, mbw, mbh;
   PnlComputeMenuBounds(mbx, mby, mbw, mbh);
   int cdTop = 0, cdBot = 0;
   bool hasBand = PnlCandleBandPx(cdTop, cdBot);

   // P-DRAW-31 (2026-09-24): and the DRAW-STRIP's published plate is a THIRD hard
   // rect. Two surfaces on one pixel is the user's own complaint («جایی که روی هم
   // نیافتن»), and the strip is the one surface this card cannot measure — it lives
   // in the module included BEFORE this one, so it PUBLISHES (`g_UIStripR*`, the
   // same contract `g_UIPanelR*` uses). Like the menu rule it is HARD: a spot that
   // lands on the plate is never used while any survivor exists.
   bool hasStrip = (g_UIStripRX >= 0 && g_UIStripRW > 0 && g_UIStripRH > 0);
   int srX = g_UIStripRX, srY = g_UIStripRY, srW = g_UIStripRW, srH = g_UIStripRH;

   // A panel dragged to a manual spot reopens where it was left (clamped
   // on-screen) — but only while that spot still PASSES the same two rules a
   // fresh spot must pass. Before P-UI-91 a park was honoured blindly, which is
   // how a card could sit on the candles for good; and a park must never be a
   // trap even though the hand can move the card again (P-UI-127), so a dirty
   // park falls through to the SAME search a
   // fresh open uses: the card keeps its place only while the place is good.
   if(g_PnlManualPos[item])
   {
      int manX = (int)MathMax(4, MathMin(cw - pw - 8, g_PnlX[item]));
      int manY = (int)MathMax(4, MathMin(ch - ph - PNL_BOTTOM_SAFE, g_PnlY[item]));
      bool parkMenuHit = !(manX + pw <= mbx - PNL_PAD_X ||
                           manX >= mbx + mbw + PNL_PAD_X ||
                           manY + ph <= mby - PNL_PAD_X ||
                           manY >= mby + mbh + PNL_PAD_X);
      // P-DRAW-31: a park on the strip's plate is as dirty as a park on the candles.
      bool parkStripHit = (hasStrip && PnlRectHits(manX, manY, pw, ph, srX, srY, srW, srH,
                                                   PNL_PAD_X));
      int parkOv = (hasBand ? PnlIntervalOverlap(manY, ph, cdTop, cdBot) : 0);
      if(!parkMenuHit && !parkStripHit && parkOv == 0) { px = manX; py = manY; return; }
   }

   int candX[4], candY[4];
   // Initialised: every slot IS assigned by the loop below, but the compiler's
   // flow analysis cannot prove it across the second (scoring) loop and warns
   // 60 - and this project ships 0 warnings.
   bool valid[4] = {false, false, false, false};

   candX[0] = mbx + mbw + PNL_PAD_X;
   candY[0] = mby + mbh/2 - ph/2;

   candX[1] = mbx - pw - PNL_PAD_X;
   candY[1] = mby + mbh/2 - ph/2;

   candX[2] = mbx + mbw/2 - pw/2;
   candY[2] = mby - ph - PNL_PAD_X;

   candX[3] = mbx + mbw/2 - pw/2;
   candY[3] = mby + mbh + PNL_PAD_X;

   for(int c=0; c<4; c++)
   {
      int cx = candX[c];
      int cy = candY[c];
      cx = MathMax(4, MathMin(cw - pw - 8, cx));
      // PNL_BOTTOM_SAFE: CHART_HEIGHT_IN_PIXELS includes the date-scale bar —
      // without the reserve the card slid under the axis (UX bug report).
      cy = MathMax(4, MathMin(ch - ph - PNL_BOTTOM_SAFE, cy));
      candX[c] = cx;
      candY[c] = cy;

      bool hits = !(cx + pw <= mbx - PNL_PAD_X ||
                    cx >= mbx + mbw + PNL_PAD_X ||
                    cy + ph <= mby - PNL_PAD_X ||
                    cy >= mby + mbh + PNL_PAD_X);
      // P-DRAW-31: the strip's plate joins the menu rect as a HARD rule — never
      // used while a survivor exists, and the least-overlap fallback below still
      // covers the case where every spot is spoken for.
      bool stripHit = (hasStrip && PnlRectHits(cx, cy, pw, ph, srX, srY, srW, srH,
                                               PNL_PAD_X));
      valid[c] = (!hits && !stripHit);
   }

   // P-UI-91: the MENU rule stays HARD — a spot that lands on the ring/orb is
   // never used — and the CANDLE rule decides AMONG the survivors: the winner is
   // the spot with the LEAST measured overlap with the price band, and the order
   // below breaks a tie. So the card stays as close to the menu as the scores
   // allow instead of jumping across the chart, and "right/left of the menu"
   // (usually inside the band) only wins when "above/below" is no better. With
   // no clean survivor at all — a card taller than the free space — the smallest
   // overlap wins, which is the honest "least bad" and not a coin flip.
   int order[4] = {0, 1, 3, 2};
   int pick = -1, pickOv = 0;
   int anyPick = -1, anyOv = 0;
   for(int o=0; o<4; o++)
   {
      int c = order[o];
      int ov = (hasBand ? PnlIntervalOverlap(candY[c], ph, cdTop, cdBot) : 0);
      if(anyPick < 0 || ov < anyOv) { anyPick = c; anyOv = ov; }
      if(valid[c] && (pick < 0 || ov < pickOv)) { pick = c; pickOv = ov; }
   }
   if(pick < 0) pick = (anyPick >= 0 ? anyPick : 0);
   px = candX[pick];
   py = candY[pick];
}

//+------------------------------------------------------------------+
//| Slider geometry helper                                            |
//+------------------------------------------------------------------+
int PnlSliderKnobX(const int item,const int row,const double val,
                   const int minV,const int maxV)
{
   double frac=(maxV>minV) ? (val-minV)/(maxV-minV) : 0.0;
   return PnlRowBaseX(item,row)+PNL_TRACK_X + (int)MathRound(frac*(PNL_TRACK_W-PNL_KNOB_W));
}

//+------------------------------------------------------------------+
//| Generic dropdown-select helpers (kind=2 rows, 4+ options)         |
//| Rendering rule: TAB rows (9,0)/(12,0) → underline tabs; 4+ option |
//| rows → dropdown select; 2-3 options → segmented pills. Engine     |
//| (open/hit) lives after PnlOpen — MQL4 needs define-before-use.    |
//+------------------------------------------------------------------+
static int g_PnlDdItem = -1, g_PnlDdRow = -1;
static int g_PnlDdX = 0, g_PnlDdY = 0, g_PnlDdW = 0, g_PnlDdH = 0, g_PnlDdN = 0;

bool IsDdRow(const int item,const int row)
{
   int kind; string label,unit,opts; int minV,maxV; double step;
   PnlRowDef(item,row,kind,label,minV,maxV,step,unit,opts);
   if(kind!=2 || IsTabRow(item,row)) return false;
   string arr[]; int cnt=PnlSplit(opts,arr,12);
   return (cnt>=4);
}
// Closed select-button rect (shared by draw + press hit-test + update).
void PnlDdRect(const int item,const int row,int &x,int &y,int &w,int &h)
{
   int kind; string label,unit,opts; int minV,maxV; double step;
   PnlRowDef(item,row,kind,label,minV,maxV,step,unit,opts);
   string arr[]; int cnt=PnlSplit(opts,arr,12);
   int maxLen=0;
   for(int i=0;i<cnt;i++) maxLen=MathMax(maxLen,StringLen(arr[i]));
   w=MathMax(104,MathMin(190,maxLen*7+54));
   int px=PnlRowBaseX(item,row), py=g_PnlY[item];
   x=px+PNL_WEL-PNL_PAD_X-w;
   y=py+PNL_HEAD_H+PnlRowLine(item,row)*PNL_ROW_H+PNL_CTL_Y;
   h=PNL_CTL_H;
}
string PnlDdOptText(const int item,const int row)
{
   int kind; string label,unit,opts; int minV,maxV; double step;
   PnlRowDef(item,row,kind,label,minV,maxV,step,unit,opts);
   string arr[]; int cnt=PnlSplit(opts,arr,12);
   if(cnt<=0) return "";
   int idx=ClampInt((int)MathRound(PnlCurrent(item,row)),0,cnt-1);
   return arr[idx];
}
void PnlDdClose()
{
   if(g_PnlDdItem<0) return;
   for(int r=0;r<12;r++)
   {
      ObjectDelete(0,PnlHead(g_PnlDdItem,"PDDR"+IntegerToString(r)+"s"));
      ObjectDelete(0,PnlHead(g_PnlDdItem,"PDDR"+IntegerToString(r)+"l"));
   }
   ObjectDelete(0,PnlHead(g_PnlDdItem,"PDDBG"));
   ObjectDelete(0,PnlHead(g_PnlDdItem,"PDDSH"));
   g_PnlDdItem=-1; g_PnlDdRow=-1;
}

//+------------------------------------------------------------------+
//| Create row widgets — TV-modern single-line layout (R-PANELMOD)    |
//|   label left · control right on ONE line (checkbox / select /     |
//|   pills / tabs / swatches); sliders keep a compact second line    |
//|   (label+value above, full-width track below, no steppers).       |
//+------------------------------------------------------------------+
// ══════════════════════════════════════════════════════════════════════════
// R-PANELUI2 row chrome helpers. Every widget name below MUST be purged in
// PnlDestroy (P-UI-02: a leaked widget stays on screen forever).
//   CHP/GL   icon chip + glyph ink      BAND/BDOT/BCNT/BCNL/SL/SHR  section band
//   SW       switch pill (40x22)        SW0/SW1 + DL0/DL1          dual pair
//   VC       slider value chip          TIC<i>                     slider ticks
//   RAIL/ACT active-row rail + wash     KEY/KEYL                   hotkey keycap
//   QA       colour "+" cell            CS<i>/CSL<i>/CSK<i>        cset cell + ring
//   SECS<i>  band colour strip          NAVC                       nav pill glyph
// ══════════════════════════════════════════════════════════════════════════
string PnlGlyphRes(const int item,const string ico,const bool on)
{
   if(ico == "") return "";
   if(on) return PnlAccentRes(item,"gl_" + ico);
   return "::Files\\Icons\\gl_" + ico + "_m.bmp";
}

//--- the --aInk ink (DARK on the bright accent ramp) for glyphs that sit ON an
//--- accent-filled surface — preview .mark and .btn.primary both use
//--- `color: var(--aInk)`. Only INK_GLYPHS have these skins (see the generator).
string PnlGlyphInkRes(const int item,const string ico)
{
   if(ico == "") return "";
   return PnlAccentRes(item,"gl_" + ico + "_i");
}

//--- the 22px icon chip + its 13px glyph ink (preview .gl / .gl svg).
//--- Chip and ink are SEPARATE objects so one chip skin serves every glyph.
void PnlPaintChip(const int item,const int row,const int x,const int y,const bool on)
{
   string ico = PnlRowIcon(item,row);
   if(ico == "") return;
   PnlSetBitmap(PnlName(item,row,"CHP"), x-PNL_CHIP_PAD, y-PNL_CHIP_PAD,
                PNL_CHIP_CANVAS, PNL_CHIP_CANVAS,
                on ? PnlAccentRes(item,"pnl_chip") : "::Files\\Icons\\pnl_chip.bmp", Z_PANEL_CHIP);
   PnlSetBitmap(PnlName(item,row,"GL"), x+4, y+4,
                PNL_GLYPH_CANVAS, PNL_GLYPH_CANVAS, PnlGlyphRes(item,ico,on), Z_PANEL_GLYPH);
}

//--- the row label. x = already resolved (after the chip and optional keycap).
//--- `maxW` (P-UI-30) is the room the row's own control leaves; a caption
//--- wider than that is clipped with ".." exactly like the preview's
//--- `.lbl>span.t{overflow:hidden;text-overflow:ellipsis}`. 0 = unclipped.
void PnlPaintLabel(const int item,const int row,const int x,const int y,
                   const string txt,const int sz=PNL_PT_LBL,const int maxW=0)
{
   string t = (maxW > 0) ? PnlFit(txt,sz,maxW) : txt;
   PnlSetLabel(PnlName(item,row,"L"), x, y, t, PNL_CLR_LABEL, sz);
   ObjectSetString(0,PnlName(item,row,"L"),OBJPROP_FONT,BioChromeFont());
}

//--- the hotkey keycap (preview .key) — a real bitmap, never a font glyph.
//--- P-UI-32: the preview's `.key` is `display:inline-grid;place-items:center`,
//--- so the letter belongs in the MIDDLE of the 18px cap. The label used to be
//--- right-anchored at x+PNL_KEYCAP_VIS (and the header's at a hard-coded 9px
//--- guess), which put every hotkey letter ~6px right of the cap centre —
//--- measured off the proof, not eyeballed. ONE owner for the cap bitmap AND
//--- its letter, so the header can never drift from the rows again.
//--- `x`,`y` = the CAP BITMAP's top-left.
void PnlKeycapAt(const string bmp,const string lbl,const int x,const int y,
                 const string k,const color clr,const int zBmp)
{
   if(k == ""){ ObjectDelete(0,bmp); ObjectDelete(0,lbl); return; }
   PnlSetBitmap(bmp, x, y, PNL_KEYCAP_CANVAS, PNL_KEYCAP_CANVAS,
                "::Files\\Icons\\pnl_keycap.bmp", zBmp);
   // the letter is centred on the CANVAS: the 18px body is itself centred in
   // the 22px canvas (its ink spans 2..19), and the preview centres the line
   // box. Both halves are measured — `tw` via PnlTextW (P-UI-30), `em` via the
   // same point->pixel mapping PnlTextW uses internally.
   int tw = PnlTextW(k,PNL_PT_KEY);
   int em = PnlLineH(PNL_PT_KEY);
   PnlSetLabel(lbl, x+PNL_KEYCAP_CANVAS/2+tw/2, y+(PNL_KEYCAP_CANVAS-em)/2,
               k, clr, PNL_PT_KEY);
   ObjectSetString(0,lbl,OBJPROP_FONT,BioChromeFont());
   ObjectSetInteger(0,lbl,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
}

//--- row keycap — `x`,`y` = the VISIBLE cap's top-left (row arithmetic keeps
//--- using the visible box, the canvas pad is subtracted here once).
void PnlPaintKey(const int item,const int row,const int x,const int y)
{
   string k = PnlRowKey(item,row);
   if(k == "") return;
   PnlKeycapAt(PnlName(item,row,"KEY"), PnlName(item,row,"KEYL"),
               x-PNL_KEYCAP_PAD, y-PNL_KEYCAP_PAD, k, PNL_CLR_LABEL, Z_PANEL_INK);
}

//--- x of the row LABEL text: after the chip and, when present, the keycap
int PnlLabelX(const int item,const int row,const int px)
{
   int x = px + PNL_PAD_X;
   if(PnlRowIcon(item,row) != "") x += PNL_CHIP_VIS + 8;
   if(PnlRowKey(item,row) != "")  x += PNL_KEYCAP_VIS + 6;
   return x;
}

//--- active-row chrome: the 2px accent rail on the card edge + the wash.
//--- The wash is always ONE column wide (312, full-bleed like the band):
//--- narrow cards paint it at the card origin, wide cards at the column px.
void PnlPaintActive(const int item,const int row,const int px,const int ry,const bool on)
{
   if(!on) return;
   PnlSetBitmap(PnlName(item,row,"ACT"), px, ry, PNL_WEL, PNL_ROW_H,
                PnlAccentRes(item,"pnl_actbg"), Z_PANEL_ACT);
   PnlSetBitmap(PnlName(item,row,"RAIL"), px-1, ry, 4, PNL_ROW_H,
                PnlAccentRes(item,"pnl_rail"), Z_PANEL_SKIN);
}

//--- one 40x22 switch pill (preview .sw) — bitmap face, hit-tested by coords
void PnlPaintSwitch(const int item,const int row,const string nm,
                    const int x,const int y,const bool on,const bool dual)
{
   string res  = on ? (dual ? PnlAccentRes(item,"pnl_dsw_on") : PnlAccentRes(item,"pnl_sw_on"))
                    : (dual ? "::Files\\Icons\\pnl_dsw_off.bmp" : "::Files\\Icons\\pnl_sw_off.bmp");
   PnlSetBitmap(nm, x-PNL_SW_PAD, y-PNL_SW_PAD,
                (dual ? PNL_DUAL_SW_W : PNL_SW_W) + 2*PNL_SW_PAD,
                (dual ? PNL_DUAL_SW_H : PNL_SW_H) + 2*PNL_SW_PAD, res, Z_PANEL_SW);
}

//--- short cell caption for .dual rows: the family prefix goes ("STRUCTURE
//--- L1" -> "L1", like the preview's L1 · L2 + L1/L2). Anything else keeps its
//--- full label — a clipped family word ("FIRST", "LABELS") reads worse than
//--- the long form, and the left label drops instead (see below).
string PnlShortCap(const string l)
{
   if(StringFind(l, "STRUCTURE ") == 0) return StringSubstr(l, 10);
   return l;
}

//--- .dual cell geometry — ONE implementation so the renderer and the press
//--- hit-test can never drift apart (the classic P-UI ghost-target bug).
//--- Returns the cell's SWITCH left edge; `cell` counts the row's own members
//--- followed by the synthetic extra ("ALL") cell when ext is set.
int PnlDualCells(const int item,const int row)
{
   int n = PnlRowMembers(item,row);
   return n + ((PnlRowExt(item,row)=="") ? 0 : 1);
}
int PnlDualCellX(const int item,const int row,const int cell)
{
   int n = PnlRowMembers(item,row);
   string extra = PnlRowExt(item,row);
   int cells = n + ((extra=="") ? 0 : 1);
   int x = 0;
   for(int i=0;i<cells;i++)
   {
      string txt = "";
      if(i < n)
      {
         string cl,cu,co; int ck,cmn,cmx; double cst;
         PnlSetDef(item,PnlMemberRow(item,row,i),ck,cl,cmn,cmx,cst,cu,co);
         txt = PnlShortCap(cl);
      }
      else txt = extra;
      if(i == cell) return x;
      x += PNL_DUAL_SW_W + 6 + PnlTextW(txt,PNL_PT_CAP) + 14;   // P-UI-30: real advance
   }
   return x;
}

//--- THE SETTINGS a dual row's synthetic "ALL" cell really owns (P-UI-66).
//---
//--- The cell means the GROUP the row lives in - the section band's members -
//--- not the row's own members. On card 11 the third row is `L5 | ALL` and holds
//--- ONE member, so a row-local ALL was a SECOND L5 switch: it could not turn
//--- the five levels on or off together, and its face mirrored L5 alone. That is
//--- the "same button twice" shape P-UI-62 removed from the zone picture, and
//--- it is what the report "STRUCTURE L1-L5 does not work" was describing.
//---
//--- The span is only used when the band's members are CONTIGUOUS settings (the
//--- write loop walks `first+k`): a band that interleaves anything else falls
//--- back to the row's own members, so the cell can never write a setting the
//--- row does not own. Returns the member count; `first` = the first setting.
int PnlAllCellSpan(const int item,const int dispRow,int &first,int &count)
{
   first = -1; count = 0;
   int s0 = PnlSetRow(item,dispRow);
   if(s0 < 0) return 0;
   int own = PnlRowMembers(item,dispRow);
   int n   = PnlRowsCount(item);
   // the band this row belongs to: the nearest SEC slot at or above it
   int band = -1;
   for(int r=dispRow;r>=0;r--)
      if(PnlRowKind(item,r) == PNL_K_SEC) { band = r; break; }
   if(band >= 0)
   {
      int f = -1, c = 0, expect = -1;
      bool contiguous = true;
      for(int r=band+1;r<n;r++)
      {
         if(PnlRowKind(item,r) == PNL_K_SEC) break;
         int r0 = PnlSetRow(item,r);
         if(r0 < 0) continue;
         int rc = PnlRowMembers(item,r);
         if(f < 0) { f = r0; }
         else if(r0 != expect) contiguous = false;
         c += rc;
         expect = r0 + rc;
      }
      if(f >= 0 && c > own && contiguous) { first = f; count = c; return count; }
   }
   first = s0; count = own;   // a lone dual row: the cell IS its members
   return count;
}

//--- face of the synthetic "ALL" cell: lit only when EVERY member of the group
//--- is on. The renderer, the row refresher and PnlAllCellSpan share this ONE
//--- owner, so the pill can never disagree with what its press will write.
bool PnlAllCellOn(const int item,const int dispRow)
{
   int f=0, c=0;
   PnlAllCellSpan(item,dispRow,f,c);
   if(f < 0 || c <= 0) return true;
   bool on = true;
   for(int k=0;k<c;k++) on = on && (PnlCurrentSet(item,f+k) > 0.5);
   return on;
}
int PnlDualTotalW(const int item,const int row)
{
   int cells = PnlDualCells(item,row);
   int w = 0;
   for(int i=0;i<cells;i++)
   {
      int a = PnlDualCellX(item,row,i);
      int b = PnlDualCellX(item,row,i+1);
      w = (i == cells-1) ? a + PNL_DUAL_SW_W + 6 + 12 : b;
   }
   return w;
}

//--- inverse of PnlSetRow: the DISPLAY row that renders a SETTING row.
//--- The palette tables (PalKindRow / PalOpenForItem / PalUpdateLive) speak
//--- SETTING rows; everything that touches an object needs the display row.
int PnlDispRowOfSet(const int item,const int setRow)
{
   if(item < 0 || item >= PNL_COUNT) return -1;
   PnlEnsureSpec(item);
   if(g_PnlSpecCount[item] == 0) return setRow;
   for(int r=0;r<g_PnlSpecCount[item];r++)
   {
      int si = g_PnlSpecStart[item] + r;
      if(g_PnlSpec[si].s0 < 0) continue;
      if(setRow >= g_PnlSpec[si].s0 && setRow < g_PnlSpec[si].s0 + g_PnlSpec[si].n) return r;
   }
   return -1;
}

//--- CSET cell under the cursor -> the SETTING row whose colour it edits
bool PnlCsetHit(const int mx,const int my,int &item,int &row,int &setRow)
{
   item=-1; row=-1; setRow=-1;
   if(g_PnlOpen < 0) return false;
   int it = g_PnlOpen;
   if(!PnlSpecCard(it)) return false;
   int px = g_PnlX[it], py = g_PnlY[it];
   int n  = PnlRowsCount(it);
   for(int r=0;r<n;r++)
   {
      if(PnlRowKind(it,r) != PNL_K_CSET) continue;
      int bx = PnlRowBaseX(it,r);
      int m = PnlRowMembers(it,r);
      int total = m*PNL_CSET_W + (m-1)*PNL_CSET_GAP;
      int x0 = bx + (PNL_WEL - total)/2;
      int ry = py + PNL_HEAD_H + PnlRowLine(it,r)*PNL_ROW_H;
      for(int i=0;i<m;i++)
      {
         int cx = x0 + i*(PNL_CSET_W+PNL_CSET_GAP);
         if(mx >= cx-3 && mx <= cx+PNL_CSET_W+3 && my >= ry+13 && my <= ry+41)
         {
            item=it; row=r; setRow=PnlMemberRow(it,r,i);
            return true;
         }
      }
   }
   return false;
}

//--- section band under the cursor -> (item, display row)
bool PnlBandHit(const int mx,const int my,int &item,int &row)
{
   item=-1; row=-1;
   if(g_PnlOpen < 0) return false;
   int it = g_PnlOpen;
   if(!PnlSpecCard(it)) return false;
   int px = g_PnlX[it], py = g_PnlY[it];
   int n  = PnlRowsCount(it);
   for(int r=0;r<n;r++)
   {
      if(PnlRowKind(it,r) != PNL_K_SEC) continue;
      int bx = PnlRowBaseX(it,r);
      int ry = py + PNL_HEAD_H + PnlRowLine(it,r)*PNL_ROW_H;
      // WIDE: bands span both columns — hit the whole card width
      if(mx >= bx+PNL_PAD_X-6 && mx <= bx+PnlCardW(it)-PNL_PAD_X+6 && my >= ry+5 && my <= ry+37)
      {
         item=it; row=r;
         return true;
      }
   }
   return false;
}

//--- DUAL cell under the cursor -> (row, cell); cell == members means the
//--- synthetic ALL cell.
bool PnlDualHit(const int mx,const int my,int &item,int &row,int &cell)
{
   item=-1; row=-1; cell=-1;
   if(g_PnlOpen < 0) return false;
   int it = g_PnlOpen;
   if(!PnlSpecCard(it)) return false;
   int px = g_PnlX[it], py = g_PnlY[it];
   int n  = PnlRowsCount(it);
   for(int r=0;r<n;r++)
   {
      if(PnlRowKind(it,r) != PNL_K_DUAL) continue;
      int bx = PnlRowBaseX(it,r);
      int cells = PnlDualCells(it,r);
      int x0 = bx + PNL_WEL - PNL_PAD_X - PnlDualTotalW(it,r);
      int ry = py + PNL_HEAD_H + PnlRowLine(it,r)*PNL_ROW_H;
      for(int i=0;i<cells;i++)
      {
         int cx = x0 + PnlDualCellX(it,r,i);
         if(mx >= cx-5 && mx <= cx+PNL_DUAL_SW_W+5 && my >= ry+5 && my <= ry+37)
         {
            item=it; row=r; cell=i;
            return true;
         }
      }
   }
   return false;
}

//--- the colour row's "+" cell (preview .q.add) -> open the full picker
bool PnlColorAddHit(const int mx,const int my,int &item,int &row)
{
   item=-1; row=-1;
   if(g_PnlOpen < 0) return false;
   int it = g_PnlOpen;
   if(!PnlSpecCard(it)) return false;
   int px = g_PnlX[it], py = g_PnlY[it];
   int n  = PnlRowsCount(it);
   for(int r=0;r<n;r++)
   {
      if(PnlRowKind(it,r) != PNL_K_COL) continue;
      int bx = PnlRowBaseX(it,r);
      int ax = bx + PNL_PAD_X + PNL_QSW_PREV + PNL_QSW_GAP
                  + PNL_QSW_N*(PNL_QSW_W+PNL_QSW_GAP);
      int ry = py + PNL_HEAD_H + PnlRowLine(it,r)*PNL_ROW_H;
      if(mx >= ax-4 && mx <= ax+PNL_QSW_ADD+4 && my >= ry+14 && my <= ry+44)
      {
         item=it; row=r;
         return true;
      }
   }
   return false;
}

#endif // BIOTAK_PANELS_ROWS_MQH
