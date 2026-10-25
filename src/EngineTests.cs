// Headless test entry point for the detection + long-shot engines (owner: engine-dev).
//   bin/EngineTests.exe --json out.json --png out-dir
// Writes machine readable results and exits 0 only when every check passed.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Text;
using System.Windows.Forms;

public static class EngineTests
{
    private sealed class CheckResult
    {
        public string Name;
        public bool Passed;
        public string Details;
        public string Error;
    }

    [STAThread]
    public static int Main(string[] args)
    {
        // STAThread is REQUIRED by the --hit-helper WinForms Form below: an MTA
        // thread is an unsupported (and empirically flaky) host for a shown Form.
        string jsonPath = null;
        string pngDir = null;
        for (int i = 0; i < args.Length; i++)
        {
            if (args[i] == "--json" && i + 1 < args.Length) jsonPath = args[++i];
            else if (args[i] == "--png" && i + 1 < args.Length) pngDir = args[++i];
            else if (args[i] == "--hit-helper" && i + 1 < args.Length) return RunHitHelper(args[++i]);
        }

        if (!string.IsNullOrEmpty(pngDir))
        {
            try { Directory.CreateDirectory(pngDir); } catch { }
        }

        if (!string.IsNullOrEmpty(jsonPath))
        {
            try
            {
                string dir = Path.GetDirectoryName(jsonPath);
                if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            }
            catch { }
        }

        List<CheckResult> checks = new List<CheckResult>();

        // Run all checks
        checks.Add(TestEnumerateWindows());
        checks.Add(TestEnumerateMonitors());
        checks.Add(TestTaskbarAndHitTest());
        checks.Add(TestDetectDumpVisualization(pngDir));
        checks.Add(TestDetectHitTestCache());

        bool allPassed = true;
        int passedCount = 0;
        int failedCount = 0;

        for (int i = 0; i < checks.Count; i++)
        {
            if (checks[i].Passed)
            {
                passedCount++;
                Console.WriteLine("[PASS] " + checks[i].Name + ": " + checks[i].Details);
            }
            else
            {
                allPassed = false;
                failedCount++;
                Console.WriteLine("[FAIL] " + checks[i].Name + ": " + checks[i].Error);
            }
        }

        // Build JSON output
        StringBuilder sb = new StringBuilder();
        sb.Append('{');
        sb.Append('"').Append("ok").Append('"').Append(':').Append(allPassed ? "true" : "false").Append(',');
        sb.Append('"').Append("timestamp").Append('"').Append(':').Append('"').Append(DateTime.UtcNow.ToString("o")).Append('"').Append(',');
        sb.Append('"').Append("checks").Append('"').Append(':').Append('[');
        for (int i = 0; i < checks.Count; i++)
        {
            if (i > 0) sb.Append(',');
            sb.Append('{');
            sb.Append('"').Append("name").Append('"').Append(':').Append('"').Append(EscapeJson(checks[i].Name)).Append('"').Append(',');
            sb.Append('"').Append("status").Append('"').Append(':').Append('"').Append(checks[i].Passed ? "passed" : "failed").Append('"').Append(',');
            sb.Append('"').Append("details").Append('"').Append(':').Append('"').Append(EscapeJson(checks[i].Details)).Append('"');
            if (!checks[i].Passed && !string.IsNullOrEmpty(checks[i].Error))
            {
                sb.Append(',').Append('"').Append("error").Append('"').Append(':').Append('"').Append(EscapeJson(checks[i].Error)).Append('"');
            }
            sb.Append('}');
        }
        sb.Append(']').Append(',');
        sb.Append('"').Append("summary").Append('"').Append(':').Append('{');
        sb.Append('"').Append("total").Append('"').Append(':').Append(checks.Count).Append(',');
        sb.Append('"').Append("passed").Append('"').Append(':').Append(passedCount).Append(',');
        sb.Append('"').Append("failed").Append('"').Append(':').Append(failedCount);
        sb.Append('}').Append('}');

        string json = sb.ToString();
        if (!string.IsNullOrEmpty(jsonPath))
        {
            // UTF-8 WITHOUT BOM: strict JSON parsers (python json, some CI tooling)
            // reject the EF BB BF prefix that the static Encoding.UTF8 emits (t19).
            File.WriteAllText(jsonPath, json, new UTF8Encoding(false));
            Console.WriteLine("Wrote JSON report to: " + jsonPath);
        }

        return allPassed ? 0 : 1;
    }

