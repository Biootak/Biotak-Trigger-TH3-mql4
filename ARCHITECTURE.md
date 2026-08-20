# Biotak Trigger TH3 — Architecture

> خلاصه فارسی: این سند معماری لایه‌ای پروژه را توصیف می‌کند؛ قواعدی که هر ماژول باید رعایت کند
> (ورودی نازک، include guard، include فقط در ابتدای فایل، جهت وابستگی به سمت پایین، تک‌منبع حقیقت
> برای فرمول‌ها) و نقشه راه رفع بدهی‌های معماری (فایل‌های غول‌پیکر، ماژول‌های مرده، جدول‌های ضریب تکراری).

## 1. Overview

The indicator is a **layered MQL4 project**: two thin entry points
(`Biotak Trigger TH3.mq4` / `Biotak Trigger TH3 Lite.mq4`) that only forward the
standard event handlers (`OnInit`, `OnDeinit`, `OnCalculate`, `OnChartEvent`, `OnTimer`)
to `EventHandlers.mqh`. All logic lives in 55 `.mqh` modules under `Biotak/` (~30k lines).

Two build variants are selected in `Biotak/BuildConfig.mqh`:

| Variant | Selection | Extra modules |
|---------|-----------|---------------|
| **Full** | default | `Profiler`, `WaveAnalysis`, `FrequencyOptimizer`, `TH3Tool` |
| **Lite** | `#define BUILD_LITE` | (none — excludes the above) |

## 2. Layers (dependency order)

Includes are ordered bottom-up in the `.mq4` files. A module may only depend on
modules **below** it; never on modules above.

```
┌────────────────────────────────────────────────────────────────┐
│ Entry           Biotak Trigger TH3.mq4 / TH3 Lite.mq4 (thin)  │
├────────────────────────────────────────────────────────────────┤
│ Events          EventHandlers.mqh                             │
├────────────────────────────────────────────────────────────────┤
│ Presentation    LabelFunctions, AlertFunctions,               │
│                 HistoricalDataFunctions                       │
├────────────────────────────────────────────────────────────────┤
│ Drawing         ObjectFunctions, ExtendedDrawingFunctions,    │
│                 FactorMode, LevelPipeline, ModeDefinitions    │
├────────────────────────────────────────────────────────────────┤
│ Zones           ZoneConstants/Factory/Validator/Calculator/   │
│                 Renderer, ZoneTrackingHelpers,                │
│                 UnifiedZoneSystem, DrawingPipeline            │
├────────────────────────────────────────────────────────────────┤
│ Domain (Full)   WaveAnalysis, FrequencyOptimizer, TH3Tool     │
├────────────────────────────────────────────────────────────────┤
│ Calculation     TimeframeFunctions, FractalTimeframes,        │
│                 StandardTimeframes, THCalculations,           │
│                 ATRCalculations, AdaptiveScaling,             │
│                 BasePriceManager (+History/MarketHours/       │
│                 DynamicTradingDayDetector)                    │
├────────────────────────────────────────────────────────────────┤
│ Foundation      UtilityFunctions, CalculationCache,           │
│                 GlobalVariables, ObjectCache,                 │
│                 PropertyChangeDetector, VisibilityManager,    │
│                 ObjectCountManager, PerformanceOptimizations, │
│                 FloatingPointHelper, InputValidator(s),       │
│                 ConstantsAndEnums, ProjectConstants,          │
│                 PropertiesAndInputs, Logger, MathConstants,   │
│                 BuildConfig                                   │
└────────────────────────────────────────────────────────────────┘
```

Key design decisions:

- **Single source of truth for formulas.** `FactorMode.mqh` centralizes the
  Factor↔Step relationship (`Step = Range / (Factor × 2)`), the auto-basis step
  table (all 8 bases) and the DIRECT/CLASSIC input semantics. Drawing, labels,
  status and hotkey paths must consume these functions instead of re-implementing
  the formulas inline.
- **Centralized global state.** All indicator-wide `static` globals live in
  `GlobalVariables.mqh` (single module, include-guarded).
- **Safety-first math.** `FloatingPointHelper.mqh` (EPSILON constants, safe
  comparisons), `SafeDivide`/`SafeSqrt`, `MAX_SAFE_PRICE` bounds checks, and
  `ASSERT` (enabled via `ENABLE_ASSERTIONS`).

## 3. Rules (best practices — enforced from now on)

1. **Thin entry point.** The `.mq4` files contain only the event-handler stubs.
2. **Include guards.** Every `.mqh` starts with `#ifndef <NAME>_MQH` /
   `#define <NAME>_MQH` and ends with `#endif`.
3. **Includes at the top only.** No mid-file `#include` (the former
   `DrawingPipeline.mqh` include inside `ExtendedDrawingFunctions.mqh` was moved
   to the header block).
4. **Dependency direction.** Lower layers never include upper layers; the main
   `.mq4` is the only place that composes the full graph.
5. **One concern per module.** Avoid god files; split by responsibility.
6. **No duplicate formulas.** Any repeated calculation must be extracted into the
   owning module and consumed everywhere.
7. **Global state only in `GlobalVariables.mqh`.** File-scope `static` state
   elsewhere should be migrated there or scoped inside functions.
8. **Full/Lite via `BUILD_LITE`**, not by copying the indicator.

## 4. Known debt / roadmap

| Item | Where | Suggested action |
|------|-------|------------------|
| God files | `ExtendedDrawingFunctions.mqh` (4,685), `TH3Tool.mqh` (3,487), `EventHandlers.mqh` (2,189), `BasePriceManager.mqh` (1,955), `ATRCalculations.mqh` (1,238) | Split by concern (e.g. factor drawing, TH3 tool panels, handler subgroups) |
| Dead modules (never included) | `EnhancedLogging.mqh`, `MemoryManager.mqh`, `LogLevels.mqh`, `ValidationUtilities.mqh` | Verify and delete, or wire them in |
| Duplicated basis-multiplier tables | `GetStepSizeForFactorBasis` (`ExtendedDrawingFunctions.mqh`) vs `GetFactorModeAutoStepSize` (`FactorMode.mqh`) | Unify behind one table, preserving adapted-vs-raw semantics |
| Corrupted docs | `DEVELOPMENT_GUIDE_FA.md` (was unreadable; rewritten) | Keep docs in sync with `ARCHITECTURE.md` |
| Scattered `static` state | several modules | Migrate to `GlobalVariables.mqh` |

## 5. Verification

```
powershell -File compile-th3.ps1 -Project workspace   # Full build
powershell -File compile-th3.ps1 -SourceFile "Biotak Trigger TH3 Lite.mq4"
```
Expected: `0 errors, 0 warnings` for both.
