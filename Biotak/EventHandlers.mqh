   //+------------------------------------------------------------------+
//| Event Handlers - Version 3.10 GOLD                              |
//| Security & Performance Audit Complete                           |
//+------------------------------------------------------------------+
#ifndef EVENT_HANDLERS_MQH
#define EVENT_HANDLERS_MQH

// P-SIZE-1500 (2026-10-04): the two owners that drifted back over the ceiling were
// split along seams they already had. ORDER IS THE COMPILER'S: MQL4 resolves a call
// top-down, so each new half is included ABOVE the file that calls it.
#include "EventHandlers_CustomPrice.mqh"      // the custom price line (was the tail of Init)
#include "EventHandlers_Init.mqh"
#include "EventHandlers_Calc.mqh"
#include "BaseKnot_Witness.mqh"   // P-BK-107: the knot's own read, witnessed (needs DrawStripDiagEmit, so it sits here — above its only caller)
#include "EventHandlers_Objects.mqh"
#include "EventHandlers_Router_Gesture.mqh"   // the line's drag stream (was Router's middle)
#include "EventHandlers_Router.mqh"
#include "EventHandlers_Tail.mqh"

#endif // EVENT_HANDLERS_MQH
