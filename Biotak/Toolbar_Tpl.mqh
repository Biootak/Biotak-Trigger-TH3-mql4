// Toolbar_Tpl.mqh - P-SIZE-1500/P-DRAW-132 (2026-10-18): the drawing TEMPLATE RACK -
// the named store, its packers and its ONE file - split out of Toolbar_B.mqh, which had
// crossed the 1500-line ceiling. Same owner P-DRAW-02’s preset system had; the slot
// engine (DrawSlotRead/Write, the style memory) stays in Toolbar_B. It is included in
// DrawToolbar.mqh ABOVE Toolbar_B: DrawSlotWrite reads s_dkTplHold (the apply batch's
// hold) which lives here, and every function here calls Toolbar_B’s own forward.
#ifndef TOOLBAR_TPL_MQH
#define TOOLBAR_TPL_MQH

// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-132 (2026-10-18) — THE TEMPLATE LAYER, REWRITTEN. «میخوام تمپلت های
// مختلف رو سیو کنم و به راحیت هر کدوم خواستم فعال کنم بشه دیگه مثل تردینگ ویو
// معمار شو از نو بنویس و معماری قبلی رو حذف کن». What shipped as P-DRAW-02 was a
// fixed six-slot rack: three seeded suggestions the user could never rename or
// remove, three anonymous user slots filled in order, and a full rack that
// silently overwrote its newest row. The ask is the TradingView shape: NAMED
// templates per tool — save the current look under any name, apply any of them
// from one list, delete any of them (the seeds are ordinary first-run rows now).
//
// THE MODEL. Every kind owns up to `DRAW_TPL_MAX` named templates in the order
// the user made them. One template is the WHOLE look — colour, width, style,
// fill, ray, caption size, arrow glyph, layer and interior colour, nine values
// packed into two exact doubles. Saving under an existing name REPLACES it
// (case-insensitive); a new name APPENDS; a FULL rack REFUSES, with a witness,
// instead of silently eating the oldest template; a delete COMPACTS the list, so
// a row's index is its row. Applying one writes the whole look onto the drawing
// and LEARNS it — the next drawing of that kind wears it (P-DRAW-01's "last
// change saved", one level up).
//
// WHY PER KIND AND NOT GLOBAL. A fibo's level family and a rectangle's fill are
// different animals; a shared list would offer a rectangle a look it cannot
// wear. Per kind, every offered template is always applicable — the list shows
// them all without a single disabled row.
// ══════════════════════════════════════════════════════════════════════════
#define DRAW_TPL_MAX 12        // the ceiling per kind — two pages of six in the lists
#define DRAW_TPL_PAGE 6        // rows one page of the more-popover / Look tab shows
#define DRAW_TPL_FILE "Biotak\\DrawTemplates.csv"    // ONE file, global, not per chart
#define DRAW_TPL_LEGACY "Biotak\\DrawPresets.csv"    // P-DRAW-02's file: read ONCE, migrated, deleted
//--- P-DRAW-135 (2026-10-18) — «با همه چیزش ذخیره بشه». For the level family (the
//--- fibos) the LEVELS ARE THE DRAWING (P-DRAW-132's own words), and the nine-value
//--- look never carried them: a save stamped a default fibo onto every chart. The
//--- level set now rides a row of its OWN, the encoded string in that row's `name`
//--- column at index 100+slot — clear of the template band (0..11) and of the two
//--- reserved seats (255/254), so neither a band guard nor a reserved row can eat
//--- it, and a file without these rows reads exactly like today's.
#define DRAW_TPL_LVL_ROW 100
//--- P-DRAW-09c (2026-10-04) — THE LOOK OUTLIVES THE SESSION. «همیشه آخرین تغییرات
//--- روی ابجکت پیش‌فرض بشه و هر سری نیاز نباشه تنظیم بکن» — the kind memory already
//--- made the last look the default of the NEXT drawing of that kind; what it did not
//--- do was survive an attach, so the first fibo of every session was born factory
//--- fresh. The nine values pack into TWO exact doubles and ride the templates' own
//--- file in this reserved slot, which is OUTSIDE every template band on purpose (so
//--- the band's own guard can never eat the row).
#define DRAW_LASTLOOK_SLOT 255
//--- P-DRAW-INK (2026-10-04) — THE ONE INK EVERY KIND SHARES. The kind's own colour
//--- answers «what did THIS kind last wear»; this answers the question the hand's own
//--- report asks («چرا رنگش پیش‌فرض که میکشم سفید هستش؟ آخرین تغییرات آبی بود»): which
//--- colour the LAST pick painted, whichever kind it painted. A kind that has no
//--- colour of its own takes it at birth (a first-ever fibo wears the blue the last
//--- trendline was). Its own reserved row, one below the look's.
#define DRAW_LASTINK_SLOT  254

