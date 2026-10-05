// Util_A.mqh - UtilityFunctions.mqh split 2026-09-29: exact lines 13-1446, byte-identical, zero renames.
#ifndef UTIL_A_MQH
#define UTIL_A_MQH


// P-UI-73's physical-button probe must never need a DLL, and the tree now has
// ZERO `#import` statements. Measured 2026-09-27: an `#import "user32.dll"` for
// one keyboard probe killed the whole indicator's OnInit — "unresolved import
// function call" / "DLL is not allowed" — wherever the terminal had DLL imports
// off, and that switch is not ours to ask anyone to flip. Two replacements were
// tried against THIS compiler first and both are absent from the build:
// `GetAsyncKeyState` -> error 168, `GetMouseState`/`MOUSE_LEFT` -> 168 + 256.
// The rule, and why the host's own TERMINAL_KEYSTATE_* is the right answer, are
// at UILeftButtonDown() below.

// Include ZoneFactory for centralized zone creation
#include "ZoneFactory.mqh"

// ══════════════════════════════════════════════════════════════════════════
// UI TEXT METRICS — the ONE owner of "how wide will MT4 draw this caption?"
//
// P-UI-34 (2026-09-12): MOVED here from BiotakPanels.mqh. The ring menu, its
// hover tooltip, the Tools sub-menu and the BaseKnot hint are all included
// BEFORE the panels in every entry (.mq4), so a metrics owner living in the
// panels cannot serve the surfaces that need it most - and a second copy
// would drift. The `Pnl` prefix is historical: these are the WHOLE UI metrics.
//
// P-UI-30 (2026-09-12). MT4 sizes an OBJ_LABEL/OBJ_BUTTON font at the
// TERMINAL's DPI (px = pt * dpi / 72) while these cards were designed in 96-DPI
// pixels (px = pt * 4/3). On a scaled display every caption therefore came out
// dpi/96 wider than the design AND wider than the `StringLen * 6` guess the
// layout used to reserve space, so captions ran into their own controls on a
// real chart: "ZONE STYLE" overlapped its Filled/Empty/Hidden segments, the
// GEOMETRY band's hairline crossed the label, "LS FIRST" touched the next
// switch, and every segment/dual caption overflowed its content-fitted pill.
// Measured off a real 120-DPI terminal screenshot: the 9pt row label
// "MID ZONES" drew 81px of ink where the design says 67px (rows 1.21x).
//
// Two rules, both owned here — never re-derive a caption width by hand:
//   1. PnlPt(nominal) re-expresses the design's px as points for THIS display,
//      so MT4 renders the design's 12px label instead of 12px * dpi/96.
//   2. PnlTextW() measures a caption with Arial Bold's real advances (the face
//      every panel caption sets) at the terminal's DPI, and PnlFit() clips a
//      caption to the room its control leaves — the twin of the preview's
//      `.row{gap:10px}` + `.lbl>span.t{text-overflow:ellipsis}`.
// ══════════════════════════════════════════════════════════════════════════
#define PNL_PT_MIN    4       // never go below 4pt (unreadable + MT4 clamps)

// ══════════════════════════════════════════════════════════════════════════
// P-UI-93 (2026-09-16) — THE DISPLAY'S DPI IS A MEASUREMENT, NOT A LATCH.
//
// The DPI this whole layer is sized by was read ONCE, into a function-local
// `static`, and nothing in the tree could ever move it again: the value lives
// for the life of the INDICATOR INSTANCE, and an instance lives until the
// indicator is removed or the terminal closes. So the one display event the
// user actually performs — dragging the terminal from the laptop's 100%
// panel onto the 4K monitor at 150%, or changing Windows' scale while the
// chart stays attached — left every surface on the OLD metric:
//   * `PnlPt()` keeps converting the design's px with dpi = 96, so MT4 draws
//     every caption at the pixel size of the smaller screen while the pixels
//     are now 1.5x bigger → captions that fit at 100% overflow their boxes
//     ("LS FIRST" touches the next switch again, the segment pills clip);
//   * `PnlLineH()`/`PnlRawLineH()` keep the old em box, so the row stacks
//     (the panel rows AND the chart-side trade card) pitch by the wrong
//     line height and drift out of their cards;
//   * and in the other direction (4K → laptop) every size comes out
//     microscopic, which is the report this block exists for.
// The old code could only be healed by remove + re-attach, i.e. by losing the
// user's live state — for a change the terminal itself reports.
//
// THE RULE: the DPI is re-probed, but by ONE owner and at a studied rate —
// `PnlDpi()` stays a pure cached read (it is called several times per drawn
// caption), and `PnlDpiPoll()` is the only thing that may touch the terminal,
// once per `PNL_DPI_PROBE_MS`. It answers TRUE only when the value really
// CHANGED, and the UI layer's one reaction to that answer is to rebuild the
// surfaces from the new metrics (`UIRebuildForMetrics`, BiotakPanels). Cost in
// steady state: one GetTickCount comparison per call site per 2 s.
//
// Deliberately NOT a per-call `TerminalInfoInteger`: that would put a terminal
// property read inside every `PnlTextW` of every row of every frame, which is
// exactly the class of cost P-PERF-16 removed from the hit tests.
// ══════════════════════════════════════════════════════════════════════════
#define PNL_DPI_PROBE_MS 2000   // P-UI-93: how often the display may be asked
static int  s_pnlDpi        = 0;   // the LATEST measurement (PnlDpi's answer)
static uint s_pnlDpiProbeMs = 0;   // the last time the terminal was asked

//--- the terminal's screen DPI as of RIGHT NOW. 96 = the DPI the design assumes.
int PnlDpiRead()
{
   int dpi = (int)TerminalInfoInteger(TERMINAL_SCREEN_DPI);
   if(dpi < 96 || dpi > 288) dpi = 96;   // outside the sane band = "unknown"
   return dpi;
}

//--- the cached, measured DPI. ONE owner of the value (P-UI-93).
int PnlDpi()
{
   if(s_pnlDpi <= 0) s_pnlDpi = PnlDpiRead();
   return s_pnlDpi;
}

//--- the re-probe. TRUE = the display's DPI CHANGED, and the caller owes the UI
//--- a rebuild from the new metrics. Rate-limited to one terminal read per
//--- `PNL_DPI_PROBE_MS`; every other call is one subtraction and a compare.
bool PnlDpiPoll()
{
   uint now = GetTickCount();
   if(s_pnlDpiProbeMs != 0 && now - s_pnlDpiProbeMs < PNL_DPI_PROBE_MS) return false;
   s_pnlDpiProbeMs = now;
   int dpi = PnlDpiRead();
   if(dpi == PnlDpi()) return false;
   s_pnlDpi = dpi;
   return true;
}
// ══════════════════════════════════════════════════════════════════════════
// P-UI-69e (2026-09-25) — THE TYPE SCALE SURVIVES EVERY DPI (D-03, solved).
// THE BUG, on the shipped `pt = round(nominal * 96 / dpi)`: twenty adjacent pairs
// across the seven scales the band allows (96..288 step 12) land on the SAME integer
// point. At 125% the section caption (7) and the value (8) are ONE SIZE, at 150% two
// pairs are, and from 250% up the whole six-size scale is a single 4pt size — the
// hierarchy is the first casualty of a scaled display, and it is invisible on the 96
// DPI machine every number was measured on.
// THE FIX, one line: a size is the design's device-px answer, LIFTED rung by rung so
// no two sizes the UI uses are ever equal, and CAPPED at the tallest em the row
// geometry can hold (`14 + 24 = 38 < 42`). Three properties, asserted by
// `tests/Biotak_TypeScale_Test.mq4`: identity at 96 DPI, never equal below the cap,
// never overflows the row — and above ~240 DPI the cap must merge the top rungs, where
// hierarchy comes from weight or colour instead. The lift is the MINIMUM that makes the
// rungs distinct, so at 125% only the top three sizes move, by one point.
// ══════════════════════════════════════════════════════════════════════════
#define PNL_PT_LADDER_MIN 5    // the smallest nominal the UI uses (PNL_PT_CSET)
#define PNL_PT_LADDER_MAX 14   // head-room above the biggest (SUB_PT_PAGER 10)
#define PNL_PT_LADDER_N  (PNL_PT_LADDER_MAX - PNL_PT_LADDER_MIN + 1)
//--- the cap's own arithmetic, spelled out here because its INPUTS (PNL_ROW_H 42,
//--- PNL_LBL_Y 14) live in BiotakPanels.mqh — include 116, above this module's 47
//--- (MQL4 is define-before-use). One number, one derivation, named once: if the
//--- row geometry ever moves, this line moves with it. 4px is the breathing gap.
#define PNL_PT_FIT_PX    24    // 42 - 14 - 4

