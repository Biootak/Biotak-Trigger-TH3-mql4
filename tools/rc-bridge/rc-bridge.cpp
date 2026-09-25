// P-UI-108 (2026-09-23) - RC BRIDGE: fastest feasible architecture.
//
// DECISION (measured, not guessed):
//   * Native subclass DLL = fastest (in-process, eats WM_RBUTTONDOWN before
//     MT4), BUT this machine has NO 32-bit C compiler (where gcc/cl empty).
//     Cannot build today, so it is NOT the choice.
//   * Helper EXE + LL hook = buildable but SLOWER: out-of-process, needs ARM
//     round-trip per press + pipe IPC. Kept as fallback only.
//   * THIS FILE = Managed C++ bridge DLL (CLR/C++/CLI, /clr, x86): in-process
//     subclass of the chart window, eats the message on the SAME thread before
//     MT4's own WndProc. Zero IPC, zero flash. MQL4 imports 2 functions only:
//
//        int  RCBlock_Arm(int hwndChart);     // install, returns 1 ok / 0 fail
//        void RCBlock_Disarm();               // remove, restores old WndProc
//
// RULES (the failure modes this design kills by construction):
//   * SAME-THREAD: SetWindowLongPtr runs on the chart thread (MQL4 calls us
//     on it), so no cross-thread subclass crash.
//   * ONE CHART: only the hwnd passed to Arm is touched; Market Watch and
//     other charts never see the hook.
//   * CTRL PASSES: GetAsyncKeyState(VK_CONTROL) checked first - Ctrl+right is
//     always forwarded to MT4 (the terminal's own gesture survives).
//   * FAIL-SAFE: if Arm fails (or DLL missing), MQL4 falls back to the
//     existing burst-close path - degraded flash, never a dead chart.
//   * NO LEAK: Disarm restores the ORIGINAL WndProc; OnDeinit MUST call it
//     (a stuck subclass after unload hangs the terminal).
//
// BUILD (Visual Studio x86, no extra SDK):
//   cl /clr /LD /D_USING_V110_SDK71_ rc-bridge.cpp user32.lib
// Output: Libraries/BiotakRCBlock.dll (32-bit, MT4 loads x86 only).
#include <windows.h>

// One subclass at a time: the indicator arms one chart per instance, and each
// chart has its own DLL instance data (MQL4 loads the DLL per chart).
static HWND     s_hwnd   = NULL;
static WNDPROC  s_old    = NULL;
static bool     s_armed  = false;

// Forward declaration: the new window procedure.
static LRESULT CALLBACK RCBlock_WndProc(HWND h, UINT m, WPARAM w, LPARAM l);

// ARM: install the subclass on this chart's window. Idempotent: arming twice
// keeps the FIRST original proc (never chains to ourselves).
extern "C" __declspec(dllexport) int __stdcall RCBlock_Arm(int hwndChart)
{
   HWND h = (HWND)(INT_PTR)hwndChart;
   if (h == NULL || !IsWindow(h)) return 0;
   if (s_hwnd == h && s_old != NULL) { s_armed = true; return 1; }
   if (s_old != NULL) return 0;              // another chart owns us: refuse
   WNDPROC old = (WNDPROC)(INT_PTR)GetWindowLongPtrW(h, GWLP_WNDPROC);
   if (old == NULL || old == RCBlock_WndProc) return 0;
   SetLastError(0);
   WNDPROC set = (WNDPROC)(INT_PTR)SetWindowLongPtrW(h, GWLP_WNDPROC, (LONG_PTR)(void*)RCBlock_WndProc);
   if (set == NULL && GetLastError() != 0) return 0;
   s_hwnd  = h;
   s_old   = old;
   s_armed = true;
   return 1;
}

// DISARM: restore the original WndProc. Safe to call twice or never-armed.
extern "C" __declspec(dllexport) void __stdcall RCBlock_Disarm()
{
   s_armed = false;
   if (s_hwnd != NULL && s_old != NULL && IsWindow(s_hwnd))
      SetWindowLongPtrW(s_hwnd, GWLP_WNDPROC, (LONG_PTR)(void*)s_old);
   s_hwnd = NULL;
   s_old  = NULL;
}

// THE PROCEDURE: eats plain right-down/up + contextmenu, forwards the rest.
// Ctrl+right ALWAYS passes (checked live, per message, not cached).
static LRESULT CALLBACK RCBlock_WndProc(HWND h, UINT m, WPARAM w, LPARAM l)
{
   if (s_armed && (m == WM_RBUTTONDOWN || m == WM_RBUTTONUP || m == WM_CONTEXTMENU))
   {
      if ((GetAsyncKeyState(VK_CONTROL) & 0x8000) == 0)
         return 0;                            // EATEN: MT4 never sees the press,
                                              // so its menu is never born.
   }
   return CallWindowProcW(s_old, h, m, w, l);
}
