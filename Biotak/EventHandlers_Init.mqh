// EventHandlers_Init.mqh - EventHandlers split 2026-09-29: exact lines 7-1496 of EventHandlers.mqh, byte-identical, zero renames.
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
    HRayOnInit();   // P-HR-06: adopt chart rays into the registry (idempotent)

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

// Helper function to create custom price horizontal line (DRY)
//
// P-UI-48: THE LINE IS ALWAYS GRABBABLE. "Why doesn't it move like it used
// to?" - because P-UI-45 answered the interference report by making a SETTLED
// line non-SELECTABLE, and the drag IS that flag. The interference was never
// selectability; it was a SELECTION THAT OUTLIVED ITS GESTURE:
//
//   * MT4 moves the SELECTED object on every later drag ANYWHERE on the chart,
//     so a line that stayed SELECTED was dragged along with the panel cards and
//     the BaseKnot boxes and kept re-anchoring the TH start price behind the
//     user's back;
//   * the old code wrote OBJPROP_SELECTED = true at creation, so this was the
//     line's state BEFORE any gesture of its own.
//
// So the flag pair is now: SELECTABLE true, ALWAYS (this is the movement), and
// SELECTED false, ALWAYS - MT4 selects the line ITSELF on the press that means
// to grab it (that is the moment the live-drag path polls for), and the
// selection it makes is dropped again on button-up (see
// ClearCustomPriceSelection + g_customPriceNativeDrag). Pre-selecting only ever
// enabled the hijack, and never selecting leaves the line as inert as it was
// before - both wrong. One wording for the tooltip too: every state of the line
// can be dragged and confirmed now, so a "PIN button to move" text would be a
// lie in the one place the user reads it.
bool CreateCustomPriceLine(double price, int digits,
                           string tooltipSuffix = "Drag to adjust, Double-click to confirm")
{
    if(ObjectFind(0, g_customPriceHorizontalLineName) < 0) {
        if(!ObjectCreate(0, g_customPriceHorizontalLineName, OBJ_HLINE, 0, 0, price)) {
            _LOG_GATE_E Print("[E][GEN] Failed to create custom price line. Error: ", GetLastError());
            g_customPriceLineCreated = false;
            return false;
        }
    } else {
        ObjectSetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, price);
    }
    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_COLOR, GetCustomPriceRenderColor());
    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_WIDTH, inpCustomPriceLevelWidth);
    // P-UI-98d: SELECTABLE follows the ARMED/SET state now — an armed line
    // drags (this IS the movement, P-UI-48), a set line is inert so no gesture
    // of any other object can steal it. The transitions go through the ONE
    // owner (CustomPriceLineOwnArm); this writer only re-asserts the state.
    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTABLE, g_cpLineArmed);
    // P-UI-98p: the line is NEVER painted - the green circle is the placement
    // (user order: «خط ابی کاستوم پرایس لازم نیست همین دایره سبز کفایت
    // میکنه»). The object stays (the drag math, the grab test and the ladder
    // anchor all read it), only its picture goes. Skipped mid-gesture like
    // the selection above (P-BK-15); the transitions re-assert below.
    if(!g_customPriceLineDragging && !g_customPriceNativeDrag &&
       (long)ObjectGetInteger(0, g_customPriceHorizontalLineName, OBJPROP_TIMEFRAMES) != OBJ_NO_PERIODS)
        ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
    // P-UI-45/P-UI-50: never LEAVE a selection in place - a line saved into the chart
    // profile arrives SELECTED, and MT4 then moves it along with every LATER gesture
    // anywhere on the chart (the interference P-UI-45 removed) - but never write it
    // while a gesture is live. This creator is reached from the click that confirms
    // the price, and that click can arrive while the button is still DOWN: a write on
    // the object MT4 is dragging cancels that drag (P-BK-15), which is the "the drag
    // is cut off very quickly" report. So it is a compare-and-write, skipped for the
    // whole duration of a gesture: one guarded read per call, and this creator only
    // runs on init / restore / mode change, never per frame.
    if(!g_customPriceLineDragging && !g_customPriceNativeDrag &&
       (bool)ObjectGetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED))
        ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED, false);
    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_ZORDER, Z_CHART_LABEL);   // P-UI-31
    ObjectSetString(0, g_customPriceHorizontalLineName, OBJPROP_TOOLTIP,
                  "[PIN] Custom Price: " + DoubleToString(price, digits) + " | " + tooltipSuffix);
    g_customPriceLineCreated = true;
    CustomPriceMarkerSync();   // P-UI-98d: the green dot rides the line's own writer
    return true;
}

// P-UI-48: the ONE owner of "drop the line's selection". MT4 selects a
// SELECTABLE object on the press that grabs it, and a selection that SURVIVES
// its gesture lets MT4 drag the line along with every later drag anywhere on the
// chart - the interference P-UI-45 removed by removing the movement. It is
// called from the button-up latch (the grab/click is over) AND from the UI press
// path (the press belonged to a panel or the ring, so the terminal's selection
// of the line must not outlive it). Guarded by the read: a no-op costs one
// ObjectGetInteger, and the write happens once per gesture.
void ClearCustomPriceSelection()
{
    if(!g_customPriceLineCreated) return;
    if(!(bool)ObjectGetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED)) return;
    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED, false);
}

