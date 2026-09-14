#!/usr/bin/env python3
"""Render the 13 settings cards the way MetaTrader will draw them — with MT4
completely out of the loop.

WHY THIS EXISTS
---------------
MT4 cannot blur, gradient or round a corner at runtime, so the redesign bakes
every one of those effects into 32-bit BMPs that MT4 merely blits. That makes
the panel's appearance a pure function of two things:

  1. the baked BMP bytes in `Files/Icons/`, and
  2. the pixel positions in `Biotak/BiotakPanels.mqh`.

Both are read here straight from the repo. This script does NOT re-implement
the design and it does NOT re-draw the art: it parses the real MQL constants
and row tables, then composites the real bitmaps at those coordinates. The
result is the panel as the terminal will show it, without launching the
terminal.

CAVEAT — text. MT4 renders OBJ_LABEL with its own font stack, so captions here
are the browser's Arial at the same point size (pt * 4/3 px) and the same
anchor. Chrome (every bitmap) is byte-exact; text is a close approximation.
Point sizes and anchors come from the MQL, so the *layout* is exact.

Usage: python tools/panel-mt4-sim.py [out.html]
"""
import base64
import os
import re
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONS = os.path.join(ROOT, "Files", "Icons")
SRC = os.path.join(ROOT, "Biotak", "BiotakPanels.mqh")

# ─────────────────────────────────────────────────────────────────────────────
# BMP / PNG plumbing (stdlib only — the managed Python has no Pillow)
# ─────────────────────────────────────────────────────────────────────────────


def read_bmp(path):
    """32bpp BGRA BMP -> (w, h, RGBA bytes, top-down)."""
    d = open(path, "rb").read()
    off = struct.unpack_from("<I", d, 10)[0]
    w, h = struct.unpack_from("<ii", d, 18)
    bpp = struct.unpack_from("<H", d, 28)[0]
    if bpp != 32:
        raise ValueError("%s: expected 32bpp, got %d" % (path, bpp))
    top_down = h < 0
    h = abs(h)
    out = bytearray(w * h * 4)
    for y in range(h):
        srow = off + (y if top_down else (h - 1 - y)) * w * 4
        drow = y * w * 4
        for x in range(w):
            s = srow + x * 4
            out[drow + x * 4] = d[s + 2]      # R
            out[drow + x * 4 + 1] = d[s + 1]  # G
            out[drow + x * 4 + 2] = d[s]      # B
            out[drow + x * 4 + 3] = d[s + 3]  # A
    return w, h, bytes(out)


def png(w, h, rgba):
    raw = b"".join(b"\x00" + rgba[y * w * 4:(y + 1) * w * 4] for y in range(h))

    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


_CACHE = {}


def uri(name):
    """`Files/Icons/<name>` -> (data-URI, w, h). Missing files yield a stub so
    a typo shows up as a visible hole instead of a silent skip."""
    if name in _CACHE:
        return _CACHE[name]
    p = os.path.join(ICONS, name)
    if not os.path.exists(p):
        _CACHE[name] = (None, 0, 0)
        return _CACHE[name]
    w, h, rgba = read_bmp(p)
    _CACHE[name] = ("data:image/png;base64," + base64.b64encode(png(w, h, rgba)).decode(), w, h)
    return _CACHE[name]


# ─────────────────────────────────────────────────────────────────────────────
# Parse the MQL — geometry, palette, row tables
# ─────────────────────────────────────────────────────────────────────────────

# The sources are UTF-8 (the '·' in PnlHeaderSub is 0xC2 0xB7) — read them as
# such or the subtitle split silently finds one segment instead of the real
# dots-and-captions run.
SRC_TEXT = open(SRC, encoding="utf-8", errors="replace").read()


def strip_line_comments(text):
    """Drop `//` comments that are not inside a string literal — the geometry
    defines all carry trailing prose (`42  // TV-dense rows`)."""
    out = []
    for line in text.split("\n"):
        q, cut = False, -1
        i = 0
        while i < len(line) - 1:
            ch = line[i]
            if ch == '"' and (i == 0 or line[i - 1] != "\\"):
                q = not q
            elif not q and ch == "/" and line[i + 1] == "/":
                cut = i
                break
            i += 1
        out.append(line[:cut] if cut >= 0 else line)
    return "\n".join(out)


def parse_defines(text):
    """Every `#define NAME <expr>` that is a plain integer expression.
    Colour defines (`C'r,g,b'`) are skipped — this script only needs geometry."""
    syms = {}
    for m in re.finditer(r"^#define\s+(\w+)\s+(\S.*)$", strip_line_comments(text), re.M):
        name, expr = m.group(1), m.group(2).strip()
        if "C'" in expr or '"' in expr:
            continue
        syms[name] = expr
    # Resolve iteratively — defines reference earlier defines.
    out = {}
    for _ in range(8):
        for name, expr in syms.items():
            if name in out:
                continue
            try:
                out[name] = int(eval(expr, {"__builtins__": {}}, dict(out)))  # noqa: S307
            except Exception:                                              # noqa: BLE001
                pass
    return out


D = parse_defines(SRC_TEXT)


def parse_item_map(fn_name, text=SRC_TEXT):
    """`if(item==N) return "X";` inside one function -> {N: "X"}.

    A branch may hold MORE than one return — item 12's caption follows the Base
    Box tab (`if(g_BkTab==1) … return "TEXT TAB …";`) and ends with the tab-0
    default. The last return in the branch is that default, which is the live
    one (`g_BkTab` starts at 0), so the plain scan below would have given the
    Base Box card NO subtitle in the proof at all. Take the last return per
    branch; for the single-return branches that is the same value as before."""
    m = re.search(r"\n\w[\w ]*\s+%s\s*\([^)]*\)\s*\{" % re.escape(fn_name), text)
    if not m:
        return {}
    # drop the trailing `// …` comments: retired branches are kept commented out
    # (`// TH3TOOL-OFF: if(item==5) return "TH3 Tool";`) and a commented return is
    # not a value — without this, item 3's title parsed as "TH3 Tool".
    body = re.sub(r"//[^\n]*", "", text[m.end():text.index("\n}", m.end())])
    out = {}
    for bm in re.finditer(r"if\(item==(\d+)\)(.*?)(?=\n\s*if\(item==|\Z)", body, re.S):
        blk = bm.group(2)
        # the function's trailing `return "";` sentinel is not a value
        vals = [v for v in re.findall(r'return\s*"([^"]*)"', blk) if v != ""]
        if not vals:
            continue
        # a branch with its own nested condition is tab-dependent: its LAST
        # return is the default tab. A plain branch's FIRST return is the value
        # (the trailing `return "";` of the function is not part of it).
        out[int(bm.group(1))] = vals[-1] if re.search(r"\bif\s*\(", blk) else vals[0]
    return out


def parse_bool_map(fn_name):
    """`bool F(item) { return (item==0 || item==1); }` -> {0,1}."""
    m = re.search(r"\nbool\s+%s\s*\([^)]*\)\s*\{" % re.escape(fn_name), SRC_TEXT)
    body = SRC_TEXT[m.end():SRC_TEXT.index("\n}", m.end())]
    nums = set(int(n) for n in re.findall(r"item==(\d+)", body))
    return nums


KIND = {"PNL_K_SEC": 7, "PNL_K_SW": 1, "PNL_K_SL": 0, "PNL_K_SEG": 2,
        "PNL_K_COL": 4, "PNL_K_NAV": 5, "PNL_K_TXT": 6, "PNL_K_CSET": 8,
        "PNL_K_DUAL": 9, "PNL_K_LEGACY": -1}


def split_args(s):
    """Split an MQL argument list on commas that are outside string literals."""
    out, cur, q = [], "", False
    for ch in s:
        if ch == '"':
            q = not q
            cur += ch
        elif ch == "," and not q:
            out.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def blank_blocks(body, pattern):
    """Replace `pattern { ... }` (brace-balanced) with spaces.

    Items 9 and 12 build their spec inside a mode/tab if-else chain, so a flat
    scan collects every branch's rows at once. Blanking the branches this
    script does not render leaves only the rows that actually appear: for the
    Step card the TH mode (which adds no section rows) and for Base Box the
    `else` STYLE tab."""
    out = body
    while True:
        m = re.search(pattern, out)
        if not m:
            return out
        ob = out.index("{", m.end())
        depth, i = 0, ob
        while i < len(out):
            if out[i] == "{":
                depth += 1
            elif out[i] == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        out = out[:m.start()] + " " * (i + 1 - m.start()) + out[i + 1:]


def parse_spec_build():
    """PnlSpecBuild -> {item: [ {kind,s0,n,ico,key,sec,cnt,ext}, ... ]}."""
    body = SRC_TEXT[SRC_TEXT.index("void PnlSpecBuild("):SRC_TEXT.index("\n}\n", SRC_TEXT.index("void PnlSpecBuild("))]
    # Drop the branches this script does not render (see blank_blocks).
    for pat in (r"if\(mode == 2\)", r"else if\(mode == 1\)", r"else if\(mode == 3\)",
                r"if\(g_BkTab == 1\)", r"else if\(g_BkTab == 2\)"):
        body = blank_blocks(body, pat)
    # The Step card's spec indexes rows as `base+K` (base = 1) and the MAX
    # LEVELS row as `maxRow` (1 + the open mode's section size). For the TH
    # mode this script renders, there are no section rows, so both are 1.
    scope = {"base": 1, "maxRow": 1, "__builtins__": {}}

    def num(tok):
        return int(eval(tok, scope))  # noqa: S307

    specs = {}
    for call in re.finditer(r"PnlSpecAdd\(([^;]*?)\);", body):
        a = split_args(call.group(1))
        item = int(a[0])
        kind = KIND.get(a[1], -1)
        row = {"kind": kind,
               "s0": num(a[2]), "n": num(a[3]),
               "ico": a[4].strip('"') if len(a) > 4 else "",
               "key": a[5].strip('"') if len(a) > 5 else "",
               "sec": a[6].strip('"') if len(a) > 6 else "",
               "cnt": num(a[7]) if len(a) > 7 else 0,
               "ext": a[8].strip('"') if len(a) > 8 else ""}
        specs.setdefault(item, []).append(row)
    return specs