//--- the PURE answer for one nominal at one dpi: no cache, no terminal read, so a
//--- harness can sweep every scale a user owns. THE rule lives here.
int PnlPtAt(const int nominal,const int dpi)
{
   int d = (dpi < 96 || dpi > 288) ? 96 : dpi;      // the sane band PnlDpiRead enforces
   int rawMin = (int)MathRound(PNL_PT_LADDER_MIN * 96.0 / (double)d);
   int shift  = (rawMin < PNL_PT_MIN) ? (PNL_PT_MIN - rawMin) : 0;   // the floor lifts the WHOLE ladder
   int pt = 0;
   for(int m = PNL_PT_LADDER_MIN; m <= nominal; m++)
   {
      // the rung for `nominal` if the ladder's floor were m, plus one point for
      // every rung between: the maximum over m IS the minimal distinct ladder.
      int c = (int)MathRound(m * 96.0 / (double)d) + (nominal - m) + shift;
      if(c > pt) pt = c;
   }
   // FLOOR, never round: rounding the cap UP gave an em of 25px for a 24px budget
   // at 180/228/252/264 DPI — the very overflow the cap exists to prevent (found
   // by the type-scale sweep, tests/Biotak_TypeScale_Test.mq4).
   int cap = (int)MathFloor(PNL_PT_FIT_PX * 72.0 / (double)d);
   if(cap < PNL_PT_MIN) cap = PNL_PT_MIN;
   if(pt > cap) pt = cap;                            // the row wins over the rung
   if(pt < PNL_PT_MIN) pt = PNL_PT_MIN;
   return pt;
}
//--- the ladder, built once per DPI: index = nominal - PNL_PT_LADDER_MIN.
//--- PnlPt is called several times per drawn caption, so the per-DPI build is
//--- amortised to nothing and the hot path stays two compares and an array read.
static int s_pnlPtDpi = -1;
static int s_pnlPtLad[PNL_PT_LADDER_N];
void PnlPtBuild(const int dpi)
{
   for(int i = 0; i < PNL_PT_LADDER_N; i++)
      s_pnlPtLad[i] = PnlPtAt(PNL_PT_LADDER_MIN + i, dpi);
   s_pnlPtDpi = dpi;
}
//--- a NOMINAL (design px * 3/4) point size, re-expressed for this display.
int PnlPt(const int nominal)
{
   int dpi = PnlDpi();
   if(s_pnlPtDpi != dpi) PnlPtBuild(dpi);            // P-UI-93: the DPI is a measurement
   int i = nominal - PNL_PT_LADDER_MIN;
   if(i >= 0 && i < PNL_PT_LADDER_N) return s_pnlPtLad[i];
   return PnlPtAt(nominal, dpi);                     // off the ladder: a one-off size
}
//--- the line box MT4 gives a NOMINAL point size, in px (em = pt * dpi / 72).
//--- the ONE owner of that arithmetic: PnlTextW measures with it, and every
//--- caller that has to stack two lines (keycap letter, hover tooltip) uses it
//--- instead of a magic pixel offset.
int PnlLineH(const int nominalPt)
{
   return (int)MathRound(PnlPt(nominalPt) * (double)PnlDpi() / 72.0);
}
//--- the line box MT4 gives a RAW point size (the CHART label family, which
//--- hands MT4 `inpFontSize` unchanged - P-UI-42). The RAW sibling of
//--- PnlLineH, and the ONE owner of the raw em arithmetic: PnlRawTextW
//--- measures with it and every chart-side row stack (the bottom-right trade
//--- card, P-LBL-07) pitches with it instead of a magic pixel offset.
int PnlRawLineH(const int rawPt)
{
   int pt = (rawPt > 0) ? rawPt : 1;
   return (int)MathRound(pt * (double)PnlDpi() / 72.0);
}
// ══════════════════════════════════════════════════════════════════════════
// THE PHYSICAL MOUSE BUTTON — the ONE owner (P-UI-73)
//
// WHY THIS EXISTS. Four engines have to answer "is the left button down RIGHT
// NOW?" from a place no mouse event can reach them: the panels' stale-claim
// recovery (`PnlPressAllowed` — a missed release used to dead-lock every
// coordinate control of an open card, P-UI-70b), the box-hold zero-move latch
// (`BkHoldPoll` — a press with ZERO movement emits no CHARTEVENT_MOUSE_MOVE at
// all, so only a probe can ever see it), and the two stale-drag watchdogs
// (`BaseKnotSyncBadges`, `CustomPriceDragHealStale` — both 1.5 s of event
// silence away from their own probe).
//
// They disagreed, and BOTH spellings were in this tree:
//     `TerminalInfoInteger(TERMINAL_KEYSTATE_LEFT) < 0`     (BiotakPanels)
//     `(TerminalInfoInteger(TERMINAL_KEYSTATE_LEFT) & 1)`   (EventHandlers,
//                                                            BaseKnotTool)
// MQL4 build lineages report this property either way: under one a pressed
// button is NEGATIVE (0 = free, and -128 is down with bit 0 CLEAR), under the
// other it is bit 0 (1 = down, 0 = free). Each spelling is blind to the other
// convention, so at least one of those four sites was answering at random — the
// ones asking "is it UP?" could report up in the middle of a live gesture (the
// P-UI-49b class: a teardown written into the press that started it) and the
// ones asking "is it DOWN?" could never see a press at all (the zero-move hold
// never latched).
//
// THE RULE: one owner, and every caller asks it. Both answers are deliberately
// CONSERVATIVE — they never invent a transition the terminal did not make:
//   * `UILeftButtonDown()` is TRUE if EITHER convention says pressed. A false
//     "down" only defers a recovery to the next event, never breaks one.
//   * `UILeftButtonUp()` is TRUE only if BOTH conventions agree the button is
//     free. A false "up" would tear a LIVE gesture down, so it is never
//     inferred from one convention.
// Never read TERMINAL_KEYSTATE_LEFT anywhere else again. No `#import` for this
// probe — the file header note says why, and the host's own keystate is the
// answer, read below exactly as UIMagnetModifierDown reads SHIFT.
bool UILeftButtonDown()
{
   long v = TerminalInfoInteger(TERMINAL_KEYSTATE_LEFT);
   return (v < 0) || ((v & 1) != 0);
}
bool UILeftButtonUp()
{
   long v = TerminalInfoInteger(TERMINAL_KEYSTATE_LEFT);
   return (v >= 0) && ((v & 1) == 0);
}

//--- P-BK-61/66: the ONE owner of "is the magnet's MODIFIER held RIGHT NOW?" —
//--- base-box handle magnet («با کنترل هم مگنت فعال میشه ... حرکت رو چسبوند به
//--- کندل های و لو که دقیق باشه»). It sits here for the same reason the button
//--- pair above does: the gesture channel (an OBJECT_DRAG) carries no keyboard
//--- state at all, so a modifier can only be answered by a live probe, and a
//--- second spelling of that probe is how the button's two conventions came to
//--- disagree (P-UI-73). Same two readings of TERMINAL_KEYSTATE_*, same rule:
//--- TRUE if EITHER convention says held. The asymmetry is DELIBERATE and the
//--- opposite of `UILeftButtonUp()`: a false "held" only means a handle drag
//--- snaps a value the user is dragging anyway (visible, one pixel wide, and
//--- undone by dragging on), while a false "free" would make the modifier
//--- look dead on exactly the build lineage that spells the probe the other way.
//---
//--- WHY THE MODIFIER IS SHIFT AND NOT CTRL (P-BK-66, 2026-09-16). Reported:
//--- «من ctrl که میگیرم برای مگنت این باکس رو کپی میکنه» — MetaTrader's own
//--- Ctrl+drag DUPLICATES a draggable object, and the box' handles ARE draggable
//--- objects (their OBJPROP_SELECTABLE is what makes them handles at all,
//--- P-BK-61), so the terminal cloned the chip instead of letting the magnet
//--- snap it: Ctrl is the terminal's copy gesture, never ours, and a magnet on
//--- Ctrl is a magnet the user can never hold down. The modifier must be a key
//--- the terminal's OWN object drag does not claim:
//---   * SHIFT   — pollable as TERMINAL_KEYSTATE_SHIFT, and MT4 binds no
//---               object-drag behaviour to it. THIS IS THE CHOICE (P-BK-66).
//---   * CONTROL — the terminal's duplicate gesture («این باکس رو کپی میکنه»).
//---   * ALT     — pollable as TERMINAL_KEYSTATE_MENU, but Windows and the
//---               terminal both eat it (menu access, Alt+Tab): a magnet that
//---               dies on a window switch is worse than no magnet.
//---   * MIDDLE  — pollable (TERMINAL_KEYSTATE_MIDDLE), but no hand holds the
//---               middle button while dragging with the left one.
//--- The caller asks by ROLE (`UIMagnetModifierDown()`), so moving the magnet to
//--- another key is THIS function and nothing else.
bool UIMagnetModifierDown()
{
   long v = TerminalInfoInteger(TERMINAL_KEYSTATE_SHIFT);
   return (v < 0) || ((v & 1) != 0);
}

//--- P-UI-114 (2026-09-23) — deleted: RightClickTerminalOwns[/Set],
//--- RightClickStripOwns[Set/Take], RightClickSelfEsc[Stamp/Ms] (dead gates of
//--- the deleted right-click era; the strip opens on a LEFT hold now).