//==============================================================================
// P-UI-98d — THE ARMED/SET MODEL OF THE TWO HAND-SET LINES, AND THEIR MARKERS.
//
// User order: «خط کاستوم پرایس و خط step اول وقتی بعد جابجایی روش کلیک شد ست
// نهایی بشه و با دبل کلیک فعال بشه؛ تا زمانی که ست نهایی نشده آزادنه درگ بشه»
// and the marker order: «نشانهٔ رنگی (خط کاستوم سبز، step اول قرمز)، یک نشانه
// باشه که خیلی مزاحم هم نباشه» + «وقتی لاین ها رو خاموش میکنم نشان ها هم نباشه».
//
// ARMED: the line answers MT4's own drag, and ONE small dot at the chart's
// right edge marks it (green for the custom price line, red for the step-1
// handles; time-0 anchoring — the pip labels' own — so it follows the market
// with no per-bar write). SET: the line is inert — nothing can grab it, which
// is also the "dragging other objects must not steal it" half — and the dot is
// DELETED, not masked, so no other mask writer can resurrect it. A single
// click sets; a double-click re-arms. The single click waits out the
// double-click window in the pending slot (the sweep commits it), so the first
// click of a double never sets first.
//
// The markers obey the LINES switch (g_linesVisible) and the hide-all state —
// «فقط لاین ها» — and are re-owned by the same passes that already run (the
// render for the step-1 dots, this sync for the custom line's).
// P-UI-98g (2026-09-22): they also obey the REVEAL latch — «فقط وقتی روش کلیک
// کردیم دایره ها بیاد برای درگ کردن» — so an armed-but-unasked line keeps its
// circle parked.
//==============================================================================
void CustomPriceMarkerSync()
{
    // P-UI-98m: in SET state the green circle is the only marker
    // (double-click the row to re-arm), so it shows WITHOUT the 98g reveal
    // latch; ARMED keeps the latch (a fresh placement is born ARMED-but-HIDDEN,
    // and an armed-but-unasked line shows nothing).
    // P-UI-98o: the green circle ignores the LINES switch - it marks the
    // custom price placement itself, not the line family, so L hides the
    // lines and the red circles but never it (hide-all still does).
    // P-UI-98p: the line itself is never painted at all - the circle below
    // is the whole face of the placement.
    // P-UI-98q: and the circle shows whenever the placement is live - ARMED
    // and SET, with no reveal latch and no LINES switch. A fresh placement
    // therefore shows its circle the moment custom price turns on, and it
    // stays through every toggle. The 98g latch survives only as the armed
    // click-flow state (first click asks, second commits). Hide-all still
    // hides it.
    bool show = g_customPriceLineCreated &&
                !IsIndicatorHidden() &&
                g_thStartPointType == TH_START_POINT_CUSTOM_PRICE;
    if(!show)
    {
        HandsetHandlePark(g_cpMarkerName, CP_HANDLE_RES);
        return;
    }
    double price = ObjectGetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, 0);
    if(!(price > 0.0) || !MathIsValidNumber(price))
    {
        HandsetHandlePark(g_cpMarkerName, CP_HANDLE_RES);
        return;
    }
    // the circular drag handle, centred on the line at the screen's middle
    HandsetHandleAt(g_cpMarkerName, price, CP_HANDLE_RES);
    // P-UI-98p: the line is never painted, so its circle carries the hover
    // text in both states. Guarded: one string compare, a write only on drift.
    {
        static string s_cpMarkTip = "";
        string tip = g_cpLineArmed
            ? "Custom price: drag the green circle - click to commit, double-click re-arms"
            : "Custom price (set) - double-click to re-activate";
        if(s_cpMarkTip != tip)
        {
            s_cpMarkTip = tip;
            ObjectSetString(0, g_cpMarkerName, OBJPROP_TOOLTIP, tip);
        }
    }
}

