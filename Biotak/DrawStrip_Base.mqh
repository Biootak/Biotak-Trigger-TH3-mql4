// DrawStrip_Base.mqh - DrawStrip split 2026-09-29: exact lines 678-1460 of DrawStrip.mqh, byte-identical, zero renames.
#ifndef DRAW_STRIP_BASE_MQH
#define DRAW_STRIP_BASE_MQH

//--- P-DRAW-126 (2026-10-01) — THE DIAG CHANNEL DOES NOT WAIT FOR THE TERMINAL.
//--- MEASURED (2026-10-01 20:15:20): the live terminal (`AMarkets - MetaTrader 4`,
//--- data folder `A1660DA4...`, one process up since 15:10:36) showed a full
//--- `20:03:44` frame in its Experts window while `MQL4\Logs\20261001.log` still
//--- ended at `20:01:38.319` — a probe for `20:03:44` counted ZERO, and the file
//--- had not grown in fourteen minutes. MT4 buffers its own journal in RAM and
//--- flushes on its own schedule, so a reader that opens only that file is always
//--- behind the tab it is meant to witness. The diag channel therefore mirrors
//--- every line into a file it owns and flushes per line: `FileFlush` is the one
//--- write whose arrival does not depend on the terminal's buffer.
//--- `tools/diag-live.py` reads THIS file (`<data folder>\MQL4\Files\`); the
//--- Experts log is never the oracle, only a fallback.
//--- P-LOG-3 (2026-10-01) — AND A FLUSH IS NOT ENOUGH IF THE HANDLE IS EXCLUSIVE.
//--- MEASURED 2026-10-01 21:52:50: the file WAS written and flushed
//--- (`biotak_diag_EURUSD.txt`, 62,965 bytes, mtime 21:52:50) — and every reader
//--- failed on it anyway: `open(path,'rb')` -> PermissionError 13, `cp`/`head` ->
//--- "Device or resource busy", `Get-Content` -> "being used by another process".
//--- A plain `FileOpen` in the terminal grants no share, so the bytes were current
//--- and unreachable at the same time: the channel could not be read by the very tool
//--- built to read it. `FILE_SHARE_READ` is the flag that lets another process open
//--- the handle the terminal holds (the stock `MQL4\Scripts\PeriodConverter.mq4`
//--- uses it), so each flushed line is now readable the moment it is written.
//--- P-LOG-3b (2026-10-01) — AND THE FILE IS PER CHART, NOT PER SYMBOL. MEASURED
//--- 21:52..21:58 with the panel open on EURUSD,M1 AND EURUSD,H1: `Symbol()` names
//--- both charts the same, so each instance opened its OWN handle to ONE path and
//--- wrote it from its own position. The file stopped growing (62,965 bytes at
//--- 21:52:50 and again at 21:58:51) while two charts were emitting whole frames,
//--- and the two frames the bytes actually held were both the M1 chart's (221 and
//--- 230 lines, matching the journal's EURUSD,M1 at 21:52:49/21:52:50) — the H1
//--- frames the screen was showing were nowhere in it. `ChartID()` is what
//--- separates two charts of one symbol, so the name carries it.
#ifdef DSTRIP_DIAG
void DrawStripDiagEmit(const string line)
{
   Print(line);
   static int dh = INVALID_HANDLE;
   if(dh == INVALID_HANDLE)
      dh = FileOpen("biotak_diag_" + Symbol() + "_" + IntegerToString(ChartID()) + ".txt",
                    FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
   if(dh == INVALID_HANDLE) return;
   FileWrite(dh, line);
   FileFlush(dh);
}
#else
// P-UI-136 (2026-10-02): the symbol stays DEFINED when the switch is 0, because
// a drawing tool that witnesses its gestures (PathWitness, PathTool.mqh — the
// channel is borrowed by name, this file owns the handle) must not turn the
// whole unit's build into "function not defined" when the census is switched
// off. The fallback is the journal, never silence (AGENTS law 3).
void DrawStripDiagEmit(const string line) { Print(line); }
#endif

#ifdef DSTRIP_DIAG
//--- P-LOG-8 (2026-10-01) — THE AFTER-FRAME. The census is a snapshot taken at dump
//--- time; the SCREEN is later. The wide gear frame of the 2026-10-01 report read
//--- 91/91 PASS (seat, layer, text, back, win, corner) while the screenshot showed the
//--- panel's left column bare, and the whole-chart walk (P-LOG-7) named no cover at
//--- all — so the only question the model cannot answer is WHETHER THE STATE IT SAW
//--- IS STILL THE STATE ON THE CHART when the user screenshots it. A later writer that
//--- deletes, moves or re-rungs a name after the dump is invisible to every snapshot.
//--- So the dump stores what the census saw, and the NEXT paint pass walks that same
//--- name list again and prints only the DELTA: GONE (a later purge), MOVED (a later
//--- writer), NEW (a later cover inside the panel rect), and a `done` line that says
//--- the model survived unchanged when nothing moved. One flag, one pass, no cost.
#define DSTRIP_DIAG_SNAP 384
int    s_dsDiagAfter = 0;                     // 0 idle · 1 armed by the dump · 2 fired
int    s_dsSnapN = 0;
int    s_dsSnapRect[4];                       // bx0, by0, bx1, by1 at snapshot time
string s_dsSnapNm[DSTRIP_DIAG_SNAP];
int    s_dsSnapX[DSTRIP_DIAG_SNAP], s_dsSnapY[DSTRIP_DIAG_SNAP];
int    s_dsSnapW[DSTRIP_DIAG_SNAP], s_dsSnapH[DSTRIP_DIAG_SNAP];
int    s_dsSnapZ[DSTRIP_DIAG_SNAP], s_dsSnapB[DSTRIP_DIAG_SNAP];

void DrawStripDiagSnapRect(const int bx0, const int by0, const int bx1, const int by1)
{
   //--- P-LOG-8b: ONE census, ONE snapshot. The store must never carry a previous
   //--- frame's names: MEASURED on the first live AFTER (23:29:10) — the store held
   //--- 200 names (the narrow frame's 98 still in it) and the delta reported 50
   //--- MOVED / 36 GONE that were only the narrow→wide layout switch
   //--- (`GS0C was=1357,146 now=1357,188`), burying the signal this block exists for.
   s_dsSnapN = 0;
   s_dsSnapRect[0] = bx0; s_dsSnapRect[1] = by0; s_dsSnapRect[2] = bx1; s_dsSnapRect[3] = by1;
}

bool DrawStripDiagSnapAdd(const string nm, const int x, const int y, const int w, const int h,
                          const int z, const int back)
{
   if(s_dsSnapN >= DSTRIP_DIAG_SNAP || ObjectFind(0, nm) < 0) return false;
   s_dsSnapNm[s_dsSnapN] = nm;
   s_dsSnapX[s_dsSnapN] = x; s_dsSnapY[s_dsSnapN] = y;
   s_dsSnapW[s_dsSnapN] = w; s_dsSnapH[s_dsSnapN] = h;
   s_dsSnapZ[s_dsSnapN] = z; s_dsSnapB[s_dsSnapN] = back;
   s_dsSnapN++;
   return true;
}

int DrawStripDiagSnapIdx(const string nm)
{
   for(int i = 0; i < s_dsSnapN; i++) if(s_dsSnapNm[i] == nm) return i;
   return -1;
}

//--- P-LOG-8c (2026-10-01) — A CHART OBJECT'S SCREEN BOX IS NOT ITS XDISTANCE.
//--- `OBJ_RECTANGLE` / `OBJ_TREND` / zones answer `OBJPROP_XDISTANCE` with 0 (that
//--- property belongs to SCREEN objects), so the census's box test read `0,0` for
//--- them and the panel-rect test threw every one away — the one family that CAN
//--- cover this panel (a TH3 zone / BaseKnot box drawn in the foreground) was still
//--- invisible to the walk that exists to name a cover. Their real box is their
//--- TIME/PRICE anchors through `ChartTimePriceToXY`. Labels keep their anchor.
bool DrawStripCensusAnyBox(const string nm, const int oty,
                           int &ox, int &oy, int &ow, int &oh)
{
   if(oty == OBJ_LABEL || oty == OBJ_TEXT) return true;
   ow = DrawStripCensusSize(nm, oty, 0);
   oh = DrawStripCensusSize(nm, oty, 1);
   if(ow > 0 || oh > 0) return true;
   datetime t1 = (datetime)ObjectGetInteger(0, nm, OBJPROP_TIME, 0);
   double   p1 = ObjectGetDouble(0, nm, OBJPROP_PRICE, 0);
   datetime t2 = (datetime)ObjectGetInteger(0, nm, OBJPROP_TIME, 1);
   double   p2 = ObjectGetDouble(0, nm, OBJPROP_PRICE, 1);
   int x1 = 0, y1 = 0, x2 = 0, y2 = 0;
   if(t1 == 0 || !ChartTimePriceToXY(0, 0, t1, p1, x1, y1)) return false;
   if(t2 == 0 || !ChartTimePriceToXY(0, 0, t2, p2, x2, y2)) { ox = x1; oy = y1; ow = 0; oh = 0; return true; }
   ox = (x1 < x2 ? x1 : x2); oy = (y1 < y2 ? y1 : y2);
   ow = (x2 > x1 ? x2 - x1 : x1 - x2);
   oh = (y2 > y1 ? y2 - y1 : y1 - y2);
   return true;
}

void DrawStripDiagAfterRun()
{
   s_dsDiagAfter = 2;
   int gone = 0, moved = 0;
   for(int i = 0; i < s_dsSnapN; i++)
   {
      string nm = s_dsSnapNm[i];
      if(ObjectFind(0, nm) < 0)
      {
         DrawStripDiagEmit("[drawstrip] AFTER GONE obj=" + nm);
         gone++;
         continue;
      }
      int x = (int)ObjectGetInteger(0, nm, OBJPROP_XDISTANCE);
      int y = (int)ObjectGetInteger(0, nm, OBJPROP_YDISTANCE);
      int z = (int)ObjectGetInteger(0, nm, OBJPROP_ZORDER);
      int bk = (int)ObjectGetInteger(0, nm, OBJPROP_BACK);
      if(x != s_dsSnapX[i] || y != s_dsSnapY[i] || z != s_dsSnapZ[i] || bk != s_dsSnapB[i])
      {
         DrawStripDiagEmit("[drawstrip] AFTER MOVED obj=" + nm +
                           " was=" + IntegerToString(s_dsSnapX[i]) + "," + IntegerToString(s_dsSnapY[i]) +
                           ",z" + IntegerToString(s_dsSnapZ[i]) + ",b" + IntegerToString(s_dsSnapB[i]) +
                           " now=" + IntegerToString(x) + "," + IntegerToString(y) +
                           ",z" + IntegerToString(z) + ",b" + IntegerToString(bk));
         moved++;
      }
   }
   int fresh = 0;
   int n = ObjectsTotal(0, -1);
   for(int oi = 0; oi < n; oi++)
   {
      string on = ObjectName(0, oi, -1);
      if(on == "" || DrawStripDiagSnapIdx(on) >= 0) continue;
      int oty = (int)ObjectGetInteger(0, on, OBJPROP_TYPE);
      int ox = (int)ObjectGetInteger(0, on, OBJPROP_XDISTANCE);
      int oy = (int)ObjectGetInteger(0, on, OBJPROP_YDISTANCE);
      if(ox + 8 < s_dsSnapRect[0] || ox > s_dsSnapRect[2] ||
         oy + 8 < s_dsSnapRect[1] || oy > s_dsSnapRect[3]) continue;
      DrawStripDiagEmit("[drawstrip] AFTER NEW obj=" + on + " type=" + IntegerToString(oty) +
                        " xy=" + IntegerToString(ox) + "," + IntegerToString(oy) +
                        " z=" + IntegerToString((int)ObjectGetInteger(0, on, OBJPROP_ZORDER)) +
                        " back=" + IntegerToString((int)ObjectGetInteger(0, on, OBJPROP_BACK)));
      fresh++;
   }
   DrawStripDiagEmit("[drawstrip] AFTER done snap=" + IntegerToString(s_dsSnapN) +
                     " gone=" + IntegerToString(gone) + " moved=" + IntegerToString(moved) +
                     " new=" + IntegerToString(fresh) + " chartObjs=" + IntegerToString(n));
}

//--- P-LOG-9 (RETIRED 2026-10-02) — the probe labels asked MT4's own draw rule and
//--- the screen answered: P1 (content rung) and P2 (rung 1600) at the LEFT seat and
//--- P3 at the right all showed while the left column stayed bare until P-LOG-10, and
//--- the touch test's same-pixel write raised nothing — CREATE is the only raise.
//--- The labels are gone; the law and its record live in DrawStrip_GearPlate (P-LOG-10)
//--- and in contract §6 item 23.
#endif

//--- P-LOG-5 (2026-10-01) — THE CENSUS'S INK COLUMN BELONGS TO EVERY CAPTIONED
//--- OBJECT, NOT TO LABELS ONLY. MEASURED 2026-10-01 22:10
//--- (`biotak_diag_EURUSD_134342075006101685.txt`): the panel passed the diff 91/91
//--- while the ONE class the diff never tested was a button's own text — the census
//--- wrote `ink` for `OBJ_LABEL` only. The swatch row's captions (`1px`..`5px`,
//--- `Solid`..`D-Dot`) are BUTTON TEXT, so the report «بعضی ردیف‌ها متن نداره» could
//--- not be decided from the log at all: a LOST caption and a healthy face both read
//--- `ink=-`, and `diag-diff` reads that same column. A button answers OBJPROP_TEXT
//--- exactly as a label does, so the column carries both now. The helper lives HERE,
//--- not in `DrawStrip_GearB.mqh`, which stands at 1497 of the 1500-line ceiling
//--- (P-SIZE-1500).
string DrawStripCensusInk(const string nm, const int oty)
{
   if(oty != OBJ_LABEL && oty != OBJ_BUTTON) return "-";
   return "\"" + ObjectGetString(0, nm, OBJPROP_TEXT) + "\":" +
          IntegerToString((int)ObjectGetInteger(0, nm, OBJPROP_COLOR));
}

//--- P-LOG-6 (2026-10-01) — THE CENSUS'S BOX TEST IS THE OBJECT'S OWN BOX.
//--- MEASURED 2026-10-01 22:17 (`biotak_diag_EURUSD_134342075006101685.txt`): the
//--- panel's PLATE is painted on every open (`DrawStripGearPlate` -> `DrawStripSkinBmp`
//--- "PnlDrawS_Gbake" / `Gtop` / `Gmid*` / `Gbot`) and it appeared in NOT ONE of the
//--- 187 census lines. The walk took a bitmap label's box from `DrawStripResW/H` of its
//--- RESOURCE, and a name that table does not carry reads 0 — so the plate's box
//--- collapsed to a POINT at `gx-14, gy-14`, its own 14px margin, outside the panel
//--- rect on both axes, and every tile was skipped. The largest object the panel owns
//--- — and the ONE that can hide every control if its rung is wrong, which Skin.mqh's
//--- own P-DRAW-72 note records as a real past failure ("the bake sat ABOVE the tabs,
//--- the hex fields, the Interior switch and the foot") — was the one object the census
//--- could never print. So a diagnostic can answer "who is on top" only for the
//--- objects it is willing to look at. The object answers XSIZE/YSIZE itself (every
//--- writer here sets them); the resource table stays as the fallback for a face that
//--- carries none. Lives HERE, not in DrawStrip_GearB.mqh (1495 of the 1500-line
//--- ceiling, P-SIZE-1500) — and Skin.mqh's `DrawStripIsBg` is included AFTER GearB,
//--- so the census cannot ask it either.
int DrawStripCensusSize(const string nm, const int oty, const int axis)
{
   if(oty == OBJ_BUTTON || oty == OBJ_RECTANGLE_LABEL || oty == OBJ_EDIT ||
      oty == OBJ_BITMAP_LABEL)
   {
      int v = (int)ObjectGetInteger(0, nm, (axis == 0) ? OBJPROP_XSIZE : OBJPROP_YSIZE);
      if(v > 0) return v;
   }
   string bf = ObjectGetString(0, nm, OBJPROP_BMPFILE, 0);
   return (axis == 0) ? DrawStripResW(bf) : DrawStripResH(bf);
}

bool DrawStripCensusInPanel(const string nm, const int oty,
                            const int ox, const int oy,
                            const int bx0, const int by0, const int bx1, const int by1)
{
   int ow = DrawStripCensusSize(nm, oty, 0), oh = DrawStripCensusSize(nm, oty, 1);
   return !(ox + ow < bx0 || ox > bx1 || oy + oh < by0 || oy > by1);
}

void DrawStripGripRelease()
{
   // P-DRAW-32: either carry owns the lock — one release ends whichever is live.
   // P-DRAW-48: and the BOARD's carry is the third, the opacity bar's own drag the
   // fourth (four owners, ONE ender — the button-up net, the close and Esc all
   // come through here).
   if(s_dsGripLive || s_dsGGripLive || s_dsBGripLive || s_dsOpGrab || s_dsPalGrab)
      ChartViewLockRelease();   // P-UI-90: one release per acquire
   s_dsGripLive = false;
   s_dsGGripLive = false;
   s_dsBGripLive = false;
   s_dsOpGrab = false;
   s_dsPalGrab = false;
}
//--- P-DRAW-31 (2026-09-24) — THE STRIP PUBLISHES ITS PLATE. The cards' placement
//--- (`PnlComputePosition`) cannot see this module (included after us, MQL4 is
//--- define-before-use), so the plate's rect is handed over instead: one writer, from
//--- every path that moves, opens or closes the strip, cleared when it is off screen.
//--- `-1` is the "no strip" answer — the same contract `g_UIPanelR*` uses.
//--- P-DRAW-32: and the SETTINGS PANEL is published with it — the two surfaces are ONE
//--- occupancy for every reader (a card must clear both, and a fresh strip must clear
//--- both), so the rect handed over is their UNION while the panel is open. One
//--- contract, one writer, no second global to keep in sync.
// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-64 (2026-09-27) — TWO COLOUR CELLS, ONE BOARD. User order: «رنگ بوردر
// بشه جدا تنظیم کرد ... و fill همه جدا. یک بخش براش اضافه کن». The owner module
// declares `DRAW_SLOT_FILLCLR` (the interior); HERE it is a COLOUR CELL exactly like
// `DRAW_SLOT_COLOR` — own swatch, board and tone — so every surface asks these two
// questions instead of naming one slot. Which board is open stays `s_dsPicker`.
// ══════════════════════════════════════════════════════════════════════════
bool DrawStripIsColorSlot(const int slot)
{
   //--- P-DRAW-BODY-UI: the handle's own colour rides the same palette bridge,
   //--- so it is a colour cell too (same seats, no layout change).
   return (slot == DRAW_SLOT_COLOR || slot == DRAW_SLOT_FILLCLR ||
           slot == DRAW_SLOT_BODYCOLOR);
}
color DrawStripColorRead(const string nm, const int slot)
{
   return (color)(int)DrawSlotRead(nm, slot);
}
//--- what a colour CELL shows: the border cell stores and shows the pure colour,
//--- the interior cell shows the pixel the chart will wear (its own tone applied) —
//--- so the two cells are never two answers to one question.
color DrawStripColorFace(const string nm, const int slot)
{
   color c = DrawStripColorRead(nm, slot);
   if(slot != DRAW_SLOT_FILLCLR) return c;
   return DrawSlotRenderFillColor(nm, c);
}

// ══════════════════════════════════════════════════════════════════════════
// P-PAL-19 (2026-10-02) — THE STRIP ASKS THE CARDS' PALETTE. It has no colour
// board of its own any more: every other surface in this product edits a
// colour through ONE popup (BiotakPanels_PalA/PalB), and the strip was the last
// surface that painted a second one — the two then drifted (the board's own
// catalogue, its own recents, its own hex field), and every defect in it was a
// defect the cards' palette never had.
// The include order decides the shape: DrawStrip is include 99, the panels are
// 124, and MQL4 needs a definition BEFORE its use — so the strip cannot call
// `PalOpenKind` itself. It leaves a REQUEST (below); the entry's bridge line,
// which sees both, performs the open. One bridge, one direction, no prototype.
// ══════════════════════════════════════════════════════════════════════════
static string s_dsPalObj = "";        // the drawing the popup is editing
static int    s_dsPalSlot = DSTRIP_PICK_NONE;
static int    s_dsPalAskSlot = DSTRIP_PICK_NONE;   // the pending open, one click wide
static bool   s_dsPalRepaint = false;      // a pick owes the strip ONE frame (P-PAL-19f)
//--- P-LVL-COLOR (2026-10-04) — ONE LEVEL'S OWN COLOR. -1 = the slot's (whole
//--- drawing); >=0 = the stored level index on s_dsPalObj. The popup is the same
//--- cards palette (one palette, P-PAL-19); only the target is narrower.
static int    s_dsPalLevel = -1;

void DrawStripPalAsk(const int slot)
{
   if(!s_dsOpen || s_dsObj == "") return;
   DrawStripGearClose();
   s_dsPalObj  = s_dsObj;
   s_dsPalSlot = slot;
   s_dsPalAskSlot = slot;
   s_dsPalLevel = -1;
}
//--- a level row's swatch asks through here: same palette, one stored level.
void DrawStripPalAskLevel(const int slot, const int level)
{
   if(!s_dsOpen || s_dsObj == "") return;
   DrawStripGearClose();
   s_dsPalObj  = s_dsObj;
   s_dsPalSlot = slot;
   s_dsPalAskSlot = slot;
   s_dsPalLevel = level;
}
bool DrawStripPalTargetIsLevel() { return (s_dsPalLevel >= 0); }
int    DrawStripPalAsked()   { if(s_dsPalAskSlot == DSTRIP_PICK_NONE) return -1;
                               int a = s_dsPalAskSlot; s_dsPalAskSlot = DSTRIP_PICK_NONE; return a; }
string DrawStripPalTargetObj()  { return s_dsPalObj; }
//--- P-PAL-19: the strip's own rect, for the one caller that places the popup beside
//--- it (the entry's bridge). Three lines, because a bridge that cannot say WHERE the
//--- strip is would park the palette in a corner — P-UI-98r's own finding, one surface
//--- over — and a popup in a corner reads as «the palette is broken».
int    DrawStripPlateX() { return s_dsOpen ? s_dsX : 0; }
int    DrawStripPlateY() { return s_dsOpen ? s_dsY : 0; }
int    DrawStripPlateW() { return s_dsOpen ? s_dsW : 0; }
//--- P-PAL-19e: is the strip still on screen? The bridge asks it so the palette
//--- CLOSES WITH ITS PARENT: a popup over a closed strip is a floater nobody owns,
//--- and it is exactly what «همراه والدش بسته بشه» is. Read here, asked once, in the
//--- only place that can see both sides.
bool   DrawStripPalParentLive() { return s_dsOpen && s_dsObj != ""; }
//--- and the flag the bridge spends: ONE frame, spent once, after the popup's route.
bool   DrawStripPalRepaintTake() { bool b = s_dsPalRepaint; s_dsPalRepaint = false; return b; }
int    DrawStripPalTargetSlot() { return s_dsPalSlot; }
bool   DrawStripPalTargetLive() { return (s_dsPalObj != "" && DrawStripIsColorSlot(s_dsPalSlot)); }
//--- the three the panels' State table asks, each ONE line and each the strip's own
//--- writer — so a pick lands on the drawing exactly the way a card row's own cell
//--- lands on its value, and every dependent (box marks, mid line, opacity) sees it.
color DrawStripPalTargetColor()
{
   if(!DrawStripPalTargetLive()) return clrNONE;
   //--- P-LVL-COLOR: a level target reads its own stored ink, never the slot's.
   if(s_dsPalLevel >= 0)
   {
      if(ObjectFind(0, s_dsPalObj) < 0) return clrNONE;
      if(s_dsPalLevel >= DrawLevelCount(s_dsPalObj)) return clrNONE;
      return (color)(int)ObjectGetInteger(0, s_dsPalObj, OBJPROP_LEVELCOLOR, s_dsPalLevel);
   }
   return DrawStripColorRead(s_dsPalObj, s_dsPalSlot);
}
int DrawStripPalTargetApply(const color c)
{
   if(!DrawStripPalTargetLive()) return 0;
   //--- P-LVL-COLOR: one stored level re-inks (undoable — the level set snapshot
   //--- carries per-level colors), the pen's children follow in the same frame.
   if(s_dsPalLevel >= 0)
   {
      if(ObjectFind(0, s_dsPalObj) < 0) return 0;
      if(s_dsPalLevel >= DrawLevelCount(s_dsPalObj)) return 0;
      if((int)c < 0) return 0;
      DrawStripUndoPush();
      ObjectSetInteger(0, s_dsPalObj, OBJPROP_LEVELCOLOR, s_dsPalLevel, c);
      FibPenSync(s_dsPalObj, false);
      DrawStripRecentPush(c);
      int gotL = (int)ObjectGetInteger(0, s_dsPalObj, OBJPROP_LEVELCOLOR, s_dsPalLevel);
      DrawStripDiagEmit("[drawstrip] PALAPPLY live=1 obj=\"" + s_dsPalObj + "\" slot=" +
                        IntegerToString(s_dsPalSlot) + " level=" + IntegerToString(s_dsPalLevel) +
                        " picked=" + DrawStripColorHex(c) +
                        " read=" + DrawStripColorHex((color)gotL));
      s_dsPalRepaint = true;
      return 1;
   }
   DrawStripColorCommit(s_dsPalSlot, c);
   DrawStripRecentPush(c);
   //--- P-PAL-19d (2026-10-02) — THE SECOND PICK IS A SEPARATE CASE, and the report
   //--- is «یک بار که یک رنگی رو انتخاب میکنم بقیه رنگ‌ها اعمال نمیشه». The MODEL
   //--- says the target is a static that outlives the pick, so the second click
   //--- should take the same three lines as the first — and the screen says it does
   //--- not. Nothing here is guessed: the line below is the WITNESS, through the
   //--- flushed channel (never `Print` — P-LOG-3), and it carries the three numbers
   //--- that decide the case: is the target still live, which slot, and what the
   //--- drawing READS BACK after the commit. `applied=` and `read=` disagreeing is
   //--- the commit; both 0 with `live=1` is the click that never arrived.
   int got = (int)DrawSlotRead(s_dsPalObj, s_dsPalSlot);   // double -> int, explicit (the project's own cast)
   DrawStripDiagEmit("[drawstrip] PALAPPLY live=" + IntegerToString((int)DrawStripPalTargetLive())
                    + " obj=\"" + s_dsPalObj + "\" slot=" + IntegerToString(s_dsPalSlot)
                    + " picked=" + DrawStripColorHex(c)
                    + " read=" + DrawStripColorHex((color)got));
   //--- P-PAL-19f (2026-10-02) — NO REPAINT FROM INSIDE THE POPUP'S OWN ROUTE. The
   //--- first bridge build called `DrawStripPaint()` here, and the report was
   //--- «یک رنگ انتخاب می‌کنم کل استریپ بسته می‌شه»: the strip repainted in the MIDDLE
   //--- of the palette's click, while the palette still owned the event, so the strip
   //--- rebuilt itself from a half-served gesture and the one who closed was the frame
   //--- it was not driving. The apply OWNS A FLAG; the BRIDGE spends it, once, after
   //--- the popup's route has returned — the same discipline the entry already uses
   //--- for «a user action settles the frame it owed, in the same event» (P-PERF-34).
   s_dsPalRepaint = true;
   return 1;
}
int DrawStripPalTargetAlpha()
{
   if(!DrawStripPalTargetLive()) return -1;
   //--- P-LVL-COLOR: one level has no tone of its own (-1 = no TR track).
   if(s_dsPalLevel >= 0) return -1;
   return DrawSlotAlphaGet(s_dsPalObj, s_dsPalSlot);
}
//--- P-DRAW-64a2 (2026-10-02) — WHICH SLOT, IN THE STRIP'S OWN WORDS. The popup's two
//--- role chips hold the KIND (`PAL_DRAW_BORDER` / `PAL_DRAW_FILL`, the panels' ladder);
//--- the SLOT is `DRAW_SLOT_COLOR` / `DRAW_SLOT_FILLCLR`, which is this module's
//--- vocabulary and nobody else's. So the chip asks here and the answer is a slot —
//--- the popup never translates a colour role into a slot index by arithmetic, which is
//--- how a border pick would end up writing the interior's tag.
void DrawStripPalRoleSet(const int role)
{
   if(s_dsPalObj == "" || s_dsPalSlot == DSTRIP_PICK_NONE) return;
   //--- P-DRAW-BODY-UI: a handle colour has no second role — the BORDER/FILL
   //--- chips must not retarget it onto the levels while the popup is open.
   if(s_dsPalSlot == DRAW_SLOT_BODYCOLOR) return;
   //--- P-LVL-COLOR: one level is one target — the role chips keep it.
   if(s_dsPalLevel >= 0) return;
   int want = (role == 0) ? DRAW_SLOT_COLOR : DRAW_SLOT_FILLCLR;
   if(!DrawSlotAvailable(DrawKindOf(s_dsPalObj), want)) return;
   s_dsPalSlot = want;
}
//--- P-PAL-20 — THE REPAINT IS A REQUEST THE BRIDGE SPENDS, and this is the ASK, so a
//--- caller outside the strip never calls `DrawStripPaint()` itself (that is a paint
//--- from inside somebody else's route — P-PAL-19f's own lesson). One flag, one spender.
void DrawStripPalRepaintAsk() { s_dsPalRepaint = true; }

// ═══════════════════════════════════════════════════════════════════════════
// P-PAL-20 (2026-10-02) — THE SURFACE LEDGER. THE DISMISSAL HAD NO NAME FOR THE POPUP.
//
// The report was «یک رنگ انتخاب می‌کنم کل استریپ بسته می‌شه», and the path is one line
// long. A colour pick is a release on TWO channels: `HandleUIChartEvent` serves the
// palette's swatch first (it runs before the strip in OnChartEvent), then the strip's
// router asks `DrawStripPointInside` about the release PIXEL — the pixel is on the
// popup, not on the strip — reads false, and calls `DrawStripClose()` (Router:1113).
// The colour did apply; the strip was eaten by the frame that did it.
//
// WHY IT IS A LEDGER AND NOT ONE MORE CLAUSE: `DrawStripPointInside` already grew one
// clause per popup — the gear panel (P-DRAW-32), the colour board (P-DRAW-48) — and the
// colour board is gone (P-PAL-19): its popup now lives in the panels, in a module the
// strip cannot see and must not know. So the clause list did not get long, it got
// WRONG, and the next popup would have broken it the same way. The strip's real rule
// was never «the plate and two special cases»: it is «a pixel on ANY surface the strip
// owns is not a click on the chart». One registry answers that, it grows without a
// branch, and it is fed by the ONE place that can see both sides (the entry's bridge).
//
// The entries are republished WHOLE every event by that single writer, so the ledger
// can never hold a rectangle of a popup that is already gone — the failure mode of a
// list written once and patched at each open.
// ═══════════════════════════════════════════════════════════════════════════
#define DSTRIP_SURF_MAX 4                 // two popups today; four is the ceiling, not a plan
static int s_dsSurfN = 0;
static int s_dsSurfX[DSTRIP_SURF_MAX], s_dsSurfY[DSTRIP_SURF_MAX];
static int s_dsSurfW[DSTRIP_SURF_MAX], s_dsSurfH[DSTRIP_SURF_MAX];

//--- the one writer's reset: called by the bridge on EVERY event, before it republishes.
void DrawStripSurfaceClear() { s_dsSurfN = 0; }
//--- append one owned surface. A zero-sized rect is not a surface (P-DRAW-32's own
//--- `s_dsGearW0 > 0` test): publishing a collapsed popup would claim nothing and
//--- would still cost the ledger a slot.
void DrawStripSurfacePublish(const int x, const int y, const int w, const int h)
{
   if(s_dsSurfN >= DSTRIP_SURF_MAX) return;
   if(w <= 0 || h <= 0) return;
   s_dsSurfX[s_dsSurfN] = x; s_dsSurfY[s_dsSurfN] = y;
   s_dsSurfW[s_dsSurfN] = w; s_dsSurfH[s_dsSurfN] = h;
   s_dsSurfN++;
}
bool DrawStripSurfaceAt(const int mx, const int my)
{
   int m = DSTRIP_SKIN_M + 2;   // the skin's fringe is plate, not chart (P-DRAW-29)
   for(int i = 0; i < s_dsSurfN; i++)
      if(mx >= s_dsSurfX[i] - m && mx <= s_dsSurfX[i] + s_dsSurfW[i] + m &&
         my >= s_dsSurfY[i] - m && my <= s_dsSurfY[i] + s_dsSurfH[i] + m) return true;
   return false;
}

void DrawStripPublishRect()
{
   if(!s_dsOpen || s_dsW <= 0 || s_dsH <= 0)
   {
      g_UIStripRX = -1; g_UIStripRY = -1; g_UIStripRW = 0; g_UIStripRH = 0;
      return;
   }
   int x1 = s_dsX - DSTRIP_SKIN_M;
   int y1 = s_dsY - DSTRIP_SKIN_M;
   int x2 = s_dsX + s_dsW + DSTRIP_SKIN_M;
   int y2 = s_dsY + s_dsH + DSTRIP_SKIN_M;
   if(s_dsGear != 0 && s_dsGearW0 > 0 && s_dsGearH > 0)
   {
      if(s_dsGEX - DSTRIP_SKIN_M < x1) x1 = s_dsGEX - DSTRIP_SKIN_M;
      if(s_dsGEY - DSTRIP_SKIN_M < y1) y1 = s_dsGEY - DSTRIP_SKIN_M;
      if(s_dsGEX + s_dsGearW0 + DSTRIP_SKIN_M > x2) x2 = s_dsGEX + s_dsGearW0 + DSTRIP_SKIN_M;
      if(s_dsGEY + s_dsGearH + DSTRIP_SKIN_M > y2) y2 = s_dsGEY + s_dsGearH + DSTRIP_SKIN_M;
   }
   //--- P-DRAW-48: the COLOUR BOARD is occupancy too — a card placed by the
   //--- neighbours must clear it, and a fresh board must clear them.
   if(DrawStripIsColorSlot(s_dsPicker) && s_dsBW > 0 && s_dsBH > 0)
   {
      if(s_dsBX - DSTRIP_SKIN_M < x1) x1 = s_dsBX - DSTRIP_SKIN_M;
      if(s_dsBY - DSTRIP_SKIN_M < y1) y1 = s_dsBY - DSTRIP_SKIN_M;
      if(s_dsBX + s_dsBW + DSTRIP_SKIN_M > x2) x2 = s_dsBX + s_dsBW + DSTRIP_SKIN_M;
      if(s_dsBY + s_dsBH + DSTRIP_SKIN_M > y2) y2 = s_dsBY + s_dsBH + DSTRIP_SKIN_M;
   }
   g_UIStripRX = x1;
   g_UIStripRY = y1;
   g_UIStripRW = x2 - x1;
   g_UIStripRH = y2 - y1;
}
//--- P-UI-113c (2026-09-23): THE OPENING PRESS'S OWN CLICK-FAMILY WINDOW. The hold
//--- fires while the button is STILL DOWN, so the release that ends it lands on the
//--- drawing = outside the strip, and the TV-style dismissal would close what the
//--- hold just opened («چرا با رها کردن هولد استریپ هم بسته میشه»). A one-shot flag
//--- cannot fix it: ONE release is reported on more than one channel (the chart's
//--- own CHARTEVENT_CLICK and the object's OBJECT_CLICK), so a shot spends the
//--- first while the second dismisses the strip the user was just shown. So it is a
//--- WINDOW, re-armed by the press's own witnesses: ARM at the fire for the
//--- press's whole life, the MOVE STREAM's release witness shortens it to the
//--- twin-event tail, a new press edge (or a close) ends it.
#define DSTRIP_OPEN_TAIL_MS      800     // twin-event tail after the release witness
#define DSTRIP_OPEN_PRESS_MAX_MS 10000   // the longest a press may claim its own clicks
static uint s_dsOpenerUntil = 0;         // 0 = disarmed; else the press's own deadline
static uint s_dsOpenerTailUntil = 0;     // the twin-event tail (after the release witness)
void DrawStripOpenerArm()    { s_dsOpenerUntil = GetTickCount() + DSTRIP_OPEN_PRESS_MAX_MS; s_dsOpenerTailUntil = 0; }
void DrawStripOpenerDisarm() { s_dsOpenerUntil = 0; s_dsOpenerTailUntil = 0; }
bool DrawStripOpenerClickSpent() { return (TickDeadlinePending(s_dsOpenerUntil) || TickDeadlinePending(s_dsOpenerTailUntil)); }
//--- P-UI-113g (2026-09-24): SELECTION IS REPAIRED AFTER MT4'S CLICK, NOT INSIDE
//--- THE CLICK CALLBACK. P-UI-113f selected the hold target both at the fire and
//--- on the release event, but MT4 commits the terminal's own press/release
//--- selection state after this callback returns. Its last step therefore cleared
//--- the eight handles/context toolbar that the release had just restored. The
//--- repair belongs to the already-running tick/timer pump: one bounded wait past
//--- the event, guarded writes only, and a new press or a close cancels it so the
//--- user's next gesture always wins.
//--- The name is explicit because a same-object CHART_CHANGE/OBJECT_DRAG ride
//--- rebuilds the strip through DrawStripClose; OpenAt snapshots and restores this
//--- repair exactly as it restores the opening-press window.
#define DSTRIP_SELECT_REPAIR_DELAY_MS 120   // let MT4 finish the release callback first
#define DSTRIP_SELECT_REPAIR_TTL_MS   1800  // bounded proof window, not a selection lock
static string s_dsSelectRepairName = "";
static uint   s_dsSelectRepairAt = 0;      // first post-event repair is legal here
static uint   s_dsSelectRepairUntil = 0;   // 0 = no repair pending
void DrawStripHoldSelectionDisarm()
{
   s_dsSelectRepairName = "";
   s_dsSelectRepairAt = 0;
   s_dsSelectRepairUntil = 0;
}
//--- P-DRAW-17: the left button's press latch, and the ONE owner of the press
//--- edge fact (`s_dsLeftPress`). The trigger needs it (a click, not a drag) and
//--- the grip carry needs it (start a carry on the press) - so the edge is
//--- computed ONCE, in the router head, which runs on EVERY move whether the
//--- strip is open or not. Two owners of "the button just went down" is how the
//--- carry and the trigger would drift apart.
//--- P-UI-113b (2026-09-23): and the head STORES it (`s_dsLeftPrev = tleft`) -
//--- without that one line the "edge" is just the button state, re-read as a
//--- fresh press by every move of a held hand (see the head's own note). The
//--- button-up channels resync it, so an off-window release cannot stick it DOWN.
static bool     s_dsLeftPrev = false;
static bool     s_dsLeftPress = false;   // true on the move that carried the press edge
static int      s_dsPressX = 0, s_dsPressY = 0;
static string   s_dsPressObj = "";       // P-UI-113i: the drawing named by that press
static int      s_dsTravel = 0;          // furthest the LEFT hand got while held
static bool     s_dsPressTracked = false;   // P-UI-113d: a press EDGE was seen for this
                                            // cycle, so `s_dsTravel` is this gesture's
                                            // (a zero-move press leaves no edge: the
                                            // release then reads as a click, never a drag)
//--- P-UI-113j (2026-09-25) — THE PRESS NAMES ITS OWN DRAWING. `s_dsPressObj`
//--- above exists only when the MOVE STREAM carried the press edge: a still press
//--- carries none (P-LM-13). The release then fell back to a live hit test, and
//--- MT4's selected controls are terminal UI - their handles are accepted only
//--- while the object IS selected (P-UI-113h), which the terminal clears around
//--- its own click. Reported: hold a SELECTED drawing, the strip opens, and the
//--- release closes it - while the same gesture works on an unselected one.
//--- So the latch - which hit-tests the press pixel anyway - KEEPS its answer for
//--- the whole press cycle: one hit test per press (P-DRAW-04), selection-free.
static bool     s_dsPressCycle = false;  // the latch named THIS press cycle
static string   s_dsPressCycleObj = "";  // the drawing its press pixel landed on ("" = chart)
static uint     s_dsPressCycleMs = 0;    // the cycle's life bound: the press cap below
//--- P-UI-130 (2026-10-02) — THE CYCLE'S LIFE IS THE PRESS'S, NOT THE OPENER'S.
//--- P-UI-115 armed this cycle and left its life bound at `DSTRIP_OPEN_PRESS_MAX_MS`
//--- — the OPENER WINDOW's own budget, ten seconds — and the live chart says what
//--- a ten-second refusal window costs. One latch on a box the hand was about to
//--- DRAG walked out from under the finger, the drag's release never arrived on
//--- the click channel, and the cycle went on to refuse FIVE real presses in a row
//--- (EURUSD,M1 00:12:57.036 latch -> :57.473 refused -> :57.931, :58.451,
//--- :58.939, 00:13:00.370, 00:13:01.481 all refused -> the user gave up until
//--- 00:14:41). That is «هولد بعضی وقتها باز نمیشه» exactly, and no line of the
//--- log named the owner until DIAG-116 printed `press refused: cycle live`.
//--- The cycle has ONE job — keep a FLAP from re-timing a press it already named
//--- (P-UI-115c) — and the flaps it was measured against are milliseconds apart
//--- (179/252/488 ms). 2 s covers every press that can still become a hold (a hold
//--- fires at 500 ms) and can never outlive its press far enough to eat the next
//--- one. A gesture already IN MOTION is guarded by its own witness instead: the
//--- router's drag heartbeat (P-UI-130 in DrawStrip_Router.mqh).
#define DSTRIP_PRESS_CYCLE_MS 2000
void DrawStripPressCycleSet(const string nm)
{ s_dsPressCycle = true; s_dsPressCycleObj = nm; s_dsPressCycleMs = GetTickCount() + DSTRIP_PRESS_CYCLE_MS; }
void DrawStripPressCycleClear() { s_dsPressCycle = false; s_dsPressCycleObj = ""; s_dsPressCycleMs = 0; }
bool DrawStripPressCycleLive()
{ return (s_dsPressCycle && TickDeadlinePending(s_dsPressCycleMs)); }
//--- P-UI-114 (2026-09-23) — dead right-click era deleted (user order:
//--- extra code out, compile back down). The strip opens on a LEFT hold now.

//--- P-DRAW-13: single-step undo — the pre-mutation looks of the group (names +
//--- packed slots), the held drawing's level set, and a duplicate's copy name.
//--- Trash is not undoable (MT4 has no undelete); undo covers looks only.
static bool     s_duValid = false;
static int      s_duN = 0;
static string   s_duName[DSTRIP_UNDO_MAX];
static color    s_duClr[DSTRIP_UNDO_MAX];
static int      s_duW[DSTRIP_UNDO_MAX], s_duSt[DSTRIP_UNDO_MAX];
static int      s_duFill[DSTRIP_UNDO_MAX], s_duRay[DSTRIP_UNDO_MAX];
static color    s_duFillClr[DSTRIP_UNDO_MAX];    // P-DRAW-64: the interior's colour
static int      s_duFillOp[DSTRIP_UNDO_MAX];     // and its own tone
static int      s_duFont[DSTRIP_UNDO_MAX], s_duGlyph[DSTRIP_UNDO_MAX], s_duBack[DSTRIP_UNDO_MAX];
static color    s_duBodyClr[DSTRIP_UNDO_MAX];   // P-DRAW-BODY-UI: undo restores the handle too
static int      s_duBodyW[DSTRIP_UNDO_MAX], s_duBodySt[DSTRIP_UNDO_MAX];
static int      s_duLvN = 0;
static double   s_duLvV[DSTRIP_UNDO_LV];
static color    s_duLvC[DSTRIP_UNDO_LV];
static int      s_duLvW[DSTRIP_UNDO_LV], s_duLvS[DSTRIP_UNDO_LV];
static string   s_duLvT[DSTRIP_UNDO_LV];   // P-LVL-TEXT: one level's own note
//--- P-LVL-TEXT (2026-10-04) — ONE LEVEL'S NOTE, ARMED. The label zone of a level
//--- row arms the e4 field on that STORED level; Enter commits LEVELTEXT.
//--- Disarmed by the commit and by GearClose (strip close rides it).
static bool     s_dsLvlDescArmed = false;
static string   s_dsLvlDescObj = "";
static int      s_dsLvlDescIdx = -1;
bool DrawStripLvlDescWant()
{
   if(!s_dsLvlDescArmed || s_dsLvlDescObj == "" || s_dsLvlDescObj != s_dsObj) return false;
   if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) return false;
   if(s_dsLvlDescIdx < 0 || s_dsLvlDescIdx >= DrawLevelCount(s_dsObj)) return false;
   return true;
}
static string   s_duCopy = "";

