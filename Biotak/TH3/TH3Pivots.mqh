//+------------------------------------------------------------------+
//| TH3/TH3Pivots.mqh                                                |
//| THE COURSE'S OWN PIVOT, AS A DETECTOR — from the course PDF      |
//| («دوره ی تیرکس», pp. 6-7 pivot, p. 3 fractal TFs, p. 50 shared). |
//|                                                                  |
//| WHY THIS MODULE EXISTS. The TH3 tool's pivots were whatever the  |
//| user clicked. The course defines a pivot by SIX conditions on    |
//| the candles themselves, knowable at a bar's close with only a    |
//| candle-sized reversal after it — so the pivots can be FOUND,     |
//| marked, and drawn on, multi-timeframe and fractally.             |
//|                                                                  |
//| THE SIX CONDITIONS, with the course's own numbers (p. 7):        |
//|  1. fewer than FOUR side/range candles before the move           |
//|     (four or more make it a BASE pivot, not a plain pivot);      |
//|  2. at least THREE standard candles in one direction before it,  |
//|     or a move of at least 240% of ATR (240..360 band's floor);   |
//|  3. a reversal of at least 80% of the SAME timeframe's ATR,      |
//|     in one candle or several;                                    |
//|  4. the candle before the pivot is a MASTER candle (80% body or  |
//|     80% shadow, p. 6) that gets covered — or, if it is not a     |
//|     master, a HYPOTHETICAL 1-ATR range at the extreme is drawn   |
//|     and the pivot is declared only when that line is covered;    |
//|  5. the covering candle engulfs the trading knot ahead of it —   |
//|     per p. 6 that IS the cover of the master / the hypothetical  |
//|     1-ATR line, so it is the same event and carries its own flag;|
//|  6. the covering candle closes in its FINAL THIRD in the         |
//|     reversal's direction.                                        |
//|                                                                  |
//| MULTI-TIMEFRAME, FRACTALLY (p. 3): timeframes chain by a factor  |
//| of FOUR — 1 -> 5 -> 15 -> 60 -> 240 -> 1440 -> 10080 -> 43200    |
//| (the course's own approximations). Three roles per chart:        |
//| structure = one chain step UP, pattern = the chart's own TF,     |
//| trigger = one chain step DOWN. The same detector runs on every   |
//| TF against THAT TF's own ATR — that is what makes it fractal.    |
//|                                                                  |
//| SHARED PIVOTS (p. 50, «پیوت های مشترک یا هم پوشا»): a pivot that |
//| fits two timeframes at once belongs to the HIGHER one. A chart-TF|
//| pivot whose extreme sits inside a structure-TF pivot's span with |
//| the same direction is flagged `shared` and wears the higher TF.  |
//|                                                                  |
//| No chart-object access — the markers that display these live in  |
//| TH3Renderer.mqh; this module only measures.                      |
//+------------------------------------------------------------------+
#ifndef TH3_PIVOTS_MQH
#define TH3_PIVOTS_MQH

#include "TH3Pivots_A.mqh"
#include "TH3Pivots_B.mqh"

#endif // TH3_PIVOTS_MQH