// P-UI-98d v2: the ride channel. A pan, a zoom or a window resize moves the
// price scale under the handles — the same stream the leg meter's discs ride
// (P-LM-16b): every MOUSE_MOVE / CHART_CHANGE re-projects, guarded (a still
// chart costs reads only, a write lands only on drift). The step-1 prices are
// the render's own answers, stashed by the face owner — and OUTSIDE the
// custom-price mode the stash is a stale answer, so the red handles park (a
// resurrected handle over a mode that no longer owns a ladder is the bug).
void HandsetMarkersRide()
{
    CustomPriceMarkerSync();
    if(g_thStartPointType != TH_START_POINT_CUSTOM_PRICE)
    {
        HandsetHandlePark(S1MarkName(1), S1_HANDLE_RES);
        HandsetHandlePark(S1MarkName(-1), S1_HANDLE_RES);
        return;
    }
    // P-UI-98e: the icon belongs to the ARMED pair: the price stash now also
    // carries a SET handle's address (the click contract needs it), so the ride
    // is what must not resurrect an icon over a line nothing can grab.
    // P-UI-98l: and the ride obeys the LINES switch and the hide-all state
    // like every other marker owner (CustomPriceMarkerSync, the face owner) -
    // without these terms the L key parked the circles through the render and
    // the very next mouse move put them back («لاین خاموش میکنم دایره هاش
    // میمونه»).
    if(g_s1LinesArmed && g_s1HandleShown && g_s1MarkAbovePrice > 0.0 && g_linesVisible && !IsIndicatorHidden())
        HandsetHandleAt(S1MarkName(1), g_s1MarkAbovePrice, S1_HANDLE_RES);
    else
        HandsetHandlePark(S1MarkName(1), S1_HANDLE_RES);
    if(g_s1LinesArmed && g_s1HandleShown && g_s1MarkBelowPrice > 0.0 && g_linesVisible && !IsIndicatorHidden())
        HandsetHandleAt(S1MarkName(-1), g_s1MarkBelowPrice, S1_HANDLE_RES);
    else
        HandsetHandlePark(S1MarkName(-1), S1_HANDLE_RES);
}

// P-UI-98e: A FRESH PLACEMENT IS BORN ARMED. The activation (the C key, the ring
// PIN) deletes the line and creates a new one at the screen's middle; the
// armed/set state is per PLACEMENT (P-UI-98d), so the new one must wake
// draggable even when the user had SET the previous line — otherwise the very
// first gesture on the fresh line is refused, and «قابل درگ کردن نیستش» returns
// for a second reason (the state, not the drag channel). ONE owner, called by
// both activation paths, so the two can never disagree about what "fresh" means.
void HandsetPlacementArm()
{
    g_cpLineArmed  = true;
    g_s1LinesArmed = true;
    g_cpSetPending = "";   g_cpSetPendingMs = 0;
    g_s1SetPending = "";   g_s1SetPendingMs = 0;
    // P-UI-98m: no re-arm candidate survives into a fresh placement.
    g_cpClickArmed = false;   g_cpClickY = 0;
    // P-UI-98g: a fresh placement is born ARMED but HIDDEN - the circles are the
    // answer to a click, and nothing has been clicked yet. The tooltip says so.
    g_cpHandleShown = false;
    g_s1HandleShown = false;
}

// The ONE owner of an armed/set TRANSITION of the custom price line. Guarded
// writes: never mid-gesture (P-BK-15), never on drift.
void CustomPriceLineOwnArm(const bool armed)
{
    // P-UI-101 (2026-09-22): A LOCKED LINE NEVER ARMS. The lock's promise is
    // «nothing moves it until I say so», and every way of grabbing this line runs
    // through this flag — the claim asks it first (P-UI-98d), the creator
    // publishes it as SELECTABLE, the double-click re-arm sets it. So the lock is
    // enforced HERE, in the one owner of the state, and not in a copy of the test
    // at each of those three places. (`want`, not `armed`: the parameter is const
    // by this function's own signature, and a lock is a REFUSAL, not a rewrite of
    // what the caller asked for.)
    bool want = (armed && !g_customPriceLocked);
    g_cpLineArmed = want;
    g_cpSetPending = "";
    g_cpSetPendingMs = 0;
    if(!g_customPriceLineCreated) return;
    if(g_customPriceLineDragging || g_customPriceNativeDrag) return;
    if((bool)ObjectGetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTABLE) != want)
        ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTABLE, want);
    if(!want) ClearCustomPriceSelection();
    // P-UI-98p: the mask is re-asserted, never lifted - the line is never
    // painted (see the creator), the green circle is the placement.
    if(ObjectFind(0, g_customPriceHorizontalLineName) >= 0 &&
       (long)ObjectGetInteger(0, g_customPriceHorizontalLineName, OBJPROP_TIMEFRAMES) != OBJ_NO_PERIODS)
        ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
    UpdateCustomPriceTooltip();   // the wording follows the state
    CustomPriceMarkerSync();
}

// P-UI-101 (2026-09-22) — THE PLACEMENT'S OWN LOCK, ONE OWNER.
//
// User order: «روی خط کاستوم پرایس که هولد کردم پنل تنظیماتش بازه بشه و بشه از
// اونجا قفلش کرد». The lock is not the armed/set state (P-UI-98d): SET is one
// click away from being undone (a double-click re-arms it), while the lock is
// released only from the panel. It is persisted with the placement, because the
// placement survives a re-attach and a lock that did not would be a lie after
// every recompile.
//
// The transition writes through the state owners, never around them: the armed
// owner (which is also the ONE enforcement point — see its own note) and the
// tooltip. A locked line is inert exactly like a SET one, so every law this
// project already measured for SET — no claim, no selection, no carry, no ride
// along with any foreign gesture — holds for it unchanged.
void CustomPriceLineOwnLock(const bool locked)
{
    if(g_customPriceLocked == locked) return;   // never write a state you would not change
    g_customPriceLocked = locked;
    CustomPriceLineOwnArm(!locked);             // locked = inert · unlocked = draggable again
    RuntimeSettingsSaveOverridesThrottled();    // the placement's lock outlives the session
}