//--- THE LOOK, NAMED — the nine values one template carries and the two exact
//--- doubles they pack into. The bit map is P-DRAW-09c's, kept verbatim so every
//--- row a previous build wrote is still read: word A holds colour 24 bits, width
//--- 3, style 3, fill 1, ray 2, then font 7 at 34, glyph 8 at 41, back 1 at 49,
//--- and the colour's PRESENCE BIT at 33; word B holds the interior's colour in
//--- 24 bits plus its own presence bit at 24. `clrNONE` is -1 and `-1 & 0xFFFFFF`
//--- is WHITE, so presence — never a guess — tells "no colour of its own" from a
//--- colour nobody chose (P-DRAW-75's rule, one file over).
struct DrawLook
{
   color clr;
   int   width;
   int   style;
   bool  fill;
   int   ray;
   int   font;
   int   glyph;
   bool  back;
   color fillClr;
};

double DrawLookPackA(const DrawLook &L)
{
   long v = (long)((int)L.clr & 0xFFFFFF);
   v += ((long)(L.width & 0x7) << 24);
   v += ((long)(L.style & 0x7) << 27);
   v += ((long)(L.fill ? 1 : 0) << 30);
   v += ((long)(L.ray & 0x3) << 31);
   v += ((long)(((int)L.clr >= 0) ? 1 : 0) << 33);
   v += ((long)(L.font & 0x7F) << 34);
   v += ((long)(L.glyph & 0xFF) << 41);
   v += ((long)(L.back ? 1 : 0) << 49);
   return (double)v;
}
double DrawLookPackB(const DrawLook &L)
{
   long v = (long)((int)L.fillClr & 0xFFFFFF);
   v += ((long)(((int)L.fillClr >= 0) ? 1 : 0) << 24);
   return (double)v;
}
void DrawLookUnpackA(const double raw, DrawLook &L)
{
   long a = (long)raw;
   L.clr   = ((((a >> 33) & 0x1) != 0) ? (color)(int)(a & 0xFFFFFF) : clrNONE);
   L.width = (int)((a >> 24) & 0x7);
   L.style = (int)((a >> 27) & 0x7);
   L.fill  = (((a >> 30) & 0x1) != 0);
   L.ray   = (int)((a >> 31) & 0x3);
   L.font  = (int)((a >> 34) & 0x7F);
   L.glyph = (int)((a >> 41) & 0xFF);
   L.back  = (((a >> 49) & 0x1) != 0);
}
void DrawLookUnpackB(const double raw, DrawLook &L)
{
   long b = (long)raw;
   b &= 0x1FFFFFF;   // word B is 25 bits: 24 of colour + its own presence bit
   L.fillClr = ((((b >> 24) & 0x1) != 0) ? (color)(int)(b & 0xFFFFFF) : clrNONE);
}

