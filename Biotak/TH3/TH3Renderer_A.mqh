// TH3Renderer_A.mqh - TH3Renderer.mqh split 2026-09-29: exact lines 10-968, byte-identical, zero renames.
#ifndef TH3_RENDERER_A_MQH
#define TH3_RENDERER_A_MQH

#property strict

// P-TH3-LOG1 ring (file scope: one slot per recent pattern; a redraw that
// re-derives the same verdict logs nothing, a new verdict logs once).
static string s_th3LogPat[8];
static string s_th3LogKey[8];
static int    s_th3LogPos = 0;

// P-TH3-LOG2 (2026-09-22) -- THE PROJECT LOG FOLDER, WITHOUT COPY-PASTE.
// Every verdict is appended to TH3LOG_<symbol>_<tf>.csv in the terminal's
// MQL4/Files (the MT4 sandbox answers nowhere else); tools/pull-th3log.ps1
// copies them into the repo's th3logs/. Same line shape as the Experts Print,
// so tools/th3_log_collect.py reads both. Runs on verdicts only (rare).
void TH3LogFileAppend(const string line)
{
    string sym = Symbol();
    string safe = "";
    for(int i = 0; i < StringLen(sym); i++)
    {
        ushort ch = StringGetCharacter(sym, i);
        bool okc = ((ch >= '0' && ch <= '9') || (ch >= 'A' && ch <= 'Z') ||
                    (ch >= 'a' && ch <= 'z'));
        safe += (okc ? StringSubstr(sym, i, 1) : "_");
    }
    string fn = StringFormat("TH3LOG_%s_%d.csv", safe, Period());
    int h = FileOpen(fn, FILE_READ | FILE_WRITE | FILE_TXT);
    if(h < 0) return;
    if(FileSize(h) == 0)
        FileWriteString(h, "# pat,chart,st,R,closed,K,rung,owner,q,pb,synth,macro,lock,step,proof,deep\n");
    FileSeek(h, 0, SEEK_END);
    FileWriteString(h, line + "\n");
    FileClose(h);
}

//+------------------------------------------------------------------+
//| Calculate AB=CD Point D (with 9-level validation)               |
//|       D       9                                |
//| Rule: AB distance = CD distance (equal price movement)          |
//+------------------------------------------------------------------+
//|      AB=CD     TH3                                    |
//| User provides A, B, C     System calculates D                      |
//| Targets (Step1/3/5/7) start from C (not D)                       |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| P-TH3-PERF-01 (2026-09-19) — THE AVERAGE CANDLE SIZE IS CACHED   |
//| PER BAR, NOT PER REDRAW.                                         |
//|                                                                   |
//| DrawABCDPattern runs on EVERY drag event and once per pattern in   |
//| UpdateAllTH3Objects, and it used to walk 20 bars (20 iHigh + 20    |
//| iLow terminal reads) each time just to place a label. The answer   |
//| only moves when a new bar opens, so it is computed once per bar    |
//| and reused: a drag that fires N times now costs those 40 reads     |
//| ONCE instead of 40 x N.                                           |
//+------------------------------------------------------------------+
double TH3AvgCandleSize()
{
   static datetime s_avgBar = 0;
   static double   s_avg    = 0.0;
   datetime nowBar = iTime(NULL, 0, 0);
   if(nowBar != s_avgBar || s_avg <= 0.0)
   {
      const int lookback = 20;
      double sum = 0.0;
      for(int k = 0; k < lookback; k++)
         sum += (iHigh(NULL, 0, k) - iLow(NULL, 0, k));
      s_avg    = sum / (double)lookback;
      s_avgBar = nowBar;
   }
   return s_avg;
}

//+------------------------------------------------------------------+
//| P-TH3-INFO-04 (2026-09-20) — THE READOUT PLATE: ONE LANGUAGE.     |
//|                                                                  |
//| The leg meter prints its three lines INSIDE a dark plate with a   |
//| hairline border (P-LM-01). The user's ask is that the AB=CD       |
//| caption read the SAME way — one tool, one visual language: the    |
//| same plate ink, the same padding, the same row grid, the same     |
//| MEASURED (never guessed) size, and the same near-white rows with  |
//| the live number on the accent row. Two surfaces spelling those    |
//| numbers themselves is exactly how a tool ends up with two looks,  |
//| so the plate's INK, its METRICS and its WRITERS have ONE owner    |
//| here and both surfaces ask for them:                              |
//|                                                                  |
//|   * TH3ROPlateW/TH3ROPlateH measure the plate off the very        |
//|     strings it carries (`PnlRawTextW`/`PnlRawLineH`, the          |
//|     chart-label grid — the measurement the BaseKnot note plate    |
//|     uses too), never off a literal;                              |
//|   * TH3ROPlateAt creates the plate ONCE, then ever only writes a  |
//|     value that CHANGED (P-PERF-02);                              |
//|   * TH3RORowAt is the row writer: font size, text, ink and place  |
//|     in one guarded pass;                                          |
//|   * TH3RORowY/TH3ROPlateY decide the block's geometry, because    |
//|     MT4 anchors a corner object's distance on the edge nearest    |
//|     that corner — a readout hangs DOWN from its top Y in an upper |
//|     corner and UP in a lower one, and the plate must agree with   |
//|     its own rows in all four.                                    |
//|                                                                  |
//| The plate is created BEFORE the ink it carries: MT4 ties equal    |
//| ZORDER by CREATION ORDER, so a row older than its plate would be  |
//| painted UNDER it — a plate covering its own text. Any surface     |
//| that finds the plate missing therefore rebuilds its rows (see     |
//| TH3InfoFamilyDraw and LegMeasureUpgradeLegacy).                   |
//|                                                                  |
//| The inks are deliberately NOT run through TH3InkForChart: the     |
//| plate is a FIXED dark ink on every theme, so a theme-flipped row  |
//| would be the one thing a readout cannot be — unreadable. The ink  |
//| TABLE itself lives with the ink owner (`TH3Controller.mqh`, the   |
//| `TH3RO_*` palette + `TH3ReadoutInk`), so both readouts ask one    |
//| table for what a row wears. What lives here is the plate's        |
//| LAYOUT — its padding, its row grid and its writers.               |
//+------------------------------------------------------------------+
#define TH3RO_PAD_X    10                 // px of plate on each side of the ink
#define TH3RO_PAD_Y    5
#define TH3RO_LINE_GAP 5                  // px between two readout rows
#define TH3RO_FONT_PT  9                  // the reference box's own text size