//==============================================================================
// P-UI-98m — RE-ARMING A MASKED (SET) CUSTOM PRICE LINE (2026-09-22).
//
// User order: «وقتی سلکت نیس فقط همون دایره سبز بمونه ... خطو نشون نده».
// A masked line fires no OBJECT_CLICK, so the line's own click contract (which
// lives on that event) cannot wake it. The press edge still sees the row -
// CustomPriceGrabAt reads the object, masked or not - so the SET click is one
// owner reached from three edges, the step-1 shape: our own press/release
// pair on the mouse stream, the button-up finalize below (a motionless
// release emits no MOUSE_MOVE, P-BK-03), and the green circle's own
// OBJECT_CLICK. One physical click can reach it twice; a 60 ms twin guard
// drops the second. A single click here is a no-op (already set) and only a
// double re-arms, so no sweep slot is needed - the first click of a double
// can never commit anything.
//==============================================================================
void CustomPriceRearmClickAt()
{
    if(g_cpLineArmed) return;   // armed clicks belong to the line's own contract
    if(g_thStartPointType != TH_START_POINT_CUSTOM_PRICE) return;
    if(!g_customPriceLineCreated || ObjectFind(0, g_customPriceHorizontalLineName) < 0)
    {
        g_cpClickArmed = false;
        return;
    }
    uint now = GetTickCount();
    if(g_cpClickHandledMs != 0 && now - g_cpClickHandledMs < 60) return;   // the same click's twin event
    g_cpClickHandledMs = now;
    bool dbl = (g_cpClickLastMs != 0 && now - g_cpClickLastMs < DOUBLE_CLICK_THRESHOLD_MS);
    g_cpClickLastMs = now;
    if(!dbl) return;
    CustomPriceLineOwnArm(true);
    g_cpHandleShown = true;
    CustomPriceMarkerSync();
    ThrottledChartRedraw();
}

// The button-up that carries no move (P-BK-03): a motionless press/release on
// the SET line's row is a click, and only a double of those re-arms.
void CustomPriceRearmFinalize()
{
    if(!UILeftButtonUp()) return;   // the press's own echo (P-UI-73): keep the row for the real release
    if(!g_cpClickArmed) return;
    g_cpClickArmed = false;
    CustomPriceRearmClickAt();
}

// The double-click window's own sweeper: a single click that stayed single
// commits the SET here. Skipped while ANY handset gesture is live — the click
// that opened a drag must not set the line under the user's hand.
void HandsetClickSweep()
{
    uint now = GetTickCount();
    // P-UI-98h: a COMMIT happens with the button FREE. Both click transports
    // can arrive on the PRESS, so a pending slot may be waiting while the user
    // is still holding - the probe keeps it pending instead of committing a
    // SET under a hand that has not let go yet (and may still drag).
    if(g_cpSetPendingMs != 0 && now - g_cpSetPendingMs >= DOUBLE_CLICK_THRESHOLD_MS
       && UILeftButtonUp())
    {
        g_cpSetPendingMs = 0;
        g_cpSetPending = "";
        if(g_cpLineArmed)
        {
            CustomPriceLineOwnArm(false);
            g_cpHandleShown = false;   // P-UI-98g: SET takes the green circle away
            CustomPriceMarkerSync();
        }
    }
    if(g_s1SetPendingMs != 0 && now - g_s1SetPendingMs >= DOUBLE_CLICK_THRESHOLD_MS
       && UILeftButtonUp())
    {
        g_s1SetPendingMs = 0;
        g_s1SetPending = "";
        if(g_s1LinesArmed && !g_s1DragLive)
        {
            g_s1LinesArmed = false;   // SET: the factor stays, the ladder keeps the step
            g_s1HandleShown = false;  // P-UI-98g: nothing points at a set line
            g_redrawTHLevelsNeeded = true;
            RedrawAllObjects(true);   // the face owner re-owns selectability + parks the dot
        }
    }
}

