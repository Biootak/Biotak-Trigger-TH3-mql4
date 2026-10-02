#!/usr/bin/env python3
"""
THE NARROWING DOCTOR — one symptom in, one core gap out.

WHY THIS EXISTS. Debugging this panel blind was slow for a measured reason, not a
mysterious one: a defect can enter at any of six places (a constant, the accordion's
layout, the count rule, the paint's ops, the birth of an object's layer, and the
terminal's real pixels), and only TWO of those had a probe. So every hunt started by
re-reading the same files and ended on a screenshot, and a screenshot proves a paint,
not a seat — the fix took an hour because the *measurement* did not exist.

So the loop here is the opposite of blind: run one probe per stage, DELETE every stage
that agrees, and the surviving stage is the core gap. Musk's "break it to the core"
is arithmetic here — the probe that diverges is the answer, and if NO stage can even
see the quantity you are chasing, that blind stage IS the finding (a fault that enters
there reaches the terminal unseen; that is P-DRAW-119's class).

  python tools/debug-doctor.py                    # instruments + every stage on every tab
  python tools/debug-doctor.py --env              # instruments only — what is broken in the LOOP
  python tools/debug-doctor.py --symptom count    # «عددِ بند اشتباه است» -> the count rule
  python tools/debug-doctor.py --symptom missing  # «متن‌ها ناقص است» -> label/layer/pixel
  python tools/debug-doctor.py --symptom stroke   # dump the Stroke tab's own seats
  python tools/debug-doctor.py --list             # the routing table, nothing else
  python tools/debug-doctor.py --fast             # skip the terminal stage (no node run)

Every number this prints is READ, never transcribed: the constants from
Biotak/DrawStrip.mqh's own `#define`s, the rows from tools/sim-gear-panel.py's walk of
DrawStripGearContent, and the count RULE from DrawStripGearSectionCount's own body — so
a tree that gains the missing filter changes this output, and a tree that loses it
fails here before a terminal ever paints.
"""

import os
import re
import shutil
import subprocess
import sys
import importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))
# TH3_ROOT: run the doctor against another tree (same switch the mirrors honour).
ROOT = os.environ.get("TH3_ROOT") or os.path.dirname(HERE)
ICONS = os.path.join(ROOT, "Files", "Icons")

_s = importlib.util.spec_from_file_location("gearpanel", os.path.join(HERE, "sim-gear-panel.py"))
G = importlib.util.module_from_spec(_s)
_s.loader.exec_module(G)

# the source, with #includes followed in place and comment lines stripped: the same
# text the mirrors read, so a probe here and a render there cannot disagree about
# what the MQL says.
UNITS = G.mql_unit_lines(G.DRAWSTRIP)


def rel(path):
    return os.path.relpath(path, ROOT).replace("\\", "/")


def at(pattern, limit=12, units=None):
    """[(file, line, text), ...] for every source line matching `pattern`."""
    rx = re.compile(pattern)
    return [(rel(o), ln, t.strip()) for o, ln, t in (units or UNITS) if rx.search(t)][:limit]


# ════════════════════════════════════════════════════════════════════════════
# S0 — THE INSTRUMENTS. A broken probe reads as "no defect", so the loop checks
#      itself first: this is the stage whose failure made a whole session slow.
# ════════════════════════════════════════════════════════════════════════════

def probe_env():
    rows, bad = [], []
    node = shutil.which("node")
    rg = os.environ.get("CODEBUFF_RG_PATH") or shutil.which("rg")
    vendored = os.path.join(os.environ.get("LOCALAPPDATA", ""), "Programs", "ZCode",
                            "resources", "tools", "ripgrep", "rg.exe")
    if not rg and os.path.exists(vendored):
        rg = vendored
    def row(name, value, ok=True):
        rows.append(("  %-24s %s" % (name, value), "", ok))

    row("python", "%d.%d.%d" % sys.version_info[:3])
    row("node", node or "NOT FOUND: the JS gates cannot run", bool(node))
    row("ripgrep", rg or "NOT FOUND: every search becomes manual "
                         "(use `grep -rn <pat> <dir>`); MEASURED 2026-10-01: a whole "
                         "session's searches were hand-written because of this", bool(rg))
    for name in ("check-regressions.js", "check-resources.js", "object_lifecycle_check.js",
                 "check-level-continuity.js", "check-shot-freshness.js",
                 "check-gear-panel.py", "sim-gear-panel.py", "before-after.py"):
        ok = os.path.exists(os.path.join(HERE, name))
        row("tool " + name, "present" if ok else "MISSING", ok)
        if not ok:
            bad.append(name)
    shots = os.path.join(ROOT, "build-logs", "shot")
    n_png = len([f for f in os.listdir(shots) if f.endswith(".png")]) if os.path.isdir(shots) else 0
    row("terminal shots", "%d PNG(s) in build-logs/shot" % n_png, n_png > 0)
    row("mirror import", "sim-gear-panel.py loads, %d tab(s), kind %s"
        % (len(G.TABS), G.DEMO_KIND))
    row("count-rule probe", "DrawStripGearSectionCount %s"
        % ("read" if count_rule_filters_groups() is not None else "NOT READABLE"))
    return {"kind": "AGREE" if not bad else "DIVERGES", "rows": rows,
            "suspects": [(f, 0, "the loop's own instrument is missing") for f in bad]}


