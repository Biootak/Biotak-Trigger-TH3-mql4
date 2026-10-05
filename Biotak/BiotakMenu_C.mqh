// BiotakMenu_C.mqh - BiotakMenu.mqh split 2026-09-29: exact lines 2842-4015, byte-identical, zero renames.
#ifndef BIOTAK_MENU_C_MQH
#define BIOTAK_MENU_C_MQH

void ToolsCreateBadge(const int i)
{
   int badgeX, badgeY;
   ToolsBadgePos(i, badgeX, badgeY);
   int feat = ToolFeature(i);

   string bg = ToolsBadgeBg(i);
   if(ObjectFind(0, bg) < 0)
   {
      if(!ObjectCreate(0, bg, OBJ_BITMAP_LABEL, 0, 0, 0)) return;
   }
   ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, badgeX);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, badgeY);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, CIRC_BADGE_SIZE);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, CIRC_BADGE_SIZE);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, CLR_CIRC_BADGE_BG);
   // BADGEBMP-OFF (P-UI-71c): this used to point BMPFILE at `badge.bmp`, a file
   // that has never existed in Files/Icons and was never declared with
   // `#resource` — so it resolved to nothing on every build (badges are retired
   // anyway, NOBADGES) and asked MT4 to re-load a missing bitmap on every badge
   // repaint. The badge is its BGCOLOR + the value label below; a dead bitmap
   // reference can only ever fail silently, so it is gone. Restore the two
   // OBJPROP_BMPFILE writes together with a real, DECLARED `badge.bmp` if the
   // badge skin ever comes back.          ObjectSetString(0, bg, OBJPROP_TOOLTIP, "");   // P-UI-119
   ObjectSetInteger(0, bg, OBJPROP_STATE, false);
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, bg, OBJPROP_ZORDER, Z_MENU_BADGE);

   string txt = ToolsBadgeTxt(i);
   if(ObjectFind(0, txt) < 0)
   {
      if(!ObjectCreate(0, txt, OBJ_LABEL, 0, 0, 0)) return;
   }
   ObjectSetInteger(0, txt, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, txt, OBJPROP_ANCHOR, ANCHOR_CENTER);
   ObjectSetInteger(0, txt, OBJPROP_XDISTANCE, badgeX + CIRC_BADGE_SIZE / 2);
   ObjectSetInteger(0, txt, OBJPROP_YDISTANCE, badgeY + CIRC_BADGE_SIZE / 2);
   ObjectSetString(0, txt, OBJPROP_TEXT, CircBadgeText(feat));
   ObjectSetInteger(0, txt, OBJPROP_COLOR, CLR_CIRC_BADGE_TXT);
   ObjectSetInteger(0, txt, OBJPROP_FONTSIZE, PnlPt(CIRC_PT_BADGE));
   ObjectSetString(0, txt, OBJPROP_FONT, BioChromeFont());          ObjectSetString(0, txt, OBJPROP_TOOLTIP, "");   // P-UI-119
   ObjectSetInteger(0, txt, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, txt, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, txt, OBJPROP_ZORDER, Z_MENU_BADGE_TX);
}

void CircBadgeDir(const int i, double &dx, double &dy)
{
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   if(cw <= 0) cw = 1920;
   if(ch <= 0) ch = 1080;
   int cx, cy;
   CircLayout(i, cx, cy);
   dx = cx - g_UI.menuX;
   dy = cy - g_UI.menuY;
   if(g_UI.menuX <= CIRC_EDGE_TRIGGER)           { dx = 1;  dy = 0;  return; }
   if(g_UI.menuX >= cw - CIRC_EDGE_TRIGGER)      { dx = -1; dy = 0;  return; }
   if(g_UI.menuY <= CIRC_EDGE_TRIGGER)           { dx = 0;  dy = 1;  return; }
   if(g_UI.menuY >= ch - CIRC_EDGE_TRIGGER)      { dx = 0;  dy = -1; return; }
   double len = MathSqrt(dx * dx + dy * dy);
   if(len > 0.1) { dx /= len; dy /= len; } else { dx = 0; dy = -1; }
}

void CircBadgePos(const int i, int &x, int &y)
{
   int cx, cy;
   CircLayout(i, cx, cy);
   double dx, dy;
   CircBadgeDir(i, dx, dy);
   double off = CIRC_BTN_SIZE / 2 + CIRC_BADGE_FLOAT;
   x = (int)MathRound(cx + dx * off - CIRC_BADGE_SIZE / 2.0);
   y = (int)MathRound(cy + dy * off - CIRC_BADGE_SIZE / 2.0);
}

void CircCreateBadge(const int i)
{
   int size = CIRC_BADGE_SIZE;
   int badgeX, badgeY;
   CircBadgePos(i, badgeX, badgeY);
   int feat = RingFeature(i);

   string bg = CircBadgeBg(i);
   if(ObjectFind(0, bg) < 0)
   {
      if(!ObjectCreate(0, bg, OBJ_BITMAP_LABEL, 0, 0, 0)) return;
   }
   ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, badgeX);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, badgeY);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, size);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, size);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, CLR_CIRC_BADGE_BG);
   // BADGEBMP-OFF (P-UI-71c): this used to point BMPFILE at `badge.bmp`, a file
   // that has never existed in Files/Icons and was never declared with
   // `#resource` — so it resolved to nothing on every build (badges are retired
   // anyway, NOBADGES) and asked MT4 to re-load a missing bitmap on every badge
   // repaint. The badge is its BGCOLOR + the value label below; a dead bitmap
   // reference can only ever fail silently, so it is gone. Restore the two
   // OBJPROP_BMPFILE writes together with a real, DECLARED `badge.bmp` if the
   // badge skin ever comes back.          ObjectSetString(0, bg, OBJPROP_TOOLTIP, "");   // P-UI-119
   ObjectSetInteger(0, bg, OBJPROP_STATE, false);
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, bg, OBJPROP_ZORDER, Z_MENU_BADGE);

   // Badge text label (value shown inside the amber badge)
   string txt = CircBadgeTxt(i);
   if(ObjectFind(0, txt) < 0)
   {
      if(!ObjectCreate(0, txt, OBJ_LABEL, 0, 0, 0)) return;
   }
   ObjectSetInteger(0, txt, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, txt, OBJPROP_ANCHOR, ANCHOR_CENTER);
   ObjectSetInteger(0, txt, OBJPROP_XDISTANCE, badgeX + size / 2);
   ObjectSetInteger(0, txt, OBJPROP_YDISTANCE, badgeY + size / 2);
   ObjectSetString(0, txt, OBJPROP_TEXT, CircBadgeText(feat));
   ObjectSetInteger(0, txt, OBJPROP_COLOR, CLR_CIRC_BADGE_TXT);
   ObjectSetInteger(0, txt, OBJPROP_FONTSIZE, PnlPt(CIRC_PT_BADGE));
   ObjectSetString(0, txt, OBJPROP_FONT, BioChromeFont());          ObjectSetString(0, txt, OBJPROP_TOOLTIP, "");   // P-UI-119
   ObjectSetInteger(0, txt, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, txt, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, txt, OBJPROP_ZORDER, Z_MENU_BADGE_TX);
}