//==============================================================================
// P-UI-53 — THE DRAG OWNS THE VIEW UNTIL THE RELEASE.
//
// Reported: "while dragging, the chart behind scrolls/pans and the drag breaks -
// lock or prepare the chart during the drag". The line's movement is MT4's own
// native object drag; the chart underneath stays live, so a gesture that wanders
// past the line - and CHART_MOUSE_SCROLL is ENABLED BY DEFAULT - pans the view.
// The price scale then slides under the cursor and MT4 answers the pan by moving
// the dragged object against a rebased price: the line jumps, the drag dies, or
// it never engages at all. BaseKnot already lives with this and solved it
// (`BaseKnotLockChart` + P-BK-14 "the drag owns the view until release"), with RAW
// Chart* calls so the Lite build compiles without the UI module. This is the same
// lock, same shape, for the line, in the same domain layer.
//
// P-UI-90 (2026-09-15) superseded the fourth bullet's "remembers what the user
// had" and the sentence that closed this block: the capture moved to ONE owner,
// because four private copies of it (this one, BaseKnot's, the panels' and the
// watchdog's) read the props while somebody ELSE held the lock and recorded our
// own `false` as the user's - so the last release wrote `false` back and the
// chart stayed scroll-locked until re-attach, and after Remove too. The lock's
// SHAPE is unchanged: the grab takes it, every throttled step re-asserts it, the
// button-up hands it back, the watchdog heals a release that never arrived, and
// OnDeinit releases it for EVERY reason. Only the bookkeeping moved.
//
// Four owners keep it honest:
//   * the GRAB takes it (once per gesture; `ChartViewLockAcquire` remembers what
//     the user had, and only at the moment NO owner holds the lock);
//   * every throttled drag step RE-ASSERTS it - read-guarded, a write only on
//     drift, because third writers (a panel closing, a watchdog restore, a
//     template reset) can flip the props back while the button is still down;
//   * the BUTTON-UP releases it (`ChartViewLockRelease` restores the user's pair,
//     and only on the LAST release - never a blind true);
//   * a watchdog heals a release that never arrived (off-window release, lost
//     focus): the P-BK-03 trap - no mouse move, so no release event either.
// CHART_AUTOSCROLL is held down too while we own the view: a tick sliding the
// scale mid-drag moves the line with it (BaseKnot makes the same call).
// OnDeinit releases it for EVERY reason (`ChartViewLockForceRelease` is the net),
// so a stale lock can never outlive the instance.
//==============================================================================
static bool s_cpChartLocked = false;
// P-UI-90: this owner no longer SAVES the scroll / context-menu pair. Its own
// capture could be taken while the Base/Knot tool (or the panels) already held
// the lock, so it recorded OUR `false` as "what the user had" and wrote it back
// on release - one of the four writers behind the chart that stayed scroll-locked
// for the life of the terminal. `ChartViewLock*` (GlobalVariables) is the single
// owner of that capture/restore now; AUTOSCROLL stays here because nothing else
// ratchets it (both writers only restore what they saw).
static bool s_cpAutoWas     = true;
static uint s_cpLockActMs   = 0;       // last activity of the owning gesture

bool CustomPriceDragLocked() { return s_cpChartLocked; }

void CustomPriceDragLockOn()
{
    if(!s_cpChartLocked)
    {
        s_cpAutoWas   = (ChartGetInteger(0, CHART_AUTOSCROLL) != 0);
        s_cpChartLocked = true;
        ChartViewLockAcquire();   // P-UI-90: scroll + context menu have ONE owner
    }
    else ChartViewLockAssert();
    if(s_cpAutoWas && (ChartGetInteger(0, CHART_AUTOSCROLL) != 0))
        ChartSetInteger(0, CHART_AUTOSCROLL, false);
    // P-UI-106 (2026-09-23): CHART_CONTEXT_MENU is a stub on this build
    // (CTXMENU-OFF) - writing it costs a repaint for zero effect, so it is
    // not written any more.
    s_cpLockActMs = GetTickCount();
}

void CustomPriceDragReassertLock()
{
    if(!s_cpChartLocked) return;
    s_cpLockActMs = GetTickCount();
    ChartViewLockAssert();   // P-UI-90: read-guarded, one owner for scroll + ctx
    if(s_cpAutoWas && ChartGetInteger(0, CHART_AUTOSCROLL) != 0)
    { ChartSetInteger(0, CHART_AUTOSCROLL, false); }
    // P-UI-106: stub write retired (see CustomPriceDragLockOn above).
}

void CustomPriceDragLockOff()
{
    if(!s_cpChartLocked) return;
    ChartViewLockRelease();   // P-UI-90: hands the view back only when NO owner is left
    if(s_cpAutoWas) ChartSetInteger(0, CHART_AUTOSCROLL, true);
    s_cpChartLocked = false;
}

// The P-BK-03 net (shape: BaseKnotSyncBadges' own stale-drag heal): a press whose
// release emits NO mouse move cannot be ended by the gesture path, so the lock (and
// the gesture flags) are healed here once the button is provably up and nothing has
// moved for 1.5 s. Cost in steady state: the caller reads one bool; the KEYSTATE
// probe runs only while a lock is actually held.
void CustomPriceDragHealStale()
{
    if(!s_cpChartLocked) return;
    if(GetTickCount() - s_cpLockActMs <= 1500) return;                     // a live drag keeps producing events
    if(!UILeftButtonUp()) return;             // still holding the button (one owner, P-UI-73)
    CustomPriceDragLockOff();
    g_customPriceLineDragging = false;
    g_customPriceDragOwn = false;
    // P-UI-98: a step-1 gesture whose release never arrived heals the same way —
    // the flags drop and the handle's selection goes (a stuck g_s1DragLive would
    // pin the handle's price forever, since the render skips its writes while the
    // flag is up). No forced frame here: the owed-frame machinery and the next
    // natural frame re-assert the picture.
    if(g_s1DragLive)
    {
        g_s1DragLive = false;
        // P-UI-98e: the carry's own state heals with the gesture's flags - a
        // live g_s1OwnActive on a healed drag would keep the held-move pass
        // reading a cursor that is no longer dragging anything. P-UI-98f: it is
        // the SAME owner the settle uses - this path used to leave the echo
        // stamp's base and the press baseline behind, and the next gesture read
        // them as its own.
        Step1GestureStateClear();
        // P-UI-98e: the borrow heals with the gesture - the face owner's next
        // frame writes the truthful flag (armed means grabbable).
        g_s1OwnBorrowed = false;
        // and a press whose release was lost is a GESTURE, never a click: the
        // candidate dies here so no later CHARTEVENT_CLICK can SET the line the
        // user had been dragging.
        g_s1ClickRow = "";
        string s1HealName = g_s1DragName;
        g_s1DragName = "";
        if(s1HealName != "" && (bool)ObjectGetInteger(0, s1HealName, OBJPROP_SELECTED))
            ObjectSetInteger(0, s1HealName, OBJPROP_SELECTED, false);
    }
}