//--- Arial Bold advances, units per 1000 em (the face the panels set).
int PnlAdvUnits(const ushort ch)
{
   if(ch >= '0' && ch <= '9') return 556;
   if(ch >= 'a' && ch <= 'z')
   {
      //            a    b    c    d    e    f    g    h    i    j    k    l    m
      int lo[26] = {556, 611, 556, 611, 556, 333, 611, 611, 278, 278, 556, 278, 889,
      //            n    o    p    q    r    s    t    u    v    w    x    y    z
                    611, 611, 611, 611, 389, 556, 333, 611, 556, 778, 556, 556, 500};
      return lo[ch - 'a'];
   }
   if(ch >= 'A' && ch <= 'Z')
   {
      //            A    B    C    D    E    F    G    H    I    J    K    L    M
      int up[26] = {722, 722, 722, 722, 667, 611, 778, 722, 278, 556, 722, 611, 833,
      //            N    O    P    Q    R    S    T    U    V    W    X    Y    Z
                    722, 778, 667, 778, 722, 667, 611, 722, 667, 944, 667, 722, 611};
      return up[ch - 'A'];
   }
   if(ch == 32)  return 278;   // space
   if(ch == 46)  return 278;   // .
   if(ch == 44)  return 278;   // ,
   if(ch == 58)  return 333;   // :
   if(ch == 59)  return 333;   // ;
   if(ch == 45)  return 333;   // -
   if(ch == 47)  return 278;   // /
   if(ch == 37)  return 889;   // %
   if(ch == 183) return 333;   // · (the P-LBL-01 middle dot)
   //--- P-BK-86: the three characters the BASE NOTE prints that this table never carried.
   //--- `[`, `]` and `|` all fell through to the 611 below, so the note's plate — the opaque
   //--- bar the ink is read on — was measured +1.27 em too wide: +14 px at 8pt/96dpi, +20 px
   //--- at 8pt/144dpi. A tail with nothing in it, and the note is the one surface whose whole
   //--- point is that its box fits its ink. The values are READ OFF the installed face, never
   //--- guessed: `tools/font-adv-check.py` parses arialbd.ttf's own `hmtx` table (unitsPerEm
   //--- 2048) and prints these three beside every other entry here. Nothing else measures
   //--- them — the panels split their option lists on `|` before measuring a single option
   //--- (PnlDdOptText), so this closes a gap rather than moving a layout.
   if(ch == 91 || ch == 93) return 333;   // [ ]  (arialbd.ttf hmtx)
   if(ch == 124) return 280;              // |    (arialbd.ttf hmtx)
   if(ch == 38)  return 722;   // &
   if(ch == 40 || ch == 41) return 333;   // ( )
   if(ch == 47 || ch == 39) return 278;   // / '
   if(ch == 43)  return 584;   // +
   if(ch == 61)  return 584;   // =
   if(ch == 60 || ch == 62) return 584;   // < >
   if(ch == 33)  return 333;   // !
   if(ch == 63)  return 611;   // ?
   if(ch == 95)  return 556;   // _
   if(ch == 35)  return 556;   // #
   if(ch == 42)  return 389;   // *
   if(ch == 64)  return 975;   // @
   return 611;                // unknown -> a mid-weight capital
}
//--- the advance sum of `s`, in Arial Bold units per 1000 em. The ONE walk of
//--- the table: both entry points below go through it, so two surfaces asking
//--- about the same caption can never get two different numbers.
int PnlTextUnits(const string s)
{
   int n = StringLen(s);
   int units = 0;
   for(int i=0;i<n;i++) units += PnlAdvUnits(StringGetCharacter(s,i));
   return units;
}
//--- the width MT4 will draw `s` at, in pixels, for a NOMINAL point size.
//--- em px = the POINT SIZE ACTUALLY PASSED (PnlPt) * dpi / 72 — the height
//--- MT4 gives the font, so the measured advance is the drawn advance.
int PnlTextW(const string s,const int nominalPt)
{
   if(StringLen(s) <= 0) return 0;
   int em = PnlLineH(nominalPt);
   return (int)MathRound(PnlTextUnits(s) * em / 1000.0);
}
//--- the width MT4 draws `s` at when its owner hands MT4 a RAW point size:
//--- an object that did NOT go through PnlPt. The CHART label family is the
//--- one such surface (P-UI-42) — it sets OBJPROP_FONTSIZE to inpFontSize
//--- unchanged, so MT4 renders px = rawPt * dpi / 72 (the P-UI-30 trap, same
//--- arithmetic, without the design correction PnlLineH applies). Same table,
//--- same cached DPI, same owner: only the em box differs.
int PnlRawTextW(const string s,const int rawPt)
{
   if(StringLen(s) <= 0) return 0;
   int em = PnlRawLineH(rawPt);      // one owner for the raw em (P-LBL-07)
   return (int)MathRound(PnlTextUnits(s) * em / 1000.0);
}
//--- the longest whole prefix of `txt` that fits `maxW` px, with ".." when it
//--- had to be clipped (the preview's ellipsis twin — MT4/Wine Arial ships no
//--- U+2026, see P-ICONS-05, so the ASCII pair is the honest stand-in).
string PnlFit(const string txt,const int nominalPt,const int maxW)
{
   if(PnlTextW(txt,nominalPt) <= maxW) return txt;
   for(int k=StringLen(txt);k>0;k--)
   {
      string cut = StringSubstr(txt,0,k);
      StringTrimRight(cut);
      if(PnlTextW(cut + "..",nominalPt) <= maxW) return cut + "..";
   }
   return "";
}
//+------------------------------------------------------------------+
//| Get Symbol Point (Cached)                                        |
//+------------------------------------------------------------------+
double GetSymbolPoint() {
    static double point = 0;
    if(point == 0) {
        // Use MODE_POINT which is the standard tick size for the symbol
        // This is equivalent to Point() built-in function
        point = MarketInfo(Symbol(), MODE_POINT);
        
        // For most forex pairs, MODE_POINT and MODE_TICKSIZE are the same
        // But to be absolutely sure, we use MODE_POINT which matches Java's tickSize
        if(point == 0) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("GetSymbolPoint: Failed to get point value for symbol ", Symbol());
            #endif
            return 0;
        }
    }
    return point;
}

void CheckArraySizes() {
    // OPTIMIZATION: Use smarter initial sizing based on actual needs
    // Cache arrays: size based on number of fractal timeframes + buffer
    int optimalCacheSize = ArraySize(FRACTAL_TIMEFRAMES) + ArraySize(STANDARD_TIMEFRAMES) + 5;
    
    // g_thCache removed - matching MT5

    // Stored THs: size based on actual timeframe count
    if(ArraySize(g_storedTHs) <= 0) {
        ArrayResize(g_storedTHs, optimalCacheSize);
    }

    // Label positions: size based on actual timeframe count
    if(ArraySize(g_labelPositions) <= 0) {
        ArrayResize(g_labelPositions, optimalCacheSize);
    }
}

//+------------------------------------------------------------------+
//| Calculate pips distance between two prices                       |
//| Note: Uses g_currentPrice which is Close of last completed bar  |
//| OPTIMIZED: Uses cached PipSize value via GetCachedPipSize()     |
//+------------------------------------------------------------------+
double CalculatePipsDistance(const double price1, const double price2) {
    double pipSize = GetCachedPipSize();
    if(IsZero(pipSize, EPSILON_PRICE)) return 0.0;
    return NormalizeDouble(MathAbs(price1 - price2) / pipSize, 1);
}

//+------------------------------------------------------------------+
//| Format tooltip with distance in pips                            |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Get midpoint price based on start point type                    |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| P-UI-98d v2: the price at the VERTICAL MIDDLE of the visible     |
//| chart — wherever the user has scrolled to. The custom price line |
//| activates there («خط کاستوم پرایس زمانی که فعال میشه هر جایی که |
//| کاربر هست وسط صفحه ظاهر بشه که راحت باشه»): the line is born     |
//| where the user is LOOKING, not at the market's last price.       |
//| 0.0 = the chart could not answer (the caller keeps its fallback).|
//+------------------------------------------------------------------+
double ScreenMiddlePrice() {
    double pmax = ChartGetDouble(0, CHART_PRICE_MAX);
    double pmin = ChartGetDouble(0, CHART_PRICE_MIN);
    if(!(pmax > pmin) || pmin <= 0.0) return 0.0;
    double mid = (pmax + pmin) / 2.0;
    if(!(mid > 0.0) || !MathIsValidNumber(mid)) return 0.0;
    return NormalizeDouble(mid, Digits);
}