void CircCreateItem(const int i)
{
   int x, y;
   CircLayout(i, x, y);
   int bx = x - CIRC_BTN_SIZE / 2;
   int by = y - CIRC_BTN_SIZE / 2;
   int feat = RingFeature(i);
   bool on = CircFeatureLit(feat);

   string bg = CircBg(i);
   if(ObjectFind(0, bg) < 0)
   {
      if(!ObjectCreate(0, bg, OBJ_BITMAP_LABEL, 0, 0, 0)) return;
   }
   string bgRes = on ? "::Files\\Icons\\circ_on.bmp" : "::Files\\Icons\\circ_off.bmp";
   ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, bx - CIRC_BG_MARGIN);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, by - CIRC_BG_MARGIN);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, CIRC_BG_SIZE);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, CIRC_BG_SIZE);
   ObjectSetString(0, bg, OBJPROP_BMPFILE, 0, bgRes);
   ObjectSetString(0, bg, OBJPROP_BMPFILE, 1, bgRes);
   ObjectSetString(0, bg, OBJPROP_TOOLTIP, "");   // P-UI-119
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, bg, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, bg, OBJPROP_BACK, false);
   ObjectSetInteger(0, bg, OBJPROP_ZORDER, Z_MENU_ITEM);

   string icon = CircIcon(i);
   if(ObjectFind(0, icon) >= 0)
      ObjectDelete(0, icon);
   if(!ObjectCreate(0, icon, OBJ_BITMAP_LABEL, 0, 0, 0)) return;
   CircConfigureIcon(icon, feat, on,
      bx + CIRC_BTN_SIZE / 2,
      by + CIRC_BTN_SIZE / 2);

   if(CircHasBadge(feat))
   {
      CircCreateBadge(i);
      if(!on) CircShowBadge(i, false);   // feature off → keep badge hidden
   }
}

void ToolsCreateItem(const int toolIdx)
{
   int x, y;
   ToolsLayout(toolIdx, x, y);
   int feat = ToolFeature(toolIdx);
   bool on = CircFeatureLit(feat);

   // Skin follows the MODE: circular glass disc in the fan/rail/ring, rounded
   // tile in the grid panel. Size and margin move together with it (see SubBgSize).
   int bgSize = SubBgSize();
   int bx = x - bgSize / 2;
   int by = y - bgSize / 2;

   string bg = ToolsBg(toolIdx);
   if(ObjectFind(0, bg) < 0) if(!ObjectCreate(0, bg, OBJ_BITMAP_LABEL, 0, 0, 0)) return;
   string bgRes = SubBgRes(on);
   ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, bx);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, by);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, bgSize);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, bgSize);
   ObjectSetString(0, bg, OBJPROP_BMPFILE, 0, bgRes);
   ObjectSetString(0, bg, OBJPROP_BMPFILE, 1, bgRes);
   ObjectSetString(0, bg, OBJPROP_TOOLTIP, "");   // P-UI-119
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, bg, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, bg, OBJPROP_BACK, false);
   ObjectSetInteger(0, bg, OBJPROP_ZORDER, Z_MENU_ITEM);

   string icon = ToolsIcon(toolIdx);
   if(ObjectFind(0, icon) >= 0)
      ObjectDelete(0, icon);
   if(!ObjectCreate(0, icon, OBJ_BITMAP_LABEL, 0, 0, 0)) return;
   CircConfigureIcon(icon, feat, on, x, y);

   // Settings badge (click → open the item's panel). Created only when the
   // feature has a panel; hidden (off-screen) when the feature is off.
   if(CircHasBadge(feat))
   {
      ToolsCreateBadge(toolIdx);
      if(!CircFeatureLit(feat)) ToolsShowBadge(toolIdx, false);
   }
}

void ToolsShowBadge(const int i, const bool show)
{
   int x = CIRC_HIDE_POS, y = CIRC_HIDE_POS;
   if(show)
      ToolsBadgePos(i, x, y);
   int tx = (show ? x + CIRC_BADGE_SIZE / 2 : x);
   int ty = (show ? y + CIRC_BADGE_SIZE / 2 : y);
   if(ObjectFind(0, ToolsBadgeBg(i)) >= 0)
   {
      ObjectSetInteger(0, ToolsBadgeBg(i), OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, ToolsBadgeBg(i), OBJPROP_YDISTANCE, y);
   }
   if(ObjectFind(0, ToolsBadgeTxt(i)) >= 0)
   {
      ObjectSetInteger(0, ToolsBadgeTxt(i), OBJPROP_XDISTANCE, tx);
      ObjectSetInteger(0, ToolsBadgeTxt(i), OBJPROP_YDISTANCE, ty);
   }
}

//+------------------------------------------------------------------+
//| P-UI-122 — THE ORB GOES WHERE THE HAND PUTS IT.                  |
//|                                                                  |
//| P-UI-121c reserved the face's crown (124 px) inside this band so |
//| "above" was always available — and the answer was «الان خیلی از  |
//| فاصله گرفته»: a parked orb could no longer reach the top of its  |
//| own chart. The reserve is gone; a top where "above" does not fit |
//| is answered by the placer's own ladder, not by moving the orb.    |
//|                                                                  |
//| ONE owner: CircCreateOrb, UpdateCircularMenuPosition and the orb   |
//| drag each carried their own copy of the same four clamp lines      |
//| (H-06) — all three ask here now.                                  |
//+------------------------------------------------------------------+
void CircOrbBounds(const int cw, const int ch,
                   int &minX, int &minY, int &maxX, int &maxY)
{
   minX = CIRC_PAD + CIRC_ORB_RADIUS;
   minY = CIRC_PAD + CIRC_ORB_RADIUS;
   maxX = cw - CIRC_PAD - CIRC_ORB_RADIUS;
   maxY = ch - CIRC_PAD - CIRC_ORB_RADIUS;
   if(minY > maxY) minY = maxY;
}

void CircCreateOrb()
{
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   if(cw <= 0) cw = 1920;
   if(ch <= 0) ch = 1080;
   int bnX, bnY, bxX, bxY;
   CircOrbBounds(cw, ch, bnX, bnY, bxX, bxY);   // P-UI-121c: the orb's one allowed band
   g_UI.menuX = ClampInt(g_UI.menuX, bnX, bxX);
   g_UI.menuY = ClampInt(g_UI.menuY, bnY, bxY);

   int x = g_UI.menuX - CIRC_ORB_SIZE / 2;
   int y = g_UI.menuY - CIRC_ORB_SIZE / 2;

   string orbBg = CircOrbBg();
   if(ObjectFind(0, orbBg) < 0)
      ObjectCreate(0, orbBg, OBJ_BITMAP_LABEL, 0, 0, 0);
   ObjectSetInteger(0, orbBg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, orbBg, OBJPROP_XDISTANCE, x - CIRC_ORB_BG_MARGIN);
   ObjectSetInteger(0, orbBg, OBJPROP_YDISTANCE, y - CIRC_ORB_BG_MARGIN);
   ObjectSetInteger(0, orbBg, OBJPROP_XSIZE, CIRC_ORB_BG_SIZE);
   ObjectSetInteger(0, orbBg, OBJPROP_YSIZE, CIRC_ORB_BG_SIZE);
   ObjectSetString(0, orbBg, OBJPROP_BMPFILE, 0, CircOrbRes());
   ObjectSetString(0, orbBg, OBJPROP_BMPFILE, 1, CircOrbRes());
   ObjectSetInteger(0, orbBg, OBJPROP_BGCOLOR, CLR_CIRC_ORB_SKIN);   // P-UI-69c: was a call-site literal
   ObjectSetInteger(0, orbBg, OBJPROP_STATE, false);
   ObjectSetInteger(0, orbBg, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, orbBg, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, orbBg, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, orbBg, OBJPROP_BACK, false);
   ObjectSetInteger(0, orbBg, OBJPROP_ZORDER, Z_MENU_ORB);
   ObjectSetString(0, orbBg, OBJPROP_TOOLTIP, "");   // P-UI-119: the drawn chip is the ONE hover box

   // No center overlay: the medallion lives entirely in orb_bg.bmp (P-ICONS-04).
   // Delete the retired CircOrbIcon object on charts that still have it.
   ObjectDelete(0, CircOrbIcon());
}