string DrawStripObjName(const int i)  { return "PnlDrawS_" + IntegerToString(i); }
string DrawStripIconName(const int i) { return "PnlDrawS_" + IntegerToString(i) + "I"; }
//--- the shell chrome: grip (drag), badge (kind xN, info only), actions.
string DrawStripGripName() { return "PnlDrawS_H"; }
string DrawStripGripIconName() { return "PnlDrawS_HI"; }
string DrawStripBadgeName() { return "PnlDrawS_B"; }
string DrawStripActName(const int a) { return "PnlDrawS_A" + IntegerToString(a); }
string DrawStripActIconName(const int a) { return "PnlDrawS_A" + IntegerToString(a) + "I"; }
//--- the popover's rows (P = button, PI = icon face, PT = left-aligned label).
string DrawStripPickName(const int r) { return "PnlDrawS_P" + IntegerToString(r); }
string DrawStripPickIconName(const int r) { return "PnlDrawS_P" + IntegerToString(r) + "I"; }
string DrawStripPickLabelName(const int r) { return "PnlDrawS_P" + IntegerToString(r) + "T"; }
string DrawStripPickChipName(const int r) { return DrawStripPickIconName(r) + "C"; }
string DrawStripPickRailName(const int r) { return DrawStripPickName(r) + "R"; }
//--- P-DRAW-33: the colour surfaces' glass sheen — one face per colour cell, so a
//--- tap on the sheen is a tap on the cell (the `+ "C"` chip pattern, one letter up).
string DrawStripPickGlassName(const int r) { return DrawStripPickName(r) + "G"; }
string DrawStripGridGlassName(const int g) { return DrawStripGridName(g) + "G"; }
//--- TV parity board (2026-09-26): the popover's own chrome — grip seat, the
//--- RECENT band's own cells (the grid is the user's 64 only) and the HEX field.
string DrawStripPHeadGName() { return "PnlDrawS_PHeadG"; }
string DrawStripPHeadGChipName() { return "PnlDrawS_PHeadGC"; }
string DrawStripPHeadGIconName() { return "PnlDrawS_PHeadGI"; }
//--- P-DRAW-92 (2026-09-30) — THE BOARD'S PAGE SEATS, NAMED LIKE EVERY OTHER
//--- BOARD OBJECT. They were spelled inline in the paint (`"PnlDrawS_Page" +
//--- IntegerToString(k)`) — P-PAL-21: the board's chrome prune went with the board.
//--- the board's chrome down (DrawStrip_GearA.mqh) — never listed them: close the
//--- board, or switch a colour slot to a width/style list, and the two `<` `>` seats
//--- and the "1/2" caption stayed floating over the strip. Found by
//--- `node tools/object_lifecycle_check.js` once its helper table went tree-wide:
//--- `DrawStripBtn paints PnlDrawS_Page…"PnlDrawS_Page" — no destroy path`.
string DrawStripPageSeatName(const int k)  { return "PnlDrawS_Page" + IntegerToString(k); }
string DrawStripPageLabelName()            { return "PnlDrawS_PageT"; }
string DrawStripPRecName(const int i) { return "PnlDrawS_PR" + IntegerToString(i); }
string DrawStripPRecGlassName(const int i) { return DrawStripPRecName(i) + "G"; }
string DrawStripPRecLabelName() { return "PnlDrawS_PRecT"; }
//--- P-PAL-14: the well an EMPTY recent slot wears. A seat of its own, because the
//--- slot is a state the trader can see, not an absence.
string DrawStripPRecEmptyName(const int i) { return DrawStripPRecName(i) + "E"; }
string DrawStripPHexLbName() { return "PnlDrawS_PHexLb"; }
string DrawStripPHexEdName() { return "PnlDrawS_PHexEd"; }
//--- P-DRAW-48: the OPACITY band's own five objects (Lb = its label, T = the bed,
//--- F = the filled part, K = the knob, V = the `NN%` readout).
string DrawStripPOpLbName()    { return "PnlDrawS_POpLb"; }
string DrawStripPOpBedName()   { return "PnlDrawS_POpT"; }
string DrawStripPOpFillName()  { return "PnlDrawS_POpF"; }
string DrawStripPOpKnobName()  { return "PnlDrawS_POpK"; }
string DrawStripPOpValName()   { return "PnlDrawS_POpV"; }
//--- the gear panel: tabs (GT), grid cells (GG/GGI), list rows (GR/GRI/GRT),
//--- foot (GF), edits (GE).
string DrawStripGridName(const int g) { return "PnlDrawS_GG" + IntegerToString(g); }
string DrawStripGridIconName(const int g) { return "PnlDrawS_GG" + IntegerToString(g) + "I"; }
string DrawStripRowName(const int r) { return "PnlDrawS_GR" + IntegerToString(r); }
string DrawStripRowIconName(const int r) { return "PnlDrawS_GR" + IntegerToString(r) + "I"; }
string DrawStripRowLabelName(const int r) { return "PnlDrawS_GR" + IntegerToString(r) + "T"; }
string DrawStripRowChipName(const int r) { return DrawStripRowIconName(r) + "C"; }
string DrawStripRowRailName(const int r) { return DrawStripRowName(r) + "R"; }
string DrawStripRowStateName(const int r) { return DrawStripRowName(r) + "S"; }
string DrawStripRowSepName(const int r) { return DrawStripRowName(r) + "L"; }
//--- P-DRAW-117: the group row's VALUE DIGEST — a member of the row family (the
//--- row's own `D`), because it is drawn in the row's own cell and dies with it.
string DrawStripRowDigestName(const int r) { return DrawStripRowName(r) + "D"; }
string DrawStripFootName(const int f) { return "PnlDrawS_GF" + IntegerToString(f); }
string DrawStripFootSkinName(const int f) { return DrawStripFootName(f) + "B"; }
string DrawStripFootGlyphName(const int f) { return DrawStripFootName(f) + "G"; }
string DrawStripFootLabelName(const int f) { return DrawStripFootName(f) + "T"; }
string DrawStripEditName(const int e) { return "PnlDrawS_GE" + IntegerToString(e); }
string DrawStripBgName() { return "PnlDrawS_BG"; }
string DrawStripBoardBgName() { return "PnlDrawS_BBG"; }   // P-DRAW-48: the board's own plate bg
//--- P-DRAW-32: the SETTINGS PANEL's own plate — its own family, so the two
//--- surfaces paint, purge and answer a tap apart (`DrawStripIsBg` matches both).
string DrawStripGearBgName() { return "PnlDrawS_GBG"; }
//--- P-DRAW-117 (2026-10-01) — `DrawStripGearTabName` / `DrawStripGearTabLineName`
//--- / `DrawStripGearTrackName` are RETIRED with the tab row. The panel's nav is a
//--- column of group ROWS now, so it rides the row family (`DrawStripRowName`) and
//--- the three retired spellings survive only where they must: as the ORPHAN SWEEP
//--- in `DrawStripGearObjectsPurge` (a chart painted by the tab build), which deletes
//--- them by literal name (GearA). Naming a retired object from a helper here would be
//--- a name no paint can produce and no reader can need.
string DrawStripGearHeadName(const string s) { return "PnlDrawS_GH" + s; }
string DrawStripGearSectionName(const int i) { return "PnlDrawS_GS" + IntegerToString(i); }
string DrawStripGearSectionLineName(const int i) { return DrawStripGearSectionName(i) + "L"; }
//--- P-DRAW-125 (2026-10-01) — "CREATE OR REWRITE?" MUST ASK THE TYPE, NOT THE NAME.
//--- Every writer decided that question from `ObjectFind(0, nm) < 0` alone, and the
//--- tree's own record names the consequence (DrawStripSweepStale, GearA): "a name
//--- that is already there IS reused — with whatever TYPE the older build created it,
//--- and MT4 draws a button's text onto a bitmap label by writing properties nobody
//--- reads: an object that exists, answers ObjectFind, and paints NOTHING." The
//--- prefix wipe at attach cannot reach a name a MID-SESSION path left mis-typed (a
//--- cell that changed role, a family half rebuilt, an orphan of the retired tab
//--- build), so the reader lives here, where every writer can reach it: the object's
//--- OWN type against the type the painter needs. A foreign name is dropped, and the
//--- writer's own create — kept IN the writer, so the lifecycle gate still sees the
//--- birth and the layer write in one block — rebuilds it. Bounded: one extra type
//--- read per object per paint, and a reclaim happens at most once per name.
void DrawStripForeign(const string nm, const int type)
{
   if(ObjectFind(0, nm) < 0) return;
   if((int)ObjectGetInteger(0, nm, OBJPROP_TYPE) == type) return;
   static bool saidType = false;
   if(!saidType)
   {
      saidType = true;
      Print("[drawstrip] object of another type reclaimed obj=", nm,
            " type=", (int)ObjectGetInteger(0, nm, OBJPROP_TYPE), " want=", type);
   }
   ObjectDelete(0, nm);
}
string DrawStripGearCloseName() { return DrawStripGearHeadName("X"); }
string DrawStripGearCloseSkinName() { return DrawStripGearCloseName() + "B"; }
string DrawStripGearCloseIconName() { return DrawStripGearCloseName() + "I"; }
int    DrawStripGearX() { return s_dsGEX; }   // P-DRAW-32: the panel's own origin
//--- P-DRAW-73: `DrawStripGearCW()` is retired here — 1 hit in the tree (its own
//--- definition) since birth, and the head painter's write to `s_dsGearW` made it
//--- answer 312 where the layout means 280. The paint asks `DSTRIP_GEAR_W - 2*PAD`
//--- (narrow) or `s_dsGearW0 - 2*PAD` (the plate) directly, one line each.
//--- P-DRAW-19 (2026-09-24) — DOES THE CARRY OWN THE VIEW?
//--- The grip carry takes the project's ONE view lock (P-UI-113d:
//--- `ChartViewLockAcquire` at the press edge, `ChartViewLockAssert` on every held
//--- step, `DrawStripGripRelease` at every end). The 250 ms watchdog that rebuilds
//--- that lock from OWNERSHIP intent (`ChartScrollReconcile` -> `ChartLockIntended`,
//--- BiotakPanels.mqh - included AFTER this module, so this accessor is DEFINED
//--- before its ONE reader) must be able to NAME it: without the term the reconcile
//--- reads the carry's lock as a LEAK, hard-releases it inside the first 250 ms of
//--- the gesture and hands the scroll back under the hand - the report this answers
//--- («هنوز هنگام درگ چارت پشتش قفل نمیشه»). P-LM-11/P-BK-62's law, worn here
//--- unchanged: a gesture that takes the view lock names itself in that list the day
//--- it is born. ONE reader, so the answer cannot drift from the lock it explains.
//--- P-DRAW-32: the SETTINGS PANEL's carry takes it too (its header bar is its
//--- handle), so BOTH latches are named here — one reader, two owners. P-DRAW-48:
//--- the OPACITY BAR's own drag, the fourth, added the day it was born (A-09/G-07).
bool   DrawStripViewOwned() { return (s_dsGripLive || s_dsGGripLive || s_dsBGripLive || s_dsOpGrab || s_dsPalGrab); }
//--- P-DRAW-09b: how many drawings this strip is editing (1 = the held one).

