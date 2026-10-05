// EventHandlers_Init.mqh - EventHandlers split 2026-09-29: exact lines 7-1496 of EventHandlers.mqh, byte-identical, zero renames.
// P-SIZE-1500 (2026-10-04): the file drifted back over the ceiling (1749 lines) and was
// split again along the seam it already had - everything from `CreateCustomPriceLine`
// down is the custom price line's own half and lives in EventHandlers_CustomPrice.mqh,
// included ABOVE this one (nothing there calls in here; this file calls out to it).
#ifndef EVENT_HANDLERS_INIT_MQH
#define EVENT_HANDLERS_INIT_MQH

#property strict

//==============================================================================
// P-PERF-38c — ONE-TIME MIGRATION OFF THE TIMEFRAME-NAMED SCHEME
//
// P-PERF-38 made the level-object prefix timeframe-free, so a chart that had
// been drawn by an older build still holds one whole namespace per timeframe it
// ever visited (`THLevels_H1_*`, `THLevels_M15_*`, ...). The old teardown swept
// all eleven of those on EVERY timeframe switch - eleven full-chart prefix scans
// for objects that, after this migration, do not exist at all.
//
// So the sweep is not deleted; it is MOVED OUT OF THE SWITCH and gated on a
// per-chart stamp. It runs exactly once per chart, ever. Steady state: one
// GlobalVariableCheck. That is the difference between "cleanup that scales with
// how often you press H1" and "cleanup that happens once".
void MigrateTimeframeNamedObjects()
{
   // P-PERF-38f: the stamp has ONE owner (GlobalVariables), shared with the label
   // sweep that must stop doing this work on every timeframe switch.
   string stamp = NameSchemeStampName();
   if(LegacyNameSchemeMigrated()) return;   // this chart is already migrated

   // Every string GetCurrentTimeframe() can return, plus the two legacy
   // spellings ("MN" from ClearAllLabels, "UNKNOWN" for a CUSTOM period).
   static string s_tfNs[] = {"M1", "M5", "M15", "M30", "H1", "H4", "D1", "W1", "MN", "MN1", "UNKNOWN"};
   g_suppressDeleteEvents = true;
   int removed = 0;
   for(int n = 0; n < ArraySize(s_tfNs); n++)
      removed += ObjectsDeleteAll(0, inpObjectPrefix + "_" + s_tfNs[n] + "_");
   // The ATR/TH label families also exist WITHOUT a TF namespace
   // (`inpObjectPrefix + "ATR_*" / "TH_*"`), and the legacy shared-pattern ones
   // carry `inpObjectPrefix + "SharedPattern_"`.
   removed += ObjectsDeleteAll(0, inpObjectPrefix + "ATR_");
   removed += ObjectsDeleteAll(0, inpObjectPrefix + "TH_");
   removed += ObjectsDeleteAll(0, inpObjectPrefix + "SharedPattern_");
   g_suppressDeleteEventsUntilMs = GetTickCount() + 250;
   g_suppressDeleteEvents = false;
   InvalidateObjectCountCache();
   GlobalVariableSet(stamp, 1.0);
   // Named, once, only when it actually did something - so the log shows the
   // upgrade happened and never repeats.
   if(removed > 0)
      _LOG_GATE_I Print("[I][GEN] P-PERF-38 migration: removed ", removed,
                        " legacy timeframe-named object(s) - this runs once per chart");
}

//==============================================================================
// P-PERF-38d — TOPOLOGY ADOPTION ACROSS MT4'S FORCED RELOAD
//
// P-PERF-38 named the level family without the timeframe and P-PERF-38b stopped
// the teardown from deleting it. On their own those two are NOT enough, and the
// reason is subtle: a chart period change makes MT4 unload and RELOAD the
// indicator, so the new instance starts with an EMPTY stored signature
// (`s_lastLevelSig == ""`). The first comparison is therefore trivially true ->
// `levelTopologyChanged` -> `shouldClearLevels` -> a full `ClearAllLevels` of the
// whole family, immediately followed by the staged rebuild that creates it all
// again. That delete+create pair IS the "changing the timeframe recomputes and
// redraws my levels" the user reports, and it survived the naming fix because
// nothing carried the fact that the chart is already drawn.
//
// So the new instance is TOLD. At teardown an ordinary timeframe change writes
// ONE per-chart fingerprint of the inputs that decide WHICH objects may exist
// (the naming scheme, the mode, and the other structure-defining inputs) — never
// the prices, which genuinely do change per timeframe. At init that fingerprint
// is compared, and on a match the first pass adopts the previous instance's
// topology: no wipe, no staging restart, and the timeframe change reduces to a
// single in-place property pass. The prices are still re-derived (`thValue`
// comes from `GetTimeframeTH()`), but they now arrive through the RENDER
// signature, which re-asserts in place, instead of through the NAME, which
// forced a destroy-and-build.
//
// Conservative by construction: no stamp (a first attach, an older build, a
// chart the indicator was just REMOVEd from) means no adoption, i.e. exactly the
// old behaviour. A wrong "same" can only ever skip a wipe, and a skipped wipe is
// safe here because every object the render does not produce is still swept by
// CleanupSurplusPipeline and the label generation sweep — both run on every
// render.
#define NAME_SCHEME_ID 40

string AdoptionStampName() { return "Biotak_AdoptTopology_" + GetCachedChartIdStr(); }

// The topology stamp is a CLAIM (written at teardown, compared at init) that the
// objects already on the chart are still correct: on a match the first pass
// ADOPTS them, so a timeframe switch is one in-place property pass instead of a
// wipe and a staged rebuild. It names every input that decides WHICH NAMES may
// exist — naming scheme, mode, level count, start-point type, LS-first, harmonic
// pair — because a name mismatch is never repaired in place (a mode change renames
// the whole family). P-LEVEL-FOREIGN-02 — the PRICES left the stamp: a stale price
// is repaired by `SweepForeignLadderObjects()` (LevelPipeline) on the one frame the
// ladder PITCH changed (measured: 250-300 ms teardown + four 60-95 ms frames per
// switch on MT5, ~30 ms on MT4). NAME_SCHEME_ID 39 -> 40 refuses every stamp a
// previous build wrote.
int AdoptionFingerprint()
{
   int fp = NAME_SCHEME_ID;
   fp = fp * 31 + (int)GetCurrentStepMode();
   fp = fp * 31 + inpMaxLevels;
   fp = fp * 31 + (int)g_thStartPointType;
   fp = fp * 31 + (inpLSFirst ? 1 : 0);
#ifndef BUILD_LITE
   fp = fp * 31 + (inpEnableHarmonicPattern ? 1 : 0);
   fp = fp * 31 + (int)MathRound(inpHarmonicRatio * 1000.0);
#endif
   // P-LEVEL-FOREIGN-02: and NOT the prices - the note above this function is
   // the whole argument. A price that moved is repaired IN PLACE by the pitch
   // sweep; a NAME that moved is not, which is the only distinction that
   // belongs in a stamp.
   return fp;
}

