# P-DRAW-INK / P-DRAW-09c / P-DRAW-09b / P-DRAW-75 / P-DRAW-74b splice (2026-10-04).
import sys

TBB = "Biotak/Toolbar_B.mqh"


def load(p):
    txt = open(p, "rb").read().decode("utf-8").replace("\r\n", "\n")
    if "\r" in txt:
        print("!! stray CR in " + p)
        sys.exit(1)
    return txt


def save(p, txt):
    open(p, "wb").write(txt.replace("\n", "\r\n").encode("utf-8"))


def sub(txt, old, new, tag):
    c = txt.count(old)
    if c != 1:
        print("!! %s matched %d times" % (tag, c))
        print(old[:240])
        sys.exit(1)
    return txt.replace(old, new, 1)


txt = load(TBB)

# ---------------------------------------------------------------- 1. the slots
E1_OLD = """#define DRAW_PRESET_MAX  6      // 3 built-in suggestions + 3 the user owns
#define DRAW_PRESET_BUILTIN 3   // slots 0..2 are the suggestions
"""
E1_NEW = """#define DRAW_PRESET_MAX  6      // 3 built-in suggestions + 3 the user owns
#define DRAW_PRESET_BUILTIN 3   // slots 0..2 are the suggestions
//--- P-DRAW-09c (2026-10-04) — THE LOOK OUTLIVES THE SESSION. «همیشه آخرین تغییرات
//--- روی ابجکت پیش‌فرض بشه و هر سری نیاز نباشه تنظیم بکن» — the kind memory already
//--- made the last look the default of the NEXT drawing of that kind; what it did not
//--- do was survive an attach, so the first fibo of every session was born factory
//--- fresh. The nine values pack into TWO exact doubles and ride the presets' own file
//--- in this reserved slot, which is OUTSIDE every preset band on purpose (so the
//--- band's own guard can never eat the row).
#define DRAW_LASTLOOK_SLOT 255
//--- P-DRAW-INK (2026-10-04) — THE ONE INK EVERY KIND SHARES. The kind's own colour
//--- answers «what did THIS kind last wear»; this answers the question the hand's own
//--- report asks («چرا رنگش پیش‌فرض که میکشم سفید هستش؟ آخرین تغییرات آبی بود»): which
//--- colour the LAST pick painted, whichever kind it painted. A kind that has no
//--- colour of its own takes it at birth (a first-ever fibo wears the blue the last
//--- trendline was). Its own reserved row, one below the look's.
#define DRAW_LASTINK_SLOT  254
"""
txt = sub(txt, E1_OLD, E1_NEW, "E1")

