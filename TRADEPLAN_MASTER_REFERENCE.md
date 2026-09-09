# TRex Trade Plan — Master vs Ours (reverse-engineering ledger)

> Snapshot compared: professor XAUUSD **Sep-9-2026 live** vs our `[SNAP]` dump
> `build-logs/tradeplan-latest.log` (terminal 12:18, broker 11:48).
> Formula owner: `Biotak/TradePlanFormulas.mqh`. Golden test:
> `Biotak_TradePlan_Golden_Test.mq4`.

---

## 1. The chain (confirmed, do not touch)

```
Eng(TF)   = iATR(trigTF, TF_min / trig_min, 1) / pip      <- SESSION ATR
slRaw(TF) = 1.20 * Eng(StructureTF)                       <- UNROUNDED
SL        = round(slRaw)
TP1/TP2/TP3 = round(slRaw * 7/3), round(slRaw * 5), round(slRaw * 31/3)
Hunter    = round(Eng(own) * 8/3)                         <- raw Eng, not round(Eng)
Base      = round(slRaw * 95/9)      Width = round(slRaw * 20/9)
display   M1..D1 : "Width -- Base"
          W1     : "round(slRaw * 16/3) -- Base"
          MN     : "(Base + Width) -- Base"   <- sum of the ROUNDED legs
Trigger = 2 rungs down (floor M1)   Structure = 2 rungs up (cap MN)
```

| Chart | Trigger | N = TF/trig | Structure |
|---|---|---|---|
| M1 | M1 | 1 | M15 |
| M5 | M1 | 5 | H1 |
| M15 | M1 | 15 | H4 |
| H1 | M5 | 12 | D1 |
| H4 | M15 | 16 | W1 |
| D1 | H1 | 24 | MN |
| W1 | H4 | 42 | MN |
| MN | D1 | 30 | MN |

---

## 2. What was wrong with our numbers (2026-09-09)

The live build printed `Eng(TF) = CompositeATR(triggerTF)` — the strip ATR of
the trigger timeframe — instead of the session ATR. Every downstream leg
(SL / TP / Hunter / StrBond) was already faithful, so **one wrong input moved
the whole block**:

| TF | Eng ours | Eng master | SL ours | SL master | TP3 ours | TP3 master | StrBond ours | StrBond master |
|---|---|---|---|---|---|---|---|---|
| M15 | 13.69 → 14 | **17** | 92 | **105** | 946 | **1089** | 204 -- 967 | **234 -- 1111** |
| H1 | 38.20 → 38 | **40** | 212 | **303** | 2194 | **3129** | 472 -- 2241 | **673 -- 3196** |
| H4 | 76.32 → 76 | **88** | 423 | **720** | 4375 | **7440** | 941 -- 4470 | **1600 -- 7600** |
| D1 | 176.92 → 177 | **252** | 1321 | **1180** | 13650 | **12189** | 2936 -- 13944 | **2621 -- 12451** |
| W1 | 352.86 → 353 | **600** | 1321 | **1180** | 13650 | **12189** | 7045 -- 13944 | **6291 -- 12451** |
| MN | 1100.82 → 1101 | **983** | 1321 | **1180** | 13650 | **12189** | 16880 -- 13944 | **15072 -- 12451** |

### The proof that Eng can never be a composite

M1, M5 and M15 **all share trigger M1** (rung floor). A per-trigger composite
returns the same number for the three of them. Our EURUSD dump showed exactly
that collapse:

```
[SNAP] M1 | 1.04 | 1.04 | 1 | 3 | ...
[SNAP] M5 | 2.12 | 1.04 | 1 | 3 | ...      <- engT identical to M1
```

The professor shows **4 / 8 / 17** for M1 / M5 / M15 — three different numbers
from one M1 series, i.e. nested windows `iATR(M1,1) < iATR(M1,5) < iATR(M1,15)`
(a market cooling off: last bar 3.8, last 5 avg 7.9, last 15 avg 16.5).
Only `iATR(trigTF, N, 1)` can produce that. **Never wire Eng to
`CalculateWeightedATR` / the strip ATR.** Guarded by
`Biotak_TradePlan_Golden_Test.mq4` (PART B).