double GetMidpointPrice(ENUM_TH_START_POINT_TYPE startPointType) {
    switch(startPointType) {        case TH_START_POINT_HISTORICAL_HIGH:
            return g_highestHigh;
        case TH_START_POINT_HISTORICAL_LOW:
            return g_lowestLow;
        case TH_START_POINT_CUSTOM_PRICE:
        {
            double customPrice = (g_customTHStartPrice > 0.0) ? g_customTHStartPrice : inpCustomTHStartPrice;
            return (customPrice > 0.0) ? customPrice : (g_highestHigh + g_lowestLow) / 2.0;
        }
        case TH_START_POINT_PREVIOUS_CLOSE:
        {
            // Previous day close (D1 bar 1). Static daily cache so the
            // per-second label refresh stays cheap. (GetPriceForPreviousDay
            // lives in a later include, so this uses the built-in iClose.)
            static datetime s_prevCloseUpdate = 0;
            static double   s_prevClose = 0;
            datetime now = TimeCurrent();
            if(s_prevCloseUpdate == 0 || now - s_prevCloseUpdate >= 86400 || s_prevClose <= 0) {
                s_prevClose = iClose(Symbol(), PERIOD_D1, 1);
                s_prevCloseUpdate = now;
            }
            return (s_prevClose > 0 && s_prevClose != EMPTY_VALUE) ? s_prevClose : Bid;
        }
        case TH_START_POINT_MIDPOINT:
        default:
            return (g_highestHigh + g_lowestLow) / 2.0;
    }
}

//+------------------------------------------------------------------+
//| Get current step calculation mode — the single Step Mode.        |
//| STEPOVERRIDE-OFF: the override layer is retired; the base IS the |
//| mode (E / Tools-ring / panel all write it directly).             |
//+------------------------------------------------------------------+
ENUM_STEP_CALCULATION_MODE GetCurrentStepMode() {
    // STEPOVERRIDE-OFF:
    //if(g_stepModeOverride >= 0 && g_stepModeOverride <= 3) {
    //    return (ENUM_STEP_CALCULATION_MODE)g_stepModeOverride;
    //}
    // Otherwise use input parameter
    return inpStepCalculationMode;
}

//+------------------------------------------------------------------+
//| Get step mode display name for UI                               |
//+------------------------------------------------------------------+
string GetStepModeName(ENUM_STEP_CALCULATION_MODE mode) {
    switch(mode) {
        case TH_STEP:           return "S";      // Structure step (was TH - renamed to avoid confusion with TH/ATR basis)
        case SS_LS_STEP:        return "SS/LS";
        case COMBO_STEP:        return "Combo";
        case FACTOR_STEP:       return "F";      // Factor step mode
        default:                return "Unknown";
    }
}

// (Removed: legacy GetComboPresetName / GetSharedComponentValue / GetSharedComponentName -
//  dead code referencing the old combo component system. Combo names/values now live in
//  ComboEngine.mqh; preset display is handled by EnumToString.)

//+------------------------------------------------------------------+
//| Clear all temporary mode labels (call before showing new one)   |
//|              label          (                         )         |
//+------------------------------------------------------------------+
void ClearAllModeLabels() {
    // Reset expiry timestamps so deleted labels are not re-cleared
    // or counted in stacking rows afterwards.
    if(ObjectFind(0, g_stepModeLabelName) >= 0) {
        ObjectDelete(0, g_stepModeLabelName);
    }
    g_stepModeLabelCreateTime = 0;
    if(ObjectFind(0, g_factorLabelName) >= 0) {
        ObjectDelete(0, g_factorLabelName);
    }
    g_factorLabelCreateTime = 0;
#ifndef BUILD_LITE
    if(ObjectFind(0, g_th3FreqLabelName) >= 0) {
        ObjectDelete(0, g_th3FreqLabelName);
    }
    g_th3FreqLabelCreateTime = 0;
#endif
    // Lock status is a persistent status while TF is locked - keep it visible.
    if(!g_timeframeLocked) {
        if(ObjectFind(0, g_lockStatusLabelName) >= 0) {
            ObjectDelete(0, g_lockStatusLabelName);
        }
        g_lockStatusLabelCreateTime = 0;
    }
}

//+------------------------------------------------------------------+
//| Get primary step price for current mode                          |
//+------------------------------------------------------------------+
double GetCurrentModePrimaryStepPrice(ENUM_STEP_CALCULATION_MODE mode)
{
    int digits = GetCachedDigits();
    double basePrice = (g_dailyClosePriceForTH > 0) ? g_dailyClosePriceForTH : Bid;
    if(basePrice <= 0) return 0.0;

    double timeframePercentage = GetTimeframeTH();
    double thValue = CalculateTH(basePrice, digits, timeframePercentage);
    if(thValue <= 0) return 0.0;
    thValue = GetAdaptedStepSize(thValue);

    switch(mode)
    {
        case TH_STEP:
            return thValue;

        case FACTOR_STEP:
            // Centralized: handles DIRECT (step semantics) and CLASSIC (factor semantics)
            return GetFactorModePrimaryStepPrice(basePrice);

        case SS_LS_STEP:
        {
            double structureValue, patternValue, triggerValue;
            CalculateFractalValues(thValue, structureValue, patternValue, triggerValue);
            return structureValue * 1.5; // SS_MULTIPLIER = 1.5
        }

        case COMBO_STEP:
            return CalculateComboStepSize(basePrice);

        default:
            return thValue;
    }
}

//+------------------------------------------------------------------+
//| P-UI-98: the same answer the ladder draws.                       |
//| The step override (the draggable rung-1 handle in custom-price   |
//| mode) multiplies the mode's steps at the factory's only consumer, |
//| so the "S:" pips the status label shows must ride the same       |
//| factor — a label that quotes the natural step over a scaled      |
//| ladder is the lie the label family exists to prevent.            |
//+------------------------------------------------------------------+
double GetCurrentModePrimaryStepPriceOverridden(ENUM_STEP_CALCULATION_MODE mode)
{
    double natural = GetCurrentModePrimaryStepPrice(mode);
    if(natural <= 0.0) return natural;
    double f = StepOverrideFactor();
    return (f != 1.0) ? natural * f : natural;
}

//+------------------------------------------------------------------+
//| Get ATR Info string for status display                           |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Base price (B) info for the status label.                        |
//| B is ALWAYS the step-calculation basis: the reference base price  |
//| (g_dailyClosePriceForTH, synced from GetBasePriceForTH on every   |
//| redraw) that CalculateTH / CalculateComboStepSize use to compute  |
//| the step sizes. It is NOT the level-drawing anchor - that is a    |
//| separate value shown as A: when it differs (see below).           |
//| Never displays 0: falls back to the live bid.                     |
//+------------------------------------------------------------------+
string GetBasePriceStatusInfo() {
    double basePrice = (g_dailyClosePriceForTH > 0) ? g_dailyClosePriceForTH : Bid;
    if(basePrice <= 0) basePrice = Bid;
    if(basePrice <= 0) basePrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    return StringFormat(" | B: %.5f", basePrice);
}

//+------------------------------------------------------------------+
//| Anchor (drawing basis) info for the status label.                |
//| Levels are drawn AROUND GetMidpointPrice(g_thStartPointType):    |
//|   Custom Price -> the custom price; Midpoint -> (H+L)/2;         |
//|   Hist High/Low -> g_highestHigh / g_lowestLow.                  |
//| This is a separate value from the step-calculation basis (B).    |
//| Shown only when it differs from B, so the user can see what the  |
//| levels anchor to without cluttering the label.                   |
//+------------------------------------------------------------------+
string GetAnchorPriceStatusInfo() {
    double basis = (g_dailyClosePriceForTH > 0) ? g_dailyClosePriceForTH : Bid;
    if(basis <= 0) return "";

    double anchor = GetMidpointPrice(g_thStartPointType);
    if(anchor <= 0 || anchor == EMPTY_VALUE) return "";

    double point = GetCachedPoint();
    if(point <= 0) return "";

    // Hide when the anchor equals the calculation basis (avoids noise)
    if(MathAbs(anchor - basis) <= point * 0.1) return "";

    return StringFormat(" | A: %.5f", anchor);
}

// The combo calc breakdown is filled by RefreshComboLabelExtraInfo() in
// ComboEngine.mqh (included later) - see g_comboLabelExtraInfo global.
//
// Combo mode appends a compact "how it was computed" breakdown, e.g.
// "avg(PatTH12.1p,TrigTH6.1p)" so the user can verify the math.
string BuildUnifiedModeLabelText()
{
    ENUM_STEP_CALCULATION_MODE currentMode = GetCurrentStepMode();
    string modeName = GetStepModeName(currentMode);
    double pipSize = GetCachedPipSize();
    // P-UI-98: the overridden answer — the step the ladder actually wears.
    double stepPrice = GetCurrentModePrimaryStepPriceOverridden(currentMode);

    if(pipSize <= 0 || stepPrice <= 0) return "[ " + modeName + " ]";

    string calcInfo = "";
    if(currentMode == COMBO_STEP && g_comboLabelExtraInfo != "")
        calcInfo = " | " + g_comboLabelExtraInfo;

    return StringFormat("[ %s | S: %.1f%s%s%s ]", 
        modeName, stepPrice / pipSize, calcInfo,
        GetBasePriceStatusInfo(), GetAnchorPriceStatusInfo());
}

//+------------------------------------------------------------------+
//| Set label text only when it actually changed (PERF: avoids      |
//| pointless ObjectSetString syscalls on every tick/refresh)       |
//+------------------------------------------------------------------+
void SetLabelTextIfChanged(const string name, const string text) {
    if(ObjectFind(0, name) < 0) return;
    string currentText = ObjectGetString(0, name, OBJPROP_TEXT);
    if(currentText != text) ObjectSetString(0, name, OBJPROP_TEXT, text);
}

