//+------------------------------------------------------------------+
//| BuildHash.mqh — GENERATED FILE. DO NOT EDIT.                      |
//|                                                                   |
//| Owner: tools/gen-build-hash.js, run by compile-th3.ps1.           |
//|                                                                   |
//| TH3_SRC_HASH is a SHA-256 (16 hex chars) over the bytes of every  |
//| file these entries compile: the two .mq4 entries, every .mqh they |
//| #include transitively, and every raster they #resource. It is the |
//| ONLY build identity the panel and the log print — a hand-typed tag |
//| cannot change when the code changes, and that is how a stale ex4   |
//| printed the same line as a fresh one for eight days.              |
//|                                                                   |
//| same tree -> same hash ; any edit -> a different hash              |
//|                                                                   |
//| files=421 hash=d6850439efc71554
//+------------------------------------------------------------------+
#ifndef TH3_BUILD_HASH_MQH
#define TH3_BUILD_HASH_MQH

#define TH3_SRC_HASH   "d6850439efc71554"   // full identity, printed in the log
#define TH3_SRC_SHORT  "d6850439"           // the 8-char stamp the panel chip shows
#define TH3_SRC_FILES  421                // files covered by the hash

#endif // TH3_BUILD_HASH_MQH
