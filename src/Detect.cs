// Target detection engine (owner: engine-dev).
//
// Contract: the overlay calls HitTest() on every mouse move and paints the returned
// rect. Screen sizes and taskbar geometry MUST come from the OS (EnumDisplayMonitors /
// Screen / SHAppBarMessage / SPI_GETWORKAREA); nothing may be hard-coded.
//
// This file must stay free of WinForms UI code and must compile for C# 5 (net48 csc).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

public enum TargetKind
{
    None = 0,
    Window = 1,
    Monitor = 2,
    Taskbar = 3
}

[StructLayout(LayoutKind.Sequential)]
public struct TargetRect
{
    public int X;
    public int Y;
    public int W;
    public int H;

    public TargetRect(int x, int y, int w, int h) { X = x; Y = y; W = w; H = h; }

    public Rectangle ToRectangle() { return new Rectangle(X, Y, W, H); }

    public static TargetRect FromRectangle(Rectangle r) { return new TargetRect(r.X, r.Y, r.Width, r.Height); }

    public override string ToString() { return X + "," + Y + " " + W + "x" + H; }
}

public sealed class WindowInfo
{
    public IntPtr Handle;
    public TargetRect Bounds;
    public string ClassName = "";
    public string Title = "";
    public int ZOrder;
    public bool Topmost;
    public bool IsToolWindow;
}

public sealed class MonitorInfo
{
    public TargetRect Bounds;
    public TargetRect WorkArea;
    public bool Primary;
}

public sealed class TargetHit
{
    public TargetKind Kind = TargetKind.None;
    public TargetRect Rect;
    public string Label = "";
    // Human readable source of the hit, for logs and tests ("window", "taskbar", "monitor").
    public string Source = "";

    public bool IsEmpty { get { return Kind == TargetKind.None || Rect.W <= 0 || Rect.H <= 0; } }
}