// Written by the teardown of a timeframe switch: the objects are staying on the
// chart, so the next instance is allowed to adopt them.
void SaveTopologyAdoptionStamp()
{
   GlobalVariableSet(AdoptionStampName(), (double)AdoptionFingerprint());
}

// Called by every teardown path that really deletes the family. Without the
// stamp the next instance wipes and rebuilds, which is the correct answer when
// the objects are genuinely gone.
void ClearTopologyAdoptionStamp()
{
   string n = AdoptionStampName();
   if(GlobalVariableCheck(n)) GlobalVariableDel(n);
}

// Resolved ONCE per instance, at the end of OnInitHandler — after the custom-
// price restore has had its say about `g_thStartPointType`, which is one of the
// fingerprint's inputs. The VALUE itself lives in GlobalVariables.mqh: the
// pipeline's ladder sweep reads it too, and LevelPipeline.mqh is included
// BEFORE this file (entry lines 93 and 99), where MQL4 has no forward reference
// for a global.

//==============================================================================
// P-VIEW-05 (2026-09-30) — THE CHART IS THE WITNESS; THE STAMP IS ONLY A CLAIM.
//
// The user's report, third time: «هنوز موقع تعویض تایم فریم سطوح حذف و رسم مجدد داره»
// — on a timeframe switch the levels are deleted and drawn again from zero. The
// wipe on that path has ONE author (`shouldClearLevels`), and it can only be true
// on a freshly reloaded instance for one of two reasons: `g_forceClearOnNextDraw`
// (raised by the frame when `!g_adoptPreviousTopology`) or a topology-signature
// difference. Both reduce to the SAME fact: this function said NO.
//
// And it can say NO without a word. The old body opened with
// `if(!GlobalVariableCheck(n)) return;` — a GlobalVariable that is not there (a
// first attach, a stamp a removing teardown deleted, the terminal's own variable
// store having been rewritten) returned with `adopt = false` and printed
// NOTHING, because the warning below is in the OTHER branch. So a timeframe
// switch could wipe ~900 objects with no line in the log naming it, which is
// exactly the "who deletes my levels" question this project keeps re-opening.
//
// Two changes, both measured by the one line below:
//
//   1. THE OBJECTS THEMSELVES ARE THE SECOND WITNESS. "Adopt" means one thing -
//      do NOT delete the family before re-asserting it - and its safety does not
//      depend on the inputs matching, because every render sweeps what it did not
//      produce (`CleanupSurplusPipeline`, `SweepForeignLadderObjects`, the label
//      sweep). A chart that is still HOLDING the family is therefore proof
//      enough: a wipe would delete objects that are about to be re-priced in
//      place, which is precisely the delete+draw the user sees. `preexist > 0`,
//      read off the chart, is that proof; the input fingerprint is kept as the
//      second (cheaper) way to reach the same verdict.
//   2. THE VERDICT IS ALWAYS PRINTED. One line per attach, so the next report is
//      `preexist=577 adopted=1` or `preexist=0 adopted=0` instead of a wipe with
//      no author. Cost: ONE chart-object walk per instance, at attach.
//
// The handoff side prints its own `probe=handoff` line from the teardown, so the
// pair "what the chart held when we left" / "what it holds when we come back" is
// two numbers in one log — which is also the only honest way to answer "does the
// terminal delete our objects on a period change, or do we".
//==============================================================================
int LevelFamilyObjectsOnChart()
{
   // ONE walk of the chart's object list, ONCE per instance (attach and, with the
   // handoff line, once per timeframe switch). The prefix is the timeframe-free
   // level namespace, so the count is the level family and nothing else.
   int total = ObjectsTotal(0, -1, -1);
   if(total <= 0) return 0;
   string prefix = GetLevelObjectPrefix();
   if(StringLen(prefix) <= 0) return 0;
   int found = 0;
   for(int i = 0; i < total; i++)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(StringLen(nm) <= 0) continue;
      if(StringFind(nm, prefix) != 0) continue;
      found++;
   }
   return found;
}

void ResolveTopologyAdoption()
{
   g_adoptPreviousTopology = false;
   string n = AdoptionStampName();
   bool haveStamp = GlobalVariableCheck(n);
   int stored = haveStamp ? (int)GlobalVariableGet(n) : 0;
   int live = AdoptionFingerprint();
   bool stampOk = (haveStamp && stored == live);
   // The chart's own answer, independent of every GlobalVariable above.
   int preexist = LevelFamilyObjectsOnChart();
   // The chart-truth witness is used for the branch the report is about: the
   // levels are SHOWN and the indicator is not hidden, so "the family is on the
   // chart" can only mean "do not delete it". The hidden/levels-off states keep
   // their previous (stamp-only) verdict: they own their objects through masks and
   // an explicit clear, and this probe has no business rewriting that path.
   bool familyHere = (preexist > 0 && inpShowTHLevels && !IsIndicatorHidden());
   g_adoptPreviousTopology = (stampOk || familyHere);
   // P-PERF-38e: a stamp that is PRESENT and mismatched still names its terms —
   // that is a genuine input change (mode, max levels, start point, LS-first,
   // harmonic pair) and the wipe is the correct answer for it.
   if(haveStamp && !stampOk)
      _LOG_GATE_W Print("[W][GEN] P-PERF-38e: topology stamp mismatch (stored fp=", stored,
                        " live fp=", live, " mode=", (int)GetCurrentStepMode(),
                        " maxLv=", inpMaxLevels, " sp=", (int)g_thStartPointType,
                        " lsFirst=", (inpLSFirst ? 1 : 0), ")");
   // UNGATED on purpose: this line is the author of the wipe, or the proof there
   // was none. See the block comment above.
   Print("[P-VIEW] probe=adopt stamp=", (haveStamp ? 1 : 0), " stored=", stored,
         " live=", live, " preexist=", preexist, " adopted=", (g_adoptPreviousTopology ? 1 : 0),
         " total=", ObjectsTotal(0, -1, -1));
}