# ════════════════════════════════════════════════════════════════════════════
# S1 — THE CONSTANTS. A wrong literal makes every stage below it right about a
#      panel that does not exist, so this is always probe one.
# ════════════════════════════════════════════════════════════════════════════

LITERALS = [("DSTRIP_GEAR_W", "GEAR_W"), ("DSTRIP_GEAR_W2", "GEAR_W2"),
            ("DSTRIP_GEAR_PAD", "PAD"), ("DSTRIP_GEAR_HEAD_H", "HEAD_H"),
            ("DSTRIP_GEAR_ROW_H", "ROW_H"), ("DSTRIP_GEAR_FOOT_H", "FOOT_H"),
            ("DSTRIP_GEAR_AIR", "AIR"), ("DSTRIP_ROW_GAP", "ROW_GAP"),
            ("DSTRIP_GEAR_LBL_PT", "LBL_PT"), ("DSTRIP_SEC_CNT_W", "SEC_CNT_W"),
            ("DSTRIP_GRK_GROUP", "GRK_GROUP"), ("DSTRIP_GEAR_LVLBLK", "LVLBLK"),
            ("DSTRIP_GEAR_SWQ_N", "SWQ_N")]

PANELS = os.path.join(ROOT, "Biotak", "BiotakPanels.mqh")


def numeric_defines():
    """Every `DSTRIP_*` / `PNL_*` #define as a NUMBER, with aliasing resolved.

    DrawStrip_Head.mqh says `#define DSTRIP_GEAR_W PNL_WEL` and
    `#define DSTRIP_GEAR_W2 (2*PNL_WEL)`. A reader that only accepts digits compares
    5 of these 13 literals and calls the rest checked — which is what the gear gate's
    own `#define\\s+(DSTRIP_\\w+)\\s+(\\d+)` reader does for the eight aliased ones
    (`if key in d` skips them in silence). Resolving one level of names makes the
    alias a MEASUREMENT instead of a skip.
    """
    raw = {}
    text = [t for _o, _l, t in UNITS]
    # the alias chain ends in BiotakPanels.mqh -> CardMetrics.mqh, so the resolver reads
    # that unit COMPOSED (its own includes followed), exactly like the compiler.
    try:
        text += [t for _o, _l, t in G.mql_unit_lines(PANELS)]
    except OSError:
        pass
    for raw_line in text:
        line = re.sub(r"//.*$", "", raw_line)          # a trailing comment is not syntax
        m = re.match(r"\s*#define\s+((?:DSTRIP|PNL)_\w+)\s+(.+?)\s*$", line)
        if m:
            raw[m.group(1)] = m.group(2).strip()
    cache = {}

    def solve(name, depth=0):
        if name in cache:
            return cache[name]
        if depth > 4 or name not in raw:
            return None
        expr = re.sub(
            r"[A-Za-z_]\w*|\d+",
            lambda mm: mm.group(0) if mm.group(0).isdigit()
            else (str(solve(mm.group(0), depth + 1))
                  if solve(mm.group(0), depth + 1) is not None else mm.group(0)),
            raw[name])
        if not re.fullmatch(r"[0-9+\-*/() ]+", expr):
            return None
        try:
            cache[name] = int(eval(expr, {"__builtins__": {}}, {}))
        except Exception:
            return None
        return cache[name]

    out = {}
    for key in raw:
        v = solve(key)
        if v is not None:
            out[key] = v
    return out, raw