public static class Detect
{
    [DllImport("user32.dll")]
    private static extern bool SetProcessDPIAware();

    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    private static extern int GetClassName(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll")]
    private static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out int pvAttribute, int cbAttribute);

    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out RECT pvAttribute, int cbAttribute);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    private static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    private static extern IntPtr FindWindowEx(IntPtr hWndParent, IntPtr hWndChildAfter, string lpszClass, string lpszWindow);

    [DllImport("shell32.dll")]
    private static extern IntPtr SHAppBarMessage(uint dwMessage, ref APPBARDATA pData);

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct APPBARDATA
    {
        public int cbSize;
        public IntPtr hWnd;
        public uint uCallbackMessage;
        public uint uEdge;
        public RECT rc;
        public IntPtr lParam;
    }

    private const int GWL_EXSTYLE = -20;
    private const int WS_EX_TOOLWINDOW = 0x00000080;
    private const int WS_EX_TOPMOST = 0x00000008;
    private const int DWMWA_EXTENDED_FRAME_BOUNDS = 9;
    private const int DWMWA_CLOAKED = 14;
    private const uint ABM_GETSTATE = 0x00000004;
    private const uint ABS_AUTOHIDE = 0x00000001;

    static Detect()
    {
        try { SetProcessDPIAware(); } catch { }
    }

    // Top-level windows in Z-order, front-most first. Must skip invisible, cloaked,
    // zero-area and own-process windows. ZOrder starts from 0 (0 = front-most).
    public static List<WindowInfo> EnumerateWindows(int excludePid)
    {
        var list = new List<WindowInfo>();
        int currentPid = 0;
        try { currentPid = Process.GetCurrentProcess().Id; } catch { }

        int z = 0;
        EnumWindows(delegate(IntPtr hWnd, IntPtr lParam)
        {
            if (!IsWindowVisible(hWnd)) return true;
            if (IsIconic(hWnd)) return true;

            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            if (excludePid != 0 && (int)pid == excludePid) return true;
            if (currentPid != 0 && (int)pid == currentPid) return true;

            int exStyle = GetWindowLong(hWnd, GWL_EXSTYLE);
            if ((exStyle & WS_EX_TOOLWINDOW) != 0) return true;

            int cloaked = 0;
            if (DwmGetWindowAttribute(hWnd, DWMWA_CLOAKED, out cloaked, 4) == 0 && cloaked != 0)
            {
                return true;
            }

            var sbClass = new StringBuilder(256);
            GetClassName(hWnd, sbClass, sbClass.Capacity);
            string cls = sbClass.ToString();

            // Exclude taskbars and desktop shell windows
            if (string.Equals(cls, "Shell_TrayWnd", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(cls, "Shell_SecondaryTrayWnd", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(cls, "Progman", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(cls, "WorkerW", StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }

            RECT rect;
            int hr = DwmGetWindowAttribute(hWnd, DWMWA_EXTENDED_FRAME_BOUNDS, out rect, Marshal.SizeOf(typeof(RECT)));
            if (hr != 0 || rect.Right <= rect.Left || rect.Bottom <= rect.Top)
            {
                GetWindowRect(hWnd, out rect);
            }

            int w = rect.Right - rect.Left;
            int h = rect.Bottom - rect.Top;
            if (w <= 0 || h <= 0) return true;

            var sbTitle = new StringBuilder(512);
            GetWindowText(hWnd, sbTitle, sbTitle.Capacity);
            string title = sbTitle.ToString();

            bool topmost = (exStyle & WS_EX_TOPMOST) != 0;

            WindowInfo info = new WindowInfo();
            info.Handle = hWnd;
            info.Bounds = new TargetRect(rect.Left, rect.Top, w, h);
            info.ClassName = cls;
            info.Title = title;
            info.ZOrder = z++;
            info.Topmost = topmost;
            info.IsToolWindow = false;

            list.Add(info);
            return true;
        }, IntPtr.Zero);

        return list;
    }

    public static List<MonitorInfo> EnumerateMonitors()
    {
        var list = new List<MonitorInfo>();
        Screen[] screens = Screen.AllScreens;
        if (screens != null && screens.Length > 0)
        {
            for (int i = 0; i < screens.Length; i++)
            {
                var s = screens[i];
                MonitorInfo m = new MonitorInfo();
                m.Bounds = TargetRect.FromRectangle(s.Bounds);
                m.WorkArea = TargetRect.FromRectangle(s.WorkingArea);
                m.Primary = s.Primary;
                list.Add(m);
            }
        }
        else
        {
            Rectangle r = SystemInformation.VirtualScreen;
            MonitorInfo m = new MonitorInfo();
            m.Bounds = TargetRect.FromRectangle(r);
            m.WorkArea = TargetRect.FromRectangle(r);
            m.Primary = true;
            list.Add(m);
        }
        return list;
    }

    // ---- Hot-path cache (t16 / REVIEW-T7 F-12) ---------------------------------
    // HitTest runs on every overlay MouseMove (~25 Hz); each uncached call paid a
    // full window enumeration plus per-monitor taskbar FindWindow loops. A short
    // TTL snapshot keeps one motion burst cheap while still reflecting the live
    // desktop between bursts. EnumerateWindows/EnumerateMonitors stay pure; only
    // HitTest populates or serves the snapshot, and InvalidateCache() forces the
    // next HitTest to re-enumerate (call it after any known desktop change).
    const int CacheTtlMs = 150;
    static readonly object cacheLock = new object();
    static List<WindowInfo> cachedWindows;
    static int cachedWindowsPid;
    static List<MonitorInfo> cachedMonitors;
    static List<TargetRect> cachedTaskbars;
    static DateTime cacheUntilUtc = DateTime.MinValue;

    // Number of HitTest calls served from the snapshot instead of a fresh
    // enumeration; diagnostics for the F-12 tests and the perf log.
    public static long CacheHits { get; private set; }

    // Drop the snapshot so the next HitTest re-enumerates windows, monitors and
    // taskbar rectangles. Signature-only API: existing call sites keep working.
    public static void InvalidateCache()
    {
        lock (cacheLock)
        {
            cachedWindows = null;
            cachedMonitors = null;
            cachedTaskbars = null;
            cacheUntilUtc = DateTime.MinValue;
        }
    }

    static bool TryGetSnapshot(int excludePid, out List<MonitorInfo> monitors, out List<TargetRect> taskbars, out List<WindowInfo> windows)
    {
        lock (cacheLock)
        {
            if (cachedWindows != null && cachedMonitors != null && cachedTaskbars != null &&
                cachedWindowsPid == excludePid && DateTime.UtcNow < cacheUntilUtc)
            {
                monitors = CloneMonitors(cachedMonitors);
                taskbars = new List<TargetRect>(cachedTaskbars);
                windows = CloneWindows(cachedWindows);
                return true;
            }
        }
        monitors = null;
        taskbars = null;
        windows = null;
        return false;
    }

    static void StoreSnapshot(List<WindowInfo> windows, int excludePid, List<MonitorInfo> monitors, List<TargetRect> taskbars)
    {
        lock (cacheLock)
        {
            cachedWindows = windows;
            cachedWindowsPid = excludePid;
            cachedMonitors = monitors;
            cachedTaskbars = taskbars;
            cacheUntilUtc = DateTime.UtcNow.AddMilliseconds(CacheTtlMs);
        }
    }

    static List<WindowInfo> CloneWindows(List<WindowInfo> source)
    {
        var copy = new List<WindowInfo>(source.Count);
        for (int i = 0; i < source.Count; i++)
        {
            WindowInfo w = source[i];
            WindowInfo c = new WindowInfo();
            c.Handle = w.Handle;
            c.Bounds = w.Bounds;
            c.ClassName = w.ClassName;
            c.Title = w.Title;
            c.ZOrder = w.ZOrder;
            c.Topmost = w.Topmost;
            c.IsToolWindow = w.IsToolWindow;
            copy.Add(c);
        }
        return copy;
    }

    static List<MonitorInfo> CloneMonitors(List<MonitorInfo> source)
    {
        var copy = new List<MonitorInfo>(source.Count);
        for (int i = 0; i < source.Count; i++)
        {
            MonitorInfo m = source[i];
            MonitorInfo c = new MonitorInfo();
            c.Bounds = m.Bounds;
            c.WorkArea = m.WorkArea;
            c.Primary = m.Primary;
            copy.Add(c);
        }
        return copy;
    }

    // The heart of the feature: which region does the pointer designate?
    // Precedence: Taskbar > Window under cursor > Monitor the cursor is on.
    public static TargetHit HitTest(Point pt, int excludePid)
    {
        var hit = new TargetHit();
        bool isZh = System.Globalization.CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "zh";

        // One snapshot per TTL burst instead of a full re-enumeration per mouse move
        // (F-12): same priority order, same results, InvalidateCache() to force fresh.
        List<MonitorInfo> monitors;
        List<TargetRect> taskbars;
        List<WindowInfo> windows;
        if (!TryGetSnapshot(excludePid, out monitors, out taskbars, out windows))
        {
            monitors = EnumerateMonitors();
            windows = EnumerateWindows(excludePid);
            taskbars = new List<TargetRect>(monitors.Count);
            for (int i = 0; i < monitors.Count; i++) taskbars.Add(TaskbarBounds(monitors[i].Bounds));
            StoreSnapshot(windows, excludePid, monitors, taskbars);
        }
        else
        {
            CacheHits++;
        }

        // 1. Taskbar check (highest precedence as taskbar is always topmost)
        for (int i = 0; i < monitors.Count; i++)
        {
            TargetRect tb = taskbars[i];
            if (tb.W > 0 && tb.H > 0 && tb.ToRectangle().Contains(pt))
            {
                hit.Kind = TargetKind.Taskbar;
                hit.Rect = tb;
                hit.Label = isZh ? "任务栏" : "Taskbar";
                hit.Source = "taskbar";
                return hit;
            }
        }

        // 2. Window check (first in Z-order; windows come from the shared snapshot)
        for (int i = 0; i < windows.Count; i++)
        {
            var win = windows[i];
            if (win.Bounds.ToRectangle().Contains(pt))
            {
                hit.Kind = TargetKind.Window;
                hit.Rect = win.Bounds;
                hit.Label = !string.IsNullOrEmpty(win.Title) ? win.Title : win.ClassName;
                hit.Source = "window";
                return hit;
            }
        }

        // 3. Monitor check
        for (int i = 0; i < monitors.Count; i++)
        {
            var m = monitors[i];
            if (m.Bounds.ToRectangle().Contains(pt))
            {
                hit.Kind = TargetKind.Monitor;
                hit.Rect = m.Bounds;
                hit.Label = (isZh ? "屏幕 " : "Display ") + (i + 1);
                hit.Source = "monitor";
                return hit;
            }
        }

        return hit;
    }

    // Taskbar rectangle for the monitor that contains it; empty when auto-hidden or not found.
    public static TargetRect TaskbarBounds(TargetRect monitorBounds)
    {
        try
        {
            APPBARDATA abd = new APPBARDATA();
            abd.cbSize = Marshal.SizeOf(typeof(APPBARDATA));
            IntPtr state = SHAppBarMessage(ABM_GETSTATE, ref abd);
            if ((state.ToInt64() & ABS_AUTOHIDE) != 0)
            {
                return new TargetRect(0, 0, 0, 0);
            }
        }
        catch { }

        List<IntPtr> tbWindows = new List<IntPtr>();
        IntPtr primaryTb = IntPtr.Zero;
        try
        {
            primaryTb = FindWindow("Shell_TrayWnd", null);
            if (primaryTb != IntPtr.Zero) tbWindows.Add(primaryTb);

            IntPtr sec = IntPtr.Zero;
            while ((sec = FindWindowEx(IntPtr.Zero, sec, "Shell_SecondaryTrayWnd", null)) != IntPtr.Zero)
            {
                tbWindows.Add(sec);
            }
        }
        catch { }

        Rectangle targetMonitorRect = monitorBounds.ToRectangle();
        bool monitorGiven = monitorBounds.W > 0 && monitorBounds.H > 0;

        for (int i = 0; i < tbWindows.Count; i++)
        {
            IntPtr hWnd = tbWindows[i];
            if (!IsWindowVisible(hWnd)) continue;

            RECT r;
            int hr = DwmGetWindowAttribute(hWnd, DWMWA_EXTENDED_FRAME_BOUNDS, out r, Marshal.SizeOf(typeof(RECT)));
            if (hr != 0 || r.Right <= r.Left || r.Bottom <= r.Top)
            {
                GetWindowRect(hWnd, out r);
            }

            int w = r.Right - r.Left;
            int h = r.Bottom - r.Top;
            if (w <= 2 || h <= 2) continue;

            Rectangle tbRect = new Rectangle(r.Left, r.Top, w, h);
            if (!monitorGiven)
            {
                if (hWnd == primaryTb) return TargetRect.FromRectangle(tbRect);
            }
            else
            {
                Rectangle inter = Rectangle.Intersect(targetMonitorRect, tbRect);
                if (inter.Width > 10 && inter.Height > 10)
                {
                    return TargetRect.FromRectangle(tbRect);
                }
            }
        }

        // Fallback: deduce from Screen.Bounds vs Screen.WorkingArea
        if (monitorGiven)
        {
            try
            {
                Screen[] screens = Screen.AllScreens;
                if (screens != null)
                {
                    for (int i = 0; i < screens.Length; i++)
                    {
                        var s = screens[i];
                        if (s.Bounds == targetMonitorRect)
                        {
                            Rectangle b = s.Bounds;
                            Rectangle wa = s.WorkingArea;
                            if (b != wa)
                            {
                                if (wa.Y > b.Y)
                                    return new TargetRect(b.X, b.Y, b.Width, wa.Y - b.Y);
                                if (wa.Bottom < b.Bottom)
                                    return new TargetRect(b.X, wa.Bottom, b.Width, b.Bottom - wa.Bottom);
                                if (wa.X > b.X)
                                    return new TargetRect(b.X, b.Y, wa.X - b.X, b.Height);
                                if (wa.Right < b.Right)
                                    return new TargetRect(wa.Right, b.Y, b.Right - wa.Right, b.Height);
                            }
                        }
                    }
                }
            }
            catch { }
        }

        return new TargetRect(0, 0, 0, 0);
    }
}
