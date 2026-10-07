# فهرست کامل قابلیت‌های اندیکاتور MT4

منبع: `Biotak Trigger TH3.mq4` + `Biotak/TH3/` (۶٬۶۷۱ خط) + `Biotak/TH3Tool_*.mqh` + `Biotak/Util_A.mqh`.
هر ردیف با `file:line` ارجاع دارد. ستون **TV** می‌گوید در تریدینگ‌ویو چه می‌شود.

## A — ورودی‌ها (`Biotak/PropertiesAndInputs.mqh`)

| # | ورودی | پیش‌فرض | کار | TV |
|---|---|---|---|---|
| A1 | `inpTH3DrawingMode` | `TH3_MODE_ABCD` | حالت ترسیم | `input.string` |
| A2 | `inpTH3BaseStepPercent` | `28.125` | فرکانس پایه (`GetCurrentTH3Frequency`) | ✅ انجام شد |
| A3 | `inpTH3PivotBasePips` | `0.0` | مادر دستی؛ `0` = خاموش | ✅ `TH3_SET_BASE_PIPS` |
| A4 | `inpTH3Color` / `inpTH3PipTextColor` | سبز / سرمه‌ای | جوهر و رنگ متن | `input.color` |
| A5 | `inpTH3Style` / `inpTH3Width` | `SOLID` / `1` | سبک و ضخامت خط | `input.string`/`input.int` |
| A6 | `inpTH3LabelPosition` | `TH3_LABEL_END` | جای برچسب | ثابت |
| A7 | `inpTH3ZoneStyle` | `ZONE_STYLE_BOX_FILLED` | سبک زون | `input.string` |
| A8 | `inpTH3ZoneColor` / `Transparency` / `HeightPercent` / `BorderStyle` / `BorderWidth` | `clrNONE` / `50` / `33.0` / `DOT` / `1` | زون | `box.new` (فاز ۳) |
| A9 | `inpTH3ToolKey` | `"V"` | کلید میانبر ابزار | ❌ کلید میانبر نداریم |
| A10 | `inpTH3AutoPivots` | `true` | اسنپ کلیک روی پیوت شش‌شرطی | ⚠️ معنا ندارد بدون کلیک |

## B — ژست و تعامل (`Biotak/TH3Tool_C.mqh`)

| # | قابلیت | ارجاع | TV |
|---|---|---|---|
| B1 | کلیک = گذاشتن گوشه (`TH3BaseMarkClick`) | `TH3Tool_C.mqh:1198-1216` | ❌ → چهار `input.price/time` (انجام شد) |
| B2 | کشیدن گوشه (`OBJECT_DRAG`) + heartbeat | `TH3Tool_C.mqh:953-966` | ✅ خودِ `input.price` روی چارت کشیده می‌شود |
| B3 | قفل دید هنگام درگ (`ChartViewLockAcquire`) | `:962`, `:987-994` | ❌ لازم نیست (کشیدن بومی است) |
| B4 | راست‌کلیک = لغو سشن (`TH3SessionCancel`) | `:1153-1156` | ❌ |
| B5 | انتخاب و حذف با `Delete` | `TH3Tool_C.mqh:10-21` | ❌ |
| B6 | اشیای موقت هنگام ترسیم (`ABCD_Temp_*`) | `#define TH3_TEMP_*` | ❌ → ورودی ناتمام = چیزی کشیده نمی‌شود |
| B7 | دکمه‌ی BASE (`TH3_BASE_EDITOR`، باند + مارکر) | `#define TH3_BASE_EDITOR`, `TH3_BASE_MARK_1` | ❌ → `input.float` (انجام شد) |
| B8 | کلید میانبر ابزار | `EventHandlers_Router.mqh:392` | ❌ |
| B9 | ذخیره‌ی خودکار وضعیت در GlobalVariables | `Biotak/GlobalVariables.mqh` | ❌ (Pine حافظه بین نشست‌ها ندارد) |

## C — چیزی که رسم می‌شود