def parse_set_def():
    """PnlSetDef -> {(item, row): {kind,label,opts,unit,minV,maxV}}."""
    start = SRC_TEXT.index("void PnlSetDef(")
    body = SRC_TEXT[start:SRC_TEXT.index("\n}\n", start)]
    defs = {}
    # Each `if(item==N)` / `else if(item==N)` opens a block; scan to the next one.
    blocks = list(re.finditer(r"(?:else\s+)?if\(item==(\d+)\)", body))
    for bi, bm in enumerate(blocks):
        item = int(bm.group(1))
        end = blocks[bi + 1].start() if bi + 1 < len(blocks) else len(body)
        blk = body[bm.end():end]
        # Rows: `if(row==K) { ... }` / `else if(row==K) { ... }` / trailing `else { ... }`
        rows = list(re.finditer(r"(?:else\s+)?if\(row==([\w()]+)\)\s*\{", blk))
        if not rows:
            continue
        for ri, rm in enumerate(rows):
            rkey = rm.group(1)
            rend = blk.index("}", rm.end())
            seg = blk[rm.end():rend]
            try:
                rn = int(rkey)
            except ValueError:
                # `row==PnlStepMaxLevelsRow()` = 1 + the open mode's section
                # size. TH (the mode rendered here) has no section rows -> 1.
                rn = 1
            d = {"kind": 0, "label": "", "opts": "", "unit": "", "minV": 0, "maxV": 100}
            for f in ("kind", "minV", "maxV"):
                fm = re.search(r"\b%s\s*=\s*([\w.]+)" % f, seg)
                if fm:
                    d[f] = int(eval(fm.group(1), {"ILS_COUNT": 5, "__builtins__": {}}))  # noqa: S307
            for f in ("label", "opts", "unit"):
                fm = re.search(r'\b%s\s*=\s*"([^"]*)"' % f, seg)
                if fm:
                    d[f] = fm.group(1)
            defs[(item, rn)] = d
        # The final `else { ... }` is the fallthrough row (e.g. item 1 row 10 =
        # LINES). It is a bare `else` (never `else if(row==..)`), so it does not
        # appear in `rows` and has to be picked up separately — the row number
        # is the count of `if(row==N)` branches that preceded it.
        for em in re.finditer(r"else\s*\{([^{}]*)\}", blk):
            seg = em.group(1)
            d = {"kind": 0, "label": "", "opts": "", "unit": "", "minV": 0, "maxV": 100}
            for f in ("kind", "minV", "maxV"):
                fm = re.search(r"\b%s\s*=\s*([\w.]+)" % f, seg)
                if fm:
                    d[f] = int(eval(fm.group(1), {"ILS_COUNT": 5, "__builtins__": {}}))  # noqa: S307
            for f in ("label", "opts", "unit"):
                fm = re.search(r'\b%s\s*=\s*"([^"]*)"' % f, seg)
                if fm:
                    d[f] = fm.group(1)
            if d["label"] and (item, len(rows)) not in defs:
                defs[(item, len(rows))] = d
    # BkSecRowDef — the Base Box Style tab's labels (sec index -> def)
    s2 = SRC_TEXT.index("void BkSecRowDef(")
    bk = SRC_TEXT[s2:SRC_TEXT.index("\n}\n", s2)]
    style = bk[bk.index("else   // STYLE"):] if "else   // STYLE" in bk else bk
    n_sec = 0
    for sm in re.finditer(r"(?:if|else if)\(sec==(\d+)\)\s*\{([^}]*)\}", style):
        seg = sm.group(2)
        d = {"kind": 0, "label": "", "opts": "", "unit": "", "minV": 0, "maxV": 100}
        for f in ("kind", "minV", "maxV"):
            fm = re.search(r"\b%s\s*=\s*([\w.]+)" % f, seg)
            if fm:
                d[f] = int(eval(fm.group(1), {"ILS_COUNT": 5, "__builtins__": {}}))  # noqa: S307
        for f in ("label", "opts", "unit"):
            fm = re.search(r'\b%s\s*=\s*"([^"]*)"' % f, seg)
            if fm:
                d[f] = fm.group(1)
        defs[(12, 1 + int(sm.group(1)))] = d
        n_sec = max(n_sec, int(sm.group(1)) + 1)
    # the trailing bare `else` is the last section (sec 5 = FILL TR)
    em = re.search(r"else\s*\{([^{}]*)\}", style)
    if em:
        seg = em.group(1)
        d = {"kind": 0, "label": "", "opts": "", "unit": "", "minV": 0, "maxV": 100}
        for f in ("kind", "minV", "maxV"):
            fm = re.search(r"\b%s\s*=\s*([\w.]+)" % f, seg)
            if fm:
                d[f] = int(eval(fm.group(1), {"ILS_COUNT": 5, "__builtins__": {}}))  # noqa: S307
        for f in ("label", "opts", "unit"):
            fm = re.search(r'\b%s\s*=\s*"([^"]*)"' % f, seg)
            if fm:
                d[f] = fm.group(1)
        if d["label"]:
            defs[(12, 1 + n_sec)] = d
    return defs


ACCENT_NAME = {0: "gold", 1: "jade", 2: "cyan", 3: "violet", 4: "ember", 5: "rose"}


def parse_card_accent():
    """PnlCardAccent(item) -> {item: accent index} — PARSED, never transcribed.

    It used to be a hardcoded table (`{0:2, 6:1, 7:1, 8:3, 9:3, 3:4, 10:4, 11:4}`)
    from before R-GOLDALL. When the MQL retired the five per-card families the
    table did not move with it, so the proof asked for `_ember`/`_jade`/...
    bitmaps that ICON-DIET had (correctly) deleted and the cards rendered as
    red "missing" hatching. The indicator itself was right the whole time —
    only the proof lied. Parse the function's own returns instead.
    """
    body = SRC_TEXT[SRC_TEXT.index("int PnlCardAccent("):]
    body = body[:body.index("\n}\n")]
    body = strip_line_comments(body)
    idx = {}
    for nm, n in re.findall(r"#define\s+PNL_A_(\w+)\s+(\d+)", SRC_TEXT):
        idx["PNL_A_" + nm] = int(n)

    def val(tok):
        if tok in idx:
            return idx[tok]
        return int(tok) if tok.isdigit() else None

    # branch form: if(item==N) return PNL_A_X;
    for m2 in re.finditer(r"if\(\s*item\s*==\s*(\d+)\s*\)\s*return\s+([\w]+)\s*;", body):
        v = val(m2.group(2))
        if v is not None:
            idx[int(m2.group(1))] = v
    # flat form: a single unconditional `return PNL_A_X;` covers every item
    flat = re.search(r"return\s+(PNL_A_\w+)\s*;", body)
    if flat:
        v = val(flat.group(1))
        if v is not None:
            out = {i: v for i in range(14)}
            return out
    return {i: idx.get("PNL_A_GOLD", 0) for i in range(14)}


CARD_ACCENT = parse_card_accent()
ACCENT_TITLE = parse_item_map("PnlTitleText")
ACCENT_SUB = parse_item_map("PnlSubtitleText")
ACCENT_HSUB = parse_item_map("PnlHeaderSub")
ACCENT_KEY = parse_item_map("PnlCardKey")
ACCENT_MARK = parse_item_map("PnlMarkIcon")
FADE_CARDS = parse_bool_map("PnlCardFade")

# palette (PnlAccentA1 / A2 / Ink / Soft / Bd, transcribed — colours are C'r,g,b')
A1 = {0: (255, 194, 71), 1: (99, 236, 189), 2: (121, 220, 255),
      3: (188, 166, 255), 4: (255, 192, 140), 5: (255, 167, 182)}
A2 = {0: (255, 138, 0), 1: (18, 184, 134), 2: (31, 168, 224),
      3: (124, 92, 255), 4: (255, 106, 43), 5: (240, 69, 95)}
AINK = {0: (26, 18, 6), 1: (4, 20, 15), 2: (4, 18, 26),
        3: (12, 7, 34), 4: (26, 10, 3), 5: (28, 4, 9)}
ASOFT = {0: (56, 53, 47), 1: (28, 52, 55), 2: (29, 50, 66),
         3: (40, 41, 69), 4: (56, 43, 44), 5: (54, 38, 50)}
ABD = {0: (94, 82, 56), 1: (25, 94, 80), 2: (30, 88, 116),
       3: (62, 55, 122), 4: (94, 62, 48), 5: (94, 50, 62)}

CLR = {
    "TITLE": (243, 246, 251), "MUTED": (140, 150, 166), "LABEL": (203, 212, 226),
    "VALUE": (243, 246, 251), "TRACK_BD": (44, 52, 68), "TRACK": (34, 41, 55),
    "SEG_ON": (255, 194, 71), "SEG_OFF": (29, 34, 44), "SEG_BD": (45, 52, 65),
    "SEG_TX": (140, 150, 166), "LINE": (34, 40, 50), "FIELD": (24, 29, 39),
    "CARD": (29, 34, 44), "FOOTBG": (18, 22, 29), "TICK": (52, 58, 70),
}
SWATCH = [(255, 171, 0), (240, 69, 95), (18, 184, 134), (31, 168, 224),
          (124, 92, 255), (207, 227, 255), (255, 255, 255), (20, 20, 20)]