void CreateMenu()
{
   // P-UI-65: this is the one UI entry point every attach (and every TF switch)
   // runs, and the click claim is gesture state - it must not cross instances.
   // Idempotent, and a no-op while the button is down.
   UIReleaseClaimReset();
   CircCreateOrb();
   CircRefreshOrbSkin();   // ORBSTATE: bow when closed, TRex when open
   if(!g_UI.menuVisible) return;
   for(int i = 0; i < RING_COUNT; i++)
      CircCreateItem(i);
   if(g_ToolsOpen)
      for(int t = 0; t < TOOL_COUNT; t++) ToolsCreateItem(t);
}

void CreateToolsMenu()
{
   if(!g_UI.menuVisible) return;
   if(TOOL_COUNT <= 0) return;                  // nothing to show — stay closed
   g_ToolsOpen = true;
   g_ToolsPage = 0;                             // always open on the first page
   SubInvalidateLayout();                       // fresh geometry for this open
   // SUB-MENU: hide EVERY main-ring item first (the orb stays). With nothing else
   // on screen the chosen geometry provably cannot overlap anything — any
   // position, any edge. The fan (r=112) and the full ring (r=100) genuinely
   // cannot coexist with the main ring at r=64: 44px buttons + their glow overlap.
   for(int i = 0; i < RING_COUNT; i++)
   {
      ObjectDelete(0, CircIcon(i));
      ObjectDelete(0, CircBg(i));
   }
   SubChromeCreate();                           // panel backdrop + header + pager
   for(int t = 0; t < TOOL_COUNT; t++) ToolsCreateItem(t);
   ChartRedraw();
}

// restoreRing=false when the whole menu is being torn down: DeleteMenu() has already
// wiped the ring, and recreating it here would leak objects onto the chart.
void DeleteToolsMenu(const bool restoreRing = true)
{
   for(int t = 0; t < TOOL_COUNT; t++)
   {
      ObjectDelete(0, ToolsBg(t));
      ObjectDelete(0, ToolsIcon(t));
      ObjectDelete(0, ToolsBadgeBg(t));
      ObjectDelete(0, ToolsBadgeTxt(t));
   }
   SubChromeDelete();                           // panel + header + pager + dots
   g_ToolsOpen = false;
   g_ToolsPage = 0;                             // next open starts on page 1 again
   SubInvalidateLayout();
   if(restoreRing && g_UI.menuVisible)             // bring the ring back
      for(int i = 0; i < RING_COUNT; i++) CircCreateItem(i);
   ChartRedraw();
}

// Re-place every cell + refresh the pager for the CURRENT page (a page flip).
// Cheap: TOOL_COUNT object moves and no bitmap re-decode — the panel BMP depends
// on the row count, and a flip never changes that.
void SubApplyPage()
{
   if(!g_ToolsOpen) return;
   for(int t = 0; t < TOOL_COUNT; t++) ToolsMoveItem(t);
   SubChromeCreate();
}

// Rebuild the sub-menu objects IN PLACE after the geometry shape changed (chart
// resized / TF switched / the orb was dragged out of a chart corner). Keeps the
// user where they were: no page reset, no ring restore, no close.
void SubRebuild()
{
   if(!g_ToolsOpen) return;
   SubChromeDelete();
   for(int t = 0; t < TOOL_COUNT; t++)
   {
      ObjectDelete(0, ToolsBg(t));
      ObjectDelete(0, ToolsIcon(t));
      ObjectDelete(0, ToolsBadgeBg(t));
      ObjectDelete(0, ToolsBadgeTxt(t));
   }
   // A shorter chart pages MORE, so the current page may no longer exist.
   int pages = SubPageCount();
   if(g_ToolsPage > pages - 1) g_ToolsPage = pages - 1;
   if(g_ToolsPage < 0)          g_ToolsPage = 0;
   SubChromeCreate();
   for(int t = 0; t < TOOL_COUNT; t++) ToolsCreateItem(t);
   ChartRedraw();
}

// Shape fingerprint of what is currently BUILT on the chart. Comparing against
// this (rather than against a before/after snapshot) is what makes the drag
// release correct: while dragging, SubMode() returns the FROZEN value, so a
// snapshot taken at release time would already show the new mode and skip the
// rebuild the release actually needs.
static int  s_SubBuiltMode  = -1;
static int  s_SubBuiltRows  = 0;
static bool s_SubBuiltPaged = false;

void SubNoteBuilt()
{
   s_SubBuiltMode  = SubMode();
   s_SubBuiltRows  = SubVisibleRows();
   s_SubBuiltPaged = SubIsPaged();
}

void SubRelayoutIfNeeded()
{
   if(!g_ToolsOpen || !g_UI.menuVisible) return;
   if(s_SubBuiltMode == SubMode() && s_SubBuiltRows == SubVisibleRows()
      && s_SubBuiltPaged == SubIsPaged())
      return;                                   // same shape — the move already ran
   SubRebuild();
}

//--- P-UI-129 (2026-09-25): the RING family alone, ONE owner. `DeleteMenu`
//--- (every teardown) and the orb TOGGLE both want exactly this, and the toggle
//--- wants nothing else — so it is a function, not a loop written twice.
void DeleteRing()
{
   for(int i = 0; i < RING_COUNT; i++)
   {
      ObjectDelete(0, CircIcon(i));
      ObjectDelete(0, CircBg(i));
      ObjectDelete(0, CircBadgeBg(i));
      ObjectDelete(0, CircBadgeTxt(i));
   }
}

void DeleteMenu()
{
   DeleteRing();
   DeleteToolsMenu(false);   // ring already wiped above — do not recreate it
   ObjectDelete(0, CircOrbBg());
   ObjectDelete(0, CircOrbIcon());
   s_CircTipFeat = -2;   // tooltip objects share the prefix pattern below
   s_TipPendFeat = -2;
   ObjectDelete(0, CircTipBg());
   ObjectDelete(0, CircTipTxT());
   ObjectDelete(0, CircTipTxH());
   ObjectDelete(0, CircTipArt());
}

