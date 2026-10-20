// BoxPreview.mqh - P-DRAGF4 (2026-10-17): the box family's interior rides the
// terminal during a gesture (split out of Toolbar_A.mqh at P-SIZE-1500).
// The same law the fibo pen learned (P-DRAGF3): the cheapest follower is NO
// follower. Mid-gesture the interior (`_FL` child) and the 50 % mid (`_BX50`) LAG
// by construction - the child is a second object re-seated from the event stream,
// and the event stream is one frame behind the terminal's own drag rendering. So
// during the gesture the master takes the interior BACK: `OBJPROP_FILL` on,
// `OBJPROP_BGCOLOR` = the child's own rendered ink, both followers hidden with
// `OBJ_NO_PERIODS` - the terminal then draws the interior natively WITH the box,
// zero writes per pixel of travel. At the release one pass re-seats the child and
// the mid on the final seat and the master gives the interior back (FILL off).
//   Cost: at rest and outside a gesture ZERO; a gesture pays one arm (four writes
//   plus the reads of the witness) and one end (two visible re-writes plus the
//   two syncs the release always did anyway). A pixel of travel pays NOTHING.
//   The gate is `BoxPreviewOwns` - `FillChildSync` (Toolbar_A) and `BoxMidSync`
//   (DrawStrip_Pick) both stand down while the preview owns the name, so the
//   gesture cannot fight itself.
// One gesture at a time, one memo slot - it re-arms on a new name. The agent asks
// `DrawTypeHasFillChild`/`DrawKindHasFillBody` first, so a stranger or the
// product's own drawings never arm; `BoxMidSync` is Full-only (Lite ships no mid).
#ifndef BOX_PREVIEW_MQH
#define BOX_PREVIEW_MQH

static bool   s_bxpOn = false;
static string s_bxpObj = "";
static string s_bxpFilObj = "";
static string s_bxpMidObj = "";
static color  s_bxpBorderInk = clrNONE;   // P-UI-175: the master's own ink, for the release
bool BoxPreviewOwns(const string obj)
{
   return (s_bxpOn && obj != "" && obj == s_bxpObj);
}
bool BoxPreviewEnd()
{
   if(!s_bxpOn) return false;
   s_bxpOn = false;
   string master = s_bxpObj;
   string fil = s_bxpFilObj, mid = s_bxpMidObj;
   s_bxpObj = ""; s_bxpFilObj = ""; s_bxpMidObj = "";
   if(ObjectFind(0, master) < 0) { s_bxpBorderInk = clrNONE; return true; }   // gone mid-gesture: nothing to give back
   //--- P-UI-175 (2026-10-20): the master gave its interior back to the terminal
   //--- in the INTERIOR's ink, so the release gives it its own ink back.
   if(s_bxpBorderInk != clrNONE)
   {
      ObjectSetInteger(0, master, OBJPROP_COLOR, s_bxpBorderInk);
      s_bxpBorderInk = clrNONE;
   }
   int unhid = 0;
   if(fil != "" && ObjectFind(0, fil) >= 0)
   {
      ObjectSetInteger(0, fil, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
      unhid++;
   }
   if(mid != "" && ObjectFind(0, mid) >= 0)
   {
      ObjectSetInteger(0, mid, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
      unhid++;
   }
   FillChildSync(master);   // re-seat the interior on the FINAL station, one pass
#ifndef BUILD_LITE
   BoxMidSync(master);      // and the 50 % mid with it (Full only: its owner lives in the strip; Lite ships no mid)
#endif
   DrawStripDiagEmit(StringFormat("[drawstrip] BOXPRE view=off obj=\"%s\" unhid=%d fil=%d mid=%d",
                                  master, unhid,
                                  (int)ObjectGetInteger(0, master, OBJPROP_FILL),
                                  (int)ObjectFind(0, mid)));
   return true;
}
void BoxPreviewArm(const string obj)
{
   if(obj == "" || !DrawTypeHasFillChild(DrawObjectType(obj))) return;
   if(BoxPreviewOwns(obj)) return;
   BoxPreviewEnd();   // a missed release must not hold the previous box hostage
   if(ObjectFind(0, obj) < 0) return;
   if(DrawIsIndicatorObject(obj)) return;
   if(!DrawKindHasFillBody(DrawKindOf(obj))) return;
   string fil = FillChildName(obj);
   if(ObjectFind(0, fil) < 0) fil = "";
   string mid = BoxMidName(obj);
   if(mid == "" || ObjectFind(0, mid) < 0) mid = "";
   if(fil == "" && mid == "") return;   // no follower: the master already is the whole drawing
   if(fil != "")
   {
      // The child's COLOUR is the rendered interior ink the user tuned (P-DRAW-64a),
      // so the native fill wears the exact pixel the child wore - no second render owner.
      //--- P-UI-175 (2026-10-20): the property MT4 PAINTS a shape's fill with is
      //--- OBJPROP_COLOR. OBJPROP_BGCOLOR belongs to OBJ_EDIT / OBJ_BUTTON /
      //--- OBJ_RECTANGLE_LABEL - a time/price shape has NO such property, so the
      //--- old write was a silent no-op and the native fill wore the BORDER's ink
      //--- for the whole gesture (the house measured the same law for the session
      //--- box: "this build fills a rectangle with its COLOR; BGCOLOR and FILL are
      //--- both unconsumed"). The master's own ink is remembered and put back.
      s_bxpBorderInk = (color)ObjectGetInteger(0, obj, OBJPROP_COLOR);
      ObjectSetInteger(0, obj, OBJPROP_COLOR, (color)ObjectGetInteger(0, fil, OBJPROP_COLOR));
      ObjectSetInteger(0, obj, OBJPROP_FILL, true);
      ObjectSetInteger(0, fil, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      s_bxpFilObj = fil;
   }
   if(mid != "")
   {
      ObjectSetInteger(0, mid, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      s_bxpMidObj = mid;
   }
   s_bxpOn = true; s_bxpObj = obj;
   // DIAG-131 style: the write AND its read-back, because «جابجا کردم یک فریم عقب» is
   // unprovable without the value the OBJECT now holds.
    DrawStripDiagEmit(StringFormat("[drawstrip] BOXPRE view=on obj=\"%s\" fil=\"%s\" mid=\"%s\" fill=%d ink=%d childtf=%d",
                                   obj, fil, mid,
                                   (int)ObjectGetInteger(0, obj, OBJPROP_FILL),
                                   (int)ObjectGetInteger(0, obj, OBJPROP_COLOR),
                                   (fil == "") ? -1 : (int)ObjectGetInteger(0, fil, OBJPROP_TIMEFRAMES)));
}

#endif // BOX_PREVIEW_MQH
