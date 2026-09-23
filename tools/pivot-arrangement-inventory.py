#!/usr/bin/env python3
"""pivot-arrangement-inventory — «چند نوع پیوت داریم؟» — the figure, where it
comes from, and a real census that goes looking for the classification behind it.

THE FIGURE
    Stated once, verbatim, and never expanded:

        «عرض کردیم بیش از ۱۴۰۳ نوع پیوت در بازار داریم که بستگی به آرایش و ترتیب
         قرار گیری کندل ها در کنار هم در مرحله بعد حتی زاویه های حرکتی میشه
         آنها را دسته بندی کرد و ما اصلا وارد آن بحث نمیشویم و فقط بر اساس چهار
         نوع کندلی که عرض کردیم دنبال شناسایی چند نوع پیوت هستیم که تکرار پذیری
         بالایی در بازار دارند ...»

    TREX METHOD, 2021-05-21, #سوال_شماره_210
      https://t.me/s/TREX_METHOD?before=86
    mirrored on the Q&A site under #شماتیک
      https://www.trexacademy.ir/questions/tag/143/

    Read it carefully, because the sentence contains its own refutation:
      * «آرایش و ترتیب قرار گیری کندل ها» — arrangement AND order.
      * «در مرحله بعد حتی زاویه های حرکتی» — an ANGLE. A continuous axis.
    A classification with a continuous axis has no finite count. So «بیش از
    ۱۴۰۳» is a floor on one discrete slice, and the master says outright that he
    will not enumerate it («ما اصلا وارد آن بحث نمیشویم»).

THE APPARENT PARADOX
    The classical canon next door is tiny: Bulkowski's thepatternsite.com, the
    very site this same course points students at, ranks «out of 103 candlestick
    patterns». 103 vs 1403. Both numbers are defensible at once, and the
    difference is the point: 103 counts NAMED SHAPES, the master counts
    ARRANGEMENTS — every ordering of the same candles as a separate animal.

    1440 = 2 x 6! is exactly that reading written as arithmetic:
    «۲ جهت  x  ترتیب قرار گیری شش کندل». Six roles (three momentum, master,
    cover, confirm), all orderings, both directions.

    And 1403 is ODD, which is the hard fact: any grid carrying a symmetric
    «جهت» axis multiplies by 2, so it can only ever total EVEN. 1403 cannot be a
    grid count of this space. It is 23 x 61. It was counted by hand, or heard
    wrong.

WHY THIS TOOL EXISTS
    «۱۴۰۳ نوع پیوت را پیدا کن» is not a lookup; there is no list to find. It is
    a SEARCH over classifications. This tool does the honest version of that:

      A. Holds every axis the course states, with its citation, so the census
         never invents one.
      B. Enumerates the taught skeleton for real — every arrangement, named,
         dumpable — instead of only multiplying cardinalities.
      C. Solves: sweeps classifications and reports which ones actually land on
         a target figure, and which axes each one had to stretch to get there.

Usage:  python tools/pivot-arrangement-inventory.py                 # the verdict
        python tools/pivot-arrangement-inventory.py --axes          # axis table
        python tools/pivot-arrangement-inventory.py --skeleton      # the census
        python tools/pivot-arrangement-inventory.py --solve 1440    # classifications that hit it
        python tools/pivot-arrangement-inventory.py --dump OUT.json # every arrangement
        python tools/pivot-arrangement-inventory.py --selftest
Exit 0 = clean, 1 = a selftest seed was not caught.
"""
import itertools
import json
import sys
from math import factorial