//--- P-DRAW-135 — THE LEVEL SET, ENCODED AND DECODED. The encoder reads the object's
//--- own truth exactly as `DrawStripLevelsCollect` does (raw ratios — MT4's real
//--- storage — and the remembered width via `FibPenLogicalWidth`, P-DRAW-74b), one
//--- record per level: `value:colour:width:style:text`, records joined by '|'. The
//--- text is the user's own word, so the two separators a split can never survive
//--- (';' breaks the CSV line, '|' breaks the record walk) are traded for safe ink;
//--- ':' MAY ride a note because the parser takes the text as the REST of a record.
string DrawTplLevelsOf(const string name)
{
   if(name == "" || ObjectFind(0, name) < 0) return "";
   if(!DrawKindHasLevels(DrawKindOf(name))) return "";
   int n = (int)ObjectGetInteger(0, name, OBJPROP_LEVELS);
   if(n <= 0) return "";
   if(n > 32) n = 32;
   string out = "";
   for(int i = 0; i < n; i++)
   {
      double v = ObjectGetDouble(0, name, OBJPROP_LEVELVALUE, i);
      if(!MathIsValidNumber(v)) continue;
      string t = ObjectGetString(0, name, OBJPROP_LEVELTEXT, i);
      StringReplace(t, ";", ",");
      StringReplace(t, "|", "/");
      StringReplace(t, "\n", " ");
      StringReplace(t, "\r", " ");
      if(out != "") out += "|";
      out += DoubleToString(v, 6) + ":" +
             IntegerToString((int)ObjectGetInteger(0, name, OBJPROP_LEVELCOLOR, i)) + ":" +
             IntegerToString(FibPenLogicalWidth(name, i)) + ":" +
             IntegerToString((int)ObjectGetInteger(0, name, OBJPROP_LEVELSTYLE, i)) + ":" + t;
   }
   return out;
}
bool DrawTplLevelsTo(const string name, const string enc)
{
   if(name == "" || enc == "" || ObjectFind(0, name) < 0) return false;
   if(!DrawKindHasLevels(DrawKindOf(name))) return false;
   double vv[32]; int cc[32], ww[32], ss[32]; string tt[32];
   ArrayInitialize(vv, 0.0); ArrayInitialize(cc, 0); ArrayInitialize(ww, 0); ArrayInitialize(ss, 0);
   int n = 0;
   int pos = 0, len = StringLen(enc);
   while(pos < len && n < 32)
   {
      int bar = StringFind(enc, "|", pos);
      string rec = (bar < 0 ? StringSubstr(enc, pos) : StringSubstr(enc, pos, bar - pos));
      int p1 = StringFind(rec, ":");
      int p2 = (p1 >= 0 ? StringFind(rec, ":", p1 + 1) : -1);
      int p3 = (p2 >= 0 ? StringFind(rec, ":", p2 + 1) : -1);
      int p4 = (p3 >= 0 ? StringFind(rec, ":", p3 + 1) : -1);
      if(p4 > 0)
      {
         double v = StringToDouble(StringSubstr(rec, 0, p1));
         if(MathIsValidNumber(v))
         {
            vv[n] = v;
            cc[n] = (int)StringToInteger(StringSubstr(rec, p1 + 1, p2 - p1 - 1));
            ww[n] = (int)StringToInteger(StringSubstr(rec, p2 + 1, p3 - p2 - 1));
            ss[n] = (int)StringToInteger(StringSubstr(rec, p3 + 1, p4 - p3 - 1));
            tt[n] = StringSubstr(rec, p4 + 1);
            n++;
         }
      }
      if(bar < 0) break;
      pos = bar + 1;
   }
   if(n <= 0) return false;
   FibPenTagDrop(name);   // P-DRAW-74b: the written set IS the truth — the memory is spent
   ObjectSetInteger(0, name, OBJPROP_LEVELS, n);
   for(int i = 0; i < n; i++)
   {
      ObjectSetDouble(0, name, OBJPROP_LEVELVALUE, i, vv[i]);
      ObjectSetInteger(0, name, OBJPROP_LEVELCOLOR, i, cc[i]);
      ObjectSetInteger(0, name, OBJPROP_LEVELWIDTH, i, ww[i]);
      ObjectSetInteger(0, name, OBJPROP_LEVELSTYLE, i, ss[i]);
      ObjectSetString(0, name, OBJPROP_LEVELTEXT, i, tt[i]);
   }
   FibPenSync(name, false);   // P-DRAW-74b: the pair converges on the new truth
   return true;
}

//--- ONE NAMED TEMPLATE: its two packed words and the user's own word for it —
//--- the NAME is why the store is a FILE (P-DRAW-07: a GV holds a double, so a
//--- label had nowhere to go and every user slot came back "My 1").
struct DrawTpl
{
   bool   used;
   string name;
   double packA;
   double packB;
   string lvl;   // P-DRAW-135: the level set, encoded — "" = a template that never carried one
};
static DrawTpl s_dkTpl[DK_COUNT][DRAW_TPL_MAX];

//--- P-DRAW-132: WHILE THIS IS ABOVE ZERO `DrawSlotWrite` does NOT save. One
//--- APPLY writes five to nine slots and would otherwise pay one full-file pass
//--- per slot; the applier raises it, writes the whole look, lowers it and saves
//--- ONCE. Zero cost on every other path — a write outside an apply still saves.
static int s_dkTplHold = 0;

//--- rows a kind really carries (a delete COMPACTS, so they are 0..n-1 always).
int DrawTplCount(const EDrawKind k)
{
   if(k <= DK_NONE || k >= DK_COUNT) return 0;
   int n = 0;
   for(int i = 0; i < DRAW_TPL_MAX; i++) if(s_dkTpl[k][i].used) n++;
   return n;
}
string DrawTplName(const EDrawKind k, const int slot)
{
   if(k <= DK_NONE || k >= DK_COUNT) return "";
   if(slot < 0 || slot >= DRAW_TPL_MAX) return "";
   return s_dkTpl[k][slot].used ? s_dkTpl[k][slot].name : "";
}
//--- the row whose name is `nm`, case-insensitively — the saver and the remover
//--- both want the user's intent, not the bytes the keyboard produced. -1 = none.
int DrawTplIndex(const EDrawKind k, const string nm)
{
   if(k <= DK_NONE || k >= DK_COUNT || nm == "") return -1;
   int n = DrawTplCount(k);
   for(int i = 0; i < n; i++)
      if(StringCompare(s_dkTpl[k][i].name, nm, false) == 0) return i;
   return -1;
}
//--- PUT — the ONE writer of the rack. Same name (case-insensitive) REPLACES in
//--- place; a new name APPENDS; a FULL rack refuses (0) instead of silently
//--- overwriting the oldest template the user still owns. 1 = added, 2 = replaced.
int DrawTplPut(const EDrawKind k, const string nm, const DrawLook &L, const string lvls = "")
{
   if(k <= DK_NONE || k >= DK_COUNT || nm == "") return 0;
   int at = DrawTplIndex(k, nm);
   int res = 2;
   if(at < 0)
   {
      if(DrawTplCount(k) >= DRAW_TPL_MAX) return 0;
      at = DrawTplCount(k);
      s_dkTpl[k][at].used = true;
      s_dkTpl[k][at].name = nm;
      res = 1;
   }
   s_dkTpl[k][at].packA = DrawLookPackA(L);
   s_dkTpl[k][at].packB = DrawLookPackB(L);
   s_dkTpl[k][at].lvl   = lvls;   // P-DRAW-135: a re-save replaces the level set with the new one
   return res;
}

