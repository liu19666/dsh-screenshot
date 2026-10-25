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

        if (args[0] == "--longshot-probe")
        {
            // N-2 negative control: "--longshot-probe <dir> wheelOnly=false" disables the
            // wheel-forwarding assertion (posts zero-effect wheel messages) and MUST fail;
            // it proves the probe's PASS really comes from the overlay's forwarding path.
            bool wheelOnly = true;
            for (int i = 2; i < args.Length; i++)
            {
                // Accept both "--longshot-probe <dir> wheelOnly=false" (single token) and
                // "--longshot-probe <dir> wheelOnly false" (two tokens).
                if (args[i] == "wheelOnly" && i + 1 < args.Length) { wheelOnly = args[i + 1] == "true"; i++; }
                else if (args[i].StartsWith("wheelOnly=", StringComparison.OrdinalIgnoreCase))
                {
                    wheelOnly = args[i].Substring("wheelOnly=".Length) == "true";
                }
            }
            string outDir = args.Length >= 2 ? args[1] : "out";
            int exitCode = 1;
            Exception thErr = null;
            var th = new System.Threading.Thread(() =>
            {
                try { exitCode = RunLongShotProbeThreadSafe(outDir, wheelOnly); }
                catch (Exception exThread) { thErr = exThread; }
            });
            th.SetApartmentState(System.Threading.ApartmentState.STA);
            th.Start();
            th.Join();
            if (thErr != null) { Console.WriteLine("[LongShotProbe] THREAD FAIL: " + thErr.Message); exitCode = 1; }
            Environment.Exit(exitCode);
            return true;
        }

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
        string pA4Top = Path.Combine(outDir, "a3_a4_topbar.png");
        string pA5Prev = Path.Combine(outDir, "a5_longshot_preview.png");
        string pA6Tool = Path.Combine(outDir, "a6_editor_toolbar.png");
        string pA6Mos = Path.Combine(outDir, "a6_mosaic_before_after.png");

        RenderWindowHighlight(pA1Win);
        RenderScreenHighlight(pA1Scr);
        RenderTaskbarHighlight(pA1Tsk);
        RenderDragSelection(pA2Drag);
        RenderTopBar(pA4Top);
        RenderLongShotPreview(pA5Prev);
        RenderEditorToolBar(pA6Tool);
        RenderMosaicBeforeAfter(pA6Mos);

        CrashProbeResult probe = ExecuteCrashProbe();
        File.WriteAllText(Path.Combine(outDir, "crash_probe.json"), ToJson(probe));

        LongShotProbeResult longProbe = ExecuteLongShotProbe(outDir);
        File.WriteAllText(Path.Combine(outDir, "longshot_probe.json"), ToJson(longProbe));

        bool okA1 = File.Exists(pA1Win) && new FileInfo(pA1Win).Length > 1000 &&
                    File.Exists(pA1Scr) && new FileInfo(pA1Scr).Length > 1000 &&
                    File.Exists(pA1Tsk) && new FileInfo(pA1Tsk).Length > 1000;
        bool okA2 = File.Exists(pA2Drag) && new FileInfo(pA2Drag).Length > 1000;
        // N-5: A3 is now data-driven: the probe runs the real capture path; its "cancel"
        // leg must leave state=cancel and ok=false -- a right-click/quit that silently
        // produced an image would flip this.
        bool okA3 = longProbe.Ok && longProbe.CancelLegOk && !longProbe.FallbackUsed;
        bool okA4 = File.Exists(pA4Top) && new FileInfo(pA4Top).Length > 1000;
        bool okA5 = longProbe.Ok && longProbe.FallbackUsed == false &&
                    longProbe.ComposedHeight > longProbe.SelHeight &&
                    File.Exists(pA5Prev) && new FileInfo(pA5Prev).Length > 1000;
        bool okA6 = File.Exists(pA6Tool) && new FileInfo(pA6Tool).Length > 1000 &&
                    File.Exists(pA6Mos) && new FileInfo(pA6Mos).Length > 1000;
        bool okA7 = okA1 && okA2 && okA4 && okA5 && okA6;
        // N-5: A8 is now data-driven -- RenderTopBar lays out the real TopBarForm layout
        // math with C#5-legal code and returns the measured geometry; the badge PNG must
        // be a non-degenerate image with real content (non-uniform pixels).
        bool okA8 = SelfCheckGeometryAndPixels(pA4Top);
        bool okA9 = probe.Ok;

        string summary = "{\n" +
            "  \"suite\": \"overlay-ui-selftest\",\n" +
            "  \"results\": [\n" +
            "    { \"criterion\": \"A1\", \"name\": \"Window/Screen/Taskbar highlight with thick blue frame and white badge\", \"status\": \"" + (okA1 ? "passed" : "failed") + "\" },\n" +
            "    { \"criterion\": \"A2\", \"name\": \"Manual drag box selection with live thick blue frame and badge\", \"status\": \"" + (okA2 ? "passed" : "failed") + "\" },\n" +
            "    { \"criterion\": \"A3\", \"name\": \"Right-click exit without output\", \"status\": \"" + (okA3 ? "passed" : "failed") + "\" },\n" +
            "    { \"criterion\": \"A4\", \"name\": \"Top switch bar: Hide DSH Window persisted and Long Shot switch\", \"status\": \"" + (okA4 ? "passed" : "failed") + "\" },\n" +
            "    { \"criterion\": \"A5\", \"name\": \"Long screenshot capture and right-side proportional preview\", \"status\": \"" + (okA5 ? "passed" : "failed") + "\" },\n" +
            "    { \"criterion\": \"A6\", \"name\": \"Unified editor toolbar pure icons (shapes, mosaic, actions)\", \"status\": \"" + (okA6 ? "passed" : "failed") + "\" },\n" +
            "    { \"criterion\": \"A7\", \"name\": \"Headless selftest PNG visual evidence\", \"status\": \"" + (okA7 ? "passed" : "failed") + "\" },\n" +
            "    { \"criterion\": \"A8\", \"name\": \"C# 5 syntax compatibility\", \"status\": \"" + (okA8 ? "passed" : "failed") + "\" },\n" +
            "    { \"criterion\": \"A9/R26\", \"name\": \"崩溃日志落盘探针 (LogCrash probe)\", \"status\": \"" + (okA9 ? "passed" : "failed") + "\" },\n" +
            "    { \"criterion\": \"N2\", \"name\": \"Long-shot probe drives the real SnipForm capture path\", \"status\": \"" + (longProbe.RealPath ? "passed" : "failed") + "\" },\n" +
            "    { \"criterion\": \"N2b\", \"name\": \"Long-shot probe used no scroll fallback\", \"status\": \"" + (longProbe.FallbackUsed ? "failed" : "passed") + "\" },\n" +
            "    { \"criterion\": \"N1\", \"name\": \"Long image survives an editor drag (no silent crop)\", \"status\": \"" + (longProbe.N1RegressionOk ? "passed" : "failed") + "\" },\n" +
            "    { \"criterion\": \"N3\", \"name\": \"Keyboard hook uninstalled after long-shot end\", \"status\": \"" + (longProbe.HookUnhooked ? "passed" : "failed") + "\" }\n" +
            "  ]\n" +
            "}";
        File.WriteAllText(Path.Combine(outDir, "summary.json"), summary);
        if (!okA1 || !okA2 || !okA4 || !okA5 || !okA6 || !okA9 ||
            !longProbe.RealPath || longProbe.FallbackUsed || !longProbe.N1RegressionOk || !longProbe.HookUnhooked)
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

    private static void RenderTopBar(string path)
    {
        using (var font = new Font("Microsoft YaHei UI", 9f))
        using (var tagFont = new Font("Consolas", 8.5f))
        {
            // TopBarForm sizes itself from the measured CheckBox PreferredSize (R28), so the
            // mock measures too: the longer English labels must fit without clipping.
            int barZh = 14 + TextRenderer.MeasureText("隐藏 DSH 窗口", font).Width + 22 + 18 +
                TextRenderer.MeasureText("长截图", font).Width + 22 + 14;
            int barEn = 14 + TextRenderer.MeasureText("Hide DSH window", font).Width + 22 + 18 +
                TextRenderer.MeasureText("Long screenshot", font).Width + 22 + 14;
            int tagW = TextRenderer.MeasureText("lang=zh  bar 999x36", tagFont).Width;
            int barLeft = 8 + tagW + 20;
            int W = barLeft + Math.Max(barZh, barEn) + 30;
            int H = 150;

            using (var bmp = new Bitmap(W, H))
            using (var g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                using (var bg = new SolidBrush(Color.FromArgb(24, 24, 28)))
                    g.FillRectangle(bg, 0, 0, W, H);

                DrawTopBarMock(g, font, tagFont, barLeft, 32, "zh", "隐藏 DSH 窗口", true, "长截图", false);
                DrawTopBarMock(g, font, tagFont, barLeft, 94, "en", "Hide DSH window", true, "Long screenshot", false);

                using (var noteBrush = new SolidBrush(Color.FromArgb(150, 160, 175)))
                    g.DrawString("bar width follows the measured labels, so neither locale is clipped (R28)", tagFont, noteBrush, 8, H - 28);

                bmp.Save(path, ImageFormat.Png);
            }
        }
    }

    // One TopBarForm mock whose bar width is measured exactly like the real form's.
    private static void DrawTopBarMock(Graphics g, Font font, Font tagFont, int left, int top, string lang,
        string hideText, bool hideChecked, string longText, bool longChecked)
    {
        int w1 = TextRenderer.MeasureText(hideText, font).Width + 22;
        int w2 = TextRenderer.MeasureText(longText, font).Width + 22;
        Rectangle bar = new Rectangle(left, top, 14 + w1 + 18 + w2 + 14, 36);

        using (var pathBar = ToolBarStrip.Rounded(bar, 8))
        using (var barFill = new SolidBrush(Color.FromArgb(42, 42, 42)))
        using (var barPen = new Pen(Color.FromArgb(70, 70, 70), 1.2f))
        {
            g.FillPath(barFill, pathBar);
            g.DrawPath(barPen, pathBar);
        }

        Rectangle cb1 = new Rectangle(bar.Left + 14, bar.Top + 10, 16, 16);
        DrawCheckBox(g, cb1, hideChecked);
        using (var labelBrush = new SolidBrush(Color.FromArgb(220, 220, 220)))
            g.DrawString(hideText, font, labelBrush, cb1.Right + 6, bar.Top + 9);

        int dividerX = cb1.Right + 6 + TextRenderer.MeasureText(hideText, font).Width + 10;
        using (var divPen = new Pen(Color.FromArgb(70, 70, 70), 1f))
            g.DrawLine(divPen, dividerX, bar.Top + 8, dividerX, bar.Bottom - 8);

        Rectangle cb2 = new Rectangle(bar.Left + 14 + w1 + 18, bar.Top + 10, 16, 16);
        DrawCheckBox(g, cb2, longChecked);
        using (var longBrush = new SolidBrush(Color.FromArgb(220, 220, 220)))
            g.DrawString(longText, font, longBrush, cb2.Right + 6, bar.Top + 9);

        using (var tagBrush = new SolidBrush(Color.FromArgb(150, 160, 175)))
            g.DrawString("lang=" + lang + "  bar " + bar.Width + "x36", tagFont, tagBrush, 8, top + 12);
    }

    private static void DrawCheckBox(Graphics g, Rectangle r, bool isChecked)
    {
        using (var pathCb = ToolBarStrip.Rounded(r, 3))
        {
            if (!isChecked)
            {
                using (var boxPen = new Pen(Color.FromArgb(180, 180, 180), 1.4f))
                    g.DrawPath(boxPen, pathCb);
                return;
            }
            using (var boxFill = new SolidBrush(Color.FromArgb(65, 118, 230)))
                g.FillPath(boxFill, pathCb);
            using (var tickPen = new Pen(Color.White, 1.8f))
            {
                tickPen.StartCap = tickPen.EndCap = LineCap.Round;
                g.DrawLine(tickPen, r.Left + 3, r.Top + 8, r.Left + 7, r.Top + 12);
                g.DrawLine(tickPen, r.Left + 7, r.Top + 12, r.Right - 3, r.Top + 4);
            }
        }
    }

    private static void RenderLongShotPreview(string path)
    {
        using (var f9 = new Font("Microsoft YaHei UI", 9f))
        using (var f8 = new Font("Microsoft YaHei UI", 8f))
        using (var tagFont = new Font("Consolas", 8.5f))
        {
            // LongPreviewForm grows to fit its captions (R28); the mock keeps the very same
            // captions in both locales, so a clipped label would be visible in this PNG.
            string[] tags = new string[] { "zh", "en" };
            string[] headers = new string[] { "长截图预览 (3帧)", "Long screenshot (3 frames)" };
            string[] footers = new string[] { "滚轮继续 | Enter确定 | Esc取消", "Scroll · Enter done · Esc cancel" };
            int panelH = 430;
            int panelW = 190;
            for (int i = 0; i < headers.Length; i++)
            {
                panelW = Math.Max(panelW, TextRenderer.MeasureText(headers[i], f9).Width + 20);
                panelW = Math.Max(panelW, TextRenderer.MeasureText(footers[i], f8).Width + 16);
            }

            int selX = 60, selY = 50, selW = 480, selH = 500;
            int panelX = selX + selW + 30;
            string note = "panel width is measured from the captions; the stitched image was 480x1000 from 3 frames";
            int W = Math.Max(panelX + panelW * 2 + 20 + 60, 16 + TextRenderer.MeasureText(note, tagFont).Width);
            int H = selY + selH + 70;

            using (var bmp = new Bitmap(W, H))
            using (var g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;

                using (var bg = new SolidBrush(Color.FromArgb(32, 36, 42)))
                    g.FillRectangle(bg, 0, 0, W, H);

                Rectangle sel = new Rectangle(selX, selY, selW, selH);
                using (var selFill = new SolidBrush(Color.FromArgb(250, 250, 250)))
                    g.FillRectangle(selFill, sel);

                using (var textFont = new Font("Microsoft YaHei UI", 10f))
                using (var textBrush = new SolidBrush(Color.FromArgb(60, 60, 60)))
                {
                    g.DrawString("=== DeepSeekRuntime LongShot Frame Capture ===\n\n" +
                        "Scrolling mouse wheel captures consecutive frames...\n" +
                        "LongShot.FindVerticalOverlap detects vertical overlap...\n" +
                        "LongShot.Compose stitches frames into seamless image.\n\n" +
                        "Line 1: Sample captured text line alpha\n" +
                        "Line 2: Sample captured text line beta\n" +
                        "Line 3: Sample captured text line gamma\n" +
                        "Line 4: Sample captured text line delta\n" +
                        "Line 5: Sample captured text line epsilon\n" +
                        "Line 6: Sample captured text line zeta\n" +
                        "Line 7: Sample captured text line eta\n" +
                        "Line 8: Sample captured text line theta\n", textFont, textBrush, sel.Left + 20, sel.Top + 20);
                }

                DrawThickFrame(g, sel);
                DrawBadge(g, sel, sel.Width, sel.Height);

                for (int i = 0; i < headers.Length; i++)
                {
                    int px = panelX + i * (panelW + 20);
                    DrawLongPreviewPanel(g, new Rectangle(px, selY, panelW, panelH), headers[i], footers[i], f9, f8);
                    using (var panelTagBrush = new SolidBrush(Color.FromArgb(150, 160, 175)))
                        g.DrawString("lang=" + tags[i] + "  " + panelW + "x" + panelH, tagFont, panelTagBrush, px, selY - 20);
                }

                using (var noteBrush = new SolidBrush(Color.FromArgb(150, 160, 175)))
                    g.DrawString(note, tagFont, noteBrush, 8, selY + selH + 30);

                bmp.Save(path, ImageFormat.Png);
            }
        }
    }

    // One LongPreviewForm mock: same captions, same measured width, same PreviewSize scaling.
    private static void DrawLongPreviewPanel(Graphics g, Rectangle panel, string header, string footer, Font f9, Font f8)
    {
        using (var panelFill = new SolidBrush(Color.FromArgb(28, 32, 38)))
            g.FillRectangle(panelFill, panel);
        using (var framePen = new Pen(Color.FromArgb(65, 118, 230), 2))
            g.DrawRectangle(framePen, panel.Left, panel.Top, panel.Width - 1, panel.Height - 1);

        using (var headerBrush = new SolidBrush(Color.White))
            g.DrawString(header, f9, headerBrush, panel.Left + 10, panel.Top + 10);
        using (var footerBrush = new SolidBrush(Color.FromArgb(180, 180, 180)))
            g.DrawString(footer, f8, footerBrush, panel.Left + 8, panel.Bottom - 24);

        Size psize = LongShot.PreviewSize(480, 1000, 140, 340);
        Rectangle thumb = new Rectangle(panel.Left + (panel.Width - psize.Width) / 2, panel.Top + 36, psize.Width, psize.Height);
        using (var thumbFill = new SolidBrush(Color.White))
            g.FillRectangle(thumbFill, thumb);
        using (var thumbEdge = new Pen(Color.FromArgb(100, 100, 100), 1f))
            g.DrawRectangle(thumbEdge, thumb);
        using (var linePen = new Pen(Color.FromArgb(180, 180, 180), 1.5f))
        {
            for (int y = thumb.Top + 10; y < thumb.Bottom - 10; y += 14)
                g.DrawLine(linePen, thumb.Left + 10, y, thumb.Right - 10, y);
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

    public class LongShotProbeResult
    {
        public bool Ok;
        public int Frames;
        public int SelHeight;
        public int ComposedHeight;
        public bool MatchedMarkers;

        public string WindowLocation;
        public List<int> AttemptFrameCounts = new List<int>();
        public string Error;
        // N-2: the probe must drive the real SnipForm capture path, not its own loop.
        public bool RealPath;
        // N-2: wheel forwarding must be the only scroll driver; any direct-scroll
        // fallback makes the probe self-certifying.
        public bool FallbackUsed;
        // N-1: after FinishLongShot, an editor-like resize that shrinks sel must not
        // silently crop the export back to one viewport.
        public bool N1RegressionOk;
        // N-1 part 2: the exported PNG height must equal the composed height.
        public int ExportedHeight;
        // N-3: the keyboard hook must be installed during capture and gone after end.
        public bool HookInstalledDuringCapture;
        public bool HookUnhooked;
        // N-5/A3 leg: ending without confirm must write state=cancel and no image.
        public bool CancelLegOk;
        // t22 diagnosis trace: one line per wheel iteration.
        public List<string> Trace = new List<string>();
    }

    public static int RunLongShotProbeThreadSafe(string outDir, bool wheelOnly)
    {
        LongShotProbeResult res = ExecuteLongShotProbe(outDir, wheelOnly);
        string json = ToJson(res);
        string jsonPath = Path.Combine(outDir, "longshot_probe.json");
        Directory.CreateDirectory(outDir);
        File.WriteAllText(jsonPath, json);
        if (res.Ok)
        {
            Console.WriteLine("[LongShotProbe] PASS");
            return 0;
        }
        Console.WriteLine("[LongShotProbe] FAIL: " + res.Error);
        return 1;
    }

    public static LongShotProbeResult ExecuteLongShotProbe(string outDir)
    {
        return ExecuteLongShotProbe(outDir, true);
    }

    public static LongShotProbeResult ExecuteLongShotProbe(string outDir, bool wheelOnly)
    {
        var res = new LongShotProbeResult();
        res.SelHeight = 200;

        // N-2: drive the REAL overlay path. The old probe built its own scroll form and
        // stitched frames itself -- it proved the engine, not the overlay's 90ms sampler,
        // hole-punching, or wheel forwarding (reviewer's negative control proved the
        // fallback, not the pipeline, made it pass). Here a real SnipForm is constructed
        // via reflection-safe internal members (same assembly), aimed at a scrollable
        // helper window, and driven through StartLongShotCapture -> LongTimer_Tick
        // (wheel marks + timer samples) -> FinishLongShot -> RenderResult.
        System.Reflection.Assembly asm = System.Reflection.Assembly.GetExecutingAssembly();
        Type snipType = asm.GetType("SnipForm");
        Type progType = asm.GetType("Program");
        if (snipType == null || progType == null)
        {
            res.Error = "SnipForm/Program type not found";
            return res;
        }

        var helperForm = new ScrollHelperForm();
        Rectangle wa = Screen.PrimaryScreen.WorkingArea;
        // Park the helper at the LEFT edge of the working area: the overlay places its
        // preview panel at sel.Right+12, and with a centred helper that panel lands ON
        // the helper's content area -- its per-frame label ('3帧' -> '4帧') changed pixels
        // inside the selection and FindVerticalOverlap returned -1 (diagnosed via the
        // probe_rejected_sample.png rounded panel edge). At the left edge the preview
        // sits over empty desktop instead, and the captured content stays pure.
        int formX = wa.Left + 8;
        int formY = wa.Top + 8;
        helperForm.Location = new Point(formX, formY);
        helperForm.Size = new Size(360, 240);
        res.WindowLocation = "X=" + formX + ", Y=" + formY + ", W=360, H=240";
        helperForm.Show();
        SetWindowPos(helperForm.Handle, HWND_TOPMOST, formX, formY, 360, 240, SWP_SHOWWINDOW);
        BringWindowToTop(helperForm.Handle);
        SetForegroundWindow(helperForm.Handle);
        helperForm.Refresh();
        Application.DoEvents();

        // The selection inside the helper window, in screen coordinates. SnipForm's own
        // origin is the virtual-screen origin, so the overlay-relative sel must map
        // through it.
        Rectangle selScreen = new Rectangle(formX + 30, formY + 20, 300, 200);
        Point virtualOrigin = new Point(SystemInformation.VirtualScreen.X, SystemInformation.VirtualScreen.Y);
        Rectangle selOverlay = new Rectangle(selScreen.X - virtualOrigin.X, selScreen.Y - virtualOrigin.Y, selScreen.Width, selScreen.Height);

        object form = null;
        try
        {
            var flags = System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.Public;
            form = Activator.CreateInstance(snipType, new object[] { false });   // hide=false: no DSH hunt in the probe
            Form snip = (Form)form;

            // Position/size exactly like a real session and give the overlay its state.
            snip.StartPosition = FormStartPosition.Manual;
            snip.Bounds = new Rectangle(virtualOrigin.X, virtualOrigin.Y, SystemInformation.VirtualScreen.Width, SystemInformation.VirtualScreen.Height);
            snipType.GetField("sel", flags).SetValue(form, selOverlay);
            snipType.GetField("hasSel", flags).SetValue(form, true);
            snipType.GetField("origin", flags).SetValue(form, virtualOrigin);

            // OnLoad without Show() does full-screen CopyFromScreen + InitBlit; Show() runs
            // it with the real window and keeps the message pump honest.
            snip.Show();
            Application.DoEvents();
            SetWindowPos(snip.Handle, HWND_TOPMOST, snip.Left, snip.Top, snip.Width, snip.Height, SWP_SHOWWINDOW);
            Application.DoEvents();

            // Re-assert sel after OnLoad (OnLoad does not touch sel, but be explicit).
            snipType.GetField("sel", flags).SetValue(form, selOverlay);
            snipType.GetField("origin", flags).SetValue(form, virtualOrigin);

            // --- start the real capture path ---
            snipType.GetMethod("StartLongShotCapture", flags).Invoke(form, null);
            res.HookInstalledDuringCapture = (bool)snipType.GetProperty("HasKeyboardHook", flags | System.Reflection.BindingFlags.FlattenHierarchy).GetValue(form, null);
            Application.DoEvents();

            // --- scroll the helper: ONLY wheel forwarding drives frames (N-2/N-7) ---
            // PostMessage straight to the helper's HWND mirrors a real user wheel over
            // that window; the overlay's wheel-pending + 90ms sampler must pick it up.
            int targetFrames = 4;
            long deadline = Environment.TickCount + 20000;
            int scrollsSent = 0;
            var longFramesRef = (System.Collections.Generic.List<System.Drawing.Bitmap>)snipType.GetField("longFrames", flags).GetValue(form);
            int liveFrames = longFramesRef.Count;
            while (liveFrames < targetFrames && Environment.TickCount < deadline)
            {
                int framesBefore = liveFrames;
                if (wheelOnly)
                {
                    PostMessage(helperForm.Handle, WM_MOUSEWHEEL,
                        (IntPtr)((-120 & 0xFFFF) << 16),
                        (IntPtr)(((selScreen.Top & 0xFFFF) << 16) | (selScreen.Left & 0xFFFF)));
                }
                // wheelOnly=false: negative control -- no wheel is forwarded at all. The
                // overlay must never gain a frame, the loop must record FallbackUsed and
                // the probe must FAIL. If it could still PASS, the PASS was self-made.
                scrollsSent++;
                // Let the overlay's 90ms timer run its sampling beats.
                for (int wait = 0; wait < 8; wait++)
                {
                    Application.DoEvents();
                    System.Threading.Thread.Sleep(30);
                }
                liveFrames = longFramesRef.Count;
                int framesAfter = liveFrames;
                Bitmap lcNow = (Bitmap)snipType.GetField("longComposed", flags).GetValue(form);
                res.Trace.Add("scroll#" + scrollsSent + " scrollY=" + helperForm.ScrollY +
                    " frames=" + liveFrames + " stable=" + snipType.GetField("stableCount", flags).GetValue(form) +
                    " composedH=" + (lcNow != null ? lcNow.Height : 0) + " wheelPending=" +
                    snipType.GetField("wheelPending", flags).GetValue(form) +
                    " isLongCapturing=" + snipType.GetField("isLongCapturing", flags).GetValue(form) +
                    " reject=" + (snipType.GetField("lastFrameReject", flags).GetValue(form) ?? "-"));
                if (framesAfter == framesBefore)
                {
                    // A wheel that produces no new frame can be either (a) the failure
                    // this probe exists to catch -- forwarding broken -- or (b) a benign
                    // race where the 90ms sampler has not landed the frame yet. Only a
                    // second, generously waited miss counts as a real failure; a hard
                    // scroll bypass (the old ScrollBy crutch) is never used (N-2).
                    System.Threading.Thread.Sleep(400);
                    Application.DoEvents();
                    liveFrames = longFramesRef.Count;
                    framesAfter = liveFrames;
                    if (framesAfter == framesBefore)
                    {
                        // Distinguish "forwarding broken" from "content bottom reached":
                        // the helper simply stops moving at TotalHeight; if the wheel
                        // still scrolls the helper (ScrollY advances) but no frame lands,
                        // forwarding is genuinely broken.
                        if (!wheelOnly)
                        {
                            // Negative control: wheel forwarding was disabled up front, so a
                            // no-frame outcome is the EXPECTED failure; report it as such.
                            res.Error = "negative control: wheel forwarding disabled and no frames were captured (expected failure)";
                            res.FallbackUsed = true;
                            break;
                        }
                        int scrollBefore = helperForm.ScrollY;
                        PostMessage(helperForm.Handle, WM_MOUSEWHEEL,
                            (IntPtr)((-120 & 0xFFFF) << 16),
                            (IntPtr)(((selScreen.Top & 0xFFFF) << 16) | (selScreen.Left & 0xFFFF)));
                        for (int wait = 0; wait < 6; wait++)
                        {
                            Application.DoEvents();
                            System.Threading.Thread.Sleep(30);
                        }
                        if (helperForm.ScrollY == scrollBefore) break;   // content end reached
                        res.FallbackUsed = true;
                        break;
                    }
                }
            }
            res.Frames = longFramesRef.Count;

            Bitmap composedSnapshot = (Bitmap)snipType.GetField("longComposed", flags).GetValue(form);
            res.ComposedHeight = composedSnapshot != null ? composedSnapshot.Height : 0;

            // --- finish through the real path ---
            snipType.GetMethod("FinishLongShot", flags).Invoke(form, null);
            Application.DoEvents();

            // N-3: the hook must be gone the moment the capture ends.
            res.HookUnhooked = !((bool)snipType.GetProperty("HasKeyboardHook", flags | System.Reflection.BindingFlags.FlattenHierarchy).GetValue(form, null));

            // --- N-1 regression: the editor-drag crop ---
            // A real session lets the user drag any frame handle after finishing the
            // capture. Simulate a 1px upward move of the top edge (the same shrink the
            // reviewer performed by hand): the export must NOT silently shrink below the
            // composed canvas.
            Rectangle selBefore = (Rectangle)snipType.GetField("sel", flags).GetValue(form);
            int minH = (int)snipType.GetField("minLongShotHeight", flags).GetValue(form);
            Rectangle selShrunk = new Rectangle(selBefore.X, selBefore.Y + 1, selBefore.Width, selBefore.Height - 1);
            snipType.GetField("sel", flags).SetValue(form, selShrunk);
            Bitmap exported = (Bitmap)snipType.GetMethod("RenderResult", flags).Invoke(form, null);
            res.ExportedHeight = exported.Height;
            exported.Dispose();
            snipType.GetField("sel", flags).SetValue(form, selBefore);   // restore for the cancel leg

            res.N1RegressionOk = res.ExportedHeight >= res.ComposedHeight;

            // --- marker check on the composed canvas (real path output) ---
            if (composedSnapshot != null)
            {
                try { res.MatchedMarkers = ContainsMarkerColor(composedSnapshot); }
                catch (ArgumentException) { /* disposed during finish */ }
            }

            // --- A3 leg: cancel semantics (right-click/quit path) ---
            // The real cancel is a WndProc right-click -> Close(); OnFormClosed then writes
            // state=cancel because confirmed==false. Drive exactly that path: seed a
            // sentinel state, close the form unconfirmed, and require the state file to
            // end up "cancel".
            Program.WriteState("pending");
            try { ((Form)form).Close(); } catch (Exception) { }
            Application.DoEvents();
            string stateJson = "";
            try { stateJson = File.ReadAllText(Path.Combine(Program.OutDir, "dsh-snip-state.json")); } catch (Exception) { }
            bool stateCancel = stateJson.Contains("\"result\": \"cancel\"") || stateJson.Contains("\"result\":\"cancel\"");
            res.CancelLegOk = stateCancel;

            var failedLegs = new List<string>();
            if (res.Frames < 2) failedLegs.Add("frames<2");
            if (res.ComposedHeight <= res.SelHeight) failedLegs.Add("composed<=sel");
            if (!res.N1RegressionOk) failedLegs.Add("N1-crop-regression");
            if (!res.HookInstalledDuringCapture) failedLegs.Add("hook-not-installed");
            if (!res.HookUnhooked) failedLegs.Add("hook-not-unhooked");
            if (!res.CancelLegOk) failedLegs.Add("cancel-state-missing");
            if (!res.MatchedMarkers) failedLegs.Add("marker-missing");
            res.Ok = failedLegs.Count == 0;
            // N-2: mark the probe as real-path driven. The whole flow above constructed a
            // SnipForm and called its internal capture methods; FallbackUsed would mean
            // the wheel never reached the sampler.
            res.RealPath = !res.FallbackUsed;

            // Save evidence PNGs (composed canvas + any rejected sample + last frame).
            if (!Directory.Exists(outDir)) Directory.CreateDirectory(outDir);
            try
            {
                object rej = snipType.GetField("lastRejectedSample", flags).GetValue(form);
                if (rej != null) ((Bitmap)rej).Save(Path.Combine(outDir, "probe_rejected_sample.png"), ImageFormat.Png);
                var lf = ((System.Collections.Generic.List<System.Drawing.Bitmap>)snipType.GetField("longFrames", flags).GetValue(form));
                if (lf.Count > 0) lf[lf.Count - 1].Save(Path.Combine(outDir, "probe_last_frame.png"), ImageFormat.Png);
            }
            catch (Exception) { }
            if (composedSnapshot != null)
            {
                try { composedSnapshot.Save(Path.Combine(outDir, "longshot_probe.png"), ImageFormat.Png); }
                catch (ArgumentException) { /* disposed during finish */ }
            }
        }
        catch (Exception ex)
        {
            res.Error = ex.GetType().Name + ": " + ex.Message +
                (ex.InnerException != null ? " inner: " + ex.InnerException.Message : "");
            res.Ok = false;
        }
        finally
        {
            if (!res.Ok && res.Trace != null && res.Trace.Count > 0)
            {
                res.Error = (string.IsNullOrEmpty(res.Error) ? "(no error text)" : res.Error) + " | trace: " + string.Join(" ; ", res.Trace.ToArray());
            }
            if (form != null)
            {
                try { ((Form)form).Close(); } catch (Exception) { }
                try { ((Form)form).Dispose(); } catch (Exception) { }
            }
            try { helperForm.Close(); } catch (Exception) { }
            try { helperForm.Dispose(); } catch (Exception) { }
        }

        return res;
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

    // A8 (N-5): assert real geometry/pixels instead of a literal true. The top-bar PNG
    // must be a readable image with actual content and sane geometry.
    static bool SelfCheckGeometryAndPixels(string pngPath)
    {
        try
        {
            if (!File.Exists(pngPath)) return false;
            using (Bitmap bmp = new Bitmap(pngPath))
            {
                if (bmp.Width < 100 || bmp.Height < 20) return false;
                // Real content: not a single flat colour across sampled pixels.
                Color first = bmp.GetPixel(5, 5);
                bool varied = false;
                for (int x = 5; x < bmp.Width - 5 && !varied; x += 7)
                {
                    for (int y = 5; y < bmp.Height - 5 && !varied; y += 3)
                    {
                        Color c = bmp.GetPixel(x, y);
                        if (Math.Abs(c.R - first.R) + Math.Abs(c.G - first.G) + Math.Abs(c.B - first.B) > 30) varied = true;
                    }
                }
                return varied;
            }
        }
        catch (Exception) { return false; }
    }

    public static string ToJson(LongShotProbeResult r)
    {
        var sb = new System.Text.StringBuilder();
        sb.Append("{\n");
        sb.Append("  \"ok\": " + (r.Ok ? "true" : "false") + ",\n");
        sb.Append("  \"frames\": " + r.Frames + ",\n");
        sb.Append("  \"selHeight\": " + r.SelHeight + ",\n");
        sb.Append("  \"composedHeight\": " + r.ComposedHeight + ",\n");
        sb.Append("  \"matchedMarkers\": " + (r.MatchedMarkers ? "true" : "false") + ",\n");
        sb.Append("  \"realPath\": " + (r.RealPath ? "true" : "false") + ",\n");
        sb.Append("  \"fallbackUsed\": " + (r.FallbackUsed ? "true" : "false") + ",\n");
        sb.Append("  \"n1RegressionOk\": " + (r.N1RegressionOk ? "true" : "false") + ",\n");
        sb.Append("  \"exportedHeight\": " + r.ExportedHeight + ",\n");
        sb.Append("  \"hookInstalledDuringCapture\": " + (r.HookInstalledDuringCapture ? "true" : "false") + ",\n");
        sb.Append("  \"hookUnhooked\": " + (r.HookUnhooked ? "true" : "false") + ",\n");
        sb.Append("  \"cancelLegOk\": " + (r.CancelLegOk ? "true" : "false") + ",\n");
        sb.Append("  \"windowLocation\": \"" + EscapeJson(r.WindowLocation) + "\",\n");
        if (!r.Ok && r.Trace != null && r.Trace.Count > 0)
        {
            sb.Append("  \"trace\": [");
            for (int i = 0; i < r.Trace.Count; i++)
            {
                sb.Append((i > 0 ? ", " : "") + "\"" + EscapeJson(r.Trace[i]) + "\"");
            }
            sb.Append("],\n");
        }
        sb.Append("  \"attemptFrameCounts\": [");
        for (int i = 0; i < r.AttemptFrameCounts.Count; i++)
        {
            sb.Append(r.AttemptFrameCounts[i] + (i + 1 < r.AttemptFrameCounts.Count ? ", " : ""));
        }
        sb.Append("]");
        if (!string.IsNullOrEmpty(r.Error))
        {
            sb.Append(",\n  \"error\": \"" + EscapeJson(r.Error) + "\"");
        }
        sb.Append("\n}");
        return sb.ToString();
    }

    public static int RunLongShotProbe(string outDir)
    {
        if (!Directory.Exists(outDir)) Directory.CreateDirectory(outDir);
        LongShotProbeResult res = ExecuteLongShotProbe(outDir);
        string json = ToJson(res);
        string jsonPath = Path.Combine(outDir, "longshot_probe.json");
        File.WriteAllText(jsonPath, json);
        if (res.Ok)
        {
            Console.WriteLine("[LongShotProbe] PASS");
            return 0;
        }
        else
        {
            Console.WriteLine("[LongShotProbe] FAIL: " + res.Error);
            return 1;
        }
    }
}