# ------------------------------------------------- 2. pack/unpack + save/load
E2_OLD = """void DrawPresetsSave()
{
   int h = FileOpen(DrawPresetPath(), FILE_WRITE | FILE_CSV | FILE_ANSI, ';');
   if(h == INVALID_HANDLE) return;
   for(int k = 1; k < DK_COUNT; k++)
      for(int i = DRAW_PRESET_BUILTIN; i < DRAW_PRESET_MAX; i++)
      {
         if(!s_dkPreset[k][i].used) continue;
         FileWrite(h, (int)k, i, s_dkPreset[k][i].name,
                   DoubleToString(DrawPresetPack(s_dkPreset[k][i]), 0));
      }
   FileClose(h);
}
"""
E2_NEW = """//--- P-DRAW-09c (2026-10-04) — THE LAST LOOK, PACKED EXACTLY. Two doubles carry the
//--- nine values of one kind's memory: word A holds the border's pair (colour 24 bits,
//--- width 3, style 3, fill 1, ray 2) plus the three appended looks (font 7, glyph 8,
//--- back 1) and a PRESENCE BIT at 33; word B holds the interior's colour (24 bits)
//--- and its own presence bit at 24. Nothing is ever a guess: `clrNONE` is -1 and
//--- `-1 & 0xFFFFFF` is WHITE, so the presence bit is what tells "no colour of its own"
//--- from a colour nobody chose (P-DRAW-75's rule, one file over).
double DrawStylePackA(const EDrawKind k)
{
   if(k <= DK_NONE || k >= DK_COUNT) return 0.0;
   long v = (long)((int)s_dkColor[k] & 0xFFFFFF);
   v += ((long)(s_dkWidth[k] & 0x7) << 24);
   v += ((long)(s_dkStyle[k] & 0x7) << 27);
   v += ((long)((s_dkFill[k] ? 1 : 0)) << 30);
   v += ((long)(s_dkRay[k] & 0x3) << 31);
   v += ((long)(((int)s_dkColor[k] >= 0) ? 1 : 0) << 33);
   v += ((long)(s_dkFont[k] & 0x7F) << 34);
   v += ((long)(s_dkGlyph[k] & 0xFF) << 41);
   v += ((long)((s_dkBack[k] ? 1 : 0)) << 49);
   return (double)v;
}
double DrawStylePackB(const EDrawKind k)
{
   if(k <= DK_NONE || k >= DK_COUNT) return 0.0;
   long v = (long)((int)s_dkFillClr[k] & 0xFFFFFF);
   v += ((long)(((int)s_dkFillClr[k] >= 0) ? 1 : 0) << 24);
   return (double)v;
}
//--- THE UNPACK — the other half of the SAME contract. Word B is 25 bits by design, so
//--- its own mask (`0x1FFFFFF`) is what keeps the presence bit and the colour in one
//--- read; word A's fields are read with the shifts its pack wrote, and a colour is
//--- returned only when the presence bit says there was one.
void DrawStyleUnpack(const EDrawKind k, const double rawA, const double rawB)
{
   if(k <= DK_NONE || k >= DK_COUNT) return;
   long a = (long)rawA;
   s_dkColor[k] = (((((a >> 33) & 0x1) != 0)) ? (color)(int)(a & 0xFFFFFF) : clrNONE);
   s_dkWidth[k] = (int)((a >> 24) & 0x7);
   s_dkStyle[k] = (int)((a >> 27) & 0x7);
   s_dkFill[k]  = (((a >> 30) & 0x1) != 0);
   s_dkRay[k]   = (int)((a >> 31) & 0x3);
   s_dkFont[k]  = (int)((a >> 34) & 0x7F);
   s_dkGlyph[k] = (int)((a >> 41) & 0xFF);
   s_dkBack[k]  = (((a >> 49) & 0x1) != 0);
   long b = (long)rawB;
   b &= 0x1FFFFFF;   // word B is 25 bits: 24 of colour + its own presence bit
   s_dkFillClr[k] = ((((b >> 24) & 0x1) != 0) ? (color)(int)(b & 0xFFFFFF) : clrNONE);
   s_dkValid[k] = true;
}

void DrawPresetsSave()
{
   int h = FileOpen(DrawPresetPath(), FILE_WRITE | FILE_CSV | FILE_ANSI, ';');
   if(h == INVALID_HANDLE) return;
   for(int k = 1; k < DK_COUNT; k++)
   {
      for(int i = DRAW_PRESET_BUILTIN; i < DRAW_PRESET_MAX; i++)
      {
         if(!s_dkPreset[k][i].used) continue;
         FileWrite(h, (int)k, i, s_dkPreset[k][i].name,
                   DoubleToString(DrawPresetPack(s_dkPreset[k][i]), 0));
      }
      //--- P-DRAW-09c: the kind's LAST LOOK rides the same file, in the reserved slot
      //--- (outside every preset band). A kind the user never styled writes nothing, so
      //--- the load can leave it factory-fresh (the test's own «nobody styled» case).
      if(!s_dkValid[k]) continue;
      FileWrite(h, (int)k, DRAW_LASTLOOK_SLOT,
                DoubleToString(DrawStylePackB(k), 0), DoubleToString(DrawStylePackA(k), 0));
   }
   //--- P-DRAW-INK: and the ONE ink every kind shares has its own row. It is not a
   //--- kind's look, so it does not ride a kind's slot: a single reserved row answers
   //--- the next attach's first drawing.
   if((int)s_dkAnyClr >= 0)
      FileWrite(h, 1, DRAW_LASTINK_SLOT, IntegerToString((int)s_dkAnyClr), "0");
   FileClose(h);
}
"""
txt = sub(txt, E2_OLD, E2_NEW, "E2")