//+------------------------------------------------------------------+
//| Update step mode label on chart (configurable duration)         |
//| Updates text in place when already visible (no recreate churn,  |
//| no expiry timestamp reset) so real-time refresh stays cheap.    |
//+------------------------------------------------------------------+
void UpdateStepModeLabel(bool clearFirst = true) {
    if(!inpShowModeChangeLabel) return;
    
    if(clearFirst) ClearAllModeLabels();
    if(IsIndicatorHidden()) return;
    
    string labelText = BuildUnifiedModeLabelText();
    
    if(ObjectFind(0, g_stepModeLabelName) < 0) {
        if(!ObjectCreate(0, g_stepModeLabelName, OBJ_LABEL, 0, 0, 0)) return;
        // Timestamp set ONLY on creation so auto-hide still fires on schedule.
        g_stepModeLabelCreateTime = GetTickCount();
        ApplyModeLabelStyle(g_stepModeLabelName, inpModeLabelColor);
    }
    SetLabelTextIfChanged(g_stepModeLabelName, labelText);
}

//+------------------------------------------------------------------+
//| P-FREE-03: the legend witness — symbol above, FREE below it.        |
//| A scammer sells with screenshots of THIS chart, so the mark sits|
//| right under the indicator names (top-left): line 1 the symbol + |
//| missing every call (undeletable in-session: hidden from the      |
//| object list, non-selectable, reborn next pump); style is birth-  |
//| only, text compare-guarded — a still chart costs two finds plus |
//| two compares. Ignores hide-all BY DESIGN (a hidden mark witnesses|
//| nothing). Dies only with the indicator (OnDeinitHandler). ASCII  |
//| only: a non-Latin glyph needs a font with coverage (P-LBL-02).    |
//+------------------------------------------------------------------+
void FreeMarkLine(const string nm, const string txt, const int y)
{
    if(ObjectFind(0, nm) < 0)
    {
        if(!ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0)) return;
        ObjectSetString(0, nm, OBJPROP_TEXT, "");
        ObjectSetString(0, nm, OBJPROP_FONT, inpFontName);
        ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 8);
        ObjectSetInteger(0, nm, OBJPROP_COLOR, BIO_CLR_MUTED);
        ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
    }
    // P-DRAW-122: seat + layer re-assert every pass, not only at birth — so a
    // stale build's seat never survives an update and a surviving object keeps
    // its rung. BACK=false is the watermark half: foreground chrome-order.
    ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, nm, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
    ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, 8);
    ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, nm, OBJPROP_BACK, false);
    if(ObjectGetString(0, nm, OBJPROP_TEXT) != txt)
        ObjectSetString(0, nm, OBJPROP_TEXT, txt);
}
void UpdateFreeMark()
{
#ifdef BUILD_LITE
    FreeMarkLine(g_freeSymName, Symbol() + " | Biotak TH3 Lite v" + INDICATOR_VERSION, 22);
#else
    FreeMarkLine(g_freeSymName, Symbol() + " | Biotak TH3 v" + INDICATOR_VERSION, 22);
#endif
    FreeMarkLine(g_freeMarkName, "FREE | @biotak", 38);
}

//+------------------------------------------------------------------+
//| Update calculation basis label on chart (configurable duration) |
//| Uses Label object matching step mode label style                |
//| Shows both basis and current step mode: "ATR | SS/LS"           |
//| Duration: inpModeLabelDuration (0=permanent, >0=seconds)        |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Build the factor label text (shared by show + real-time refresh)|
//|                                                                  |
//| DIRECT MODE:  step size first  -> "[ Step: 12.5 | F: 50.00 ]"   |
//| CLASSIC MODE: factor first     -> "[ F: 50.00 | Step: 12.5 pips ]" |
//+------------------------------------------------------------------+
string BuildFactorLabelText(const double factorValue, const double stepSize) {
    double pipSize = GetCachedPipSize();
    if(stepSize > 0 && pipSize > 0) {
        double stepPips = stepSize / pipSize;
        if(inpFactorDisplayMode == FACTOR_DISPLAY_DIRECT) {
            return StringFormat("[ Step: %.1f | F: %.2f ]", stepPips, factorValue);
        }
        return StringFormat("[ F: %.2f | Step: %.1f pips ]", factorValue, stepPips);
    }
    return StringFormat("[ F: %.2f ]", factorValue);
}

//+------------------------------------------------------------------+
//| Update Factor value label on chart (configurable duration)      |
//| Updates text in place when already visible (no recreate churn,  |
//| no expiry timestamp reset) so real-time refresh stays cheap.    |
//+------------------------------------------------------------------+
void UpdateFactorLabel(double factorValue, double directStepSize = 0, bool clearFirst = true) {
    // Check if mode label display is enabled
    if(!inpShowModeChangeLabel) return;
    
    // Clear ALL temporary labels first (prevents overlap)
    if(clearFirst) ClearAllModeLabels();
    
    // CRITICAL FIX: Don't show label if indicator is hidden
    if(IsIndicatorHidden()) return; // Don't show mode labels when hidden
    
    // Calculate step size for display
    double stepSize = directStepSize;
    if(stepSize <= 0) {
        // CLASSIC MODE: Calculate step from factor
        if(g_highestHigh > 0 && g_lowestLow > 0 && g_highestHigh > g_lowestLow) {
            stepSize = CalculateFactorStepSize(g_highestHigh, g_lowestLow, factorValue);
        }
    }
    
    string labelText = BuildFactorLabelText(factorValue, stepSize);
    
    // GOLD FIX: Check if object exists before creating
    if(ObjectFind(0, g_factorLabelName) < 0) {
        if(!ObjectCreate(0, g_factorLabelName, OBJ_LABEL, 0, 0, 0)) return;
        // Timestamp set ONLY on creation so auto-hide still fires on schedule.
        g_factorLabelCreateTime = GetTickCount();
        ApplyModeLabelStyle(g_factorLabelName, inpFactorLevelColor);
    }
    
    SetLabelTextIfChanged(g_factorLabelName, labelText);
}

// TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
#ifndef BUILD_LITE
//+------------------------------------------------------------------+
//| Build TH3 Movement-Step label text (shared by show + real-time  |
//| refresh). The FIBO object scan is throttled (max once per 5s or |
//| when the step changed) so the per-second refresh stays          |
//| lightweight.                                                    |
//+------------------------------------------------------------------+
string BuildTH3FrequencyLabelText(const double frequency) {
    static uint s_lastStepInfoMs = 0;
    static double s_lastStepInfoFreq = -1;
    static string s_cachedStepInfo = "";
    uint nowMs = GetTickCount();
    bool freqChanged = (frequency != s_lastStepInfoFreq);
    if(freqChanged || nowMs - s_lastStepInfoMs >= 5000) {
        s_lastStepInfoMs = nowMs;
        s_lastStepInfoFreq = frequency;
        s_cachedStepInfo = "";

        // PERF: Use pattern store instead of ObjectsTotal(OBJ_FIBO) loop
        // g_th3Patterns holds A,B,C,D — range = |pB - pA| (AB wave)
        int patCount = TH3PatternStoreCount();
        for(int i = 0; i < patCount; i++) {
            double p1 = g_th3Patterns.items[i].A.price;
            double p2 = g_th3Patterns.items[i].B.price;
            if(p1 <= 0 || p2 <= 0) continue;

            double rangePips = CalculatePipsDistance(p1, p2);
            double stepPips  = rangePips * (frequency / 100.0);
            if(stepPips > 0) {
                double stepCount = rangePips / stepPips;
                int    fullSteps = (int)MathFloor(stepCount);
                double remainder = stepCount - fullSteps;
                s_cachedStepInfo = StringFormat(" | AB = %d steps + %.2f x %.1f pips",
                    fullSteps, remainder, stepPips);
                break;
            }
        }

        // The step the ARRANGEMENT implies, alongside the one the percentage
        // cuts off. These are two different answers to "how big is a step": the
        // first is a share of AB, the second comes from the pattern's skeleton
        // (momentum band, cover depth, cover delay). Showing both is the point -
        // the skeleton reading is the one that can be checked against the market.
        for(int j = 0; j < patCount; j++) {
            if(!g_th3Patterns.items[j].skeleton.valid) continue;
            double skelStep = g_th3Patterns.items[j].skeleton.stepPips;
            if(skelStep <= 0) continue;
            s_cachedStepInfo += StringFormat(" | skeleton %0.1f pips (key %d)",
                                             skelStep, g_th3Patterns.items[j].skeleton.key);
            break;
        }
    }
    // The number is a MOVEMENT STEP, not a frequency. `frequency` is the name
    // the field carried when a step was expressed as "100/freq = N steps", and
    // a percentage label reads like a signal frequency — which it is not. It is
    // how far one step of the move is, so the label says so. The internal name
    // stays `frequency` deliberately: the GlobalVariable keys are
    // `Biotak_TH3Freq_<chart>` and `Biotak_TH3FreqIdx_<chart>`, and renaming
    // those would orphan every setting already saved on a live terminal.
    // P-TH3-THB (2026-09-19) — the CLOSED step (|C-B|/K, the unified formula)
    // rides beside the percentage when a pattern exists, so the label shows the
    // formula the ladder actually wears, not only the legacy AB cut.
    // P-TH3-INFO-05 (2026-09-21) — ONE LEG SHORT. This read passed the store's
    // A/B/C, which under P-TH3-D4's naming (TH3Pivots.mqh:1320: our A = their B,
    // our B = their C, our C = their D) is the wave's X/A/B, not its A/B/C. It
    // measured the RETRACEMENT leg instead of the closing one, so the label's
    // `closed` number never agreed with the ladder DrawABCDPattern actually
    // wears (TH3Renderer.mqh:549 and :1996 both pass B/C/D). A pattern whose
    // retrace is flat also fell past the K table's 0.75 floor and printed
    // nothing while the ladder carried a real closed step.
    string closedInfo = "";
    int closedCount = TH3PatternStoreCount();
    for(int c = 0; c < closedCount; c++) {
        double cs = 0, ck = 0, cr = 0;
        if(TH3ClosedStepFromLegs(g_th3Patterns.items[c].B.price,
                                 g_th3Patterns.items[c].C.price,
                                 g_th3Patterns.items[c].D.price, cs, ck, cr)) {
            closedInfo = StringFormat(" | closed %.1f pips (K=%.1f R=%.2f)",
                                      cs / GetCachedPipSize(), ck, cr);
            break;
        }
    }
    return StringFormat("[ TH3 Movement Step: %.3f%%%s%s ]", frequency,
                        closedInfo, s_cachedStepInfo);
}