| # | شیء | نام/ارجاع | TV |
|---|---|---|---|
| C1 | خط AB و BC | `_Line_AB`, `_Line_BC` | ⬜ فاز ۳ |
| C2 | خط CD (پایانی) | `TH3_TEMP_LINE_CD` | ⬜ فاز ۳ |
| C3 | نقطه‌های A/B/C/D | `_Point_` | ⬜ فاز ۳ |
| C4 | برچسب هر پله | `_Label_` | ✅ انجام شد |
| C5 | تارگت‌های نردبان (Step1/3/5/7) | `_Target_` | ✅ انجام شد (۷ پله) |
| C6 | زون ABCD | `_Zone` + style/transparency/height | ⬜ فاز ۳ |
| C7 | پنل اطلاعات | `_Info` | ✅ انجام شد (جدول readout) |
| C8 | مارکرهای پیوت شش‌شرطی | `TH3_P6_` (فلش 217/218) | ✅ انجام شد (۵۰_draw) |
| C9 | زون مادر + خط ORG | `TH3_MP_` (`TH3Renderer_B.mqh:1221-1243`) | ⬜ فاز ۷ |
| C10 | براکت‌های TH (۱.۵۰/۱.۷۵/۲.۰۰ × رانگ) | `TH3Pivots_B.mqh:45-62` | ⬜ فاز ۶ |

## D — موتور محاسبه

| # | قاعده | ارجاع | TV |
|---|---|---|---|
| D1 | `Step* = sqrt(step_mother × step_pattern)` | `TH3Pivots_B.mqh` | ✅ پاریتی ۹۰ چک |
| D2 | جدول K زنده (۲.۵/۳.۰/۳.۵/۱.۰) | `TH3UnifiedK` | ✅ |
| D3 | جدول K بسته (قدیمی) | `TH3ClosedK` | ✅ |
| D4 | نردبان ۷ پله از D، خلاف لگ بسته | `TH3Recorder.mqh:215-218` | ✅ |
| D5 | رانگ مالک = `close(tf,1) × pct/100` از جدول پروفسور | `TH3Pivots_B.mqh:23-37` | ✅ |
| D6 | **walk-up تایم‌فریم مالک** تا ورود به بازه‌ی `[3,7]` | `TH3Pivots_A.mqh:1367-1387` | ⬜ فاز ۴ |
| D7 | قفل `base` = گواهی، نه تصمیم | `TH3Renderer_B.mqh:130-137` | ✅ |
| D8 | زنجیره‌ی seed | `TH3Renderer_B.mqh:80-90` | ✅ |
| D9 | کف رأی ۲.۴۰ رانگ + قلاده‌ی ۲۵٪ | `TH3Pivots_A.mqh:34,40` | ✅ (تشخیصی) |
| D10 | `GetCurrentTH3Frequency` با کران (۰,۱۲۰] | `TH3Tool_A.mqh:378-388` | ✅ |
| D11 | پیپ‌سایز (معدن = ۱۰×point) | `PerformanceOptimizations.mqh:168-215` | ✅ ۱۱/۱۱ |
| D12 | پیوت شش‌شرطی (PDF ص ۶-۷) | `TH3Pivots_A.mqh:295-434` | ✅ پورت شد — ⚠️ شرط ۲ برآورده نمی‌شود |
| D13 | مادر: matcher + امتیازدهی سه‌لایه | `TH3Pivots_A.mqh:643-766` | ⬜ فاز ۷ |
| D14 | ORG (پایه‌ی دور، ماکرو) | `TH3Pivots_A.mqh:593-625` | ⬜ فاز ۷ |
| D15 | پیوت مشترک (ص ۵۰) | `TH3Pivots_A.mqh:472-487` | ⬜ فاز ۷ |
| D16 | mitigation (تازه/مالیده) | `TH3Pivots_A.mqh:208-222` | ✅ در رجیستری |
| D17 | رأی/رتریس کامل با انتخاب k | `TH3Pivots_A.mqh:1068-1190` | 🟡 فقط کف + deepest |
| D18 | **TH / ATR**: براکت‌های ۱.۵۰/۱.۷۵/۲.۰۰ | `TH3Pivots_B.mqh:52-62` | ⬜ فاز ۶ |
| D19 | لیبل حالت step + basis («ATR | SS/LS») | `Util_A.mqh:685-716` | ⬜ فاز ۶ |