# ------------------------------------------------------------- 3. the load
E3_OLD = """      if(FileIsEnding(h) && pk == \"\") break;
      if(k <= DK_NONE || k >= DK_COUNT) continue;
      if(i < DRAW_PRESET_BUILTIN || i >= DRAW_PRESET_MAX) continue;
"""
E3_NEW = """      if(FileIsEnding(h) && pk == \"\") break;
      //--- P-DRAW-09c / P-DRAW-INK: the two reserved rows are answered BEFORE the preset
      //--- bands reject them — 255 and 254 are outside every band ON PURPOSE, so a guard
      //--- read first would eat the very rows these features write.
      if(i == DRAW_LASTLOOK_SLOT) { DrawStyleUnpack(k, StringToDouble(pk), StringToDouble(nm)); continue; }
      if(i == DRAW_LASTINK_SLOT) { int ink = (int)StringToInteger(nm); if(ink >= 0) s_dkAnyClr = (color)ink; continue; }
      if(k <= DK_NONE || k >= DK_COUNT) continue;
      if(i < DRAW_PRESET_BUILTIN || i >= DRAW_PRESET_MAX) continue;
"""
txt = sub(txt, E3_OLD, E3_NEW, "E3")

# -------------------------------------------- 4. the create path (P-DRAW-75/INK)
E4_OLD = """   EDrawKind k = DrawKindOf(name);
   if(k == DK_NONE || !s_dkValid[k]) return false;   // never touched: leave the terminal's own look
   if(ObjectFind(0, name) < 0) return false;
   if((DrawKindCaps(k) & DRAW_CAP_COLOR) != 0)
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, s_dkColor[k]);
      if(DrawKindHasLevels(k)) DrawLevelsSetColor(name, s_dkColor[k]);
   }
"""
E4_NEW = """   EDrawKind k = DrawKindOf(name);
   if(k == DK_NONE) return false;   // a stranger: the terminal's own look, untouched
   if(ObjectFind(0, name) < 0) return false;
   //--- P-DRAW-INK (2026-10-04) — THE INK THE KIND HAS NO MEMORY OF. Reported on a
   //--- chart whose fibos had been given a width and a look but never a colour:
   //--- «چرا رنگش پیش‌فرض که میکشم سفید هستش؟ آخرین تغییرات آبی بود». The kind's own
   //--- colour is asked FIRST (P-DRAW-48/75); only a kind that has none takes the last
   //--- ink the hand picked ANYWHERE — so a fresh drawing wears the blue the last pick
   //--- painted, never the terminal's factory white.
   color want = s_dkColor[k];
   if((int)want < 0) want = s_dkAnyClr;
   if((DrawKindCaps(k) & DRAW_CAP_COLOR) != 0 && (int)want >= 0)
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, want);
      if(DrawKindHasLevels(k)) DrawLevelsSetColor(name, want);
   }
   //--- P-DRAW-INK: a kind the user has NEVER styled has exactly one thing of its own
   //--- to wear — the ink above. Its width, style, fill and ray were never chosen, so
   //--- they are left exactly as the terminal would have drawn them (P-DRAW-75).
   if(!s_dkValid[k]) return true;
"""
txt = sub(txt, E4_OLD, E4_NEW, "E4")