void CircMoveItem(const int i)
{
   int x, y;
   CircLayout(i, x, y);
   int bx = x - CIRC_BTN_SIZE / 2;
   int by = y - CIRC_BTN_SIZE / 2;
   if(ObjectFind(0, CircIcon(i)) >= 0)
   {
      ObjectSetInteger(0, CircIcon(i), OBJPROP_XDISTANCE, x - CIRC_ICON_SIZE / 2);
      ObjectSetInteger(0, CircIcon(i), OBJPROP_YDISTANCE, y - CIRC_ICON_SIZE / 2);
   }
   if(ObjectFind(0, CircBg(i)) >= 0)
   {
      ObjectSetInteger(0, CircBg(i), OBJPROP_XDISTANCE, bx - CIRC_BG_MARGIN);
      ObjectSetInteger(0, CircBg(i), OBJPROP_YDISTANCE, by - CIRC_BG_MARGIN);
   }
   int feat = RingFeature(i);
   if(CircHasBadge(feat)) CircMoveBadge(i);
}

void CircMoveBadge(const int i)
{
   int feat = RingFeature(i);
   if(!CircFeatureLit(feat))
   {
      CircShowBadge(i, false);
      return;
   }
   int x, y;
   CircBadgePos(i, x, y);
   if(ObjectFind(0, CircBadgeBg(i)) >= 0)
   {
      ObjectSetInteger(0, CircBadgeBg(i), OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, CircBadgeBg(i), OBJPROP_YDISTANCE, y);
   }
   if(ObjectFind(0, CircBadgeTxt(i)) >= 0)
   {
      ObjectSetInteger(0, CircBadgeTxt(i), OBJPROP_XDISTANCE, x + CIRC_BADGE_SIZE / 2);
      ObjectSetInteger(0, CircBadgeTxt(i), OBJPROP_YDISTANCE, y + CIRC_BADGE_SIZE / 2);
   }
}

void ToolsMoveItem(const int t)
{
   // Off-page items are parked EXPLICITLY: ToolsLayout() refuses to clamp a
   // parked item (the clamp would drag it back on-chart), so without this a cell
   // from the previous page keeps sitting at its old coordinates after a flip.
   if(!SubItemOnPage(t)) { SubParkItem(t); return; }

   int x, y;
   ToolsLayout(t, x, y);
   int bgSize = SubBgSize();
   if(ObjectFind(0, ToolsBg(t)) >= 0)
   {
      ObjectSetInteger(0, ToolsBg(t), OBJPROP_XDISTANCE, x - bgSize / 2);
      ObjectSetInteger(0, ToolsBg(t), OBJPROP_YDISTANCE, y - bgSize / 2);
   }
   if(ObjectFind(0, ToolsIcon(t)) >= 0)
   {
      ObjectSetInteger(0, ToolsIcon(t), OBJPROP_XDISTANCE, x - CIRC_ICON_SIZE / 2);
      ObjectSetInteger(0, ToolsIcon(t), OBJPROP_YDISTANCE, y - CIRC_ICON_SIZE / 2);
   }
   // Badge follows the item while dragging the orb
   int featT = ToolFeature(t);
   if(CircHasBadge(featT) && ObjectFind(0, ToolsBadgeBg(t)) >= 0)
      ToolsShowBadge(t, CircFeatureOn(featT));
}

void CircApplyMenuPosition()
{
   int orbX = g_UI.menuX - CIRC_ORB_SIZE / 2;
   int orbY = g_UI.menuY - CIRC_ORB_SIZE / 2;
   if(ObjectFind(0, CircOrbBg()) >= 0)
   {
      ObjectSetInteger(0, CircOrbBg(), OBJPROP_XDISTANCE, orbX - CIRC_ORB_BG_MARGIN);
      ObjectSetInteger(0, CircOrbBg(), OBJPROP_YDISTANCE, orbY - CIRC_ORB_BG_MARGIN);
   }

   if(g_UI.menuVisible)
   {
      for(int i = 0; i < RING_COUNT; i++)
         CircMoveItem(i);
      if(g_ToolsOpen)
      {
         SubChromeMove();   // panel + header + pager translate with the orb
         for(int t = 0; t < TOOL_COUNT; t++) ToolsMoveItem(t);
      }
   }
}

void UpdateCircularMenuPosition()
{
   if(ObjectFind(0, CircOrbBg()) < 0) return;
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   if(cw <= 0) cw = 1920;
   if(ch <= 0) ch = 1080;

   // P-UI-131e: the HOME is the truth, the live pair is DERIVED from it. A resize used to
   // ratchet the clamped value for the rest of the session and never give the place back
   // when the chart grew again. Guarded off mid-drag: the hand owns the pair until release.
   if(!g_OrbDragging)
   {
      int hx = 0, hy = 0;
      if(CircOrbHomeGet(hx, hy)) { g_UI.menuX = hx; g_UI.menuY = hy; }
   }

   int bnX, bnY, bxX, bxY;
   CircOrbBounds(cw, ch, bnX, bnY, bxX, bxY);   // P-UI-121c: one band, three clamps
   g_UI.menuX = ClampInt(g_UI.menuX, bnX, bxX);
   g_UI.menuY = ClampInt(g_UI.menuY, bnY, bxY);

   CircApplyMenuPosition();
   // A resize / TF switch can change the sub-menu's SHAPE (the arc may no longer
   // fit, or fewer rows may fit and the panel must page). Rebuild only when the
   // shape actually changed — a plain move already ran above.
   SubRelayoutIfNeeded();
   CircTipPinnedTouch();   // P-UI-126: a pinned banner "above the orb" follows by tick, not per move
   SaveUIStates();
}

static bool g_PnlForegroundWasOn = false;
static int  g_PnlForegroundLock = 0;
void PnlLockForeground()
{
   if(g_PnlForegroundLock++ == 0)
   {
      g_PnlForegroundWasOn = (ChartGetInteger(0, CHART_FOREGROUND) != 0);
      if(g_PnlForegroundWasOn) ChartSetInteger(0, CHART_FOREGROUND, false);
   }
}
void PnlUnlockForeground()
{
   if(g_PnlForegroundLock == 0) return;
   if(--g_PnlForegroundLock == 0 && g_PnlForegroundWasOn)
      ChartSetInteger(0, CHART_FOREGROUND, true);
}

// P-UI-73 (2026-09-14) - OPENING A CARD TAKES THE POINTER AWAY FROM THE RING.
//
// The ring's long-press latch is ARMED by the press on a ring item and normally
// consumed by that press's own release - but the card it opens exists from the
// moment the hold fires, while the latch lives until the button comes up. The
// latch's block sits at the TOP of CircHandleMouseMove, i.e. BEFORE the modal
// guard P-UI-72 added, so for as long as it is set the ring answers the press:
// a press landing within LONG_PRESS_MOVE of the arming point is swallowed (it
// returns without ever reaching the card), and a press further away is only
// rescued by the move-cancel. The card therefore reads as un-draggable and its
// controls as dead for that whole gesture - P-UI-72's "one press, one owner"
// failure, one state further in. The abort is called from PnlOpen, the instant
// the card really does own the pointer, and it takes back exactly what the
// armer took: the latch, its DRAG_MENU claim and its chart lock.
//
// What it deliberately does NOT touch:
//   * `g_LongPressFired` - the release-click claim still has to eat the
//     release that ends this hold (the card was opened BY it), and that claim
//     is what clears the fired flag in the CLICK handler (P-UI-40c).
//   * a LIVE orb drag - its own release must reach its own branch.
void CircAbortRingGesture()
{
   if(g_OrbDragging) return;
   if(g_LongPressItem < 0) return;
   g_LongPressItem = -1;
   DragReleaseIf(DRAG_MENU);
   CircUnlockChart();   // the lock the long-press armer took, released once
}

