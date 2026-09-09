# محاسبات TH و ATR — سند فنی فارسی

> قانون این سند: فقط چیزی اینجا هست که هم در کد هست هم با داده واقعی دیده شده.
> اعداد در حال اعتبارسنجی (مثل ضریب مقیاس تریدپلن) عمداً اینجا نیستند —
> آن‌ها در کد (`Biotak/TradePlanFormulas.mqh`) و حافظه ایجنت (`AGENTS.md`) دنبال می‌شوند.
> جزئیات تریدپلن در `TRADEPLAN_FA.md` است؛ اینجا موتورهای TH و ATR توضیح داده می‌شوند.

---

## ۱. قیمت پایه (Base Price)

منبع: `Biotak/BasePriceManager.mqh` ،`Biotak/UtilityFunctions.mqh` (`GetMidpointPrice`)

پنج حالت (`ENUM_TH_START_POINT_TYPE` در `Biotak/ConstantsAndEnums.mqh`):

| حالت | مبنا |
|---|---|
| Midpoint | میانگین سقف/کف تاریخی `(H+L)/2` |
| Historical High / Low | سقف / کف تاریخی |
| Custom Price | قیمت دستی کاربر (خط قابل درگ) |
| Previous Close | کلوز روز قبل |

به‌روزرسانی در بلوک‌های ۳۰ دقیقه‌ای (`BLOCK_MINUTES 30`) و فقط اگر تغییر نسبت به
مبنای قبلی از آستانه نویز بیشتر باشد (`0.066%` — `BasePriceManager.mqh:16-19`).

---

## ۲. فرمول TH

منبع: `Biotak/THCalculations.mqh` (`CalculateTHPoints:87`)

```
TH (واحد قیمت) = (قیمت پایه × درصد) / 100
TH (پوینت) = TH قیمتی / Point
```

نگاشت چارت به تایم‌فریم فراکتال (`GetBaseFractalTimeframeForCurrent` در
`Biotak/FractalTimeframes.mqh:5-16`) و درصدها (`MODIFIED_FRACTAL_PERCENTAGES`
در `Biotak/ConstantsAndEnums.mqh:56-66`):

| چارت | فراکتال | درصد |
|---|---|---|
| M1 | M1 | ۲.۰۸٪ |
| M5 | M4 | ۴.۱۷٪ |
| M15 / M30 | M16 | ۸.۳۳٪ |
| H1 | H1+M4 | ۱۶.۶۶٪ |
| H4 | H4+M16 | ۳۳.۳۳٪ |
| D1 | H17+M4 | ۶۶.۶۶٪ |
| W1 | D11+H9+M4 | ۲۶۶.۶۴٪ |
| MN1 | D45+H12+M16 | ۵۳۳.۲۸٪ |

---

## ۳. گام‌ها و سطوح

منبع: `Biotak/MathConstants.mqh:7-8` ،`Biotak/THCalculations.mqh:19-30` ،`Biotak/ExtendedDrawingFunctions.mqh:1235`

```
SS (گام کوتاه) = Structure × 1.5
LS (گام بلند)  = Structure × 2.0
Control        = (SS + LS) / 2 = Structure × 1.75
```

سلسله‌مراتب لول: Structure (گام کامل) ← Pattern (نصف) ← Trigger (ربع).
سطوح استراکچر L1 تا L5:

```
فاصله سطح = BaseMultiplier × 2^(Level - 1)
```

هندسه زون (`ExtendedDrawingFunctions.mqh:2104-2109`): نیمه‌گام = نصف گام،
ارتفاع زون = ۲۵٪ نیمه‌گام (۱۲.۵٪ هر سمت نقطه میانی).

---

## ۴. ATR میانگین (کامپوزیت)

منبع: `Biotak/ATRCalculations.mqh`

میانگین وزنی `iATR` داخلی MT4 روی کندل بسته (شیفت ۱ — `CalculateATRBatchWilders:873-885`):

| پریود | ۵ | ۱۰ | ۲۱ | ۶۶ | ۱۳۲ | ۲۶۴ |
|---|---|---|---|---|---|---|
| وزن | ۱ | ۱ | ۲ | ۳ | ۵ | ۸ |