NUMDEF, RAWDEF = numeric_defines()


def probe_constants():
    rows, sus, n, skipped = [], [], 0, []
    for key, mine in LITERALS:
        if key not in NUMDEF:
            skipped.append(key)
            continue
        n += 1
        same = NUMDEF[key] == getattr(G, mine)
        if not same:
            site = at(r"#define\s+%s\b" % key, 1)
            sus.append((site[0][0] if site else "Biotak/DrawStrip_Head.mqh",
                        site[0][1] if site else 0,
                        "mql %s=%d, mirror %s=%d" % (key, NUMDEF[key], mine, getattr(G, mine))))
        rows.append(("  %-22s mql=%-4d mirror=%-4d %s"
                     % (key, NUMDEF[key], getattr(G, mine), "ok" if same else "DRIFT"), "", same))
    if skipped:
        rows.append(("  not a resolvable number, NOT CHECKED: %s" % ", ".join(skipped), "", False))
    alias = [k for k, _ in LITERALS if not RAWDEF.get(k, "0").isdigit()]
    return {"kind": "AGREE" if not sus else "DIVERGES", "rows": rows, "suspects": sus,
            "proof": "%d literal(s) compared (%d through their PNL_*/expression chain), "
                     "%d unchecked" % (n, len(alias), len(skipped))}


# ════════════════════════════════════════════════════════════════════════════
# S2 — THE LAYOUT. Where every row lands, in which column, on which pitch.
# ════════════════════════════════════════════════════════════════════════════

def probe_layout(tabs=None):
    rows, sus = [], []
    for t in range(len(G.TABS)):
        if tabs is not None and t not in tabs:
            continue
        L = G.layout(t)
        gh, gw, cn = L["h"], L["w"], L["card_n"]
        seats = [(b[4], b[2]) for b in L["blocks"]]
        bad = []
        if (gh - 104) % 42:
            bad.append("gh=%d is off (104+42n)" % gh)
        if gw == G.GEAR_W and not (1 <= cn <= 10):
            bad.append("narrow cardN=%d has no bake" % cn)
        if len(seats) != len(set(seats)):
            dup = [s for s in seats if seats.count(s) > 1]
            bad.append("two blocks share seat %s" % (sorted(set(dup))[:2],))
        if L.get("unmodelled"):
            bad.append("unmodelled: %s" % "; ".join(L["unmodelled"][:2]))
        rows.append(("  %-6s gh=%-4d w=%-4d rows=%-2d blocks=%-2d %s"
                     % (L["tab_name"], gh, gw, (gh - 104) // 42, len(L["blocks"]),
                        "ok" if not bad else " | ".join(bad)), "", not bad))
        if bad:
            sus.append(("tools/sim-gear-panel.py", 0, "%s: %s" % (L["tab_name"], " | ".join(bad))))
    return {"kind": "AGREE" if not sus else "DIVERGES", "rows": rows, "suspects": sus,
            "proof": "%d tab(s) walked from DrawStripGearContent" % len(G.TABS)}


def dump_tab(t):
    """The seat dump a human would otherwise build by hand: every block, its column,
    its y and what it is. This is the artefact the earlier hunt spent calls on."""
    L = G.layout(t)
    out = [("=== %s (w=%d h=%d, %d block(s))" % (L["tab_name"], L["w"], L["h"],
                                                 len(L["blocks"])), "", True)]
    for kind, name, y, ex, col in L["blocks"]:
        out.append(("  %-8s col%d y=%-4d %-24s %s"
                    % (kind, col, y, str(name)[:24], ex), "", True))
    return {"kind": "AGREE", "rows": out, "suspects": [],
            "proof": "sim-gear-panel.layout(%d)" % t}


# ════════════════════════════════════════════════════════════════════════════
# S3 — THE COUNT RULE. The band's `.cnt` pill: which rows does the rule mean?
#
# This is the probe that did not exist. Two facts, both read:
#   * the rows, from the mirror's own walk of the tab (the source's calls), and
#   * the RULE, from DrawStripGearSectionCount's body — specifically whether its row
#     loop excludes `DSTRIP_GRK_GROUP`. A group header is the accordion's NAV, not a
#     setting, and it rides the same row array in the same column.
# ════════════════════════════════════════════════════════════════════════════