//==============================================================================
// P-UI-98j — THE STEP-1 PAIR HEALS ITSELF (2026-09-22).
//
// Reported: «بعضی وقتا این خطش ناپدید میشه step و دیگه نمیشه جابجاش کرد ...
// تایم بالا میریم دوباره درست میشه». The shape is exact: a stashed handle
// whose OBJECT is gone. The stash - and the red circle riding it - survives,
// the claim refuses (ObjectFind < 0, P-UI-98e), and nothing re-creates the
// line: steady-state frames are sealed by the geometry signature (the levels
// block only runs on `g_redrawTHLevelsNeeded || g_buildStage != 0`), and the
// external-delete self-heal in OnChartEventHandler only fires when the delete
// event is NOT suppressed - a delete landing inside our own 250 ms
// post-delete suppression window is ignored, the cache keeps vouching for a
// name the chart no longer carries, and the picture stays wrong until
// something unrelated rebuilds (a TF switch does it for real: OnInit bumps
// the epoch, resets the absent table and rebuilds the whole family).
//
// The net is this function, called from the tick path beside
// CustomPriceDragHealStale (throttled to S1_HEAL_MS; reads-only while
// healthy): in custom-price mode, armed, same-TF stash, no live gesture and
// no rebuild in flight, a stashed handle whose price sits inside the RAW
// visible window but whose object is gone arms the delete branch's own two
// lines (redraw flag + generation bump) - an in-place re-assert, never a
// wipe. The raw window (not the ±25% cull window) is the proof the line must
// be painted: anything on screen is inside every cull window by construction
// (P-PERF-04's margin covers the hysteresis band), so a correctly culled
// off-screen line can never trip it, and a line the build legitimately
// dropped has no stash to trip it with.
//==============================================================================
#define S1_HEAL_MS 2000
void Step1HandleHealMissing()
{
    if(g_thStartPointType != TH_START_POINT_CUSTOM_PRICE) return;
    if(!g_s1LinesArmed || g_s1DragLive) return;
    if(IsIndicatorHidden() || !g_linesVisible) return;
    if(g_s1MarkPeriod != Period()) return;
    if(g_buildStage != 0 || g_forceClearOnNextDraw) return;
    static uint s_s1HealLastMs = 0;
    uint now = GetTickCount();
    if(s_s1HealLastMs != 0 && now - s_s1HealLastMs < S1_HEAL_MS) return;
    s_s1HealLastMs = now;
    double wMax = WindowPriceMax();
    double wMin = WindowPriceMin();
    if(!(wMax > wMin)) return;   // no window known: do not guess
    bool missing = false;
    if(g_s1MarkAboveName != "" && g_s1MarkAbovePrice >= wMin && g_s1MarkAbovePrice <= wMax &&
       ObjectFind(0, g_s1MarkAboveName) < 0)
        missing = true;
    if(!missing && g_s1MarkBelowName != "" && g_s1MarkBelowPrice >= wMin && g_s1MarkBelowPrice <= wMax &&
       ObjectFind(0, g_s1MarkBelowName) < 0)
        missing = true;
    if(!missing) return;
    // A stashed handle the chart should paint but does not carry: the stored
    // geometry no longer describes the chart, so the next frame rebuilds for
    // real and the render re-creates it in place. No wipe - a wipe answers a
    // topology change, never a hole.
    g_redrawTHLevelsNeeded = true;
    MarkDrawGeneration();
}

