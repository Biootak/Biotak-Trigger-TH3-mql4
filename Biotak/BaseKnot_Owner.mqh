//+------------------------------------------------------------------+
//| BaseKnot_Owner.mqh                                              |
//| P-BK-114 — the selected knot's owner TF, measured before Sync.    |
//|                                                                  |
//| The ruler's law: the box height belongs to the TF whose own ATR   |
//| makes it 240%..360%. That TF is the knot's time now, so the pump  |
//| measures it first, recounts the base on that TF, and publishes    |
//| both before the ability rows are asked for.                      |
//+------------------------------------------------------------------+
#ifndef BASE_KNOT_OWNER_MQH
#define BASE_KNOT_OWNER_MQH

int BaseKnotOwnerTFWalk(const double boxPips, const datetime an)
{
   if(boxPips <= 0.0) return 0;
   int tf = Period();
   if(tf <= 0) tf = 60;
   int visited[9];
   ArrayInitialize(visited, 0);
   int nv = 0;
   for(int w = 0; w < 9; w++)
   {
      double atr = CalculateWeightedATRAt(CompatTF(tf), an);
      double a = BaseKnotToPips(atr);
      if(a <= 0.0) break;
      double r = boxPips / a;
      if(r >= BK_OWNER_LO && r <= BK_OWNER_HI) return tf;
      int nxt = (r > BK_OWNER_HI ? BaseKnotNextTFMin(tf) : BaseKnotPrevTFMin(tf));
      if(nxt <= 0 || nxt == tf) break;
      bool seen = false;
      for(int v = 0; v < nv; v++) if(visited[v] == nxt) { seen = true; break; }
      if(seen) break;
      if(nv < 9) { visited[nv] = tf; nv++; }
      tf = nxt;
   }
   return 0;
}

void BaseKnotOwnerATRPump()
{
   int k = BaseKnotFind(BaseKnotSelectedId());
   int tf = Period();
   if(tf <= 0) tf = 1;
   datetime an = 0;
   if(k >= 0)
   {
      string pfx = BaseKnotPrefix(g_bkBoxes[k].id);
      string box = (pfx == "" ? "" : BaseKnotBoxName(pfx));
      if(box != "" && ObjectFind(0, box) >= 0)
      {
         datetime t1 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 0);
         datetime t2 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 1);
         if(t2 < t1) { datetime tt = t1; t1 = t2; t2 = tt; }
         double p1 = ObjectGetDouble(0, box, OBJPROP_PRICE, 0);
         double p2 = ObjectGetDouble(0, box, OBJPROP_PRICE, 1);
         double top = MathMax(p1, p2), bot = MathMin(p1, p2);
         an = g_bkBoxes[k].storyT;
         int owner = BaseKnotOwnerTFWalk(BaseKnotToPips(top - bot), an);
         BaseKnotSpan osp;
         if(owner > 0 && BaseKnotBarCount(t1, t2, top, bot, osp, owner) > 0)
         {
            g_bkBoxes[k].ownerTFMin = owner;
            g_bkBoxes[k].baseTFMin = owner;
            g_bkBoxes[k].storyT = osp.tLast;
            g_bkBoxes[k].exitT = osp.tExit;
         }
         else g_bkBoxes[k].ownerTFMin = 0;
      }
   }
   if(k >= 0 && g_bkBoxes[k].baseTFMin > 0) tf = g_bkBoxes[k].baseTFMin;
   if(k >= 0) an = g_bkBoxes[k].storyT;
   int down = BaseKnotPrevTFMin(tf);
   for(int i = 0; i < 3 && down > 0; i++)
   {
      double atr = CalculateWeightedATRAt(CompatTF(down), an);
      BaseKnotOwnerATRPush(down, an, atr);
      down = BaseKnotPrevTFMin(down);
   }
}

#endif // BASE_KNOT_OWNER_MQH