# ------------------------------------------------ 5. the colour write notes the ink
E5_OLD = """         s_dkColor[k] = c;
         break;
"""
E5_NEW = """         s_dkColor[k] = c;
         //--- P-DRAW-INK (2026-10-04): the ONE ink every kind shares is noted HERE,
         //--- where every pick arrives. The kind's own memory records what IT wore; this
         //--- records the last colour the HAND chose anywhere, so a kind with no colour
         //--- of its own can wear it at birth.
         if((int)c >= 0) s_dkAnyClr = c;
         break;
"""
txt = sub(txt, E5_OLD, E5_NEW, "E5")

# ------------------------------------------------ 6. the STYLE slot's looks (74b)
E6_OLD = """      case DRAW_SLOT_STYLE:
      {
         int st = (int)MathRound(v);
         if(st < 0) st = 0;
         if(st > (int)STYLE_DASHDOTDOT) st = (int)STYLE_DASHDOTDOT;
"""
E6_NEW = """      case DRAW_SLOT_STYLE:
      {
         int st = (int)MathRound(v);
         //--- P-DRAW-74b (2026-10-03) — THE FIBO'S LOOKS LIVE ABOVE THE NATIVE FIVE.
         //--- MT4's five styles end where chic begins: STYLE 5/6/7 means the pen's own
         //--- looks (FIBPEN_LOOK_NEON/CAPS/WASH), each a `[LKn]` tag beside the NATIVE
         //--- pair the terminal holds and painted by the pen's own followers. This is the
         //--- ONE writer that translates the pick: the tag first, then the native style
         //--- the look really draws with.
         int lk = 0;
         if(st > (int)STYLE_DASHDOTDOT && DrawKindHasLevels(k))
         {
            int cand = st - (int)STYLE_DASHDOTDOT;   // 5 -> 1, 6 -> 2, 7 -> 3
            if(cand >= FIBPEN_LOOK_NEON && cand <= FIBPEN_LOOK_WASH) lk = cand;
            if(lk > 0) FibPenLookSet(name, lk);
         }
         if(st < 0) st = 0;
         if(st > (int)STYLE_DASHDOTDOT) st = (int)STYLE_DASHDOTDOT;
         //--- the look's native half is what the terminal can actually draw; and a
         //--- NATIVE pick (0..4) means the look is off — one truth, never two.
         if(lk > 0) st = FibPenLookNative(lk);
         else if(DrawKindHasLevels(k)) FibPenLookDrop(name);
"""
txt = sub(txt, E6_OLD, E6_NEW, "E6")

# ------------------------------------------------ 7. the one writer persists
E7_OLD = """   s_dkValid[k] = true;
   return true;
}
"""
E7_NEW = """   s_dkValid[k] = true;
   //--- P-DRAW-09c (2026-10-04): the ONE slot writer persists what it just learned —
   //--- «همیشه آخرین تغییرات روی ابجکت پیش‌فرض بشه» is true only if the last change
   //--- survives the session. One write per user act; a still frame never reaches here.
   DrawPresetsSave();
   return true;
}
"""
txt = sub(txt, E7_OLD, E7_NEW, "E7")

# ------------------------------------------------ 8. the store is ONE (09b)
E8_OLD = """#define DRAW_SEL_MAX 64

static string s_dkSel[DRAW_SEL_MAX];
"""
E8_NEW = """// P-DRAW-09b-RETIRED (2026-10-03): THE STRIP SERVES ONE OBJECT. Reported: «مثلا من
// اگر دوتا فيبو داشته باشم بخوام رنگ يک شو عوض کنم روي ديگر هم اعمال ميشه» — two fibos,
// one colour tap, the second changed too. The writer was not the colour writer: this
// store walked the chart for every drawing of the held kind whose OBJPROP_SELECTED was
// true, and MT4 keeps that flag long after the gesture, so a Ctrl+click made hours
// earlier became a standing instruction. The store holds the held name and nothing else
// now, so every fan-out loop in the strip is gone by ARITHMETIC; «Apply to all <Kind>»
// stays the ONE explicit multi-object command (`DrawStyleApplyToKind`).
#define DRAW_SEL_MAX 1

static string s_dkSel[DRAW_SEL_MAX];
"""
txt = sub(txt, E8_OLD, E8_NEW, "E8")