//--- P-DRAW-08c: is this point ON the strip? Two gaps came from not asking:
//---   * a button tap also arrives as a chart CLICK on some builds, and the
//---     dismissal branch below ate the strip in the same event that used it;
//---   * a press that lands on the strip must never be read as a press on the
//---     drawing underneath it (the hold's own hit test starts with this).
//--- The size is the one the OPEN measured (`s_dsW`/`s_dsH`), never re-derived
//--- here: this question is asked on the press edge, where a kind lookup would be
//--- work for an answer already in hand.
bool DrawStripPointInside(const int mx, const int my)
{
   if(!s_dsOpen) return false;
   //--- P-DRAW-29: the skin stands DSTRIP_SKIN_M past the content on every
   //--- side — its fringe is plate, not chart.
   int m = DSTRIP_SKIN_M + 2;
   if(s_dsW > 0 && s_dsH > 0 &&
      mx >= s_dsX - m && mx <= s_dsX + s_dsW + m &&
      my >= s_dsY - m && my <= s_dsY + s_dsH + m) return true;
   //--- P-DRAW-32: the SETTINGS PANEL is our surface too. A tap on its plate is
   //--- not a tap on the chart, so it must never dismiss the strip that owns it
   //--- (the panel is where the user was just working).
   if(s_dsGear != 0 && s_dsGearW0 > 0 && s_dsGearH > 0 &&
      mx >= s_dsGEX - m && mx <= s_dsGEX + s_dsGearW0 + m &&
      my >= s_dsGEY - m && my <= s_dsGEY + s_dsGearH + m) return true;
   //--- P-DRAW-48: the COLOUR BOARD is our surface too — it can float anywhere,
   //--- including over the chart, and a click on its plate is not a click on the
   //--- chart (it would dismiss the very strip the board belongs to).
   if(DrawStripIsColorSlot(s_dsPicker) && s_dsBW > 0 && s_dsBH > 0 &&
      mx >= s_dsBX - m && mx <= s_dsBX + s_dsBW + m &&
      my >= s_dsBY - m && my <= s_dsBY + s_dsBH + m) return true;
   //--- P-PAL-20: AND WHATEVER ELSE THIS STRIP OWNS — the popups the entry's bridge
   //--- republished this event (the cards' palette, opened by a colour cell). Same
   //--- law as the two clauses above, one registry instead of one branch per popup.
   if(DrawStripSurfaceAt(mx, my)) return true;
   return false;
}