//==============================================================================
// P-UI-56 — the custom-price SOURCE has ONE owner and ONE precedence. The whole
// level family is anchored on `GetMidpointPrice(g_thStartPointType)` ->
// `g_customTHStartPrice`, and it was resolved by TWO copies of the same
// three-branch chain (here and in RedrawAllObjects) carrying two defects that only
// a used chart shows: (1) the persisted placement was keyed per SYMBOL, so two
// charts of one symbol shared one price; (2) the INPUT silently outranked and
// OVERWROTE the placement keys. ONE owner answers "what is the custom price of
// THIS chart?": the user's own chart-keyed placement BEATS the static input, and
// the input is only the seed when the chart has no placement of its own — it never
// writes the placement keys (so the OFF paths still return to the input).
//==============================================================================
string CustomPriceGVName()         { return "Biotak_CustomPrice_" + GetCachedChartIdStr(); }
string CustomPriceOverrideGVName() { return "Biotak_CustomPriceOverride_" + GetCachedChartIdStr(); }
// The PREVIOUS scheme's keys (symbol-scoped). Read once, ONLY to adopt a price an
// older build left behind; never written again (only purged on REASON_REMOVE).
string CustomPriceLegacyGVName()         { return "Biotak_CustomPrice_" + GetCachedSymbol(); }
string CustomPriceLegacyOverrideGVName() { return "Biotak_CustomPriceOverride_" + GetCachedSymbol(); }

void CustomPriceMigrateLegacyKeys()
{
    static bool s_migrationDone = false;
    if(s_migrationDone) return;
    s_migrationDone = true;                                  // one probe per instance, never per frame
    if(GlobalVariableCheck(CustomPriceGVName())) return;     // this chart owns a price already
    string legacy = CustomPriceLegacyGVName();
    if(!GlobalVariableCheck(legacy)) return;
    double legacyPrice = GlobalVariableGet(legacy);
    if(!(legacyPrice > 0.0) || !MathIsValidNumber(legacyPrice)) return;
    // Is the legacy price a USER PLACEMENT or an input-seeded copy? It matters:
    // a placement must outrank the input, an input seed must not. Provable from the
    // old writers - only ONE of them wrote the price key from a non-user source,
    // and that one (the init/frame INPUT branch) wrote `inpCustomTHStartPrice`
    // itself. So: with the input unset the legacy price can only be a placement;
    // with the input set, the legacy override flag is the only trustworthy witness.
    string legacyFlag = CustomPriceLegacyOverrideGVName();
    bool legacyOverride = GlobalVariableCheck(legacyFlag) ? (GlobalVariableGet(legacyFlag) != 0.0) : false;
    bool legacyIsPlacement = legacyOverride || !(inpCustomTHStartPrice > 0.0);
    GlobalVariableSet(CustomPriceGVName(), legacyPrice);
    GlobalVariableSet(CustomPriceOverrideGVName(), legacyIsPlacement ? 1.0 : 0.0);
    _LOG_GATE_I Print("[I][GEN] P-UI-56: adopted the symbol-scoped custom price ",
                      DoubleToString(legacyPrice, Digits), " as this chart's own (",
                      legacyIsPlacement ? "placement" : "input seed", ")");
}

// ONE writer for "the user placed / moved the line on THIS chart".
void CustomPricePersistPlacement(const double price)
{
    if(!(price > 0.0) || !MathIsValidNumber(price)) return;
    GlobalVariableSet(CustomPriceGVName(), price);
    GlobalVariableSet(CustomPriceOverrideGVName(), 1.0);
}

// ONE writer for "this chart has no placement of its own" (the OFF paths).
void CustomPriceForgetPlacement()
{
    GlobalVariableDel(CustomPriceGVName());
    GlobalVariableSet(CustomPriceOverrideGVName(), 0.0);
}

// The resolver's result. Ints, not an enum: both call sites are ABOVE this block
// in the translation unit, and MQL4 type resolution is positional.
#define CPSRC_NONE   0   // no placement and no input price → not the custom-price start point
#define CPSRC_PLACED 1   // the user's own price on this chart (wins over the input)
#define CPSRC_INPUT  2   // the Input's seed price (the "default state")

int CustomPriceResolveSource(double &priceOut, bool &overrideFlagOut)
{
    priceOut = 0.0;
    overrideFlagOut = false;
    CustomPriceMigrateLegacyKeys();

    string priceKey = CustomPriceGVName();
    string flagKey  = CustomPriceOverrideGVName();
    double placed = GlobalVariableCheck(priceKey) ? GlobalVariableGet(priceKey) : 0.0;
    bool   placedFlag = GlobalVariableCheck(flagKey) ? (GlobalVariableGet(flagKey) != 0.0) : false;
    if(placed > 0.0 && MathIsValidNumber(placed)) {
        // The flag only decides WHO WINS (this chart's placement or the Input) - the
        // stored price is honoured either way, exactly like the old chain, whose
        // branch 1 and branch 3 restored the SAME price and differed only by that
        // flag. Keeping that asymmetry is what lets a parameter change put the start
        // point back on the Input default while the price survives for later.
        if(placedFlag) {
            priceOut = placed;
            overrideFlagOut = true;
            return CPSRC_PLACED;
        }
        if(inpCustomTHStartPrice > 0.0 && MathIsValidNumber(inpCustomTHStartPrice)) {
            priceOut = inpCustomTHStartPrice;
            return CPSRC_INPUT;
        }
        priceOut = placed;
        return CPSRC_PLACED;
    }
    if(inpCustomTHStartPrice > 0.0 && MathIsValidNumber(inpCustomTHStartPrice)) {
        priceOut = inpCustomTHStartPrice;
        return CPSRC_INPUT;
    }
    return CPSRC_NONE;
}

//+------------------------------------------------------------------+
//| P-ARCH-03 (2026-09-29) — TWO BUILDS, ONE CHART, ONE SET OF NAMES.|
//|                                                                  |
//| Lite is Full minus features, NOT a differently named family:     |
//| both units paint the SAME object names (that is what makes a     |
//| switch between them keep the chart). Two of them on one chart is  |
//| therefore two writers per name — one deletes what the other drew, |
//| the countdown is re-created twice a second, the TRex card's inks  |
//| have two owners, and a whole price band can stay missing while    |
//| the other half is drawn correctly. That is exactly the report     |
//| this session chased: «سطوح حذف میشه ولی دیگه نمیاد» + «ثانیه شمار  |
//| هی حذف و رسم میشه» + «رنگ آبی TR عوض میشه» + the empty band in   |
//| the user's screenshot — ALL ONE CAUSE, and the user FOUND it by   |
//| removing the Lite unit from the chart. MEASURED, from the         |
//| terminal's own log (EURUSD,M15):                                  |
//|   23:23:44.792  BiotakProject\Biotak Trigger TH3 Lite  loaded     |
//|   23:23:44.875  BiotakProject\Biotak Trigger TH3       loaded     |
//|                                                                  |
//| The oracle is the CHART's own list, never a global variable and   |
//| never a marker object: it cannot go stale, it cannot survive a    |
//| crash, and it is the same list the Navigator shows. A unit that   |
//| finds a second one REFUSES to initialise, so the chart says so    |
//| instead of quietly painting a wrong picture.                      |
//|                                                                  |
//| Cost: one chart enumeration at init only (no per-frame work).     |
//+------------------------------------------------------------------+
bool TH3SiblingUnitOnChart()
{
   string mine = "Biotak Trigger TH3";
   #ifdef BUILD_LITE
      mine = mine + " Lite";
   #endif
   int total = ChartIndicatorsTotal(0, 0);
   int th3 = 0, other = 0;
   string names = "";
   int mineLen = StringLen(mine);
   for(int i = 0; i < total; i++)
   {
      string nm = ChartIndicatorName(0, 0, i);
      if(nm == "") continue;
      if(StringFind(nm, "Biotak Trigger TH3") < 0) continue;   // not our family
      th3++;
      if(names != "") names += " + ";
      names += nm;
      // A DIFFERENT UNIT is a name that does not end with ours. The folder prefix
      // (`BiotakProject\`) is not part of the identity, the tail is.
      if(StringLen(nm) < mineLen || StringSubstr(nm, StringLen(nm) - mineLen) != mine) other++;
   }
   // `other > 0`: a sibling of the other unit (or the same-name file from another
   // folder) is attached. `th3 > 1`: two entries that BOTH spell our own name —
   // that is two attachments of one unit and the same interference.
   if(other > 0 || th3 > 1)
   {
      Print("[E][ARCH] P-ARCH-03: ", th3, " builds of this indicator on ONE chart: ", names,
            " — they paint the SAME object names, so each one deletes what the other drew "
            "(missing price bands, a countdown re-created every second, two writers on the "
            "TRex card's colours). This unit will not load. Remove all but ONE and re-add it.");
      return true;
   }
   return false;
}

