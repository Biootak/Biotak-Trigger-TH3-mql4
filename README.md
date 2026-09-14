# Biotak Trigger TH3

**MetaTrader 4 Custom Indicator** implementing Professor Saeed Khakestar's TH (Time Harmonic) levels formula.

## Version
**3.05** - Build Configuration System Added

## Features
- TH Level Display with multiple step modes (TH, SS/LS, M, TP, Combo)
- Fractal Timeframes (M1, M4, M16, H1+M4, H4+M16, etc.)
- 30-minute Base Price Updates
- Custom Price Selection
- Performance Monitoring
- Alert System
- ATR trade-plan labels (S1, TP1/TP2/TP3, HuntSL, EngSL) normalized per active timeframe

---

##    Build Configuration (Debug/Production)

### Quick Start

| Mode | Action |
|------|--------|
| **Production**    | Default - no changes needed |
| **Debug**    | Uncomment `#define DEBUG_BUILD` in `Biotak/BuildConfig.mqh` |

### How to Switch Modes

Edit `Biotak/BuildConfig.mqh`:

```mql4
//                                                                   
//    UNCOMMENT FOR DEBUG BUILD |                             
//                                                                   
//#define DEBUG_BUILD    //   Uncomment this line for Debug mode
```

### What's Different?

| Feature | Production    | Debug    |
|---------|--------------|----------|
| Debug logs |   Removed at compile |   Active |
| Performance tracking |   Removed |   Active |
| Assertions |   Removed |   Active |
| Binary size | Smaller | Larger |
| Speed | Faster | Normal |

### How to Know Which Mode?

Check the Experts tab when indicator loads:

```
// Production:
   Biotak Trigger TH3 - Version 3.05
Build Mode: PRODUCTION
  PRODUCTION BUILD - Optimized for performance

// Debug:
   Biotak Trigger TH3 - Version 3.05
Build Mode: DEBUG
   DEBUG BUILD - Not for production use!
```

---

## Installation

1. Copy files to `MT4_Data_Folder/MQL4/Indicators/`
2. Include files go to `MT4_Data_Folder/MQL4/Include/Biotak/`
3. Compile `Biotak Trigger TH3.mq4` in MetaEditor (F7)
4. Attach to chart

---

## File Structure

```
    Biotak Trigger TH3.mq4      # Main indicator file
    Biotak/
        BuildConfig.mqh         #    Build configuration (Debug/Production)
        PropertiesAndInputs.mqh # Input parameters
        ConstantsAndEnums.mqh   # Constants and enums
        GlobalVariables.mqh     # Global state
        THCalculations.mqh      # TH calculation logic
        BasePriceManager.mqh    # 30-min base price updates
        TimeframeFunctions.mqh  # Timeframe utilities
        ObjectFunctions.mqh     # Chart object creation
        LabelFunctions.mqh      # Label management
        EventHandlers.mqh       # Event processing
        AlertFunctions.mqh      # Alert system
        PerformanceMonitor.mqh  # Performance tracking
        Tests/                  # Property-based tests
```

---

## ATR trade-plan labels

The H1 reference coefficients are rendered as ratios of the ATR of the active (or locked) timeframe:

```text
SL=0.62, TP1=1.53, TP2=3.30, TP3=6.81, HuntSL=0.63, EngSL=0.27
```

For example, H1 uses `ATR(H1)` and M15 uses `ATR(M15)`. This keeps the model volatility-normalized instead of copying fixed H1 pip distances. Only the active/locked timeframe is shown in a compact bottom-right block, away from the TH labels and other bottom-left information: ATR pips on top, `Hunter SL: <hunt> Eng.SL: <eng>` (red) in the middle, `#TP1+<t1> #TP2+<t2> #TP3+<t3>` (blue) at the bottom — all integer pips, rows centered in the block. The TRex brand (`TR`/`ex` with the pair's live spread in pips) and the red `Hunter SL: <hunt> Eng.SL: <eng>` row are the TOP HALF of that same bottom-right card: all three rows share one centre axis, the seam between any two of them is the same `inpATRTradeLabelRowGap` (default 10 px, the card's own input — not the shared label-grid gap), the `TR`/`ex` spacing is the measured width of `ex` (so the letters never collide at any DPI), and `inpTrexStampGapRows` (default 0 = tight) asks for extra blank rows when a looser card is wanted. Only the rows that are switched ON occupy a slot: turning one off slides the others down instead of leaving a hole, and the row's object is removed by the same writer that draws it. **The card is personalisable from the panel, not just from the Inputs dialog:** the `ATR LABELS` card carries `ROW GAP`, `TRADE SIZE`, `STAMP GAP`, `CARD MARGIN` and a five-cell colour strip (`TR` · `ex` · `HUNTER` · `TRADE` · `SPREAD`), each row writing the same setting as its group-13 input so the two can never disagree. The label card's `H/L PIP LABELS` row controls the pip-distance figures drawn beside the High/Low levels (it is read by four modules, so it is a real control — the caption used to be just `PIP LABELS`, which named nothing). Panels can be dragged by the header **or by any free spot of the card body**, the position is remembered per panel, and a drag that never receives its release is recovered automatically rather than locking the controls. The card's own knobs are `inpLabelsMarginBottom` (how far it sits off the chart floor, 8 px by default), `inpATRTradeLabelRowGap` (the seam between its rows, 10 px) and `inpTrexStampGapRows` (extra blank rows, 0 = tight) — the other margin inputs in that group also move the ATR/TH columns, these three move only the card. The Persian caption row this stamp used to carry was removed on 2026-09-14. `inpShowATRTradeSLLabels` and `inpShowATRTradeTPLabels` independently toggle the stop and target rows; `inpShowATRTradeLabels` toggles the whole block. The coefficients are empirical inputs from the supplied H1 snippet; the repository does not contain the professor’s original statistical derivation, so validate them with backtesting before live use.

---

## Hotkeys

| Key | Action |
|-----|--------|
| F | Hide/Show indicator |
| G | Lock/Unlock timeframe |
| C | Set custom price |
| Double-click Custom Price | Select SS-first or LS-first order |
| T | Toggle trigger levels |
| E | Cycle step modes |
| R | Reset to defaults |

---

## License

  Formula by Professor Saeed Khakestar, Indicator by Biotak.