//--- THE SEEDS. Three per kind family, chosen to be the three looks a trader
//--- actually reaches for: the plain one, the loud one, and the quiet one. They
//--- are ordinary templates — written through `DrawTplPut`, so the user renames
//--- one by saving over it and deletes one like any other row. They are seeded
//--- ONLY when the file does not exist yet; after that the file is the truth, so
//--- a deleted seed stays deleted (P-DRAW-132).
void DrawTplSeedOne(const EDrawKind k, const string nm, const color c,
                    const int w, const int st, const bool fl, const int ry)
{
   DrawLook L;
   L.clr     = c;
   L.width   = w;
   L.style   = st;
   L.fill    = fl;
   L.ray     = ry;
   L.font    = DRAW_FONT_DEF;
   L.glyph   = 0;
   L.back    = false;
   L.fillClr = clrNONE;
   DrawTplPut(k, nm, L);
}
void DrawTplSeed()
{
   //--- lines and rays: the workhorses
   DrawTplSeedOne(DK_LINE, "Trend",   clrDodgerBlue, 1, (int)STYLE_SOLID,     false, 0);
   DrawTplSeedOne(DK_LINE, "Ray",     clrOrangeRed,  1, (int)STYLE_SOLID,     false, 1);
   DrawTplSeedOne(DK_LINE, "Quiet",   clrGray,       1, (int)STYLE_DOT,       false, 0);
   //--- the horizontal/vertical levels: two looks, one for marking, one for reading
   DrawTplSeedOne(DK_HLINE, "Level",  clrGold,       2, (int)STYLE_SOLID,     false, 0);
   DrawTplSeedOne(DK_HLINE, "Marker", clrRed,        1, (int)STYLE_DASH,      false, 0);
   DrawTplSeedOne(DK_HLINE, "Quiet",  clrSilver,     1, (int)STYLE_DOT,       false, 0);
   DrawTplSeedOne(DK_VLINE, "Session",clrGold,       1, (int)STYLE_DASH,      false, 0);
   DrawTplSeedOne(DK_VLINE, "Marker", clrRed,        1, (int)STYLE_SOLID,     false, 0);
   //--- the fibo family: the levels ARE the object, so the templates carry the
   //--- LEVEL look (colour/style/width) that MT4 makes the user set level by level
   DrawTplSeedOne(DK_FIBO, "Classic", clrGold,       1, (int)STYLE_SOLID,     false, 0);
   DrawTplSeedOne(DK_FIBO, "Zones",   clrOrange,     1, (int)STYLE_DASH,      false, 0);
   DrawTplSeedOne(DK_FIBO, "Quiet",   clrDimGray,    1, (int)STYLE_DOT,       false, 0);
   DrawTplSeedOne(DK_FIBOFAN, "Classic", clrGold,    1, (int)STYLE_SOLID,     false, 0);
   DrawTplSeedOne(DK_FIBOFAN, "Zones",   clrOrange,  1, (int)STYLE_DASH,      false, 0);
   DrawTplSeedOne(DK_FIBOCHAN, "Classic", clrGold,   1, (int)STYLE_SOLID,     false, 0);
   DrawTplSeedOne(DK_FIBOCHAN, "Filled",  clrGold,   1, (int)STYLE_SOLID,     true,  0);
   DrawTplSeedOne(DK_EXPANSION, "Classic", clrGold,  1, (int)STYLE_SOLID,     false, 0);
   //--- the boxes: the user's own example («چند باکس پرکاربرد»)
   DrawTplSeedOne(DK_RECT, "Box",     clrDodgerBlue, 1, (int)STYLE_SOLID,     false, 0);
   DrawTplSeedOne(DK_RECT, "Zone",    clrTeal,       1, (int)STYLE_DASH,      true,  0);
   DrawTplSeedOne(DK_RECT, "Demand",  clrCrimson,    1, (int)STYLE_SOLID,     true,  0);
   DrawTplSeedOne(DK_TRIANGLE, "Wedge", clrDodgerBlue, 1, (int)STYLE_SOLID,   true,  0);
   DrawTplSeedOne(DK_TRIANGLE, "Quiet", clrGray,     1, (int)STYLE_DASH,      false, 0);
   DrawTplSeedOne(DK_ELLIPSE, "Cycle", clrDodgerBlue, 1, (int)STYLE_SOLID,    false, 0);
   DrawTplSeedOne(DK_CHANNEL, "Channel", clrDodgerBlue, 1, (int)STYLE_SOLID,  false, 0);
   DrawTplSeedOne(DK_CHANNEL, "Quiet",   clrGray,     1, (int)STYLE_DASH,     false, 0);
   DrawTplSeedOne(DK_GANN, "Gann",    clrGold,       1, (int)STYLE_SOLID,     false, 0);
   DrawTplSeedOne(DK_PITCHFORK, "Fork", clrDodgerBlue, 1, (int)STYLE_SOLID,   false, 0);
   DrawTplSeedOne(DK_ARROW, "Mark",   clrRed,        1, (int)STYLE_SOLID,     false, 0);
   DrawTplSeedOne(DK_TEXT, "Note",    clrWhite,      1, (int)STYLE_SOLID,     false, 0);
}