def count_rule_filters_groups():
    """The rule's own flag, read through the MIRROR's owner — one table, no second.

    `sim-gear-panel.count_rule_excludes_nav()` parses
    `s_dsGRKind[r] != DSTRIP_GRK_GROUP` out of DrawStripGearSectionCount's own body.
    The doctor asks that function instead of re-reading the source, so this run and
    `check-gear-panel.py` (which asserts through the same one) can never disagree
    about what the rule says. None = the rule is not in the composed source at all.
    """
    if not hasattr(G, "count_rule_excludes_nav"):
        return None
    if not G._fn_body(G.DS, r"int\s+DrawStripGearSectionCount\s*\("):
        return None
    return G.count_rule_excludes_nav()


def band_counts(L, filters):
    """One tab's bands, through the mirror's own count (P-DRAW-121).

    `filters` is the rule's flag: False counts the nav rows the way the defect did,
    True is the rule with them excluded — the delta between the two IS the defect.
    """
    return G.band_counts(L, filters)


def probe_rule(tabs=None):
    filters = count_rule_filters_groups()
    site = at(r"s_dsGRCol\[r\] == col", 1) or [("Biotak/DrawStrip_GearB.mqh", 0, "")]
    if filters is None:
        return {"kind": "BLIND", "rows": [], "suspects": [],
                "proof": "DrawStripGearSectionCount is not in the composed source"}
    rows, sus = [], []
    for t in range(len(G.TABS)):
        if tabs is not None and t not in tabs:
            continue
        L = G.layout(t)
        for name, col, n, nav in band_counts(L, filters):
            # `nav` comes back whether or not it was counted, so a divergent tree can
            # NAME the rows that leaked: the number alone is not a fix.
            leaks = (not filters) and bool(nav)
            flag = ""
            if nav and not filters:
                flag = "  <- counts %d nav row(s): %s" % (len(nav), ", ".join(nav))
                sus.append((site[0][0], site[0][1],
                            "%s/%s pill reads %d, owns %d setting(s) + %d nav row(s)"
                            % (L["tab_name"], name, n, n - len(nav), len(nav))))
            rows.append(("  %-6s %-12s col%d cnt=%-2d%s" % (L["tab_name"], name, col, n, flag),
                         "", not leaks))
    return {"kind": "AGREE" if not sus else "DIVERGES", "rows": rows, "suspects": sus,
            "proof": "row loop %s exclude DSTRIP_GRK_GROUP (kind %d); bands read "
                     "through sim-gear-panel.band_counts()"
                     % ("DOES" if filters else "does NOT", G.GRK_GROUP)}


def coverage(symbol):
    """Which gates assert this rule today? A rule no gate reads is a rule that can
    regress in silence — the honest form of "why was this slow"."""
    hits = []
    for name in sorted(os.listdir(HERE)):
        if not name.endswith((".js", ".py")) or name == "debug-doctor.py":
            continue
        try:
            with open(os.path.join(HERE, name), encoding="utf-8", errors="replace") as fh:
                if symbol in fh.read():
                    hits.append(name)
        except OSError:
            pass
    return hits


# ════════════════════════════════════════════════════════════════════════════
# S4 — THE PAINT. Every block must push its own ops: a label, a digest, a face.
#      "The texts are incomplete" is exactly this probe's question.
# ════════════════════════════════════════════════════════════════════════════