// ══════════════════════════════════════════════════════════════════════════
// P-UI-90 (2026-09-15) — A NEW PRESS IS THE WITNESS THAT ENDED THE OLD ONE.
//
// The ring's own latches (`g_OrbDragging` + its DRAG_MENU claim + the orb's
// `CircLockChart`) all end in the SAME place: the MOUSE_MOVE that carries the
// button-up bit. MT4 emits no such move for a release that does not travel
// (P-BK-03), and the button-up finalizer is itself gated by a physical probe
// (P-UI-73a) — lose both (off-window release, a dialog stealing focus, a probe
// that disagrees) and `g_OrbDragging` stays TRUE forever. The consequences are
// exactly the reported pair:
//   * `ChartLockIntended()` keeps returning true, so `ChartScrollReconcile`
//     re-forces the lock on every 250 ms timer tick, forever;
//   * the orb's `CircLockChart` is never paired with its unlock, and the
//     poisoned "what the user had" that the old capture recorded was written
//     back on the next release — the CHART stayed scroll-locked even after the
//     indicator was removed.
//
// THE WITNESS THAT CANNOT BE MISSED IS THE NEXT PRESS — the same rule
// `PnlReapStaleGestures` (P-UI-81) already uses for the panel's latches. A
// press EDGE means the button went up and came back down; nothing else can
// produce one. So while the ring is being told a NEW press just began, any
// ring latch still set belongs to a gesture that is already over, by
// construction. The heal is FORWARD (the user's next press IS the repair), it
// costs one bool per move, and `MousePressStart`'s rising edge emits exactly
// once per genuine press — so a live drag has no second edge left to reap it,
// and if the terminal ever does deliver one the same press re-arms the claim on
// the very next lines (with the grab offsets recomputed from the orb's current
// spot, so nothing jumps).
// ══════════════════════════════════════════════════════════════════════════
void CircReapStaleRingClaims()
{
   if(g_LongPressItem < 0 && !g_OrbDragging && g_DragOwner != DRAG_MENU) return;
   _LOG_GATE_W Print("[W][UI] P-UI-90: reaped a stale ring claim on a new press "
                     "(orb=", (g_OrbDragging ? 1 : 0), " hold=", g_LongPressItem, ")");
   g_LongPressItem  = -1;
   g_LongPressFired = false;
   g_OrbDragging    = false;   // the press edge proves the previous press is over
   DragReleaseIf(DRAG_MENU);
   CircUnlockChart();          // its chart lock, released once (paired with the arm)
}