//--- ONE TAP — the whole look (all nine values the kind can wear) onto the object
//--- AND into the kind's memory. The template is the FULL look; each write goes
//--- through its slot owner, guarded by the kind's caps exactly like the picker
//--- (a value the kind cannot wear is not written, never truncated), and the
//--- interior colour goes FIRST so a fill routed to a child is born with its
//--- colour already on the drawing (P-DRAW-64). `s_dkTplHold` batches the nine
//--- per-write saves into ONE file pass.
bool DrawTplApply(const string name, const int slot)
{
   if(name == "" || ObjectFind(0, name) < 0) return false;
   EDrawKind k = DrawKindOf(name);
   if(k == DK_NONE || slot < 0 || slot >= DRAW_TPL_MAX) return false;
   if(!s_dkTpl[k][slot].used) return false;
   DrawLook L;
   DrawLookUnpackA(s_dkTpl[k][slot].packA, L);
   DrawLookUnpackB(s_dkTpl[k][slot].packB, L);
   s_dkTplHold++;
   if((int)L.clr >= 0)
      DrawSlotWrite(name, DRAW_SLOT_COLOR, (double)(int)L.clr);
   DrawSlotWrite(name, DRAW_SLOT_WIDTH, (double)L.width);
   DrawSlotWrite(name, DRAW_SLOT_STYLE, (double)L.style);
   if((int)L.fillClr >= 0 && DrawSlotAvailable(k, DRAW_SLOT_FILLCLR))
      DrawSlotWrite(name, DRAW_SLOT_FILLCLR, (double)(int)L.fillClr);
   if(DrawSlotAvailable(k, DRAW_SLOT_FILL))
      DrawSlotWrite(name, DRAW_SLOT_FILL, L.fill ? 1.0 : 0.0);
   if(DrawSlotAvailable(k, DRAW_SLOT_RAY))
      DrawSlotWrite(name, DRAW_SLOT_RAY, (double)L.ray);
   if(DrawSlotAvailable(k, DRAW_SLOT_FONT))
      DrawSlotWrite(name, DRAW_SLOT_FONT, (double)L.font);
   if(DrawSlotAvailable(k, DRAW_SLOT_GLYPH))
      DrawSlotWrite(name, DRAW_SLOT_GLYPH, (double)L.glyph);
   if(DrawSlotAvailable(k, DRAW_SLOT_BACK))
      DrawSlotWrite(name, DRAW_SLOT_BACK, L.back ? 1.0 : 0.0);
   //--- P-DRAW-135: the level family's own truth rides LAST — after the slot writes
   //--- (whose colour/width/style land on ALL levels), so the template's exact
   //--- per-level rows win. A template without a level set leaves the target's alone.
   if(s_dkTpl[k][slot].lvl != "")
      DrawTplLevelsTo(name, s_dkTpl[k][slot].lvl);
   s_dkTplHold--;
   DrawTplSave();
   return true;
}