E8B_OLD = """//--- SNAPSHOT: the terminal's selected drawings of THIS kind, the held one
//--- always in. Returns the group size (0 when `hold` is not a drawing of ours).
int DrawSelSnapshot(const string hold)
{
   DrawSelClear();
   if(hold == "" || (DrawIsIndicatorObject(hold) && !DrawIsHRay(hold) && !DrawIsPathSeg(hold))) return 0;   // P-HR-04/P-UI-136
   EDrawKind k = DrawKindOf(hold);
   if(k <= DK_NONE || k >= DK_COUNT) return 0;
   s_dkSel[0] = hold;
   s_dkSelN = 1;
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0 && s_dkSelN < DRAW_SEL_MAX; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(nm == "" || nm == hold) continue;
      if(DrawIsIndicatorObject(nm) && !DrawIsHRay(nm) && !DrawIsPathSeg(nm)) continue;   // P-HR-04/P-UI-136: rays and paths group too
      if(DrawKindOf(nm) != k) continue;
      if(!(bool)ObjectGetInteger(0, nm, OBJPROP_SELECTED)) continue;
      s_dkSel[s_dkSelN] = nm;
      s_dkSelN++;
   }
   return s_dkSelN;
}
"""
E8B_NEW = """//--- SNAPSHOT: THE SERVED NAME, and never a walk (P-DRAW-09b-RETIRED). The terminal's
//--- own selection was once the group, but `OBJPROP_SELECTED` outlives the gesture that
//--- set it, so «these drawings» was a statement from an hour ago. The served drawing is
//--- the one the hand opened, and the callers' loops keep their shape (`DrawSelCount` is
//--- 0 or 1), so no fan-out can run without a caller first writing a second name.
int DrawSelSnapshot(const string hold)
{
   DrawSelClear();
   if(hold == "" || (DrawIsIndicatorObject(hold) && !DrawIsHRay(hold) && !DrawIsPathSeg(hold))) return 0;   // P-HR-04/P-UI-136
   EDrawKind k = DrawKindOf(hold);
   if(k <= DK_NONE || k >= DK_COUNT) return 0;
   s_dkSel[0] = hold;
   s_dkSelN = 1;
   return s_dkSelN;
}
"""
txt = sub(txt, E8B_OLD, E8B_NEW, "E8B")

# ------------------------------------------------ 9. the count the label means
E9_OLD = """   return done;
}

// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-09b (2026-09-23) — THE GROUP: ONE TOOLBAR, MANY DRAWINGS.
"""
E9_NEW = """   return done;
}

//--- P-DRAW-09b-RETIRED (2026-10-03): HOW MANY DRAWINGS «Apply to all <Kind>» WILL
//--- REALLY TOUCH. The row's label used to print the SELECTION's size, so it promised
//--- «all 2 selected» while the act underneath reached every drawing of the kind. This is
//--- the walk `DrawStyleApplyToKind` performs, so the number and the act are one fact.
int DrawStyleKindCount(const string fromName)
{
   EDrawKind k = DrawKindOf(fromName);
   if(k == DK_NONE) return 0;
   int n = 0;
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(nm == \"\" || nm == fromName || DrawIsIndicatorObject(nm)) continue;
      if(DrawKindOf(nm) != k) continue;
      n++;
   }
   return n;
}

// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-09b (2026-09-23) — THE GROUP: ONE TOOLBAR, MANY DRAWINGS.
"""
txt = sub(txt, E9_OLD, E9_NEW, "E9")

save(TBB, txt)
print("ok Toolbar_B.mqh: 9 edits applied")