// P-UI-49: the ONE owner of the line's drag TOOLTIP TEXT. It used to be written
// in the drag handler itself, i.e. on EVERY step of a native drag - and MT4
// CANCELS an in-progress native drag when the dragged object is rewritten
// mid-gesture (P-BK-15's rule, learned on the BaseKnot box: the pump "snapped
// the box back to the drag start"; the level-family follow obeys it too -
// "never a full Sync per step, its style/tooltip rewrites lagged children behind
// the native BOX"). While the line was created pre-SELECTED the movement came
// from the SELECTION (MT4 moves every selected object on each mouse-move), so
// that write was invisible; the moment P-UI-45/48 moved the movement onto the
// PER-OBJECT native drag it cancelled the very gesture it was decorating and the
// line stopped following the cursor - the reported "the custom price line cannot
// be dragged". So the line is written ONCE per gesture, from the release, and
// NOTHING touches it while the button is down. Cost: fewer writes than before
// (one per gesture instead of one per drag step), no per-frame work.
void UpdateCustomPriceTooltip()
{
    if(!g_customPriceLineCreated) return;
    // P-UI-98g: the wording follows the state the user is actually in — an armed
    // line whose handle is not up yet asks for the click that brings it up.
    string text = g_waitingForCustomPriceClick
                  ? "Current price: " + DoubleToString(g_customTHStartPrice, Digits) + " - Double-click to confirm"
                  : (g_cpLineArmed
                     ? (g_cpHandleShown
                        ? "Custom TH start price: " + DoubleToString(g_customTHStartPrice, Digits) + " - Drag the green handle, click to commit"
                        : "Custom TH start price: " + DoubleToString(g_customTHStartPrice, Digits) + " - Click it to bring up the green handle")
                     : "Custom TH start price: " + DoubleToString(g_customTHStartPrice, Digits) + " - Set. Double-click to re-arm");
    ObjectSetString(0, g_customPriceHorizontalLineName, OBJPROP_TOOLTIP, text);
}

// P-UI-49c: the gesture's own bookkeeping. `s_ownGrabPrice` is the line's price
// when the grab started and `s_ownLastWrite` the last price WE wrote; they are
// what tells a working native drag (the terminal's price moves on its own - we
// then touch nothing, P-BK-15) from a frozen one (it does not - we carry it).
static double s_ownGrabPrice = 0.0;
static double s_ownLastWrite = 0.0;

// P-UI-100b (2026-09-22): THE DRAW THAT LOOKED LIKE A GRAB.
//
// A press that lands ON the custom price line is claimed by us and P-UI-49d
// hands the movement to the terminal - correct for a GRAB, wrong for a DRAW: with
// MT4's fib tool armed, the same press starts a fib and the line we just selected
// is carried to the fib's other end («وقتی فیو یا باکس از همون محل میکشم کاستوم
// پرایس جابجا میشه»). At the press the two are indistinguishable, so the answer
// is the OUTCOME, and the outcome is an OBJECT: a gesture of ours never CREATES
// one, and the terminal's own drawing tools always do. Two witnesses, both fed by
// the one detector in OnChartEventHandler:
//   * `s_cpForeignDrawUntil` — the WINDOW a foreign create opens. The claim asks
//     it at the press edge: a draw that was already under way (MT4 creates a
//     drawn object on the press) is refused before it can move anything at all.
//   * `s_drawNotGrab`     — THIS GESTURE is a draw, not a grab. Set only while a
//     claim of ours is live; it stands the carry down and the release puts the
//     line back. ONE flag for BOTH hand-set lines: a claim of the step-1 pair and
//     a claim of the custom price line are mutually exclusive (one cursor, one
//     gesture — the step claim runs first and the other yields), so there is never
//     a second gesture for it to describe, and each settle clears it.
static uint s_cpForeignDrawUntil = 0;   // the deadline a foreign create opens
static bool s_drawNotGrab      = false;  // the live gesture turned out to be a draw
#define CP_DRAW_WITNESS_MS 600       // how long a foreign create disqualifies a claim

// P-UI-55: THE PRESS LATCH FOR OUR OWN CARRY, IN PIXELS.
//
// Reported with two screenshots: "I CLICK the line - I did not move it - and every
// level lands somewhere else: 1.15697 becomes 1.15705." Eight points on a 5-digit
// chart is ~1.6 px, which is the hit tolerance itself. The carry used to be
// ABSOLUTE TO THE CURSOR and it engaged on ANY button-down mouse move after the
// press edge, so the one-pixel jitter of a CLICK was enough to hand the line the
// cursor's price: the press had landed ~2 px off the line (exactly what
// CustomPriceGrabAt tolerates as "on the line") and that offset was copied onto the
// PRICE. The user did not move anything on purpose, yet the line's price changed -
// and every level, which is derived from that price, moved with it. A price that
// changes without the user moving something is the "the levels are not reliable"
// bug, so the carry is fenced by the two rules the BaseKnot box already uses:
//   * SLOP: only a gesture that has actually TRAVELLED may drive the line, and an
//     HLINE can only be moved along Y - so a click's jitter can never pass, and a
//     click is honest: the price does not change at all.
//   * DELTA from the press latch, never absolute-to-cursor: the press offset is
//     preserved (the line follows the mouse exactly like MT4's own drag does) and
//     the movement can never snap the line onto the cursor.
static int    s_ownGrabX = 0;             // cursor pixel at the grab
static int    s_ownGrabY = 0;
static double s_ownGrabCursorPrice = 0.0; // price under that pixel at the grab
#define CP_DRAG_SLOP 3                    // px of vertical travel before it is a DRAG (P-UI-96: was 6; 6px ate precise nudges on coarse charts, clicks still filter via !pressEdge + jitter < 3px)
// P-UI-99-OFF (2026-09-21, user order): CP_HOLD_MS / CP_HOLD_MOVE (the 500 ms
// hold-to-arm beat, P-UI-97) are retired — the line's claim is immediate, the
// select/deselect pair carries the comfort instead. Restore is a git revert of
// the claim block, not a rewrite.

