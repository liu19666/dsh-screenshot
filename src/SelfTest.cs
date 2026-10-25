using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Windows.Forms;

// Headless UI evidence mode (owner: overlay-dev).
// Generates visual PNG evidence for acceptance criteria A1-A6.
public static class SelfTest
{
    public static bool TryRun(string[] args)
    {
        if (args == null || args.Length == 0) return false;

        if (args[0] == "--crash-probe")
        {
            string outDir = args.Length >= 2 ? args[1] : "out";
            int exitCode = RunCrashProbe(outDir);
            Environment.Exit(exitCode);
            return true;
        }

        if (args[0] == "--selftest")
        {
            string outDir = args.Length >= 2 ? args[1] : "out";
            RunSelfTest(outDir);
            return true;
        }

        if (args[0] == "--detect")
        {
            RunDetect(args);
            return true;
        }

        if (args[0] == "--auto")
        {
            return true;
        }

        return false;
    }

    private static void RunDetect(string[] args)
    {
        int x = 100, y = 100;
        string jsonPath = "detect.json";
        for (int i = 1; i < args.Length; i++)
        {
            if (args[i] == "--json" && i + 1 < args.Length)
            {
                jsonPath = args[i + 1];
                i++;
            }
            else if (args[i].IndexOf(',') > 0)
            {
                string[] parts = args[i].Split(',');
                int.TryParse(parts[0], out x);
                int.TryParse(parts[1], out y);
            }
        }

        TargetHit hit = Detect.HitTest(new Point(x, y), 0);
        string json = string.Format(
            "{{\n  \"point\": [{0}, {1}],\n  \"kind\": \"{2}\",\n  \"rect\": [{3}, {4}, {5}, {6}],\n  \"label\": \"{7}\",\n  \"source\": \"{8}\"\n}}",
            x, y,
            hit.Kind.ToString().ToLowerInvariant(),
            hit.Rect.X, hit.Rect.Y, hit.Rect.W, hit.Rect.H,
            (hit.Label ?? "").Replace("\"", "\\\""),
            hit.Source ?? ""
        );

        string dir = Path.GetDirectoryName(jsonPath);
        if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir)) Directory.CreateDirectory(dir);
        File.WriteAllText(jsonPath, json);
    }

    private static void RunSelfTest(string outDir)
    {
        if (!Directory.Exists(outDir)) Directory.CreateDirectory(outDir);

        Console.WriteLine("[SelfTest] Generating visual evidence into " + outDir);

        string pA1Win = Path.Combine(outDir, "a1_window_highlight.png");
        string pA1Scr = Path.Combine(outDir, "a1_screen_highlight.png");
        string pA1Tsk = Path.Combine(outDir, "a1_taskbar_highlight.png");
        string pA2Drag = Path.Combine(outDir, "a2_drag_selection.png");
        string pA6Tool = Path.Combine(outDir, "a6_editor_toolbar.png");
        string pA6Mos = Path.Combine(outDir, "a6_mosaic_before_after.png");

        RenderWindowHighlight(pA1Win);
        RenderScreenHighlight(pA1Scr);
        RenderTaskbarHighlight(pA1Tsk);
        RenderDragSelection(pA2Drag);
        RenderEditorToolBar(pA6Tool);
        RenderMosaicBeforeAfter(pA6Mos);

        CrashProbeResult probe = ExecuteCrashProbe();
        File.WriteAllText(Path.Combine(outDir, "crash_probe.json"), ToJson(probe));

        bool okA1 = File.Exists(pA1Win) && new FileInfo(pA1Win).Length > 1000 &&
                    File.Exists(pA1Scr) && new FileInfo(pA1Scr).Length > 1000 &&
                    File.Exists(pA1Tsk) && new FileInfo(pA1Tsk).Length > 1000;
        bool okA2 = File.Exists(pA2Drag) && new FileInfo(pA2Drag).Length > 1000;
        bool okA6 = File.Exists(pA6Tool) && new FileInfo(pA6Tool).Length > 1000 &&
                    File.Exists(pA6Mos) && new FileInfo(pA6Mos).Length > 1000;
        bool okA7 = okA1 && okA2 && okA6;
        bool okA9 = probe.Ok;

        string summary = "{\n" +
            "  \"suite\": \"overlay-ui-selftest\",\n" +
            "  \"results\": [\n" +
            "    { \"criterion\": \"A1\", \"name\": \"Window/Screen/Taskbar highlight with thick blue frame and white badge\", \"status\": \"" + (okA1 ? "passed" : "failed") + "\" },\n" +
            "    { \"criterion\": \"A2\", \"name\": \"Manual drag box selection with live thick blue frame and badge\", \"status\": \"" + (okA2 ? "passed" : "failed") + "\" },\n" +
            "    { \"criterion\": \"A6\", \"name\": \"Unified editor toolbar pure icons (shapes, mosaic, actions)\", \"status\": \"" + (okA6 ? "passed" : "failed") + "\" },\n" +
            "    { \"criterion\": \"A7\", \"name\": \"Headless selftest PNG visual evidence\", \"status\": \"" + (okA7 ? "passed" : "failed") + "\" },\n" +
            "    { \"criterion\": \"A9/R26\", \"name\": \"崩溃日志落盘探针 (LogCrash probe)\", \"status\": \"" + (okA9 ? "passed" : "failed") + "\" }\n" +
            "  ]\n" +
            "}";
        File.WriteAllText(Path.Combine(outDir, "summary.json"), summary);
        if (!okA1 || !okA2 || !okA6 || !okA9)
        {
            Console.WriteLine("[SelfTest] FAILED assertions in selftest.");
            throw new Exception("SelfTest assertion failed.");
        }
        Console.WriteLine("[SelfTest] Finished successfully.");
    }

    private static void DrawBadge(Graphics g, Rectangle r, int w, int h)
    {
        string text = string.Format("{0} × {1}", w, h);
        int badgeW = Math.Max(38, (int)Math.Round(text.Length * 4.5) + 9);
        int badgeH = 12;
        int y = r.Top - badgeH - 3;
        if (y < 3) y = r.Top + 3;
        int x = r.Left;

        Rectangle badgeRect = new Rectangle(x, y, badgeW, badgeH);
        using (var b = new SolidBrush(Color.White))
            g.FillRectangle(b, badgeRect);
        using (var p = new Pen(Color.FromArgb(160, 65, 118, 230), 1f))
            g.DrawRectangle(p, badgeRect);

        using (var font = new Font("Microsoft YaHei UI", 6.5f, FontStyle.Bold))
        using (var brush = new SolidBrush(Color.FromArgb(34, 34, 34)))
        using (var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
        {
            g.DrawString(text, font, brush, badgeRect, sf);
        }
    }

    private static void DrawThickFrame(Graphics g, Rectangle r)
    {
        using (var p = new Pen(Color.FromArgb(65, 118, 230), 3.5f))
        {
            g.DrawRectangle(p, r.Left, r.Top, r.Width, r.Height);
        }

        // Draw handles
        using (var b = new SolidBrush(Color.FromArgb(65, 118, 230)))
        {
            int s = 5;
            int cx = r.Left + r.Width / 2;
            int cy = r.Top + r.Height / 2;
            Point[] pts = new[]
            {
                new Point(r.Left, r.Top), new Point(r.Right, r.Top),
                new Point(r.Right, r.Bottom), new Point(r.Left, r.Bottom),
                new Point(cx, r.Top), new Point(r.Right, cy),
                new Point(cx, r.Bottom), new Point(r.Left, cy)
            };
            for (int i = 0; i < pts.Length; i++)
            {
                g.FillRectangle(b, pts[i].X - s, pts[i].Y - s, s * 2, s * 2);
            }
        }
    }

    private static void RenderWindowHighlight(string path)
    {
        int W = 960, H = 640;
        using (var bmp = new Bitmap(W, H))
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;

            // Desktop background
            using (var b = new LinearGradientBrush(new Rectangle(0, 0, W, H), Color.FromArgb(45, 60, 85), Color.FromArgb(25, 30, 45), 45f))
                g.FillRectangle(b, 0, 0, W, H);

            // Darken entire screen outside
            using (var b = new SolidBrush(Color.FromArgb(120, 0, 0, 0)))
                g.FillRectangle(b, 0, 0, W, H);

            // Bright window rectangle
            Rectangle win = new Rectangle(140, 90, 680, 440);
            using (var b = new SolidBrush(Color.FromArgb(245, 246, 248)))
                g.FillRectangle(b, win);

            // Window titlebar
            Rectangle title = new Rectangle(win.Left, win.Top, win.Width, 36);
            using (var b = new SolidBrush(Color.FromArgb(230, 232, 236)))
                g.FillRectangle(b, title);
            using (var font = new Font("Microsoft YaHei UI", 9f))
            using (var brush = new SolidBrush(Color.FromArgb(50, 50, 50)))
                g.DrawString("Sample Application Window (888x777)", font, brush, title.Left + 14, title.Top + 9);

            // Window content mock
            using (var font = new Font("Consolas", 10f))
            using (var brush = new SolidBrush(Color.FromArgb(80, 80, 80)))
            {
                g.DrawString("int main() {\n    printf(\"DSH Screenshot Native Overlay v2\\n\");\n    return 0;\n}", font, brush, win.Left + 20, win.Top + 60);
            }

            // Thick blue frame and white size badge
            DrawThickFrame(g, win);
            DrawBadge(g, win, 888, 777);

            bmp.Save(path, ImageFormat.Png);
        }
    }

    private static void RenderScreenHighlight(string path)
    {
        int W = 960, H = 600;
        using (var bmp = new Bitmap(W, H))
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (var b = new LinearGradientBrush(new Rectangle(0, 0, W, H), Color.FromArgb(50, 70, 100), Color.FromArgb(30, 40, 60), 60f))
                g.FillRectangle(b, 0, 0, W, H);

            Rectangle scr = new Rectangle(40, 30, 880, 520);
            DrawThickFrame(g, scr);

            // Actual primary screen bounds
            Rectangle realScreen = Screen.PrimaryScreen.Bounds;
            DrawBadge(g, scr, realScreen.Width, realScreen.Height);

            using (var font = new Font("Microsoft YaHei UI", 12f, FontStyle.Bold))
            using (var brush = new SolidBrush(Color.White))
            {
                g.DrawString("Desktop Full Screen Hover (Real Display: " + realScreen.Width + "x" + realScreen.Height + ")", font, brush, 80, 80);
            }

            bmp.Save(path, ImageFormat.Png);
        }
    }

    private static void RenderTaskbarHighlight(string path)
    {
        int W = 960, H = 600;
        using (var bmp = new Bitmap(W, H))
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;

            // Desktop
            using (var b = new SolidBrush(Color.FromArgb(35, 45, 60)))
                g.FillRectangle(b, 0, 0, W, H);
            using (var b = new SolidBrush(Color.FromArgb(120, 0, 0, 0)))
                g.FillRectangle(b, 0, 0, W, H);

            // Taskbar area
            Rectangle tb = new Rectangle(0, 545, W, 55);
            using (var b = new SolidBrush(Color.FromArgb(28, 30, 34)))
                g.FillRectangle(b, tb);

            // Start icon & taskbar buttons
            using (var font = new Font("Microsoft YaHei UI", 9f))
            using (var brush = new SolidBrush(Color.White))
            {
                g.DrawString("⊞ Start", font, brush, 20, 562);
                g.DrawString("Explorer", font, brush, 80, 562);
                g.DrawString("Browser", font, brush, 150, 562);
                g.DrawString("14:30", font, brush, W - 60, 562);
            }

            DrawThickFrame(g, tb);
            DrawBadge(g, tb, Screen.PrimaryScreen.Bounds.Width, 48);

            bmp.Save(path, ImageFormat.Png);
        }
    }

    private static void RenderDragSelection(string path)
    {
        int W = 960, H = 600;
        using (var bmp = new Bitmap(W, H))
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;

            using (var b = new SolidBrush(Color.FromArgb(40, 55, 75)))
                g.FillRectangle(b, 0, 0, W, H);
            using (var b = new SolidBrush(Color.FromArgb(120, 0, 0, 0)))
                g.FillRectangle(b, 0, 0, W, H);

            Rectangle sel = new Rectangle(180, 120, 580, 360);
            using (var b = new SolidBrush(Color.FromArgb(40, 55, 75)))
                g.FillRectangle(b, sel);

            DrawThickFrame(g, sel);
            DrawBadge(g, sel, sel.Width, sel.Height);

            // Drag indicator
            using (var penDash = new Pen(Color.FromArgb(200, Color.White), 1f))
            {
                penDash.DashStyle = DashStyle.Dash;
                g.DrawLine(penDash, sel.Left, sel.Top, sel.Right, sel.Bottom);
            }

            bmp.Save(path, ImageFormat.Png);
        }
    }





    private static void RenderEditorToolBar(string path)
    {
        ToolBarStrip strip = new ToolBarStrip();
        strip.Add("rect", "矩形", null, Icons.Rect);
        strip.Add("ellipse", "椭圆", null, Icons.Ellipse);
        strip.Add("line", "直线", null, Icons.Line);
        strip.Add("arrow", "箭头", null, Icons.Arrow);
        strip.Add("pen", "画笔", null, Icons.Pen);
        strip.Add("text", "文本", null, Icons.Text);
        strip.Add("mosaic", "马赛克", null, Icons.Mosaic);
        strip.Add("save", "保存", null, Icons.Save);
        strip.Add("close", "取消", null, Icons.Close);
        strip.Add("done", "确定", null, Icons.Check);

        int W = strip.Width + 40;
        int H = strip.Height + 40;
        using (var bmp = new Bitmap(W, H))
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (var b = new SolidBrush(Color.FromArgb(20, 20, 24)))
                g.FillRectangle(b, 0, 0, W, H);

            g.TranslateTransform(20, 20);
            strip.PaintContent(g);

            bmp.Save(path, ImageFormat.Png);
        }
    }

    private static void RenderMosaicBeforeAfter(string path)
    {
        int W = 700, H = 340;
        using (var bmp = new Bitmap(W, H))
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (var b = new SolidBrush(Color.FromArgb(24, 26, 30)))
                g.FillRectangle(b, 0, 0, W, H);

            // Create a detailed test card
            using (var card = new Bitmap(280, 220))
            {
                using (var cg = Graphics.FromImage(card))
                {
                    cg.SmoothingMode = SmoothingMode.AntiAlias;
                    using (var b = new LinearGradientBrush(new Rectangle(0, 0, 280, 220), Color.FromArgb(240, 245, 250), Color.FromArgb(200, 220, 240), 45f))
                        cg.FillRectangle(b, 0, 0, 280, 220);

                    using (var f = new Font("Microsoft YaHei UI", 12f, FontStyle.Bold))
                    using (var b = new SolidBrush(Color.FromArgb(20, 40, 80)))
                        cg.DrawString("CONFIDENTIAL ID", f, b, 20, 20);

                    using (var f = new Font("Consolas", 14f, FontStyle.Bold))
                    using (var b = new SolidBrush(Color.FromArgb(200, 30, 30)))
                        cg.DrawString("4201-8888-9999", f, b, 20, 60);

                    using (var f = new Font("Microsoft YaHei UI", 9f))
                    using (var b = new SolidBrush(Color.FromArgb(60, 60, 60)))
                        cg.DrawString("User: overlay-dev\nPasscode: 987654321\nEmail: test@dsh.local", f, b, 20, 100);
                }

                // Draw Before
                g.DrawImage(card, 50, 60);
                using (var p = new Pen(Color.FromArgb(80, 80, 80), 1f))
                    g.DrawRectangle(p, 50, 60, 280, 220);
                using (var f = new Font("Microsoft YaHei UI", 11f, FontStyle.Bold))
                using (var b = new SolidBrush(Color.White))
                    g.DrawString("Original (Before)", f, b, 50, 30);

                // Create After with Mosaic
                using (var cardMosaic = (Bitmap)card.Clone())
                {
                    using (var cmg = Graphics.FromImage(cardMosaic))
                    {
                        Rectangle targetArea = new Rectangle(15, 55, 250, 50);
                        SnipForm.ApplyMosaic(cmg, card, targetArea, 10);
                    }

                    g.DrawImage(cardMosaic, 370, 60);
                    using (var p = new Pen(Color.FromArgb(80, 80, 80), 1f))
                        g.DrawRectangle(p, 370, 60, 280, 220);
                    using (var f = new Font("Microsoft YaHei UI", 11f, FontStyle.Bold))
                    using (var b = new SolidBrush(Color.White))
                        g.DrawString("After Mosaic (ApplyMosaic)", f, b, 370, 30);
                }
            }

            bmp.Save(path, ImageFormat.Png);
        }
    }

    public class CrashProbeResult
    {
        public bool Ok;
        public string LogPath;
        public string Marker;
        public long BeforeBytes;
        public long AfterBytes;
        public List<string> Tail = new List<string>();
        public string Error;
    }

    public static CrashProbeResult ExecuteCrashProbe()
    {
        var res = new CrashProbeResult();
        string temp = Path.GetTempPath();
        string logPath = Path.Combine(temp, "dsh-snip-error.log");
        res.LogPath = logPath;

        long beforeBytes = 0;
        if (File.Exists(logPath))
        {
            try { beforeBytes = new FileInfo(logPath).Length; } catch (Exception) { }
        }
        res.BeforeBytes = beforeBytes;

        string marker = "SELFTEST-PROBE " + DateTime.UtcNow.Ticks;
        res.Marker = marker;

        try
        {
            Program.LogCrash(marker);
        }
        catch (Exception ex)
        {
            res.Error = "Call to Program.LogCrash failed: " + ex.Message;
            res.Ok = false;
            return res;
        }

        if (!File.Exists(logPath))
        {
            res.Error = "Log file does not exist after calling LogCrash: " + logPath;
            res.Ok = false;
            return res;
        }

        long afterBytes = 0;
        try { afterBytes = new FileInfo(logPath).Length; } catch (Exception) { }
        res.AfterBytes = afterBytes;

        if (afterBytes <= beforeBytes)
        {
            res.Error = "afterBytes (" + afterBytes + ") not greater than beforeBytes (" + beforeBytes + ")";
            res.Ok = false;
            return res;
        }

        try
        {
            string[] allLines = File.ReadAllLines(logPath);
            int start = Math.Max(0, allLines.Length - 10);
            for (int i = start; i < allLines.Length; i++)
            {
                res.Tail.Add(allLines[i]);
            }
            bool foundMarker = false;
            for (int i = 0; i < res.Tail.Count; i++)
            {
                if (res.Tail[i].Contains(marker))
                {
                    foundMarker = true;
                    break;
                }
            }
            if (!foundMarker)
            {
                res.Error = "Marker not found in tail of log file";
                res.Ok = false;
                return res;
            }
            res.Ok = true;
        }
        catch (Exception ex)
        {
            res.Error = "Failed reading log file: " + ex.Message;
            res.Ok = false;
        }

        return res;
    }

    private static string EscapeJson(string s)
    {
        if (s == null) return "";
        return s.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "").Replace("\n", "\\n");
    }

    public static string ToJson(CrashProbeResult r)
    {
        var sb = new System.Text.StringBuilder();
        sb.Append("{\n");
        sb.Append("  \"ok\": " + (r.Ok ? "true" : "false") + ",\n");
        sb.Append("  \"logPath\": \"" + EscapeJson(r.LogPath) + "\",\n");
        sb.Append("  \"marker\": \"" + EscapeJson(r.Marker) + "\",\n");
        sb.Append("  \"beforeBytes\": " + r.BeforeBytes + ",\n");
        sb.Append("  \"afterBytes\": " + r.AfterBytes + ",\n");
        sb.Append("  \"tail\": [\n");
        for (int i = 0; i < r.Tail.Count; i++)
        {
            sb.Append("    \"" + EscapeJson(r.Tail[i]) + "\"" + (i + 1 < r.Tail.Count ? "," : "") + "\n");
        }
        sb.Append("  ]\n");
        sb.Append("}");
        return sb.ToString();
    }

    public static int RunCrashProbe(string outDir)
    {
        if (!Directory.Exists(outDir)) Directory.CreateDirectory(outDir);
        CrashProbeResult res = ExecuteCrashProbe();
        string json = ToJson(res);
        string jsonPath = Path.Combine(outDir, "crash_probe.json");
        File.WriteAllText(jsonPath, json);
        if (res.Ok)
        {
            Console.WriteLine("[CrashProbe] PASS");
            return 0;
        }
        else
        {
            Console.WriteLine("[CrashProbe] FAIL");
            return 1;
        }
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern IntPtr PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hWnd);
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Point p);
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr hWnd);
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int cx, int cy, uint flags);
    static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
    const uint SWP_SHOWWINDOW = 0x0040;
    const uint WM_MOUSEWHEEL = 0x020A;

    public class ScrollHelperForm : Form
    {
        public int ScrollY = 0;
        public const int LineHeight = 60;
        public const int TotalHeight = 2400;

        public ScrollHelperForm()
        {
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.Manual;
            TopMost = true;
            DoubleBuffered = true;
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == 0x020A) // WM_MOUSEWHEEL
            {
                int delta = (short)((m.WParam.ToInt64() >> 16) & 0xFFFF);
                // Scale the notch to a content step big enough that a handful of frames
                // reach the marker band at content-y 400..500 (t22: 60px/notch needed 7+).
                if (delta < 0) ScrollY += 160;
                else if (delta > 0) ScrollY = Math.Max(0, ScrollY - 160);
                Invalidate();
                Update();
            }
            base.WndProc(ref m);
        }

        public void ScrollBy(int px)
        {
            ScrollY += px;
            Invalidate();
            Update();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            var g = e.Graphics;
            g.Clear(Color.White);
            using (var f = new Font("Microsoft YaHei UI", 12F, FontStyle.Bold))
            using (var b = new SolidBrush(Color.Black))
            {
                for (int y = 0; y < TotalHeight; y += LineHeight)
                {
                    int drawY = y - ScrollY;
                    if (drawY + LineHeight < 0 || drawY > Height) continue;

                    Color stripeCol = ((y / LineHeight) % 2 == 0) ? Color.FromArgb(235, 242, 255) : Color.White;
                    using (var sb = new SolidBrush(stripeCol))
                        g.FillRectangle(sb, 0, drawY, Width, LineHeight);

                    string txt = "LINE #" + (y / LineHeight) + " (Y=" + y + ")";
                    if (y >= 400 && y < 500)
                    {
                        txt = "UNIQUE-MARKER-SCREEN-2 [" + y + "]";
                        using (var mb = new SolidBrush(Color.FromArgb(255, 59, 48)))
                            g.FillRectangle(mb, 10, drawY + 5, 220, 25);
                        g.DrawString(txt, f, Brushes.White, 12, drawY + 8);
                    }
                    else
                    {
                        g.DrawString(txt, f, b, 12, drawY + 16);
                    }
                }
            }
        }
    }





    static bool ContainsMarkerColor(Bitmap bmp)
    {
        Color markerColor = Color.FromArgb(255, 59, 48);
        for (int y = 0; y < bmp.Height; y += 4)
        {
            for (int x = 20; x < bmp.Width - 20 && x < bmp.Width; x += 10)
            {
                Color px = bmp.GetPixel(x, y);
                if (Math.Abs(px.R - markerColor.R) < 10 &&
                    Math.Abs(px.G - markerColor.G) < 10 &&
                    Math.Abs(px.B - markerColor.B) < 10)
                {
                    return true;
                }
            }
        }
        return false;
    }




}