//+------------------------------------------------------------------+
//| Update TH3 Frequency Label — RETIRED (P-TH3-INFO-07, 2026-09-21).|
//| The readout plate (TH3InfoFamilyDraw, TH3Renderer.mqh) is the ONE |
//| surface that says the step now, so this mode-stack label         |
//| (`[ TH3 Movement Step: ... ]`) is a second mouth in the OLD       |
//| format — and a mouth that AUTO-HIDES, which is exactly the user's |
//| «یکبار میاد ولی ... دیگه نمیشه». Every historical call site is a  |
//| cleanup point now: delete any legacy object, reset its clock,     |
//| draw nothing. (The 3/4 keys keep their log line + the panel row;  |
//| the F-hide/show writes on a missing name are documented no-ops.)  |
//+------------------------------------------------------------------+
void UpdateTH3FrequencyLabel(double frequency, bool clearFirst = true) {
    ObjectDelete(0, g_th3FreqLabelName);   // legacy sweep (no-op when absent)
    g_th3FreqLabelCreateTime = 0;
}
#endif   // TH3TOOL-ON: was #ifndef BUILD_LITE guard for the two functions above


//+------------------------------------------------------------------+
//| Show all status labels without changing modes                    |
//+------------------------------------------------------------------+
void ShowAllStatusLabels() {
    ClearAllModeLabels();
    
    // Show every info label, stacked (non-destructive updates)
    UpdateStepModeLabel(false);
    
    // Factor info only applies in Factor mode - don't show it in other
    // modes (the values would be irrelevant to what is actually drawn).
    if(GetCurrentStepMode() == FACTOR_STEP) {
        double factorVal = 0;
        double stepVal = 0;
        double basePrice = (g_dailyClosePriceForTH > 0) ? g_dailyClosePriceForTH : Bid;
        ComputeFactorModeValues(basePrice, factorVal, stepVal);
        UpdateFactorLabel(factorVal, stepVal, false);
    }
    // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
#ifndef BUILD_LITE
    // TH3 frequency info belongs to the TH3 tool - only show it when the
    // tool is enabled (UpdateTH3FrequencyLabel also gates internally).
    if(inpEnableTH3Tool) {
        double freq = (g_th3FreqOverride > 0) ? g_th3FreqOverride : inpTH3BaseStepPercent;
        UpdateTH3FrequencyLabel(freq, false);
    }
#endif
    UpdateLockStatusLabel();
}

//+------------------------------------------------------------------+
//| Real-time refresh of currently visible info labels               |
//| Called from OnTimer (1s cadence). Updates text in place ONLY     |
//| when it changed - never recreates objects, never resets expiry   |
//| timestamps, so auto-hide and CPU usage stay correct.             |
//+------------------------------------------------------------------+
void RefreshVisibleStatusLabels() {
    if(!inpShowModeChangeLabel) return;
    if(IsIndicatorHidden()) return;
    
    // Step-mode label (mode + current step in pips)
    if(ObjectFind(0, g_stepModeLabelName) >= 0) {
        SetLabelTextIfChanged(g_stepModeLabelName, BuildUnifiedModeLabelText());
    }
    
    // Factor label (F + Step) - only relevant while in Factor mode
    if(GetCurrentStepMode() == FACTOR_STEP) {
        if(ObjectFind(0, g_factorLabelName) >= 0) {
            double factorVal = 0;
            double stepVal = 0;
            double basePrice = (g_dailyClosePriceForTH > 0) ? g_dailyClosePriceForTH : Bid;
            ComputeFactorModeValues(basePrice, factorVal, stepVal);
            // P-UI-98: the step override is the drawn truth here too. In DIRECT
            // display mode the factor NUMBER is derived from the step, so it is
            // re-derived from the overridden step to keep the pair honest; in
            // CLASSIC mode the factor number IS the input and only the pips move.
            double s1F = StepOverrideFactor();
            if(s1F != 1.0 && stepVal > 0.0) {
                stepVal *= s1F;
                if(inpFactorDisplayMode == FACTOR_DISPLAY_DIRECT) {
                    double s1ReFactor = CalculateFactorFromStep(GetFactorRange(), stepVal);
                    if(s1ReFactor > 0.0)
                        factorVal = NormalizeDouble(MathMax(0.01, MathMin(10000, s1ReFactor)), 2);
                }
            }
            SetLabelTextIfChanged(g_factorLabelName, BuildFactorLabelText(factorVal, stepVal));
        }
    } else {
        // Not in Factor mode: remove any lingering factor label
        if(ObjectFind(0, g_factorLabelName) >= 0) {
            ObjectDelete(0, g_factorLabelName);
            g_factorLabelCreateTime = 0;
        }
    }
    
    // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
#ifndef BUILD_LITE
    // TH3 frequency label (frequency + step info) - only when tool enabled
    if(inpEnableTH3Tool) {
        if(ObjectFind(0, g_th3FreqLabelName) >= 0) {
            double freq = (g_th3FreqOverride > 0) ? g_th3FreqOverride : inpTH3BaseStepPercent;
            SetLabelTextIfChanged(g_th3FreqLabelName, BuildTH3FrequencyLabelText(freq));
        }
    } else {
        // Tool disabled: remove any lingering TH3 label
        if(ObjectFind(0, g_th3FreqLabelName) >= 0) {
            ObjectDelete(0, g_th3FreqLabelName);
            g_th3FreqLabelCreateTime = 0;
        }
    }
#endif
}