> Our composite engine itself is fine — `TR(own)` matches his top-bar ATR
> (M15 76.32 vs 75, H1 176.92 vs 173, H4 352.86 vs 360, D1 1100.82 vs 1066).
> It is the right number in the wrong slot. W1/MN still read low
> (1630 vs 2003, 2282 vs 3144) — history depth, dynamic denominator.

---

## 3. Back-solve: his unrounded Eng ladder

Every rounded cell pins a half-unit window on `slRaw`; intersecting all of
them (SL, TP1, TP2, TP3, Base, Width) leaves a window barely wider than a
hundredth of a pip, and `Eng(str) = slRaw / 1.20`:

| Row | slRaw window | ⇒ Eng(StructureTF) | cross-check Hunter(str) |
|---|---|---|---|
| M1 | 19.790 .. 19.847 | Eng(M15) 16.492 .. 16.539 | 44 ⇒ 16.313 .. 16.688 ✓ |
| M5 | 47.795 .. 47.855 | Eng(H1) 39.829 .. 39.879 | 106 ⇒ 39.563 .. 39.938 ✓ |
| M15 | 105.339 .. 105.300 ⚠ | Eng(H4) ≈ 87.75 .. 87.78 | 234 ⇒ 87.563 .. 87.938 ✓ |
| H1 | 302.786 .. 302.826 | Eng(D1) 252.321 .. 252.355 | 673 ⇒ 252.188 .. 252.563 ✓ |
| H4 | 719.953 .. 720.047 | Eng(W1) 599.961 .. 600.039 | 1600 ⇒ 599.813 .. 600.188 ✓ |
| D1/W1/MN | 1179.532 .. 1179.616 | Eng(MN) 982.944 .. 983.013 | 2621 ⇒ 982.688 .. 983.063 ✓ |

⚠ **M15 is the one inconsistent row of his own table**: TP3 = 1089 needs
`slRaw >= 105.339` while Base = 1111 needs `slRaw <= 105.300`. A 0.04-pip gap,
so no single Eng(H4) satisfies both — the frozen StrBond leg and the live TP
legs were captured a tick apart. Replaying his ladder gives TP3 1088 / Base
1112 there: **±1 tolerance on the M15 row only**, everything else exact.

Feeding `Eng = {3.80, 7.90, 16.515, 39.854, 87.766, 252.338, 600.000, 982.978}`
through the chain reproduces **7 of 8 rows cell-for-cell**, including the
awkward ones: TP3 3129 (not 3131 — must ride `slRaw`, not `SL`), Hunter 10 for
Eng 4 (raw Eng, `round(4*8/3)` would give 11), Base 12451 (not 12456 — again
`slRaw`), W1 SB1 6291 via 16/3, MN SB1 12451+2621 = 15072 (sum of rounded, not
rounded sum 15073).

---

## 4. Diagonal theorem (holds in code, not an input)

`SB_Width(TF) == Hunter(StructureTF)` because `1.20 * 20/9 == 8/3`, so both
sides round the same double:

| TF | Width | Hunter(str) |
|---|---|---|
| H1 | 673 | D1 673 |
| H4 | 1600 | W1 1600 |
| D1 | 2621 | MN 2621 |

---

## 5. Regression history

| When (UTC) | Commit | Eng source | Verdict |
|---|---|---|---|
| 09-09 07:42 | `b2707d5` | `iATR(trigTF, N, 1)` | correct |
| 09-09 08:07 | `8a8a4b9` | MULT[TF] × composite(own) | wrong |
| 09-09 08:24 | `8ec0298` | composite(triggerTF) | wrong — **this is the build the 12:18 log came from** |
| 09-09 08:29 | `47125bc` | `iATR(trigTF, N, 1)` | correct (current `main`) |

So the deltas in §2 are a **stale EX4**, not a live formula error: rebuild from
`main` and re-dump before comparing again.
