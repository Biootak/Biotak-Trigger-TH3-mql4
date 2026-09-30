#ifndef HTF_CANDLES_MQH
#define HTF_CANDLES_MQH

#property strict

//+------------------------------------------------------------------+
//|                                            HTFCandles.mqh        |
//|                                                                  |
//| THE HTF CANDLE OVERLAY. This file is the HUB: it keeps the unit's |
//| public name — the entry (`Biotak Trigger TH3.mq4:115`) and          |
//| `BiotakMenu_A.mqh` both include `HTFCandles.mqh`, and the tests      |
//| and the gates resolve the same name — and nothing else. The code     |
//| lives in three parts, BY OWNER, included in the order they were      |
//| declared when they were one file (MQL4 has no forward declaration,   |
//| so include order IS ownership):                                       |
//|                                                                      |
//|   HTFCandles_Geom.mqh       state, the TF ladder, the index map, the  |
//|                             candle's shape (HTFCandleGeometry, the    |
//|                             P-HTF-SLOT pitch)                         |
//|   HTFCandles_Draw.mqh       the chart's objects: upsert, card cull,   |
//|                             prune, look probes, the draw passes       |
//|   HTFCandles_Life.mqh       birth (init), the 15 saved keys, cleanup  |
//|                                                                       |
//| P-HTF-SPLIT (2026-09-30). The single file reached 1519 lines against  |
//| the contract's 1500 ceiling (§7: a file over it never grows, touch it |
//| = split it by owner). The split MOVED lines: same names, same output, |
//| no behaviour rewritten — the four gates and the compile are what say  |
//| so, and `tools/check-regressions.js` fails if the hub stops reaching a |
//| part or a part stops being the one writer.                             |
//+------------------------------------------------------------------+

#include "HTFCandles_Geom.mqh"
#include "HTFCandles_Draw.mqh"
#include "HTFCandles_Life.mqh"

#endif // HTF_CANDLES_MQH
