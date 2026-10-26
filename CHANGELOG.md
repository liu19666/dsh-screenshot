# Changelog

## 2.1.4

- Changed: the helper now **outlives its session by 30 seconds** instead of leaving immediately.
  It is still started on the first click (nothing runs at load), still exits on its own, and the
  30s window is the only lifetime extension: a session ends (confirm / cancel / right-click) →
  the host notices the native state file change and kills the helper 30s later. A second capture
  inside that window reuses the running helper over the wake-up pipe, so it comes up instantly;
  if the session never reports, a 15-minute hard cap still removes the process.
- Unchanged: the helper still runs from `%LOCALAPPDATA%\dsh-screenshot\<sha256-8>\SnipTool.exe`
  (never `node_modules`), `bin/SnipTool.exe` bytes are identical to 2.1.1-2.1.3, and no process
  is spawned at page load or on an idle timer.

## 2.1.3

- Changed: **no background process at all.** One helper process is started when you click the
  scissors button and it is gone as soon as the session ends (confirm, cancel or right-click).
  The warm/`--serve` model is gone from the host half: no pipe, no keep-alive, no 180s idle
  window, nothing left running between captures. Cost: ~0.3-0.5s of startup per capture.
  A second click while an overlay is open is absorbed by the native single-instance mutex.
- Unchanged: the helper still runs from `%LOCALAPPDATA%\dsh-screenshot\<sha256-8>\SnipTool.exe`,
  so `node_modules` is never locked by a running process (see 2.1.2); `bin/SnipTool.exe` bytes
  are identical to 2.1.1/2.1.2.

## 2.1.2

- Fixed: installing any other plugin from the market failed with `EPERM` and rolled the whole
  transaction back (so nothing was installed). The helper ran out of
  `node_modules/dsh-screenshot/bin/SnipTool.exe`, and Windows keeps a running image's own file
  locked, so a package manager re-importing this package could not replace it. The helper is now
  copied once per build to `%LOCALAPPDATA%\dsh-screenshot\<sha256-8>\SnipTool.exe` and runs from
  there; `node_modules` only holds the source file and is never locked. Copies of older builds are
  pruned on the next capture; if the copy cannot be made the packaged file is used as before.
- Changed: no helper process is started when DSH loads and none is kept alive on a timer. The
  first capture starts it, and it keeps itself ready for the next one and exits after 180s idle.
  This removes the other half of the `EPERM` problem (a process that is always holding the file)
  at the cost of ~0.3s on the first capture after idle. Consequence: nothing in this plugin is
  running until you take a screenshot.
- Fixed the package description, which still advertised the long-screenshot feature removed in 2.1.0.

## 2.1.1

- Fixed: after confirming a capture ("done") DSH came back windowed instead of maximised.
  The helper restored the window twice on that path (once before the paste, once on close),
  and `SW_RESTORE` un-maximises a window that is already restored. Right-click exit only
  restored once, which is why cancel never showed the bug. The helper now remembers whether
  DSH was maximised before it was minimised and restores exactly once (`RestoreDsh()`).
  The same fix covers the left-click entry, which never hid the window but still resized it.

## 2.1.0

- Removed the long-screenshot feature entirely (scrolling capture, the preview window, the top
  switch bar and the settings file). The wheel-driven preview never worked reliably on real
  pages, so it was dropped instead of patched further.
- Entry is two gestures on the same scissors button: left click captures with the DSH window
  kept, right click captures with the DSH window minimised (restored on exit). The tooltip now
  reads 左键保留窗口，右键最小化窗口 / Left click keeps the window, right click minimises it.
- Hiding is decided per click and travels in the wake line (`hide=1|0`) or the cold-start flag
  (`--hide` / `--no-hide`); nothing is persisted any more.

## 2.0.0

- Rewritten as a Cordis plugin with a native helper: window / monitor / taskbar detection,
  dimming with a size badge, manual drag selection, an annotation toolbar (rectangle, ellipse,
  line, arrow, pen, text, mosaic) and one-click insertion into the composer without sending.

## 1.0.5

- The composer tooltip follows the DSH language again: its pointer listeners were bound to
  nodes that DSH replaces when it re-renders the composer (theme or language switch), so the
  tooltip kept the old language. They are delegated from the document now.
- The tooltip and the capture UI share one source: the client asks the host for the locale
  (`/shot/api/lang`), and the host reads it from the DSH profile - the same value it passes to
  the tool - so the two can no longer disagree.

## 1.0.4

- Dark mode: the magnifier card no longer draws an outline. The hard white border showed as a
  bright line beside the text block, and a grey replacement still read as a strip, so the card
  is drawn bare in dark mode; light mode keeps its white outline.
- The magnifier hint reads `按Ctrl+C复制色号` / `Press Ctrl+C to copy the colour`.

## 1.0.3

- The magnifier hint now reads `按Ctrl+C复制色号` / `Press Ctrl+C to copy the colour`.

## 1.0.2

- Fix: every capture now runs on its own STA thread with a fresh message loop. Reusing the
  thread left a stale WinForms context, so the second and later captures died in
  `Control.CreateHandle()` with `ObjectDisposedException: cannot access a disposed object: "SnipForm"`.

## 1.0.1

- Fix: the session message loop could wedge after a capture closed, so later presses were
  acknowledged but never showed the overlay (the "click does nothing" bug).
- Fix: guard every window message handler against a disposed form (the
  "cannot access a disposed object: SnipForm" dialog).
- Fix: the toolbar flashed at the bottom of the screen before moving to its real position.
- Fix: the magnifier stopped refreshing while the pointer slid along a screen edge.
- Fix: right click cancels the capture without leaking the desktop context menu.
- New: the UI follows the DSH language (zh / en) on every capture.
- Docs: bilingual README, real screenshots, MIT licence.

## 1.0.0

- First release: instant region capture, annotations, colour picker, magnifier.
