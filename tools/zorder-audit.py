#!/usr/bin/env python3
"""zorder-audit — the gate behind P-UI-31 (the Z ladder).

MT4 paints the SCREEN-SPACE objects (OBJ_LABEL / OBJ_BUTTON / OBJ_BITMAP_LABEL
/ OBJ_EDIT / OBJ_RECTANGLE_LABEL) in ZORDER order and, on a tie, in creation
order. The SAME property is the click priority: only the object with the
highest priority under the cursor receives CHARTEVENT_CLICK. So "what is on top"
and "what is clicked" are one number, and that number now has ONE owner —
the Z LADDER block in `Biotak/ConstantsAndEnums.mqh`.

This script keeps that true. Five checks, all on the source, no terminal:

  1. LADDER        every `#define Z_*` parses, and the values are UNIQUE
  2. ALIASES       `#define X  Z_*` aliases (PNL_DD_Z_*, BK_DD_Z_*) resolve
  3. ORDER         the documented rung order holds, and Z_PANEL_TOP is the max
  4. CALL SITES    every `OBJPROP_ZORDER` write and every `.zOrder =` assignment
                   names a rung (or a pass-through parameter/field) — never a
                   literal, never arithmetic. This is the rule the ladder's
                   comment states: "never invent a literal at a call site".
  5. PROOF BAND    tools/panel-mt4-sim.py's `BAND` table (rank -> rung) is
                   monotone with the ladder, every rank in use is declared,
                   and the type paints last. The sim is the only way to see a
                   card without MT4, so if its paint order drifts, every
                   measurement taken off the proof is wrong.

KNOWN LIMIT: check 5 proves the declared table and its use, not that each
individual op picked the rank matching its own rung (the sim's ranks are chosen
per call site by hand). Closing that would mean deriving an asset-family ->
rung map from the MQL's `PnlSetBitmap(..., res, rung)` call sites and comparing
it with the ranks the sim passes; the knob (rank 6 -> 4) was the one real
inversion this found by hand.

Usage:  python tools/zorder-audit.py [--quiet] [--sites] [--selftest]
        --selftest seeds each fault into a doctored source and requires the
        matching check to catch it (a gate that cannot fail proves nothing).
        --sites prints the inventory: every ZORDER write and the rung it names,
        sorted by rung — the fastest way to answer "what is above what".
Exit 0 = clean, 1 = the ladder or a call site is broken.
"""

import ast
import os
import re
import sys

QUIET = "--quiet" in sys.argv
SITES = "--sites" in sys.argv
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def note(*a):
    if not QUIET:
        print(*a)


def path(*p):
    return os.path.join(ROOT, *p)


# ── sources ------------------------------------------------------------------
LADDER_FILE = "Biotak/ConstantsAndEnums.mqh"
ALIAS_FILES = ["Biotak/BiotakPanels.mqh"]
SIM_FILE = "tools/panel-mt4-sim.py"

# Diagnostic harnesses: standalone probes that include no ladder and set a
# local ZORDER on purpose (Biotak_ZoneRender_Test) or only READ it back
# (Biotak Sync Compare). They are not product surfaces.
EXEMPT_FILES = {"Biotak_ZoneRender_Test.mq4", "Biotak Sync Compare.mq4",
                "Biotak ATR Audit.mq4", "Biotak_TH3_Test.mq4",
                "Biotak_TradePlan_Golden_Test.mq4"}


def product_sources():
    """Every MQL source that ships in the indicator."""
    out = []
    for dirpath, _dirs, files in os.walk(path("Biotak")):
        for f in files:
            if f.endswith(".mqh"):
                out.append(os.path.relpath(os.path.join(dirpath, f), ROOT))
    for f in ("Biotak Trigger TH3.mq4", "Biotak Trigger TH3 Lite.mq4"):
        out.append(f)
    return sorted(p.replace("\\", "/") for p in out)


def read(rel):
    with open(path(*rel.split("/")), "r", encoding="utf-8", errors="replace") as fh:
        return fh.read()


# ── 1. the ladder ------------------------------------------------------------
def parse_ladder():
    """{name: value} for every `#define Z_* <int>` in the ladder file, in the
    order they are declared (the declaration order IS the paint order)."""
    src = read(LADDER_FILE)
    ladder = []
    for m in re.finditer(r"^\s*#define\s+(Z_[A-Z0-9_]+)\s+(\d+)\s*(?://(.*))?$",
                         src, re.M):
        ladder.append((m.group(1), int(m.group(2)), (m.group(3) or "").strip()))
    return ladder