//--- «پاکش کن» — one row goes and the list COMPACTS: the rows after the hole move
//--- down, so every index the strip holds (the current-row mark) stays a row, not
//--- a slot. The seeds are ordinary rows now — deleting "Classic" is allowed and
//--- it comes back only for a user with no file at all (P-DRAW-132).
bool DrawTplDelete(const EDrawKind k, const int slot)
{
   if(k <= DK_NONE || k >= DK_COUNT) return false;
   int n = DrawTplCount(k);
   if(slot < 0 || slot >= n) return false;
   for(int i = slot; i < n - 1; i++)
   {
      s_dkTpl[k][i].used  = s_dkTpl[k][i + 1].used;
      s_dkTpl[k][i].name  = s_dkTpl[k][i + 1].name;
      s_dkTpl[k][i].packA = s_dkTpl[k][i + 1].packA;
      s_dkTpl[k][i].packB = s_dkTpl[k][i + 1].packB;
      s_dkTpl[k][i].lvl   = s_dkTpl[k][i + 1].lvl;   // P-DRAW-135: the level set moves with its row
   }
   s_dkTpl[k][n - 1].used  = false;
   s_dkTpl[k][n - 1].name  = "";
   s_dkTpl[k][n - 1].packA = 0.0;
   s_dkTpl[k][n - 1].packB = 0.0;
   s_dkTpl[k][n - 1].lvl   = "";
   DrawTplSave();
   return true;
}

//--- «ذخیره به عنوان تمپلیت» — the object's CURRENT look under the user's NAME.
//--- Same name (case-insensitively) replaces; empty name becomes "My <n>"; a full
//--- rack REFUSES (0) instead of silently eating the oldest row. Capture and
//--- persist are ONE act (P-DRAW-08b kept): a saved template that is not written
//--- is a template the user loses on the next attach. 1 = added, 2 = replaced.
int DrawTplSaveAs(const string name, const string label)
{
   if(name == "" || ObjectFind(0, name) < 0) return 0;
   EDrawKind k = DrawKindOf(name);
   if(k == DK_NONE) return 0;
   DrawStylePairCoerce(name);   // P-DRAW-74: never learn an illegal pair from the terminal dialog
   DrawLook L;
   L.clr     = (color)(int)DrawSlotRead(name, DRAW_SLOT_COLOR);
   L.width   = (int)DrawSlotRead(name, DRAW_SLOT_WIDTH);
   L.style   = (int)DrawSlotRead(name, DRAW_SLOT_STYLE);
   L.fill    = (DrawSlotRead(name, DRAW_SLOT_FILL) > 0.5);
   L.ray     = (int)DrawSlotRead(name, DRAW_SLOT_RAY);
   L.font    = (int)DrawSlotRead(name, DRAW_SLOT_FONT);
   L.glyph   = (int)DrawSlotRead(name, DRAW_SLOT_GLYPH);
   L.back    = (DrawSlotRead(name, DRAW_SLOT_BACK) > 0.5);
   L.fillClr = (color)(int)DrawSlotRead(name, DRAW_SLOT_FILLCLR);
   string nm = label;
   if(nm == "") nm = "My " + IntegerToString(DrawTplCount(k) + 1);
   //--- P-DRAW-135: the capture is the WHOLE look — the level family's own set rides
   //--- with the nine slot values («با همه چیزش ذخیره بشه»), so a template stamps a
   //--- whole fibo on any chart, on any pair. Non-level kinds encode "".
   string lv = DrawTplLevelsOf(name);
   int res = DrawTplPut(k, nm, L, lv);
   if(res > 0) DrawTplSave();
   return res;
}

//--- P-DRAW-76: `DrawPresetApplyToKind` (a chart-wide walk per apply) is DELETED. P-DRAW-03's
//--- "one look, every drawing of the kind" is live as `DrawStyleApplyToKind` (the popover's
//--- APPLY-ALL row), and a template reaches a whole GROUP through the strip's own selection loop
//--- (`DrawStripTplApplyGroup` -> `DrawTplApply` per member). Two owners of one act was
//--- the defect, and this one had no caller in any commit.

// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-07 — THE TEMPLATES LIVE IN A FILE, BECAUSE A NAME IS NOT A NUMBER.
// (Kept by P-DRAW-132; the store it serves is the named rack above.)
//
// P-DRAW-05 stored one slot per GlobalVariable and hit the terminal's own wall:
// a GV holds a DOUBLE, so the user's label («My Box», «Supply 4H») had nowhere
// to go and every user slot came back as "My 1". That is the shape of limit this
// project refuses to ship: a template the user cannot NAME is a template they
// cannot find — exactly the ceiling MT4's own dialog has, where a look can only
// be "the last one" and never "my demand box".
//
// So the store is a FILE. MQL4's file API carries strings, and the project
// already keeps persistent state in files (the base-price history), so this is
// the codebase's own language, not a new one:
//
//   MQL4/Files/Biotak/DrawTemplates.csv    (ONE file, GLOBAL, not per chart)
//   kind ; row ; name ; packed-A ; packed-B
//
// WHY ONE GLOBAL FILE AND NOT ONE PER CHART: a template is the USER's look, not
// the chart's — «چند نوع فیبو که هر بار لازم نباشه از نو تنظیم بکنه» is a
// statement about the trader, and the same fibo look belongs on every chart they
// open. The chart id stays out of the name for that reason.
//
// The look is TWO exact doubles (the bit map lives with the packers above), so a
// line is five fields and the whole file is a few hundred bytes. Rows 255 and
// 254 are RESERVED inside the same file (P-DRAW-09c / P-DRAW-INK) and are read
// BEFORE any band guard — a guard read first would eat the very rows these
// features write (P-UI-133's lesson, one file over).
//
// WRITES ARE RARE AND GUARDED: a save happens when a template is saved, deleted
// or applied — never per frame — and an APPLY batches its nine slot writes into
// ONE save through `s_dkTplHold`. The file is rewritten in full, which for 17
// kinds × 12 rows is trivial and keeps ONE writer instead of an append log to
// reconcile.
// ══════════════════════════════════════════════════════════════════════════