void CircHandleMouseMove(const int mx, const int my, const bool leftDown,
                         const bool pressStart)
{
   g_OrbMovedThisEvent = false;

   // P-UI-90: BEFORE anything below claims, drop what a previous press left
   // behind (see the block note). One bool on the steady-state path.
   if(pressStart) CircReapStaleRingClaims();

   // P-UI-126: THE CHIP'S OWN DRAG. A press edge proves the last gesture is over, so
   // the latch is cleared there (the same forward heal the ring uses); a press ON the
   // banner then takes the claim BEFORE any ring arithmetic can, because the chip is
   // drawn over the menu — it is what was pressed. While it is held, nothing else moves.
   if(pressStart) { s_TipDrag = false; s_TipMoved = false; }
   if(s_TipDrag)
   {
      if(leftDown) CircTipDragTo(mx, my);
      else CircTipDragFinalize();   // one ender, shared with the button-up net
      return;
   }
   if(pressStart && CircTipGrabStart(mx, my))
   {
      DragClaim(DRAG_MENU);
      CircLockChart();
      return;
   }

   CircTipOnMove(mx, my, leftDown);   // custom hover tooltip (runs before
   // the hidden-menu guard below so a stale tip also hides when hidden)

   // Hidden menu: only the orb is interactive — and it must STAY draggable
   // while the ring is collapsed. A fresh press may therefore fall through to
   // the orb-grab logic below; hover and everything else is ignored.
   if(!g_UI.menuVisible && !g_OrbDragging && g_LongPressItem < 0 && !pressStart) return;

   if(g_LongPressItem >= 0)
   {
      if(leftDown)
      {
         if(MathAbs(mx - g_LongPressX) > LONG_PRESS_MOVE ||
            MathAbs(my - g_LongPressY) > LONG_PRESS_MOVE)
         {
            g_LongPressItem = -1;
            CircUnlockChart();
         }
         else if(!g_LongPressFired && GetTickCount() - g_LongPressStart >= LONG_PRESS_TIME)
         {
            g_LongPressFired = true;
            PnlOpen(g_LongPressItem);
            UISuppressNextClick();
         }
         return;
      }
      else
      {
         bool panelOpened = g_LongPressFired;   // long-press already opened the panel
         g_LongPressItem = -1;
         DragReleaseIf(DRAG_MENU);
         // Only an opened panel must swallow the release click; a plain item
          // click (released before the 500ms hold) must still reach the toggle.
         if(panelOpened) UISuppressNextClick();
         CircUnlockChart();
      }
   }

   // P-UI-72 (2026-09-14) - A SETTINGS CARD OWNS EVERY PRESS WHILE IT IS OPEN.
   //
   // The ring's hit boxes are GEOMETRIC (CircItemAt / ToolsItemAt / the orb
   // rect), not objects, and the card is movable - so parking the card on the
   // menu (or onto the orb, which is where the menu usually sits) put a ring
   // item UNDER the control the user was aiming at. The press then claimed
   // DRAG_MENU before PnlHandleMouseMove ever saw it, and the two symptoms the
   // user reported as separate bugs were one bug:
   //   * `PnlPressAllowed()` returns false for a foreign live claim, so every
   //     card control under that hit box read as DEAD ("the colour buttons do
   //     nothing when I click them");
   //   * the orb followed the cursor out from under the card ("the panel
   //     detaches and moves to another part").
    // A long-press armed BEFORE the card opened still finishes (its own block
    // above), and a live orb drag still runs to its release. While a card is
    // open the RING arms stay refused (P-UI-72: a ring box under the card would
    // claim DRAG_MENU before the panel sees the press, killing its controls),
    // but the ORB itself stays draggable from pixels the card + palette do not
    // cover — read from the published cover rects, the only panel geometry
    // this earlier include can see. A press ON the card still belongs to it.
    bool panelModal = (g_UIPanelOpen && g_LongPressItem < 0 && !g_OrbDragging);
    bool onCard = (panelModal && g_UIPanelRX >= 0 && g_UIPanelRW > 0 &&
                   mx >= g_UIPanelRX && mx <= g_UIPanelRX + g_UIPanelRW &&
                   my >= g_UIPanelRY && my <= g_UIPanelRY + g_UIPanelRH);
    bool onPal = (panelModal && g_UIPPalRX >= 0 && g_UIPPalRW > 0 &&
                  mx >= g_UIPPalRX && mx <= g_UIPPalRX + g_UIPPalRW &&
                  my >= g_UIPPalRY && my <= g_UIPPalRY + g_UIPPalRH);
    if(panelModal && (onCard || onPal)) return;
    bool orbOnly = (panelModal && !onCard && !onPal);

   if(!g_OrbDragging)
   {
      if(!pressStart) return;
      if(!DragCanGrab(DRAG_MENU)) return;

       const int hitIdx = CircItemAt(mx, my);
       // Items do not exist while the menu is hidden — never arm a long-press
       // on an invisible ring position (only the orb is interactive then).
       // While a card is open only the orb grabs (`orbOnly` above).
       if(hitIdx >= 0 && g_UI.menuVisible && !orbOnly)
      {
         int feat = RingFeature(hitIdx);
         if(feat == CIR_TOOLS) return; // tools toggles submenu on click, no long press
         g_LongPressItem  = RingPanel(hitIdx);
         g_LongPressStart = GetTickCount();
         g_LongPressX     = mx;
         g_LongPressY     = my;
         g_LongPressFired = false;
         DragClaim(DRAG_MENU);
         CircLockChart();
         return;
      }
       const int toolHit = ToolsItemAt(mx, my);
       if(toolHit >= 0 && !orbOnly)
      {
          // Base/Knot arms drawing on CLICK; a hold opens its style card
          // instead (g_LongPressFired guard below skips the arm then).
         if(ToolPanel(toolHit) < 0) return;
         g_LongPressItem  = ToolPanel(toolHit);
         g_LongPressStart = GetTickCount();
         g_LongPressX     = mx;
         g_LongPressY     = my;
         g_LongPressFired = false;
         DragClaim(DRAG_MENU);
         CircLockChart();
         return;
      }

      int ox = g_UI.menuX - CIRC_ORB_SIZE / 2;
      int oy = g_UI.menuY - CIRC_ORB_SIZE / 2;
      if(mx < ox || mx > ox + CIRC_ORB_SIZE || my < oy || my > oy + CIRC_ORB_SIZE) return;
      g_OrbDragging = true;
      g_OrbWasDragged = false;
      g_OrbMoved = false;   // P-UI-147: a fresh press owes the release its own answer
      g_OrbGrabDX = g_UI.menuX - mx;
      g_OrbGrabDY = g_UI.menuY - my;
      g_OrbPressX = mx;
      g_OrbPressY = my;
      DragClaim(DRAG_MENU);
      CircLockChart();
      return;
   }

   if(!leftDown)
   {
      g_OrbDragging = false;
      DragReleaseIf(DRAG_MENU);
      // Only a REAL drag (>= ORB_DRAG_THRESHOLD px) may eat the release click.
      // Suppressing unconditionally made plain orb clicks unreliable whenever
      // the cursor was still moving at button-up (no click → menu won't toggle).
      if(g_OrbWasDragged) UISuppressNextClick();
      CircUnlockChart();
      // P-UI-131e: the RELEASE is the hand's answer, so the HOME is what may be saved
      // from here on — the live pair is clamped and must never become the stored one.
      // P-UI-147: it reads `g_OrbMoved`, the flag ONLY the release clears — so a trailing
      // click that ate `g_OrbWasDragged` can no longer cost the user their drag.
      if(g_OrbMoved)
      {
         CircOrbHomeSet(g_UI.menuX, g_UI.menuY); SaveUIStates(); g_OrbMoved = false;
      }
      // The mode was FROZEN for the whole drag (rebuilding geometry under the
      // hand would flicker). The release is where it is allowed to change, so
      // re-derive it now: dragging out of a corner may turn the arc into a
      // train, or a train into the grid panel.
      SubRelayoutIfNeeded();
      return;
   }

   if(MathAbs(mx - g_OrbPressX) > ORB_DRAG_THRESHOLD ||
      MathAbs(my - g_OrbPressY) > ORB_DRAG_THRESHOLD)
   {
      //--- P-UI-147 (2026-10-02, user: «چرا این منوی اصلی رو که درگ میکنم بعضی وقتا
      //--- بریمیگرده سرجای قبلیش»): TWO FACTS WERE ONE FLAG, and each reader wanted a
      //--- different half. `g_OrbWasDragged` used to mean «the hand really moved the orb»
      //--- AND «the click that follows a drag must be eaten» — so BiotakMenu_D.mqh:16, which
      //--- CLEARS it when the trailing click arrives, could clear it BEFORE the release read
      //--- it, and the home was never saved: the next repaint put the orb back exactly where
      //--- it was. That is the «بعضی وقتا». The movement keeps its own flag, which only the
      //--- release may clear, and the click-eater keeps its own — two facts, two owners, and
      //--- nothing that reads the other.
      g_OrbMoved = true;
      g_OrbWasDragged = true;   // the click-eater's own flag (unchanged meaning)
   }
   if(!g_OrbMoved) return;
   CircReassertLock();   // LEARNING §5: the orb owns the view until release

   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   if(cw <= 0) cw = 1920;
   if(ch <= 0) ch = 1080;
   int nx = mx + g_OrbGrabDX;
   int ny = my + g_OrbGrabDY;
   int orbMinX, orbMinY, orbMaxX, orbMaxY;
   CircOrbBounds(cw, ch, orbMinX, orbMinY, orbMaxX, orbMaxY);   // P-UI-121c: one band, three clamps
   if(nx <= CIRC_EDGE_TRIGGER || nx >= cw - CIRC_EDGE_TRIGGER ||
      ny <= CIRC_EDGE_TRIGGER || ny >= ch - CIRC_EDGE_TRIGGER)
   {
      int rx = MathMax(orbMinX, MathMin(orbMaxX, nx));
      int ry = MathMax(orbMinY, MathMin(orbMaxY, ny));
      int dLeft = rx - orbMinX, dRight = orbMaxX - rx;
      int dTop = ry - orbMinY, dBottom = orbMaxY - ry;
      int edge = 0, best = dLeft;
      if(dRight < best) { edge = 1; best = dRight; }
      if(dTop < best) { edge = 2; best = dTop; }
      if(dBottom < best) { edge = 3; best = dBottom; }
      if(edge == 0) rx = orbMinX;
      else if(edge == 1) rx = orbMaxX;
      else if(edge == 2) ry = orbMinY;
      else ry = orbMaxY;
      nx = rx; ny = ry;
   }
   else
   {
      nx = MathMax(orbMinX, MathMin(orbMaxX, nx));
      ny = MathMax(orbMinY, MathMin(orbMaxY, ny));
   }
   if(nx == g_UI.menuX && ny == g_UI.menuY) return;

   uint now = GetTickCount();
   if(now - g_OrbLastRedrawTick < CIRC_DRAG_REDRAW_INTERVAL) return;
   g_OrbLastRedrawTick = now;

   g_UI.menuX = nx;
   g_UI.menuY = ny;
   CircApplyMenuPosition();
   g_OrbMovedThisEvent = true;
   ChartRedraw();
}

void CircUpdateItemState(const int i)
{
   int feat = RingFeature(i);
   bool on = CircFeatureLit(feat);

   string icon = CircIcon(i);
   if(ObjectFind(0, icon) >= 0)
   {
      int ix, iy;
      CircLayout(i, ix, iy);
      CircConfigureIcon(icon, feat, on, ix, iy);
   }
   string bg = CircBg(i);
   if(ObjectFind(0, bg) >= 0)
   {
      string res = on ? "::Files\\Icons\\circ_on.bmp" : "::Files\\Icons\\circ_off.bmp";
      ObjectSetString(0, bg, OBJPROP_BMPFILE, 0, res);
      ObjectSetString(0, bg, OBJPROP_BMPFILE, 1, res);
      ObjectSetString(0, bg, OBJPROP_TOOLTIP, "");   // P-UI-119   // bg ring keeps a live tooltip too
   }

   if(CircHasBadge(feat)) CircShowBadge(i, on);
}