def parse_aliases():
    """`#define PNL_DD_Z_SH Z_PANEL_DD_SH` -> {"PNL_DD_Z_SH": "Z_PANEL_DD_SH"}"""
    aliases = {}
    for rel in ALIAS_FILES:
        for m in re.finditer(r"^\s*#define\s+([A-Z][A-Z0-9_]*)\s+(Z_[A-Z0-9_]+)\s*(?://.*)?$",
                             read(rel), re.M):
            aliases[m.group(1)] = m.group(2)
    return aliases


# ── 3. the documented order --------------------------------------------------
# Each line is a chain of rungs that must be strictly increasing. Split into
# sections exactly as the ladder file documents them.
ORDER = [
    ("chart content", ["Z_CHART_ZONE", "Z_CHART_LINE", "Z_CHART_TOOL", "Z_BOX_RAY",
                       "Z_BOX_FILL", "Z_BOX_EDGE", "Z_BOX_INFO", "Z_BOX_TEXT",
                       "Z_CHART_LABEL"]),
    ("under the card", ["Z_BOX_HINT", "Z_BOX_BADGE", "Z_STRIP", "Z_STRIP_ICON",
                        "Z_STRIP_OVER"]),
    ("ring menu", ["Z_MENU_PANEL", "Z_MENU_DOT", "Z_MENU_ITEM", "Z_MENU_ICON",
                   "Z_MENU_BADGE", "Z_MENU_BADGE_TX", "Z_MENU_PAGER",
                   "Z_MENU_ORB", "Z_MENU_TIP_BG", "Z_MENU_TIP"]),
    ("panel rows", ["Z_PANEL_CARD", "Z_PANEL_TOPBAR", "Z_PANEL_ACT", "Z_PANEL_BAND",
                    "Z_PANEL_SEP", "Z_PANEL_HAIR", "Z_PANEL_BASE", "Z_PANEL_SKIN",
                    "Z_PANEL_CHIP", "Z_PANEL_INK", "Z_PANEL_GLYPH", "Z_PANEL_GLOSS",
                    "Z_PANEL_SW", "Z_PANEL_EDIT", "Z_PANEL_KNOB", "Z_PANEL_TEXT",
                    "Z_PANEL_CTL", "Z_PANEL_MARK"]),
    ("popovers", ["Z_PANEL_DD_SH", "Z_PANEL_DD_BG", "Z_PANEL_DD_SEL",
                  "Z_PANEL_DD_LBL", "Z_PANEL_DD_ICO", "Z_PANEL_POP",
                  "Z_PANEL_POP_BG", "Z_PANEL_POP_CTL", "Z_PANEL_POP_FG",
                  "Z_PANEL_TOP"]),
]

# The three relations that carry the design (see the ladder's own header):
#   * the CARD owns the top: nothing the indicator draws may sit over a card
#     except a popover it opened itself
#   * the ring menu and the hover tip sit BELOW the card
#   * the popovers sit ABOVE every row rung
RELATIONS = [
    ("menu under the card", ["Z_MENU_*"], ["Z_PANEL_CARD"]),
    ("box pills under the card", ["Z_BOX_HINT", "Z_BOX_BADGE", "Z_STRIP*"],
     ["Z_PANEL_CARD"]),
    ("popovers over the rows", ["Z_PANEL_CARD..Z_PANEL_MARK"],
     ["Z_PANEL_DD_SH"]),
]


# ── MQL call-site parsing ----------------------------------------------------
def split_args(call_body):
    """Top-level comma split (nested parentheses / string literals respected)."""
    args, depth, cur, instr = [], 0, "", False
    i = 0
    while i < len(call_body):
        ch = call_body[i]
        if instr:
            cur += ch
            if ch == "\\":
                cur += call_body[i + 1:i + 2]
                i += 2
                continue
            if ch == '"':
                instr = False
        elif ch == '"':
            instr = True
            cur += ch
        elif ch == "(":
            depth += 1
            cur += ch
        elif ch == ")":
            depth -= 1
            cur += ch
        elif ch == "," and depth == 0:
            args.append(cur.strip())
            cur = ""
        else:
            cur += ch
        i += 1
    args.append(cur.strip())
    return args


