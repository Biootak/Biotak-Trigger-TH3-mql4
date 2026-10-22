#ifndef CALC_ANCHOR_MQH
#define CALC_ANCHOR_MQH

// P-ANCHOR-LAST: one active historical anchor, owned by the newest committed
// LegMeasure or BaseKnot. State lives in GlobalVariables.mqh; this unit only
// maintains it. Two compares on the ATR read; writes on commit/delete/toggle,
// plus one compare per moved drag event while the owner follows the hand.

string CalcAnchorGVKey()
{
   return "Biotak_CalcAnchor_" + IntegerToString((long)ChartID());
}

void CalcAnchorSave()
{
   GlobalVariableSet(CalcAnchorGVKey(), g_calcAnchorOn ? 1.0 : 0.0);
}

void CalcAnchorLoad()
{
   // P-ANCHOR-LAST-MOVE (2026-10-22): shipped OFF. The switch is no longer a row
   // on the ATR card (it never was an ATR-label setting); it belongs to the two
   // tools that own the anchor — the BaseKnot box and the leg ruler — so a chart
   // starts LIVE and the user arms it himself. The key is still written, so an
   // explicit ON survives an attach and a chart that never stored it answers OFF.
   if(!GlobalVariableCheck(CalcAnchorGVKey()))
   {
      g_calcAnchorOn = false;
      CalcAnchorSave();
   }
   else g_calcAnchorOn = (GlobalVariableGet(CalcAnchorGVKey()) > 0.5);
   g_calcAnchorTime = 0;
   g_calcAnchorOwner = "";
   g_calcAnchorLastTime = 0;
   g_calcAnchorLastOwner = "";
}

datetime CalcAnchorAt()
{
   return (g_calcAnchorOn && g_calcAnchorTime > 0) ? g_calcAnchorTime : 0;
}

void CalcAnchorRemember(const datetime t, const string owner)
{
   if(t <= 0 || owner == "") return;
   g_calcAnchorLastTime = t;
   g_calcAnchorLastOwner = owner;
   if(!g_calcAnchorOn) return;
   if(g_calcAnchorTime == t && g_calcAnchorOwner == owner) return;
   g_calcAnchorTime = t;
   g_calcAnchorOwner = owner;
   g_labelsRelayoutNeeded = true;
   g_redrawNeeded = true;
}

void CalcAnchorFollow(const string owner, const datetime t)
{
   if(owner == "" || t <= 0) return;
   if(owner == g_calcAnchorLastOwner) g_calcAnchorLastTime = t;
   // P-ANCHOR-LAST: an attach has no object registry to scan yet, so the first
   // object the user TOUCHES adopts the ON state instead of leaving it inert.
   if(g_calcAnchorOn && g_calcAnchorOwner == "")
   {
      g_calcAnchorOwner = owner;
      g_calcAnchorTime = t;
      g_calcAnchorLastOwner = owner;
      g_calcAnchorLastTime = t;
      g_labelsRelayoutNeeded = true;
      g_redrawNeeded = true;
      return;
   }
   if(owner != g_calcAnchorOwner) return;
   if(g_calcAnchorTime == t) return;
   g_calcAnchorTime = t;
   g_labelsRelayoutNeeded = true;
   g_redrawNeeded = true;
}

void CalcAnchorForget(const string owner)
{
   if(owner == "") return;
   if(g_calcAnchorOwner == owner)
   {
      g_calcAnchorTime = 0;
      g_calcAnchorOwner = "";
      g_labelsRelayoutNeeded = true;
      g_redrawNeeded = true;
   }
   if(g_calcAnchorLastOwner == owner)
   {
      g_calcAnchorLastTime = 0;
      g_calcAnchorLastOwner = "";
   }
}

void CalcAnchorSetOn(const bool on)
{
   if(g_calcAnchorOn == on) return;
   g_calcAnchorOn = on;
   if(on && g_calcAnchorLastTime > 0)
   {
      g_calcAnchorTime = g_calcAnchorLastTime;
      g_calcAnchorOwner = g_calcAnchorLastOwner;
   }
   else
   {
      g_calcAnchorTime = 0;
      g_calcAnchorOwner = "";
   }
   CalcAnchorSave();
   g_labelsRelayoutNeeded = true;
   g_redrawNeeded = true;
}

#endif // CALC_ANCHOR_MQH