## E — خروجی داده

| # | قابلیت | ارجاع | TV |
|---|---|---|---|
| E1 | کلید `M` → نوشتن ردیف در `Dataset.csv` | `Biotak/TH3Recorder.mqh` | ❌ Pine فایل نمی‌نویسد |
| E2 | درخت `TH3_Dataset/{Logs,Samples,Screenshots}` | `TH3DatasetPaths.mqh` | ❌ |
| E3 | هش سورس (`TH3_SRC_HASH`) برای ردیابی نسخه | `#define TH3_SRC_HASH` | ✅ در provenance ی build |
| E4 | خط لاگ قابل پارس (P-TH3-LOG1) | `TH3Renderer_B.mqh:222-238` | ❌ → `log.info`/alert |

## F — پنل‌ها و readout

| # | توکن | معنا | TV |
|---|---|---|---|
| F1 | `Step` / `Ratio` / `K` | عدد اصلی و ورودی‌هایش | ✅ |
| F2 | `Dir` / `Anchor` | جهت و صندلی | ✅ |
| F3 | `Lock` | گواهی base vs pattern | ✅ |
| F4 | `Rung` / `TH rung` | رانگ مالک | ✅ (+منبع) |
| F5 | `TF` / `Owner` | تایم‌فریم چارت و مالک | 🟡 فاز ۴ |
| F6 | `Closed` | step جدول بسته | ⬜ فاز ۵ |
| F7 | `Freq` | فرکانس مؤثر | ⬜ فاز ۵ |
| F8 | `reaction X.XX/Y rungs` | رأی و کف | ✅ |
| F9 | `ATR | SS/LS` | مبنا و حالت | ⬜ فاز ۶ |
| F10 | `T3@TF err x%` | گواهی پیوت روی تیپ | ⬜ فاز ۷ |

## خلا‌صه‌ی عددی (شمارش‌شده، نه تخمینی)

```
$ grep -cE "^input .*inpTH3" Biotak/PropertiesAndInputs.mqh                    -> 16
$ grep -rhoE "#define +TH3_(SUFFIX|TEMP)_[A-Z0-9_]+" ... | sort -u | wc -l     -> 16
```

- **۱۶ ورودی `inpTH3*`** در ۱۰ گروه (جدول A)، **۱۶ خانواده‌ی نام شیء** در ۱۰ ردیف (جدول C)،
  **۱۹ قاعده‌ی محاسبه** (D)، **۱۰ توکن readout** (F)، **۴ مسیر داده** (E)، **۹ قابلیت ژست** (B).
- در تریدینگ‌ویو **قطعی‌الممکن‌نیست**: B1, B4, B5, B8, B9, E1, E2, E4 (پلتفرم کلیک و فایل ندارد).
- **انجام‌شده تا امروز**: A2, A3, C4, C5, C7, C8, D1-D5, D7-D12, D16, F1-F4, F8.

## دامنه‌ی این فهرست (تا کجا خوانده شده)

از گرپ سیستماتیک روی `PropertiesAndInputs.mqh`، `TH3Pivots_A/B.mqh`، `TH3Recorder.mqh`،
`TH3Renderer_B/C.mqh`، `TH3Tool_C.mqh`، `Util_A.mqh` و `TH3DatasetPaths.mqh` ساخته شده.
**خوانده نشده و در نتیجه غایب:** `BiotakMenu_A/B/C.mqh`، `BiotakPanels_*.mqh`،
`BiotakKit.mqh`، `BaseKnot_*.mqh`. اگر قابلیتی آن‌جا باشد، این فهرست آن را ندارد -
و این جمله عمداً این‌جاست تا فهرست، کامل‌تر از واقع به نظر نرسد.