def find_calls(src, fname, skip_decl=False):
    """Every `fname(` call with its top-level argument list (multi-line safe).
    skip_decl drops a function DEFINITION (its body opens with `{`) - the
    declaration's own parameter list is not a call site."""
    out = []
    for m in re.finditer(r"(?<![A-Za-z0-9_])" + re.escape(fname) + r"\s*\(", src):
        i = m.end() - 1
        depth, instr = 0, False
        while i < len(src):
            ch = src[i]
            if instr:
                if ch == "\\":
                    i += 2
                    continue
                if ch == '"':
                    instr = False
            elif ch == '"':
                instr = True
            elif ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        if skip_decl and re.match(r"\s*\{", src[i + 1:i + 8]):
            continue
        line = src.count("\n", 0, m.start()) + 1
        out.append((line, split_args(src[m.end():i])))
    return out


PASS_THROUGH = re.compile(r"^[a-z][A-Za-z0-9_]*$")            # `z`
PASS_FIELD = re.compile(r"^[A-Za-z_][A-Za-z0-9_\[\]\.]*(\.zOrder)$")


def is_rung(expr, ladder, aliases):
    e = expr.strip()
    e = aliases.get(e, e)
    return e in ladder


def ladder_value(expr, ladder, aliases):
    e = aliases.get(expr.strip(), expr.strip())
    return ladder.get(e, "pass") if e in ladder else "pass"


def allowed_passthrough(expr):
    e = expr.strip()
    return bool(PASS_THROUGH.match(e) or PASS_FIELD.match(e))


def z_helpers():
    """Functions whose LAST parameter is a z rung: a call site must hand them a
    rung too, or the ladder leaks at the second hop (`PnlSetBitmap(..., 1500)`).
    Returns {function_name: z_argument_index} (index 0 = last argument)."""
    out = {}
    for rel in product_sources():
        src = read(rel)
        for m in re.finditer(r"\b(?:void|bool|int|string)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^;{)]*)\)\s*\n?\s*\{",
                             src, re.S):
            params = split_args(m.group(2).strip())
            if not params or not params[-1]:
                continue
            last = params[-1]
            if re.search(r"\b(const\s+)?int\s+z(Order)?\s*$", last):
                out[m.group(1)] = 0          # 0 = the last argument
    return out


def check_call_sites(ladder, aliases):
    """Rule: a ZORDER write - direct or through a z-taking helper - names a
    rung or forwards a parameter/field, never a literal."""
    helpers = z_helpers()
    bad, ok, exempt, inv = [], [], 0, []
    for rel in product_sources():
        base = os.path.basename(rel)
        src = read(rel)
        # ObjectSetInteger(chart_id, name, property, value) -> value is args[3]
        for line, args in find_calls(src, "ObjectSetInteger"):
            if len(args) < 4 or args[2].strip() != "OBJPROP_ZORDER":
                continue
            if base in EXEMPT_FILES:
                exempt += 1
                continue
            _judge(bad, inv, ok, rel, line, args[1], args[3], ladder, aliases)
        for fn, pos in sorted(helpers.items()):
            for line, args in find_calls(src, fn, skip_decl=True):
                if len(args) < 2:
                    continue
                if base in EXEMPT_FILES:
                    exempt += 1
                    continue
                _judge(bad, inv, ok, rel, line, args[0], args[pos - 1], ladder, aliases)
        # struct-field assignments: `lines[i].zOrder = config.zOrder;`
        for m in re.finditer(r"\.zOrder\s*=\s*([^;]+);", src):
            if base in EXEMPT_FILES:
                continue
            _judge(bad, inv, ok, rel,
                   src.count("\n", 0, m.start()) + 1, ".zOrder",
                   m.group(1), ladder, aliases)
    if SITES:
        print("\n-- ZORDER call sites, lowest rung first --")
        key = lambda t: (0, t[0]) if isinstance(t[0], int) else (1, 0)
        for val, rel, line, name in sorted(inv, key=key):
            print("%6s  %-32s:%-5d %s" % (val, rel, line, name[:60]))
        print("\nhelper z params: %s" % ", ".join(sorted(helpers)))
        print("")
    return ok, bad, exempt


def _judge(bad, inv, ok, rel, line, name, expr, ladder, aliases):
    if is_rung(expr, ladder, aliases) or allowed_passthrough(expr):
        inv.append((ladder_value(expr, ladder, aliases), rel, line, name))
        ok.append(1)
    else:
        bad.append((rel, line, expr))