(مجموع وزن ۲۰ — `ATR_PERIOD_*` و `ATR_WEIGHT_*` در `ATRCalculations.mqh:38-55`.)

* برای هر تایم‌فریم از دیتای خودش حساب می‌شود (نه مقیاس‌بندی از تایم دیگر).
* کش چندتایم‌فریمه: هر TF حداکثر با طول «تایم تریگر» خودش تازه‌سازی می‌شود
  (تریگر = دو پله پایین‌تر در نردبان، کف M1 — `GetTriggerDurationSeconds:891`)
  و با شمارش جدید کندل باطل می‌شود (`CalculateWeightedATR:912-974`).
* نمادمستقل است: تبدیل به پیپ فقط با `GetCachedPipSize()` انجام می‌شود
  (طلا ۰.۱، جفت JPY ‏۰.۰۱، فارکس ۵رقمی ۰.۰۰۰۱ — `PerformanceOptimizations.mqh:146-198`).

---

## ۵. نوارهای ما

منبع: `Biotak/LabelFunctions.mqh`

* **نوار بالا (ATR):** برای هر تایم‌فریم `نام: مقدار پیپ` + پله‌ها
  `(۱.۵× ـ میانگین ـ ۲×)` + اهداف `floor(۳× ـ ۵× ـ ۱۵×)`
  (`CreateATRLabelSimple:83-102`).
* **نوار پایین (TH):** برای هر تایم‌فریم فراکتال/استاندارد `نام: مقدار` + همان
  قالب پله و هدف (`CreateTHLabel:645-656` ،`DisplayFractalTHs` ،`DisplayStandardTHs`).

---

## ۶. اتصال به بلاک تریدپلن (خلاصه — جزئیات در `TRADEPLAN_FA.md`)

* چیدمان: پایین-راست `#SL / #TP1 / #TP2 / #TP3` (آبی) + `Close in` (قرمز)،
  بالا-راست `Hunter SL / Eng.SL` (قرمز) + `Str Bond` (آبی) + مُهر TRex.
* هر تایم‌فریم SL خودش را دارد (M1: ‏۱.۵×، M5: ‏۱.۲×، M15: ‏۱.۳۵×، H1: ‏۱.۷۵×،
  H4: ‏۲× ATR همان TF)؛ D1 و بالاتر سقف ماکرو روزانه (`۱.۱۰۷ × ATR(D1)`)؛
  قفل تایم‌فریم (کلید G) فقط لول/زون را پین می‌کند و روی پلن اثر ندارد.
* نسبت‌های تأییدشده روی دو بلاک واقعی استاد (XAUUSD/H1 و EURUSD/D1):
  `TP1/SL=۷/۳` ،`TP2/SL=۵` ،`TP3/SL=۳۱/۳` ،`Hunter=۸/۳×Eng` (از ورودی گردنشده).
* `Eng = SL(تریگر)/۱.۲` که عملاً همان ATR نوارِ تریگر است (دیده‌شده: Eng‏۴۳ = نوار ‏M5‏۴۳).
* پایه‌های کُند (SL/TP/SB) هر کندل چارت یک‌بار فریز می‌شوند (مثل استاد) و
  Eng/Hunter زنده‌اند — جزئیات و وضعیت اعتبارسنجی مولت‌ها در `TRADEPLAN_FA.md`.

---

## ۷. بازنشسته‌ها (تکرار نشوند)

* ضرایب قدیمی `۰.۶۲/۱.۵۳/۳.۳۰/۶.۸۱/۰.۶۳/۰.۲۷` هیچ بلاک واقعی را نمی‌سازند —
  شرح کامل در `DOCUMENTATION_FA.md` بخش ۳.
* قانون «ضریب فرد Eng» (۱/۳/۵) با مشاهده ۴۳=۴۳ باطل شد؛ Eng ضریب ۱ دارد.
* لرزش ±۱ واحد بین دو لحظه، خطا نیست (ATR زنده با هر تیک می‌لرزد و رُند قورتش می‌دهد).