# The census is written in the course's own language, and a Windows console
# defaults to cp1252, which cannot encode a single Persian letter. Reconfigure
# rather than transliterate: the Persian IS the data here.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# ==========================================================================
# 1. THE AXES — every entry is a thing the course states. `cards` is the range
#    of cardinalities worth testing for that axis; `sourced` is the one the
#    course actually names. A classification that has to move an axis off its
#    `sourced` value is a stretch, and the solver says so out loud.
# ==========================================================================
AXES = [
    dict(key="side", name="جهت", cards=[2], sourced=2, src="#شماتیک",
         why="صعودی / نزولی — هر شماتیک یک جهت دارد"),
    dict(key="klass", name="دسته طول حرکت", cards=[4, 5], sourced=4,
         src="#دسته_بندی_کندل",
         why="اسپینینگ ۱-۷۹٪ / استاندارد ۸۰-۱۲۰٪ / لانگ‌بار ۱۲۰-۲۵۰٪ / اسپایک ۲۵۰٪+ "
             "(۵ = با احتساب کندل خودپوشاننده)"),
    dict(key="momentum", name="مومنتوم", cards=[2, 3], sourced=3, src="#انواع_پیوت",
         why="۱) سه کندل هم‌راستا  ۲) دو کندل لانگ‌بار/اسپایک  ۳) تک‌کندل"),
    dict(key="pivot", name="کندل پیوت", cards=[3, 4, 6, 8], sourced=8,
         src="#انواع_پیوت · #سوال_۲۱۰",
         why="۳ = سه نوع رسمی (استاندارد/اسپایک-لانگ‌بار/بیس‌پیوت) · "
             "۴ = چهار حالت مستر کندل · ۸ = هر شاهدی که دوره می‌دهد"),
    dict(key="engulf", name="عمق پوشش", cards=[4, 5], sourced=5, src="#انواع_پیوت",
         why="کل کندل / لو آخرین مستر / ۵۰٪ / خط فرضی ۱ ATR / بدنه"),
    dict(key="delay", name="تأخیر پوشش", cards=[2, 3, 4, 6], sourced=4,
         src="ص۹ · #سوال_۲۱۰",
         why="کندل برگشت در چه تعداد کندل پوشش می‌دهد؛ ۴ = ۱..۴ کندل (ص۹)"),
    dict(key="base", name="بیس", cards=[1, 2], sourced=2, src="#بیس_پیوت",
         why="۳ کندل درجا (پترن) / ۴ کندل درجا (درگیری با تایم بالاتر)"),
    dict(key="angle", name="زاویه حرکتی", cards=[1, 3], sourced=1,
         src="#سوال_۲۱۰",
         why="شارپ / تسویه / ملایم — استاد خودش این را «مرحله بعد» می‌داند؛ "
             "در عمل پیوسته است، پس ۱ = بیرون از شمارش"),
]

# The research anchor — and NOT a source for anything else in this file.
#
# Read directly from thepatternsite.com (CandleEntry.html and Hammer.html,
# 2026-09-19), not from a search snippet:
#   «All ranks are out of 103 candlestick patterns with the top performer
#    ranking 1.»
#   «… rank of 65 where 1 is best out of 103 candle types.»
#
# Two corrections that matter for how much weight this carries:
#   1. 103 is the RANKED set — the patterns they had enough samples to score.
#      Their own index headline says «over 100 different candle patterns» and
#      lists noticeably more names than 103, including entries that are not
#      candlesticks at all (Busted patterns, Chart patterns, Volume patterns).
#      So 103 is a STUDIED-SET size, not «how many candle shapes exist».
#   2. It counts NAMED SHAPES, not ARRANGEMENTS. That is the whole gap to the
#      course's figure: the classical world names a shape, the course counts
#      every ordering of the same candles separately.
#
# The link is the course's own, not ours: #مقدمه_پیوت says «سایت The pattern
# site که الگوهای کندل استیک رو میشه اینجا کامل دید».
ANCHORS = [
    (103, "thepatternsite.com's RANKED set: «All ranks are out of 103 candlestick "
          "patterns». Named shapes, not arrangements. The course itself sends "
          "students to this site, so it is the fair outside yardstick."),
    (103 * 2, "the same 103 doubled for direction — still shapes, still not "
              "arrangements. Doubling does not bridge the gap; ordering does."),
]

NOTED = 1403     # what the notes carry
QUOTED = 1440    # what the classes quote; == 2 x 6!