string DrawTplPath() { return DRAW_TPL_FILE; }

//--- P-DRAW-09c (2026-10-04) — THE LAST LOOK, PACKED EXACTLY. Two doubles carry the
//--- nine values of one kind's memory: word A holds the border's pair (colour 24 bits,
//--- width 3, style 3, fill 1, ray 2) plus the three appended looks (font 7, glyph 8,
//--- back 1) and a PRESENCE BIT at 33; word B holds the interior's colour (24 bits)
//--- and its own presence bit at 24. Nothing is ever a guess: `clrNONE` is -1 and
//--- `-1 & 0xFFFFFF` is WHITE, so the presence bit is what tells "no colour of its own"
//--- from a colour nobody chose (P-DRAW-75's rule, one file over).
double DrawStylePackA(const int k)
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
double DrawStylePackB(const int k)
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
void DrawStyleUnpack(const int k, const double rawA, const double rawB)
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

//--- ONE LINE PER TEMPLATE, the user's NAME included — the whole rack, every kind.
//--- Rows are written in index order (the list is compact), so the reader takes
//--- them back in order; rows 255/254 keep their reserved seats (P-DRAW-09c /
//--- P-DRAW-INK may never fight a band guard — they ARE outside every band).
void DrawTplSave()
{
   int h = FileOpen(DrawTplPath(), FILE_WRITE | FILE_CSV | FILE_ANSI, ';');
   if(h == INVALID_HANDLE) return;
   for(int k = 1; k < DK_COUNT; k++)
   {
      int n = DrawTplCount((EDrawKind)k);
      for(int i = 0; i < n; i++)
      {
         FileWrite(h, (int)k, i, s_dkTpl[k][i].name,
                   DoubleToString(s_dkTpl[k][i].packA, 0),
                   DoubleToString(s_dkTpl[k][i].packB, 0));
         //--- P-DRAW-135: the template's level set rides its own reserved row — the
         //--- encoded string IS that row's `name` column; a template without one
         //--- writes nothing, so old files and non-level kinds are byte-identical.
         if(s_dkTpl[k][i].lvl != "")
            FileWrite(h, (int)k, DRAW_TPL_LVL_ROW + i, s_dkTpl[k][i].lvl, "0", "0");
      }
      //--- P-DRAW-09c: the kind's LAST LOOK rides the same file, in the reserved
      //--- slot. A kind the user never styled writes nothing, so the load can
      //--- leave it factory-fresh (the test's own «nobody styled» case).
      if(!s_dkValid[k]) continue;
      FileWrite(h, (int)k, DRAW_LASTLOOK_SLOT, "",
                DoubleToString(DrawStylePackA(k), 0), DoubleToString(DrawStylePackB(k), 0));
   }
   //--- P-DRAW-INK: and the ONE ink every kind shares has its own row. It is not a
   //--- kind's look, so it does not ride a kind's slot: a single reserved row answers
   //--- the next attach's first drawing.
   if((int)s_dkAnyClr >= 0)
      FileWrite(h, 1, DRAW_LASTINK_SLOT, IntegerToString((int)s_dkAnyClr), "0", "0");
   FileClose(h);
}

