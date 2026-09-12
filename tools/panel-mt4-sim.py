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


def rgb(t):
    return "rgb(%d,%d,%d)" % t


def rgba(t, a):
    return "rgba(%d,%d,%d,%.3f)" % (t[0], t[1], t[2], a)


# MT4's OBJ_LABEL font is Arial/Arial Bold at a point size; 1pt = 4/3px at the
# 96 DPI MT4 assumes. This is the closest the raster can get to the terminal's
# own type — the HTML emitter leaves it to the browser instead.
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
ON = {"SHOW", "SHOW LINES", "MID ZONES", "LS FIRST", "COUNTDOWN", "ATR LABELS",
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

    def text(self, x, y, s, col, pt, bold=False, anchor="lu", z=5):
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
                             % (x, y, tf, col, round(pt * 4 / 3), "700" if bold else "400", z,
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
                f = _font(round(pt * 4 / 3), bold)
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
    ph = HH + n * RH + FH
    skin_w = WEL + 2 * D["PNL_MARGIN"]
    skin_h = ph + 2 * D["PNL_MARGIN"]

    # ── card body (the baked soft shadow + gradient + hairlines live in here).
    #    The BMP is the whole skin INCLUDING its 2*PNL_MARGIN shadow fringe and
    #    MT4 blits it M px up-left of the card origin — exactly what the MQL does
    #    with (px-PNL_MARGIN, py-PNL_MARGIN). So the fringe is drawn at 0,0 and
    #    the chrome origin is pushed in by MARGIN to match.
    c.img("pnl_card%d%s.bmp" % (min(D["PNL_CARD_ROWS_MAX"], max(3, n)),
                                "f" if item in FADE_CARDS else ""), 0, 0, skin_w, skin_h, 0)
    c.origin(D["PNL_MARGIN"], D["PNL_MARGIN"])

    # ── header
    c.img("pnl_topbar_%s.bmp" % aname, 0, 0, WEL, 3 + 2 * D["PNL_CHIP_PAD"], 1)
    c.img("pnl_hair_%s.bmp" % aname, PAD, HH - 1 - D["PNL_CHIP_PAD"],
          WEL - 2 * PAD, 1 + 2 * D["PNL_CHIP_PAD"], 2)
    MP = D["PNL_MARK_PAD"]
    c.img("pnl_mark_%s.bmp" % aname, PAD - MP, D["PNL_MARK_Y"] - MP,
          D["PNL_MARK_VIS"] + 2 * MP, D["PNL_MARK_VIS"] + 2 * MP, 3)
    mi = ACCENT_MARK.get(item, "")
    if mi:
        g = (D["PNL_MARK_VIS"] - D["PNL_GLYPH_CANVAS"]) // 2
        c.img("gl_%s_i_%s.bmp" % (mi, aname), PAD + g, D["PNL_MARK_Y"] + g,
              D["PNL_GLYPH_CANVAS"], D["PNL_GLYPH_CANVAS"], 4)
    htx = PAD + D["PNL_MARK_VIS"] + 10
    c.text(htx, 15, ACCENT_TITLE.get(item, ""), rgb(CLR["TITLE"]), PT["title"], True)
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
    ck = ACCENT_KEY.get(item, "")
    vtxt = str(item)
    vw = 10 + len(vtxt) * 5
    hx = WEL - PAD - D["PNL_XBTN_VIS"] - 6
    chip_l = hx - vw
    if ck:
        chip_l -= 10 + D["PNL_KEYCAP_VIS"] + 2 * D["PNL_KEYCAP_PAD"] + D["PNL_CHIP_PAD"]
    sub_limit = chip_l - 10
    segs = [s.strip() for s in ACCENT_HSUB.get(item, "").split("·") if s.strip()]
    sdx, drawn = htx, 0
    for si, seg in enumerate(segs):
        text_x = sdx + 9
        txt_w = len(seg) * 5
        cap = seg
        if text_x + txt_w > sub_limit:          # crosses the .htxt edge
            fits = (sub_limit - text_x) // 5    # whole characters only
            if fits < 1:
                break
            cap = seg[:fits].rstrip()
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
        c.img("pnl_keycap.bmp", hx - D["PNL_KEYCAP_VIS"] - D["PNL_KEYCAP_PAD"] - D["PNL_CHIP_PAD"],
              19 - D["PNL_KEYCAP_PAD"], 22, 22, 3)
        c.text(hx - D["PNL_CHIP_PAD"] - 9, 22, ck, rgb(CLR["LABEL"]), PT["key"], True, "ru")
    xbx = WEL - PAD - D["PNL_XBTN_VIS"]
    c.img("pnl_xbtn.bmp", xbx - D["PNL_XBTN_PAD"], 15 - D["PNL_XBTN_PAD"],
          D["PNL_XBTN_VIS"] + 2 * D["PNL_XBTN_PAD"], D["PNL_XBTN_VIS"] + 2 * D["PNL_XBTN_PAD"], 3)
    c.img("gl_x_m.bmp", xbx + (D["PNL_XBTN_VIS"] - D["PNL_GLYPH_CANVAS"]) // 2,
          15 + (D["PNL_XBTN_VIS"] - D["PNL_GLYPH_CANVAS"]) // 2,
          D["PNL_GLYPH_CANVAS"], D["PNL_GLYPH_CANVAS"], 4)

    # ── rows
    for i, r in enumerate(rows):
        ry = HH + i * RH
        if i > 0:
            c.rect(PAD, ry, WEL - 2 * PAD, 1, rgb(CLR["LINE"]), 1)
        kind = r["kind"]
        ico, key, lab = r["ico"], r["key"], r["label"]
        lx = PAD + (D["PNL_CHIP_VIS"] + 8 if ico else 0) + (D["PNL_KEYCAP_VIS"] + 6 if key else 0)

        def chip(on=False, x=None, y=None):
            if not ico:
                return
            x = PAD if x is None else x
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
            c.img("pnl_keycap.bmp", x - D["PNL_KEYCAP_PAD"], y - D["PNL_KEYCAP_PAD"], 22, 22, 3)
            c.text(x + D["PNL_KEYCAP_VIS"], y + 4, key, rgb(CLR["LABEL"]), PT["key"], True, "ru")

        if kind == 7:                                        # SECTION BAND
            c.img("pnl_secband.bmp", PAD, ry, 280, 42, 2)
            c.img("pnl_secdot_%s.bmp" % aname, PAD - D["PNL_SECDOT_PAD"], ry + 18 - D["PNL_SECDOT_PAD"],
                  D["PNL_SECDOT_VIS"] + 2 * D["PNL_SECDOT_PAD"],
                  D["PNL_SECDOT_VIS"] + 2 * D["PNL_SECDOT_PAD"], 4)
            c.text(PAD + 14, ry + 14, lab, rgb(CLR["MUTED"]), PT["sec"], True)
            hx0 = PAD + 14 + len(lab) * 6 + 10
            if r["ext"] == "strip" and i + 1 < n and rows[i + 1]["kind"] == 8:
                mem = CSET_DEMO.get(item, [])
                for s in range(min(len(mem), rows[i + 1]["n"])):
                    c.rect(PAD + 14 + len(lab) * 6 + 12 + s * 18, ry + 13, 15, 15, rgb(mem[s]), 4, 3)
                hx0 = PAD + 14 + len(lab) * 6 + 12 + len(mem) * 18 + 8
            cw = D["PNL_SEC_CNT_W"]
            hx1 = WEL - PAD - cw - 12 - 16
            c.rect(hx0, ry + 21, max(0, hx1 - hx0), 1, rgb(CLR["LINE"]), 4)
            c.img("pnl_cntchip.bmp", WEL - PAD - cw - D["PNL_CHIP_PAD"] - 16, ry + 11,
                  cw + 2 * D["PNL_CHIP_PAD"], 20, 4)
            c.text(WEL - PAD - 8 - 16, ry + 16, str(r["cnt"]), rgb(CLR["MUTED"]), PT["sec"], True, "ru")
            c.img("pnl_chev_%s.bmp" % aname, WEL - PAD - 12, ry + 16, 10, 10, 4)
            continue

        if kind == 8:                                        # COLOUR SET
            mem = CSET_DEMO.get(item, [(255, 171, 0), (18, 184, 134), (31, 168, 224)])
            m = r["n"]
            total = m * D["PNL_CSET_W"] + (m - 1) * D["PNL_CSET_GAP"]
            x0 = (WEL - total) // 2
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
            widths = [D["PNL_DUAL_SW_W"] + 6 + len(t) * 6 + 14 for t in cells]
            total = sum(widths) - (14 - 12)
            cx = WEL - PAD - total
            for j, t in enumerate(cells):
                c.img("pnl_dsw_on_%s.bmp" % aname,
                      cx - D["PNL_SW_PAD"], ry + 11 - D["PNL_SW_PAD"],
                      D["PNL_DUAL_SW_W"] + 2 * D["PNL_SW_PAD"], D["PNL_DUAL_SW_H"] + 2 * D["PNL_SW_PAD"], 5)
                c.text(cx + D["PNL_DUAL_SW_W"] + 8, ry + 16, t, rgb(CLR["MUTED"]), PT["cap"], True)
                cx += widths[j]
            chip()
            dj = " · ".join(shorts + ([r["ext"]] if r["ext"] else []))
            if len(dj) * 5 > (WEL - PAD - total - 6 - lx):
                dj = ""
            c.text(lx, ry + 14, dj, rgb(CLR["LABEL"]), PT["lbl"], True)
            continue

        if kind == 1:                                        # SWITCH
            on = lab in ON
            if on:
                c.img("pnl_actbg_%s.bmp" % aname, PAD, ry, 280, 42, 1)
                c.img("pnl_rail_%s.bmp" % aname, -1, ry, 4, 42, 4)
            chip(on)
            keycap(PAD + D["PNL_CHIP_VIS"] + 8, ry + 12)
            c.text(lx, ry + 14, lab, rgb(CLR["LABEL"]), PT["lbl"], True)
            c.img("pnl_sw_on_%s.bmp" % aname if on else "pnl_sw_off.bmp",
                  D["PNL_SW_X"] - D["PNL_SW_PAD"], ry + D["PNL_SW_Y"] - D["PNL_SW_PAD"],
                  D["PNL_SW_W"] + 2 * D["PNL_SW_PAD"], D["PNL_SW_H"] + 2 * D["PNL_SW_PAD"], 5)
            continue

        if kind == 4:                                        # COLOUR ROW
            c.img("gl_%s_m.bmp" % (ico or "droplet"), PAD - 1, ry + 2,
                  D["PNL_GLYPH_CANVAS"], D["PNL_GLYPH_CANVAS"], 4)
            c.text(PAD + D["PNL_GLYPH_VIS"] + 7, ry + 3, lab, rgb(CLR["LABEL"]), PT["lblsm"], True)
            sy = ry + 18
            cur = SWATCH[2]
            c.rect(PAD, sy, D["PNL_QSW_PREV"], 22, rgb(cur), 2, 4, rgb(A1[acc]))
            qx = PAD + D["PNL_QSW_PREV"] + D["PNL_QSW_GAP"]
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
            c.text(lx, ry + 14, lab, rgb(CLR["LABEL"]), PT["lbl"], True)
            nw = 118
            nx = WEL - PAD - nw
            c.rect(nx, ry + D["PNL_CTL_Y"] - 1, nw, 26, rgb(CLR["SEG_OFF"]), 2, 6, rgb(CLR["SEG_BD"]))
            c.text(nx + 10, ry + D["PNL_CTL_Y"] + 4, r["ext"], rgb(CLR["VALUE"]), PT["nav"], True)
            c.img("gl_%s_%s.bmp" % ("back" if ico == "back" else "nav", aname),
                  nx + nw - 20, ry + D["PNL_CTL_Y"] + 4,
                  D["PNL_GLYPH_CANVAS"], D["PNL_GLYPH_CANVAS"], 4)
            continue

        if kind == 6:                                        # TEXT FIELD
            c.img("gl_%s_m.bmp" % (ico or "type"), PAD - 1, ry + 2,
                  D["PNL_GLYPH_CANVAS"], D["PNL_GLYPH_CANVAS"], 4)
            c.text(PAD + D["PNL_GLYPH_VIS"] + 7, ry + 3, lab, rgb(CLR["LABEL"]), PT["lblsm"], True)
            c.rect(PAD, ry + 15, WEL - 2 * PAD, 24, rgb(CLR["FIELD"]), 2, 4, rgb(CLR["SEG_BD"]))
            continue

        if kind == 2:                                        # SEGMENTS
            arr = r["opts"].split("|") if r["opts"] else ["—"]
            if item in (9, 12) and i == 0:                   # underline TABS
                icons = ["wave", "swap", "fn", "sigma"] if item == 9 else ["box", "type", "target"]
                tx = 12
                idx = int(demo_value(item, r))
                for j, t in enumerate(arr):
                    has = j < len(icons)
                    tw = 12 + len(t) * 6 + (20 if has else 0)
                    if j == idx:
                        c.rect(tx, ry + D["PNL_CTL_Y"], tw, D["PNL_CTL_H"], rgba(A1[acc], .14), 1, 6)
                    if has:
                        c.img("gl_%s_%s.bmp" % (icons[j], aname) if j == idx else "gl_%s_m.bmp" % icons[j],
                              tx + 5, ry + D["PNL_CTL_Y"] + 4, D["PNL_GLYPH_CANVAS"], D["PNL_GLYPH_CANVAS"], 4)
                    c.text(tx + 12 + (20 if has else 0), ry + D["PNL_CTL_Y"] + 7, t,
                           rgb(CLR["TITLE"]) if j == idx else rgb(CLR["SEG_TX"]), PT["ctl"], j == idx)
                    if j == idx:
                        c.rect(tx + 7, ry + D["PNL_CTL_Y"] + D["PNL_CTL_H"] - 1, tw - 14, 2, rgb(A1[acc]), 5, 1)
                    tx += tw + 2
                continue
            if len(arr) >= 4:                                # dropdown select
                txt = arr[int(demo_value(item, r))]
                # MUST mirror the MQL's PnlCreateRow dropdown: icon (7+15) +
                # caption (6px/char) + 8px gap + 10px chevron + 8px right pad.
                # At 26+6*len the chevron landed 11px inside the caption.
                dw = max(72, 50 + len(txt) * 6)
                dx = WEL - PAD - dw
                dy = ry + D["PNL_CTL_Y"] - 1
                c.rect(dx, dy, dw, 26, rgb(CLR["FIELD"]), 2, 6, rgb(CLR["SEG_BD"]))
                c.img("gl_%s_%s.bmp" % (ico or "fn", aname), dx + 7, dy + 7,
                      D["PNL_GLYPH_CANVAS"], D["PNL_GLYPH_CANVAS"], 4)
                c.text(dx + 24, dy + 8, txt, rgb(CLR["TITLE"]), PT["ctl"], True)
                c.img("pnl_chev_%s.bmp" % aname, dx + dw - 13, dy + 11, 10, 10, 4)
                chip()
                c.text(lx, ry + 14, lab, rgb(CLR["LABEL"]), PT["lbl"], True)
                continue
            idx = int(demo_value(item, r))                   # 2-3 pills
            tot = sum(16 + len(t) * 6 for t in arr) + (len(arr) - 1) * 4
            sx = WEL - PAD - tot
            for j, t in enumerate(arr):
                w = 16 + len(t) * 6
                c.rect(sx, ry + D["PNL_CTL_Y"] + 1, w, 24,
                       rgb(A1[acc]) if j == idx else rgb(CLR["SEG_OFF"]), 2, 6,
                       rgb(A2[acc]) if j == idx else rgb(CLR["SEG_BD"]))
                c.text(sx + w / 2, ry + D["PNL_CTL_Y"] + 7, t,
                       rgb(AINK[acc]) if j == idx else rgb(CLR["SEG_TX"]), 8, j == idx, "cu")
                sx += w + 4
            chip()
            c.text(lx, ry + 14, lab, rgb(CLR["LABEL"]), PT["lbl"], True)
            continue

        # SLIDER
        chip()
        keycap(PAD + D["PNL_CHIP_VIS"] + 8, ry + 4)
        c.text(lx, ry + 7, lab, rgb(CLR["LABEL"]), PT["lbl"], True)
        vx = WEL - PAD - D["PNL_VCHIP_W"]
        c.img("pnl_vchip_%s.bmp" % aname, vx - D["PNL_VCHIP_PAD"],
              ry + D["PNL_VCHIP_Y"] - D["PNL_VCHIP_PAD"],
              D["PNL_VCHIP_W"] + 2 * D["PNL_VCHIP_PAD"], D["PNL_VCHIP_H"] + 2 * D["PNL_VCHIP_PAD"], 3)
        val = demo_value(item, r)
        unit = r["unit"]
        vt = ("%d%%" % round(val)) if unit == "%" else str(round(val))
        c.text(vx + D["PNL_VCHIP_W"] - 8, ry + 7, vt, rgb(A1[acc]), PT["ctl"], True, "ru")
        tx0, tw0 = D["PNL_TRACK_X"], D["PNL_TRACK_W"]
        ty0 = ry + D["PNL_TRK_Y"]
        c.rect(tx0, ty0 - 1, tw0, D["PNL_TRK_H"] + 2, rgb(CLR["TRACK_BD"]), 2, 4)
        c.rect(tx0 + 1, ty0, tw0 - 2, D["PNL_TRK_H"], rgb(CLR["TRACK"]), 3, 3)
        frac = (val - r["minV"]) / (r["maxV"] - r["minV"]) if r["maxV"] > r["minV"] else 0
        kw = D["PNL_KNOB_W"]
        knob = tx0 + round(frac * (tw0 - kw))
        c.rect(tx0 + 1, ty0, max(0, knob + kw // 2 - (tx0 + 1)), D["PNL_TRK_H"], rgb(A1[acc]), 3, 3)
        c.img("pnl_knob.bmp", knob, ty0 + D["PNL_TRK_H"] // 2 - kw // 2, kw, kw, 6)
        for t in range(D["PNL_TICK_N"]):
            c.rect(tx0 + round(t * (tw0 - 1) / (D["PNL_TICK_N"] - 1)), ry + D["PNL_TICK_Y"], 1, 3,
                   rgb(CLR["TICK"]), 2)

    # ── footer
    fy = HH + n * RH
    BP, BW, BH = D["PNL_BTN_PAD"], D["PNL_BTN_W"], D["PNL_BTN_H"]

    def foot(ftag, bx, label, primary, ico_name):
        c.rect(bx, fy + 10, BW, BH, rgb(CLR["FOOTBG"]), 2)
        c.img("pnl_btn_prim_%s.bmp" % aname if primary else "pnl_btn_ghost.bmp",
              bx - BP, fy + 10 - BP, BW + 2 * BP, BH + 2 * BP, 3)
        c.img("gl_%s_%s.bmp" % (ico_name, "i_" + aname) if primary else "gl_%s_m.bmp" % ico_name,
              bx + 12, fy + 16, D["PNL_GLYPH_CANVAS"], D["PNL_GLYPH_CANVAS"], 4)
        c.text(bx + 32, fy + 17, label, rgb(AINK[acc]) if primary else rgb(CLR["MUTED"]), PT["foot"], True)

    foot("rst", PAD, "Reset", False, "reset")
    foot("done", WEL - PAD - BW, "Done", True, "check")

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


def main():
    argv = [a for a in sys.argv[1:] if not a.startswith("--")]
    raster = "--raster" in sys.argv
    out = argv[0] if argv else os.path.join(ROOT, "panel_mt4_sim.html")
    cards = [c for c in (render_card(i) for i in range(14)) if c]

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

    html = """<!doctype html><meta charset="utf-8">
<title>Panel simulator &mdash; the cards as MetaTrader draws them</title>
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
the same point size (pt &times; 4/3 px) and the same anchor the MQL sets, but MT4 has its own
font stack. Treat the chrome as exact and the type as very close.</p>
<div class="wrap">
@@CARDS@@
</div>
""".replace("@@CARDS@@", "".join(body))

    open(out, "w", encoding="utf-8").write(html)
    print("wrote %s (%d cards, %d bitmaps)" % (out, len(cards), len(_CACHE)))
    return 0


SPECS = parse_spec_build()
DEFS = parse_set_def()

if __name__ == "__main__":
    sys.exit(main())