# ==========================================================================
# 2. ARITHMETIC
# ==========================================================================
def factorize(n):
    """Prime factorisation as {prime: exponent}. n >= 1."""
    if n < 1:
        raise ValueError("factorize needs n >= 1")
    f, d = {}, 2
    while d * d <= n:
        while n % d == 0:
            f[d] = f.get(d, 0) + 1
            n //= d
        d += 1
    if n > 1:
        f[n] = f.get(n, 0) + 1
    return f


def fstr(n):
    return " x ".join(f"{p}^{e}" if e > 1 else str(p) for p, e in sorted(factorize(n).items()))


def subset_products(axes, pool):
    """Every product of a DISTINCT set of axes drawn from `pool` (key -> card)."""
    keys = list(pool)
    out = []
    for r in range(1, len(keys) + 1):
        for combo in itertools.combinations(keys, r):
            p = 1
            for k in combo:
                p *= pool[k]
            out.append((combo, p))
    return out


def solve(target, axes=None):
    """Every classification that totals `target`, and how far each stretched.

    A stretch is an axis set to a cardinality the course does NOT name. The
    solver reports the stretch count so 'it hits 1403!' can never be quietly
    bought by inventing an axis.
    """
    axes = axes if axes is not None else AXES
    hits = []
    # cartesian sweep over each axis's candidate cardinalities
    for combo in itertools.product(*[a["cards"] for a in axes]):
        pool = {a["key"]: c for a, c in zip(axes, combo)}
        prod = 1
        for v in pool.values():
            prod *= v
        # (a) a plain product
        if prod == target:
            hits.append((dict(pool), 1, 1, 0))
        # (b) x k! — «ترتیب قرار گیری»
        for k in range(2, 9):
            if prod * factorial(k) == target:
                hits.append((dict(pool), k, 1, 0))
                break
        # (c) x 2^j — an axis genuinely repeated in the arrangement
        for j in range(1, 5):
            if prod * (2 ** j) == target:
                hits.append((dict(pool), 1, 2 ** j, 0))
                break
    # score each hit by how many axes had to leave their sourced cardinality
    by_src = {a["key"]: a["sourced"] for a in axes}
    uniq = {}
    for pool, k, f2, _ in hits:
        pool["_stretch"] = sum(1 for kk, v in pool.items()
                               if kk in by_src and v != by_src[kk])
        key = (tuple(sorted(pool.items())), k, f2)
        uniq[key] = (pool, k, f2)
    return sorted(uniq.values(), key=lambda h: h[0]["_stretch"])


# ==========================================================================
# 3. THE CENSUS — the taught skeleton, enumerated for real
# ==========================================================================
SKELETON = [
    ("momentum", "مومنتوم",
     ["سه کندل استاندارد هم‌راستا", "دو کندل لانگ‌بار/اسپایک", "تک‌کندل"],
     "#انواع_پیوت"),
    ("pivot", "کندل پیوت",
     ["مستر ۸۰٪ بدنه", "مستر ۸۰٪ شدو بالا", "مستر ۸۰٪ شدو پایین",
      "پین‌بار تبصره‌ای", "خودپوشاننده", "لانگ‌بار + خط فرضی",
      "اسپایک + خط فرضی", "اسپینینگ (بیس)"],
     "#انواع_پیوت · #سوال_۲۱۰"),
    ("engulf", "عمق پوشش",
     ["کل کندل (کلوز زیر لو مستر)", "بدنه", "۵۰٪", "خط فرضی ۱ ATR",
      "لو آخرین مستر"],
     "#انواع_پیوت"),
    ("delay", "تأخیر پوشش", None, "ص۹ · #سوال_۲۱۰"),
    ("side", "جهت", ["صعودی", "نزولی"], "#شماتیک"),
]
DELAY_SOURCED = ["۱ کندل", "۲ کندل", "۳ کندل", "۴ کندل"]          # ص۹
DELAY_STRETCHED = ["۱ کندل", "۲ کندل", "۳ کندل", "۴ کندل", "۵ کندل", "۶ کندل"]