def check_reads():
    """`ObjectGetInteger(..., OBJPROP_ZORDER)` is a read and must exist only in
    the diagnostics — the indicator itself has no business asking."""
    out = []
    for rel in product_sources():
        src = read(rel)
        for line, args in find_calls(src, "ObjectGetInteger"):
            if len(args) >= 3 and args[2].strip() == "OBJPROP_ZORDER":
                out.append((rel, line))
    return out


# ── 5. the sim's paint bands -------------------------------------------------
def parse_sim_bands(src):
    """The sim's `BAND = {rank: [rung, ...]}` literal and `TEXT_BAND = n`.
    Parsed with ast so a typo in the table is a hard error, not a silent pass."""
    m = re.search(r"^BAND\s*=\s*(\{.*?^\})", src, re.M | re.S)
    if not m:
        return None, None, ["cannot find the BAND table (P-UI-31)"]
    try:
        band = ast.literal_eval(m.group(1))
    except (ValueError, SyntaxError) as exc:
        return None, None, ["BAND table does not parse: %s" % exc]
    t = re.search(r"^TEXT_BAND\s*=\s*(\d+)", src, re.M)
    if not t:
        return None, None, ["cannot find TEXT_BAND"]
    return band, int(t.group(1)), []


def check_sim_bands(ladder):
    """The proof is MT4's paint order: the sim's bands must be monotone with
    the ladder, every band used must be declared, and the TYPE must paint last
    (no rung above Z_PANEL_TEXT in a band above the text's band). If any of
    that drifts, `--audit`'s overlap gate is testing an order the terminal does
    not have - and every measurement taken off the proof is wrong."""
    src = read(SIM_FILE)
    band, text_band, errs = parse_sim_bands(src)
    if errs:
        return None, None, [(e, []) for e in errs]
    problems = []
    for b, rungs in sorted(band.items()):
        for r in rungs:
            if r not in ladder:
                problems.append(("band %d names `%s`, not a ladder rung" % (b, r), []))
    ranks = sorted(band)
    for b1, b2 in zip(ranks, ranks[1:]):
        lo, hi = [ladder[r] for r in band[b1] if r in ladder], \
                 [ladder[r] for r in band[b2] if r in ladder]
        if not lo or not hi:
            continue
        if min(lo) > min(hi) or max(lo) > max(hi):
            problems.append(("band %d (%d..%d) is not below band %d (%d..%d)"
                             % (b1, min(lo), max(lo), b2, min(hi), max(hi)), []))
    if text_band not in band:
        problems.append(("TEXT_BAND %d is not declared in BAND" % text_band, []))
    else:
        text_rungs = [ladder[r] for r in band[text_band] if r in ladder]
        if not text_rungs:
            problems.append(("TEXT_BAND %d names no rung" % text_band, []))
        else:
            highest = max(text_rungs)
            for b, rungs in sorted(band.items()):
                if b <= text_band:
                    continue
                for r in rungs:
                    if r in ladder and ladder[r] < highest:
                        problems.append(
                            ("rung %s (%d) sits in band %d, above the type's "
                             "band %d - the type must paint last"
                             % (r, ladder[r], b, text_band), []))
    used = {text_band: ["Canvas.text default"]}
    for fn, argi in (("img", 5), ("rect", 5)):
        for line, args in find_calls(src, "c." + fn):
            if len(args) > argi and re.match(r"^\d+$", args[argi].strip()):
                b = int(args[argi])
                used.setdefault(b, []).append("%s:%d" % (fn, line))
    for b, where in sorted(used.items()):
        if b not in band:
            problems.append(("band %d used at %s is not declared in BAND"
                             % (b, ", ".join(where[:3])), []))
    return text_band, used, problems