# Point sizes, transcribed from the PnlSetLabel(...) calls in PnlCreate /
# PnlCreateRow / PnlFooterBtn. They are the one set of numbers this script
# cannot read out of the source without a full expression parser, so keep them
# in sync by hand when a label's size changes.
# These MUST equal the PNL_PT_* table in Biotak/BiotakPanels.mqh (preview CSS px
# * 3/4). They drifted twice already: the row label sat at 7 here against the
# MQL's 8, and the title was 12 in both against the preview's 12.5px -> 9.
PT = {"title": 9, "sub": 6, "lbl": 9, "lblsm": 8, "sec": 7, "cap": 7,
      "val": 8, "ctl": 8, "nav": 8, "key": 6, "ver": 6, "cset": 5,
      "foot": 8, "pal": 8, "palsec": 7}

# ── TEXT METRICS — the mirror of PnlDpi / PnlPt / PnlAdvUnits / PnlTextW / PnlFit
# in Biotak/BiotakPanels.mqh (P-UI-30, 2026-09-12). MT4 sizes a label font at
# the TERMINAL's DPI while these cards are designed in 96-DPI pixels, so the MQL
# now (a) shrinks each point size by 96/dpi — MT4 then draws the DESIGN's px on
# any display — and (b) reserves room with the real Arial Bold advance instead
# of a `StringLen * 6` guess. Both halves must stay in step here or the proof
# stops predicting the terminal. See `--dpi`.
DPI = 96          # 120 = a Windows desktop at 125% scaling, 144 = 150%


def dpi_pt(nominal):
    """The point size the MQL passes to MT4 (PnlPt)."""
    return max(4, int(round(nominal * 96.0 / DPI)))


def font_px(nominal):
    """px per em MT4 uses: the passed points at the display's DPI."""
    return int(round(dpi_pt(nominal) * DPI / 72.0))


_ADV_LO = [556, 611, 556, 611, 556, 333, 611, 611, 278, 278, 556, 278, 889,
           611, 611, 611, 611, 389, 556, 333, 611, 556, 778, 556, 556, 500]
_ADV_UP = [722, 722, 722, 722, 667, 611, 778, 722, 278, 556, 722, 611, 833,
           722, 778, 667, 778, 722, 667, 611, 722, 667, 944, 667, 722, 611]
_ADV = {32: 278, 46: 278, 44: 278, 58: 333, 59: 333, 45: 333, 47: 278, 37: 889,
        183: 333, 38: 722, 40: 333, 41: 333, 43: 584, 61: 584, 60: 584, 62: 584,
        33: 333, 63: 611, 95: 556, 35: 556, 42: 389, 64: 975}


def adv(ch):
    """Arial Bold advance, units per 1000 em."""
    o = ord(ch)
    if 48 <= o <= 57:
        return 556
    if 97 <= o <= 122:
        return _ADV_LO[o - 97]
    if 65 <= o <= 90:
        return _ADV_UP[o - 65]
    return _ADV.get(o, 611)


def text_w(s, nominal):
    """The px MT4 will draw `s` at, for a NOMINAL (design) point size."""
    if not s:
        return 0
    return int(round(sum(adv(ch) for ch in s) * dpi_pt(nominal) * DPI / 72.0 / 1000.0))


def fit(s, nominal, max_w):
    """PnlFit: the longest prefix that fits, ".." when clipped."""
    if max_w <= 0 or text_w(s, nominal) <= max_w:
        return s
    for k in range(len(s), 0, -1):
        cut = s[:k].rstrip()
        if text_w(cut + "..", nominal) <= max_w:
            return cut + ".."
    return ""


# ── --audit: every caption that sits beside a control records its room, so a
# row that has grown too tight is REPORTED instead of discovered on a chart.
# The number that matters is slack = room - text_w(caption): negative means the
# caption had to be clipped (".."). This is the P-UI-30 regression gate.
AUDIT = []


def audit(item, r, kind, lab, lx, room, nominal=None, mode="clip"):
    """Record a caption's room. `mode` is what the MQL does when it runs out:
    "clip" = PnlFit ellipsis, "drop" = the DUAL rule (the caption is dropped and
    the band above keeps naming the group), "none" = no limit to apply."""
    nominal = PT["lbl"] if nominal is None else nominal
    AUDIT.append((item, r, kind, lab, lx, room, text_w(lab, nominal), nominal, mode))


def rgb(t):
    return "rgb(%d,%d,%d)" % t


def rgba(t, a):
    return "rgba(%d,%d,%d,%.3f)" % (t[0], t[1], t[2], a)


# MT4's OBJ_LABEL font is Arial/Arial Bold at a point size; the panels pass a
# DPI-compensated size (PnlPt) so the em box lands on the DESIGN's px — see
# font_px(). This is the closest the raster can get to the terminal's own type;
# the HTML emitter leaves the glyph shapes to the browser instead.
_FONTS = {}


def _font(px, bold):
    key = (px, bold)
    if key in _FONTS:
        return _FONTS[key]
    try:
        from PIL import ImageFont
    except ImportError:
        _FONTS[key] = None
        return None
    name = "arialbd.ttf" if bold else "arial.ttf"
    for cand in (os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts", name),
                 "/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf" % ("-Bold" if bold else "")):
        if os.path.exists(cand):
            _FONTS[key] = ImageFont.truetype(cand, px)
            return _FONTS[key]
    _FONTS[key] = None
    return None


# ─────────────────────────────────────────────────────────────────────────────
# Card model
# ─────────────────────────────────────────────────────────────────────────────


def accent_of(item):
    return CARD_ACCENT.get(item, 0)


def missing_assets(cards):
    """Every bitmap the sim blits that is NOT on disk — the proof's own
    self-check, and it must be EMPTY.

    A name the MQL can still build that no file backs is a silent no-op in the
    terminal (P-PANELUI-01: an undeclared/unbacked bitmap just does not paint,
    so the row loses its chrome and nothing anywhere reports it). The proof is
    the only place that can see it, so it fails loudly instead of hatching.
    """
    seen = set()
    for c in cards:
        for op in c["canvas"].ops:
            if op[0] == "img" and op[1]:
                seen.add(op[1])
    return sorted(n for n in seen
                  if not os.path.exists(os.path.join(ICONS, n)))


def card_rows(item):
    """Display rows for one card, matching PnlSpecBuild + PnlRowDef."""
    specs = SPECS.get(item)
    if not specs:
        return []
    out = []
    for s in specs:
        kind = s["kind"]
        label, opts, unit, mn, mx = s["sec"], "", "", 0, 100
        if kind == -1:                      # PNL_K_LEGACY -> the setting's own def
            d = DEFS.get((item, s["s0"]), {})
            kind = d.get("kind", 0) or 0
            label = d.get("label", "")
            opts, unit = d.get("opts", ""), d.get("unit", "")
            mn, mx = d.get("minV", 0), d.get("maxV", 100)
        out.append({**s, "kind": kind, "label": label, "opts": opts,
                    "unit": unit, "minV": mn, "maxV": mx})
    return out


# ─────────────────────────────────────────────────────────────────────────────
# Demo state — deterministic, chosen so every control type is visible
# ─────────────────────────────────────────────────────────────────────────────
ON = {"SHOW", "SHOW LINES", "MID ZONES", "SS/LS ORDER", "COUNTDOWN", "ATR LABELS",
      "ATR TARGETS", "TRADE LABELS", "TP ROW", "TH LABELS", "FRACTAL THs",
      "TH TARGETS", "ENABLED", "MAGNET", "SHOW STRUCTURE", "SHOW WICKS",
      "STRUCTURE L1", "STRUCTURE L2", "STRUCTURE L3", "STRUCTURE L4"}
PCT = {"TRANSPARENCY": 28, "HEIGHT": 62, "BORDER TR": 20, "FILL TR": 55,
       "COUNT SIZE": 9, "COUNT GAP": 6, "ROW GAP": 18, "MARGIN BOTTOM": 40,
       "MAGNET SENS": 12, "VALUE": 100, "WIDTH": 2, "BORDER WIDTH": 2,
       "WICK WIDTH": 1, "SIZE": 11, "TARGET R": 2, "MAX LEVELS": 5}
SEG0 = {"ZONE STYLE": 0, "BORDER": 0, "STYLE": 0, "TIMEFRAME": 1, "BOX MODE": 0,
        "MODE": 0, "DISPLAY": 0, "BASIS": 0, "B INFO": 0, "ALIGN": 1,
        "VALIGN": 1, "TEMPLATE": 0, "B | I": 1}
CSET_DEMO = {6: [(63, 236, 189), (240, 69, 95), (140, 150, 166), (45, 52, 65)],
             12: [(46, 139, 87), (220, 50, 50), (30, 144, 255)]}


def demo_value(item, r):
    k, lab = r["kind"], r["label"]
    if k == 1:
        return 1.0 if lab in ON else 0.0
    if k == 0:
        return float(PCT.get(lab, 50))
    if k == 2:
        return float(SEG0.get(lab, 0))
    if k == 9:
        return 1.0
    return 0.0


# ─────────────────────────────────────────────────────────────────────────────
# HTML emission
# ─────────────────────────────────────────────────────────────────────────────


# ── PAINT BANDS (P-UI-31) — the sim's local ranks and the LADDER rung each one
# stands for. MT4 paints by OBJPROP_ZORDER (tie -> creation order); the real
# rungs live in the Z ladder of `Biotak/ConstantsAndEnums.mqh`. The proof only
# needs the ORDER, so it uses small integer ranks — but a rank that says nothing
# is a rank that drifts, so every rank declares its rung here and
# `tools/zorder-audit.py` proves the two agree:
#   * the ranks must be monotone with their rungs (a band may not mix a low and
#     a high rung with a band in between)
#   * every rank used at a call site must appear here
#   * no rung ABOVE Z_PANEL_TEXT may sit in a band ABOVE the type's band — the
#     type paints LAST, which is the premise of the whole overlap gate
# A band that legally mixes rungs (a chip body and the glyph ON it) is fine:
# equal ranks tie, and the sim creates tied objects in the MQL's own order.
BAND = {
    0: ["Z_PANEL_CARD"],
    1: ["Z_PANEL_TOPBAR", "Z_PANEL_ACT", "Z_PANEL_SEP"],
    2: ["Z_PANEL_BAND", "Z_PANEL_HAIR", "Z_PANEL_SKIN", "Z_PANEL_CHIP"],
    3: ["Z_PANEL_BASE", "Z_PANEL_SKIN", "Z_PANEL_CHIP", "Z_PANEL_INK"],
    4: ["Z_PANEL_SKIN", "Z_PANEL_CHIP", "Z_PANEL_INK", "Z_PANEL_GLYPH",
        "Z_PANEL_SW", "Z_PANEL_EDIT", "Z_PANEL_KNOB"],
    5: ["Z_PANEL_TEXT"],          # the type paints LAST
    6: ["Z_PANEL_MARK"],          # ...except the active tab underline, over it
}
TEXT_BAND = 5                     # Canvas.text's default rank