def census(delays=None, enum=False):
    """Count (and optionally enumerate) the taught skeleton."""
    delays = delays if delays is not None else DELAY_SOURCED
    slots = []
    for key, label, opts, src in SKELETON:
        if key == "delay":
            slots.append((key, label, delays, src))
        else:
            slots.append((key, label, opts, src))
    n = 0
    rows = []
    for combo in itertools.product(*[s[2] for s in slots]):
        n += 1
        if enum:
            rows.append(dict(zip([s[0] for s in slots], combo)))
    return n, rows


# ==========================================================================
# 4. REPORT
# ==========================================================================
def print_axes():
    print("\n  axis                              sourced  tested   source")
    for a in AXES:
        print(f"    {a['name']:<28} {a['sourced']:>4}     {str(a['cards']):<10} {a['src']}")
    print("\n  Each 'why' line is the citation, not a guess:")
    for a in AXES:
        print(f"    {a['name']}: {a['why']}")


def print_census():
    n, _ = census()
    ns, _ = census(DELAY_STRETCHED)
    print(f"\n  THE TAUGHT SKELETON — {len(SKELETON)} slots, enumerated for real")
    for key, label, opts, src in SKELETON:
        cnt = len(opts) if opts else len(DELAY_SOURCED)
        print(f"    {label:<18} x{cnt:<3} {src}")
        if opts:
            for o in opts:
                print(f"        · {o}")
        else:
            print("        · " + " / ".join(DELAY_SOURCED))
    print(f"\n    total = {n} arrangements")
    print(f"    with the cover delay stretched to 1..6 -> {ns}")
    if ns == QUOTED:
        print(f"    ^ that is {QUOTED} exactly, and {QUOTED} = 2 x 6! — "
              f"«۲ جهت x ترتیب قرار گیری شش کندل».")


def print_solve(target):
    print(f"\n  SOLVING FOR {target}  [{fstr(target)}]")
    odd = target % 2 == 1
    even_axes = [a["name"] for a in AXES if a["cards"] and all(c % 2 == 0 for c in a["cards"])]
    if odd and even_axes:
        print(f"    ✗ {target} is ODD. The «{even_axes[0]}» axis is symmetric and "
              f"multiplies by 2,")
        print(f"      so every legal total in this grammar is EVEN. "
              f"{target} cannot be a grid count.")
    hits = solve(target)
    if not hits:
        print(f"    · no classification over these axes totals {target}, "
              f"with or without a factorial / repeat term.")
        # closest reachable neighbours
        reach = set()
        for combo in itertools.product(*[a["cards"] for a in AXES]):
            p = 1
            for v in combo:
                p *= v
            reach.add(p)
            for k in range(2, 9):
                reach.add(p * factorial(k))
            for j in range(1, 5):
                reach.add(p * (2 ** j))
        near = sorted(reach, key=lambda v: abs(v - target))[:4]
        print(f"    · nearest reachable totals: {near}")
        return
    print(f"    ✓ {len(hits)} classification(s) hit it. Stretches = axes pushed "
          f"off their sourced cardinality.")
    for pool, k, f2 in hits[:8]:
        bits = " x ".join(f"{next(a['name'] for a in AXES if a['key']==kk)}({v})"
                          for kk, v in sorted(pool.items()) if not kk.startswith("_"))
        extra = ""
        if k > 1:
            extra += f" x {k}!"
        if f2 > 1:
            extra += f" x {f2}"
        print(f"      [stretch {pool['_stretch']}] {bits}{extra} = {target}")
    if len(hits) > 8:
        print(f"      … {len(hits)-8} more")