def main():
    ladder_list = parse_ladder()
    ladder = dict((n, v) for n, v, _ in ladder_list)
    aliases = parse_aliases()
    fails = []

    note("ladder: %d rungs in %s" % (len(ladder_list), LADDER_FILE))
    if not ladder:
        print("FAIL: no `#define Z_*` found - the ladder is the one owner, it "
              "cannot be empty")
        return 1

    # 1. uniqueness
    seen = {}
    for n, v, _ in ladder_list:
        if v in seen:
            fails.append("duplicate rung value %d: %s and %s" % (v, seen[v], n))
        seen[v] = n

    # 2. aliases resolve
    note("aliases: %d" % len(aliases))
    for a, target in sorted(aliases.items()):
        if target not in ladder:
            fails.append("alias %s -> %s is not a ladder rung" % (a, target))

    # 3. order
    for family, chain in ORDER:
        missing = [n for n in chain if n not in ladder]
        if missing:
            fails.append("%s: missing rung(s) %s" % (family, ", ".join(missing)))
            continue
        for a, b in zip(chain, chain[1:]):
            if ladder[a] >= ladder[b]:
                fails.append("%s: %s (%d) must be below %s (%d)"
                             % (family, a, ladder[a], b, ladder[b]))
    top = ladder.get("Z_PANEL_TOP")
    if top is not None and top != max(ladder.values()):
        fails.append("Z_PANEL_TOP (%d) must be the highest rung, found %d"
                     % (top, max(ladder.values())))
    for label, under, above in RELATIONS:
        lo = [v for n, v in ladder.items() if _matches(n, under)]
        hi = [v for n, v in ladder.items() if _matches(n, above)]
        if not lo or not hi:
            continue
        if max(lo) >= min(hi):
            fails.append("%s: %s reaches %d, %s starts at %d"
                         % (label, under, max(lo), above, min(hi)))

    # 4. call sites
    ok, bad, exempt = check_call_sites(ladder, aliases)
    note("call sites: %d on a rung / pass-through, %d exempt (harness)"
         % (len(ok), exempt))
    for rel, line, expr in bad:
        fails.append("%s:%d writes ZORDER as `%s` - name a rung (Z_*) or "
                     "forward a parameter" % (rel, line, expr))

    for rel, line in check_reads():
        if os.path.basename(rel) not in EXEMPT_FILES:
            fails.append("%s:%d READS OBJPROP_ZORDER (a diagnostic, not product "
                         "code)" % (rel, line))

    # 5. the proof's paint order
    text_band, used, problems = check_sim_bands(ladder)
    if text_band is None:
        for msg, _where in problems:
            fails.append("panel-mt4-sim.py: %s" % msg)
    else:
        note("proof: bands %s used, type band %d"
             % (",".join(str(b) for b in sorted(used)), text_band))
        for msg, where in problems:
            fails.append("panel-mt4-sim.py: %s%s"
                         % (msg, (" (" + ", ".join(where) + ")") if where else ""))

    # coverage — an unused rung is a smell, not a failure
    used = set()
    for rel in product_sources():
        src = read(rel)
        used |= set(re.findall(r"\b(Z_[A-Z0-9_]+)\b", src))
    for a, target in aliases.items():
        used.add(target)
    unused = [n for n, _, _ in ladder_list if n not in used]
    if unused:
        note("unused rungs: %s" % ", ".join(unused))

    if fails:
        print("")
        for f in fails:
            print("FAIL: " + f)
        print("\n%d problem(s) - the Z ladder no longer proves the paint order."
              % len(fails))
        return 1
    print("zorder audit: clean - %d rungs, every call site named, the proof "
          "paints the type last" % len(ladder_list))
    return 0


def _matches(name, patterns):
    for p in patterns:
        if p.endswith("*") and name.startswith(p[:-1]):
            return True
        if p == "Z_PANEL_CARD..Z_PANEL_MARK" and name.startswith("Z_PANEL_"):
            return name not in ("Z_PANEL_DD_SH", "Z_PANEL_DD_BG", "Z_PANEL_DD_SEL",
                                "Z_PANEL_DD_LBL", "Z_PANEL_DD_ICO", "Z_PANEL_POP",
                                "Z_PANEL_POP_BG", "Z_PANEL_POP_CTL",
                                "Z_PANEL_POP_FG", "Z_PANEL_TOP")
        if p == name:
            return True
    return False