int TH3ROLineH(const int fontPt) { return PnlRawLineH(fontPt); }
int TH3RORowH(const int fontPt)  { return TH3ROLineH(fontPt) + TH3RO_LINE_GAP; }

// The plate's height for `rows` rows of ink, padding included.
int TH3ROPlateH(const int rows, const int fontPt)
{
    if(rows <= 0) return 2 * TH3RO_PAD_Y;
    return rows * TH3ROLineH(fontPt) + (rows - 1) * TH3RO_LINE_GAP + 2 * TH3RO_PAD_Y;
}

// The plate's width is the WIDEST row it carries — measured, not guessed.
int TH3ROPlateW(const string &rows[], const int n, const int fontPt)
{
    int bw = 2 * TH3RO_PAD_X + 8;   // a one-character row still gets a plate
    for(int i = 0; i < n; i++)
    {
        if(StringLen(rows[i]) == 0) continue;
        int w = PnlRawTextW(rows[i], fontPt) + 2 * TH3RO_PAD_X;
        if(w > bw) bw = w;
    }
    return bw;
}

// ── the block's own geometry: ONE owner for rows and plate ──────────
bool TH3ROLowerCorner(const ENUM_BASE_CORNER corner)
{
    return (corner == CORNER_LEFT_LOWER || corner == CORNER_RIGHT_LOWER);
}

// Row `row` of a block whose near edge (its first row, top-down) is at `topY`.
int TH3RORowY(const int topY, const int row, const int fontPt, const ENUM_BASE_CORNER corner)
{
    int rowH = TH3RORowH(fontPt);
    if(TH3ROLowerCorner(corner)) return topY - row * rowH;   // a lower corner's y grows UP
    return topY + row * rowH;
}

// The plate's y: PAD_Y BEYOND the block's near edge, on whichever side that is.
int TH3ROPlateY(const int topY, const int rows, const int fontPt, const ENUM_BASE_CORNER corner)
{
    int nearRow = TH3ROLowerCorner(corner) ? rows - 1 : 0;
    return TH3RORowY(topY, nearRow, fontPt, corner) - TH3RO_PAD_Y;
}

// The plate's x: the same rule on the other axis — a right corner's distance is
// measured from the right edge, so there the plate grows to the RIGHT of the ink.
int TH3ROPlateX(const int nearX, const ENUM_BASE_CORNER corner)
{
    if(corner == CORNER_RIGHT_UPPER || corner == CORNER_RIGHT_LOWER)
        return nearX + TH3RO_PAD_X;
    return nearX - TH3RO_PAD_X;
}

// ── change-guarded writers (P-PERF-02) ─────────────────────────────
void TH3ROSetXy(const string nm, const int x, const int y)
{
    if(ObjectFind(0, nm) < 0) return;
    if((int)ObjectGetInteger(0, nm, OBJPROP_XDISTANCE) != x) ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
    if((int)ObjectGetInteger(0, nm, OBJPROP_YDISTANCE) != y) ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
}

void TH3ROSetWh(const string nm, const int w, const int h)
{
    if(ObjectFind(0, nm) < 0) return;
    if((int)ObjectGetInteger(0, nm, OBJPROP_XSIZE) != w) ObjectSetInteger(0, nm, OBJPROP_XSIZE, w);
    if((int)ObjectGetInteger(0, nm, OBJPROP_YSIZE) != h) ObjectSetInteger(0, nm, OBJPROP_YSIZE, h);
}

// Y only — the reposition pass moves a whole block without re-measuring it.
void TH3ROSetY(const string nm, const int y)
{
    if(ObjectFind(0, nm) < 0) return;
    if((int)ObjectGetInteger(0, nm, OBJPROP_YDISTANCE) != y) ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
}

void TH3ROSetCorner(const string nm, const ENUM_BASE_CORNER corner)
{
    if(ObjectFind(0, nm) < 0) return;
    if((int)ObjectGetInteger(0, nm, OBJPROP_CORNER) != (int)corner)
        ObjectSetInteger(0, nm, OBJPROP_CORNER, corner);
}

// Place — and, on the first call, CREATE — the plate at its own top-left corner.
void TH3ROPlateAt(const string plate, const ENUM_BASE_CORNER corner,
                  const int x, const int y, const int w, const int h,
                  const bool create, const string tooltip)
{
    if(create && ObjectFind(0, plate) < 0)
    {
        if(!ObjectCreate(0, plate, OBJ_RECTANGLE_LABEL, 0, 0, 0)) return;
        ObjectSetInteger(0, plate, OBJPROP_BORDER_TYPE, BORDER_FLAT);
        ObjectSetInteger(0, plate, OBJPROP_STYLE,       STYLE_SOLID);
        ObjectSetInteger(0, plate, OBJPROP_WIDTH,       1);
        ObjectSetInteger(0, plate, OBJPROP_COLOR,       TH3RO_EDGE);
        ObjectSetInteger(0, plate, OBJPROP_BGCOLOR,     TH3RO_FILL);
        ObjectSetInteger(0, plate, OBJPROP_BACK,        false);
        ObjectSetInteger(0, plate, OBJPROP_SELECTABLE,  false);
        ObjectSetInteger(0, plate, OBJPROP_HIDDEN,      true);
        ObjectSetInteger(0, plate, OBJPROP_ZORDER,      Z_TH3_RO_PLATE);
        ObjectSetString( 0, plate, OBJPROP_TOOLTIP,     tooltip);
    }
    if(ObjectFind(0, plate) < 0) return;
    TH3ROSetCorner(plate, corner);
    TH3ROSetXy(plate, x, y);
    TH3ROSetWh(plate, w, h);
    // P-TH3-INFO-09: the same re-owning the rows got — a plate some stale
    // writer left with BACK=true slides under every label on the chart.
    if((bool)ObjectGetInteger(0, plate, OBJPROP_BACK))
        ObjectSetInteger(0, plate, OBJPROP_BACK, false);
}

