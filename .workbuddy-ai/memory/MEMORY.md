# MEMORY.md — Biotak Trigger TH3 (project, long-term)

## The live terminal (the only one that proves anything)

```
%APPDATA%\MetaQuotes\Terminal\A1660DA4CB596E740BE3B3233E577E1B
  exe     : C:\Program Files (x86)\AMarkets - MetaTrader 4\terminal.exe
  logs    : MQL4\Logs\YYYYMMDD.log   (the ONLY place a runtime fact is proved)
  charts  : profiles\default\chart01..06.chr
  MQL4\Indicators\BiotakProject  ->  SYMLINK to this repo (a compile IS the .ex4)
```
Full entry is the one attached on the user's charts. MT4 has NO hot swap: after a
compile the user must re-add the indicator (or change TF / restart) — the terminal log's
`loaded successfully` line is what says which build is live.

## DLL imports are NOT allowed on this terminal (measured 2026-09-17)

```
15:07:48.627  Cannot call 'user32.dll::GetAncestor', DLL is not allowed
15:07:48.627  Vazir-Khakestari EURUSD,M5: unresolved import function call
```
The program is STOPPED by the refused call — but it still LOADS and initialises first, so
the failure lands at the first call, not at attach. Consequence for any user32 work:
- the indicator's "Common → Allow DLL imports" must be ticked, or
- it fails visibly at attach if the call is put in `OnInitHandler` (the deliberate choice).

## MT4's chart context menu — the facts that decide any design

1. `CHART_CONTEXT_MENU` is a **stub** on this build: the write is refused and the getter
   answers 0 forever (`[ctxmenu] impl-probe: mouseScroll=1 write(true)=refused readback=0
   => STUB`). `.chr` files carry no `contextmenu` key. It is NOT a lever.
2. **The menu is created ON THE BUTTON-DOWN, ~20 ms LATE** (measured 2026-09-23, twice:
   `DOWN-held: popup first seen at +24 ms`, refined to 17..27 ms). It is born at (0,0) with
   its final 206x653 size and then moved to the click point, and it survives the release.
   Consequence: `CHARTEVENT_CLICK` never arrives for a right click, AND a close posted at
   the press edge is DRAINED by the terminal's idle loop during those ~20 ms — which is why
   the old press-edge ESC never worked (P-UI-102 finding C).
3. The menu is a `#32768` popup on the terminal's ONE message thread, and this build
   creates it with **GW_OWNER = 0**, so an ownership test built on the owner can never
   pass. Identify it by thread + "this chart has a press waiting" instead.
4. **THE CADENCE IS THE LEVER, NOT THE MESSAGE** (P-UI-103). A close that arrives LATE —
   just before or while the menu's own loop runs — works in 1-2 ms: posted
   `WM_KEYDOWN/ESC` to the popup ~1 ms, to the chart ~2 ms, posted `WM_CANCELMODE` ~0 ms.
   What does NOT work: `SendMessage` (synchronous, handled inside the terminal's own press
   processing — the menu lived 54 ms), and `ShowWindow(SW_HIDE)` (MT4 re-shows the menu
   while positioning it). `RightClickOwner.mqh`'s fast window raises the timer cadence to
   1 ms for 900 ms on a plain press and posts every tick; the housekeeping is let through
   on its own 250 ms due time so only the cadence changes.
5. Measuring a foreign window's popup from outside: `GetPixel` on this composited screen
   costs **16.6 ms a call** — a pixel/paint oracle is impossible at that resolution, so use
   popup VISIBILITY. Harnesses at the repo root: `_rc-when.ps1`, `_rc-race.ps1`,
   `_rc-bench.ps1`; pin the terminal topmost (`SetWindowPos`) and verify the cursor, the
   foreground AND that the point is the chart VIEW, or the run reports a false "NO MENU".
6. **A menu command MQL4 "cannot call" is still callable** (measured 2026-09-23):
   `PostMessageW(mainFrame, WM_COMMAND /*0x0111*/, MAKEWPARAM(id, 0), 0)` fires MT4's own
   commands. Proven by diffing every child window around the post — Navigator 33310 hid
   its bar, Market Watch 33309 / Terminal 33314 / Data Window 33302 showed theirs, all
   reversible. Ids read off THIS terminal's live menu bar by `_mt4-menu-ids.ps1`:
   Indicators List 35419, Objects List 35402, Properties 33157 (F8), Navigator 33310,
   Market Watch 33309, Terminal 33314, Data Window 33302, Strategy Tester 33315,
   Grid 33021, Volumes 33024, Auto Scroll 33017, Chart Shift 33023, Zoom In/Out
   33025/33026, Refresh 33324, Save/Load Template 33220/35511, Bar/Candles/Line
   33018/33019/33022, Save As Picture 33054, New Order 33266, History Center 33262,
   Global Variables 35403, Options 33265, Full Screen 33305, Symbols 38313.
   The chart context menu needs no separate reading — it is built from the same command
   set. Chart-scoped ids act on the **active** chart, so bring it to the front first.
7. `GetMenuItemCount` / `GetMenuItemID` / `GetMenuString` take an **HMENU**, not an HWND —
   an HWND answers 0 and does not throw. `GetMenu(popupHwnd)` is 0 for a `TrackPopupMenu`
   popup; `MN_GETHMENU` (0x01E1) is the route, and even that answers 0 while the owning
   thread is still settling, so retry it.


## Key-state probes on this terminal (measured 2026-09-23)

`TerminalInfoInteger(TERMINAL_KEYSTATE_CONTROL)` **answers "held" while nothing is
held** — six plain right-clicks all logged `ctrl=1`. Use `GetAsyncKeyState(VK_CONTROL)
& 0x8000` (user32) for Ctrl. By the MQL4 doc table `TERMINAL_KEYSTATE_LEFT/RIGHT/UP/DOWN`
are the ARROW keys, not mouse buttons, so `UILeftButtonDown()` (P-UI-73) is not a mouse
probe either.

`P-UI-102` (`Biotak/RightClickOwner.mqh`, Full only, needs "Allow DLL imports") is the
right-click owner; the Ctrl gate is published through `RightClickTerminalOwns()` in
`UtilityFunctions.mqh` because `BaseKnotTool` is shared and asks it (P-BUILD-01).

## Audit-suite lessons paid for here

- An anchor that no longer matches the source turns a gate into a permanent red that
  blames clean code. Re-point it the moment the source line changes (panel-wiring's
  `[th-percent]`, after P-UI-57).
- A mutant with no leg is a case that can never fail: adding a mutant means adding the
  check it is supposed to break (panel-wiring's caption heal + caption grow).
- A file-wide search for a key name is a false positive waiting to happen: scope the
  assertion to the function that owns the choice (panel-wiring's P-BK-66 CONTROL gate).
- Compile every root `.mq4`, not just the entries: the harnesses mirror the entry's
  include chain by hand, so a new module breaks them with two `error 168`s (P-BUILD-02).