# ── negative control ---------------------------------------------------------
# A gate that cannot fail proves nothing. `--selftest` seeds each fault into a
# doctored copy of a real source and requires the matching check to catch it.
def selftest():
    global read
    real_read = read
    ladder_list = parse_ladder()
    ladder = dict((n, v) for n, v, _ in ladder_list)
    aliases = parse_aliases()
    cases = []

    def with_source(rel, old, new):
        # A seed that no longer exists in the file would make its case a silent
        # no-op: refuse it instead, so a stale selftest cannot pass.
        if old not in real_read(rel):
            raise SystemExit("selftest seed is stale (not in %s): %s" % (rel, old))

        def patched(r):
            src = real_read(r)
            return src.replace(old, new) if r == rel else src
        return patched

    # 1. an EXPRESSION instead of a rung at a direct site
    read = with_source("Biotak/BiotakPanels.mqh",
                       "ObjectSetInteger(0,en,OBJPROP_ZORDER,Z_PANEL_EDIT);",
                       "ObjectSetInteger(0,en,OBJPROP_ZORDER,Z_PANEL_EDIT+1);")
    _ok, bad, _ex = check_call_sites(ladder, aliases)
    cases.append(("an expression instead of a rung is reported", bool(bad)))
    read = with_source("Biotak/BiotakPanels.mqh",
                       "ObjectSetInteger(0,PnlName(item,row,\"NAV\"),OBJPROP_ZORDER,Z_PANEL_BASE);",
                       "ObjectSetInteger(0,PnlName(item,row,\"NAV\"),OBJPROP_ZORDER,1500);")
    _ok, bad, _ex = check_call_sites(ladder, aliases)
    cases.append(("a raw 1500 literal is reported", bool(bad)))

    # 2. a literal handed to a z-taking helper. (The seed used to be the row
    #    keycap call; P-UI-32 moved the cap + its letter into PnlKeycapAt, whose
    #    z is now a forwarded PARAMETER there — so the literal must be seeded at
    #    a site that still passes a rung by name.)
    read = with_source("Biotak/BiotakPanels.mqh",
                       "\"::Files\\\\Icons\\\\pal_card.bmp\", Z_PANEL_POP);",
                       "\"::Files\\\\Icons\\\\pal_card.bmp\", 1600);")
    _ok, bad, _ex = check_call_sites(ladder, aliases)
    cases.append(("a literal at a helper call site is reported", bool(bad)))

    # 3. a duplicated rung value
    read = with_source(LADDER_FILE, "#define Z_PANEL_BAND   1486",
                       "#define Z_PANEL_BAND   1484")
    dup = [n for n, v, _ in parse_ladder()]
    vals = [v for _n, v, _ in parse_ladder()]
    cases.append(("a duplicate rung value is reported",
                  len(vals) > len(set(vals))))

    # 4a. a band declared with a rung that is not on the ladder
    read = with_source(SIM_FILE, '6: ["Z_PANEL_MARK"]', '6: ["Z_PANEL_NOPE"]')
    _tb, _used, problems = check_sim_bands(ladder)
    cases.append(("a band naming an unknown rung is reported", bool(problems)))
    # 4b. a band that inverts the ladder order (MARK moved below KNOB's rung)
    read = with_source(SIM_FILE, '6: ["Z_PANEL_MARK"]', '6: ["Z_PANEL_SKIN"]')
    _tb, _used, problems = check_sim_bands(ladder)
    cases.append(("a band that inverts the ladder is reported", bool(problems)))
    # 4c. a band ABOVE the type's band holding a rung below the type
    read = with_source(SIM_FILE, '6: ["Z_PANEL_MARK"]', '6: ["Z_PANEL_KNOB"]')
    _tb, _used, problems = check_sim_bands(ladder)
    cases.append(("a rung below the type in a higher band is reported",
                  bool(problems)))
    read = real_read
    # 4d. a rank used at a call site but never declared
    read = with_source(SIM_FILE, "kw, kw, 4)", "kw, kw, 7)")
    _tb, _used, problems = check_sim_bands(ladder)
    cases.append(("an undeclared rank at a call site is reported", bool(problems)))

    # 5. the declared bands are exactly the ranks in use (no silent band)
    read = real_read
    cases.append(("the declared bands are exactly the ones used",
                  sorted(parse_sim_bands(real_read(SIM_FILE))[0]) ==
                  sorted(b for b in check_sim_bands(ladder)[1])))

    read = real_read
    for name, ok in cases:
        print("%-52s %s" % (name, "caught" if ok else "MISSED"))
    missed = [n for n, ok in cases if not ok]
    if missed:
        print("\nselftest FAILED: %d fault(s) went undetected" % len(missed))
        return 1
    print("\nselftest: %d/%d faults caught - the audit is not vacuous"
          % (len(cases), len(cases)))
    return 0


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv else main())