class Canvas:
    """Records draw ops in MT4's own terms — an image blit, a filled rect or a
    text run, each at an absolute pixel rect. Two emitters consume the list:
    HTML (for inspection) and a rasteriser (so the layout can be eyeballed
    without a browser)."""

    def __init__(self):
        self.ops = []
        # The card skin BMP carries a transparent PNL_MARGIN fringe (it holds the
        # baked shadow), so the MQL blits it at (px-M, py-M) while every piece of
        # chrome is placed at px+.... Renderings here are in CARD coordinates, so
        # the origin shift has to be applied to the chrome — otherwise the whole
        # card sits M px up-and-left of its own body and every spacing
        # measurement taken off this proof is wrong by 14px.
        self.dx = 0
        self.dy = 0

    def origin(self, dx, dy):
        self.dx, self.dy = dx, dy

    def img(self, name, x, y, w, h, z=1, title=""):
        u, bw, bh = uri(name)
        self.ops.append(("img", name if u else None, x + self.dx, y + self.dy, w, h, z))

    def rect(self, x, y, w, h, col, z=1, radius=0, border=None):
        if w <= 0 or h <= 0:
            return
        self.ops.append(("rect", col, x + self.dx, y + self.dy, w, h, radius, border, z))

    def text(self, x, y, s, col, pt, bold=False, anchor="lu", z=TEXT_BAND):
        if s == "":
            return
        self.ops.append(("text", s, x + self.dx, y + self.dy, col, pt, bold, anchor, z))

    # ── emitter 1: HTML (exact chrome + browser-rendered type)
    def to_html(self):
        # MT4 paints by ZORDER with creation order breaking ties, and this op
        # list IS the creation order — so one STABLE sort on z reproduces the
        # terminal exactly. It used to sort every op by o[5], which is the
        # element's HEIGHT for both images and rects (z lives one slot further
        # right), so the 384px-tall card skin sorted behind every caption and
        # painted straight over the whole card: the proof showed bare chrome
        # with all its type hidden under the card gradient. That is why the
        # page must never be 'verified' by eyeballing alone.
        parts = []
        for op in sorted(self.ops, key=lambda o: o[-1]):
            if op[0] == "img":
                name, x, y, w, h, z = op[1:7]
                if name is None:
                    parts.append('<i class="miss" style="left:%dpx;top:%dpx;width:%dpx;'
                                 'height:%dpx;z-index:%d"></i>' % (x, y, w, h, z))
                    continue
                u = uri(name)[0]
                parts.append('<img src="%s" style="left:%dpx;top:%dpx;width:%dpx;height:%dpx;'
                             'z-index:%d" alt="" title="%s">' % (u, x, y, w, h, z, name))
            elif op[0] == "rect":
                _, col, x, y, w, h, radius, border, _z = op
                b = "border:1px solid %s;" % border if border else ""
                parts.append('<i style="left:%dpx;top:%dpx;width:%dpx;height:%dpx;background:%s;'
                             'border-radius:%dpx;%s"></i>' % (x, y, w, h, col, radius, b))
            else:
                _, s, x, y, col, pt, bold, anchor, z = op
                tf = {"lu": "translate(0,0)", "ru": "translate(-100%,0)",
                      "cu": "translate(-50%,0)"}[anchor]
                # The z-index is NOT decoration: CSS paints every positioned
                # element with z-index:auto in the SAME layer as z-index:0, i.e.
                # BELOW every z-index:1+ image. Text without one therefore
                # disappeared under its own chrome — the footer captions sat
                # under the 88x44 button skin (z 3) and the proof showed blank
                # Reset/Done pills. MT4 has the one ZORDER scale (labels 1520 >
                # skins 1501 > buttons 1500), so the sim must emit it too.
                parts.append('<span style="left:%dpx;top:%dpx;transform:%s;color:%s;'
                             'font-size:%dpx;font-weight:%s;line-height:1;white-space:nowrap;'
                             'z-index:%d">%s</span>'
                             % (x, y, tf, col, font_px(pt), "700" if bold else "400", z,
                                s.replace("&", "&amp;").replace("<", "&lt;")))
        return "".join(parts)

    # ── emitter 2: raster (chrome + type, via Pillow when available)
    def to_raster(self, W, H):
        try:
            from PIL import Image, ImageDraw, ImageFont
        except ImportError:
            return self._to_raster_stdlib(W, H)
        img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        for op in self.ops:
            if op[0] == "img":
                _, name, x, y, w, h, _z = op
                if name is None:
                    continue
                iw, ih, px = read_bmp(os.path.join(ICONS, name))
                spr = Image.frombytes("RGBA", (iw, ih), px)
                if (iw, ih) != (w, h):
                    spr = spr.resize((w, h), Image.NEAREST)
                img.alpha_composite(spr, (x, y))
            elif op[0] == "rect":
                _, col, x, y, w, h, radius, _b, _z = op
                m = re.match(r"rgba?\((\d+),(\d+),(\d+)(?:,([\d.]+))?\)", col)
                if not m or w <= 0 or h <= 0:
                    continue
                fill = (int(m.group(1)), int(m.group(2)), int(m.group(3)),
                        int(float(m.group(4)) * 255) if m.group(4) else 255)
                if radius:
                    ImageDraw.Draw(img).rounded_rectangle(
                        [x, y, x + w - 1, y + h - 1], radius=min(radius, min(w, h) // 2), fill=fill)
                else:
                    ImageDraw.Draw(img).rectangle([x, y, x + w - 1, y + h - 1], fill=fill)
            else:
                _, s, x, y, col, pt, bold, anchor, _z = op
                f = _font(font_px(pt), bold)
                if f is None:
                    continue
                m = re.match(r"rgba?\((\d+),(\d+),(\d+)", col)
                if not m:
                    continue
                ImageDraw.Draw(img).text((x, y), s, font=f,
                                         fill=(int(m.group(1)), int(m.group(2)), int(m.group(3)), 255),
                                         anchor={"lu": "la", "ru": "ra", "cu": "ma"}[anchor])
        return W, H, img.tobytes()

    def _to_raster_stdlib(self, W, H):
        """Fallback when Pillow is unavailable: chrome only, no type."""
        buf = bytearray(W * H * 4)

        def blend(x, y, r, g, b, a):
            if a == 0 or not (0 <= x < W and 0 <= y < H):
                return
            i = (y * W + x) * 4
            sa, da = a / 255.0, buf[i + 3] / 255.0
            oa = sa + da * (1 - sa)
            if oa <= 0:
                return
            for k, c in enumerate((r, g, b)):
                buf[i + k] = int(round((c * sa + buf[i + k] * da * (1 - sa)) / oa))
            buf[i + 3] = int(round(oa * 255))

        for op in self.ops:
            if op[0] == "img":
                _, name, x, y, w, h, _z = op
                if name is None:
                    continue
                iw, ih, px = read_bmp(os.path.join(ICONS, name))
                for yy in range(h):
                    for xx in range(w):
                        s = ((yy * ih // h) * iw + (xx * iw // w)) * 4
                        blend(x + xx, y + yy, px[s], px[s + 1], px[s + 2], px[s + 3])
            elif op[0] == "rect":
                _, col, x, y, w, h, radius, _b, _z = op
                m = re.match(r"rgba?\((\d+),(\d+),(\d+)(?:,([\d.]+))?\)", col)
                if not m:
                    continue
                r, g, b = int(m.group(1)), int(m.group(2)), int(m.group(3))
                a = int(float(m.group(4)) * 255) if m.group(4) else 255
                for yy in range(h):
                    for xx in range(w):
                        if radius and min(xx, w - 1 - xx) + min(yy, h - 1 - yy) < radius - 1:
                            continue
                        blend(x + xx, y + yy, r, g, b, a)
        return W, H, bytes(buf)

    def html(self):
        return self.to_html()


def keycap_at(c, x, y, k, col, band):
    """P-UI-32 — the mirror of PnlKeycapAt() in Biotak/BiotakPanels.mqh: the cap
    bitmap plus its CENTRED letter. The preview's `.key` is `place-items:center`;
    the port used to right-anchor the letter at the cap's right edge, which put
    every hotkey ~6px right of centre. Both halves are measured (P-UI-30): the
    advance via text_w, the em box via font_px."""
    canvas = D["PNL_KEYCAP_CANVAS"]
    c.img("pnl_keycap.bmp", x, y, canvas, canvas, band)
    c.text(x + canvas // 2 + text_w(k, PT["key"]) // 2,
           y + (canvas - font_px(PT["key"])) // 2, k, col, PT["key"], True, "ru")


def render_card(item):
    rows = card_rows(item)
    n = len(rows)
    if n == 0:
        return None
    acc = accent_of(item)
    aname = ACCENT_NAME[acc]
    c = Canvas()
    PAD = D["PNL_PAD_X"]
    WEL = D["PNL_WEL"]
    HH, RH, FH = D["PNL_HEAD_H"], D["PNL_ROW_H"], D["PNL_FOOT_H"]
    # WIDE mirror of PnlRowCol/PnlRowLine/PnlPairRows/PnlIsWide (P-UI-25):
    # full rows (SEC bands, underline tabs) own their line; halves alternate.
    wide = n > D["PNL_WIDE_MIN_ROWS"]
    cardW = D["PNL_WIDE_WEL"] if wide else WEL
    DX = D["PNL_COL_DX"]
    def _full(j):
        return wide and (rows[j]["kind"] == 7 or (item in (9, 12) and j == 0))
    if not wide:
        cols, lines = [0] * n, list(range(n))
    else:
        cols, lines = [], []
        _cc = 0
        for j in range(n):
            if _full(j):
                _cc = 0
            cols.append(_cc)
            if not _full(j):
                _cc = 1 - _cc
        _ln, _lc = 0, 0
        for j in range(n):
            full = _full(j)
            slot = _ln + (1 if (full and _lc == 1) else 0)
            lines.append(slot)
            if full:
                _ln, _lc = slot + 1, 0
            else:
                if _lc == 1:
                    _ln += 1
                _lc = 1 - _lc
    pairN = lines[-1] + 1
    ph = HH + pairN * RH + FH
    if wide:
        wm = max(1, min(D["PNL_WIDE_ROWS_MAX"], pairN))
        skin_name = "pnl_cardW%d%s.bmp" % (wm, "f" if item in FADE_CARDS else "")
    else:
        skin_name = "pnl_card%d%s.bmp" % (min(D["PNL_CARD_ROWS_MAX"], max(3, n)),
                                          "f" if item in FADE_CARDS else "")
    skin_w = cardW + 2 * D["PNL_MARGIN"]
    skin_h = ph + 2 * D["PNL_MARGIN"]

    # ── card body (the baked soft shadow + gradient + hairlines live in here).
    #    The BMP is the whole skin INCLUDING its 2*PNL_MARGIN shadow fringe and
    #    MT4 blits it M px up-left of the card origin — exactly what the MQL does
    #    with (px-PNL_MARGIN, py-PNL_MARGIN). So the fringe is drawn at 0,0 and
    #    the chrome origin is pushed in by MARGIN to match.
    c.img(skin_name, 0, 0, skin_w, skin_h, 0)
    c.origin(D["PNL_MARGIN"], D["PNL_MARGIN"])

    # ── header
    c.img("pnl_topbar%s_%s.bmp" % ("W" if wide else "", aname), 0, 0, cardW,
          3 + 2 * D["PNL_CHIP_PAD"], 1)
    c.img("pnl_hair%s_%s.bmp" % ("W" if wide else "", aname), 0, HH - 1 - D["PNL_CHIP_PAD"],
          cardW, 1 + 2 * D["PNL_CHIP_PAD"], 2)
    MP = D["PNL_MARK_PAD"]
    c.img("pnl_mark_%s.bmp" % aname, PAD - MP, D["PNL_MARK_Y"] - MP,
          D["PNL_MARK_VIS"] + 2 * MP, D["PNL_MARK_VIS"] + 2 * MP, 3)
    mi = ACCENT_MARK.get(item, "")
    if mi:
        g = (D["PNL_MARK_VIS"] - D["PNL_GLYPH_CANVAS"]) // 2
        c.img("gl_%s_i_%s.bmp" % (mi, aname), PAD + g, D["PNL_MARK_Y"] + g,
              D["PNL_GLYPH_CANVAS"], D["PNL_GLYPH_CANVAS"], 4)
    htx = PAD + D["PNL_MARK_VIS"] + 10
    # .key + .ver + .x column — the title's own room ends one .hd gap left of
    # it (P-UI-30; the title used to run under the .ver badge on scaled DPIs).
    ck0 = ACCENT_KEY.get(item, "")
    vtxt0 = str(item)
    vw0 = 10 + text_w(vtxt0, PT["ver"])
    hx0 = cardW - PAD - D["PNL_XBTN_VIS"] - 6
    chip_l0 = hx0 - vw0
    if ck0:
        chip_l0 -= 10 + D["PNL_KEYCAP_VIS"] + 2 * D["PNL_KEYCAP_PAD"] + D["PNL_CHIP_PAD"]
    c.text(htx, 15, fit(ACCENT_TITLE.get(item, ""), PT["title"], chip_l0 - htx - D["PNL_ROW_GAP"]),
           rgb(CLR["TITLE"]), PT["title"], True)
    # .subttl — mirrors BiotakPanels.mqh PnlCreate: one 4px dot (amber, jade,
    # amber …) + caption per ' · ' segment, cut at the right edge of the
    # preview's .htxt box — one 10px .hd gap left of .key when the card has a
    # hotkey, else of .ver (R-SUBFIT). The preview is overflow:hidden, so it
    # draws every caption and CUTS the last one mid-word; MT4 cannot cut a
    # glyph, so a caption that crosses the edge is drawn as the longest whole
    # prefix that fits and the run stops there (R-SUBFIT2). A caption's own
    # width decides the fit, not its width plus the 5px gap to the next dot.
    # This must stay in step with the MQL or the proof stops predicting the
    # terminal.
    ck, vtxt, vw, hx = ck0, vtxt0, vw0, hx0     # one owner (built with the title)
    sub_limit = chip_l0 - 10
    segs = [s.strip() for s in ACCENT_HSUB.get(item, "").split("·") if s.strip()]
    sdx, drawn = htx, 0
    for si, seg in enumerate(segs):
        text_x = sdx + 9
        txt_w = text_w(seg, PT["sub"])          # P-UI-30: real advance
        cap = seg
        if text_x + txt_w > sub_limit:          # crosses the .htxt edge
            cap = fit(seg, PT["sub"], sub_limit - text_x)
            if cap == "":
                break
        c.img("pnl_subdot_amber.bmp" if si % 2 == 0 else "pnl_subdot_jade.bmp",
              sdx - 2, 31, 8, 8, 2)
        c.text(text_x, 30, cap, rgb(CLR["MUTED"]), PT["sub"], True)
        drawn += 1
        if cap != seg:
            break                               # that was the clipped tail
        sdx = text_x + txt_w + 5                # next dot sits 5px on
    if drawn == 0:
        c.text(htx, 30, ACCENT_HSUB.get(item, ""), rgb(CLR["MUTED"]), PT["sub"], True)
    # .key then .ver (the preview's flex order), then .x
    c.rect(hx - vw, 20, vw, 16, rgb(ASOFT[acc]), 3, 4, rgb(ABD[acc]))
    c.text(hx - vw / 2, 24, vtxt, rgb(A1[acc]), PT["ver"], True, "cu")
    hx -= vw + 10
    if ck:
        keycap_at(c, hx - D["PNL_KEYCAP_VIS"] - D["PNL_KEYCAP_PAD"] - D["PNL_CHIP_PAD"],
                  19 - D["PNL_KEYCAP_PAD"], ck, rgb(CLR["LABEL"]), 3)
    xbx = cardW - PAD - D["PNL_XBTN_VIS"]
    c.img("pnl_xbtn.bmp", xbx - D["PNL_XBTN_PAD"], 15 - D["PNL_XBTN_PAD"],
          D["PNL_XBTN_VIS"] + 2 * D["PNL_XBTN_PAD"], D["PNL_XBTN_VIS"] + 2 * D["PNL_XBTN_PAD"], 3)
    c.img("gl_x_m.bmp", xbx + (D["PNL_XBTN_VIS"] - D["PNL_GLYPH_CANVAS"]) // 2,
          15 + (D["PNL_XBTN_VIS"] - D["PNL_GLYPH_CANVAS"]) // 2,
          D["PNL_GLYPH_CANVAS"], D["PNL_GLYPH_CANVAS"], 4)

    # ── rows (BX = column origin: 0, or +312 in a wide right half)
    for i, r in enumerate(rows):
        ry = HH + lines[i] * RH
        BX = cols[i] * DX
        if lines[i] > 0 and (i == 0 or lines[i - 1] != lines[i]):
            # P-UI-29: full card width like the spec's .row border-top.
            c.rect(0, ry, cardW, 1, rgb(CLR["LINE"]), 1)
        kind = r["kind"]
        ico, key, lab = r["ico"], r["key"], r["label"]
        lx = BX + PAD + (D["PNL_CHIP_VIS"] + 8 if ico else 0) + (D["PNL_KEYCAP_VIS"] + 6 if key else 0)

        def chip(on=False, x=None, y=None):
            if not ico:
                return
            x = BX + PAD if x is None else x
            y = ry + D["PNL_CHIP_Y"] if y is None else y
            c.img("pnl_chip_%s.bmp" % aname if on else "pnl_chip.bmp",
                  x - D["PNL_CHIP_PAD"], y - D["PNL_CHIP_PAD"],
                  D["PNL_CHIP_CANVAS"], D["PNL_CHIP_CANVAS"], 3)
            # PnlGlyphRes(ico, on): ON = the accent-coloured glyph, OFF = _m.
            # (The `_i_` ink set is only for glyphs sitting ON an accent
            #  surface — the header mark and the primary button.)
            c.img("gl_%s_%s.bmp" % (ico, aname) if on else "gl_%s_m.bmp" % ico,
                  x + 4, y + 4, D["PNL_GLYPH_CANVAS"], D["PNL_GLYPH_CANVAS"], 4)

        def keycap(x, y):
            if not key:
                return
            keycap_at(c, x - D["PNL_KEYCAP_PAD"], y - D["PNL_KEYCAP_PAD"],
                      key, rgb(CLR["LABEL"]), 3)

        if kind == 7:                                        # SECTION BAND
            # P-UI-29: full row width — spec .row.sec is the row's own bg.
            c.img("pnl_secband%s.bmp" % ("W" if wide else ""), 0, ry, cardW, 42, 2)
            c.img("pnl_secdot_%s.bmp" % aname, BX + PAD - D["PNL_SECDOT_PAD"], ry + 18 - D["PNL_SECDOT_PAD"],
                  D["PNL_SECDOT_VIS"] + 2 * D["PNL_SECDOT_PAD"],
                  D["PNL_SECDOT_VIS"] + 2 * D["PNL_SECDOT_PAD"], 4)
            lab_w = text_w(lab, PT["sec"])       # P-UI-30: real advance
            c.text(BX + PAD + 14, ry + 14, lab, rgb(CLR["MUTED"]), PT["sec"], True)
            hx0 = BX + PAD + 14 + lab_w + D["PNL_ROW_GAP"]
            if r["ext"] == "strip" and i + 1 < n and rows[i + 1]["kind"] == 8:
                mem = CSET_DEMO.get(item, [])
                for s in range(min(len(mem), rows[i + 1]["n"])):
                    c.rect(BX + PAD + 14 + lab_w + 12 + s * 18, ry + 13, 15, 15, rgb(mem[s]), 4, 3)
                hx0 = BX + PAD + 14 + lab_w + 12 + len(mem) * 18 + 8
            cw = D["PNL_SEC_CNT_W"]
            hx1 = cardW - PAD - cw - 12 - 16
            c.rect(hx0, ry + 21, max(0, hx1 - hx0), 1, rgb(CLR["LINE"]), 4)
            c.img("pnl_cntchip.bmp", cardW - PAD - cw - D["PNL_CHIP_PAD"] - 16, ry + 11,
                  cw + 2 * D["PNL_CHIP_PAD"], 20, 4)
            cnts = str(r["cnt"])
            # centred in the chip (P-UI-32): preview `.cnt` is a padded box.
            c.text(cardW - PAD - cw // 2 - 16 + text_w(cnts, PT["sec"]) // 2,
                   ry + 16, cnts, rgb(CLR["MUTED"]), PT["sec"], True, "ru")
            c.img("pnl_chev_%s.bmp" % aname, cardW - PAD - 12, ry + 16, 10, 10, 4)
            continue

        if kind == 8:                                        # COLOUR SET
            mem = CSET_DEMO.get(item, [(255, 171, 0), (18, 184, 134), (31, 168, 224)])
            m = r["n"]
            total = m * D["PNL_CSET_W"] + (m - 1) * D["PNL_CSET_GAP"]
            x0 = BX + (WEL - total) // 2
            for j in range(m):
                cx = x0 + j * (D["PNL_CSET_W"] + D["PNL_CSET_GAP"])
                c.rect(cx, ry + 17, D["PNL_CSET_W"], D["PNL_CSET_H"], rgb(mem[j % len(mem)]), 3, 3)
                nm = re.sub(r"\s*COLOR$", "", DEFS.get((item, r["s0"] + j), {}).get("label", ""))
                c.text(cx + D["PNL_CSET_W"] / 2, ry + 6, nm, rgb(CLR["MUTED"]), PT["cset"], True, "cu")
            continue

        if kind == 9:                                        # DUAL switches
            memb = [DEFS.get((item, r["s0"] + j), {}).get("label", "") for j in range(r["n"])]
            # PnlShortCap mirror: only the STRUCTURE family prefix goes
            shorts = [t[10:] if t.startswith("STRUCTURE ") else t for t in memb]
            cells = shorts + ([r["ext"]] if r["ext"] else [])
            widths = [D["PNL_DUAL_SW_W"] + 6 + text_w(t, PT["cap"]) + 14 for t in cells]
            total = sum(widths) - (14 - 12)
            cx = BX + WEL - PAD - total
            for j, t in enumerate(cells):
                # band 4 = Z_PANEL_SW (1506): the ladder keeps the switch face
                # UNDER the caption, so the proof does too (P-UI-31).
                c.img("pnl_dsw_on_%s.bmp" % aname,
                      cx - D["PNL_SW_PAD"], ry + 11 - D["PNL_SW_PAD"],
                      D["PNL_DUAL_SW_W"] + 2 * D["PNL_SW_PAD"], D["PNL_DUAL_SW_H"] + 2 * D["PNL_SW_PAD"], 4)
                c.text(cx + D["PNL_DUAL_SW_W"] + 8, ry + 16, t, rgb(CLR["MUTED"]), PT["cap"], True)
                cx += widths[j]
            chip()
            dj = " · ".join(shorts + ([r["ext"]] if r["ext"] else []))
            # DUAL: the caption is DROPPED, never clipped — the cells keep their
            # own full captions and the band above names the group (P-UI-30).
            audit(item, i, "DUAL", dj, lx, BX + WEL - PAD - total - D["PNL_ROW_GAP"] - lx,
                  mode="drop")
            if text_w(dj, PT["lbl"]) > (BX + WEL - PAD - total - D["PNL_ROW_GAP"] - lx):
                dj = ""
            c.text(lx, ry + 14, dj, rgb(CLR["LABEL"]), PT["lbl"], True)
            continue

        if kind == 1:                                        # SWITCH
            on = lab in ON
            if on:
                # P-UI-29: one column, full-bleed like the band.
                c.img("pnl_actbg_%s.bmp" % aname, BX, ry, WEL, 42, 1)
                c.img("pnl_rail_%s.bmp" % aname, BX - 1, ry, 4, 42, 4)
            chip(on)
            keycap(BX + PAD + D["PNL_CHIP_VIS"] + 8, ry + 12)
            room = BX + D["PNL_SW_X"] - lx - D["PNL_ROW_GAP"]
            audit(item, i, "SW", lab, lx, room)
            c.text(lx, ry + 14, fit(lab, PT["lbl"], room),
                   rgb(CLR["LABEL"]), PT["lbl"], True)
            c.img("pnl_sw_on_%s.bmp" % aname if on else "pnl_sw_off.bmp",
                  BX + D["PNL_SW_X"] - D["PNL_SW_PAD"], ry + D["PNL_SW_Y"] - D["PNL_SW_PAD"],
                  D["PNL_SW_W"] + 2 * D["PNL_SW_PAD"], D["PNL_SW_H"] + 2 * D["PNL_SW_PAD"], 4)
            continue

        if kind == 4:                                        # COLOUR ROW
            c.img("gl_%s_m.bmp" % (ico or "droplet"), BX + PAD - 1, ry + 2,
                  D["PNL_GLYPH_CANVAS"], D["PNL_GLYPH_CANVAS"], 4)
            c.text(BX + PAD + D["PNL_GLYPH_VIS"] + 7, ry + 3,
                   fit(lab, PT["lblsm"], WEL - 2 * PAD - D["PNL_GLYPH_VIS"] - 7),
                   rgb(CLR["LABEL"]), PT["lblsm"], True)
            sy = ry + 18
            cur = SWATCH[2]
            c.rect(BX + PAD, sy, D["PNL_QSW_PREV"], 22, rgb(cur), 2, 4, rgb(A1[acc]))
            qx = BX + PAD + D["PNL_QSW_PREV"] + D["PNL_QSW_GAP"]
            for qi in range(D["PNL_QSW_N"]):
                c.rect(qx + qi * (D["PNL_QSW_W"] + D["PNL_QSW_GAP"]), sy, D["PNL_QSW_W"], 22,
                       rgb(SWATCH[qi]), 2, 4, rgb(A1[acc]) if SWATCH[qi] == cur else rgb(CLR["LINE"]))
            axx = qx + D["PNL_QSW_N"] * (D["PNL_QSW_W"] + D["PNL_QSW_GAP"])
            c.img("pnl_add_%s.bmp" % aname, axx - D["PNL_CHIP_PAD"], sy - D["PNL_CHIP_PAD"], 26, 26, 3)
            c.img("gl_plus_%s.bmp" % aname, axx + 4, sy + 4,
                  D["PNL_GLYPH_CANVAS"], D["PNL_GLYPH_CANVAS"], 4)
            continue

        if kind == 5:                                        # NAV
            chip()
            nw = 118
            nx = BX + WEL - PAD - nw
            audit(item, i, "NAV", lab, lx, nx - lx - D["PNL_ROW_GAP"])
            c.text(lx, ry + 14, fit(lab, PT["lbl"], nx - lx - D["PNL_ROW_GAP"]),
                   rgb(CLR["LABEL"]), PT["lbl"], True)
            c.rect(nx, ry + D["PNL_CTL_Y"] - 1, nw, 26, rgb(CLR["SEG_OFF"]), 2, 6, rgb(CLR["SEG_BD"]))
            c.text(nx + 10, ry + D["PNL_CTL_Y"] + 4,
                   fit(r["ext"], PT["nav"], nw - 32 - D["PNL_ROW_GAP"]),
                   rgb(CLR["VALUE"]), PT["nav"], True)
            c.img("gl_%s_%s.bmp" % ("back" if ico == "back" else "nav", aname),
                  nx + nw - 20, ry + D["PNL_CTL_Y"] + 4,
                  D["PNL_GLYPH_CANVAS"], D["PNL_GLYPH_CANVAS"], 4)
            continue

        if kind == 6:                                        # TEXT FIELD
            c.img("gl_%s_m.bmp" % (ico or "type"), BX + PAD - 1, ry + 2,
                  D["PNL_GLYPH_CANVAS"], D["PNL_GLYPH_CANVAS"], 4)
            c.text(BX + PAD + D["PNL_GLYPH_VIS"] + 7, ry + 3,
                   fit(lab, PT["lblsm"], WEL - 2 * PAD - D["PNL_GLYPH_VIS"] - 7),
                   rgb(CLR["LABEL"]), PT["lblsm"], True)
            c.rect(BX + PAD, ry + 15, WEL - 2 * PAD, 24, rgb(CLR["FIELD"]), 2, 4, rgb(CLR["SEG_BD"]))
            continue

        if kind == 2:                                        # SEGMENTS
            arr = r["opts"].split("|") if r["opts"] else ["—"]
            if item in (9, 12) and i == 0:                   # underline TABS
                icons = ["wave", "swap", "fn", "sigma"] if item == 9 else ["box", "type", "target"]
                tx = 12
                if wide:                                      # MQL centres across both columns
                    tot = sum(12 + text_w(t, PT["ctl"]) + (20 if j < len(icons) else 0) + 2
                              for j, t in enumerate(arr)) - 2
                    tx = (cardW - tot) // 2
                idx = int(demo_value(item, r))
                for j, t in enumerate(arr):
                    has = j < len(icons)
                    tw = 12 + text_w(t, PT["ctl"]) + (20 if has else 0)
                    if j == idx:
                        c.rect(tx, ry + D["PNL_CTL_Y"], tw, D["PNL_CTL_H"], rgba(A1[acc], .14), 1, 6)
                    if has:
                        c.img("gl_%s_%s.bmp" % (icons[j], aname) if j == idx else "gl_%s_m.bmp" % icons[j],
                              tx + 5, ry + D["PNL_CTL_Y"] + 4, D["PNL_GLYPH_CANVAS"], D["PNL_GLYPH_CANVAS"], 4)
                    c.text(tx + 12 + (20 if has else 0), ry + D["PNL_CTL_Y"] + 7, t,
                           rgb(CLR["TITLE"]) if j == idx else rgb(CLR["SEG_TX"]), PT["ctl"], j == idx)
                    if j == idx:
                        # band 6 = Z_PANEL_MARK: the ladder paints the underline
                        # OVER its caption, so the proof must too (P-UI-31).
                        c.rect(tx + 7, ry + D["PNL_CTL_Y"] + D["PNL_CTL_H"] - 1, tw - 14, 2, rgb(A1[acc]), 6, 1)
                    tx += tw + 2
                continue
            if len(arr) >= 4:                                # dropdown select
                txt = arr[int(demo_value(item, r))]
                # MUST mirror the MQL's PnlCreateRow dropdown: icon (7+15) +
                # caption (6px/char) + 8px gap + 10px chevron + 8px right pad.
                # At 26+6*len the chevron landed 11px inside the caption.
                dw = max(72, 50 + text_w(txt, PT["ctl"]))
                dx = BX + WEL - PAD - dw
                dy = ry + D["PNL_CTL_Y"] - 1
                c.rect(dx, dy, dw, 26, rgb(CLR["FIELD"]), 2, 6, rgb(CLR["SEG_BD"]))
                c.img("gl_%s_%s.bmp" % (ico or "fn", aname), dx + 7, dy + 7,
                      D["PNL_GLYPH_CANVAS"], D["PNL_GLYPH_CANVAS"], 4)
                c.text(dx + 24, dy + 8, txt, rgb(CLR["TITLE"]), PT["ctl"], True)
                c.img("pnl_chev_%s.bmp" % aname, dx + dw - 13, dy + 11, 10, 10, 4)
                chip()
                audit(item, i, "DD", lab, lx, dx - lx - D["PNL_ROW_GAP"])
                c.text(lx, ry + 14, fit(lab, PT["lbl"], dx - lx - D["PNL_ROW_GAP"]),
                       rgb(CLR["LABEL"]), PT["lbl"], True)
                continue
            idx = int(demo_value(item, r))                   # 2-3 pills
            tot = sum(16 + text_w(t, PT["ctl"]) for t in arr) + (len(arr) - 1) * 4
            sx = sx0 = BX + WEL - PAD - tot
            for j, t in enumerate(arr):
                w = 16 + text_w(t, PT["ctl"])
                c.rect(sx, ry + D["PNL_CTL_Y"] + 1, w, 24,
                       rgb(A1[acc]) if j == idx else rgb(CLR["SEG_OFF"]), 2, 6,
                       rgb(A2[acc]) if j == idx else rgb(CLR["SEG_BD"]))
                c.text(sx + w / 2, ry + D["PNL_CTL_Y"] + 7, t,
                       rgb(AINK[acc]) if j == idx else rgb(CLR["SEG_TX"]), PT["ctl"], j == idx, "cu")
                sx += w + 4
            chip()
            audit(item, i, "SEG", lab, lx, sx0 - lx - D["PNL_ROW_GAP"])
            c.text(lx, ry + 14, fit(lab, PT["lbl"], sx0 - lx - D["PNL_ROW_GAP"]),
                   rgb(CLR["LABEL"]), PT["lbl"], True)
            continue

        # SLIDER — P-UI-30: label + chip ride the TOP line (preview .sltop) so
        # the chip's 26px canvas cannot cover the track's first 24px.
        chip(y=ry + D["PNL_CHIP_Y_SL"])
        keycap(BX + PAD + D["PNL_CHIP_VIS"] + 8, ry + 4)
        vx = BX + WEL - PAD - D["PNL_VCHIP_W"]
        audit(item, i, "SLIDER", lab, lx, vx - lx - D["PNL_ROW_GAP"])
        c.text(lx, ry + 7, fit(lab, PT["lbl"], vx - lx - D["PNL_ROW_GAP"]),
               rgb(CLR["LABEL"]), PT["lbl"], True)
        c.img("pnl_vchip_%s.bmp" % aname, vx - D["PNL_VCHIP_PAD"],
              ry + D["PNL_VCHIP_Y"] - D["PNL_VCHIP_PAD"],
              D["PNL_VCHIP_W"] + 2 * D["PNL_VCHIP_PAD"], D["PNL_VCHIP_H"] + 2 * D["PNL_VCHIP_PAD"], 3)
        val = demo_value(item, r)
        unit = r["unit"]
        vt = ("%d%%" % round(val)) if unit == "%" else str(round(val))
        # centred on the 46px chip body (P-UI-32): preview `.val.chip` is
        # `text-align:center`, the port right-anchored it 8px in from the edge.
        c.text(vx + D["PNL_VCHIP_W"] // 2 + text_w(vt, PT["val"]) // 2, ry + 7,
               vt, rgb(A1[acc]), PT["val"], True, "ru")
        tx0, tw0 = BX + D["PNL_TRACK_X"], D["PNL_TRACK_W"]
        ty0 = ry + D["PNL_TRK_Y"]
        c.rect(tx0, ty0 - 1, tw0, D["PNL_TRK_H"] + 2, rgb(CLR["TRACK_BD"]), 2, 4)
        c.rect(tx0 + 1, ty0, tw0 - 2, D["PNL_TRK_H"], rgb(CLR["TRACK"]), 3, 3)
        frac = (val - r["minV"]) / (r["maxV"] - r["minV"]) if r["maxV"] > r["minV"] else 0
        kw = D["PNL_KNOB_W"]
        knob = tx0 + round(frac * (tw0 - kw))
        c.rect(tx0 + 1, ty0, max(0, knob + kw // 2 - (tx0 + 1)), D["PNL_TRK_H"], rgb(A1[acc]), 3, 3)
        # band 4, not 6: Z_PANEL_KNOB (1512) sits BELOW Z_PANEL_TEXT (1520), so
        # the value caption paints over the knob in MT4 — and here.
        c.img("pnl_knob.bmp", knob, ty0 + D["PNL_TRK_H"] // 2 - kw // 2, kw, kw, 4)
        for t in range(D["PNL_TICK_N"]):
            c.rect(tx0 + round(t * (tw0 - 1) / (D["PNL_TICK_N"] - 1)), ry + D["PNL_TICK_Y"], 1, 3,
                   rgb(CLR["TICK"]), 2)

    # ── footer
    fy = HH + pairN * RH
    BP, BW, BH = D["PNL_BTN_PAD"], D["PNL_BTN_W"], D["PNL_BTN_H"]

    def foot(ftag, bx, label, primary, ico_name):
        c.rect(bx, fy + 10, BW, BH, rgb(CLR["FOOTBG"]), 2)
        c.img("pnl_btn_prim_%s.bmp" % aname if primary else "pnl_btn_ghost.bmp",
              bx - BP, fy + 10 - BP, BW + 2 * BP, BH + 2 * BP, 3)
        c.img("gl_%s_%s.bmp" % (ico_name, "i_" + aname) if primary else "gl_%s_m.bmp" % ico_name,
              bx + 12, fy + 16, D["PNL_GLYPH_CANVAS"], D["PNL_GLYPH_CANVAS"], 4)
        c.text(bx + 32, fy + 17, fit(label, PT["foot"], D["PNL_BTN_W"] - 32 - 8),
               rgb(AINK[acc]) if primary else rgb(CLR["MUTED"]), PT["foot"], True)

    foot("rst", PAD, "Reset", False, "reset")
    foot("done", cardW - PAD - BW, "Done", True, "check")

    return {"item": item, "w": skin_w, "h": skin_h, "rows": n,
            "title": ACCENT_TITLE.get(item, "Factor"), "accent": aname,
            "fade": item in FADE_CARDS, "html": c.html(), "canvas": c}


def blit(dst, dw, dh, src, sw, sh, ox, oy):
    """Alpha-composite one RGBA buffer onto another at (ox, oy)."""
    for y in range(sh):
        dy = oy + y
        if not (0 <= dy < dh):
            continue
        for x in range(sw):
            dx = ox + x
            if not (0 <= dx < dw):
                continue
            s = (y * sw + x) * 4
            sa = src[s + 3] / 255.0
            if sa <= 0:
                continue
            d = (dy * dw + dx) * 4
            da = dst[d + 3] / 255.0
            oa = sa + da * (1 - sa)
            for k in range(3):
                dst[d + k] = int(round((src[s + k] * sa + dst[d + k] * da * (1 - sa)) / oa))
            dst[d + 3] = int(round(oa * 255))


def contact_sheet(cards, out):
    """One PNG with every card side by side, on the chart backdrop MT4 draws
    them over. Chrome only — the type is added by the HTML emitter."""
    gap, pad, top = 24, 18, 34
    W = pad * 2 + sum(c["w"] for c in cards) + gap * (len(cards) - 1)
    H = top + pad * 2 + max(c["h"] for c in cards)
    buf = bytearray(W * H * 4)
    for i in range(W * H):                       # #0E1116 chart backdrop
        buf[i * 4], buf[i * 4 + 1], buf[i * 4 + 2], buf[i * 4 + 3] = 0x0E, 0x11, 0x16, 255
    x = pad
    for c in cards:
        w, h, rgba = c["canvas"].to_raster(c["w"], c["h"])
        blit(buf, W, H, rgba, w, h, x, top)
        x += w + gap
    open(out, "wb").write(png(W, H, bytes(buf)))
    return W, H


# ── --audit (2/2): THE OVERLAP GATE. Every op the renderer records is turned
# back into its pixel box, then every pair is checked in PAINT order (ZORDER,
# creation order breaking ties). The bug class P-UI-30 fixed was always "a
# caption's tail ended up UNDER the control painted after it" — a label that
# grew at a scaled DPI while the control beside it stayed put. Full-width chrome
# (the card skin, the accent top bar, a section band, the active-row rail, a
# hairline divider) is painted UNDER the rows on purpose, so it is exempt.
OVERLAP_TOL = 2        # px of shared edge that is antialiasing, not a collision
UNDER = ("pnl_card", "pnl_secband", "pnl_actbg", "pnl_topbar", "pnl_hair",
         "pnl_mark", "pnl_subdot", "pnl_vchip", "pnl_chip", "pnl_check")


def op_box(op):
    """One painted op as (label, x0, y0, x1, y1, zorder)."""
    if op[0] == "img":
        _, name, x, y, w, h, z = op
        return (name or "(missing)", x, y, x + w, y + h, z)
    if op[0] == "rect":
        _, _col, x, y, w, h, _rad, _bd, z = op
        return ("rect", x, y, x + w, y + h, z)
    _, s, x, y, _col, pt, _bold, anchor, z = op
    w, h = text_w(s, pt), font_px(pt)
    if anchor[0] == "c":
        x -= w / 2.0
    elif anchor[0] == "r":
        x -= w
    if anchor[1] == "c":
        y -= h / 2.0
    elif anchor[1] == "b":
        y -= h
    return ('text "%s"' % s, x, y, x + w, y + h, z)


def overlap_hits(card):
    """Pairs where a later-painted op covers > OVERLAP_TOL px of a TEXT run.
    Only captions are reported: chrome over chrome (a chip under its glyph, a
    band under its label) is the design, a caption with a control on top of it
    is the bug."""
    boxes = [op_box(o) for o in card["canvas"].ops]
    out = []
    for i, a in enumerate(boxes):
        if not a[0].startswith("text "):
            continue
        for j, b in enumerate(boxes):
            if i == j or not b[0] or b[0].startswith(UNDER):
                continue
            if b[0].startswith("text ") and j < i:
                continue                     # the earlier caption is the victim
            if not b[0].startswith("text ") and (b[5], j) <= (a[5], i):
                continue                     # painted first -> underneath, fine
            ox = min(a[3], b[3]) - max(a[1], b[1])
            oy = min(a[4], b[4]) - max(a[2], b[2])
            if ox > OVERLAP_TOL and oy > OVERLAP_TOL:
                out.append((a, b, ox, oy))
    return out


def report_audit(cards):
    """--audit: (1) the captions with the least room left beside their control
    — slack < 0 means the caption was CLIPPED with "..", i.e. a row that has
    grown too tight for its own label; and (2) every caption a later-painted op
    covers. Run this after any caption / geometry change."""
    worst = sorted(AUDIT, key=lambda a: a[5] - a[6])
    tight = [a for a in AUDIT if a[5] - a[6] < 0 and a[8] != "drop"]
    drops = [a for a in AUDIT if a[5] - a[6] < 0 and a[8] == "drop"]
    print("audit: %d captioned controls, %d tight (%d clipped, %d dropped by design)"
          % (len(AUDIT), len(tight) + len(drops), len(tight), len(drops)))
    for item, r, kind, lab, lx, room, need, nom, mode in worst[:10]:
        print("  card %-2d row %-2d %-7s %-24s room %3d  needs %3d  slack %+4d%s"
              % (item, r, kind, '"' + lab + '"', room, need, room - need,
                 "  (drop: band names it)" if mode == "drop" else ""))
    hits = 0
    for c in cards:
        for a, b, ox, oy in overlap_hits(c):
            hits += 1
            if hits <= 12:
                print("  OVERLAP card %-2d  %s  under  %s  (%dx%d px)"
                      % (c["item"], a[0], b[0], ox, oy))
    if hits:
        print("overlap gate: %d caption(s) covered by a later-painted op" % hits)
    else:
        print("overlap gate: clean — no caption is covered by its own control")
    return len(tight) + hits


def main():
    global DPI
    # --dpi N models the terminal's display scaling: MT4 sizes label fonts at the
    # SCREEN dpi, and the MQL compensates by shrinking the point size (PnlPt),
    # so the LAYOUT is dpi-independent and only the em box can shift by a px.
    # 120 = Windows 125%, 144 = 150%; 96 (the design's own dpi) is the default.
    # Its VALUE must be consumed before the positional scan, or `--dpi 120`
    # writes the whole page to a file literally called "120" in the CWD.
    args = list(sys.argv[1:])
    if "--dpi" in args:
        k = args.index("--dpi")
        DPI = int(args[k + 1])
        del args[k:k + 2]
    argv = [a for a in args if not a.startswith("--")]
    raster = "--raster" in args
    out = argv[0] if argv else os.path.join(ROOT, "panel_mt4_sim.html")
    cards = [c for c in (render_card(i) for i in range(14)) if c]

    if "--audit" in args:
        report_audit(cards)

    missing = missing_assets(cards)
    if missing:
        print("SELF-CHECK FAILED: %d bitmap(s) the MQL blits are not in "
              "Files/Icons — every one is a silent no-op in MT4:" % len(missing))
        for n in missing:
            print("  MISSING: %s" % n)
        if "--allow-missing" not in sys.argv:
            return 1

    if raster:
        sheet = os.path.join(ROOT, "panel_mt4_sim_sheet.png")
        W, H = contact_sheet(cards, sheet)
        for c in cards:
            w, h, rgba = c["canvas"].to_raster(c["w"], c["h"])
            open(os.path.join(ROOT, "panel_mt4_sim_%02d.png" % c["item"]), "wb").write(png(w, h, rgba))
        print("wrote %s (%dx%d) + %d per-card PNGs" % (sheet, W, H, len(cards)))
        return 0

    body = []
    for c in cards:
        body.append(
            '<figure class="card">'
            '<figcaption><b>%d &middot; %s</b><span>%d rows &middot; accent %s%s</span></figcaption>'
            '<div class="skin" style="width:%dpx;height:%dpx">%s</div></figure>'
            % (c["item"], c["title"], c["rows"], c["accent"],
               " &middot; .fade" if c["fade"] else "", c["w"], c["h"], c["html"]))

    html = ("""<!doctype html><meta charset="utf-8">
<title>Panel simulator &mdash; the cards as MetaTrader draws them</title>""" + """
<style>
 body{margin:0;padding:26px 30px;background:#F2F5F9;color:#16202E;
      font:13px/1.55 Arial,Helvetica,sans-serif}
 h1{font-size:19px;margin:0 0 6px}
 .sub{color:#5A6577;font-size:12.5px;margin:0 0 8px;max-width:1000px}
 .sub code{background:#E6EBF2;padding:1px 5px;border-radius:4px;font-size:12px}
 .note{background:#FFF6E0;border:1px solid #F0D9A0;border-radius:8px;padding:10px 13px;
       font-size:12.5px;color:#6A5320;margin:0 0 24px;max-width:1000px}
 .wrap{display:flex;flex-wrap:wrap;gap:30px;align-items:flex-start}
 figure{margin:0}
 figcaption{font-size:11.5px;color:#5A6577;margin:0 0 8px}
 figcaption b{display:block;color:#16202E;font-size:12.5px}
 /* the chart backdrop a card actually sits on */
 .skin{position:relative;background:#0E1116;
       background-image:linear-gradient(rgba(255,255,255,.035) 1px,transparent 1px),
                        linear-gradient(90deg,rgba(255,255,255,.035) 1px,transparent 1px);
       background-size:22px 22px;border-radius:10px;box-shadow:0 10px 30px rgba(16,24,38,.22)}
 /* border-box: MT4's OBJ_BUTTON paints its 1px border INSIDE the XSIZE x YSIZE,
    so without this the proof inflated every swatch/segment/field by 2px and the
    colour row looked like it overflowed the card. */
 .skin *{position:absolute;margin:0;box-sizing:border-box}
 .skin img{image-rendering:pixelated;display:block}
 .skin i{display:block}
 .skin .miss{background:repeating-linear-gradient(45deg,#ff4d4d,#ff4d4d 4px,#7a1f1f 4px,#7a1f1f 8px);
             opacity:.85}
 .skin span{position:absolute}
</style>
<h1>Panel simulator &mdash; the cards as MetaTrader draws them</h1>
<p class="sub">Every bitmap below is the <b>real file</b> from <code>Files/Icons</code>; every
coordinate is parsed out of <code>Biotak/BiotakPanels.mqh</code>. No terminal involved &mdash;
this is the pixel layout MT4 will blit, so the baked soft shadows, gradients and radii
show up exactly as shipped.</p>
<p class="note"><b>Text is the one approximation.</b> Captions are rendered by the browser at
the same em box (the MQL's DPI-compensated point size &rarr; @@PX px) and the same anchor it
sets, but MT4 has its own font stack. Treat the chrome as exact and the type as very close.
<b>Every caption that touches a control is measured, never guessed</b> (P-UI-30): label
widths come from Arial Bold's real advances at @@DPI dpi, and a caption with no room left is
clipped with <code>..</code> the way the preview's ellipsis clips it.</p>
<div class="wrap">
@@CARDS@@
</div>
""").replace("@@CARDS@@", "".join(body)).replace("@@PX", str(font_px(PT["lbl"]))).replace("@@DPI", str(DPI))

    open(out, "w", encoding="utf-8").write(html)
    print("wrote %s (%d cards, %d bitmaps, %d dpi)" % (out, len(cards), len(_CACHE), DPI))
    return 0


SPECS = parse_spec_build()
DEFS = parse_set_def()

if __name__ == "__main__":
    sys.exit(main())
