# P-DRAW-74b follow-up (2026-10-04): a styled THICK fibo must keep its stack.
#   (A) the STYLE slot must not erase the level widths BEFORE the pen can read them;
#   (B) the pair coercion must not force a pen-owned kind back to STYLE_SOLID.
import sys

TBB = "Biotak/Toolbar_B.mqh"


def load(p):
    t = open(p, "rb").read().decode("utf-8")
    if t.count("\r\n") == 0:
        print("!! %s is not CRLF" % p)
        sys.exit(1)
    return t


def save(p, t):
    open(p, "wb").write(t.encode("utf-8"))


def sub(t, old, new, tag):
    c = t.count(old)
    if c != 1:
        print("!! %s matched %d times" % (tag, c))
        print(old[:240])
        sys.exit(1)
    return t.replace(old, new, 1)


t = load(TBB)

# ---------------------------------------------------------------- (A) the STYLE slot
A_OLD = (
    "         if(st != (int)STYLE_SOLID)\r\n"
    "         {\r\n"
    "            if((int)ObjectGetInteger(0, name, OBJPROP_WIDTH) != DRAW_WIDTH_MIN)\r\n"
    "            {\r\n"
    "               ObjectSetInteger(0, name, OBJPROP_WIDTH, DRAW_WIDTH_MIN);\r\n"
    "               if(DrawKindHasLevels(k)) DrawLevelsSetWidth(name, DRAW_WIDTH_MIN);\r\n"
    "            }\r\n"
    "            if(!DrawIsHRay(name) && !DrawIsPathSeg(name)) s_dkWidth[k] = DRAW_WIDTH_MIN;\r\n"
    "         }\r\n"
)
A_NEW = (
    "         if(st != (int)STYLE_SOLID)\r\n"
    "         {\r\n"
    "            if((int)ObjectGetInteger(0, name, OBJPROP_WIDTH) != DRAW_WIDTH_MIN)\r\n"
    "               ObjectSetInteger(0, name, OBJPROP_WIDTH, DRAW_WIDTH_MIN);\r\n"
    "            //--- P-DRAW-74b (2026-10-04) — ON A PEN KIND THE WIDTH LIVES IN THE STACK.\r\n"
    "            //--- While no stack exists, the LEVEL widths ARE the logical width\r\n"
    "            //--- (`FibPenLogicalWidth` reads them), and `FibPenSync` demotes them to the\r\n"
    "            //--- visible 1 itself — AFTER it has read the logical one. Folding them here,\r\n"
    "            //--- before the style is even set, erased that memory one write early: the\r\n"
    "            //--- pen then read 1, built nothing and the level came out a plain 1 px dash,\r\n"
    "            //--- i.e. «استایل‌ها روی ضخامت‌های بزرگ اعمال نمی‌شد». Only the OBJECT's own\r\n"
    "            //--- width is folded for these kinds; their levels are the pen's business.\r\n"
    "            bool penKind = (k == DK_FIBO || k == DK_FIBOFAN);\r\n"
    "            if(!penKind) DrawLevelsSetWidth(name, DRAW_WIDTH_MIN);\r\n"
    "            //--- ...and the kind's remembered WIDTH is the LOGICAL one on a pen kind, so\r\n"
    "            //--- a dash pick must not fold it to 1 either (the next fibo would be born\r\n"
    "            //--- thin, losing the thickness the user chose). Other kinds keep the law:\r\n"
    "            //--- a dash is a one-pixel pen.\r\n"
    "            if(!DrawIsHRay(name) && !DrawIsPathSeg(name) && !penKind) s_dkWidth[k] = DRAW_WIDTH_MIN;\r\n"
    "         }\r\n"
)
t = sub(t, A_OLD, A_NEW, "A")

# ---------------------------------------------------------- (B) the pair coercion
B_OLD = (
    "bool DrawStylePairCoerce(const string name)\r\n"
    "{\r\n"
    "   if(name == \"\" || ObjectFind(0, name) < 0) return false;\r\n"
    "   EDrawKind k = DrawKindOf(name);\r\n"
    "   if(k == DK_NONE) return false;\r\n"
    "   int w = (int)ObjectGetInteger(0, name, OBJPROP_WIDTH);\r\n"
)
B_NEW = (
    "bool DrawStylePairCoerce(const string name)\r\n"
    "{\r\n"
    "   if(name == \"\" || ObjectFind(0, name) < 0) return false;\r\n"
    "   EDrawKind k = DrawKindOf(name);\r\n"
    "   if(k == DK_NONE) return false;\r\n"
    "   //--- P-DRAW-74b (2026-10-04) — A PEN KIND IS NOT THIS FUNCTION'S OBJECT. Its drawn\r\n"
    "   //--- pair lives on the LEVELS (`OBJPROP_LEVELWIDTH`/`LEVELSTYLE`), and the object's\r\n"
    "   //--- own pair is only a MEMORY. Reading that memory here meant a thick styled fibo\r\n"
    "   //--- was forced back to STYLE_SOLID — every level with it — the moment the strip\r\n"
    "   //--- opened or the chart repainted (`DrawStrip_Paint` calls this on every open), so\r\n"
    "   //--- the stack died and the style vanished: the same report as (A), one seat over.\r\n"
    "   //--- `FibPenSync` owns the visible pair for these kinds — a styled level is drawn at\r\n"
    "   //--- width 1 with the thickness carried by the stack — so the pair is legal by\r\n"
    "   //--- construction and this coercion has nothing true to say about it.\r\n"
    "   if(k == DK_FIBO || k == DK_FIBOFAN) return false;\r\n"
    "   int w = (int)ObjectGetInteger(0, name, OBJPROP_WIDTH);\r\n"
)
t = sub(t, B_OLD, B_NEW, "B")

save(TBB, t)
print("ok Toolbar_B.mqh: (A)+(B) applied")