// One row of ink: created on the first call, then only moved and re-inked.
// WHICH ink it wears is not this writer's question — it asks the palette owner
// (TH3ReadoutInk), so the leg meter's box and the AB=CD caption cannot end up
// with two different ideas of what the live row looks like.
bool TH3RORowAt(const string nm, const string txt, const ENUM_BASE_CORNER corner,
                const int x, const int y, const int fontPt,
                const int row, const int rowCount, const bool create)
{
    if(create && ObjectFind(0, nm) < 0)
    {
        if(!ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0)) return false;
        ObjectSetString( 0, nm, OBJPROP_FONT,       BioChromeFont());
        ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);
        ObjectSetInteger(0, nm, OBJPROP_ZORDER,     Z_TH3_RO_TEXT);
    }
    if(ObjectFind(0, nm) < 0) return false;
    color rowInk = TH3ReadoutInk(row, rowCount);
    TH3ROSetCorner(nm, corner);
    if((int)ObjectGetInteger(0, nm, OBJPROP_FONTSIZE) != fontPt)
        ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, fontPt);
    if(ObjectGetString(0, nm, OBJPROP_TEXT) != txt)
        ObjectSetString(0, nm, OBJPROP_TEXT, txt);
    if((color)ObjectGetInteger(0, nm, OBJPROP_COLOR) != rowInk)
        ObjectSetInteger(0, nm, OBJPROP_COLOR, rowInk);
    // P-TH3-INFO-09: the BACK flag is re-owned here, not just at creation — a
    // row a PRE-INFO-09 build (or any stale writer) left with BACK=true paints
    // BEHIND its own plate: the reported «متن داخل کادر سیاه دیده نمیشه» (the
    // plate renders, the ink is under it). Guarded write, one read per row.
    if((bool)ObjectGetInteger(0, nm, OBJPROP_BACK))
        ObjectSetInteger(0, nm, OBJPROP_BACK, false);
    TH3ROSetXy(nm, x, y);
    return true;
}

//+------------------------------------------------------------------+
//| P-TH3-INFO-01 (2026-09-20) — THE CAPTION IS WRAPPED, NOT CLIPPED.|
//|                                                                  |
//| MT4 truncates an object's text at 63 CHARACTERS. It is not a     |
//| MT4 quirk to be worked around once and forgotten; it is a CLIFF   |
//| that every caption added to walks off silently. The user's report |
//| was exactly that: the EURUSD D1 caption on screen read            |
//|                                                                  |
//|   AB=CD | AB:504.1 | BC:765.0 | Step:267.7 pips [closed K=3.0 rat |
//|                                                                  |
//| — 63 characters, cut mid-word inside "ratio" — while the live     |
//| step 267.7 was produced by the WALK-UP SHIFT, whose own words     |
//| ("-> SHIFT 2xLS(D1)=267.7"), the rung, T3/T5 and the milestone    |
//| were ALL past the cliff. Measured off the chart's own price axis  |
//| the ladder is consistent (Step1 1.1290, Step3 1.0754 — 536 pips = |
//| 2 x 267.7 — projecting from the real D at 1.1558) and the closed  |
//| seed really was 162.7 pips with K=3.0; the arithmetic was right.   |
//| What was missing was the ONE line that explains it, so the reader  |
//| draws the only conclusion left: «گام اشتباه میندازه» — a K=3.0    |
//| caption beside a step no K=3.0 seed can produce.                   |
//|                                                                    |
//| So the caption is a FAMILY, not a label: the SAME honest text,      |
//| wrapped at its own " | " boundaries into as many ≤63-character      |
//| lines as it needs, stacked by the project's own spacing (font + 6,  |
//| the mode-label stack's rule — P-TH3-PERF-01's neighbourhood).      |
//| Nothing about the text changes, so whenever the provenance grows    |
//| again the caption grows with it instead of losing its tail. The     |
//| wrap prefers a " | " boundary, falls back to the last space, and    |
//| only hard-cuts when a single token is longer than the line — and it |
//| NEVER drops text itself: the last slot takes whatever is left, so   |
//| the only clip that can still happen is MT4's own, on the final line |
//| of a caption longer than TH3_INFO_MAX_LINES x 63 characters.        |
//|                                                                    |
//| ONE OWNER for the family's whole lifecycle (name, wrap, draw,       |
//| delete, visibility, position). The active-pattern sweep, the        |
//| reposition pass and the delete path all ask these functions instead |
//| of spelling "_Info" themselves — that is what keeps a five-label    |
//| family from leaking a line into the next pattern's caption.         |
//+------------------------------------------------------------------+
#define TH3_INFO_TEXT_MAX  63   // MT4's own cap on OBJPROP_TEXT
#define TH3_INFO_MAX_LINES 6    // room for three rows, each of which may wrap
#define TH3_INFO_ROWS      3    // P-TH3-INFO-04: the readout's layout is its rows
#define TH3_INFO_SLOT_GAP  8    // RETIRED (P-TH3-INFO-14, 2026-09-25): the px between two
                                // captions' plates in the stack. Kept for a one-line restore
                                // (see the retirement note below), no reader now.

// Line 0 keeps the historical name (`_Info`), so the base-name extraction,
// the prefix wipes and any object already on a chart keep resolving.
string TH3InfoLineName(const string base, const int line)
{
    if(line <= 0) return base + "_Info";
    return base + "_Info" + IntegerToString(line + 1);
}

// The plate that carries the family's ink (P-TH3-INFO-04). It is PART OF the
// family on purpose: a caption that is repositioned, hidden or deleted without
// its plate would leave a dark empty bar on the chart — the half-a-readout the
// BaseKnot note's own plate gate forbids on the other surface (P-BK-86).
string TH3InfoPlateName(const string base) { return base + "_InfoPlate"; }

//+------------------------------------------------------------------+
//| P-TH3-INFO-14 (2026-09-25) — THE SLOT PITCH IS DEAD; THE CAPTION |
//| SITS AT THE BASE OF THE SAFE AREA.                                |
//|                                                                  |
//| P-TH3-INFO-03 gave every pattern its own SLOT so two captions'     |
//| plates could not overlap, and P-TH3-INFO-04 sized that pitch on    |
//| `TH3_INFO_ROWS` (three). Both are now wrong in the same way:      |
//|                                                                  |
//|   * P-TH3-INFO-10 made the plate follow visibility by EXISTENCE —  |
//|     only the ACTIVE family carries a plate, and every inactive      |
//|     family's rows wear OBJ_NO_PERIODS. So a second slot can never  |
//|     be OCCUPIED, and the pitch could only ever push the one plate  |
//|     the user sees down by `patternIndex x (56 + 8) = 64 px` at the |
//|     reference size (pt 9, 96 dpi) — over the empty slot of a        |
//|     caption that is not there; and switching the active pattern     |
//|     made the caption JUMP by that much.                            |
//|   * The pitch was a FIXED three rows while the wrap budget is       |
//|     `TH3_INFO_MAX_LINES` (six): a four-line caption measures        |
//|     TH3ROPlateH(4) = 73 px against a 64 px pitch, and a six-line    |
//|     one 107 px — so the very overlap the slot existed to prevent    |
//|     was 9..43 px of it, and the "two plates never overlap" note at   |
//|     the call site was arithmetic that did not hold.                 |
//|                                                                  |
//| The pitch therefore has no reader that can be true, and the two    |
//| helpers that computed it are gone. The plate is measured from its  |
//| own final lines (`TH3ROPlateH(n)`), which is what makes it fit      |
//| whatever the wrap produced — the height was never the problem, the |
//| PITCH was. Restore a stack by giving `TH3_INFO_SLOT_GAP` a reader:  |
//| `topY = baseY + slot * (TH3ROPlateH(n, fontPt) + TH3_INFO_SLOT_GAP)`|
//| — with `n` the PREVIOUS family's own line count, never a constant.  |
//+------------------------------------------------------------------+