def probe_paint(tabs=None):
    rows, sus, holes = [], [], []
    for t in range(len(G.TABS)):
        if tabs is not None and t not in tabs:
            continue
        L = G.layout(t)
        notes = []
        c = G.paint(L, notes, t)
        gw, gh = L["w"], L["h"]
        px = G.PAD
        # P-DRAW-109's own trap: a column's cell is `DSTRIP_GEAR_W - 2*PAD` (280) on
        # EVERY tab, never the box (`gw - 2*PAD` = 592 on a wide one). Measured here
        # the day this file was written: with the box, the digest's right-aligned seat
        # of a 624 tab computed 683 and the probe called three PAINTED digests missing.
        cw = G.GEAR_W - 2 * G.PAD
        texts = [o for o in c.ops if o[0] == "text"]
        miss_lbl, miss_dg, off = [], [], []
        for kind, name, y, ex, col in L["blocks"]:
            pxr = px + col * G.GEAR_COL
            if kind in ("row", "section", "caption") and str(name).strip():
                hit = [o for o in texts
                       if pxr - 4 <= o[2] <= pxr + 90 and y + 8 <= o[3] <= y + 30]
                if not hit:
                    miss_lbl.append("%s@col%d y=%d" % (str(name)[:18], col, y))
                if kind == "row" and ex and len(ex) >= 1 and str(ex[0]) == str(G.GRK_GROUP):
                    dg = [o for o in texts if o[2] > pxr + cw * 0.6 and y + 8 <= o[3] <= y + 30]
                    if not dg:
                        miss_dg.append("%s@col%d y=%d" % (str(name)[:18], col, y))
        for o in c.ops:
            if o[0] == "img" and (o[2] < -14 or o[3] < -14 or o[2] + (o[4] or 0) > gw + 14
                                  or o[3] + (o[5] or 0) > gh + 14):
                off.append("%s at %s,%s" % (o[1], o[2], o[3]))
        holes += [o[1] for o in c.ops if o[0] == "img" and o[1] is None]
        bad = []
        if miss_lbl:
            bad.append("%d label(s) not painted: %s" % (len(miss_lbl), "; ".join(miss_lbl[:3])))
        if miss_dg:
            bad.append("%d group digest(s) not painted: %s" % (len(miss_dg), "; ".join(miss_dg[:3])))
        if off:
            bad.append("%d face(s) off the plate: %s" % (len(off), "; ".join(off[:2])))
        rows.append(("  %-6s ops=%-4d texts=%-4d %s"
                     % (L["tab_name"], len(c.ops), len(texts), "ok" if not bad else " | ".join(bad)),
                     "", not bad))
        if bad:
            sus.append(("tools/sim-gear-panel.py", 0, "%s: %s" % (L["tab_name"], " | ".join(bad))))
    return {"kind": "AGREE" if not sus else "DIVERGES", "rows": rows, "suspects": sus,
            "proof": "every tab painted through sim-gear-panel.paint()"}


# ════════════════════════════════════════════════════════════════════════════
# S5 — THE BIRTH. An object that keeps an older layer reads correct in the census
#      and paints under the plate. The rule is "a painted layer is re-asserted every
#      paint", and it has ONE OWNER: the lifecycle gate derives the set from every
#      painter in Biotak/** and fails on a birth-only layer write (P-DRAW-122), so
#      this stage READS it instead of re-implementing it — the same way S6 reads the
#      shot gate. One rule, one verdict, and the gate's failing lines are already
#      `file:line fn …`, which is exactly what a narrowing report needs.
# ════════════════════════════════════════════════════════════════════════════

def probe_layers():
    script = os.path.join(HERE, "object_lifecycle_check.js")
    if not shutil.which("node") or not os.path.exists(script):
        return {"kind": "BLIND",
                "rows": [("  node or object_lifecycle_check.js unavailable", "", False)],
                "suspects": [], "proof": "no layer stage in this environment"}
    try:
        p = subprocess.run(["node", script], cwd=ROOT, capture_output=True, text=True,
                           timeout=180)
    except (OSError, subprocess.TimeoutExpired) as e:
        return {"kind": "BLIND", "rows": [("  %s" % e, "", False)], "suspects": [],
                "proof": "the layer gate did not run"}
    out = p.stdout or ""
    line = ""
    for ln in out.splitlines():
        if ln.strip().startswith("layers:"):
            line = ln.strip()
    sus = []
    for ln in out.splitlines():
        m = re.match(r"\s*\[FAIL\]\s*(\S+?):(\d+)\s+(\w+)\s+writes OBJPROP_ZORDER/BACK",
                     ln)
        if m:
            sus.append((m.group(1), int(m.group(2)),
                        "%s writes the layer only at birth: a surviving object keeps "
                        "its old rung and paints under the plate (P-DRAW-122)"
                        % m.group(3)))
    if not line:
        tail = (out.strip().splitlines() or ["(no output)"])[-1][:110]
        return {"kind": "BLIND", "rows": [("  %s" % tail, "", False)], "suspects": sus,
                "proof": "object_lifecycle_check.js reported no layer verdict"}
    ok = "0 write the layer only at birth" in line
    return {"kind": "AGREE" if ok else "DIVERGES", "rows": [("  %s" % line, "", ok)],
            "suspects": sus, "proof": "object_lifecycle_check.js: %s" % line}