// ═══════════════════════════════════════════════════════════════════════════
// P-DRAW-84 (2026-09-29) — THE PANEL'S BUTTONS ARE DEAD, AND THE REASON IS ONE
// FLAG, NOT TWELVE BUGS.
//
// Every painter in this file is born `OBJPROP_SELECTABLE = false`
// (DrawStripBtnZ:3317, DrawStripFaceZ:3366, DrawStripLblAt:3413,
// DrawStripRect:3444), and that is CORRECT for this project: the indicator owns
// all input, and the strip opens by a coordinate hit test (DrawStripOpenAt),
// not by a click on an object. But the gear panel's ROUTER is a NAME router:
// every branch of the CHARTEVENT_OBJECT_CLICK chain at 7408-7433 compares
// `sparam` against a control's own object name — DrawStripRowName(r),
// DrawStripFootName(f), the retired DrawStripGearTabName(t), and so on. MT4 never emits
// OBJECT_CLICK for a non-selectable object, so `sparam` can never BE one of
// those names: every tab, row, switch, grid chip and foot button was dead on a
// green compile. The cards work because BiotakPanels has P-UI-74's
// `PnlClickFallback(mouseX, mouseY)` — the COORDINATE channel gets first
// refusal, the name router only runs when no control acted. The panel had no
// such channel at all.
//
// This function IS that channel for the gear panel, and it is deliberately
// written to read the SAME seat arrays the paint writes (`s_dsGRY/Col`,
// `s_dsGGX/Y/W/H`, `s_dsGearFootY`, `s_dsGearEditX/W/Y`,
// `s_dsGEY`, `s_dsGEX`, `s_dsGearW0`) — never a re-derived number. A hit test
// with its own arithmetic is a second grid, which is P-DRAW-77's defect again.
//--- P-DRAW-117: and the group headers ride those same row arrays now — the tab
//--- row's own band and `s_dsGearTabX/W` seats are retired with it.
//
// Order is Z-order, topmost first, because the panel's controls overlap: the
// head's X sits over the plate, the tab underline over its tab, the grid chips
// over their row. Returns true when a control acted (the caller spends the
// event); false when the point is dead space, so the name router below can
// still have it.
// ═══════════════════════════════════════════════════════════════════════════
bool DrawStripGearHit(const int mx, const int my)
{
   if(!s_dsOpen || s_dsObj == "") return false;
   if(s_dsGear == 0 || s_dsGearW0 <= 0 || s_dsGearH <= 0) return false;
   if(mx < s_dsGEX || mx > s_dsGEX + s_dsGearW0) return false;
   if(my < s_dsGEY || my > s_dsGEY + s_dsGearH) return false;

   int gx = s_dsGEX, gy = s_dsGEY;
   int colW = DrawStripGearColW();
   int px = gx + DSTRIP_GEAR_PAD;

   // --- the head's own X, and the grip that carries the panel. Both live in the
   // head band, which is above everything below, so they are asked first. The X's
   // seat is the paint's own: `closeX = gx + W0 - PAD - 26`, at `hy + 17`, 26x26
   // (3913-3914) — the 26 is the cards' own XBTN and is written there twice, so it
   // is read here from the same expression rather than a third literal.
   //--- P-DRAW-103: AND THE HIT IS THE PAINTED SHAPE. This tested a CIRCLE of radius
   //--- `26/2 + 3` = 16 against a painted 26x26 SQUARE, so the square's own four
   //--- corners were dead: at the diagonal the circle ends 11.3px from the centre
   //--- while the corner sits 18.4px out, leaving a 3.7px dead triangle at each
   //--- corner of the one control that closes the panel. A thumb pad of 3px on every
   //--- side keeps the seam with the grip (P-DRAW-36 stops the carry 16px short of
   //--- the corner) untouched: the box now runs `cx0-3 .. cx0+29` and the carry ends
   //--- at `cx0-16`, so the 13px gap the design asked for is still there and the
   //--- circle's slack is spent on the corners that were missing.
   if(s_dsGearHeadY >= 0)
   {
      int hy = gy + s_dsGearHeadY;
      if(my >= hy && my < hy + DSTRIP_GEAR_HEAD_H)
      {
         const int xbtn = 26, xpad = 3;
         int cx0 = gx + s_dsGearW0 - DSTRIP_GEAR_PAD - xbtn;
         int cy0 = hy + 17;
         if(mx >= cx0 - xpad && mx < cx0 + xbtn + xpad &&
            my >= cy0 - xpad && my < cy0 + xbtn + xpad)
         { DrawStripGearClose(); return true; }
      }
      //--- P-DRAW-85: the head is ALSO the panel's carry. Outside the X, a press
      //--- on it drags the panel (DrawStripGearGripAt owns the exact seat); the
      //--- user could not move the panel at all before this.
      if(DrawStripGearGripAt(mx, my)) return false;   // the grip's own handler acts
   }

   // --- P-DRAW-117: THE GROUP HEADERS ARE NOT ASKED HERE. A group is a ROW now
   // (`DSTRIP_GRK_GROUP` in `s_dsGRKind`), so it answers through the row probe below
   // — the same seat array the paint writes, which is P-DRAW-84's own law: one hit
   // test, no second grid. The retired tab band's probe (a `ty` band over `s_dsGearTabsY`
   // and the `s_dsGearTabX/W` seats) went with the tab row it measured.

   // --- the hex / text fields: a press takes focus for typing, no action
   // (P-DRAW-48). The seat is the SAME `s_dsGearEditX/W/Y` the paint wrote.
   //--- P-DRAW-94 (2026-09-30): AND THE SAME COLUMN. `s_dsGearEditCol[e]` is what
   //--- the WIDE pass writes when it moves a field into the right column
   //--- (DrawStripGearShiftItems, GearA:474) and the paint adds the same
   //--- `* DSTRIP_GEAR_COL` (GearB:1009). This probe was the ONE reader that did
   //--- not: on a wide tab (a fibo's Levels, 10+ rows) the "add a level" field was
   //--- DRAWN at px + 312 + editX and probed at px + editX — so the field could not
   //--- be focused by clicking it, and a click in the empty left column at that row
   //--- focused a field 312px away. One term, read from the paint's own expression.
   //--- P-DRAW-98: AND THE PAINT'S OWN WIDTH, INCLUDING ITS FALLBACK. This probe
   //--- skipped a field whose `s_dsGearEditW` is 0, and the paint does not skip it:
   //--- `int ew = (s_dsGearEditW[e] > 0) ? s_dsGearEditW[e] : cw` (GearB) gives it
   //--- the WHOLE cell. Only the two Paint-tab hex fields ever set a width, so the
   //--- `add a level` (e1), the `Caption` (e2) and the `Template name` (e3) fields
   //--- were drawn as full-width text boxes that no click could ever reach — and
   //--- every painter here is `OBJPROP_SELECTABLE=false`, so the terminal could not
   //--- reach them either. On the two tabs the gate measures narrow (Look 312, Text
   //--- 312) that is every field but the two hex ones. The guard is now the paint's
   //--- own `s_dsGearEditY[e] >= 0` (which is exactly the paint's `want`), and the
   //--- width is the paint's own expression, term for term.
   for(int e = 0; e < 5; e++)
   {
      if(s_dsGearEditY[e] < 0) continue;
      int ew = (s_dsGearEditW[e] > 0) ? s_dsGearEditW[e] : DrawStripGearCellW();
      if(ew <= 0) continue;
      int ex = px + s_dsGearEditCol[e] * DSTRIP_GEAR_COL + s_dsGearEditX[e];
      int ey = gy + s_dsGearEditY[e] + (DSTRIP_GEAR_ROW_H - DSTRIP_GEAR_EDIT_H) / 2;
      if(mx >= ex && mx < ex + ew &&
         my >= ey && my < ey + DSTRIP_GEAR_EDIT_H)
      {
         if(ObjectFind(0, DrawStripEditName(e)) >= 0)
            ObjectSetInteger(0, DrawStripEditName(e), OBJPROP_STATE, true);
         //--- P-DRAW-118 (2026-10-01): the panel's two COLOUR fields (e0/e4) are gone
         //--- with their hex boxes, so no field here arms `s_dsHexFocus` any more —
         //--- that guard belongs to the BOARD's HEX field alone now (the router arms
         //--- it on the board's own name and `DrawStripPopHexEnd` releases it).
         return true;
      }
   }

   // --- the grid chips (Style tab's width / style / ray rows).
   for(int g = 0; g < s_dsGGN && g < DSTRIP_GRID_MAX; g++)
   {
      if(s_dsGGH[g] <= 0) continue;
      int cx = gx + s_dsGGX[g];
      int cy = gy + s_dsGGY[g] + (DSTRIP_GEAR_ROW_H - s_dsGGH[g]) / 2;
      if(mx >= cx && mx < cx + s_dsGGW[g] && my >= cy && my < cy + s_dsGGH[g])
      { DrawStripGridTap(g); return true; }
   }

   // --- the list rows. A row is a full-width CELL (P-DRAW-69: one tone, one
   // owner), so the whole band answers, not just its chip — the same contract
   // the cards' rows have.
   //--- P-DRAW-99: THE CELL IS ONE COLUMN, AND THIS PROBE WAS ASKING THE BOX. The
   //--- paint gives the row `DrawStripGearCellW()` (280) and this asked `colW` =
   //--- `DrawStripGearColW()` — the tab's whole content box, 592 on a 624 tab. The
   //--- gate measures Style and Row wide (624, 7 rows each, 10 and 12 blocks), so on
   //--- both the probe claimed 312px of bare plate to the right of every row in
   //--- column 0: a click on empty card toggled the switch that row names. The
   //--- foot below was already moved off `colW` by P-DRAW-90; the row was the
   //--- reader it did not reach.
   int rowW = DrawStripGearCellW();
   for(int r = 0; r < s_dsGRN && r < DSTRIP_GLIST_MAX; r++)
   {
      int ry = gy + s_dsGRY[r];
      if(my < ry || my >= ry + DSTRIP_GEAR_ROW_H) continue;
      int rx = px + s_dsGRCol[r] * DSTRIP_GEAR_COL;
      if(mx < rx || mx >= rx + rowW) continue;
      //--- P-LVL-COLOR: the level row's swatch (the paint's own chip seat below)
      //--- opens the palette on that stored level; the rest of the row toggles.
      //--- Same seat arrays the paint writes (s_dsGRY/s_dsGRCol) plus the paint's
      //--- own chip constants — no second grid.
      //--- P-LVL-TEXT: the LABEL zone arms the note field; the switch zone and
      //--- the row's padding keep the legacy toggle.
      if(s_dsGRKind[r] == 4)
      {
         int sx = rx + DSTRIP_GEAR_PAD, sy = ry + DSTRIP_CARD_CHIP_Y;
         if(mx >= sx && mx < sx + 22 && my >= sy && my < sy + 22)
         { DrawStripGearLevelColorTap(r); return true; }
         int lx = rx + DSTRIP_GEAR_PAD + 22 + 8;
         int wx = rx + rowW - 40;
         if(mx >= lx && mx < wx)
         { DrawStripGearLevelDescTap(r); return true; }
      }
      DrawStripGearRowTap(r);
      return true;
   }

   // --- the foot (All / Copy). The seats are the paint's own, read not re-derived
   // (4281-4283): the ghost face is `fx-8`, `fy-8`, `bw+16` x `44` around a 28px
   // button at `fy = footY + 10`. The hit box is the GHOST, not the button — a hand
   // aims at the plate it can see, and the ghost is 8px of it on every side.
   const int fpad = 8, fbtnH = 28, ftop = 10;
   int fy0 = gy + s_dsGearFootY;
   //--- P-DRAW-90: the width AND the seat are the paint's own owners now
   //--- (DrawStripFootBw / DrawStripFootX), read here, never re-derived: the old
   //--- `px + f*(bw+gap)` stood in this file and in DrawStripGearPaint at once,
   //--- and the moment `Reset` moves the pair to the right edge the two would
   //--- have disagreed on screen. `colW` is the same DrawStripGearColW() the
   //--- paint passes (280 on a 312 tab, 592 on a 624 one).
   for(int f = 0; f < DSTRIP_GEAR_FOOT_N; f++)
   {
      int bw = DrawStripFootBw(f);
      int fx = DrawStripFootX(f, px, colW);
      int fy = fy0 + ftop;
      if(mx >= fx - fpad && mx < fx + bw + fpad &&
         my >= fy - fpad && my < fy + fbtnH + fpad)
      { DrawStripFootTap(f); return true; }
   }

   return false;   // the plate's own dead space: never a tap
}