//+------------------------------------------------------------------+
//| Create Mid-Range Zone (Generic function for all modes)          |
//|                  (                         )                     |
//| Logic: Draw zone with specified height around midpoint          |
//| Compatible with CreateFactorMidZone logic                        |
//| @param zoneName - Unique name for zone object                   |
//| @param prevPrice - Previous level price                         |
//| @param currentPrice - Current level price                       |
//| @param zoneHeight - Height of zone ( from midpoint)             |
//| @param zoneColor - Color of zone                                |
//| @param transparency - Transparency (0-100)                      |
//+------------------------------------------------------------------+
//| Create Generic Mid Zone - GOLD VERSION v2                        |
//|       Zone             -            v2                           |
//|                                                                  |
//| ARCHITECTURE: Delegates to ZoneFactory with comprehensive        |
//| validation, error handling, and NO unnecessary deletion          |
//|                                                                  |
//| IMPROVEMENTS v2:                                                 |
//| - REMOVED unnecessary object deletion (let factory handle it)   |
//| - Factory will UPDATE existing objects (more efficient)         |
//| - Better error messages with context                            |
//| - Consistent error handling                                     |
//+------------------------------------------------------------------+
bool CreateGenericMidZone(const string zoneName, const double prevPrice, const double currentPrice,
                          const double zoneHeight, const color zoneColor, const int transparency)
{
    //                                                                
    // PHASE 1: QUICK VALIDATION (Fail Fast)
    //                                                                
    if(StringLen(zoneName) == 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  CreateGenericMidZone: Empty zone name");
        #endif
        return false;
    }
    
    if(prevPrice <= 0 || currentPrice <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  CreateGenericMidZone: Invalid prices - Prev=", DoubleToString(prevPrice, Digits), 
              ", Current=", DoubleToString(currentPrice, Digits));
        #endif
        return false;
    }
    
    if(prevPrice == currentPrice) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("   CreateGenericMidZone: Prices are equal - no zone needed");
        #endif
        return false;
    }
    
    if(zoneHeight <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  CreateGenericMidZone: Invalid zone height: ", DoubleToString(zoneHeight, Digits));
        #endif
        return false;
    }
    
    //                                                                
    // PHASE 2: CALCULATE ZONE BOUNDARIES (Optimized)
    //                                                                
    
    // Calculate midpoint between previous and current
    double midPoint = (prevPrice + currentPrice) / 2.0;
    
    // Calculate zone boundaries ( zoneHeight from midpoint)
    // OPTIMIZATION: Single NormalizeDouble call per value
    double upperPrice = NormalizeDouble(midPoint + zoneHeight, Digits);
    double lowerPrice = NormalizeDouble(midPoint - zoneHeight, Digits);
    
    // Validate zone boundaries
    if(upperPrice <= lowerPrice) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  CreateGenericMidZone: Invalid zone boundaries - Upper=", DoubleToString(upperPrice, Digits), 
              ", Lower=", DoubleToString(lowerPrice, Digits));
        #endif
        return false;
    }
    
    //                                                                
    // PHASE 3: DELEGATE TO ZONE FACTORY (Centralized Creation)
    // OPTIMIZATION: Let factory handle update vs create decision
    //                                                                
    
    SZoneCreationRequest request = ZoneRequestNew();   // P-UI-131h
    request.name = zoneName;
    request.topPrice = upperPrice;
    request.bottomPrice = lowerPrice;
    request.zoneColor = zoneColor;
    request.transparency = transparency;
    // P-UI-63: this path draws a BAND only (filled = true, so no edge is produced), but
    // the field is written anyway: a stack struct must never leave a value to chance.
    request.borderTransparency = inpMidZoneBorderTransparency;
    // P-UI-131h: a band-only picture draws no edge, so the four half-surfaces are inert
    // here - written anyway, because a stack struct must never leave a value to chance.
    request.borderTopColor = inpZoneEdgeTopColor;
    request.borderBottomColor = inpZoneEdgeBottomColor;
    request.borderTopTransparency = inpZoneEdgeTopTransparency;
    request.borderBottomTransparency = inpZoneEdgeBottomTransparency;
    request.filled = true;
    request.borderStyle = inpMidZoneBorderStyle;
    request.borderWidth = inpMidZoneBorderWidth;
    request.startTime = 0;  // Auto-calculate
    request.endTime = 0;    // Auto-calculate
    
    SZoneCreationResult result = CreateZone(request);
    
    if(!result.success) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  CreateGenericMidZone: Factory failed for '", zoneName, "' - ", result.errorMessage, 
              " (Code: ", result.errorCode, ")");
        #endif
        return false;
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("  CreateGenericMidZone: Created/Updated '", zoneName, "' [", 
          DoubleToString(lowerPrice, Digits), " - ", DoubleToString(upperPrice, Digits), "]");
    #endif
    
    return true;
}

//+------------------------------------------------------------------+
//| Throttled ChartRedraw() to prevent excessive CPU usage           |
//| GOLD FIX: Prevents rapid ChartRedraw calls in OnChartEvent      |
//+------------------------------------------------------------------+
void ThrottledChartRedraw(bool forceRedraw = false) {
    uint nowMs = GetTickCount();
    if(forceRedraw) {
        ChartRedraw();
        g_lastChartRedrawTime = nowMs;
        return;
    }
    if(IsIndicatorHidden()) return;
    if(nowMs - g_lastChartRedrawTime > CHART_REDRAW_THROTTLE_MS) {
        ChartRedraw();
        g_lastChartRedrawTime = nowMs;
    }
}

//+------------------------------------------------------------------+
//| P-UI-75b: THE DRAG'S OWN FRAME.                                  |
//|                                                                  |
//| A live drag writes a batch of coordinates and owes exactly ONE   |
//| repaint per applied batch. ThrottledChartRedraw() is a 100 ms    |
//| TICK throttle, so the two gates never composed: the card's        |
//| coordinates landed 30x/s while the chart was painted 10x/s and    |
//| the card visibly jumped behind the cursor. The DRAG's own window  |
//| is the coalescer now (PNL_MOVE_FRAME_* in BiotakPanels), so this  |
//| owner is reachable once per batch and ONLY while a live grab owns |
//| the pointer - never from the tick path, never per mouse event.    |
//| Cost when idle: zero (no caller runs).                           |
//|                                                                  |
//| PANELDRAG-OFF (2026-09-14) retired the card-move gesture and left |
//| this owner UNCALLED; P-UI-127 (2026-09-25, user order: «پنل رو هم  |
//| بشه درگ کرد») restored the gesture, so it is called again — once  |
//| per applied batch of a live drag, and nothing else.               |
//+------------------------------------------------------------------+
void DragFrameRedraw() {
    ChartRedraw();
    // The frame WE just paid for counts for the tick throttle too, so the
    // tick cannot immediately re-paint the same picture (P-PERF-06's rule).
    g_lastChartRedrawTime = GetTickCount();
}

//+------------------------------------------------------------------+
//| P-PERF-24: DISCRETE ACTION PAINT (toggle / key / one row press)  |
//|                                                                  |
//| ThrottledChartRedraw() is the right owner for the TICK path - it  |
//| exists so price vibration cannot hammer the terminal. But every   |
//| VISIBILITY toggle (L key, SHOW LINES, the trigger/mid-zone show   |
//| rows) ended its work with the THROTTLED call, and that call has   |
//| two ways to swallow the feedback:                                  |
//|   - inside CHART_REDRAW_THROTTLE_MS (100 ms) of any earlier repaint|
//|     it returns without painting - and the frame that follows a     |
//|     toggle is usually a tick whose `hasPendingWork` is already     |
//|     false, so nothing repaints until the NEXT tick's redraw;       |
//|   - while the indicator is hidden it returns unconditionally.      |
//| The user presses a switch and the chart changes when the market    |
//| decides to tick - that IS "toggling the levels takes ages".        |
//|                                                                    |
//| A discrete action is ONE event, never a stream: forcing the paint  |
//| here cannot hammer anything (the F key already did exactly this    |
//| with a bare ChartRedraw() and documented why). Keep callers to     |
//| real USER actions - never the tick, never a drag loop.            |
//+------------------------------------------------------------------+
void RepaintForDiscreteAction() {
    ThrottledChartRedraw(true);
}

//+------------------------------------------------------------------+
//| Clear a single temporary label by name and reset its timestamp  |
//+------------------------------------------------------------------+
void ClearSingleModeLabel(const string labelName, uint &createTime) {
    if(ObjectFind(0, labelName) >= 0)
        ObjectDelete(0, labelName);
    createTime = 0;
}

//+------------------------------------------------------------------+
//| Check and clear expired labels (called from OnTimer)            |
//| Returns true if any labels remain (timer should continue)       |
//+------------------------------------------------------------------+
bool CheckAndClearExpiredLabels() {
    uint now = GetTickCount();
    // P-UI-57d: clamp BEFORE the cast, not after. `inpModeLabelDuration` is an int
    // input that ValidateInputs does not cover, so a negative or oversized value
    // wrapped right here: (uint)(-1) * 1000 = 4294966296 ms, about 49.7 days, and a
    // label the user expected to vanish in seconds outlived the session. 0 is left
    // as 0 - "never expire" - which the `durationMs > 0` test below already honours.
    int durSec = inpModeLabelDuration;
    if(durSec < 0) durSec = 0;
    if(durSec > 86400) durSec = 86400;          // one day is the sane ceiling
    uint durationMs = (uint)durSec * 1000;
    bool anyRemaining = false;
    bool anyCleared = false;

    if(durationMs > 0) {
        // P-UI-57f-OFF (2026-09-22): the step-mode (SS/LS) row's clock
        // exemption is retired by user order — «لیبل مود ها ... باید بعد چند
        // ثانیه حذف بشن هرچی که اطلاعاتی هستش». EVERY info row is a timed
        // visitor now: the step-mode row expires on the same
        // inpModeLabelDuration the event rows always kept, and a real change
        // (a mode press, a refresh that recreates the object) re-arms it
        // through its creation timestamp, exactly as before.
        if(g_stepModeLabelCreateTime > 0) {
            if((now - g_stepModeLabelCreateTime) >= durationMs) {
                ClearSingleModeLabel(g_stepModeLabelName, g_stepModeLabelCreateTime);
                anyCleared = true;
            } else {
                anyRemaining = true;
            }
        }
        if(g_factorLabelCreateTime > 0) {
            if((now - g_factorLabelCreateTime) >= durationMs) {
                ClearSingleModeLabel(g_factorLabelName, g_factorLabelCreateTime);
                anyCleared = true;
            } else {
                anyRemaining = true;
            }
        }
#ifndef BUILD_LITE
        if(g_th3FreqLabelCreateTime > 0) {
            if((now - g_th3FreqLabelCreateTime) >= durationMs) {
                ClearSingleModeLabel(g_th3FreqLabelName, g_th3FreqLabelCreateTime);
                anyCleared = true;
            } else {
                anyRemaining = true;
            }
        }
#endif
        if(g_lockStatusLabelCreateTime > 0) {
            // Lock status is a persistent status: stays visible while locked.
            if(g_timeframeLocked) {
                anyRemaining = true;
            } else if((now - g_lockStatusLabelCreateTime) >= durationMs) {
                ClearSingleModeLabel(g_lockStatusLabelName, g_lockStatusLabelCreateTime);
                anyCleared = true;
            } else {
                anyRemaining = true;
            }
        }
    } else {
        bool labelsExist = (g_stepModeLabelCreateTime > 0 || g_factorLabelCreateTime > 0 || g_lockStatusLabelCreateTime > 0);
#ifndef BUILD_LITE
        labelsExist = labelsExist || (g_th3FreqLabelCreateTime > 0);
#endif
        if(labelsExist)
            RepositionAllOverlayLabels();
        anyRemaining = false;
    }

    if(g_resetCommentCreateTime > 0) {
        if((now - g_resetCommentCreateTime) >= 2000) {
            Comment("");
            g_resetCommentCreateTime = 0;
            anyCleared = true;
        } else {
            anyRemaining = true;
        }
    }

    if(anyCleared)
        RepositionAllOverlayLabels();

    return anyRemaining;
}

