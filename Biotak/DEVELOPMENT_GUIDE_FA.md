# راهنمای توسعه — بیوتک تریگر TH3

این سند راهنمای توسعه و ساختار معماری اندیکاتور «بیوتک تریگر TH3» است.
برای نمای کامل معماری و قواعد لایه‌بندی، `ARCHITECTURE.md` را ببینید.

## ۱. معماری لایه‌ای (Level Pipeline)

پردازش سطوح در یک خط لوله (Pipeline) در `LevelPipeline.mqh` انجام می‌شود:

1. **CalculateLevels** — محاسبه سطوح (Step) بر اساس حالت گام انتخابی.
2. **ClassifyLevels** — دسته‌بندی سطوح (مانند SS و LS).
3. **BuildZones** — ساخت زون‌ها (Zones).
4. **DeriveTriggers** — استخراج تریگرها.
5. **Render** — رسم روی نمودار.

### جریان تعریف حالت‌ها

1. حالت‌های محاسبه گام در `ENUM_STEP_CALCULATION_MODE` (در `ConstantsAndEnums.mqh`) تعریف شده‌اند.
2. تنظیمات هر حالت در `ModeDefinitions.mqh` (تابع `BuildNewModeConfig`) ساخته می‌شود.
3. حالت فعال با `GetModeDefinition` در `ModeDefinitions.mqh` انتخاب می‌شود.
4. پسوندهای هر حالت با `GetAllModeSuffixes` در `LevelPipeline.mqh` تولید می‌شود.

## ۲. نسخه‌های Full و Lite

پروژه با پرچم `BUILD_LITE` دو نسخه دارد:

### نسخه Full (کامل)
- شامل ماژول‌های: **Profiler**، **Frequency Optimizer** و **TH3 Tool (ABCD)**.
- تمام امکانات و تحلیل‌ها فعال است.

### نسخه Lite (سبک)
- با `#define BUILD_LITE` در `BuildConfig.mqh` فعال می‌شود.
- ماژول‌های سنگین غیرضروری از build حذف می‌شوند.
- ورودی‌ها (Inputs) مرتبط نیز حذف می‌شوند.

## ۳. امنیت و اعتبارسنجی (Validation)

- **تقسیم امن**: استفاده از `SafeDivide` در همه محاسبات حساس.
- **مدیریت اشیاء**: کنترل تعداد اشیاء نموداری با `ObjectCountManager` و `MAX_SAFE_OBJECTS`.
- **محدودیت قیمت**: بررسی با `MAX_SAFE_PRICE` برای جلوگیری از سرریز محاسبات.
- **Include Guards**: همه فایل‌های `.mqh` دارای `#ifndef` هستند تا از include دوباره جلوگیری شود.

## ۴. ساختار فایل‌ها

- `Biotak Trigger TH3.mq4`: نقطه ورود نسخه کامل (فقط Event Handlerها).
- `Biotak Trigger TH3 Lite.mq4`: نقطه ورود نسخه سبک.
- `ModeDefinitions.mqh`: تعریف حالت‌های محاسبه گام.
- `LevelPipeline.mqh`: خط لوله ساخت و رسم سطوح.
- `FactorMode.mqh`: تک‌منبع حقیقت برای منطق حالت Factor (رابطه Factor↔Step و هر ۸ مبنای خودکار).
- `BuildConfig.mqh`: تنظیمات build (Debug/Production/Lite).
- `GlobalVariables.mqh`: تمام متغیرهای سراسری پروژه در یک ماژول.

---
*ساخته‌شده توسط تیم بیوتک*