void ToolsUpdateItemState(const int t)
{
   if(!SubItemOnPage(t)) { SubParkItem(t); return; }   // page not shown -> park

   int feat = ToolFeature(t);
   bool on = CircFeatureLit(feat);
   string icon = ToolsIcon(t);
   if(ObjectFind(0, icon) >= 0)
   {
      int tx, ty;
      ToolsLayout(t, tx, ty);
      CircConfigureIcon(icon, feat, on, tx, ty);
   }
   string bg = ToolsBg(t);
   if(ObjectFind(0, bg) >= 0)
   {
      string res = SubBgRes(on);
      ObjectSetString(0, bg, OBJPROP_BMPFILE, 0, res);
      ObjectSetString(0, bg, OBJPROP_BMPFILE, 1, res);
      ObjectSetString(0, bg, OBJPROP_TOOLTIP, "");   // P-UI-119   // bg ring keeps a live tooltip too
   }
   // Refresh badge text + visibility (e.g. Step/Factor override → Auto)
   if(CircHasBadge(feat) && ObjectFind(0, ToolsBadgeBg(t)) >= 0)
   {
      ToolsShowBadge(t, on);
      string ttxt = ToolsBadgeTxt(t);
      if(ObjectFind(0, ttxt) >= 0)
      {
         ObjectSetString(0, ttxt, OBJPROP_TEXT, CircBadgeText(feat));
         ObjectSetString(0, ttxt, OBJPROP_TOOLTIP, "");   // P-UI-119
      }
      string tbg = ToolsBadgeBg(t);
      ObjectSetString(0, tbg, OBJPROP_TOOLTIP, "");   // P-UI-119
   }
}

void CircShowBadge(const int i, const bool show)
{
   int x = CIRC_HIDE_POS, y = CIRC_HIDE_POS;
   if(show)
      CircBadgePos(i, x, y);
   int tx = (show ? x + CIRC_BADGE_SIZE / 2 : x);
   int ty = (show ? y + CIRC_BADGE_SIZE / 2 : y);
   if(ObjectFind(0, CircBadgeBg(i)) >= 0)
   {
      ObjectSetInteger(0, CircBadgeBg(i), OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, CircBadgeBg(i), OBJPROP_YDISTANCE, y);
   }
   if(ObjectFind(0, CircBadgeTxt(i)) >= 0)
   {
      ObjectSetInteger(0, CircBadgeTxt(i), OBJPROP_XDISTANCE, tx);
      ObjectSetInteger(0, CircBadgeTxt(i), OBJPROP_YDISTANCE, ty);
   }
}

void UpdateCircularItemStates()
{
   for(int i = 0; i < RING_COUNT; i++)
      CircUpdateItemState(i);
   if(g_ToolsOpen)
      for(int t = 0; t < TOOL_COUNT; t++) ToolsUpdateItemState(t);
}

void UpdateCircularBadges()
{
   for(int i = 0; i < RING_COUNT; i++)
   {
      int feat = RingFeature(i);
      if(!CircHasBadge(feat)) continue;
      string bg = CircBadgeBg(i);
      if(ObjectFind(0, bg) >= 0)
         ObjectSetString(0, bg, OBJPROP_TOOLTIP, "");   // P-UI-119
      string txt = CircBadgeTxt(i);
      if(ObjectFind(0, txt) >= 0)
      {
         ObjectSetString(0, txt, OBJPROP_TEXT, CircBadgeText(feat));
         ObjectSetString(0, txt, OBJPROP_TOOLTIP, "");   // P-UI-119
      }
   }
}

//+------------------------------------------------------------------+
//| PERF: change-guarded periodic icon sync.                          |
//| Re-setting OBJPROP_BMPFILE makes MT4 re-decode the bitmap, so the |
//| old every-500ms unconditional pass churned the chart thread even  |
//| when nothing changed. We fingerprint the on/off state of all ring |
//| icons and only run the heavy pass when it actually differs.       |
//+------------------------------------------------------------------+
void UpdateMenuSyncIfChanged()
{
   static ulong s_LastStateHash = 0;

   // FNV-1a fingerprint of ring + tools on/off state AND badge TEXT, so
   // value-only changes (E/S hotkeys, factor override, TH mode) refresh the
   // badges — not just on/off flips.
   ulong h = 1469598103934665603;
   for(int i = 0; i < RING_COUNT; i++)
   {
      int feat = RingFeature(i);
      ulong v = (ulong)(CircFeatureLit(feat) ? 1 : 0);
      h = (h ^ (v + 0x9E3779B97F4A7C15 * (ulong)(feat + 1))) * 1099511628211;
      string t = CircBadgeText(feat);
      for(int c = 0; c < StringLen(t); c++)
         h = (h ^ StringGetCharacter(t, c)) * 1099511628211;
   }
   for(int t = 0; t < TOOL_COUNT; t++)
   {
      int feat = ToolFeature(t);
      ulong v = (ulong)(CircFeatureLit(feat) ? 1 : 0);
      h = (h ^ (v + 0x9E3779B97F4A7C15 * (ulong)(feat + 1))) * 1099511628211;
      string bt = CircBadgeText(feat);
      for(int c = 0; c < StringLen(bt); c++)
         h = (h ^ StringGetCharacter(bt, c)) * 1099511628211;
   }
   if(h == s_LastStateHash) return;   // nothing visible changed -> no churn
   s_LastStateHash = h;

   if(g_UI.menuVisible)
      UpdateCircularItemStates();
   UpdateCircularBadges();
   CircTipRefresh();   // hovered tooltip follows the new state
}

int CircIndexFromName(const string name)
{
   string pfx;
   // NOTE: check "CircBadgeTxt" BEFORE "CircBadge" — the plain-prefix match
   // would otherwise swallow the text object and mis-parse its index.
   pfx = g_UI.btnPrefix + "CircBadgeTxt";
   if(StringFind(name, pfx) == 0) return (int)StringToInteger(StringSubstr(name, StringLen(pfx)));
   pfx = g_UI.btnPrefix + "CircBg";
   if(StringFind(name, pfx) == 0) return (int)StringToInteger(StringSubstr(name, StringLen(pfx)));
   pfx = g_UI.btnPrefix + "CircIcon";
   if(StringFind(name, pfx) == 0) return (int)StringToInteger(StringSubstr(name, StringLen(pfx)));
   pfx = g_UI.btnPrefix + "CircBadge";
   if(StringFind(name, pfx) == 0) return (int)StringToInteger(StringSubstr(name, StringLen(pfx)));
   return -1;
}

int ToolsIndexFromName(const string name)
{
   string pfx;
   // NOTE: check "ToolsBadgeTxt" BEFORE "ToolsBadge" — the plain-prefix match
   // would otherwise swallow the text object and mis-parse its index.
   pfx = g_UI.btnPrefix + "ToolsBadgeTxt";
   if(StringFind(name, pfx) == 0) return (int)StringToInteger(StringSubstr(name, StringLen(pfx)));
   pfx = g_UI.btnPrefix + "ToolsBg";
   if(StringFind(name, pfx) == 0) return (int)StringToInteger(StringSubstr(name, StringLen(pfx)));
   pfx = g_UI.btnPrefix + "ToolsIcon";
   if(StringFind(name, pfx) == 0) return (int)StringToInteger(StringSubstr(name, StringLen(pfx)));
   pfx = g_UI.btnPrefix + "ToolsBadge";
   if(StringFind(name, pfx) == 0) return (int)StringToInteger(StringSubstr(name, StringLen(pfx)));
   return -1;
}

