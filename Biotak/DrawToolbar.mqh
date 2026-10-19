  //+------------------------------------------------------------------+
//|                                              DrawToolbar.mqh      |
//|   P-DRAW-01 (2026-09-22) — THE USER'S OWN DRAWINGS, ONE OWNER.     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Biotak Project"
#property strict

#ifndef DRAW_TOOLBAR_MQH
#define DRAW_TOOLBAR_MQH

#include "Toolbar_A.mqh"
#include "DrawKindProfile.mqh"   // P-UNIFY-4: the kind's geometry / pen / look profile
#include "DrawLooks.mqh"         // P-UNIFY-4: the look vocabulary's one slot / native / name translator
#include "Toolbar_Hit.mqh"   // P-SIZE-1500 (2026-10-19): the PICK owner, split out of Toolbar_A at 1526 lines — it reads the kind, the anchors and the segment distance from Toolbar_A, so it must stand ABOVE them (MQL4 resolves a call top-down)
#include "FibPen.mqh"
#include "PenStack.mqh"   // P-DRAW-74c + P-PEN-ALL + P-UNIFY-2: the whole-object pen (HLINE/VLINE/LINE/the by-angle line and the shapes: rect, ellipse, triangle, channel, gann, cycles), FibPen's offset law
#include "BoxPreview.mqh"   // P-DRAGF4: the box family's interior rides the terminal mid-gesture
#include "Toolbar_Tpl.mqh"   // P-SIZE-1500: the template rack (was the tail of Toolbar_B — DrawSlotWrite reads its s_dkTplHold)
#include "Toolbar_B.mqh"

#endif // DRAW_TOOLBAR_MQH
