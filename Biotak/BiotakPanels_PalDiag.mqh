// BiotakPanels_PalDiag.mqh - the palette popup's own census (P-UI-137, 2026-10-02).
// Its own file because a witness is an OWNER, and PalB was one line over the
// contract's 1500 ceiling with it inlined (P-SIZE-1500).
#ifndef BIOTAK_PANELS_PALDIAG_MQH
#define BIOTAK_PANELS_PALDIAG_MQH

#ifndef BUILD_LITE
//--- P-UI-137: THE POPUP HAD NO WITNESS. A caption the popup paints and the screen
//--- does not show can only be argued about from the object list - and the object
//--- list cannot see paint order, ink on ink, or a value written empty. So the popup
//--- censuses ITSELF, through the FLUSHED channel (P-LOG-3 - never `Print`: MT4
//--- buffers the journal in RAM, so a Print witness reads "nothing happened" long
//--- after the tap). One line per caption/field inside the card, carrying the four
//--- numbers that decide the case: seat, ink size, layer, text.
//--- ONCE PER OPEN, NOT PER PASS (the Optimize rule: the cost is a number). MEASURED
//--- 2026-10-02: on EVERY pass this walked the chart and wrote ~55 flushed lines, and
//--- `PalDraw` runs on every chip / tab / pager click - the popup became visibly slow
//--- for a witness nobody reads twice. Paint order and ink are identical in every
//--- pass, so one answer per open is the whole answer: 1 walk + ~55 lines per OPEN,
//--- 0 on every later repaint.
void PalDiagCensus(const int px,const int py,const int w,const int h)
{
   if(s_palDiagDone) return;
   s_palDiagDone = true;
   string pfx=g_UI.btnPrefix+"Pal_";
   int n=ObjectsTotal(0,0,-1);
   for(int i=0;i<n;i++)
   {
      string nm=ObjectName(0,i,0,-1);
      if(StringFind(nm,pfx)!=0) continue;
      int ty=(int)ObjectGetInteger(0,nm,OBJPROP_TYPE);
      if(ty!=OBJ_LABEL && ty!=OBJ_EDIT && ty!=OBJ_BUTTON) continue;
      int x=(int)ObjectGetInteger(0,nm,OBJPROP_XDISTANCE);
      int y=(int)ObjectGetInteger(0,nm,OBJPROP_YDISTANCE);
      if(x<px-8 || y<py-8 || x>px+w+8 || y>py+h+8) continue;
      DrawStripDiagEmit("[pal] "+nm+" t="+IntegerToString(ty)
         +" xy="+IntegerToString(x)+","+IntegerToString(y)
         +" sz="+IntegerToString((int)ObjectGetInteger(0,nm,OBJPROP_FONTSIZE))
         +" z="+IntegerToString((int)ObjectGetInteger(0,nm,OBJPROP_ZORDER))
         +" ink="+IntegerToString((int)ObjectGetInteger(0,nm,OBJPROP_COLOR))
         +" txt=\""+ObjectGetString(0,nm,OBJPROP_TEXT)+"\"");
   }
}
#endif

#endif // BIOTAK_PANELS_PALDIAG_MQH