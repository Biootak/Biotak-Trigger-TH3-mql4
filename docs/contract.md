# contract.md — the live rules (the only contract)

One page. A rule here is not advice: a surface that fails a line is a bug.
Every claim carries a number (file:line) or it is not a claim.
A note that no longer matches the code is DELETED, not kept — a stale `OPEN`
sends the next reader after a bug that no longer exists. There is no second archive:
this page IS the whole contract.

## 1. Ownership (one owner, never a second copy)

| value | owner |
|---|---|
| palette | `BioPickColor` / `BioPickAt` / `BIOPAL_N` (`ConstantsAndEnums.mqh`) |
| z ladder | `Z_*` (`ConstantsAndEnums.mqh`) — paint order IS click priority |
| ink | `BIO_CLR_*`; `PNL_CLR_*` / `DSTRIP_CLR_*` are aliases, never a second literal |
| text metrics | `PnlPt` / `PnlTextW` / `PnlLineH` / `PnlFit` (`UtilityFunctions.mqh`) |
| geometry | card `312 / 624 / 42 / 56 / 48`; plate law `48 + 42k` |
| swatch floor | `BioSwatchBorder` + `BIO_SWATCH_MIN_CONTRAST` |
| the UI claim | `UIPointerOverSurface` (where) + `UIPeekClickClaim` (whose) |
| view lock | `ChartLockIntended()` — a gesture that locks the view names itself the day it is born |

A *face* (alias, wrapper, reader) is expected. A second *owner* is the defect.
Include order is ownership: `ConstantsAndEnums` → `UtilityFunctions` → `DrawStrip`
→ `BiotakMenu` → `BiotakPanels`. Move a rule down, never copy it up.

## 2. What MT4 cannot do (and the answer we ship)

- no bitmap scaling — it crops: bake the size and 9-slice; crop, never stretch.
- no rounded corner, shadow or gradient on a native rect: bake the skin, and fill the
  object beneath with exactly the footer ink so no square peeks through a radius.
- no real translucency: bake the glass into the BMP; a solid underlayer under it.
- **`OBJPROP_TIMEFRAMES` is a LABEL-only property** — a rect/bitmap keeps showing. Hide a
  plate by EXISTENCE (delete it), never by a period mask.
- no mouse-wheel event, no double-click event, no right click without the native menu:
  ship explicit +/− or a drag, measure the click interval, use left gestures only.
- one target per pixel: only the highest ZORDER receives `CHARTEVENT_CLICK`; a face drawn
  above a control is non-selectable (skin above, button below).
- `ZORDER` cannot lift a panel over the candles: use `CHART_FOREGROUND`.
- object text truncates at **63 chars**: wrap one logical line into a family of objects.
- the object list is user-facing: chrome wears `OBJPROP_HIDDEN`; every created name is
  deleted by the same surface's destroy.

## 3. Appearance (the dirt list, hunted proactively — not only when reported)

A swatch that reads as a hole · a caption running into its control (use `PnlFit`) ·
hierarchy collapsing at other DPI (compute the points) · a hairline crossing ink ·
an off-grid plate edge · a shadow eaten by a neighbour · an empty bar over a readout ·
a ghost surface on the wrong timeframe · a stale surface after a TF switch · a hover face
left painted · a control that draws but cannot be hit (and the reverse) · a control
clipped by the card edge · flicker on a tick · the chart jumping under the hand · the
wrong object getting the click · a surface opening on the cursor over the work · two
surfaces overlapping · a colour that "does not work" because the face ignored the value ·
one act spelled two ways · a dead `Z_*` rung · a comment that cites a function nobody calls.

## 4. Lifecycle

Reattach · TF switch · terminal restart · template re-apply: every surface survives all
four. Panel-editable settings live in `RuntimeSettings.mqh` and nowhere else;
indicator-wide state in `GlobalVariables.mqh`; what must ride an object lives in its
`DESCRIPTION`. A placed surface's home key carries no chart and no symbol; the value that
paints (clamped) is never the value stored; a remove SAVES like any teardown.
Never advertise a state that did not happen — delete the mark, do not dim it.

## 5. Performance

Realtime is the same event: a follower writes in the event that moved its owner; a
deferred frame IS the lag. At rest: zero writes, zero polling. A still frame is reads only.
Nothing whose cost scales with the chart enters the mouse stream or the tick path, and
every walk is bounded by a stated count. The target is the weakest supported machine;
when two solutions behave the same, the cheaper one ships and its cost is a number
(`CPU_WARNING_MS 50` / `CPU_CRITICAL_MS 200`, `COOP_WARN_MS 40`).

## 6. Gate (definition of done)

1. `compile-th3.ps1 -Project all` → `Result: 0 errors` (Full), then the same for
   `Biotak Trigger TH3 Lite.mq4` and every harness (`-SourceFile`, one run each).
2. `node tools/submenu_geometry_check.js` passes.
3. No new literal for a colour, pixel, z-order or font; no second table.
4. Every swatch through `BioSwatchBorder`; every caption measured with `PnlFit`.
5. Every new raster has a `#resource` line AND a `tools/icon-manifest.txt` entry, and
   every file on disk has a manifest entry.
6. A change to generated assets hashes the set before and after: untouched files
   byte-identical.
7. The report names the file, the number and the measurement.

## 7. Size (one file, one owner)

One file = one owner, `<= 1500` lines (`[System.IO.File]::ReadAllLines`).
A file over the ceiling never grows: touch it = split it by owner
(state / names / layout / paint / router), same names, same output,
orphan sweep included. A new file over the ceiling fails the gate.
One function over the ceiling stays whole and never grows.
