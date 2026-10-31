// BiotakPanels_PalSpec.mqh - split from BiotakPanels_PalA.mqh 2026-10-17 (P-SIZE-1500,
// contract item 7 "one file = one owner"): the DISPLAY-ROW SPEC owner - the spec
// table builder, the per-card spec gate, the band collapse and the palette
// kind-to-row map. Moved byte-identical, zero renames. The spec globals it reads
// are declared in PalA, so this include stays AFTER it; every CALLER sits later
// in the chain than either.
#ifndef BIOTAK_PANELS_PALSPEC_MQH
#define BIOTAK_PANELS_PALSPEC_MQH

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
   if(item == 0)   // TRIGGER ZONES (cyan) — 3 settings / 5 display rows
   {
      // P-UI-131j gave the card's SECOND surface its pair: TRANSPARENCY + COLOR own the
      // trigger ZONE; LABEL COLOR + LABEL OPACITY owned the pip label on the trigger
      // family's levels (addresses 2 and 4, APPENDED past 0..3 so every persisted OV_
      // key kept its meaning). P-LBL-12 (2026-10-17): the pip labels are retired, so
      // those two rows left the spec; the addresses and keys stay (MIDPOINT precedent).
      PnlSpecAdd(0, PNL_K_SEC, -1, 0, "", "", "ZONE APPEARANCE", 2);
      PnlSpecAdd(0, PNL_K_LEGACY, 0, 1, "contrast");
      PnlSpecAdd(0, PNL_K_LEGACY, 1, 1, "droplet");
      // P-LBL-12 (2026-10-17): addresses 2 (LABEL COLOR) and 4 (LABEL OPACITY)
      // are OFF THE CARD - they existed only to paint the trigger lines'
      // pip-distance labels (P-UI-131j), and there are no labels any more.
      // Both addresses, their palette targets, their read/apply branches and
      // their persisted keys all stay (MIDPOINT precedent, P-UI-47): nothing
      // renumbers and an old OV/GV still lands where it was written.
      PnlSpecAdd(0, PNL_K_SEC, -1, 0, "", "", "VISIBILITY", 1);
      PnlSpecAdd(0, PNL_K_LEGACY, 3, 1, "eye");   // hotkey T lives in the header badge only
   }
   else if(item == 1)   // ZONES & LEVELS (gold) — 11 settings / 19 display rows
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
      PnlSpecAdd(1, PNL_K_SEC, -1, 0, "", "", "SUB-CARDS", 5);
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
      // P-UI-220: the ANCHOR's START POINT (address 4 of the CUSTOM PRICE card) had
      // ONE door — hold the PIN ring item, or hold the custom-price line. Nothing on
      // the levels' own card named it, so «این تنظیمات startpoint سطوح رو توی پنل ها
      // ندیدم» was a true report about a live setting. APPENDED (row 18) the way
      // P-UI-126 and P-UI-131 appended theirs, so every address above keeps its
      // number and the NAV row itself persists nothing.
      PnlSpecAdd(1, PNL_K_LEGACY, 18, 1, "target", "", "", 0, "START POINT");
   }
   else if(item == 2)   // ATR LABELS (gold) — the countdown tag, the label
                        // switches, the plan ATR and the card colours: addresses
                        // 10..13 (the trade card's grid) render on the GENERAL
                        // card now (P-UI-131) while their addresses stay here.
   {
      PnlSpecAdd(2, PNL_K_SEC, -1, 0, "", "", "COUNTDOWN", 4);
      PnlSpecAdd(2, PNL_K_LEGACY, 0, 1, "timer", "C");
      PnlSpecAdd(2, PNL_K_LEGACY, 1, 1, "droplet");
      PnlSpecAdd(2, PNL_K_LEGACY, 2, 1, "textsize");
      PnlSpecAdd(2, PNL_K_LEGACY, 3, 1, "gap");
      PnlSpecAdd(2, PNL_K_SEC, -1, 0, "", "", "ATR BLOCK", 2);
      PnlSpecAdd(2, PNL_K_DUAL, 4, 2, "gauge");   // ATR LABELS · ATR TARGETS in one row (15→14 rows)
      PnlSpecAdd(2, PNL_K_SEC, -1, 0, "", "", "TRADE PLAN ROWS", 3);
      PnlSpecAdd(2, PNL_K_LEGACY, 6, 1, "tag", "T");
      PnlSpecAdd(2, PNL_K_LEGACY, 7, 1, "crosshair", "H");
      PnlSpecAdd(2, PNL_K_LEGACY, 8, 1, "flag", "P");
      // P-LBL-12 (2026-10-17): address 9 ("H/L PIP LABELS", the ruler row) is
      // OFF THE CARD - the setting's only consumer, the pip-distance labels,
      // is retired. The address, its input, its `PD` key and its descriptor/
      // read/apply branches all stay (MIDPOINT precedent, P-UI-47).
      // P-LEGATR: the plan's ATR source, APPENDED in its own band (14→16 display
      // rows, still wide). Address 19 renders here and nowhere else.
      // P-ANCHOR-LAST-MOVE (2026-10-22): address 20 (LAST OBJECT) is OFF THIS CARD.
      // It was never an ATR-label setting: its two consumers are the BaseKnot note
      // and the leg ruler, and neither reads it (they carry their own anchors —
      // BaseKnot_Owner.mqh:37 `an = t2`, TH3Tool_C.mqh:387 `LegReadAnchor`). The
      // address, its read/apply branches and its GV stay (MIDPOINT precedent,
      // P-UI-47), exactly like address 9 above; only the display row is gone, so
      // the band declares ONE row (19) instead of two.
      PnlSpecAdd(2, PNL_K_SEC, -1, 0, "", "", "PLAN ATR", 1);
      PnlSpecAdd(2, PNL_K_LEGACY, 19, 1, "gauge");
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
    else if(item == 3)   // TH LABELS (ember) — 7 addresses / 9 display rows
                         // (P-UI-131: MARGIN BOTTOM renders on the GENERAL card)
    {
       PnlSpecAdd(3, PNL_K_SEC, -1, 0, "", "", "TH SOURCES", 3);
       PnlSpecAdd(3, PNL_K_LEGACY, 0, 1, "wave");
       PnlSpecAdd(3, PNL_K_LEGACY, 1, 1, "steps");
       PnlSpecAdd(3, PNL_K_LEGACY, 2, 1, "wave");
       PnlSpecAdd(3, PNL_K_SEC, -1, 0, "", "", "TARGETS", 1);
       PnlSpecAdd(3, PNL_K_LEGACY, 3, 1, "target");
       PnlSpecAdd(3, PNL_K_SEC, -1, 0, "", "", "LAYOUT", 1);
       PnlSpecAdd(3, PNL_K_LEGACY, 6, 1, "wave");
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
       // P-UI-154: the anchor's START POINT (dialog-only until now) rides here,
       // address 4 APPENDED so 0..3 keep their numbers and the OV_ keys keep
       // their meaning. A fifth address, still far below PNL_WIDE_MIN_ROWS.
       PnlSpecAdd(8, PNL_K_SEC, -1, 0, "", "", "ANCHOR", 1);
       PnlSpecAdd(8, PNL_K_LEGACY, 4, 1, "wave");
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
      else if(g_BkTab == 2)   // SETUP — the 3 leg colours in ONE row
                              // (P-BK-27 added INFO SIZE to the EXTRAS band; BKCORNER-ON
                              // removed the INFO Auto/Show/Corner row — setting 5 stays
                              // reserved in place so 6/7 never renumber)
      {
         PnlSpecAdd(12, PNL_K_SEC, -1, 0, "", "", "RISK / REWARD", 1);
         PnlSpecAdd(12, PNL_K_LEGACY, 1, 1, "target");
         PnlSpecAdd(12, PNL_K_SEC, -1, 0, "", "", "LEG COLORS", 3, "strip");
         PnlSpecAdd(12, PNL_K_CSET, 2, 3);
         PnlSpecAdd(12, PNL_K_SEC, -1, 0, "", "", "EXTRAS", 2);
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
   // P-SESS — SESSIONS (15): the overview. 13 rows, WIDE (two columns): the
   // master and its door first, then every drawn family as one switch, its two
   // reach sliders paired. Row order = address order (spec order is the paint).
   else if(item == 15)
   {
      PnlSpecAdd(15, PNL_K_LEGACY, 0, 1, "power");
      PnlSpecAdd(15, PNL_K_LEGACY, 1, 1, "back");     // past days  (paired with FUTURE)
      PnlSpecAdd(15, PNL_K_LEGACY, 2, 1, "nav");      // future days
      PnlSpecAdd(15, PNL_K_LEGACY, 3, 1, "line");     // H/L lines
      PnlSpecAdd(15, PNL_K_LEGACY, 4, 1, "type");     // line labels
      PnlSpecAdd(15, PNL_K_LEGACY, 5, 1, "ruler");    // range text
      PnlSpecAdd(15, PNL_K_LEGACY, 6, 1, "flag");     // prior day
      PnlSpecAdd(15, PNL_K_LEGACY, 7, 1, "layers");   // overlap
      PnlSpecAdd(15, PNL_K_LEGACY, 8, 1, "timer");    // countdown
      PnlSpecAdd(15, PNL_K_LEGACY, 9, 1, "sparkles"); // alerts
      PnlSpecAdd(15, PNL_K_LEGACY, 10, 1, "layers");   // FILL % (P-SESS-14 — the look)
      PnlSpecAdd(15, PNL_K_LEGACY, 11, 1, "clock");    // ZONE LAW (P-SESS-15 — standard table / city clock)
      PnlSpecAdd(15, PNL_K_LEGACY, 13, 1, "line");     // TV LEVELS (P-SESS-18 — Midpoint / Mean / VWAP / Trendline)
      PnlSpecAdd(15, PNL_K_LEGACY, 14, 1, "ruler");    // STRIP (P-SESS-19 — the bottom session divider)
      PnlSpecAdd(15, PNL_K_LEGACY, 16, 1, "layers");   // STYLE Filled|Empty for the whole family (P-SESS-25 — appended)
      PnlSpecAdd(15, PNL_K_LEGACY, 12, 1, "tag");     // EDIT SESSIONS nav
   }
   // P-SESS — SESSION EDITOR (16): one slot at a time, chosen at row 0. 13 rows,
   // WIDE. The NAMED rows (preset/zone/style) are dropdowns by option count
   // (>=4 opts → the generic select engine asks no card-specific question); the
   // two grid rows are the chips kind with their table named in `opts`.
   else if(item == 16)
   {
      PnlSpecAdd(16, PNL_K_LEGACY, 0, 1, "tag");       // SESSION (which slot)
      PnlSpecAdd(16, PNL_K_LEGACY, 1, 1, "template");  // PRESET (factory fill)
      PnlSpecAdd(16, PNL_K_LEGACY, 2, 1, "clock");     // TIMEZONE
      PnlSpecAdd(16, PNL_K_LEGACY, 3, 1, "gap");       // UTC OFFSET
      PnlSpecAdd(16, PNL_K_LEGACY, 4, 1, "timer");     // START HOUR (paired with MIN)
      PnlSpecAdd(16, PNL_K_LEGACY, 5, 1, "timer");     // START MIN
      PnlSpecAdd(16, PNL_K_LEGACY, 6, 1, "timer");     // END HOUR (paired with MIN)
      PnlSpecAdd(16, PNL_K_LEGACY, 7, 1, "timer");     // END MIN
      PnlSpecAdd(16, PNL_K_LEGACY, 8, 1, "flag");      // DAYS chips
      PnlSpecAdd(16, PNL_K_LEGACY, 9, 1, "droplet");   // COLOR chips
      PnlSpecAdd(16, PNL_K_LEGACY, 10, 1, "linestyle");// STYLE
      PnlSpecAdd(16, PNL_K_LEGACY, 11, 1, "power");    // ACTIVE
      PnlSpecAdd(16, PNL_K_LEGACY, 12, 1, "back");     // OVERVIEW nav
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
   if(item==15 || item==16) return true;   // P-SESS: the Sessions pair
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

#endif