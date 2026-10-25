// Long-screenshot (scroll capture) engine (owner: engine-dev).
//
// Contract: pure image math, no UI, no OS calls. The overlay feeds frames captured
// while the user scrolls and asks for the stitched result and for the preview size.
// Must compile for C# 5 (net48 csc) and never throw on degenerate input.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;

public static class LongShot
{
    // Vertical pixel offset (0..height) of "next" relative to "prev": how many rows of
    // "next" are already present at the bottom of "prev". Returns -1 when no reliable
    // overlap is found. Implementations should use a column-sampled row-difference
    // search, tolerant to a few pixels of horizontal jitter.
    public static int FindVerticalOverlap(Bitmap prev, Bitmap next, int minOverlap, int maxOverlap)
    {
        return -1;
    }

    // Stacks frames at the given offsets into one bitmap of the given size.
    public static Bitmap Compose(IList<Bitmap> frames, IList<int> offsets, int width, int height)
    {
        var bmp = new Bitmap(Math.Max(1, width), Math.Max(1, height), PixelFormat.Format32bppArgb);
        return bmp;
    }

    // Preview box for the floating preview panel: keeps the content aspect ratio and
    // shrinks proportionally as the captured content grows.
    public static Size PreviewSize(int contentW, int contentH, int maxW, int maxH)
    {
        int w = Math.Max(1, contentW);
        int h = Math.Max(1, contentH);
        double scale = Math.Min((double)maxW / w, (double)maxH / h);
        if (scale > 1.0) scale = 1.0;
        return new Size(Math.Max(1, (int)Math.Round(w * scale)), Math.Max(1, (int)Math.Round(h * scale)));
    }
}