//+------------------------------------------------------------------+
//| Get Y row offset for a specific label type (stacked vertically) |
//+------------------------------------------------------------------+
int GetModeLabelRowOffset(const string labelName) {
    int rowHeight = inpModeLabelFontSize + 12;
    if(labelName == g_stepModeLabelName)  return 0;
    if(labelName == g_factorLabelName) {
        int row = 0;
        if(g_stepModeLabelCreateTime > 0) row++;
        return row * rowHeight;
    }
#ifndef BUILD_LITE
    if(labelName == g_th3FreqLabelName) {
        int row = 0;
        if(g_stepModeLabelCreateTime > 0) row++;
        if(g_factorLabelCreateTime > 0) row++;
        return row * rowHeight;
    }
#endif
    if(labelName == g_lockStatusLabelName) {
        int row = 0;
        if(g_stepModeLabelCreateTime > 0) row++;
        if(g_factorLabelCreateTime > 0) row++;
#ifndef BUILD_LITE
        if(g_th3FreqLabelCreateTime > 0) row++;
#endif
        return row * rowHeight;
    }
    return 0;
}

//+------------------------------------------------------------------+
//| Get total height of ALL active mode labels (for stacking below) |
//+------------------------------------------------------------------+
int GetModeLabelBlockHeight() {
    int activeCount = 0;
    if(g_stepModeLabelCreateTime > 0) activeCount++;
    if(g_factorLabelCreateTime > 0) activeCount++;
#ifndef BUILD_LITE
    if(g_th3FreqLabelCreateTime > 0) activeCount++;
#endif
    if(g_lockStatusLabelCreateTime > 0) activeCount++;
    int rowHeight = inpModeLabelFontSize + 12;
    return activeCount * rowHeight;
}

//+------------------------------------------------------------------+
//| Apply standard style to an overlay mode label                   |
//+------------------------------------------------------------------+
void ApplyModeLabelStyle(const string name, const color textColor, const int yOffsetExtra = 0) {
    ObjectSetInteger(0, name, OBJPROP_CORNER, inpModeLabelCorner);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, inpModeLabelXDistance);
    int rowOffset = GetModeLabelRowOffset(name);
    
    int finalY = inpModeLabelYDistance + yOffsetExtra + rowOffset;
    
    // Smart stacking: Avoid overlapping with ATR (top) or TH (bottom) labels
    if(inpModeLabelCorner == CORNER_LEFT_UPPER || inpModeLabelCorner == CORNER_RIGHT_UPPER) {
        // Offset for top-aligned corners (below ATR labels)
        finalY += g_modeLabelYOffset + 45; 
    } else {
        // Offset for bottom-aligned corners (above TH labels)
        finalY += g_currentLabelYOffsetBottom + inpTHLabelsMarginBottom + 15;
    }
    
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, finalY);
    ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
    ObjectSetString(0, name, OBJPROP_FONT, inpFontName);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, inpModeLabelFontSize);
    ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
    // P-TH3-INFO-09: the BACK flag is owned here like every other property the
    // style writes — a stale label with BACK=true paints behind the chart art
    // and reads as "the label does not show" (the all-labels check the user
    // asked for: «برای تمام لیبل ها چک بکنش»).
    ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

//+------------------------------------------------------------------+
//| Unified repositioning for ALL overlay labels                     |
//| Call after g_modeLabelYOffset changes to keep layout consistent  |
//+------------------------------------------------------------------+
void RepositionAllOverlayLabels() {
    if(ObjectFind(0, g_stepModeLabelName) >= 0)
        ApplyModeLabelStyle(g_stepModeLabelName, (color)ObjectGetInteger(0, g_stepModeLabelName, OBJPROP_COLOR));
    if(ObjectFind(0, g_factorLabelName) >= 0)
        ApplyModeLabelStyle(g_factorLabelName, (color)ObjectGetInteger(0, g_factorLabelName, OBJPROP_COLOR));
#ifndef BUILD_LITE
    if(ObjectFind(0, g_th3FreqLabelName) >= 0)
        ApplyModeLabelStyle(g_th3FreqLabelName, (color)ObjectGetInteger(0, g_th3FreqLabelName, OBJPROP_COLOR));
#endif
    if(ObjectFind(0, g_lockStatusLabelName) >= 0)
        ApplyModeLabelStyle(g_lockStatusLabelName, (color)ObjectGetInteger(0, g_lockStatusLabelName, OBJPROP_COLOR));

    UpdateLockStatusLabel(false);
    // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
#ifndef BUILD_LITE
    RepositionABCDInfoLabels();
#endif
}

// ══════════════════════════════════════════════════════════════════════════
// P-UI-100 (2026-09-22) — SELECTION HYGIENE OF THE TWO HAND-SET LINES.
//
// REPORTED: «وقتی فیو یا باکس از همون محل میکشم کاستوم پرایس جابجا میشه» — the
// custom price line moves, and with it the whole ladder (every level is derived
// from its price), while the user draws a fib or a box somewhere else.
//
// THE LAW, measured in this project twice already (P-UI-45 on the line,
// P-BK-26 on the box): an MT4 drag does not move the object under the cursor,
// it moves EVERY SELECTED OBJECT. A hand-set line that is SELECTED when somebody
// else's gesture begins is therefore carried by that gesture — our own box draw,
// MT4's fib tool, a panel drag, a pan — and its price lands wherever the foreign
// gesture ended.
//
// WHY THIS IS OURS TO KEEP: both lines are INVISIBLE by design (P-UI-98p), and
// MT4 cannot select an object it does not paint. Every selection they can wear
// was written by US — P-UI-49d's claim, which hands the movement to the
// terminal. That makes the invariant one sentence, and this module its one home:
//
//   A hand-set line is SELECTED only while a gesture of OURS owns it.
//
// Everything else is stale by definition. Three owners, one per direction:
//   * `HandLineDropSelection`    — the ONE writer of "this line is not selected".
//   * `HandLinesSelectionGuard`  — drop every hand-set line that no live gesture
//     of ours owns. Called by the gesture STARTS of every layer that can begin
//     one (the box tool, the TH3 band, the panel finalizer, the custom-price
//     press edge) and by the 250 ms net for the paths we do not see at all.
//     `HandLinesDropAll` is the same drop without the question, for the presses
//     another layer provably owns.
//   * `HandLinesRestorePrice`    — put a line back where the user left it, for
//     the one case no guard can prevent: a press that lands ON a line and then
//     turns out to be a DRAW (P-UI-100b, EventHandlers).
//
// Cost: three name compares plus a guarded read per line, and a write only on
// drift. Every caller gates the call behind a gesture of its own or the timer,
// so no pointer-rate path pays for it.
// ══════════════════════════════════════════════════════════════════════════

// The ONE writer of "this line is not selected". A line that is absent, or not
// selected, costs two reads and no terminal write (the guarded-write law this
// project follows everywhere).
void HandLineDropSelection(const string name)
{
   if(name == "") return;
   if(ObjectFind(0, name) < 0) return;
   if(!(bool)ObjectGetInteger(0, name, OBJPROP_SELECTED)) return;
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
}

// Is a gesture of OURS holding the custom price line right now? The
// `g_...NativeDrag` flag is deliberately NOT in the test: it means "a gesture is
// in flight and the clear is owed to its release" — the FOREIGN case (P-UI-96),
// never ours.
bool CustomPriceLineGestureLive()
{
   return g_customPriceLineDragging;
}

// Is a gesture of OURS holding the step-1 pair? Both channels count: the claim's
// own carry (P-UI-98e) and the terminal's per-object drag (P-UI-98 OBJECT_DRAG).
bool Step1LinesGestureLive()
{
   return (g_s1DragLive || g_s1OwnActive);
}

// Drop the selection of every hand-set line THIS gesture does not own. Each line
// is asked separately because the two gestures are independent: dragging the
// custom price line must not leave a stale selection on the red handles (they
// would ride along with it), and vice versa.
void HandLinesSelectionGuard()
{
   if(!CustomPriceLineGestureLive() && g_customPriceLineCreated)
      HandLineDropSelection(g_customPriceHorizontalLineName);
   if(!Step1LinesGestureLive())
   {
      HandLineDropSelection(g_s1MarkAboveName);
      HandLineDropSelection(g_s1MarkBelowName);
   }
}

#endif // UTIL_A_MQH
