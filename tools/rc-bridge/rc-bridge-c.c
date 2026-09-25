// P-UI-108b (2026-09-23) - RC BRIDGE, PURE C (no /clr, no CRT).
// WHY PURE C: the /clr build needs MSVC; this file builds with TinyCC (tcc,
// ~400 KB, downloads in seconds) or any x86 gcc. Zero CRT imports: only
// user32 + kernel32, so the DLL loads even on a bare terminal machine.
// Same contract as the C++ draft (rc-bridge.cpp is the readable spec):
//   RCBlock_Arm(int hwndChart) -> 1 ok / 0 fail
//   RCBlock_Disarm()           -> restores the original WndProc
// Same rules: same-thread subclass, one chart, Ctrl+right always passes,
// fail-safe (Arm fail = caller keeps the burst path), no leak (Disarm in
// OnDeinit). BUILD: tcc -shared -m32 -o BiotakRCBlock.dll rc-bridge-c.c
// P-UI-108d2 probe note (keep windows.h; the import names are correct).
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

static HWND    s_hwnd  = NULL;
static WNDPROC s_old   = NULL;
static BOOL    s_armed = FALSE;

// P-UI-108c: tcc maps *PtrW to the ANSI *W import (no Ptr export on Win32
// user32) - and MT4's loader fails the whole DLL (error 126) on ONE missing
// import. So use the guaranteed 32-bit pair explicitly.
#ifndef GetWindowLongPtrW
#define GetWindowLongPtrW GetWindowLongW
#endif
#ifndef SetWindowLongPtrW
#define SetWindowLongPtrW SetWindowLongW
#endif
#ifndef LONG_PTR
#define LONG_PTR long
#endif
static LRESULT CALLBACK RCBlock_WndProc(HWND h, UINT m, WPARAM w, LPARAM l)
{
   if (s_armed && (m == WM_RBUTTONDOWN || m == WM_RBUTTONUP || m == WM_CONTEXTMENU))
   {
      if ((GetAsyncKeyState(VK_CONTROL) & 0x8000) == 0)
         return 0;
   }
   return CallWindowProcW(s_old, h, m, w, l);
}

// DllMain: REMOVED (P-UI-108d). tcc's startup entry breaks MT4's loader.
// The MQL4 side owns the lifecycle: Arm on attach, Disarm on EVERY deinit
// (RightClickOwnerDeinit) - a stuck proc cannot outlive the indicator because
// the terminal unloads the DLL with it.

// Export ABI: MQL4 resolves the PLAIN name only (no _Name@N stdcall
// decoration), and tcc exports exactly the spelling written here. So both
// entry points are __cdecl (no suffix at all) - MQL4's importer calls them
// by plain name. The bodies touch only HWND/ints, so the convention change
// costs nothing.
__declspec(dllexport) int RCBlock_Arm(int hwndChart)
{
   HWND h = (HWND)(INT_PTR)hwndChart;
   if (h == NULL || !IsWindow(h)) return 0;
   if (s_hwnd == h && s_old != NULL) { s_armed = TRUE; return 1; }
   if (s_old != NULL) return 0;
   {
      WNDPROC old = (WNDPROC)(INT_PTR)GetWindowLongPtrW(h, GWLP_WNDPROC);
      if (old == NULL || old == RCBlock_WndProc) return 0;
      SetLastError(0);
      (void)SetWindowLongPtrW(h, GWLP_WNDPROC, (LONG_PTR)RCBlock_WndProc);
      if (GetLastError() != 0) return 0;
      s_hwnd = h; s_old = old; s_armed = TRUE;
      return 1;
   }
}

__declspec(dllexport) void RCBlock_Disarm(void)
{
   s_armed = FALSE;
   if (s_hwnd != NULL && s_old != NULL && IsWindow(s_hwnd))
      SetWindowLongPtrW(s_hwnd, GWLP_WNDPROC, (LONG_PTR)s_old);
   s_hwnd = NULL; s_old = NULL;
}