# ════════════════════════════════════════════════════════════════════════════
# S6 — THE PIXELS. The only stage that may be called "what the screen shows", and
#      the one stage a mirror can never substitute for.
# ════════════════════════════════════════════════════════════════════════════

def probe_pixels():
    script = os.path.join(HERE, "check-shot-freshness.js")
    if not shutil.which("node") or not os.path.exists(script):
        return {"kind": "BLIND", "rows": [("  node or check-shot-freshness.js unavailable", "", False)],
                "suspects": [], "proof": "no terminal stage in this environment"}
    try:
        p = subprocess.run(["node", script], cwd=ROOT, capture_output=True, text=True,
                           timeout=120)
    except (OSError, subprocess.TimeoutExpired) as e:
        return {"kind": "BLIND", "rows": [("  %s" % e, "", False)], "suspects": [],
                "proof": "the terminal stage did not run"}
    line = ""
    for ln in p.stdout.splitlines():
        if "fresh" in ln and "stale" in ln:
            line = ln.strip()
    m = re.search(r"fresh\s+(\d+)\s+.*stale\s+(\d+)\s+.*missing\s+(\d+)", line)
    if not m:
        return {"kind": "BLIND", "rows": [("  %s" % (line or p.stdout.strip()[-120:]), "", False)],
                "suspects": [], "proof": "unreadable verdict"}
    fresh, stale, missing = (int(x) for x in m.groups())
    kind = "AGREE" if fresh and not stale and not missing else "NOT CURRENT"
    return {"kind": kind,
            "rows": [("  %s" % line, "", kind == "AGREE")],
            "suspects": [], "proof": "check-shot-freshness.js: %d fresh / %d stale / %d missing"
                                     % (fresh, stale, missing)}


# ════════════════════════════════════════════════════════════════════════════
# THE ROUTING TABLE. A symptom names the stages worth running and the question the
# symptom is really asking; the doctor then deletes the stages that agree.
# ════════════════════════════════════════════════════════════════════════════

SYMPTOMS = {
    "count": {
        "words": ["count", "cnt", "pill", "badge", "عدد", "شمارش", "تعداد"],
        "ask": "the band's `.cnt` pill - which rows does the rule count?",
        "stages": ["constants", "layout", "rule", "paint"],
        # a shot shows a wrong NUMBER but cannot NAME it: the rule itself needs a probe
        "blind": [("pixels", "a pill's NUMBER is ink a shot shows but cannot name")],
    },
    "missing": {
        "words": ["missing", "incomplete", "text", "label", "ناقص", "متن", "گم", "نیست"],
        "ask": "rows/blocks whose own ops never reached the screen",
        "stages": ["constants", "layout", "paint", "layers", "pixels"],
        "blind": [("pixels", "a missing label is only PROVEN by the terminal's PNG; "
                             "the mirror says the op exists, and it did")],
    },
    "stroke": {
        "words": ["stroke", "tab", "accordion", "تب", "استروک"],
        "ask": "the Stroke tab's own seats, block by block",
        "stages": ["layout", "rule", "paint", "layers"],
        "dump": 1,
        "blind": [],
    },
}

PROBES = {
    "constants": lambda ctx: probe_constants(),
    "layout": lambda ctx: probe_layout(),
    "rule": lambda ctx: probe_rule(),
    "paint": lambda ctx: probe_paint(),
    "layers": lambda ctx: probe_layers(),
    "pixels": lambda ctx: probe_pixels(),
}

STAGE_ORDER = ["constants", "layout", "rule", "paint", "layers", "pixels"]


def route(text):
    low = text.lower()
    for key, spec in SYMPTOMS.items():
        for w in spec["words"]:
            if w in low:
                return key
    return None


def print_probe(label, res):
    mark = {"AGREE": "AGREE  ", "DIVERGES": "DIVERGES", "BLIND": "BLIND  ",
            "NOT CURRENT": "STALE  "}[res["kind"]]
    print("  %-14s %s  %s" % (label, mark, res.get("proof", "")))
    for row, _d, ok in res.get("rows", []):
        if row:
            print("      %s %s" % (" " if ok else "!", row.strip()))
    for f, ln, note in res.get("suspects", []):
        print("      ! %s:%d  %s" % (f, ln, note))


