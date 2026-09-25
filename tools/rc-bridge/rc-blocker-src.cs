// P-UI-107 (2026-09-23) STEP 1 - RC-BLOCKER.
// WHY THIS EXISTS: the indicator's user32 lever (RightClickOwner.mqh) can only
// CLOSE the terminal menu after it is born (17-27 ms after the press, measured
// on this terminal). The only lever that stops it being born is a low-level
// mouse hook (WH_MOUSE_LL) that drops the right-button-down before the chart
// window procedure ever sees it - and MQL4 cannot install one (no HHOOK, no
// message loop), so a tiny helper EXE does it. No injection into terminal.exe,
// no subclass, no admin: the hook only watches, and drops (return 1) the one
// event the indicator armed (a plain right-down on an armed chart rect).
//
// PROTOCOL (stdin/stdout lines, so MQL4 pipes stay ASCII):
//   ARM <hwndChart> <x0> <y0> <x1> <y1>   arm one plain press (screen px rect)
//   DISARM                            drop the arm (after the press is answered)
//   QUIT                              exit
// Every line is ACKed with OK/ERR. While armed, a right-down INSIDE the rect
// is swallowed and reported as BLOCKED; a right-down OUTSIDE passes through.
// Ctrl+right is never blocked (the helper checks Ctrl itself): the terminal's
// own gesture always survives.
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

static class RcBlocker
{
   const int WH_MOUSE_LL = 14;
   const int WM_RBUTTONDOWN = 0x0204;
   const int VK_CONTROL = 0x11;

   delegate IntPtr HookProc(int code, IntPtr w, IntPtr l);

   [DllImport("user32.dll")] static extern IntPtr SetWindowsHookEx(int id, HookProc fn, IntPtr mod, uint tid);
   [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr h);
   [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr h, int code, IntPtr w, IntPtr l);
   [DllImport("user32.dll")] static extern short GetAsyncKeyState(int v);
   [DllImport("user32.dll")] static extern bool GetCursorPos(out P2 p);
   [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h, uint f);
   [DllImport("user32.dll")] static extern int GetWindowThreadProcessId(IntPtr h, out int pid);

   [StructLayout(LayoutKind.Sequential)] struct P2 { public int x; public int y; }
   [StructLayout(LayoutKind.Sequential)] struct MLL { public P2 pt; public int data; public int flags; public int time; public IntPtr extra; }

   static IntPtr s_hook = IntPtr.Zero;
   static HookProc s_proc;
   // One armed press: the chart rect in SCREEN pixels (the hook sees screen px).
   static int s_x0, s_y0, s_x1, s_y1;
   static bool s_armed = false;
   static readonly object s_gate = new object();

   static int Main()
   {
      s_proc = Hook;
      using (Process me = Process.GetCurrentProcess())
      using (ProcessModule mod = me.MainModule)
         s_hook = SetWindowsHookEx(WH_MOUSE_LL, s_proc, GetModuleHandleW(mod.ModuleName), 0);
      if (s_hook == IntPtr.Zero) { Console.WriteLine("ERR hook"); return 1; }
      Console.WriteLine("OK ready");
      string line;
      while ((line = Console.ReadLine()) != null)
      {
         string[] p = line.Split(' ');
         try
         {
            if (p[0] == "ARM" && p.Length == 6)
            {
               int hwnd = int.Parse(p[1]);
               int cx0 = int.Parse(p[2]), cy0 = int.Parse(p[3]);
               int cx1 = int.Parse(p[4]), cy1 = int.Parse(p[5]);
               // Chart rect (client px) -> screen px: offset by the chart origin.
               P2 org = new P2();
               ClientToScreen(hwnd, out org);
               lock (s_gate)
               {
                  s_x0 = org.x + Math.Min(cx0, cx1); s_y0 = org.y + Math.Min(cy0, cy1);
                  s_x1 = org.x + Math.Max(cx0, cx1); s_y1 = org.y + Math.Max(cy0, cy1);
                  s_armed = true;
               }
               Console.WriteLine("OK armed");
            }
            else if (p[0] == "DISARM") { lock (s_gate) { s_armed = false; } Console.WriteLine("OK idle"); }
            else if (p[0] == "QUIT") { Console.WriteLine("OK bye"); break; }
            else Console.WriteLine("ERR cmd");
         }
         catch { Console.WriteLine("ERR arg"); }
      }
      UnhookWindowsHookEx(s_hook);
      return 0;
   }

   static IntPtr Hook(int code, IntPtr w, IntPtr l)
   {
      if (code >= 0 && w.ToInt32() == WM_RBUTTONDOWN)
      {
         bool armed;
         int x0, y0, x1, y1;
         lock (s_gate) { armed = s_armed; x0 = s_x0; y0 = s_y0; x1 = s_x1; y1 = s_y1; }
         if (armed)
         {
            MLL m = (MLL)Marshal.PtrToStructure(l, typeof(MLL));
            // NEVER block Ctrl+right: the terminal's own gesture always passes.
            if ((GetAsyncKeyState(VK_CONTROL) & 0x8000) == 0 &&
                m.pt.x >= x0 && m.pt.x <= x1 && m.pt.y >= y0 && m.pt.y <= y1)
            {
               lock (s_gate) { s_armed = false; }   // one press, one block
               Console.WriteLine("BLOCKED " + m.pt.x + " " + m.pt.y);
               return (IntPtr)1;                     // DROP: the chart never sees it
            }
         }
      }
      return CallNextHookEx(s_hook, code, w, l);
   }

   [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandleW(string n);
   [DllImport("user32.dll")] static extern bool ClientToScreen(int h, out P2 p);
}