// Is this object part of ANY pattern's caption — a line, or the plate under them?
// (the family test the active-pattern sweep needs, so a line 2 is swept with its
// line 1, and a plate goes dark with the rows it carries)
bool TH3IsInfoPlateName(const string objName)
{
    int n = StringLen(objName);
    return (n > 10 && StringSubstr(objName, n - 10) == "_InfoPlate");
}

bool TH3IsInfoLabelName(const string objName)
{
    if(TH3IsInfoPlateName(objName)) return true;
    int n = StringLen(objName);
    for(int line = 0; line < TH3_INFO_MAX_LINES; line++)
    {
        string suffix = (line == 0) ? "_Info" : "_Info" + IntegerToString(line + 1);
        int s = StringLen(suffix);
        if(n > s && StringSubstr(objName, n - s) == suffix) return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| P-TH3-P6f (2026-09-22) — AT MOST ONE LADDER IS VISIBLE.          |
//| Two patterns in the store drew two Step1/3/5/7 families and the   |
//| chart read as one mixed ladder (XAUUSD M15: Step1 115.4 vs 109.6, |
//| Step3 346.3 vs 328.8 — each pattern owns its closedStep, so each  |
//| owns its q winner and its lock). The ladder is the ACTIVE         |
//| pattern's answer the way the caption already is (P-TH3-P6d) and   |
//| the mother badge already is (one badge per chart): other patterns |
//| keep their ABCD ink and their caption slot, but no targets, no    |
//| zones, no proof. Chart objects obey TIMEFRAMES (the P-TH3-INFO-10  |
//| exception is screen plates only), so masks hide them; guarded     |
//| writes only (perf law). Suffix-tested like the info test above.   |
//+------------------------------------------------------------------+
bool TH3IsLadderName(const string objName)
{
    if(StringFind(objName, "_Target_") >= 0) return true;
    if(StringFind(objName, "_ZoneUpper_") >= 0) return true;
    if(StringFind(objName, "_ZoneLower_") >= 0) return true;
    if(StringFind(objName, "_Zone_") >= 0) return true;
    if(StringFind(objName, "_HitLine") >= 0) return true;
    if(StringFind(objName, "_HitLabel") >= 0) return true;
    return false;
}

void TH3LadderMaskOne(const string objName, const int wantTF)
{
    if(ObjectFind(0, objName) < 0) return;
    if(ObjectGetInteger(0, objName, OBJPROP_TIMEFRAMES) != wantTF)
        ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, wantTF);
}

void TH3LadderSetVisible(const string base, const bool visible)
{
    int wantTF = visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    for(int i = 1; i <= 4; i++)
    {
        string s = IntegerToString(i);
        TH3LadderMaskOne(base + "_Target_" + s, wantTF);
        TH3LadderMaskOne(base + "_ZoneUpper_" + s, wantTF);
        TH3LadderMaskOne(base + "_ZoneLower_" + s, wantTF);
        TH3LadderMaskOne(base + "_Zone_" + s, wantTF);
        TH3LadderMaskOne(base + "_Zone_" + s + "_B_Top", wantTF);
        TH3LadderMaskOne(base + "_Zone_" + s + "_B_Bottom", wantTF);
        TH3LadderMaskOne(base + "_Zone_" + s + "_B_Left", wantTF);
    }
    TH3LadderMaskOne(base + "_HitLine", wantTF);
    TH3LadderMaskOne(base + "_HitLabel", wantTF);
}

//+------------------------------------------------------------------+
//| P-TH3-DEL1 (2026-09-22) -- THE FAMILY BASE, OFF THE NAME.       |
//| Pattern names are `ABCD_Pattern_<digits>` (TH3Tool.mqh: the      |
//| completion stamps GetTickCount()). Any member name — point, line, |
//| target, zone, border, proof, caption row, temp, or the TH3_MP_    |
//| overlay's own prefix — reduces to the same base: the literal      |
//| prefix plus its leading digits. "" when the name is no family    |
//| member at all. Pure string logic: Lite-safe, harness-safe.        |
//+------------------------------------------------------------------+
string TH3FamilyBaseOf(const string objName)
{
    string rest = objName;
    if(StringFind(rest, "TH3_MP_") == 0)
        rest = StringSubstr(rest, 7);
    string pre = TH3_PATTERN_PREFIX;
    if(StringFind(rest, pre) != 0) return "";
    string tail = StringSubstr(rest, StringLen(pre));
    int di = 0;
    int tn = StringLen(tail);
    while(di < tn)
    {
        ushort ch = StringGetCharacter(tail, di);
        if(ch < '0' || ch > '9') break;
        di++;
    }
    if(di <= 0) return "";
    return pre + StringSubstr(tail, 0, di);
}

//+------------------------------------------------------------------+
//| P-TH3-DEL2 (2026-09-22) -- THE ANCHORS DECIDE. A family whose    |
//| A/B/C points and AB/BC leg lines all stand is INTACT: a member   |
//| missing from it is our own maintenance (overlay/proof/zone       |
//| dropped by a draw) and is healed back, never wiped. A family     |
//| missing ANY of them was broken by a hand (or a failed build) and |
//| wipes whole. D/CD are NOT anchors: a rule-D pattern (AB=CD fallback,|
//| P-TH3-D4) carries no D objects, yet is whole -- demanding them   |
//| wiped such patterns on any member delete. Five probes, delete    |
//| path only -- nothing on the steady path.                         |
//+------------------------------------------------------------------+
bool TH3FamilyAnchorsAlive(const string base)
{
    if(ObjectFind(0, base + "_Point_A") < 0) return false;
    if(ObjectFind(0, base + "_Point_B") < 0) return false;
    if(ObjectFind(0, base + "_Point_C") < 0) return false;
    if(ObjectFind(0, base + "_Line_AB") < 0) return false;
    if(ObjectFind(0, base + "_Line_BC") < 0) return false;
    return true;
}

// Split a caption into its own rows: a "\n" is a HARD BREAK (P-TH3-INFO-04) —
// that is how a readout hands its rows over: what the pattern is, what its legs
// measure, and the live number.
int TH3InfoSplitRows(const string text, string &rows[])
{
    ArrayResize(rows, 0);
    string rest = text;
    while(true)
    {
        int p = StringFind(rest, "\n");
        int n = ArraySize(rows);
        ArrayResize(rows, n + 1);
        if(p < 0) { rows[n] = rest; break; }
        rows[n] = StringSubstr(rest, 0, p);
        rest = StringSubstr(rest, p + 1);
    }
    return ArraySize(rows);
}

// Wrap ONE row into the accumulator. The row is taken whole when it fits; a row
// past the cap breaks at its own " | " boundary, then at the last space, and only
// hard-cuts when a single token is longer than the line. The caller owns the slot
// budget, so two rows can never spend each other's lines.
void TH3InfoWrapRow(const string row, const int maxLen, string &lines[])
{
    string rest = row;
    int guard = 0;
    while(StringLen(rest) > 0 && guard < 32)
    {
        guard++;
        bool lastSlot = (ArraySize(lines) >= TH3_INFO_MAX_LINES - 1);
        if(StringLen(rest) <= maxLen || lastSlot)
        {
            int n = ArraySize(lines);
            ArrayResize(lines, n + 1);
            lines[n] = rest;
            break;
        }
        int cut = -1;
        int from = 0;
        while(true)                          // the LAST " | " that still fits
        {
            int p = StringFind(rest, " | ", from);
            if(p < 0 || p + 3 > maxLen) break;
            cut = p + 3;
            from = p + 1;
        }
        if(cut > 0 && (maxLen - cut) > maxLen / 5) cut = -1;
        if(cut <= 0)                         // else the last space that fits
        {
            cut = maxLen;
            for(int i = maxLen; i >= 1; i--)
            {
                if(StringGetCharacter(rest, i - 1) == 32) { cut = i; break; }
            }
        }
        int n = ArraySize(lines);
        ArrayResize(lines, n + 1);
        lines[n] = StringSubstr(rest, 0, cut);
        rest = StringSubstr(rest, cut);
        while(StringLen(rest) > 0 && StringGetCharacter(rest, 0) == 32)
            rest = StringSubstr(rest, 1);    // no line starts on the space it broke at
    }
}

// Wrap a whole caption: every "\n" row through the row wrapper, into ONE
// accumulator. Returns the count; the lines array is resized to it. Prefers a
// " | " boundary, then the last space, then a hard cut; the final slot takes the
// remainder, so this never drops text itself.
int TH3InfoWrap(const string text, const int maxLen, string &lines[])
{
    ArrayResize(lines, 0);
    string rows[];
    int rowCount = TH3InfoSplitRows(text, rows);
    for(int r = 0; r < rowCount && ArraySize(lines) < TH3_INFO_MAX_LINES; r++)
        TH3InfoWrapRow(rows[r], maxLen, lines);
    return ArraySize(lines);
}

// Delete every caption line of one pattern (the surplus lines included) AND the
// plate that carried them: half a readout left behind is a dark empty bar.
void TH3InfoFamilyDelete(const string base)
{
    for(int line = 0; line < TH3_INFO_MAX_LINES; line++)
        ObjectDelete(0, TH3InfoLineName(base, line));
    ObjectDelete(0, TH3InfoPlateName(base));
}

//+------------------------------------------------------------------+
//| P-TH3-INFO-10 (2026-09-22) — THE PLATE IS HIDDEN BY ABSENCE,     |
//| NEVER BY A MASK.                                                  |
//|                                                                   |
//| The report was the M15 chart's top-left box: «اول نمایش میده ولی   |
//| بعد دیگه فقط سیاه هستش». The caption's ROWS went dark on the      |
//| first deactivation (an OBJ_LABEL DOES honour OBJPROP_TIMEFRAMES —  |
//| the P-TH3-INFO-06c "hidden while active" state proved that on this |
//| terminal), while the plate behind them stayed: an                  |
//| OBJ_RECTANGLE_LABEL does NOT go away under the same mask (the      |
//| same screen-object fact P-UI-98n found for OBJ_BITMAP_LABEL — the  |
//| ride circles the L key could not hide). Every family path wrote    |
//| the SAME mask onto both halves, so every hide left a dark bar with |
//| no ink: the «جعبهٔ سیاه بالای چارت» this project has now chased    |
//| four times (INFO-06/06b/06c/08) with fixes aimed at the rows.      |
//|                                                                   |
//| So the plate's visibility is EXISTENCE: a family that must be dark |
//| drops its plate (display-only — a redraw recreates whatever it     |
//| needs), a family that must light grows it back from its OWN rows,  |
//| which are the geometry authority (placed on TH3ROPlateAt/          |
//| TH3RORowAt's one grid; they still hold corner, font, anchor Y and  |
//| text). The rows keep their masks — that half of the contract was   |
//| always honoured. Nothing ever writes OBJ_NO_PERIODS on a plate     |
//| again: a plate on the chart IS a visible plate.                    |
//+------------------------------------------------------------------+
void TH3InfoFamilyPlateDrop(const string base)
{
    string plate = TH3InfoPlateName(base);
    if(ObjectFind(0, plate) >= 0) ObjectDelete(0, plate);
}

// Rebuild the plate from the family's contiguous rows. False = nothing to
// carry (no row 0), which is exactly the orphan rule — never a plate alone.
// P-TH3-INFO-12 (2026-09-22): the rows are rebuilt AFTER the plate, always.
// MT4 ties equal ZORDER by CREATION ORDER (the rule TH3RORowAt's own header
// states), so rows that predate the plate they sit on paint UNDER it — the
// reported «وقتی روی خطوط کلیک میکنم سیاه میشه»: the active sweep (drop) plus
// the verify (grow) round-trip left every surviving row OLDER than its fresh
// plate, the plate covered the ink, and only the next full redraw healed it.
// Recreating the rows re-ages them past the plate; every property they need
// (corner, font, text, ink, BACK=false, Z_TH3_RO_TEXT) is re-owned by
// TH3RORowAt on the way in, and their TIMEFRAMES land on OBJ_ALL_PERIODS —
// both grow callers only ever grow a family that must be LIT.
// P-TH3-INFO-13: the visit clock is NOT armed here — every caller that lights
// a family arms it on its own way out (SetVisible's light path), so a hidden
// family regrown for layout never buys a visit.
bool TH3InfoFamilyPlateGrow(const string base)
{
    string r0 = TH3InfoLineName(base, 0);
    if(ObjectFind(0, r0) < 0) return false;
    string rows[];
    ArrayResize(rows, 0);
    for(int line = 0; line < TH3_INFO_MAX_LINES; line++)
    {
        string nm = TH3InfoLineName(base, line);
        if(ObjectFind(0, nm) < 0) break;          // Draw writes rows contiguously
        int cnt = ArraySize(rows);
        ArrayResize(rows, cnt + 1);
        rows[cnt] = ObjectGetString(0, nm, OBJPROP_TEXT);
    }
    int n = ArraySize(rows);
    if(n <= 0) return false;
    int fontPt = (int)ObjectGetInteger(0, r0, OBJPROP_FONTSIZE);
    int crn = (int)ObjectGetInteger(0, r0, OBJPROP_CORNER);
    ENUM_BASE_CORNER corner = (ENUM_BASE_CORNER)crn;
    int topY = (int)ObjectGetInteger(0, r0, OBJPROP_YDISTANCE);  // row 0 IS topY on both corner sides
    int nearX = (int)ObjectGetInteger(0, r0, OBJPROP_XDISTANCE);
    string plate = TH3InfoPlateName(base);
    TH3ROPlateAt(plate, corner,
                 TH3ROPlateX(nearX, corner),
                 TH3ROPlateY(topY, n, fontPt, corner),
                 TH3ROPlateW(rows, n, fontPt),
                 TH3ROPlateH(n, fontPt),
                 true,
                 "AB=CD caption (P-TH3-INFO-04): the pattern, its legs in pips, and the live step");
    // a plate a pre-INFO-10 build left masked heals itself on the way in —
    // the mask is meaningless to it now, but one honest write settles both
    // possible terminal behaviours.
    if((int)ObjectGetInteger(0, plate, OBJPROP_TIMEFRAMES) != OBJ_ALL_PERIODS)
        ObjectSetInteger(0, plate, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
    // P-TH3-INFO-12: the ink goes back on AFTER the plate exists — a row a
    // pre-grow build created is older than this fresh plate and paints under
    // it (the black box with no text). Deleting first makes TH3RORowAt's
    // create path run, which re-owns every property the row wears.
    for(int line = 0; line < n; line++)
    {
        string nm = TH3InfoLineName(base, line);
        ObjectDelete(0, nm);
        TH3RORowAt(nm, rows[line], corner, nearX,
                   TH3RORowY(topY, line, fontPt, corner), fontPt,
                   line, n, true);
        if((int)ObjectGetInteger(0, nm, OBJPROP_TIMEFRAMES) != OBJ_ALL_PERIODS)
            ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
    }
    return true;
}

// Show/hide the whole family (the active-pattern rule: at most ONE pattern's
// caption is visible, and "one" means every line of it AND its plate).
void TH3InfoFamilySetVisible(const string base, const bool visible)
{
    // P-TH3-INFO-08: never show a plate with no rows — it paints as a dark
    // empty bar. Showing is display-only: deleting the orphan loses nothing a
    // redraw cannot recreate.
    // P-TH3-INFO-10: the PLATE now follows the intent by EXISTENCE — a mask
    // does not hide an OBJ_RECTANGLE_LABEL (the rows DO obey theirs), so
    // masking the plate is exactly what left «فقط سیاه» on the chart.
    int rows = 0;
    for(int line = 0; line < TH3_INFO_MAX_LINES; line++)
        if(ObjectFind(0, TH3InfoLineName(base, line)) >= 0) rows++;
    if(rows <= 0) { TH3InfoFamilyPlateDrop(base); return; }
    for(int line = 0; line < TH3_INFO_MAX_LINES; line++)
    {
        string nm = TH3InfoLineName(base, line);
        if(ObjectFind(0, nm) < 0) continue;
        // P-TH3-INFO-08: ink above plate — rare path, unconditional is fine.
        ObjectSetInteger(0, nm, OBJPROP_ZORDER, Z_TH3_RO_TEXT);
        ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES,
                         visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
    }
    if(!visible) { TH3InfoFamilyPlateDrop(base); return; }
    string plate = TH3InfoPlateName(base);
    if(ObjectFind(0, plate) < 0)
    {
        TH3InfoFamilyPlateGrow(base);
        TH3InfoVisitArm();   // P-TH3-INFO-13: a regrown plate still buys a visit
        return;
    }

    ObjectSetInteger(0, plate, OBJPROP_ZORDER, Z_TH3_RO_PLATE);
    if((bool)ObjectGetInteger(0, plate, OBJPROP_BACK))
        ObjectSetInteger(0, plate, OBJPROP_BACK, false);
    if((int)ObjectGetInteger(0, plate, OBJPROP_TIMEFRAMES) != OBJ_ALL_PERIODS)
        ObjectSetInteger(0, plate, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
    TH3InfoVisitArm();   // P-TH3-INFO-13: every light path re-arms the visit
}

// Move the whole block — rows AND plate — down from a top offset, keeping its
// stacking. The rows move on the readout's own grid (TH3RORowY) and the plate on
// the same one, which is what keeps the ink inside the plate after the move.
void TH3InfoFamilyReposition(const string base, const int topY)
{
    int fontPt = inpABCDInfoFontSize;
    int rows = 0;
    for(int line = 0; line < TH3_INFO_MAX_LINES; line++)
        if(ObjectFind(0, TH3InfoLineName(base, line)) >= 0) rows++;
    for(int line = 0; line < TH3_INFO_MAX_LINES; line++)
    {
        string nm = TH3InfoLineName(base, line);
        if(ObjectFind(0, nm) < 0) continue;
        TH3ROSetY(nm, TH3RORowY(topY, line, fontPt, inpABCDInfoCorner));
    }
    string plate = TH3InfoPlateName(base);
    if(ObjectFind(0, plate) < 0) return;
    // P-TH3-INFO-06: a plate with no rows is never a valid state — it paints
    // as a dark empty bar (the user's top-left box). Rows are counted by
    // EXISTENCE above (a hidden row still counts), so this only ever removes a
    // true orphan instead of moving it.
    if(rows <= 0) { ObjectDelete(0, plate); return; }
    TH3ROSetY(plate, TH3ROPlateY(topY, rows, fontPt, inpABCDInfoCorner));
}

// P-TH3-INFO-06b (2026-09-21) — THE CHART-WIDE ORPHAN SWEEP. The reposition
// pass only visits the STORE, but a plate can outlive its rows from a path
// that never touches the store (a skipped restore base, a build mix after a
// remove/re-add): a plate with ZERO surviving family rows is never valid —
// it paints as a dark empty bar (the top-left box). Display-only objects, so
// deleting one destroys nothing a redraw cannot recreate. Rows count by
// EXISTENCE (a hidden row still counts), exactly like the reposition guard.
// Callers: the reposition pass (rare layout moments) and the attach restore.
void TH3InfoOrphanPlateSweep()
{
    for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
    {
        string nm = ObjectName(0, i, -1, -1);
        if(StringFind(nm, "ABCD_Pattern_") != 0) continue;
        int n = StringLen(nm);
        if(n <= 10 || StringSubstr(nm, n - 10) != "_InfoPlate") continue;
        string base = StringSubstr(nm, 0, n - 10);
        bool anyRow = false;
        for(int line = 0; line < TH3_INFO_MAX_LINES; line++)
        {
            if(ObjectFind(0, TH3InfoLineName(base, line)) >= 0) { anyRow = true; break; }
        }
        if(!anyRow) ObjectDelete(0, nm);
    }
}

// P-TH3-INFO-06c (2026-09-21) — VERIFY, THEN MOVE. Reposition used to only
// move families that already agreed with the active rule; a family whose rows
// exist but wear the WRONG visibility (hidden while active, or lit while
// retired) kept disagreeing forever — the caption that «یکبار میاد ولی ...
// دیگه نمیشه». The redraw always rewrites both sides together, so this only
// heals what happened BETWEEN redraws, through the ONE owner (guarded writes,
// no second writer of TIMEFRAMES here). A plate with no rows dies like any
// other orphan (the store-side twin of the chart-wide sweep).
void TH3InfoFamilyVerify(const string base, const bool isActive)
{
    int rows = 0;
    for(int line = 0; line < TH3_INFO_MAX_LINES; line++)
        if(ObjectFind(0, TH3InfoLineName(base, line)) >= 0) rows++;
    string plate = TH3InfoPlateName(base);
    bool hasPlate = (ObjectFind(0, plate) >= 0);
    if(rows <= 0) { TH3InfoFamilyPlateDrop(base); return; }
    int wantTF = isActive ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    for(int line = 0; line < TH3_INFO_MAX_LINES; line++)
    {
        string nm = TH3InfoLineName(base, line);
        if(ObjectFind(0, nm) < 0) continue;
        // P-TH3-INFO-08: ink above plate, re-asserted UNGUARDED (old charts).
        // P-UI-31: the rung is never read back — a guarded read would be a
        // product question about paint order, and the 8ab-20b seed bans it.
        // The 250 ms net only reaches a family that already exists; seven
        // same-value writes beat a diagnostic read the audit forbids.
        ObjectSetInteger(0, nm, OBJPROP_ZORDER, Z_TH3_RO_TEXT);
        // P-TH3-INFO-09: and the BACK flag healed here — a stale row with
        // BACK=true is invisible behind its own plate between redraws.
        if((bool)ObjectGetInteger(0, nm, OBJPROP_BACK))
            ObjectSetInteger(0, nm, OBJPROP_BACK, false);
        if((int)ObjectGetInteger(0, nm, OBJPROP_TIMEFRAMES) != wantTF)
            ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES, wantTF);
    }
    // P-TH3-INFO-10: the plate is EXISTENCE, never a mask — a family that
    // must be dark drops its plate; a lit family whose plate went missing
    // grows it back from its own rows. Only the ALL half of wantTF ever
    // touches a plate from here (a masked plate is a plate that stayed
    // visible — the empty dark bar).
    if(!isActive) { TH3InfoFamilyPlateDrop(base); return; }
    if(!hasPlate) { TH3InfoFamilyPlateGrow(base); return; }
    // P-TH3-INFO-11 / P-UI-31: same unguarded re-assert as the rows above —
    // the rung is never read back (see the rows' note).
    ObjectSetInteger(0, plate, OBJPROP_ZORDER, Z_TH3_RO_PLATE);
    if((bool)ObjectGetInteger(0, plate, OBJPROP_BACK))
        ObjectSetInteger(0, plate, OBJPROP_BACK, false);
    if((int)ObjectGetInteger(0, plate, OBJPROP_TIMEFRAMES) != OBJ_ALL_PERIODS)
        ObjectSetInteger(0, plate, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

// ── P-TH3-INFO-13 — THE CAPTION IS A TIMED VISITOR ─────────────────
// The user's order (2026-09-22): «لیبل مود ها و لیبل abcd باید بعد چند ثانیه
// حذف بشن هرچی که اطلاعاتی هستش» — every info readout is a guest of a few
// seconds, the leg meter's own contract (P-LM-09). ONE deadline global, armed
// by the light paths (SetVisible's light branch, the verify's grow, and the
// redraw's own active re-arm in DrawABCDPattern), asked
// through the wrap-safe owner (TickDeadlinePending, [tick-wrap]), swept by the
// 250 ms heal net BEFORE its heal half so a heal can never resurrect an
// expired visit. The duration is inpModeLabelDuration — the SAME input the
// mode rows expire on — so one setting owns every info readout's lifetime.
// 0 = permanent (the input's own contract).
uint g_th3InfoVisitUntilMs = 0;

// The active family's visit still has time on it.
bool TH3InfoVisitPending() { return (g_th3InfoVisitUntilMs != 0); }

// Arm/re-arm the active family's visit clock. Called by the light paths
// (SetVisible's light branch; the verify's grow); a redraw re-arms, an expiry
// is a drop.
void TH3InfoVisitArm()
{
    int durSec = inpModeLabelDuration;
    if(durSec <= 0) { g_th3InfoVisitUntilMs = 0; return; }   // 0 = permanent
    if(durSec > 86400) durSec = 86400;
    g_th3InfoVisitUntilMs = GetTickCount() + (uint)durSec * 1000;
}

// The expiry's own verb: the whole ACTIVE family goes dark through its ONE
// owner (rows masked, plate dropped — the P-TH3-INFO-10 shapes), the active
// pattern stays in the store and its ladder stays; only the readout leaves.
void TH3InfoFamilyDropActive()
{
    string base = g_activeABCDPattern;
    if(base == "") return;
    TH3InfoFamilySetVisible(base, false);
}

//+------------------------------------------------------------------+
//| P-TH3-INFO-11 (2026-09-22) -- THE CAPTION HEAL NET. The top-left |
//| dark plate kept recurring (INFO-06/06b/06c/08/10) because every  |
//| fix covered the paths that DRAW, while killer paths only need to |
//| delete or mask ROWS once between redraws (object-list deletes the |
//| terminal allows despite SELECTABLE=false, foreign sweeps, build   |
//| mixes). So the 250 ms timer asks one question of the ACTIVE      |
//| family through its one owner: rows-masked-while-active unmasked, |
//| missing plate regrown, rowless plate dropped. Reads-only while   |
//| healthy (every write below the verify is guarded); an action     |
//| logs one TH3CAP line the user can send back with the screenshot. |
//+------------------------------------------------------------------+
void TH3InfoCaptionHeal()
{
    if(g_activeABCDPattern == "") return;
    string base = g_activeABCDPattern;
    // P-TH3-INFO-13 (2026-09-22): the caption is a TIMED VISITOR first. The
    // user's order: «لیبل مود ها و لیبل abcd باید بعد چند ثانیه حذف بشن
    // هرچی که اطلاعاتی هستش» — every info readout leaves after a few
    // seconds, exactly the leg meter's 4-second visit (P-LM-09). The sweep
    // runs here (the 250 ms clock, already running) BEFORE the heal, so a
    // heal can never resurrect an expired visit. Duration is the SAME input
    // the mode rows answer (inpModeLabelDuration, 0 = permanent). A redraw
    // (a re-step, a drag, a settings press) re-arms the clock below.
    if(TH3InfoVisitPending() && !TickDeadlinePending(g_th3InfoVisitUntilMs))
    {
        TH3InfoFamilyDropActive();
        g_th3InfoVisitUntilMs = 0;
        ThrottledChartRedraw();
        return;
    }
    int rows = 0;
    bool masked = false;
    for(int line = 0; line < TH3_INFO_MAX_LINES; line++)
    {
        string nm = TH3InfoLineName(base, line);
        if(ObjectFind(0, nm) < 0) continue;
        rows++;
        if((int)ObjectGetInteger(0, nm, OBJPROP_TIMEFRAMES) != OBJ_ALL_PERIODS)
            masked = true;
    }
    bool hasPlate = (ObjectFind(0, TH3InfoPlateName(base)) >= 0);
    if(rows <= 0 && !hasPlate) return;            // nothing to heal
    if(rows > 0 && !masked && hasPlate) return;   // healthy: reads only
    TH3InfoFamilyVerify(base, true);              // (its grow re-arms the visit)
    // P-TIME-01: the line carries its own SERVER stamp (epoch, no spaces) so
    // rows from two machines stay comparable -- Experts prefixes print the
    // Windows clock, which is a second timezone the formula must not see.
    Print("TH3CAP healed ", base, " st=", IntegerToString((long)TimeCurrent()),
          " rows=", rows,
          " masked=", (masked ? 1 : 0), " plate=", (hasPlate ? 1 : 0));
    ThrottledChartRedraw();
}

// ── P-TH3-INFO-04 — THE CAPTION WRITER: text in, a boxed readout out ──
// THE owner of what a caption looks like. The text may carry "\n" ROW BREAKS (the
// readout's layout: what the pattern is, what its legs measure, the live number),
// and every row is wrapped on its own — MT4's 63-character cliff is per OBJECT, so
// a row that needs two lines gets them instead of being cut. The plate is then
// measured off the FINAL lines, so a caption that grows a line grows its plate
// with it. `topY` starts the whole block, so each pattern's plate owns its slot.
int TH3InfoFamilyDraw(const string base, const string text,
                      const bool isActive, const int topY)
{
    string lines[];
    int n = TH3InfoWrap(text, TH3_INFO_TEXT_MAX, lines);
    if(n <= 0)
    {
        TH3InfoFamilyDelete(base);   // nothing to say: no caption AND no empty plate
        return 0;
    }
    int fontPt = inpABCDInfoFontSize;
    int wantTF = isActive ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    string plate = TH3InfoPlateName(base);

    // A plate that is NOT there yet is created now — and every row that predates
    // it is dropped FIRST (P-TH3-INFO-08 keeps the explicit rungs plate 62 /
    // ink 63 too, so creation order no longer decides). The rows are
    // our own text and every character of it is recomputed right here, so
    // rebuilding them moves nothing the user drew.
    // P-TH3-INFO-10: only the ACTIVE family carries a plate — an inactive
    // one would need a mask to go dark, and a mask does not hide an
    // OBJ_RECTANGLE_LABEL (its rows DO obey theirs — that asymmetry is the
    // empty dark bar: «اول نمایش میده ولی بعد دیگه فقط سیاه هستش»).
    if(isActive)
    {
        if(ObjectFind(0, plate) < 0)
            for(int line = 0; line < TH3_INFO_MAX_LINES; line++)
                ObjectDelete(0, TH3InfoLineName(base, line));

        TH3ROPlateAt(plate, inpABCDInfoCorner,
                     TH3ROPlateX(inpABCDInfoXDistance, inpABCDInfoCorner),
                     TH3ROPlateY(topY, n, fontPt, inpABCDInfoCorner),
                     TH3ROPlateW(lines, n, fontPt), TH3ROPlateH(n, fontPt), true,
                     "AB=CD caption (P-TH3-INFO-04): the pattern, its legs in pips, and the live step");
    }

    for(int line = 0; line < TH3_INFO_MAX_LINES; line++)
    {
        string nm = TH3InfoLineName(base, line);
        if(line >= n)
        {
            if(ObjectFind(0, nm) >= 0) ObjectDelete(0, nm);
            continue;
        }
        TH3RORowAt(nm, lines[line], inpABCDInfoCorner, inpABCDInfoXDistance,
                   TH3RORowY(topY, line, fontPt, inpABCDInfoCorner), fontPt,
                   line, n, true);
        if((int)ObjectGetInteger(0, nm, OBJPROP_TIMEFRAMES) != wantTF)
            ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES, wantTF);
    }
    // P-TH3-INFO-10: an inactive family drops its plate (existence is its
    // visibility); an active one only ever heals toward ALL — never a mask.
    if(!isActive) { TH3InfoFamilyPlateDrop(base); return n; }
    if(ObjectFind(0, plate) >= 0 &&
       (int)ObjectGetInteger(0, plate, OBJPROP_TIMEFRAMES) != OBJ_ALL_PERIODS)
        ObjectSetInteger(0, plate, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
    return n;
}

#endif // TH3_RENDERER_A_MQH
