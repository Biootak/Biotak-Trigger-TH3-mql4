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

For example, H1 uses `ATR(H1)` and M15 uses `ATR(M15)`. This keeps the model volatility-normalized instead of copying fixed H1 pip distances. Only the active/locked timeframe is shown in a compact bottom-right block, away from the TH labels and other bottom-left information: ATR pips on top, `Hunter SL: <hunt> Eng.SL: <eng>` (red) in the middle, `#TP1+<t1> #TP2+<t2> #TP3+<t3>` (blue) at the bottom — all integer pips, rows centered in the block. A top-right TRex stamp (active-TF TH value + caption + `TR`/`ex` brand) rides the same block visibility. `inpShowATRTradeSLLabels` and `inpShowATRTradeTPLabels` independently toggle the stop and target rows; `inpShowATRTradeLabels` toggles the whole block. The coefficients are empirical inputs from the supplied H1 snippet; the repository does not contain the professor’s original statistical derivation, so validate them with backtesting before live use.

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