//+------------------------------------------------------------------+
//| Base/Knot session → back to the ring menu (orb-cancel path).      |
//| The ESC / right-click path restores via BaseKnotTakeRestoreFlag() |
//| in HandleUIChartEvent (BiotakPanels.mqh) instead.                 |
//+------------------------------------------------------------------+
void BaseKnotExitToMenu()
{
   if(BaseKnotSessionActive()) BaseKnotCancel();
   BaseKnotTakeRestoreFlag();   // consumed here — the tick hook must not fire again
   if(!g_UI.menuVisible)
   {
      g_UI.menuVisible = true;
      DeleteMenu();
      CreateMenu();
      SaveUIStates();
      ChartRedraw();
   }
}

//+------------------------------------------------------------------+
//| P-UI-95 (2026-09-16) — THE MEASURING TOOL'S ARM PATH, ONE OWNER.  |
//|                                                                  |
//| The steps below used to be spelled INSIDE the Tools cell's        |
//| click branch, and the item they belong to is a MAIN-RING item now |
//| (RING_BASEKNOT, the user's «ایتم اندازه گیری بیس رو بیار توی منوی   |
//| اصلی»). A second copy is how the two surfaces would drift — the   |
//| ring forgetting `PnlCloseAll` (a stale style card or MINI strip    |
//| left floating over a live draw session), or the save landing      |
//| after the object wipe. So the steps MOVE here, verbatim: the ring  |
//| item calls it, and the retired Tools cell (UIBK-OFF) still calls   |
//| the same one — restoring that cell cannot restore a second path.  |
//|                                                                  |
//| Momentary by construction: the ring hides (room for analysis), the |
//| chart locks inside BaseKnotArm(), and the drag-draw flow starts.   |
//| No indicator recalc — REFRESH_NONE (Arm redraws itself).           |
//+------------------------------------------------------------------+
int CircArmBaseKnot()
{
   g_UI.menuVisible = false;
   DeleteMenu();
   CreateMenu();   // orb only — the ring is gone while menuVisible=false
   SaveUIStates();
   PnlCloseAll();   // a stale strip/card must not survive under the draw session
   if(HRaySessionActive()) HRayCancel();   // P-HR-06: the ray yields (its lock goes back)
   if(PathSessionActive()) { PathSessionClear(); PathCancel(); }
   BaseKnotArm();
   UpdateCircularBadges();
   ChartRedraw();
   return REFRESH_NONE;
}

int CircArmPath()
{
   if(BaseKnotSessionActive()) return REFRESH_NONE;
#ifndef BUILD_LITE
   if(LegMeasureSessionActive() || TH3SessionActive()) return REFRESH_NONE;
#endif
   if(PathSessionActive()) { PathSessionClear(); PathCancel(); }
   else PathArm();
   ChartRedraw();
   return REFRESH_NONE;
}

//+------------------------------------------------------------------+
//| P-HR-01 — THE HORIZONTAL RAY'S ARM PATH, ONE OWNER.              |
//| Toggle: press arms, second press cancels. The menu stays OPEN —   |
//| one chart click is what places the ray, and the lit cell is what  |
//| cancels it. No recalc — REFRESH_NONE (Arm redraws itself).        |
//+------------------------------------------------------------------+
int CircArmHRay()
{
   // P-HR-06: one gesture at a time — the ray yields to a live draw session
   // instead of arming under it (a second light whose clicks never arrive).
   if(BaseKnotSessionActive()) return REFRESH_NONE;
#ifndef BUILD_LITE
   if(LegMeasureSessionActive() || TH3SessionActive()) return REFRESH_NONE;
#endif
   if(HRaySessionActive()) HRayCancel();
   else HRayArm();
   ChartRedraw();
   return REFRESH_NONE;
}

//+------------------------------------------------------------------+
//| P-UI-96 (2026-09-19) — THE TH3 TOOL'S ARM PATH, ONE OWNER.        |
//|                                                                  |
//| The ring press used to flip `g_enableTH3Tool` and nothing else:   |
//| the switch moved, the light came on, and no drawing ever started  |
//| — the AB=CD session was reachable only from the V key, which no   |
//| surface of the panel ever mentions.                              |
//|                                                                  |
//| A press now does what the item's tooltip promises: it gets the    |
//| tool READY and takes the four pivots (X, A, B, C). Both           |
//| preconditions are REPAIRED when false, never obeyed silently:     |
//|                                                                  |
//|   * `g_enableTH3Tool` off — the four clicks would draw into a     |
//|     chart whose TH3 objects the visibility hooks skip, i.e. a     |
//|     pattern nobody can see;                                     |
//|   * drawing mode STEPS — that mode ships no click path at all     |
//|     (`ToggleTH3Tool` handles AB=CD only), so the press would be   |
//|     the dead press P-UI-93 forbids. The mode is switched, logged  |
//|     AND persisted, so the card's MODE row cannot disagree with    |
//|     the session that is running.                                |
//|                                                                  |
//| A second press CANCELS, so the item is a toggle whose "on" is the |
//| armed session — which is exactly what the ring light reads.      |
//|                                                                  |
//| The ring is deliberately NOT hidden while placing (BASEKNOT hides |
//| its own): that tool needs the whole chart for ONE drag gesture,   |
//| while four discrete clicks do not compete with a corner menu —    |
//| and the visible item is what lets the same press cancel.         |
//+------------------------------------------------------------------+
int CircArmTH3Draw()
{
#ifndef BUILD_LITE
   if(!g_enableTH3Tool)
   {
      g_enableTH3Tool = true;
      RequestUISync();   // the TH3 TOOL card's ENABLED row displays this flag
      Print("TH3: engine was DISABLED - enabled by the ring press that armed the draw");
   }
   if(g_th3DrawingMode != TH3_MODE_ABCD)
   {
      g_th3DrawingMode = TH3_MODE_ABCD;
      // The mode is a PERSISTED setting, so a repair that lived only in RAM
      // would come back as STEPS on the next attach (the E key's own save
      // rides the same owner).
      RuntimeSettingsSaveOverridesThrottled();
      RequestUISync();   // ...and the MODE row shows the mode the session is in
      Print("TH3: drawing mode STEPS has no click path - switched to AB=CD");
   }
   PnlCloseAll();        // a stale card must not sit under the four clicks (BASEKNOT's arm does the same)
   ToggleTH3Tool(true);  // ONE owner for the toggle; true = swallow the arming press
   CircTipDisarm();      // a hover tip describing "Ready" must not outlive the press
   ChartRedraw();
   return REFRESH_NONE;  // the session draws itself - nothing to recalculate
#else
   // Lite ships no chart-event routing for the AB=CD session (EventHandlers
   // compiles that block out), so an armed session there would take no click
   // and could never end. This build keeps the control it already had.
   g_enableTH3Tool = !g_enableTH3Tool;
   UpdateAllTH3Objects();
   return REFRESH_ALL;
#endif
}

#endif // BIOTAK_MENU_C_MQH
