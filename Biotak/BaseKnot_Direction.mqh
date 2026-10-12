//+------------------------------------------------------------------+
//| BaseKnot_Direction.mqh                                         |
//| P-BK-111 (2026-10-09) — THE USER'S CALL ON THE SIDE.            |
//|                                                                  |
//| The user: «خوب یک چیزی باشه که کاربر خواست جهت سل و بای گره عوض |
//| بکن چ.ن بعضی گره به صورت مارکر هستش که مثل سل هستش ولی در جهت |
//| بای وقتی که ایگنور شد میشه استفاده کرد ازش».                     |
//|                                                                  |
//| WHY IT EXISTS AT ALL: the side is read from the market (the price |
//| crossing the band, P-BK-13) or from the break's story (P-BK-81). |
//| A marker that reads Sell can be traded the other way, and that is|
//| a judgement made by LOOKING at that one box — so the control has  |
//| to live on the box (the Base Box strip, the ninth cell) and not in|
//| a settings card.                                                    |
//|                                                                  |
//| THREE STATES, the user named two of them: the price answers      |
//| (auto) → the user's opposite → auto again. The middle state is    |
//| what makes it more than a checkbox: the price follow runs every   |
//| 500 ms and would undo a bare click in half a second, so the       |
//| user's answer needs a bit of its own — `g_bkBoxes[k].dirLock`.   |
//|                                                                  |
//| WHAT IS *NOT* HERE, ON PURPOSE: this owns the ACTION and its      |
//| persistence. The follow's gate is in the follow (one line), the   |
//| strip's two readers are beside the lock's reader, and the button  |
//| itself is a strip cell with its own hit rect. Four owners, one   |
//| decision each - a second place that flipped the side would be a  |
//| second direction the chart could draw.                           |
//+------------------------------------------------------------------+
#ifndef BASE_KNOT_DIRECTION_MQH
#define BASE_KNOT_DIRECTION_MQH

//--- The lock's persistence key rides beside the side's own GV pair, so a
//--- call the user made survives the restart exactly as the side does.
string BaseKnotDirLockGV(const string id)
{
   return "Biotak_BKL_" + id + "_" + GetCachedChartIdStr();
}

//--- The strip is compiled ABOVE this layer (BiotakPanels, line 126), so it cannot reach
//--- the registry. It asks these two, and they answer from the same fields the flip writes —
//--- neither decides anything. They sit here, not in the follow, because they exist only to
//--- draw a caption and pick an ink.
bool BaseKnotDirLocked(const string id)
{
   int k = BaseKnotFind(id);
   return (k >= 0 && g_bkBoxes[k].dirLock != 0);
}
string BaseKnotDirWord(const string id)
{
   int k = BaseKnotFind(id);
   if(k < 0) return "nothing";
   return (g_bkBoxes[k].dir >= 0 ? "BUY" : "SELL");
}

//--- P-BK-111: THE FLIP'S OWN WITNESS RECORD. This layer compiles BEFORE DrawStrip.mqh
//--- (BaseKnotTool is line 52, DrawStrip is ~200), so it cannot call DrawStripDiagEmit —
//--- and a `Print` witness reads as «nothing happened» (P-DRAW-126: the journal stood still
//--- for seven minutes while the clicks went into MT4's RAM buffer). So the flip RECORDS
//--- here and the flushed channel REPORTS it (BaseKnot_Witness.mqh, which compiles after
//--- DrawStrip) with a read-back: the box, the side before and after, the lock, and what the
//--- GlobalVariable now holds. «کلیک کردم هیچی نشد» is unprovable without the read-back.
#define BK_DF_MAX 8
string  s_bkDfId[BK_DF_MAX];
int     s_bkDfFrom[BK_DF_MAX];
int     s_bkDfTo[BK_DF_MAX];
int     s_bkDfLock[BK_DF_MAX];
bool    s_bkDfUsed[BK_DF_MAX];
int     s_bkDfHead = 0;

//--- ONE bounded push per press. The ring is 8 because a witness may never be the reason a
//--- write is lost: a full ring DROPS the line (the oldest is overwritten), it never refuses
//--- the flip itself.
void BaseKnotDirFlipNote(const string id, const int from, const int to, const int lock)
{
   int s = s_bkDfHead;
   s_bkDfId[s] = id; s_bkDfFrom[s] = from; s_bkDfTo[s] = to;
   s_bkDfLock[s] = lock; s_bkDfUsed[s] = true;
   s_bkDfHead = (s + 1) % BK_DF_MAX;
}

//--- THE WITNESS'S READ of the record it is about to report. One seat per call, so two flips
//--- inside one pump round are TWO lines and not one merged lie.
bool BaseKnotDirFlipTake(string &id, int &from, int &to, int &lock)
{
   for(int i = 0; i < BK_DF_MAX; i++)
   {
      if(!s_bkDfUsed[i]) continue;
      id = s_bkDfId[i]; from = s_bkDfFrom[i]; to = s_bkDfTo[i]; lock = s_bkDfLock[i];
      s_bkDfUsed[i] = false;
      return true;
   }
   return false;
}

//--- THE SERVED OBJECT'S BOX. The draw-strip serves ONE object by name (P-DRAW-09b), and
//--- every knot structure shares one prefix (`<pfx>_BK_<id>_`, BaseKnotPrefix), so the
//--- mapping is a bounded walk of the registry asked ONLY on a strip open, a tap and a
//--- tooltip - never per tick. It answers the id, or "" when the served drawing is not a
//--- Base Box at all (a fib, a ray, a zone): that is the case the cell must refuse rather
//--- than guess, and "" is how it says so.
string BaseKnotDirBoxFor(const string objName)
{
   if(objName == "") return "";
   for(int i = 0; i < ArraySize(g_bkBoxes); i++)
   {
      string pfx = BaseKnotPrefix(g_bkBoxes[i].id);
      if(pfx != "" && StringFind(objName, pfx) == 0) return g_bkBoxes[i].id;
   }
   return "";
}

//--- THE ONE ACTION. Returns "did anything change", so the caller rebuilds
//--- on that and on nothing else.
bool BaseKnotFlipDirection(const string id)
{
   int k = BaseKnotFind(id);
   if(k < 0) return false;
   int was = g_bkBoxes[k].dir;
   if(g_bkBoxes[k].dirLock != 0)
   {
      // BACK TO AUTO: the price answers again, from the CURRENT side — so the box does
      // not visibly jump on the way and the next pump simply keeps it honest.
      g_bkBoxes[k].dirLock = 0;
      GlobalVariableSet(BaseKnotDirLockGV(id), 0.0);
      BaseKnotDirFlipNote(id, was, was, 0);
      return true;
   }
   int want = (g_bkBoxes[k].dir >= 0 ? -1 : 1);
   g_bkBoxes[k].dir     = want;
   g_bkBoxes[k].dirLock = want;   // same sign as the side it locked: one bit, no second scale
   GlobalVariableSet(BaseKnotGV(id), (double)want);
   GlobalVariableSet(BaseKnotGVTwin(id), (double)want);   // P-UI-142: restart layer
   GlobalVariableSet(BaseKnotDirLockGV(id), (double)want);
   BaseKnotDirFlipNote(id, was, want, want);
   return true;
}

#endif // BASE_KNOT_DIRECTION_MQH
