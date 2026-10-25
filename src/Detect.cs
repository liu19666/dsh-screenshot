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
    // Top-level windows in Z-order, front-most first. Must skip invisible, cloaked,
    // zero-area and own-process windows.
    public static List<WindowInfo> EnumerateWindows(int excludePid)
    {
        return new List<WindowInfo>();
    }

    public static List<MonitorInfo> EnumerateMonitors()
    {
        // TODO(engine-dev): System.Windows.Forms.Screen.AllScreens (per-monitor DPI aware),
        // one MonitorInfo per screen, WorkArea from Screen.WorkingArea.
        return new List<MonitorInfo>();
    }

    // The heart of the feature: which region does the pointer designate?
    // Precedence: window under the cursor > taskbar > the monitor the cursor is on.
    public static TargetHit HitTest(Point pt, int excludePid)
    {
        var hit = new TargetHit();
        foreach (var m in EnumerateMonitors())
        {
            var r = m.Bounds.ToRectangle();
            if (r.Contains(pt))
            {
                hit.Kind = TargetKind.Monitor;
                hit.Rect = m.Bounds;
                hit.Source = "monitor";
                break;
            }
        }
        return hit;
    }

    // Taskbar rectangle for the monitor that contains it; empty when auto-hidden.
    public static TargetRect TaskbarBounds(TargetRect monitorBounds)
    {
        return new TargetRect();
    }
}