bool DrawStripClickFamily()
{
   UISuppressNextClick();
   return true;
}

//--- the slot -> capability map: the strip shows the kind's own controls, in the
//--- order this module declares them, each only where the kind really carries it. A
//--- slot the kind does not carry is SKIPPED, so the strip is never wider than it
//--- needs to be and never shows a control that would do nothing. DELETE lives in
//--- FireDelete (the strip owns it since the menu went); SAVE/ALL are not quick
//--- cells (they ride the more-popover and the gear foot, one tap further). The cap
//--- is EIGHT (P-DRAW-64 -> 64a): worst case DK_RECT = 8 cells + 4 chrome, ~616px,
//--- inside DSTRIP_SKIN_MAXW 660. Past the cap a slot rides the more-popover as an
//--- MK_SLOT row (P-DRAW-08i: a slot past the paint ceiling stays reachable).
void DrawStripVisInit()
{
   if(s_dsVisInit) return;
   s_dsVisInit = true;
   for(int k = 0; k < DK_COUNT; k++)
      for(int s = 0; s < DRAW_SLOT_N; s++) s_dsVis[k][s] = true;
}
bool DrawStripVis(const EDrawKind k, const int slot)
{
   DrawStripVisInit();
   if(k <= DK_NONE || k >= DK_COUNT) return false;
   int seat = (slot == DSTRIP_SLOT_LEVELS) ? DRAW_SLOT_MORE : slot;
   if(seat < 0 || seat >= DRAW_SLOT_N) return true;
   return s_dsVis[k][seat];
}
//--- P-DRAW-64a (2026-09-27) — ONE COLOUR SEAT FOR TWO ROLES. User order: «این
//--- دوتا باکس که برای یک کار هستش میشه باهم ادغام کرد ... میشه یکی بشه». A kind
//--- that carries the interior's colour too shows ONE colour cell whose RING is the
//--- BORDER's colour and whose CENTRE is the interior's (see the paint), so the seat
//--- is `DRAW_SLOT_FILLCLR` and `DRAW_SLOT_COLOR` is folded into it.
//--- P-DRAW-64a: and a KIND-level cap can be finer than it looks. DK_CHANNEL covers
//--- three MT4 types and two of them — the regression and the standard-deviation
//--- channel — have no interior of their own (`DrawTypeHasFillChild`), so the
//--- interior's COLOUR would be a silent no-op there: the seat is not shown at all
//--- (C-04). Asked ONLY for that one kind, so every other kind pays one compare and
//--- no terminal call; the two reads are the channel's own seat, on a repaint.
//--- (The box's own 50 % is NOT in this test: it moves the drawing's own anchor, so
//--- it works on every channel type.)
bool DrawStripSeatAvail(const EDrawKind k, const int slot)
{
   //--- P-UI-139: THE 50 % CELL IS THE PATH'S TOO — a polyline's own answer to it is
   //--- a small circle at each leg's middle. It CANNOT be a KIND rule: a kind rule
   //--- would hand the cell to every plain trendline, and a control nothing answers
   //--- is the one thing this strip refuses (C-04). So the answer is asked of the
   //--- HELD OBJECT, the same way the channel's fill child is asked below — and it is
   //--- asked BEFORE the caps gate, because DK_LINE's caps carry no 50 % bit (the
   //--- rectangle has its own, and this seat is now shared by two owners).
   if(k == DK_LINE && slot == DRAW_SLOT_BOXHALF)
   {
      if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) return false;
      return DrawIsPathSeg(s_dsObj);
   }
   if(!DrawSlotAvailable(k, slot)) return false;
   if(k != DK_CHANNEL) return true;
   if(slot != DRAW_SLOT_FILLCLR) return true;
   if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) return true;
   return DrawTypeHasFillChild(DrawObjectType(s_dsObj));
}
bool DrawStripMergedColor(const EDrawKind k)
{
   return (DrawStripSeatAvail(k, DRAW_SLOT_FILLCLR) && DrawSlotAvailable(k, DRAW_SLOT_COLOR));
}
//--- is a seat on the row? The merged colour seat is one seat for two roles, so it
//--- takes the WIDER of the two answers — a control the user asked to see is never
//--- silently dropped by a hide of the other role.
bool DrawStripSeatVis(const EDrawKind k, const int s, const bool merged)
{
   if(merged && s == DRAW_SLOT_FILLCLR)
      return (DrawStripVis(k, DRAW_SLOT_FILLCLR) || DrawStripVis(k, DRAW_SLOT_COLOR));
   return DrawStripVis(k, s);
}
//--- one ordered pass over everything the quick row COULD show (value slots +
//--- LEVELS); the quick cap and the overflow split read this, so the two can
//--- never disagree about order.
int DrawStripAllSlotAt(const EDrawKind k, const int shown)
{
   //--- The order is the module's own (index ascending), with ONE exception: the
   //--- FILL FAMILY reads together — FILL, then the two extras the user asked to
   //--- keep at hand (HALF · EXTEND) — so a box reads "filled · half · extends · …".
   bool merged = DrawStripMergedColor(k);
   //--- P-UI-139: THE 50 % CELL IS A QUICK-ROW CELL FOR A PATH. It is normally held
   //--- back from the walk and re-inserted right after FILL, because a box's fill and
   //--- its two extras read as one family ("filled · half · extends"). A PATH has no
   //--- fill, so that insertion point never arrives and the cell would exist in the
   //--- gear panel and in the writer while being INVISIBLE on the row the user is
   //--- looking at. So for a path the walk keeps the slot at its own index instead:
   //--- after colour/width/style/ray/lock/back, which is where a switch belongs.
   bool pathHalf = (k == DK_LINE && DrawStripSeatAvail(k, DRAW_SLOT_BOXHALF));
   int seen = 0;
   for(int s = 0; s < DRAW_SLOT_N; s++)
   {
      if(s == DRAW_SLOT_MORE) continue;   // no dialog to open from here
      if(merged && s == DRAW_SLOT_COLOR) continue;                 // folded into the colour seat
      if((s == DRAW_SLOT_BOXHALF || s == DRAW_SLOT_EXTEND) && !pathHalf) continue;  // served beside FILL
      if(!DrawStripSeatAvail(k, s)) continue;
      if(!DrawStripSeatVis(k, s, merged)) continue;
      if(seen == shown) return s;
      seen++;
      if(s == DRAW_SLOT_FILL && !pathHalf)
      {
         if(DrawStripSeatAvail(k, DRAW_SLOT_BOXHALF) && DrawStripVis(k, DRAW_SLOT_BOXHALF))
         {
            if(seen == shown) return DRAW_SLOT_BOXHALF;
            seen++;
         }
         if(DrawSlotAvailable(k, DRAW_SLOT_EXTEND) && DrawStripVis(k, DRAW_SLOT_EXTEND))
         {
            if(seen == shown) return DRAW_SLOT_EXTEND;
            seen++;
         }
      }
   }
   if(DrawKindHasLevels(k) && DrawStripVis(k, DSTRIP_SLOT_LEVELS))
   {
      if(seen == shown) return DSTRIP_SLOT_LEVELS;
      seen++;
   }
   return -1;
}
int DrawStripAllSlotCount(const EDrawKind k)
{
   int n = 0;
   while(DrawStripAllSlotAt(k, n) != -1 && n < DSTRIP_MAX_SLOTS + 4) n++;
   return n;
}
int DrawStripQuickSlotAt(const EDrawKind k, const int shown)
{
   if(shown < 0 || shown >= DSTRIP_QUICK_CAP) return -1;
   return DrawStripAllSlotAt(k, shown);
}
int DrawStripQuickCount(const EDrawKind k)
{
   int n = DrawStripAllSlotCount(k);
   if(n > DSTRIP_QUICK_CAP) n = DSTRIP_QUICK_CAP;
   return n;
}
int DrawStripOverflowSlotAt(const EDrawKind k, const int shown)
{
   if(shown < 0) return -1;
   return DrawStripAllSlotAt(k, DSTRIP_QUICK_CAP + shown);
}
int DrawStripOverflowCount(const EDrawKind k)
{
   int n = DrawStripAllSlotCount(k) - DSTRIP_QUICK_CAP;
   return (n > 0 ? n : 0);
}

// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-10 — THE ICON FACE.
// ══════════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-13 — EVERY QUICK CELL WEARS A RASTER (icon-only row). State carriers
// vary per value (width/style/ray — the P-DRAW-10 honesty rule); pure glyphs
// ride one raster and the gold face carries the state; the colour cell is a
// swatch (no raster, ""), its face IS the object's colour (P-DRAW-09c).
// ══════════════════════════════════════════════════════════════════════════
string DrawStripIconRes(const int slot, const string nm)
{
   //--- P-DRAW-64a: the colour seat wears no raster — its face IS the two colours it
   //--- edits (the border's ring and the interior's centre), which is the answer
   //--- DRAW_SLOT_COLOR always gave. The droplet that told the two cells apart went
   //--- with the merge; the seat is one cell now, so nothing needs telling apart.
   if(DrawStripIsColorSlot(slot)) return "";
   //--- P-DRAW-64a: the fill family's two extras. OFF is the plate ink, ON the
   //--- amber twin, so the ON cell stays quiet (one shape on the accent wash).
   if(slot == DRAW_SLOT_BOXHALF)
   {
      // P-UI-139/140 (2026-10-02, MEASURED: a tap meant for this cell landed on
      // `slot=9 Behind candles`, because a PATH wore the BOX's block art beside two
      // other block glyphs). The path answers with its OWN face — two legs with a
      // dot on each middle — so no hand has to guess which of three block icons is
      // the marker. One raster pair, the same 24 canvas, the same amber twin.
      if(DrawIsPathSeg(nm))
         return ((DrawSlotRead(nm, DRAW_SLOT_BOXHALF) > 0.5) ? "::Files\\Icons\\bk_mid_on.bmp"
                                                             : "::Files\\Icons\\bk_mid_off.bmp");
      return ((DrawSlotRead(nm, DRAW_SLOT_BOXHALF) > 0.5) ? "::Files\\Icons\\bk_half_on.bmp"
                                                          : "::Files\\Icons\\bk_half_off.bmp");
   }
   if(slot == DRAW_SLOT_EXTEND)
      return ((DrawSlotRead(nm, DRAW_SLOT_EXTEND) > 0.5) ? "::Files\\Icons\\bk_ext_on.bmp"
                                                         : "::Files\\Icons\\bk_ext_off.bmp");
   if(slot == DRAW_SLOT_WIDTH)
   {
      int w = (int)DrawSlotRead(nm, DRAW_SLOT_WIDTH);
      if(w < DRAW_WIDTH_MIN || w > DRAW_WIDTH_MAX) w = DRAW_WIDTH_MIN;
      return "::Files\\Icons\\bk_w" + IntegerToString(w) + ".bmp";
   }
   if(slot == DRAW_SLOT_STYLE)
   {
      int st = (int)DrawSlotRead(nm, DRAW_SLOT_STYLE);
      if(st < 0) st = 0;
      // P-LOOK: a look wears its native icon (no baked glyphs for looks).
      else if(st > 4) st = FibPenLookNative(st - 4);
      if(st < 0 || st > 4) st = 0;
      return "::Files\\Icons\\bk_style" + IntegerToString(st) + ".bmp";
   }
   //--- P-DRAW-BODY-UI: the handle's own width/style reuse the level family's
   //--- rasters (same seats, no new art) — read off the body's own slots, so the
   //--- two width cells can never show each other's value.
   if(slot == DRAW_SLOT_BODYWIDTH)
   {
      int bw = (int)DrawSlotRead(nm, DRAW_SLOT_BODYWIDTH);
      if(bw < DRAW_WIDTH_MIN || bw > DRAW_WIDTH_MAX) bw = DRAW_WIDTH_MIN;
      return "::Files\\Icons\\bk_w" + IntegerToString(bw) + ".bmp";
   }
   if(slot == DRAW_SLOT_BODYSTYLE)
   {
      int bs = (int)DrawSlotRead(nm, DRAW_SLOT_BODYSTYLE);
      if(bs < 0 || bs > 4) bs = 0;
      return "::Files\\Icons\\bk_style" + IntegerToString(bs) + ".bmp";
   }
   if(slot == DRAW_SLOT_RAY)
   {
      int r = (int)DrawSlotRead(nm, DRAW_SLOT_RAY);
      if(r < 0 || r > 3) r = 0;
      return "::Files\\Icons\\bk_ray" + IntegerToString(r) + ".bmp";
   }
   if(slot == DRAW_SLOT_FILL)
      return ((DrawSlotRead(nm, DRAW_SLOT_FILL) > 0.5) ? "::Files\\Icons\\bk_fill_on.bmp"
                                                       : "::Files\\Icons\\bk_bucket.bmp");
   //--- P-DRAW-47: the ON faces are the AMBER twins (`bk_*_on` / `bk_lock_on_g`).
   //--- Their dark-ink predecessors were drawn for a solid gold plate, while the
   //--- ON face here is a translucent WASH — measured, the dark art's own mean
   //--- luminance is ~12 against a wash whose premultiplied mean is (33,22,0), so
   //--- ON read as NO glyph at all. The preview's rule is accent ink on the wash.
   if(slot == DRAW_SLOT_LOCK)
      return ((DrawSlotRead(nm, DRAW_SLOT_LOCK) > 0.5) ? "::Files\\Icons\\bk_lock_on_g.bmp"
                                                       : "::Files\\Icons\\bk_lock_off.bmp");
   //--- P-UI-131 (2026-10-02): the BACK seat wears ONE shape in two inks, like every
   //--- other toggle in this row. It used to answer `gl_layers_m` when off (grey
   //--- chevrons, 26 px) and `bk_back_on` when on (amber overlapping rects, 24 px) —
   //--- two glyphs and two canvases for one control, which is why the live tap
   //--- («رنگ fill باکس رو خاموش و روشن میکنه») read as the wrong button even though
   //--- the witness proves the write was exact. `bk_back_off` is its own art in the
   //--- plate ink, baked by the generator beside `bk_back_on` (see gen-th3-icons.js).
   if(slot == DRAW_SLOT_BACK)
      return ((DrawSlotRead(nm, DRAW_SLOT_BACK) > 0.5) ? "::Files\\Icons\\bk_back_on.bmp"
                                                       : "::Files\\Icons\\bk_back_off.bmp");
   if(slot == DRAW_SLOT_FONT) return "::Files\\Icons\\gl_textsize_m.bmp";
   if(slot == DRAW_SLOT_GLYPH) return "::Files\\Icons\\bk_glyph.bmp";
   if(slot == DSTRIP_SLOT_LEVELS) return "::Files\\Icons\\bk_levels.bmp";
   return "";
}
//--- chrome faces: grip, badge has none (text label), actions by seat.
string DrawStripActRes(const int a)
{
   if(a == DSTRIP_ACT_MORE) return "::Files\\Icons\\bk_more.bmp";
   if(a == DSTRIP_ACT_GEAR) return "::Files\\Icons\\bk_gear.bmp";
   if(a == DSTRIP_ACT_PIN)
      return (s_dsPinned ? "::Files\\Icons\\gl_pin_gold.bmp" : "::Files\\Icons\\gl_pin_m.bmp");
   if(a == DSTRIP_ACT_DEL) return "::Files\\Icons\\bk_del.bmp";
   return "";
}