//--- P-DRAW-132 — ONE START, ONE TRUTH. The file is authoritative the moment it
//--- exists: a deleted seed stays deleted and a deleted template never comes back.
//--- Only a FIRST run seeds; a first run that finds P-DRAW-02's file migrates it
//--- first and retires it — after the new file is on disk, so a crash in between
//--- leaves the old rows readable. The reserved rows are answered BEFORE any band
//--- guard (P-DRAW-09c / P-DRAW-INK / P-UI-133's lesson, one file over).
void DrawTplLoad()
{
   int h = FileOpen(DrawTplPath(), FILE_READ | FILE_CSV | FILE_ANSI, ';');
   if(h == INVALID_HANDLE) return;
   while(!FileIsEnding(h))
   {
      int k = (int)StringToInteger(FileReadString(h));
      int i = (int)StringToInteger(FileReadString(h));
      string nm = FileReadString(h);
      string pa = FileReadString(h);
      string pb = FileReadString(h);
      if(FileIsEnding(h) && pb == "") break;
      if(i == DRAW_LASTLOOK_SLOT) { DrawStyleUnpack(k, StringToDouble(pa), StringToDouble(pb)); continue; }
      if(i == DRAW_LASTINK_SLOT) { int ink = (int)StringToInteger(nm); if(ink >= 0) s_dkAnyClr = (color)ink; continue; }
      if(k <= DK_NONE || k >= DK_COUNT) continue;
      //--- P-DRAW-135: the level rows are answered BEFORE the template band guard —
      //--- a guard asked first would eat the very rows this feature writes
      //--- (P-UI-133's lesson, one file over).
      if(i >= DRAW_TPL_LVL_ROW && i < DRAW_TPL_LVL_ROW + DRAW_TPL_MAX)
      { s_dkTpl[k][i - DRAW_TPL_LVL_ROW].lvl = nm; continue; }
      if(i < 0 || i >= DRAW_TPL_MAX) continue;
      s_dkTpl[k][i].used  = true;
      s_dkTpl[k][i].name  = (nm == "" ? ("My " + IntegerToString(i + 1)) : nm);
      s_dkTpl[k][i].packA = StringToDouble(pa);
      s_dkTpl[k][i].packB = StringToDouble(pb);
   }
   FileClose(h);
}

//--- P-DRAW-132 — THE ONE-TIME MIGRATION of P-DRAW-02's file (DrawPresets.csv).
//--- Old rows are `kind ; slot ; name ; packed-33-bit`, user slots 3..5 only (the
//--- 0..2 built-ins were never written), plus 255 (the last look, packed across
//--- TWO columns — B in `name`, A in `packed`) and 254 (the shared ink, a number
//--- in `name`). A user row moves whole — its colour/width/style/fill/ray exact —
//--- wearing today's fresh values for what the old pack did not carry (font,
//--- glyph, back, interior colour). The old built-ins are NOT migrated: the new
//--- seeds already carry the same three looks, and they are ordinary rows now.
void DrawTplMigrate()
{
   int h = FileOpen(DRAW_TPL_LEGACY, FILE_READ | FILE_CSV | FILE_ANSI, ';');
   if(h == INVALID_HANDLE) return;
   while(!FileIsEnding(h))
   {
      int k = (int)StringToInteger(FileReadString(h));
      int i = (int)StringToInteger(FileReadString(h));
      string nm = FileReadString(h);
      string pk = FileReadString(h);
      if(FileIsEnding(h) && pk == "") break;
      if(i == DRAW_LASTLOOK_SLOT) { DrawStyleUnpack(k, StringToDouble(pk), StringToDouble(nm)); continue; }
      if(i == DRAW_LASTINK_SLOT) { int ink = (int)StringToInteger(nm); if(ink >= 0) s_dkAnyClr = (color)ink; continue; }
      if(k <= DK_NONE || k >= DK_COUNT) continue;
      if(i < 3 || i >= 6) continue;   // the old rack: 0..2 built-ins, 3..5 the user's
      long v = (long)StringToDouble(pk);
      DrawLook L;
      L.clr     = (color)(int)(v & 0xFFFFFF);
      L.width   = (int)((v >> 24) & 0x7);
      L.style   = (int)((v >> 27) & 0x7);
      L.fill    = (((v >> 30) & 0x1) != 0);
      L.ray     = (int)((v >> 31) & 0x3);
      L.font    = DRAW_FONT_DEF;
      L.glyph   = 0;
      L.back    = false;
      L.fillClr = clrNONE;
      DrawTplPut((EDrawKind)k, (nm == "" ? ("My " + IntegerToString(i - 3 + 1)) : nm), L);
   }
   FileClose(h);
}

//--- P-DRAW-132 — ONE START: clear the rack, then let the FILE rule. First run:
//--- seed, migrate P-DRAW-02's file when it exists, write, then retire it.
void DrawTplBoot()
{
   for(int k = 0; k < DK_COUNT; k++)
      for(int i = 0; i < DRAW_TPL_MAX; i++)
      {
         s_dkTpl[k][i].used  = false;
         s_dkTpl[k][i].name  = "";
         s_dkTpl[k][i].packA = 0.0;
         s_dkTpl[k][i].packB = 0.0;
         s_dkTpl[k][i].lvl   = "";
      }
   if(FileIsExist(DRAW_TPL_FILE))
   {
      DrawTplLoad();
      if(FileIsExist(DRAW_TPL_LEGACY)) FileDelete(DRAW_TPL_LEGACY);
      return;
   }
   DrawTplSeed();
   if(FileIsExist(DRAW_TPL_LEGACY)) DrawTplMigrate();
   DrawTplSave();
   if(FileIsExist(DRAW_TPL_LEGACY)) FileDelete(DRAW_TPL_LEGACY);
}

#endif // TOOLBAR_TPL_MQH