    private static string EscapeJson(string s)
    {
        if (s == null) return "";
        return s.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "").Replace("\n", " ");
    }

    // B1: EnumerateWindows
    private static CheckResult TestEnumerateWindows()
    {
        CheckResult res = new CheckResult();
        res.Name = "B1_EnumerateWindows";
        try
        {
            List<WindowInfo> windows = Detect.EnumerateWindows(0);
            if (windows == null)
            {
                res.Passed = false;
                res.Error = "EnumerateWindows returned null";
                return res;
            }

            int currentPid = Process.GetCurrentProcess().Id;
            for (int i = 0; i < windows.Count; i++)
            {
                WindowInfo w = windows[i];
                if (w.Handle == IntPtr.Zero)
                {
                    res.Passed = false;
                    res.Error = "Window at index " + i + " has null handle";
                    return res;
                }
                if (w.ZOrder != i)
                {
                    res.Passed = false;
                    res.Error = "Window ZOrder is not sequential: expected " + i + ", got " + w.ZOrder;
                    return res;
                }
                if (w.Bounds.W <= 0 || w.Bounds.H <= 0)
                {
                    res.Passed = false;
                    res.Error = "Window " + w.Title + " has non-positive bounds: " + w.Bounds;
                    return res;
                }
                if (string.Equals(w.ClassName, "Shell_TrayWnd", StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(w.ClassName, "Shell_SecondaryTrayWnd", StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(w.ClassName, "Progman", StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(w.ClassName, "WorkerW", StringComparison.OrdinalIgnoreCase))
                {
                    res.Passed = false;
                    res.Error = "Shell window was not filtered: " + w.ClassName;
                    return res;
                }
            }

            res.Passed = true;
            res.Details = "Found " + windows.Count + " valid windows in front-to-back ZOrder starting at 0";
            return res;
        }
        catch (Exception ex)
        {
            res.Passed = false;
            res.Error = ex.Message;
            return res;
        }
    }

    // B2: EnumerateMonitors
    private static CheckResult TestEnumerateMonitors()
    {
        CheckResult res = new CheckResult();
        res.Name = "B2_EnumerateMonitors";
        try
        {
            List<MonitorInfo> monitors = Detect.EnumerateMonitors();
            if (monitors == null || monitors.Count == 0)
            {
                res.Passed = false;
                res.Error = "EnumerateMonitors returned empty list";
                return res;
            }

            int primaryCount = 0;
            for (int i = 0; i < monitors.Count; i++)
            {
                MonitorInfo m = monitors[i];
                if (m.Primary) primaryCount++;
                if (m.Bounds.W <= 0 || m.Bounds.H <= 0)
                {
                    res.Passed = false;
                    res.Error = "Monitor " + i + " has invalid Bounds: " + m.Bounds;
                    return res;
                }
                if (m.WorkArea.W <= 0 || m.WorkArea.H <= 0)
                {
                    res.Passed = false;
                    res.Error = "Monitor " + i + " has invalid WorkArea: " + m.WorkArea;
                    return res;
                }
            }

            if (primaryCount != 1)
            {
                res.Passed = false;
                res.Error = "Expected exactly 1 primary monitor, found " + primaryCount;
                return res;
            }

            res.Passed = true;
            res.Details = "Found " + monitors.Count + " monitors; Primary is unique; Bounds=" + monitors[0].Bounds;
            return res;
        }
        catch (Exception ex)
        {
            res.Passed = false;
            res.Error = ex.Message;
            return res;
        }
    }

    // B3: TaskbarBounds & HitTest precedence
    private static CheckResult TestTaskbarAndHitTest()
    {
        CheckResult res = new CheckResult();
        res.Name = "B3_TaskbarAndHitTest";
        try
        {
            List<MonitorInfo> monitors = Detect.EnumerateMonitors();
            TargetRect tb = Detect.TaskbarBounds(monitors[0].Bounds);

            // 1. Taskbar precedence test
            if (tb.W > 0 && tb.H > 0)
            {
                Point tbPoint = new Point(tb.X + tb.W / 2, tb.Y + tb.H / 2);
                TargetHit tbHit = Detect.HitTest(tbPoint, 0);
                if (tbHit.Kind != TargetKind.Taskbar)
                {
                    res.Passed = false;
                    res.Error = "HitTest on taskbar point returned kind " + tbHit.Kind + ", expected Taskbar";
                    return res;
                }
                if (tbHit.Source != "taskbar")
                {
                    res.Passed = false;
                    res.Error = "HitTest on taskbar point returned source " + tbHit.Source + ", expected taskbar";
                    return res;
                }
                if (string.IsNullOrEmpty(tbHit.Label))
                {
                    res.Passed = false;
                    res.Error = "Taskbar hit label is empty";
                    return res;
                }
            }

            // 2. Window HitTest test
            List<WindowInfo> windows = Detect.EnumerateWindows(0);
            if (windows.Count > 0)
            {
                WindowInfo topWin = windows[0];
                Point winPoint = new Point(topWin.Bounds.X + topWin.Bounds.W / 2, topWin.Bounds.Y + topWin.Bounds.H / 2);
                // If this point falls inside the taskbar, shift it away from taskbar
                if (tb.W > 0 && tb.H > 0 && tb.ToRectangle().Contains(winPoint))
                {
                    winPoint = new Point(topWin.Bounds.X + topWin.Bounds.W / 2, topWin.Bounds.Y + 20);
                }

                TargetHit winHit = Detect.HitTest(winPoint, 0);
                if (winHit.Kind != TargetKind.Window && winHit.Kind != TargetKind.Taskbar)
                {
                    res.Passed = false;
                    res.Error = "HitTest on window point returned kind " + winHit.Kind + ", expected Window";
                    return res;
                }
            }

            // 3. Monitor HitTest test (test virtual point)
            Point monitorPoint = new Point(monitors[0].Bounds.X + monitors[0].Bounds.W / 2, monitors[0].Bounds.Y + monitors[0].Bounds.H / 2);
            TargetHit monHit = Detect.HitTest(monitorPoint, 0);
            if (monHit.Kind == TargetKind.None)
            {
                res.Passed = false;
                res.Error = "HitTest inside monitor bounds returned TargetKind.None";
                return res;
            }

            res.Passed = true;
            res.Details = "TaskbarBounds=" + tb + "; HitTest priority Taskbar > Window > Monitor confirmed";
            return res;
        }
        catch (Exception ex)
        {
            res.Passed = false;
            res.Error = ex.Message;
            return res;
        }
    }



    // B6: Detect dump visualization PNG
    private static CheckResult TestDetectDumpVisualization(string pngDir)
    {
        CheckResult res = new CheckResult();
        res.Name = "B6_DetectDumpVisualization";
        try
        {
            if (string.IsNullOrEmpty(pngDir))
            {
                res.Passed = true;
                res.Details = "Skipped PNG generation (no pngDir specified)";
                return res;
            }

            List<MonitorInfo> monitors = Detect.EnumerateMonitors();
            List<WindowInfo> windows = Detect.EnumerateWindows(0);

            int minX = int.MaxValue, minY = int.MaxValue, maxX = int.MinValue, maxY = int.MinValue;
            for (int i = 0; i < monitors.Count; i++)
            {
                var r = monitors[i].Bounds.ToRectangle();
                if (r.Left < minX) minX = r.Left;
                if (r.Top < minY) minY = r.Top;
                if (r.Right > maxX) maxX = r.Right;
                if (r.Bottom > maxY) maxY = r.Bottom;
            }

            int totalW = Math.Max(800, maxX - minX);
            int totalH = Math.Max(600, maxY - minY);

            // Scale to a comfortable preview canvas (e.g. 960x540)
            int canvasW = 960;
            int canvasH = (int)Math.Round((double)totalH * canvasW / totalW);
            if (canvasH < 300) canvasH = 540;

            using (Bitmap bmp = new Bitmap(canvasW, canvasH, PixelFormat.Format32bppArgb))
            {
                using (Graphics g = Graphics.FromImage(bmp))
                {
                    g.Clear(Color.FromArgb(30, 30, 35));
                    double scaleX = (double)canvasW / totalW;
                    double scaleY = (double)canvasH / totalH;

                    // Draw monitors
                    using (Font font = new Font("Arial", 11, FontStyle.Bold))
                    using (Pen monPen = new Pen(Color.FromArgb(100, 150, 255), 2))
                    {
                        for (int i = 0; i < monitors.Count; i++)
                        {
                            var r = monitors[i].Bounds.ToRectangle();
                            int mx = (int)Math.Round((r.X - minX) * scaleX);
                            int my = (int)Math.Round((r.Y - minY) * scaleY);
                            int mw = (int)Math.Round(r.Width * scaleX);
                            int mh = (int)Math.Round(r.Height * scaleY);

                            g.FillRectangle(new SolidBrush(Color.FromArgb(45, 45, 55)), mx, my, mw, mh);
                            g.DrawRectangle(monPen, mx, my, mw, mh);
                            g.DrawString("Monitor " + (i + 1) + (monitors[i].Primary ? " (Primary)" : "") + " " + r.Width + "x" + r.Height, font, Brushes.LightSkyBlue, mx + 8, my + 8);

                            // Draw taskbar for this monitor
                            TargetRect tb = Detect.TaskbarBounds(monitors[i].Bounds);
                            if (tb.W > 0 && tb.H > 0)
                            {
                                int tbx = (int)Math.Round((tb.X - minX) * scaleX);
                                int tby = (int)Math.Round((tb.Y - minY) * scaleY);
                                int tbw = (int)Math.Round(tb.W * scaleX);
                                int tbh = (int)Math.Round(tb.H * scaleY);
                                g.FillRectangle(new SolidBrush(Color.FromArgb(60, 80, 110)), tbx, tby, tbw, tbh);
                                g.DrawRectangle(new Pen(Color.Cyan, 1.5f), tbx, tby, tbw, tbh);
                                g.DrawString("Taskbar " + tb.W + "x" + tb.H, font, Brushes.Cyan, tbx + 4, tby + 2);
                            }
                        }
                    }

                    // Draw first 8 windows in reverse Z-order (deepest first, foremost last)
                    int winLimit = Math.Min(windows.Count, 8);
                    using (Font winFont = new Font("Arial", 9))
                    {
                        Color[] colors = new Color[] {
                            Color.FromArgb(200, 255, 100, 100),
                            Color.FromArgb(200, 100, 255, 100),
                            Color.FromArgb(200, 255, 200, 50),
                            Color.FromArgb(200, 200, 100, 255),
                            Color.FromArgb(200, 100, 200, 255)
                        };

                        for (int i = winLimit - 1; i >= 0; i--)
                        {
                            var w = windows[i];
                            var r = w.Bounds.ToRectangle();
                            int wx = (int)Math.Round((r.X - minX) * scaleX);
                            int wy = (int)Math.Round((r.Y - minY) * scaleY);
                            int ww = (int)Math.Round(r.Width * scaleX);
                            int wh = (int)Math.Round(r.Height * scaleY);

                            Color c = colors[i % colors.Length];
                            using (Pen p = new Pen(c, 1.5f))
                            using (Brush fillBrush = new SolidBrush(Color.FromArgb(40, c.R, c.G, c.B)))
                            {
                                g.FillRectangle(fillBrush, wx, wy, ww, wh);
                                g.DrawRectangle(p, wx, wy, ww, wh);
                                string label = "Z=" + w.ZOrder + " " + (!string.IsNullOrEmpty(w.Title) ? w.Title : w.ClassName);
                                if (label.Length > 35) label = label.Substring(0, 32) + "...";
                                g.DrawString(label, winFont, new SolidBrush(c), wx + 4, wy + 4);
                            }
                        }
                    }
                }

                string dumpPath = Path.Combine(pngDir, "engine_detect_dump.png");
                bmp.Save(dumpPath, ImageFormat.Png);
            }

            res.Passed = true;
            res.Details = "Generated engine_detect_dump.png with visual monitor/taskbar/window mapping";
            return res;
        }
        catch (Exception ex)
        {
            res.Passed = false;
            res.Error = ex.Message;
            return res;
        }
    }



    private static bool ThrowsArgumentError(Action action, string what)
    {
        try
        {
            action();
        }
        catch (ArgumentException)
        {
            return false; // expected
        }
        Console.WriteLine("[t16] expected ArgumentException was NOT thrown for: " + what);
        return true;
    }

    // B8: Detect.HitTest hot-path cache (t16 / F-12) -----------------------------------
    // 1) Same state, two calls: identical result, second served from the snapshot
    //    (CacheHits must advance).
    // 2) A brand-new topmost window then must be found after InvalidateCache() --
    //    proven with a real Form in a subprocess (--hit-helper <expectFound>), so a
    //    cache bug can never fake the pass here.
    private static CheckResult TestDetectHitTestCache()
    {
        CheckResult res = new CheckResult();
        res.Name = "B8_DetectHitTestCache";
        try
        {
            Detect.InvalidateCache();

            List<MonitorInfo> monitors = Detect.EnumerateMonitors();
            List<WindowInfo> windows = Detect.EnumerateWindows(0);
            if (windows.Count == 0)
            {
                res.Passed = false;
                res.Error = "no windows to hit-test against";
                return res;
            }
            WindowInfo top = windows[0];
            Point pt = new Point(top.Bounds.X + top.Bounds.W / 2, top.Bounds.Y + top.Bounds.H / 2);
            TargetRect tb = Detect.TaskbarBounds(monitors[0].Bounds);
            if (tb.W > 0 && tb.H > 0 && tb.ToRectangle().Contains(pt))
            {
                pt = new Point(top.Bounds.X + top.Bounds.W / 2, top.Bounds.Y + 15);
                if (pt.Y >= monitors[0].Bounds.Y + monitors[0].Bounds.H) pt.Y = top.Bounds.Y + 5;
            }

            long hitsBefore = Detect.CacheHits;
            TargetHit first = Detect.HitTest(pt, 0);   // may populate the snapshot
            TargetHit second = Detect.HitTest(pt, 0);  // must be served from the cache
            if (first.Kind != second.Kind || !first.Rect.ToString().Equals(second.Rect.ToString()) ||
                !first.Label.Equals(second.Label) || !first.Source.Equals(second.Source))
            {
                res.Passed = false;
                res.Error = "two HitTest calls on the same state returned different results: " +
                    first.Source + "@" + first.Rect + " vs " + second.Source + "@" + second.Rect;
                return res;
            }
            if (first.IsEmpty)
            {
                res.Passed = false;
                res.Error = "HitTest returned an empty hit for a window point: " + pt;
                return res;
            }
            if (Detect.CacheHits <= hitsBefore)
            {
                res.Passed = false;
                res.Error = "CacheHits did not advance on the repeated HitTest call (" + Detect.CacheHits + " <= " + hitsBefore + ")";
                return res;
            }

            // Real change propagation in a subprocess: a fresh topmost Form is created,
            // then HitTest must see it only after InvalidateCache().
            string selfExe = Process.GetCurrentProcess().MainModule.FileName;
            string helperOut = Path.Combine(Path.GetTempPath(), "dsh-hit-helper-" + Guid.NewGuid().ToString("N").Substring(0, 8) + ".txt");
            string probePt = pt.X + "," + pt.Y;
            var psi = new ProcessStartInfo();
            psi.FileName = selfExe;
            psi.Arguments = "--hit-helper " + helperOut;
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            int rounds = 0;
            System.Diagnostics.Stopwatch poll = System.Diagnostics.Stopwatch.StartNew();
            using (Process helper = Process.Start(psi))
            {
                // The helper writes the file once its window is visible and pumping.
                bool fileReady = false;
                for (int i = 0; i < 100 && !fileReady; i++)
                {
                    System.Threading.Thread.Sleep(50);
                    if (File.Exists(helperOut)) fileReady = true;
                }
                if (!fileReady)
                {
                    try { helper.Kill(); } catch { }
                    res.Passed = false;
                    res.Error = "hit-helper did not report ready (no file after 5s)";
                    return res;
                }
                // Aim at the helper's own centre: its location is independent of pt.
                // Parse defensively: a stale ready file in the old 9-field format (or a
                // truncated one) must not surface as an unrelated FormatException.
                string readyRaw = File.ReadAllText(helperOut);
                string[] parts = readyRaw.Split(',');
                int hx = 0, hy = 0, hw = 0, hh = 0;
                bool boundsOk = parts.Length >= 4 &&
                    int.TryParse(parts[0], out hx) && int.TryParse(parts[1], out hy) &&
                    int.TryParse(parts[2], out hw) && int.TryParse(parts[3], out hh);
                if (!boundsOk)
                {
                    try { helper.Kill(); } catch { }
                    try { File.Delete(helperOut); } catch { }
                    res.Passed = false;
                    res.Error = "hit-helper ready file is stale or malformed (first fields not 4 ints): " + readyRaw;
                    return res;
                }
                Point helperPt = new Point(hx + hw / 2, hy + hh / 2);
                if (parts.Length > 4 && parts[4] == "0")
                {
                    try { helper.Kill(); } catch { }
                    try { File.Delete(helperOut); } catch { }
                    res.Passed = false;
                    res.Error = "hit-helper self-check never saw its own window pass the EnumerateWindows " +
                        "visibility filters within 5s (readyFields=" + readyRaw + ")";
                    return res;
                }

                // Poll the real pipeline (InvalidateCache -> HitTest) until the brand-new
                // window answers; the assertion never depends on a single sample (t19).
                // 5s budget @ 50ms -- with the helper-side readiness gate above this is
                // defense in depth, not the primary fix.
                bool foundAfterInvalidate = false;
                while (poll.ElapsedMilliseconds < 5000 && !foundAfterInvalidate)
                {
                    rounds++;
                    Detect.InvalidateCache();
                    TargetHit h = Detect.HitTest(helperPt, 0);
                    if (h.Kind == TargetKind.Window)
                    {
                        string title = h.Label ?? "";
                        if (title.IndexOf("DSH16HitProbe", System.StringComparison.Ordinal) >= 0) foundAfterInvalidate = true;
                    }
                    if (!foundAfterInvalidate) System.Threading.Thread.Sleep(50);
                }

                try { helper.Kill(); } catch { }
                try { if (!helper.WaitForExit(1500)) { } } catch { }
                try { File.Delete(helperOut); } catch { }

                if (!foundAfterInvalidate)
                {
                    // Diagnose: did a direct uncached enumeration see the helper at all?
                    List<WindowInfo> fresh = Detect.EnumerateWindows(0);
                    int seen = 0;
                    for (int i = 0; i < fresh.Count; i++)
                    {
                        if ((fresh[i].Title ?? "").IndexOf("DSH16HitProbe", System.StringComparison.Ordinal) >= 0) seen++;
                    }
                    bool helperGone;
                    int helperExit = -1;
                    try { helperGone = helper.HasExited; if (helperGone) helperExit = helper.ExitCode; } catch { helperGone = true; }
                    res.Passed = false;
                    res.Error = "new topmost window not found via HitTest even after InvalidateCache()" +
                        " (direct EnumerateWindows saw " + seen + " probe window(s) over " + rounds + " poll rounds in " +
                        poll.ElapsedMilliseconds + "ms; helper bounds " + hx + "," + hy + " " + hw + "x" + hh +
                        "; helper exited=" + helperGone + (helperGone ? " exitCode=" + helperExit : "") +
                        "; helper self: readyFields=" + readyRaw + ")";
                    return res;
                }
            }

            res.Passed = true;
            res.Details = "F-12 cache: same-state double call identical (CacheHits " + hitsBefore + "->" + Detect.CacheHits + "); new topmost window found after InvalidateCache() (subprocess Form, " + rounds + " poll round(s), helper ready gate passed)";
            return res;
        }
        catch (Exception ex)
        {
            res.Passed = false;
            res.Error = ex.Message;
            return res;
        }
    }

    [System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
    private static extern int GetWindowLongLong(IntPtr hWnd, int nIndex);
    private const int GWL_EXSTYLE_DIAG = -20;
    private const int WS_EX_TOOLWINDOW_DIAG = 0x00000080;
    private const int DWMWA_CLOAKED_DIAG = 14;
    [System.Runtime.InteropServices.DllImport("dwmapi.dll", EntryPoint = "DwmGetWindowAttribute")]
    private static extern int DwmGetWindowAttributeDiag(IntPtr hwnd, int attr, out int value, int size);
    [System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint = "IsWindowVisible")]
    private static extern bool IsWindowVisibleDiag(IntPtr h);
    [System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint = "IsIconic")]
    private static extern bool IsIconicDiag(IntPtr h);
    [System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint = "GetWindowRect")]
    private static extern bool GetWindowRectDiag(IntPtr h, out RECTDiag r);
    [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
    private struct RECTDiag { public int Left, Top, Right, Bottom; }
    private delegate bool EnumProcDiag(IntPtr h, IntPtr l);
    [System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint = "EnumWindows")]
    private static extern bool EnumWindowsDiag(EnumProcDiag cb, IntPtr l);

    // Does this very window pass the same filters Detect.EnumerateWindows applies to
    // a window of ANOTHER process (same-process exclusion cannot apply to the helper
    // checking itself; the parent runs in a different process)? Mirrors the filter
    // chain: visible, not iconic, no WS_EX_TOOLWINDOW, not DWM-cloaked, non-zero area.
    private static bool SelfEnumerableForExternalObserver(Form f)
    {
        bool ok = false;
        EnumWindowsDiag(delegate(IntPtr h, IntPtr l)
        {
            if (h != f.Handle) return true;
            if (!IsWindowVisibleDiag(h)) return true;
            if (IsIconicDiag(h)) return true;
            int ex = 0;
            try { ex = GetWindowLongLong(h, GWL_EXSTYLE_DIAG); } catch { }
            if ((ex & WS_EX_TOOLWINDOW_DIAG) != 0) return true;
            int cloaked = 0;
            try
            {
                if (DwmGetWindowAttributeDiag(h, DWMWA_CLOAKED_DIAG, out cloaked, 4) == 0 && cloaked != 0) return true;
            }
            catch { }
            RECTDiag r;
            if (!GetWindowRectDiag(h, out r)) return true;
            if (r.Right - r.Left <= 0 || r.Bottom - r.Top <= 0) return true;
            ok = true;
            return true;
        }, IntPtr.Zero);
        return ok;
    }

    // Subprocess helper: shows a uniquely titled topmost form under the probe point
    // until killed. Writes a ready file once the message pump is running. Exit code
    // is meaningless; the parent only needs the window to exist for a while.
    private static int RunHitHelper(string readyFile)
    {
        try
        {
            using (Form f = new Form())
            {
                // Must stay enumerable for Detect.EnumerateWindows: no WS_EX_TOOLWINDOW
                // (so no *ToolWindow border and ShowInTaskbar stays true).
                f.Text = "DSH16HitProbe Window";
                f.FormBorderStyle = FormBorderStyle.Sizable;
                f.StartPosition = FormStartPosition.Manual;
                f.TopMost = true;
                int x = 160, y = 160;
                try
                {
                    Rectangle wa = Screen.PrimaryScreen.WorkingArea;
                    if (x + 320 > wa.Right) x = wa.Left + 20;
                    if (y + 240 > wa.Bottom) y = wa.Top + 20;
                    if (x < wa.Left) x = wa.Left;
                    if (y < wa.Top) y = wa.Top;
                }
                catch { }
                f.Bounds = new Rectangle(x, y, 300, 200);
                f.Show();
                Application.DoEvents();
                f.Refresh();
                Application.DoEvents();

                // Deterministic readiness (t19): the ready file is written only after the
                // window passes the same visibility filters Detect.EnumerateWindows
                // applies (visible, not iconic, not a tool window, not cloaked, non-zero
                // area). Before this fix Show()+DoEvents() raced DWM first presentation
                // and the parent asserted on a window EnumWindows could not see yet
                // (~1/5 of runs under load). The one filter omitted here is the
                // same-process exclusion, which only applies to the helper itself --
                // the parent observes from a different process.
                System.Diagnostics.Stopwatch ready = System.Diagnostics.Stopwatch.StartNew();
                bool enumerable = SelfEnumerableForExternalObserver(f);
                while (!enumerable && ready.ElapsedMilliseconds < 5000)
                {
                    Application.DoEvents();
                    System.Threading.Thread.Sleep(25);
                    enumerable = SelfEnumerableForExternalObserver(f);
                }

                // Fields 0..3 = bounds (parent contract, parsed as ints). Field 4 =
                // self-enumerable 0/1, field 5 = ms waited for enumerability,
                // fields 6..8 = legacy self-diagnostics (visible/handleCreated/exstyle).
                int exStyleDiag = 0;
                try { exStyleDiag = GetWindowLongLong(f.Handle, GWL_EXSTYLE_DIAG); } catch { }
                File.WriteAllText(readyFile, f.Left + "," + f.Top + "," + f.Width + "," + f.Height +
                    "," + (enumerable ? "1" : "0") + "," + ready.ElapsedMilliseconds +
                    "," + f.Visible + "," + f.IsHandleCreated + "," + exStyleDiag);
                System.Diagnostics.Stopwatch sw = System.Diagnostics.Stopwatch.StartNew();
                while (sw.ElapsedMilliseconds < 20000)
                {
                    Application.DoEvents();
                    System.Threading.Thread.Sleep(25);
                }
            }
        }
        catch (Exception exHelp)
        {
            // Surface the real failure into the ready file: a bare "error" left the
            // parent guessing (t19 debugging showed only 'error' ten runs in a row).
            try { File.WriteAllText(readyFile, "error: " + exHelp.GetType().Name + ": " + exHelp.Message.Replace(",", ";")); } catch { }
        }
        return 0;
    }
}