//--- MT4 paints a bitmap label at the file's NATIVE size from the label's own
//--- top-left corner, so centring the art is arithmetic — and the arithmetic
//--- needs the art's size. The families in this strip are fixed:
//---   every `bk_*` = 24, `gl_*` = 15 — and the four 26px `gl_*` glyphs, named
//---   in the table below.
//--- (Measured off the shipped files; a new family must be added here, which is
//--- what keeps a 24 px raster from hanging off a 30 px cell.)
//--- P-DRAW-106 (2026-10-01): AND THE `bk_w` / `bk_style` / `bk_ray` EXCEPTION IS
//--- RETIRED. It answered 16 for those three chips, but the shipped rasters are
//--- 24x24 with the glyph centred in its own canvas (measured on Files/Icons: all
//--- 32 `bk_*.bmp` the strip names are 24x24; `bk_w1.bmp`'s ink is 16 wide at
//--- x4..19 of a 24 canvas) — so `x + (cell - 16)/2` placed each chip's art 4px
//--- right and 4px down of its cell's centre, on the strip's width/style/ray cell
//--- and on the settings panel's Style chips alike. The FILE is what MT4 draws,
//--- so the file's canvas is what this table must answer.
int DrawStripIconPx(const string res)
{
   if(StringFind(res, "gl_") >= 0) return 15;
   if(StringFind(res, "bk_") >= 0) return 24;
   return 0;
}
int DrawStripResW(const string res)
{
   // P-UI-34: W-variants are 624px (wide panel header); narrow variants are 312px.
   if(StringFind(res, "pnl_topbarW") >= 0 || StringFind(res, "pnl_hairW") >= 0) return 624;
   if(StringFind(res, "pnl_topbar") >= 0 || StringFind(res, "pnl_hair") >= 0) return 312;
   if(StringFind(res, "pnl_mark") >= 0) return 44;
   if(StringFind(res, "dsg_btn") >= 0) return 80;
   if(StringFind(res, "pnl_sw_") >= 0) return 52;
    // P-UI-34 (2026-09-25): sheen sizes must be known for correct centring —
    // without an entry here DrawStripFaceZ gets pw=0 and places the art at the
    // cell's own centre instead of its corner. ICON-DIET 2026-09-27: the two
    // pnl_glass entries left with their bitmaps (see the #resource block).
    if(StringFind(res, "ds_cell32") >= 0) return 32;
    if(StringFind(res, "ds_ring32") >= 0) return 32;
    if(StringFind(res, "ds_swatch24") >= 0) return 24;
    if(StringFind(res, "pnl_chip") >= 0) return 26;
    if(StringFind(res, "pnl_rail") >= 0) return 4;
    if(StringFind(res, "pnl_vchip") >= 0) return 50;
    if(StringFind(res, "pnl_xbtn") >= 0) return 30;
   if(StringFind(res, "pnl_secdot") >= 0) return 14;   // P-DRAW-71: the cards' own section dot
   //--- P-DRAW-108 (2026-10-01) — AND THIS RULE WAS NEVER COMPILED. It stood on the
   //--- `secdot` line, AFTER that line's own `//` comment, so the MQL compiler read
   //--- the whole `if` as comment text: `DrawStripResW("::Files\\Icons\\pnl_cntchip.bmp")`
   //--- fell through to `DrawStripIconPx`'s 0 for a 28x20 canvas, and the section's
   //--- count pill — painted by DrawStripFaceZ in a rect `DSTRIP_SEC_CNT_W + 4` wide,
   //--- DrawStrip_GearB.mqh:842 — landed at `x + 28/2, y + 20/2`: 14px right and 10px
   //--- down of its own rect, with MT4 cropping the 24px art to what was left of it.
   //--- The gate missed it for the same reason: tools/check-resources.js split the
   //--- table on `;` and kept every `//` tail, so a commented-out rule was read as
   //--- LIVE and answered a right number by accident. A one-line statement is not a
   //--- one-line change — the rule owns its line now.
   if(StringFind(res, "pnl_cntchip") >= 0) return 28;  // ... and its count pill (24+2*2)
   if(StringFind(res, "pnl_subdot") >= 0) return 8;
   //--- P-DRAW-106 (2026-10-01) — THE FOOT'S OWN GHOST, WHICH THIS TABLE DID NOT
   //--- CARRY. `pnl_btn_ghost.bmp` is 88x44 (measured on the file) and had no
   //--- entry, so it fell through to `DrawStripIconPx`'s 0 — and `DrawStripFaceZ`
   //--- centres a raster in its cell as `x + (w - pw)/2`, which with `pw = 0` is
   //--- HALF THE CELL. The gear panel's foot asks for the ghost as
   //--- `(fx - 8, fy - 8, bw + 16, 44)`, i.e. the 72x28 button plus its 8px pad, so
   //--- the three plates shipped at `fx + 36, fy + 14`: 44px right of the button and
   //--- 22px below it — off the label each one belongs to, the last one 19px past the
   //--- card's right edge and all of them under the plate's bottom edge. One missing
   //--- number, three dead-looking foot buttons, and a green compile says nothing
   //--- (the size is a number in a chain of string tests, not a symbol).
   //--- The same audit measured `gl_pin*`, `gl_textsize*` and `gl_layers*`: 26x26
   //--- canvases inside a `gl_` family this table calls 15, so each of those arts
   //--- sat 5.5px right and down of its cell (the strip's pin cell and the FONT
   //--- chip are the two the panel paints).
   if(StringFind(res, "pnl_btn_ghost") >= 0) return 88;
   if(StringFind(res, "gl_pin") >= 0 || StringFind(res, "gl_textsize") >= 0 ||
      StringFind(res, "gl_layers") >= 0) return 26;
   return DrawStripIconPx(res);
}
int DrawStripResH(const string res)
{
   if(StringFind(res, "pnl_topbarW") >= 0) return 7;
   if(StringFind(res, "pnl_hairW") >= 0) return 5;
   if(StringFind(res, "pnl_topbar") >= 0) return 7;
   if(StringFind(res, "pnl_hair") >= 0) return 5;
   if(StringFind(res, "pnl_mark") >= 0) return 44;
   if(StringFind(res, "dsg_btn") >= 0) return 44;
   if(StringFind(res, "pnl_sw_") >= 0) return 34;
    // P-UI-34 (2026-09-25): glass sheen heights. ICON-DIET 2026-09-27: the
    // pnl_glass pair left with its bitmaps (see the #resource block).
    if(StringFind(res, "ds_cell32") >= 0) return 32;
    if(StringFind(res, "ds_ring32") >= 0) return 32;
    if(StringFind(res, "ds_swatch24") >= 0) return 24;
    if(StringFind(res, "pnl_chip") >= 0) return 26;
    if(StringFind(res, "pnl_rail") >= 0) return 42;
   if(StringFind(res, "pnl_vchip") >= 0) return 26;
   if(StringFind(res, "pnl_xbtn") >= 0) return 30;
   if(StringFind(res, "pnl_secdot") >= 0) return 14;
   if(StringFind(res, "pnl_cntchip") >= 0) return 20;
   if(StringFind(res, "pnl_subdot") >= 0) return 8;
   if(StringFind(res, "pnl_btn_ghost") >= 0) return 44;   // P-DRAW-106, see ResW
   if(StringFind(res, "gl_pin") >= 0 || StringFind(res, "gl_textsize") >= 0 ||
      StringFind(res, "gl_layers") >= 0) return 26;       // P-DRAW-106, see ResW
   return DrawStripIconPx(res);
}

