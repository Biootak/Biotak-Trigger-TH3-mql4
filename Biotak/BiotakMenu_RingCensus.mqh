//| BiotakMenu_RingCensus.mqh — P-UI-200 (2026-10-22)                  |
//|                                                                   |
//| «مربع شده» is a PIXEL report, and the seat's art is only one       |
//| writer of those pixels: the panel's cards, the tip face and any    |
//| orphan of an older build sit in the same rect. So the ring's       |
//| census READS BACK every seat's BMPFILE from the object (a write    |
//| proves nothing — P-DRAW-125) and names every object whose rect     |
//| touches the ring's bounding box with its type, live box and art.   |
//|                                                                   |
//| Reads only: no write, no pixel (P-DRAW-125). The body lives in     |
//| its own file because BiotakMenu_B is at the 1500 ceiling           |
//| (contract §7) and MQL4 warns on a body-less prototype (warning 46).|
//| Included AFTER BiotakMenu_A (CircBg) and BiotakMenu_Ring (the      |
//| seat's side, the outer radius), BEFORE BiotakMenu_B (CircNoteBuilt |
//| is the one-per-build caller).                                      |
//+------------------------------------------------------------------+
#ifndef BIOTAK_MENU_RINGCENSUS_MQH
#define BIOTAK_MENU_RINGCENSUS_MQH

void CircRingCensus(const int n)
{
   int r  = (int)MathCeil(CircRing2Radius() + CIRC_BTN_SIZE / 2.0 + CIRC_BG_MARGIN);
   int x0 = g_UI.menuX - r, y0 = g_UI.menuY - r, x1 = g_UI.menuX + r, y1 = g_UI.menuY + r;
   for(int i = 0; i < n; i++)
   {
      string nm = CircBg(i);
      if(ObjectFind(0, nm) < 0) { DrawStripDiagEmit(StringFormat("[P-UI-200] seat=%d bg MISSING", i)); continue; }
      DrawStripDiagEmit(StringFormat("[P-UI-200] seat=%d s=%d box=%dx%d at=%d,%d bmp=%s",
                                     i, CircSeatSize(i),
                                     (int)ObjectGetInteger(0, nm, OBJPROP_XSIZE),
                                     (int)ObjectGetInteger(0, nm, OBJPROP_YSIZE),
                                     (int)ObjectGetInteger(0, nm, OBJPROP_XDISTANCE),
                                     (int)ObjectGetInteger(0, nm, OBJPROP_YDISTANCE),
                                     ObjectGetString(0, nm, OBJPROP_BMPFILE, 0)));
   }
   int total = ObjectsTotal(0, -1, -1), hits = 0;
   for(int k = 0; k < total; k++)
   {
      string nm = ObjectName(0, k, -1, -1);
      if(nm == "") continue;
      int ty = (int)ObjectGetInteger(0, nm, OBJPROP_TYPE);
      if(ty != OBJ_BITMAP_LABEL && ty != OBJ_RECTANGLE_LABEL && ty != OBJ_BUTTON) continue;
      int ow = (int)ObjectGetInteger(0, nm, OBJPROP_XSIZE);
      int oh = (int)ObjectGetInteger(0, nm, OBJPROP_YSIZE);
      int ox = (int)ObjectGetInteger(0, nm, OBJPROP_XDISTANCE);
      int oy = (int)ObjectGetInteger(0, nm, OBJPROP_YDISTANCE);
      if(ox > x1 || oy > y1 || ox + ow < x0 || oy + oh < y0) continue;
      hits++;
      DrawStripDiagEmit(StringFormat("[P-UI-200] inRing obj=%s ty=%d x=%d y=%d w=%d h=%d bmp=%s bg=%s",
                                     nm, ty, ox, oy, ow, oh,
                                     (ty == OBJ_BITMAP_LABEL ? ObjectGetString(0, nm, OBJPROP_BMPFILE, 0) : "-"),
                                     (ty == OBJ_RECTANGLE_LABEL ? (string)(int)ObjectGetInteger(0, nm, OBJPROP_BGCOLOR, 0) : "-")));
   }
   DrawStripDiagEmit(StringFormat("[P-UI-200] ring census n=%d rect=%d,%d..%d,%d hits=%d chart=%d",
                                  n, x0, y0, x1, y1, hits, total));
}

#endif // BIOTAK_MENU_RINGCENSUS_MQH