def run_all(fast=False):
    print("NARROWING RUN - every stage, every tab")
    print("")
    env = probe_env()
    print_probe("S0 env", env)
    for name in STAGE_ORDER:
        if fast and name == "pixels":
            print("  %-14s SKIPPED  --fast" % ("S" + str(STAGE_ORDER.index(name) + 1) + " " + name))
            continue
        print_probe("S%d %s" % (STAGE_ORDER.index(name) + 1, name), PROBES[name](None))
    return 1 if env["kind"] != "AGREE" else 0


def run_symptom(key, fast=False):
    spec = SYMPTOMS[key]
    print("NARROWING RUN - symptom: %s" % key)
    print("  question: %s" % spec["ask"])
    print("")
    gaps, blind, siblings = [], [], []
    for name in spec["stages"]:
        if fast and name == "pixels":
            continue
        res = PROBES[name](None)
        print_probe("S%d %s" % (STAGE_ORDER.index(name) + 1, name), res)
        if res["kind"] == "BLIND":
            blind.append(name)
        elif res["kind"] in ("DIVERGES", "NOT CURRENT"):
            gaps.append((name, res))
        if name != "layers":
            siblings += res.get("suspects", [])
    if spec.get("dump") is not None:
        print("")
        print_probe("S2 dump", dump_tab(spec["dump"]))
    if "layers" not in spec["stages"]:
        lay = probe_layers()
        if lay["suspects"]:
            print("")
            print_probe("S5 layers", lay)      # same class, other sites: always shown
    print("")
    filters = count_rule_filters_groups()
    if key == "count":
        hits = coverage("DrawStripGearSectionCount")
        print("  GATE COVERAGE: %s" % (", ".join(hits) if hits
                                       else "NO gate reads DrawStripGearSectionCount; "
                                            "S3 above is its first probe"))
        site = at(r"s_dsGRCol\[r\] == col", 1)
        if site:
            print("  RULE SITE: %s:%d  `%s`" % (site[0][0], site[0][1], site[0][2][:70]))
        print("  RULE FILTER: %s DSTRIP_GRK_GROUP" % ("EXCLUDES" if filters else "does NOT exclude"))
    if gaps:
        name, res = gaps[0]
        print("")
        print("  CORE GAP: stage S%d %s" % (STAGE_ORDER.index(name) + 1, name))
        for f, ln, note in res["suspects"][:4]:
            print("      %s:%d  %s" % (f, ln, note))
    else:
        print("")
        print("  CORE GAP: no stage diverged - the fault is at a stage this plan did not run,")
        print("            or in the one place no probe can reach: the chart's own state.")
    if blind:
        print("  BLIND: %s" % ", ".join(blind))
    for name, why in spec["blind"]:
        print("  BLIND BY DESIGN: %s - %s" % (name, why))
    for name, res in gaps[1:]:
        print("")
        print("  NEXT DIVERGENT STAGE: S%d %s" % (STAGE_ORDER.index(name) + 1, name))
        for f, ln, note in res["suspects"][:4]:
            print("      %s:%d  %s" % (f, ln, note))
    return 0


def generic_hits(keyword, limit=12):
    """Whole-to-part fallback: every source line that names `keyword`, newest first.

    This is the universal stage S1+S2 for any surface: no per-tab model, just the
    caller/writer set the Touch rule demands (AGENTS.md). Reads Biotak/** + both
    entries, case-insensitive, skips this tool's own directory.
    """
    rx = re.compile(re.escape(keyword), re.IGNORECASE)
    wrx = re.compile(
        r"ObjectCreate|ObjectDelete|ObjectsDeleteAll|ClearAllLevels|"
        r"SetTriggerLevelsVisible|SetTHLabelsVisibility|g_adoptPreviousTopology|"
        r"g_forceClearOnNextDraw|void\s+\w*%s|int\s+\w*%s|bool\s+\w*%s" % (
            re.escape(keyword), re.escape(keyword), re.escape(keyword)), re.IGNORECASE)
    hits, writers = [], []
    files = []
    if os.path.isdir(os.path.join(ROOT, "Biotak")):
        for dp, _dn, fn in os.walk(os.path.join(ROOT, "Biotak")):
            for f in sorted(fn):
                if f.endswith((".mqh", ".mq4")):
                    files.append(os.path.join(dp, f))
    for f in sorted(files):
        try:
            with open(f, encoding="utf-8", errors="replace") as fh:
                for ln, line in enumerate(fh, 1):
                    s = line.strip()
                    if not rx.search(line):
                        continue
                    if s.startswith("//|") or s.startswith("//---") or s.startswith("//==="):
                        continue    # file-banner noise, never a writer
                    item = (rel(f), ln, s[:100])
                    (writers if wrx.search(line) else hits).append(item)
                    if len(writers) + len(hits) >= 300:
                        break
        except OSError:
            pass
    return (writers + hits)[:limit]