//--- P-DRAW-09c — THE CELL'S TWO READING AIDS.
//
// 1. THE COLOUR CELL SHOWS A NAME A TRADER CAN READ. `ColorToString` says
//    `clrWhite` (a programming name) or `C'255,128,0'` (a compiler literal).
//    Neither is a caption: the first loses its spaces — `clrDodgerBlue` — and the
//    second is unreadable at a glance. So the MT4 names are un-CamelCased into
//    words («Dodger Blue») and anything else becomes the hex the rest of the
//    industry shows («#FF8000»), which is both modern and exact.
//
// 2. AND ITS INK CONTRASTS WITH THE SWATCH. The cell's face IS the object's
//    colour (that is what makes it a swatch), so the label sits on a colour the
//    user chose — and this project already paid for this lesson once (P-UI-69,
//    «رنگ ها کار نمیکنه»: an invisible control reads as a broken one). The maths
//    is WCAG's relative luminance, the same one `PnlLum` uses; it is local
//    because its owner (`BiotakPanels.mqh`) is included after this module.
// ══════════════════════════════════════════════════════════════════════════
double DrawStripLum(const color c)
{
   // `color` is UNSIGNED in MQL4, so `c < 0` is always false (warning 65): a
   // stray clrNONE only shows up once the value is seen as a signed int.
   int v = (int)c;
   if(v < 0) return 1.0;
   double r = (double)(v % 256) / 255.0;
   double g = (double)((v / 256) % 256) / 255.0;
   double b = (double)(v / 65536) / 255.0;
   if(r > 0.03928) r = MathPow((r + 0.055) / 1.055, 2.4); else r = r / 12.92;
   if(g > 0.03928) g = MathPow((g + 0.055) / 1.055, 2.4); else g = g / 12.92;
   if(b > 0.03928) b = MathPow((b + 0.055) / 1.055, 2.4); else b = b / 12.92;
   return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

color DrawStripInkOn(const color bg)
{
   // the threshold sits where the eye does: above it the face is light, so the
   // ink is the dark plate's own ink; below it, the light one. No colour is
   // rejected — the swatch keeps the user's exact colour either way.
   return (DrawStripLum(bg) > 0.45) ? DSTRIP_CLR_ACCENTT : DSTRIP_CLR_LABEL;
}

string DrawStripColorLabel(const color c)
{
   string s = ColorToString(c, false);
   if(StringFind(s, "clr") == 0)
   {
      s = StringSubstr(s, 3);
      string out = "";
      for(int i = 0; i < StringLen(s); i++)
      {
         // a capital that is not the first character starts a new word (a plain
         // character-code test: `StringToUpper(ch)` on a one-char string costs a
         // temporary and warns on some builds' implicit conversions)
         int code = StringGetCharacter(s, i);
         if(i > 0 && code >= 'A' && code <= 'Z') out += " ";
         out += StringSubstr(s, i, 1);
      }
      if(StringLen(out) > 10) out = StringSubstr(out, 0, 10);
      return out;
   }
   // `C'r,g,b'` -> `#RRGGBB`
   int nOpen = StringFind(s, "'");
   int nClose = StringFind(s, "'", nOpen + 1);
   if(nOpen >= 0 && nClose > nOpen)
   {
      string t = StringSubstr(s, nOpen + 1, nClose - nOpen - 1);
      int p1 = StringFind(t, ",");
      int p2 = StringFind(t, ",", p1 + 1);
      if(p1 > 0 && p2 > p1)
      {
         int r = (int)StringToInteger(StringSubstr(t, 0, p1));
         int g = (int)StringToInteger(StringSubstr(t, p1 + 1, p2 - p1 - 1));
         int b = (int)StringToInteger(StringSubstr(t, p2 + 1, StringLen(t) - p2 - 1));
         return StringFormat("#%02X%02X%02X", r, g, b);
      }
   }
   return "Color";   // P-UI-69d: ONE spelling in user-visible text (`Color`), like the one verb
}
#endif // DRAW_STRIP_BASE_MQH
