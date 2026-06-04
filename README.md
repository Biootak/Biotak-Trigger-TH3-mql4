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

---

## 🔧 Build Configuration (Debug/Production)

### Quick Start

| Mode | Action |
|------|--------|
| **Production** 🚀 | Default - no changes needed |
| **Debug** 🔧 | Uncomment `#define DEBUG_BUILD` in `Biotak/BuildConfig.mqh` |

### How to Switch Modes

Edit `Biotak/BuildConfig.mqh`:

```mql4
// ══════════════════════════════════════════════════════════════════
// 🔧 UNCOMMENT FOR DEBUG BUILD | برای حالت توسعه آنکامنت کنید
// ══════════════════════════════════════════════════════════════════
//#define DEBUG_BUILD    // ← Uncomment this line for Debug mode
```

### What's Different?

| Feature | Production 🚀 | Debug 🔧 |
|---------|--------------|----------|
| Debug logs | ❌ Removed at compile | ✅ Active |
| Performance tracking | ❌ Removed | ✅ Active |
| Assertions | ❌ Removed | ✅ Active |
| Binary size | Smaller | Larger |
| Speed | Faster | Normal |

### How to Know Which Mode?

Check the Experts tab when indicator loads:

```
// Production:
🚀 Biotak Trigger TH3 - Version 3.05
Build Mode: PRODUCTION
✅ PRODUCTION BUILD - Optimized for performance

// Debug:
🔧 Biotak Trigger TH3 - Version 3.05
Build Mode: DEBUG
⚠️ DEBUG BUILD - Not for production use!
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
├── Biotak Trigger TH3.mq4      # Main indicator file
├── Biotak/
│   ├── BuildConfig.mqh         # 🆕 Build configuration (Debug/Production)
│   ├── PropertiesAndInputs.mqh # Input parameters
│   ├── ConstantsAndEnums.mqh   # Constants and enums
│   ├── GlobalVariables.mqh     # Global state
│   ├── THCalculations.mqh      # TH calculation logic
│   ├── BasePriceManager.mqh    # 30-min base price updates
│   ├── TimeframeFunctions.mqh  # Timeframe utilities
│   ├── ObjectFunctions.mqh     # Chart object creation
│   ├── LabelFunctions.mqh      # Label management
│   ├── EventHandlers.mqh       # Event processing
│   ├── AlertFunctions.mqh      # Alert system
│   ├── PerformanceMonitor.mqh  # Performance tracking
│   └── Tests/                  # Property-based tests
```

---

## Hotkeys

| Key | Action |
|-----|--------|
| F | Hide/Show indicator |
| G | Lock/Unlock timeframe |
| C | Set custom price |
| T | Toggle trigger levels |
| E | Cycle step modes |
| R | Reset to defaults |

---

## License

© Formula by Professor Saeed Khakestar, Indicator by Biotak.