int OnInitHandler() {
    // P-ARCH-03: the one-chart-one-unit rule lands before ANY observable work — before
    // the legacy sweep, before the settings seed, before a single object. A refused
    // unit must not have touched the chart it refuses to share.
    if(TH3SiblingUnitOnChart()) return INIT_FAILED;
    // P-PERF-38c: the one-time legacy sweep must land before the first render, so
    // a chart drawn by an older build cannot blend two naming schemes.
    MigrateTimeframeNamedObjects();
    // P-PERF-10: phase ledger for the init path (see g_pInitMs* in GlobalVariables).
    uint pInitTick = GetTickCount();
    // Seed runtime settings from the real MT4 Inputs-dialog values FIRST:
    // every inpX read from here on is the runtime copy (see RuntimeSettings.mqh).
    RuntimeSettingsInit();
    //--- P-BUILD-08 (2026-09-29, supersedes P-UI-134/134b/134c) — THE LINE IS THE
    //--- CODE, BEFORE ANY CLOCK OR TAG CAN LIE ABOUT IT.
    //--- The old tag was a hand-typed word ("T2") that stayed "T2" across every
    //--- build of 09-29, so a chart holding an hours-old ex4 printed the same line
    //--- as the fresh one — measured: the tab track read -16924895 (0xFEFDBF21) on
    //--- an ex4 that predated the P-DRAW-89 tone fix while this tree computes
    //--- 2892316 = RGB(28,34,44). `TH3_BUILD_TAG` is now `TH3_SRC_HASH`, a SHA-256
    //--- over the bytes this unit compiles (Biotak/BuildHash.mqh, generated by the
    //--- build), so the stamp changes when and only when the code does; `srcfile=`
    //--- prints the hash the last build wrote beside this terminal and `match=NO`
    //--- is a chart running an older ex4, said out loud instead of inferred.
    //--- `__DATETIME__` answers "when was this compiled" and is kept as the clock;
    //--- it cannot answer "which code" — a compile fed a stale DrawStrip.mqh
    //--- answers "now" (measured on the 19:02:42 ex4, whose TABCENSUS printed a
    //--- tone the current StrapBodyTone cannot produce: its whole output space is
    //--- R 18-29, G 22-35, B 29-46).
#ifndef BUILD_LITE
    // P-BUILD-01: the strip is a Full surface, so the Lite unit has neither the
    // names nor the functions — the probe lives where the strip does (compile error
    // 256/168 on the 2026-09-29 Lite build was this line read without the guard).
    int probeTone = (int)StrapBodyTone(DSTRIP_BODY_TOP, DSTRIP_GEAR_GRID_TOP - DSTRIP_BODY_TOP, 314);
    int probeFill = (int)DrawStripPlateFill();
    //--- P-UI-134c: the probe now prints the PARTS, not only the answer. Measured
    //--- 2026-09-29 19:28: the same build printed `tracktone=-16924895` while this
    //--- file's arithmetic for `StrapBodyTone(2,96,314)` is 2892316 = RGB(28,34,44),
    //--- and the compiler's own include trail named this repo's DrawStrip.mqh. So one
    //--- of the three inputs is not what the source says — the stops, the ramp, or the
    //--- plate fill — and these five numbers name WHICH one. `rampAt159` is 2892316
    //--- when the ramp is the cards' own; `cardTop/panel/foot` are 1971742/2432023/
    //--- 1906194 when the stops are BIO_CLR_CARD_TOP/PANEL/FOOT.
    int probeMid  = (int)BioCardTone(0.1592);
    int probeTop  = (int)BIO_CLR_CARD_TOP;
    int probePan  = (int)BIO_CLR_PANEL;
    int probeFoot = (int)BIO_CLR_FOOT;
    int probeCard = (int)BIO_CLR_CARD;
    //--- P-BUILD-10: the three INKS the report names, read out of the runtime copies
    //--- the card and the countdown actually paint with. clrBlue is 255 (0x0000FF) and
    //--- clrRed is 255<<0... `tr=255` is the shipped bold blue the user asked for; any
    //--- other number here is the ink the label will wear, said out loud at attach.
    int probeTR   = (int)g_atrTradeTRColor;
    int probeEX   = (int)g_atrTradeExColor;
    int probeCD   = (int)g_countdownColor;
#endif
#ifdef BUILD_LITE
    Print("[BUILD] TH3 src=", TH3_BUILD_TAG, " files=", TH3_SRC_FILES, " LITE compiled=",
          TimeToString(__DATETIME__, TIME_DATE|TIME_SECONDS),
          TH3SourceStampTail());
#else
    //--- the probe numbers stay: they are READ OUT OF THE COMPILED FUNCTIONS at the
    //--- arguments the tab track itself asks for, so a compile that shipped stale
    //--- strip code under a fresh stamp still shows it here —
    //--- StrapBodyTone(2,96,314)=2892316 = RGB(28,34,44), plateFill=2432023, and
    //--- the five stop/ramp values name WHICH input drifted.
    Print("[BUILD] TH3 src=", TH3_BUILD_TAG, " files=", TH3_SRC_FILES, " FULL compiled=",
          TimeToString(__DATETIME__, TIME_DATE|TIME_SECONDS),
          TH3SourceStampTail(),
          " tracktone=", probeTone, " plateFill=", probeFill,
          " rampAt159=", probeMid, " cardTop=", probeTop, " panel=", probePan,
          " foot=", probeFoot, " card=", probeCard,
          " tr=", probeTR, " ex=", probeEX, " cd=", probeCD);
    //--- P-BUILD-09 (2026-09-29) — THE RAMP, SAMPLED. Measured with the stamp above:
    //--- `rampAt159=2138660689` = 0x7F795F51 and `tracktone=-16924895` = 0xFEFDBF21
    //--- both carry a NON-ZERO alpha byte, which `return (color)(r | (g << 8) |
    //--- (bl << 16))` cannot produce from three byte-sized channels (ConstantsAndEnums
    //--- 1141). The stops themselves are correct in the same run (cardTop=3089438 =
    //--- C'30,36,47', panel=2432023 = C'23,28,37', foot=1906194 = C'18,22,29'), so the
    //--- defect is in the ramp's own arithmetic — and a value nobody measured cannot
    //--- be fixed. These seven numbers are that measurement: four points ON the stops
    //--- must come back as the stop itself (t=0 -> cardTop, t=0.52 -> panel,
    //--- t=1 -> foot) and `mid100` must read 52 (BIO_CARD_MID_T x 100).
    Print("[BUILD] ramp t0=", (int)BioCardTone(0.0),
          " t26=", (int)BioCardTone(0.26), " t52=", (int)BioCardTone(0.52),
          " t76=", (int)BioCardTone(0.76), " t100=", (int)BioCardTone(1.0),
          " mid100=", (int)(BIO_CARD_MID_T * 100.0));
#endif
    InitializeGlobalCache();
    LoggerSetLevel(inpLogLevel);
    // P-UI-90: resolve "what is the user's view pair on THIS chart?" before any
    // owner can take the lock, and heal a chart an older build left locked (see
    // the block note in GlobalVariables.mqh). Two chart reads + three GVar reads.
    ChartViewLockInit();
    // P-PERF-02: a fresh instance knows nothing about the visibility masks the
    // previous one left on the chart (and re-attach / TF switch reuses the same
    // chart objects), so every guarded mask write must land once. The
    // hide-once state starts clean for the same reason.
    BumpTfEpoch();
    ResetHideAllState();
    // P-PERF-07: a fresh instance can see objects the previous one left on the
    // chart (re-attach / TF switch reuses the same chart), so the previous
    // instance's "this name is absent" facts are not trustworthy yet.
    CacheAbsentResetAll();
    HRayOnInit(); PathOnInit();   // P-HR-06 / P-UI-136: adopt the chart's drawings into the registry (idempotent)

    // Restore hidden state
    string gvar_name = "Biotak_isHidden_" + GetCachedChartIdStr();
    bool shouldBeHidden = RestoreBoolGlobalVar(gvar_name, false);
    DEBUG_PRINTF("OnInit: shouldBeHidden=", shouldBeHidden);

    string chartIdStr = GetCachedChartIdStr();
    datetime initNow = TimeCurrent();

    // Timeframe-switch debounce: detect recent TF change (within 20s)
    string tfSwitchStampGvar = "Biotak_LastTFSwitch_" + chartIdStr;
    bool recentTimeframeSwitch = false;
    if(GlobalVariableCheck(tfSwitchStampGvar)) {
        datetime lastTFSwitch = (datetime)GlobalVariableGet(tfSwitchStampGvar);
        if(initNow > 0 && lastTFSwitch > 0 && (initNow - lastTFSwitch) <= 20)
            recentTimeframeSwitch = true;
    }

    // Restore toggle states (early, before validation)
    g_triggerLevelsEnabled = RestoreBoolGlobalVar("Biotak_TriggerLevels_" + chartIdStr, inpShowTrigger);
    g_linesVisible = RestoreBoolGlobalVar("Biotak_LinesVisible_" + chartIdStr, inpShowLines);

    // Restore ATR labels visibility (Default to OFF on first load)
    g_atrLabelsVisible = RestoreBoolGlobalVar("Biotak_ATRLabels_" + chartIdStr, false);

    // Restore TH labels mode (Default OFF: 0=OFF, 1=FRACTAL, 2=STANDARD exclusive)
    string thLabelsGvarName = "Biotak_THLabels_" + chartIdStr;
    if(GlobalVariableCheck(thLabelsGvarName)) {
        double gvarValue = GlobalVariableGet(thLabelsGvarName);
        bool isZero = MathAbs(gvarValue - 0.0) < EPSILON_GENERAL;
        bool isOne = MathAbs(gvarValue - 1.0) < EPSILON_GENERAL;
        bool isTwo = MathAbs(gvarValue - 2.0) < EPSILON_GENERAL;
        bool isThree = MathAbs(gvarValue - 3.0) < EPSILON_GENERAL;
        if(isZero || isOne || isTwo || isThree) {
            g_thLabelsMode = (int)gvarValue;
            if(g_thLabelsMode == 3) g_thLabelsMode = 2; // legacy BOTH -> STANDARD
            SyncTHFlagsFromMode();   // flags follow the restored mode
        } else {
            _LOG_GATE_E Print("[E][GEN] OnInit: Corrupted TH labels state (", DoubleToString(gvarValue, 10), "), resetting");
            g_thLabelsMode = 0; // Default to OFF
            GlobalVariableSet(thLabelsGvarName, 0.0);
            g_thLabelsVisible = false;
        }
    } else {
        // First attach: honor the Inputs-dialog TH flags, default ON is STANDARD.
        g_thLabelsMode = THModeFromFlags();
        if(g_showTHLabels && g_thLabelsMode == 0) g_thLabelsMode = 2;
        SyncTHFlagsFromMode();
    }

    //+------------------------------------------------------------------+
    //| P-UI-119 (2026-09-25) — THE LEVEL AND ZONE FAMILIES START OFF,    |
    //| ONCE PER CHART (user order «سطوح هم پیش فرض خاموش باشه»).           |
    //|                                                                  |
    //| The INPUTS default every one of them off now, but the states     |
    //| restored just above are PER CHART — so a chart that ever had a   |
    //| family on keeps it on for ever, and the new default would never  |
    //| be visible to anyone who has used the chart before. A default is |
    //| only real when it is applied to what is ALREADY stored, so this  |
    //| runs once per chart (the stamp idiom the timeframe-name migration|
    //| above uses) and then never again: from the next attach on the    |
    //| saved state is the user's own again.                             |
    //|                                                                  |
    //| What it covers — the level/zone families the loader above reads   |
    //| KEYS for: the trigger ladder, the hand-drawn level LINES           |
    //| (`inpShowLines`' own label), the TH labels and the mid-zone band  |
    //| (whose key spelling belongs to RuntimeSettings, so the asking is   |
    //| delegated — one owner per key). The ATR/trade LABEL blocks are    |
    //| not levels and are left exactly as the user set them.             |
    //+------------------------------------------------------------------+
    string levelsOffStamp = "Biotak_LevelsOffDefault_" + chartIdStr;
    if(!GlobalVariableCheck(levelsOffStamp)) {
        GlobalVariableDel("Biotak_TriggerLevels_" + chartIdStr);
        GlobalVariableDel("Biotak_LinesVisible_"  + chartIdStr);
        GlobalVariableDel("Biotak_THLabels_"      + chartIdStr);
        MidZonesStateForget();          // the mid-zone band's own key (RuntimeSettings owner)
        g_triggerLevelsEnabled = false; // ...and the runtime copies, so THIS attach is clean too
        g_linesVisible         = false;
        g_thLabelsMode         = 0;
        SyncTHFlagsFromMode();          // the TH flag mirrors follow the single source of truth
        g_showMidZones         = false;
        GlobalVariableSet(levelsOffStamp, 1.0);
    }

    int validationResult = ValidateInputs();
    if(validationResult != INIT_SUCCEEDED) return validationResult;
    g_pInitMsSettings = GetTickCount() - pInitTick;   // P-PERF-10
    pInitTick = GetTickCount();

    ChartSetInteger(0, CHART_EVENT_OBJECT_DELETE, true);
    ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
    // P-UI-127 (2026-09-25): THE CREATE CHANNEL IS SUBSCRIBED AT LAST. MT4 sends
    // no CHARTEVENT_OBJECT_CREATE until this flag is set, and the handler's whole
    // `if(id == CHARTEVENT_OBJECT_CREATE)` branch (P-UI-100b's "this gesture is a
    // DRAW, not a grab" and P-DRAW-01's `DrawStyleApplyOnCreate`) had therefore
    // never run in any build: `s_drawNotGrab`'s only writer is unreachable without
    // it. The branch's own cost is one prefix test per foreign create, which is
    // exactly what the flag limits it to — our own objects never reach it.
    ChartSetInteger(0, CHART_EVENT_OBJECT_CREATE, true);
    ChartSetInteger(0, CHART_SHOW_GRID, false);
    // 250 ms cadence (not 1 s): hold-to-open polling + hint pumps stay
    // responsive on tick-less charts (weekends). Every OnTimer callee is
    // time-gated / change-guarded / idempotent, so 4 Hz is free.
    EventSetMillisecondTimer(250);
    CheckArraySizes();

    // Deferred init: skip heavy historical load on recent TF switch
    bool deferHeavyInit = recentTimeframeSwitch;
    if(!deferHeavyInit) {
        if(!UpdateHistoricalValues()) {
            // P-MT5-01b (2026-09-16): A NOT-YET-LOADED HISTORY IS A DEFERRAL, NOT A FATAL.
            //
            // This used to `return INIT_FAILED`. That aborts the whole
            // initialisation, so the terminal renders an indicator that never
            // draws anything - and the live MT5 log carries precisely that
            // abort 17 times in one day, as "[E][GEN] OnInit:
            // UpdateHistoricalValues failed. Error: 4401"
            // (ERR_HISTORY_NOT_FOUND), on the symbols whose top timeframe the
            // terminal had not built yet (SPXUSD-ECN H1 among them).
            //
            // MT4 CANNOT REACH THIS BRANCH: its series are resident, so iBars()
            // never answers 0. The MT4-observable behaviour is therefore "init
            // succeeds and the levels appear", and that is what MT5 must show
            // too. So rather than invent a recovery path, fall through to the
            // deferral the recent-TF-switch branch beside it already uses:
            // g_initialized stays false, and RedrawAllObjects - which tests
            // exactly that flag - retries this call every frame, logs that it is
            // retrying, and draws the moment the data lands.
            //
            // The warning is rate-limited so a genuinely unavailable symbol
            // cannot flood Experts; a re-request is issued by
            // UpdateHistoricalValues itself (P-MT5-01b), so the retry converges
            // instead of polling a series nobody asked for.
            static uint s_lastHistInitWarnMs = 0;
            uint histInitNowMs = GetTickCount();
            if(histInitNowMs - s_lastHistInitWarnMs > 30000) {
                _LOG_GATE_W Print("[W][GEN] OnInit: historical data not ready (err ",
                                  GetLastError(), ") - deferring; the redraw path retries");
                s_lastHistInitWarnMs = histInitNowMs;
            }
            g_initialized = false;
        } else {
            g_initialized = true;
        }
    } else {
        g_initialized = false;
    }
    g_calculatedOnce = false;
    InitializeAdaptiveScaling();

    g_dailyClosePriceForTH = GetPriceForPreviousDay(inpTHPriceType);
    if(g_dailyClosePriceForTH == EMPTY_VALUE || !MathIsValidNumber(g_dailyClosePriceForTH) || g_dailyClosePriceForTH <= 0) {
        // P-MT5-01b (2026-09-16): DEFER, DO NOT ABORT.
        //
        // GetPriceForPreviousDay now answers EMPTY_VALUE while the D1 series has
        // never been readable (MT5 synthesises it on demand; see the guard in
        // HistoricalDataFunctions.mqh), because the alternative was worse: it
        // used to return a stamped 0 for a full day, which made the TH base
        // price - and therefore the whole level family - zero.
        //
        // Returning INIT_FAILED here would just move the failure, so this takes
        // the same deferral the history branch above takes: g_initialized stays
        // false, RedrawAllObjects retries, and the first redraw frame runs
        // UpdateBasePrice() (its 30-minute gate is empty on a fresh instance,
        // so it fires immediately and fills g_basePriceCached), which is what
        // GetBasePriceForTH() reads. No new recovery path - the one that already
        // exists is simply no longer bypassed by an aborted init.
        //
        // The wider test (non-finite, negative, zero) is the P-UI-57 discipline:
        // a NaN is neither > 0 nor < 0, so a strict `== EMPTY_VALUE` would let
        // it through and it would become the anchor of every level.
        g_dailyClosePriceForTH = 0.0;
        g_initialized = false;
        static uint s_lastPrevDayWarnMs = 0;
        uint prevDayNowMs = GetTickCount();
        if(prevDayNowMs - s_lastPrevDayWarnMs > 30000) {
            _LOG_GATE_W Print("[W][GEN] OnInit: previous-day prices not ready (D1 series still loading) - deferring");
            s_lastPrevDayWarnMs = prevDayNowMs;
        }
    }
    g_pInitMsHistory = GetTickCount() - pInitTick;   // P-PERF-10
    pInitTick = GetTickCount();

    // P-UI-56: no local GVar names here any more - the custom-price source (and its
    // keys) have ONE owner in this file (see the P-UI-56 block above), and the
    // resolution below asks it instead of re-implementing the chain.
    int digits = Digits;

    // Validate custom price input
    double validatedCustomPrice = inpCustomTHStartPrice;
    // P-UI-57: a non-finite input price is not "negative" and not "too large" —
    // every comparison against NaN is false, so it would sail through both checks
    // below and become the anchor of the whole level family.
    if(!MathIsValidNumber(validatedCustomPrice)) {
        _LOG_GATE_E Print("[E][GEN] OnInit: Invalid custom price (not a number)");
        validatedCustomPrice = 0.0;
    }
    if(validatedCustomPrice < 0.0) {
        _LOG_GATE_E Print("[E][GEN] OnInit: Invalid custom price (negative): ", validatedCustomPrice);
        validatedCustomPrice = 0.0;
    }
    if(validatedCustomPrice > 1000000.0) {
        _LOG_GATE_E Print("[E][GEN] OnInit: Invalid custom price (too large): ", validatedCustomPrice);
        validatedCustomPrice = 0.0;
    }

    // P-UI-56: the source of the drawing price is resolved by ONE owner, shared
    // with the per-frame path (`RedrawAllObjects`): THIS chart's placement first,
    // the Input's seed second, nothing third - and the Input NEVER writes the
    // placement keys, so a price the user dragged can no longer be replaced by the
    // value in the Inputs dialog on the next attach.
    //
    // The old init chain also wrote `GlobalVariableSet(gvarName, input)` in its
    // input branch while the per-symbol keys were shared by every chart of the
    // symbol - the mechanism behind "each time the levels go somewhere else".
    double srcPrice = 0.0;
    bool   srcOverride = false;
    int    srcKind = CustomPriceResolveSource(srcPrice, srcOverride);
    g_customPriceKeyboardOverride = srcOverride;
    #ifdef ENABLE_DEBUG_LOGS
    Print("[D][GEN] === Custom Price Debug (OnInit) ===");
    Print("[D][GEN] inpCustomTHStartPrice: ", inpCustomTHStartPrice, " validated: ", validatedCustomPrice);
    Print("[D][GEN] resolved price: ", srcPrice, " kind: ", srcKind);
    #endif
    if(srcKind != CPSRC_NONE) {
        g_customTHStartPrice = srcPrice;
        g_thStartPointType = TH_START_POINT_CUSTOM_PRICE;
        _LOG_GATE_I Print("[I][GEN] OnInit: custom price source=",
                          (srcKind == CPSRC_PLACED ? "this chart's placement" : "Input seed"),
                          " at ", DoubleToString(g_customTHStartPrice, digits));
        CreateCustomPriceLine(g_customTHStartPrice, digits);
    } else {
        g_customTHStartPrice = 0.0;
        g_thStartPointType = inpTHStartPointType;
        g_customPriceKeyboardOverride = false;
        CustomPriceForgetPlacement();
        DEBUG_PRINT("OnInit: Using default mode (no custom price)");
    }

    g_redrawTHLevelsNeeded = true;

    // Base price init debounce: skip if recently initialized during TF switch
    string baseInitStampGvar = "Biotak_BaseInit_" + chartIdStr;
    bool shouldInitBasePrice = true;
    if(deferHeavyInit && GlobalVariableCheck(baseInitStampGvar)) {
        datetime lastBaseInit = (datetime)GlobalVariableGet(baseInitStampGvar);
        if(initNow > 0 && lastBaseInit > 0 && (initNow - lastBaseInit) <= 120)
            shouldInitBasePrice = false;
    }
    if(shouldInitBasePrice) {
        InitializeBasePriceSystem();
        if(initNow > 0) GlobalVariableSet(baseInitStampGvar, (double)initNow);
    } else {
        g_systemInitialized = false;
    }
    g_pInitMsBase = GetTickCount() - pInitTick;   // P-PERF-10
    pInitTick = GetTickCount();

    // Restore timeframe lock state
    string lockFlagName = "Biotak_LockTF_" + chartIdStr;
    if(GlobalVariableCheck(lockFlagName)) {
        g_timeframeLocked = (bool)GlobalVariableGet(lockFlagName);
    }
    string lockPeriodName = "Biotak_LockTFPeriod_" + chartIdStr;
    if(GlobalVariableCheck(lockPeriodName)) {
        // R-TF-UNIT: this value outlives the process that wrote it. An MT5 build
        // from before the unit fix persisted an ENUM_TIMEFRAMES constant here
        // (16385 for H1), which would restore as a lock on a timeframe that does
        // not exist - the badge reading "16385" and every `tf == Period()` test
        // failing. CompatMinutes() normalises whatever is on disk to minutes, so
        // the upgrade is invisible to the user.
        g_lockedPeriod = CompatMinutes((int)GlobalVariableGet(lockPeriodName));
    }

    // VIEWLOCK-OFF: view-lock restore retired —
    //string viewFlagName = "Biotak_ViewLock_" + chartIdStr;
    //if(GlobalVariableCheck(viewFlagName)) {
    //    g_viewLockEnabled = (GlobalVariableGet(viewFlagName) > 0.5);
    //}
    //if(GlobalVariableCheck("Biotak_ViewAnchorT_" + chartIdStr)) {
    //    g_viewAnchorTime = (datetime)GlobalVariableGet("Biotak_ViewAnchorT_" + chartIdStr);
    //    g_viewAnchorMin = GlobalVariableGet("Biotak_ViewAnchorMin_" + chartIdStr);
    //    g_viewAnchorMax = GlobalVariableGet("Biotak_ViewAnchorMax_" + chartIdStr);
    //}
    //if(g_viewLockEnabled) {
    //    if(recentTimeframeSwitch && g_viewAnchorTime > 0) g_viewRestorePending = true;
    //    else { ViewLockCapture(); ViewAnchorLineEnsure(); }   // fresh attach: anchor = current view
    //}

    // STEPOVERRIDE-OFF: one-time migration — the retired override key becomes
    // the single base mode. (If the chart ALSO has an OV_ SM panel value, that
    // loads later in RuntimeSettingsLoadOverrides and wins — it is the newer
    // explicit choice.) The key is deleted and never read again.
    string stepModeGvarName = "Biotak_StepMode_" + chartIdStr;
    if(GlobalVariableCheck(stepModeGvarName)) {
        int migratedMode = (int)GlobalVariableGet(stepModeGvarName);
        if(migratedMode >= 0 && migratedMode <= 3) {
            g_stepCalculationMode = (ENUM_STEP_CALCULATION_MODE)migratedMode;
        } else {
            _LOG_GATE_W Print("[W][GEN] OnInit: Corrupted StepMode (", migratedMode, "), resetting.");
        }
        GlobalVariableDel(stepModeGvarName);
    }

    // Restore SS/LS sequence origin selected from the Custom Price menu
    // (0 = SS first, 1 = LS first, any other value = use input).
    // P-UI-67: the restore ADOPTS the persisted answer, through the owners - the
    // read happens first because the clear (which owns the key) deletes it, and an
    // absent or corrupt key must end as "the input answers", never as a bare
    // `= -1` that leaves the persisted value behind for the next attach to read.
    string sslsFirstGvarName = "Biotak_SSLSFirst_" + chartIdStr;
    bool sslsKeyPresent = GlobalVariableCheck(sslsFirstGvarName);
    int restoredSSLSFirst = sslsKeyPresent ? (int)GlobalVariableGet(sslsFirstGvarName) : -1;
    SSLSOrderOverrideClear();
    if(restoredSSLSFirst == 0 || restoredSSLSFirst == 1)
        SSLSOrderOverrideSet(restoredSSLSFirst);

    // Restore factor with validation (0 < val <= MAX_SAFE_FACTOR)
    string factorGvarName = "Biotak_Factor_" + chartIdStr;
    if(GlobalVariableCheck(factorGvarName)) {
        double val = GlobalVariableGet(factorGvarName);
        if(val > 0 && val <= MAX_SAFE_FACTOR) {
            g_factorValueOverride = val;
        } else {
            _LOG_GATE_E Print("[E][GEN] OnInit: Invalid Factor (", val, "), resetting.");
            GlobalVariableDel(factorGvarName);
            g_factorValueOverride = 0.0;
        }
    } else {
        g_factorValueOverride = 0.0;
    }
    // Manual mode factor clamping
    if(inpFactorMode == FACTOR_MODE_MANUAL) {
        if(inpFactorValue <= 0 || inpFactorValue > MAX_SAFE_FACTOR) {
            _LOG_GATE_E Print("[E][GEN] OnInit: Invalid inpFactorValue (", inpFactorValue, "), clamping to 50.0");
            g_factorValueOverride = 50.0;
        }
    }

    // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
#ifndef BUILD_LITE
    // Restore TH3 frequency with dynamic max validation (binary subdivision)
    string freqGvarName = "Biotak_TH3Freq_" + chartIdStr;
    if(GlobalVariableCheck(freqGvarName)) {
        double restoredFreq = GlobalVariableGet(freqGvarName);
        double maxFreq = GetFrequencyByIndex(MAX_TH3_FREQ_INDEX);
        if(restoredFreq > 0 && restoredFreq <= maxFreq) {
            g_th3FreqOverride = restoredFreq;
        } else {
            g_th3FreqOverride = 0;
            GlobalVariableDel(freqGvarName);
        }
    }
    string indexGvarName = "Biotak_TH3FreqIdx_" + chartIdStr;
    if(GlobalVariableCheck(indexGvarName)) {
        int restoredIndex = (int)GlobalVariableGet(indexGvarName);
        if(restoredIndex >= MIN_TH3_FREQ_INDEX && restoredIndex <= MAX_TH3_FREQ_INDEX) {
            g_th3FreqIndex = restoredIndex;
        } else {
            g_th3FreqIndex = DEFAULT_TH3_FREQ_INDEX;
            GlobalVariableDel(indexGvarName);
        }
    }
    // Binary subdivision migration: sync index with saved frequency (old GM -> binary)
    if(g_th3FreqOverride > 0) {
        double expectedFreq = GetFrequencyByIndex(g_th3FreqIndex);
        if(MathAbs(expectedFreq - g_th3FreqOverride) > 0.01) {
            g_th3FreqIndex = FindNearestFreqIndex(g_th3FreqOverride);
            g_th3FreqOverride = GetFrequencyByIndex(g_th3FreqIndex);
            GlobalVariableSet(freqGvarName, g_th3FreqOverride);
            GlobalVariableSet(indexGvarName, (double)g_th3FreqIndex);
            _LOG_GATE_I Print("[I][GEN] OnInit: TH3 Freq migrated to binary subdivision: idx=", g_th3FreqIndex,
                              " freq=", DoubleToString(g_th3FreqOverride, 4));
        }
    }
#endif

    InitializeATRCache();

    // ATR warmup debounce: skip if recently warmed up (within 90s)
    if(inpShowATRLabels && !shouldBeHidden) {
        datetime nowWarmup = TimeCurrent();
        string warmupGvar = "Biotak_ATRWarmup_" + chartIdStr;
        datetime lastWarmup = 0;
        if(GlobalVariableCheck(warmupGvar)) {
            lastWarmup = (datetime)GlobalVariableGet(warmupGvar);
        }
        if(lastWarmup <= 0 || nowWarmup <= 0 || (nowWarmup - lastWarmup) > 90) {
            WarmupATRMultiTFCache();
            if(nowWarmup > 0) GlobalVariableSet(warmupGvar, (double)nowWarmup);
        }
    }

    g_pInitMsAtr = GetTickCount() - pInitTick;   // P-PERF-10 (ATR cache init + warmup)

    PrintBuildInfo();

    // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
#ifndef BUILD_LITE
    // P-LM-04: a leg measurement drawn by an older build carries loose labels and
    // no plate; its readout is recomputed into today's box here — the same slot,
    // and the same rule, as the pattern restore below: legacy chart objects take
    // the current build's shape before the first render. It runs AFTER the ATR
    // warmup above on purpose: at attach a TF whose history is not loaded yet gives
    // no ATR, and the sweep refuses to write a box built on a guessed one.
    LegMeasureUpgradeLegacy();
    // P-TH3-D4h: legacy chart objects repaint with the current build first;
    // only when nothing was restored does the settings-change flag matter.
    int th3Restored = TH3RestorePatternsFromChart();
    // Check if TH3 objects need update (after settings change)
    string th3UpdateFlag = "Biotak_TH3_NeedsUpdate_" + chartIdStr;
    if(GlobalVariableCheck(th3UpdateFlag) && GlobalVariableGet(th3UpdateFlag) > 0) {
        if(th3Restored <= 0) UpdateAllTH3Objects();
        GlobalVariableDel(th3UpdateFlag);
    }
#endif

    #ifdef ENABLE_DEBUG_LOGS
    Print("[D][GEN] OnInit complete: deferred=", deferHeavyInit, " hidden=", shouldBeHidden);
    #endif

    // Hidden state: set flags (objects created later in OnCalculate/RedrawAllObjects)
    if(shouldBeHidden) {
        g_redrawTHLevelsNeeded = false;
    } else {
        g_redrawTHLevelsNeeded = true;
    }

    #ifdef ENABLE_ASSERTIONS
    FactorModeSanityCheck();
    #endif

    // P-PERF-38d: LAST thing before the first frame — every fingerprint input
    // (mode, max levels, start point, LS-first, harmonic) is final by now.
    ResolveTopologyAdoption();

    // P-DRAW-01/02 (2026-09-22): the drawing toolbar's own two tables — the
    // per-kind style memory and the preset slots (the built-in suggestions the
    // user overwrites). Seeded once per instance, before any drawing can exist.
    DrawStyleInit();
    DrawPresetsInit();
    DrawPresetsLoad();   // P-DRAW-05: the user's own templates survive the session

    return INIT_SUCCEEDED;
}

#endif // EVENT_HANDLERS_INIT_MQH