def print_verdict():
    print("\n" + "=" * 74)
    print("  THE VERDICT")
    print("=" * 74)
    print("""
  The master did not leave 1403 for us to find — he left us the AXES and said
  he would not enumerate. And he was right not to: one of his own axes, «زاویه
  حرکتی», is continuous, so the space as he states it is not finite at all.

  What IS finite is the slice he actually teaches. Enumerated, it is 960
  arrangements — every combination of momentum form x pivot candle x cover
  depth x delay x direction. Push the one unsourced axis (cover delay 1..4 ->
  1..6) and it becomes 1440 exactly, which is also 2 x 6!:
  «۲ جهت x ترتیب قرار گیری شش کندل».

  1403 cannot be produced by any of this, and the reason is arithmetic, not
  opinion: it is odd, so no grammar carrying a symmetric جهت axis can total it.
  The one outside number worth putting next to it is the classical canon's: the
  site this same course points students at ranks «out of 103 candlestick
  patterns». Those count NAMED SHAPES; the master counts ARRANGEMENTS. That gap
  is real and is exactly the 1440-vs-103 story — but note 103 is their RANKED
  set, not their whole index, so it is a yardstick and not a census either.
  «۱۴۰۳» differs from «۱۰۳» by exactly a dropped/added «۱۴»; a transcription
  slip across a spoken number remains the least exotic explanation on the table
  — but it is a hypothesis, not a finding.
""")
    for v, note in ANCHORS:
        print(f"  ANCHOR  {v:>6}  {note}")
    print()


def selftest():
    """Seed deliberate faults; every one must be caught."""
    faults = 0

    def check(cond, what):
        nonlocal faults
        if not cond:
            print(f"  SEED NOT CAUGHT: {what}")
            faults += 1

    check(factorize(1440) == {2: 5, 3: 2, 5: 1}, "factorize(1440)")
    check(factorize(1403) == {23: 1, 61: 1}, "factorize(1403) = 23 x 61")
    check(fstr(1403) == "23 x 61", "fstr(1403)")

    # the tautology that actually matters here
    check(1403 % 2 == 1, "1403 is odd")
    check(1440 == 2 * factorial(6), "1440 == 2 x 6!")
    check(factorial(6) == 720, "6! == 720")

    # the census is a real enumeration, not a hard-coded number
    n, rows = census(enum=True)
    check(n == 3 * 8 * 5 * 4 * 2, f"census count {n}")
    check(n == 960, "sourced census is 960")
    check(len(rows) == n, "enumeration length matches the count")
    check(len(set(json.dumps(r, sort_keys=True) for r in rows)) == n,
          "every enumerated arrangement is distinct")
    ns, _ = census(DELAY_STRETCHED)
    check(ns == 1440, f"stretched census {ns} == 1440")

    # the solver must hit 1440 and must NOT hit an odd target
    check(len(solve(1440)) > 0, "solver finds 1440")
    check(solve(1403) == [], "solver must find nothing for 1403")
    check(solve(961) == [], "solver must find nothing for 961 (odd)")

    # stretching must be counted, or the solver can buy answers for free
    hits = solve(1440)
    check(all("_stretch" in p for p, _, _ in hits), "every hit carries a stretch count")
    check(min(p["_stretch"] for p, _, _ in hits) <= 2, "1440 is reachable with few stretches")

    # a doctored axis set must move the answer
    doctored = [dict(a) for a in AXES]
    doctored[0]["cards"] = [4]
    check(solve(1440, doctored) != hits, "doctored cardinality must change the hit set")

    print(f"  selftest: {faults} uncaught seed(s)")
    return faults


def main(argv):
    if "--selftest" in argv:
        return 1 if selftest() else 0

    print("pivot-arrangement-inventory — «چند نوع پیوت داریم؟»")
    print(f"  {len(AXES)} axes, sourced census {census()[0]} arrangements, "
          f"figure under test {NOTED} / {QUOTED}")

    if "--axes" in argv:
        print_axes()
        return 0
    if "--skeleton" in argv:
        print_census()
        return 0
    if "--solve" in argv:
        print_solve(int(argv[argv.index("--solve") + 1]))
        return 0
    if "--dump" in argv:
        out = argv[argv.index("--dump") + 1]
        n, rows = census(DELAY_STRETCHED, enum=True)
        with open(out, "w", encoding="utf-8") as f:
            json.dump({"count": n, "slots": [s[1] for s in SKELETON],
                       "arrangements": rows}, f, ensure_ascii=False, indent=1)
        print(f"\n  wrote {n} arrangements to {out}")
        return 0

    print_census()
    print_solve(NOTED)
    print_solve(QUOTED)
    print_verdict()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