// P-UI-49c/P-UI-50: did the press at (x,y) land on the line? ONE conversion, the
// one already proven to work in this codebase (ChartXYToTimePrice - the panels and
// the carry below use it), never one per move: the answer only decides WHO owns the
// gesture. The first version converted the LINE to a pixel with
// ChartTimePriceToXY(0, 0, 0, ...) and MT4 REFUSES that call with time = 0, so the hit
// test could never fire at all (zero "grab hit-test" lines in a whole session of
// drags) and the drag lived or died by the terminal's own pick-up. Now the cursor's
// price is compared against the line's, with the tolerance expressed in PIXELS
// through the very price-per-pixel the chart is drawn at: the line as drawn plus a
// few pixels, i.e. what the terminal itself uses - a normal press grabs the line, a
// press clearly away still pans the chart.
bool CustomPriceGrabAt(const int x, const int y)
{
    if(!g_customPriceLineCreated) return false;
    double linePrice = ObjectGetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, 0);
    if(linePrice <= 0) return false;
    int subW = 0; datetime cursorT = 0; double priceAtCursor = 0.0;
    if(!ChartXYToTimePrice(0, x, y, subW, cursorT, priceAtCursor)) return false;
    int heightPx = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
    double span = WindowPriceMax() - WindowPriceMin();
    if(heightPx <= 0 || span <= 0) return false;
    // P-UI-98q: the tolerance covers the visible affordance - the 19 px green
    // circle, not the unpainted line under it.
    int tolPx = (int)inpCustomPriceLevelWidth + 4 + (CP_HANDLE_HALF - HANDSET_HANDLE_HALF);
    if(tolPx < 5) tolPx = 5;
    double tolPrice = span * ((double)tolPx / (double)heightPx);
    return (MathAbs(linePrice - priceAtCursor) <= tolPrice);
}

//| Helper function to hide all TH objects (DRY)                     |
//|                                                                  |
//| Centralized hide logic to avoid code duplication                 |
//| Used by: OnInit, RedrawAllObjects, F key handler                 |
//| COVERS: TH levels, labels, zones, mode labels, custom price      |
//+------------------------------------------------------------------+
// P-PERF-02: hide is a STATE, not a per-frame action. RedrawAllObjects calls
// HideAllTHObjects() from its hidden early-exit on every heavy frame, so the
// old code walked every chart object and wrote a mask on every hit for as long
// as the indicator stayed hidden (the whole point of the F key). Nothing can
// re-show those objects while we are hidden, so the pass runs once per hide
// transition; ResetHideAllState() re-arms it from every path that can show
// objects again (F key show branch, OnInit, OnDeinit).
static bool g_hideAllApplied = false;

void ResetHideAllState() { g_hideAllApplied = false; }

void HideAllTHObjectsPass()
{
    // P-PERF-31: the walk lives in the visibility owner and follows the
    // object cache (only our objects, zero ObjectName calls over foreign
    // chart objects, zero type probes — hiding needs no classification).
    // A fresh instance with a cold cache falls back to one legacy chart
    // scan for the previous instance's leftovers; steady state never scans.
    VisibilityHideAllCached();
    // PERF: Batch special label hide - ObjectSetInteger is no-op if object doesn't exist
    long noPeriodsVal = OBJ_NO_PERIODS;
    ObjectSetInteger(0, g_stepModeLabelName, OBJPROP_TIMEFRAMES, noPeriodsVal);
    ObjectSetInteger(0, g_factorLabelName, OBJPROP_TIMEFRAMES, noPeriodsVal);
    // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
#ifndef BUILD_LITE
    ObjectSetInteger(0, g_th3FreqLabelName, OBJPROP_TIMEFRAMES, noPeriodsVal);
#endif
    ObjectSetInteger(0, g_lockStatusLabelName, OBJPROP_TIMEFRAMES, noPeriodsVal);
    if(g_customPriceLineCreated)
        ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_TIMEFRAMES, noPeriodsVal);
    // P-UI-98d: the handset handles hide with everything else (F key). They are
    // screen-pixel BITMAP_LABELs — no TF mask applies — so they PARK off-window;
    // the next sync (ride channel / face owner) re-places them on the show path.
    HandsetHandlePark(g_cpMarkerName, CP_HANDLE_RES);
    HandsetHandlePark(S1MarkName(1), S1_HANDLE_RES);
    HandsetHandlePark(S1MarkName(-1), S1_HANDLE_RES);
    // NOTE: ABCD pattern objects are NOT hidden by F key
}

// Returns true when this call performed the (once per transition) pass.
bool HideAllTHObjects()
{
    if(g_hideAllApplied) return false;
    g_hideAllApplied = true;
    HideAllTHObjectsPass();
    // Written outside the visibility guard → invalidate every stored mask.
    BumpTfEpoch();
    return true;
}
#endif // EVENT_HANDLERS_INIT_MQH
