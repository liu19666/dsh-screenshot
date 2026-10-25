// Long-screenshot (scroll capture) engine (owner: engine-dev).
//
// Contract: pure image math, no UI, no OS calls. The overlay feeds frames captured
// while the user scrolls and asks for the stitched result and for the preview size.
// Must compile for C# 5 (net48 csc) and never throw on degenerate input.
//
// Compose offsets contract (pinned by t16 / REVIEW-T7 F-13, single semantics):
//   offsets[i] = y offset of frame i's TOP edge on the stitched canvas.
//   offsets[0] == 0; offsets is non-decreasing; offsets.Count == frames.Count.
//   Compose allocates the canvas as offsets[Count-1] + frames[Count-1].Height
//   (or exactly `height` rows when height > 0, which must be >= that sum) and
//   pastes frame i at (0, offsets[i]).
//   Contract violations -- count mismatch, offsets[0] != 0, non-monotonic
//   offsets, a frame extending past the canvas, a null frame -- throw
//   ArgumentException instead of producing a silently wrong image. The legacy
//   "overlaps list" style (offsets.Count == frames.Count - 1) does NOT satisfy
//   this contract and is rejected. Empty/null frames stay degenerate-tolerant
//   (blank canvas) so one bad call cannot take the overlay down.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class LongShot
{
    // Vertical pixel offset (0..height) of "next" relative to "prev": how many rows of
    // "next" are already present at the bottom of "prev". Returns -1 when no reliable
    // overlap is found. Implementations should use a column-sampled row-difference
    // search, tolerant to a few pixels of horizontal jitter.
    public static int FindVerticalOverlap(Bitmap prev, Bitmap next, int minOverlap, int maxOverlap)
    {
        if (prev == null || next == null) return -1;
        if (prev.Width <= 0 || prev.Height <= 0 || next.Width <= 0 || next.Height <= 0) return -1;
        if (prev.Width != next.Width) return -1;

        int w = prev.Width;
        int h1 = prev.Height;
        int h2 = next.Height;

        int minO = Math.Max(1, minOverlap);
        int maxO = Math.Min(Math.Min(h1, h2), maxOverlap);
        if (minO > maxO) return -1;

        BitmapData d1 = null;
        BitmapData d2 = null;
        try
        {
            d1 = prev.LockBits(new Rectangle(0, 0, w, h1), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            d2 = next.LockBits(new Rectangle(0, 0, w, h2), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);

            int stride1 = d1.Stride / 4;
            int stride2 = d2.Stride / 4;
            int[] pix1 = new int[stride1 * h1];
            int[] pix2 = new int[stride2 * h2];
            Marshal.Copy(d1.Scan0, pix1, 0, pix1.Length);
            Marshal.Copy(d2.Scan0, pix2, 0, pix2.Length);

            // Precompute sample columns
            int sampleCount = Math.Min(16, w);
            int[] sampleCols = new int[sampleCount];
            for (int i = 0; i < sampleCount; i++)
            {
                sampleCols[i] = (w * (i + 1)) / (sampleCount + 1);
            }

            // Search from largest candidate overlap down to minOverlap
            int bestK = -1;
            long bestDiff = long.MaxValue;

            for (int k = maxO; k >= minO; k--)
            {
                // Fast filter 1: top row of next (y=0) vs corresponding row of prev (h1 - k)
                int rPrev0 = (h1 - k) * stride1;
                int rNext0 = 0;
                bool match = true;
                for (int s = 0; s < sampleCount; s++)
                {
                    int col = sampleCols[s];
                    if (pix1[rPrev0 + col] != pix2[rNext0 + col])
                    {
                        match = false;
                        break;
                    }
                }
                if (!match) continue;

                // Fast filter 2: bottom row of next overlap (y = k - 1) vs bottom row of prev (h1 - 1)
                int rPrevEnd = (h1 - 1) * stride1;
                int rNextEnd = (k - 1) * stride2;
                for (int s = 0; s < sampleCount; s++)
                {
                    int col = sampleCols[s];
                    if (pix1[rPrevEnd + col] != pix2[rNextEnd + col])
                    {
                        match = false;
                        break;
                    }
                }
                if (!match) continue;

                // Fast filter 3: middle row (y = k / 2)
                int mid = k / 2;
                int rPrevMid = (h1 - k + mid) * stride1;
                int rNextMid = mid * stride2;
                for (int s = 0; s < sampleCount; s++)
                {
                    int col = sampleCols[s];
                    if (pix1[rPrevMid + col] != pix2[rNextMid + col])
                    {
                        match = false;
                        break;
                    }
                }
                if (!match) continue;

                // Fast filter 4: quarter rows (k/4 and 3k/4)
                if (k >= 4)
                {
                    int q1 = k / 4;
                    int rPrevQ1 = (h1 - k + q1) * stride1;
                    int rNextQ1 = q1 * stride2;
                    for (int s = 0; s < sampleCount; s++)
                    {
                        int col = sampleCols[s];
                        if (pix1[rPrevQ1 + col] != pix2[rNextQ1 + col])
                        {
                            match = false;
                            break;
                        }
                    }
                    if (!match) continue;

                    int q3 = (3 * k) / 4;
                    int rPrevQ3 = (h1 - k + q3) * stride1;
                    int rNextQ3 = q3 * stride2;
                    for (int s = 0; s < sampleCount; s++)
                    {
                        int col = sampleCols[s];
                        if (pix1[rPrevQ3 + col] != pix2[rNextQ3 + col])
                        {
                            match = false;
                            break;
                        }
                    }
                    if (!match) continue;
                }

                // Detailed comparison across all k rows
                long diff = 0;
                int stepX = w > 200 ? 2 : 1;
                long maxTolerance = (long)k * (w / stepX) * 2; // small tolerance for noise
                bool differs = false;

                for (int y = 0; y < k; y++)
                {
                    int pRow = (h1 - k + y) * stride1;
                    int nRow = y * stride2;
                    for (int x = 0; x < w; x += stepX)
                    {
                        int c1 = pix1[pRow + x];
                        int c2 = pix2[nRow + x];
                        if (c1 != c2)
                        {
                            int r1 = (c1 >> 16) & 0xFF, g1 = (c1 >> 8) & 0xFF, b1 = c1 & 0xFF;
                            int r2 = (c2 >> 16) & 0xFF, g2 = (c2 >> 8) & 0xFF, b2 = c2 & 0xFF;
                            diff += Math.Abs(r1 - r2) + Math.Abs(g1 - g2) + Math.Abs(b1 - b2);
                            if (diff > maxTolerance)
                            {
                                differs = true;
                                break;
                            }
                        }
                    }
                    if (differs) break;
                }

                if (!differs)
                {
                    // Check that the overlap region actually has some non-uniform features
                    // (prevent false match on completely flat blank regions)
                    int firstPx = pix2[0];
                    bool hasFeature = false;
                    for (int y = 0; y < k; y += Math.Max(1, k / 8))
                    {
                        int row = y * stride2;
                        for (int x = 0; x < w; x += Math.Max(1, w / 8))
                        {
                            if (pix2[row + x] != firstPx)
                            {
                                hasFeature = true;
                                break;
                            }
                        }
                        if (hasFeature) break;
                    }

                    if (hasFeature && diff < bestDiff)
                    {
                        bestDiff = diff;
                        bestK = k;
                        if (diff == 0)
                        {
                            // Exact match found!
                            return bestK;
                        }
                    }
                }
            }

            if (bestK > 0 && bestDiff <= (long)bestK * (w / 2) * 2)
            {
                return bestK;
            }

            return -1;
        }
        catch
        {
            return -1;
        }
        finally
        {
            if (d1 != null && prev != null) prev.UnlockBits(d1);
            if (d2 != null && next != null) next.UnlockBits(d2);
        }
    }

    // Stacks frames onto one canvas. offsets[i] is the canvas-y of frame i's top
    // edge (see the pinned contract in the file header). The canvas height is
    // offsets[Count-1] + frames[Count-1].Height, or exactly `height` when height > 0.
    public static Bitmap Compose(IList<Bitmap> frames, IList<int> offsets, int width, int height)
    {
        if (frames == null || frames.Count == 0)
        {
            return new Bitmap(Math.Max(1, width), Math.Max(1, height), PixelFormat.Format32bppArgb);
        }

        if (offsets == null)
        {
            throw new ArgumentException("LongShot.Compose: offsets must not be null when frames is non-empty");
        }
        if (offsets.Count != frames.Count)
        {
            throw new ArgumentException("LongShot.Compose: offsets.Count (" + offsets.Count + ") must equal frames.Count (" +
                frames.Count + "); the legacy overlaps-style list (Count == frames.Count - 1) is not accepted");
        }
        if (offsets[0] != 0)
        {
            throw new ArgumentException("LongShot.Compose: offsets[0] must be 0, got " + offsets[0]);
        }

        int last = offsets.Count - 1;
        int computedH = offsets[last] + frames[last].Height;
        int targetH = height > 0 ? height : computedH;

        for (int i = 0; i < frames.Count; i++)
        {
            if (frames[i] == null)
            {
                throw new ArgumentException("LongShot.Compose: frames[" + i + "] must not be null");
            }
            if (i > 0 && offsets[i] < offsets[i - 1])
            {
                throw new ArgumentException("LongShot.Compose: offsets must be non-decreasing, offsets[" + i + "] (" +
                    offsets[i] + ") < offsets[" + (i - 1) + "] (" + offsets[i - 1] + ")");
            }
            if (offsets[i] + frames[i].Height > targetH)
            {
                throw new ArgumentException("LongShot.Compose: frame " + i + " at y=" + offsets[i] + " with height " +
                    frames[i].Height + " exceeds the canvas height " + targetH);
            }
        }

        int targetW = width > 0 ? width : frames[0].Width;
        var bmp = new Bitmap(Math.Max(1, targetW), Math.Max(1, targetH), PixelFormat.Format32bppArgb);

        using (Graphics g = Graphics.FromImage(bmp))
        {
            g.InterpolationMode = InterpolationMode.NearestNeighbor;
            g.PixelOffsetMode = PixelOffsetMode.Half;

            // Later frames are pasted on top; the overlap rows are identical pixels,
            // so the visible result is the seamless stitched scroll.
            for (int i = 0; i < frames.Count; i++)
            {
                g.DrawImage(frames[i], 0, offsets[i]);
            }
        }

        return bmp;
    }

    // Preview box for the floating preview panel: keeps the content aspect ratio and
    // shrinks proportionally as the captured content grows.
    public static Size PreviewSize(int contentW, int contentH, int maxW, int maxH)
    {
        int cw = Math.Max(1, contentW);
        int ch = Math.Max(1, contentH);
        int mw = Math.Max(1, maxW);
        int mh = Math.Max(1, maxH);

        double scale = Math.Min((double)mw / cw, (double)mh / ch);
        if (scale > 1.0) scale = 1.0;

        int w = Math.Max(1, (int)Math.Round(cw * scale));
        int h = Math.Max(1, (int)Math.Round(ch * scale));
        if (w > mw) w = mw;
        if (h > mh) h = mh;

        return new Size(w, h);
    }
}