def run_generic(sym, fast=False):
    """One symptom, no gear route: narrow whole -> part in one run.

    U0 env (the loop's own instruments) -> U1 gate coverage (which gate reads this
    word today; none = the rule is ungated) -> U2 caller/writer set (the Touch-rule
    dependents; two writers = the second one is the bug) -> U3 layers (birth-only
    rung, P-DRAW-122's class) -> U4 pixels (fresh/stale/missing, never a mirror).
    Prints CORE GAP as file:line, same contract as run_symptom.
    """
    print("NARROWING RUN - generic symptom: %s" % sym)
    print("  question: which STAGE owns this word, and which file:line diverges?")
    print("")
    env = probe_env()
    print_probe("S0 env", env)
    hits = coverage(sym)
    print("  GATE COVERAGE: %s" % (", ".join(hits) if hits
                                   else "NO gate reads %r; S3-equivalent is missing "
                                        "(that gap IS the finding)" % sym))
    rows = generic_hits(sym)
    writers = [h for h in rows if re.search(
        r"\b(ObjectCreate|ObjectDelete|ObjectsDeleteAll|ClearAllLevels|"
        r"SetTriggerLevelsVisible|SetTHLabelsVisibility|g_adoptPreviousTopology|"
        r"g_forceClearOnNextDraw|void\s+\w*%s\w*|int\s+\w*%s\w*)" % (
            re.escape(sym), re.escape(sym)), h[2], re.IGNORECASE)]
    print("  U2 callers/writers: %d hit(s), %d writer-like" % (len(rows), len(writers)))
    for f, ln, t in rows[:12]:
        mark = "W" if (f, ln, t) in writers else " "
        print("     %s %s:%d  %s" % (mark, f, ln, t[:90]))
    if len(writers) > 1:
        print("      ! two writers name %r: the second one is the suspect (Touch rule 6)" % sym)
    print("")
    lay = probe_layers()
    print_probe("U3 layers", lay)
    if not fast:
        print_probe("U4 pixels", probe_pixels())
    else:
        print("  U4 pixels    SKIPPED  --fast")
    print("")
    if writers:
        f, ln, t = writers[0]
        print("  CORE GAP: start at %s:%d  %s" % (f, ln, t[:70]))
    elif rows:
        f, ln, t = rows[0]
        print("  CORE GAP: start at %s:%d  %s" % (f, ln, t[:70]))
    else:
        print("  CORE GAP: no source names %r - the fault is chart state or a renamed "
               "object (orphan sweep, contract.md:41)" % sym)
    if not hits:
        print("  BLIND: no gate asserts this word - add the probe before the fix "
              "(docs/debugging.md:75)")
    return 0 if env["kind"] == "AGREE" else 1


def main():
    argv = sys.argv[1:]
    fast = "--fast" in argv
    if "--list" in argv:
        print("SYMPTOM -> STAGES  (the routing table)")
        for key, spec in SYMPTOMS.items():
            words = [w for w in spec["words"] if w.isascii()]   # the console is not UTF-8
            print("  %-9s %-28s %s" % (key, "/".join(spec["stages"]), ", ".join(words)))
        print("  *         env/coverage/writers/layers/pixels  any other word (generic fallback)")
        return 0
    if "--env" in argv:
        env = probe_env()
        print("INSTRUMENTS - the loop's own probes (a broken probe reads as no defect)")
        for r, _d, ok in env["rows"]:
            print("%s%s" % ("  " if ok else "!!", r))
        return 0 if env["kind"] == "AGREE" else 1
    sym = None
    for i, a in enumerate(argv):
        if a == "--symptom" and i + 1 < len(argv):
            sym = argv[i + 1]
        elif a.startswith("--symptom="):
            sym = a.split("=", 1)[1]
        elif not a.startswith("-"):
            sym = sym or a
    if sym:
        key = route(sym)
        if key is None:
            return run_generic(sym, fast)
        return run_symptom(key, fast)
    return run_all(fast)


if __name__ == "__main__":
    sys.exit(main())
