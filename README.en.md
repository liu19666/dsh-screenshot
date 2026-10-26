# DSH Screenshot Tool v2

Native screenshot tool v2 for DeepSeek Harness on Windows: automatic window/screen/taskbar recognition & highlight, drag selection, shapes/pen/text annotations, mosaic, color picker, and injection into DSH composer without auto-sending. Left-click keeps the DSH window; right-click minimizes it first.

![platform](https://img.shields.io/badge/platform-Windows%2010%2B-0078D6?logo=windows&logoColor=white)
![dsh](https://img.shields.io/badge/DeepSeek%20Harness-%E2%89%A50.2.0-4B6BFB)
![license](https://img.shields.io/badge/license-MIT-green)
![version](https://img.shields.io/badge/version-2.1.0-blue)

English | [中文](README.md)

![Overview](docs/screenshots/overview-zh.png)
> *Note: The screenshot shows the v2.1 interface — a hovered candidate region (thicker blue frame + size badge at its top-left), the area outside dimmed, and the icon-only toolbar.*

## Features (R1–R30)

| Feature | Description |
|---|---|
| Scissors Entry Button (left/right click) | Injected to the left of the microphone button in the same container; matching size, border radius, and hover state; **left-click opens the overlay without hiding DSH, right-click minimizes DSH first**; the tooltip spells out both gestures and the browser context menu is suppressed (R1, R2, R2a) |
| Auto Target Detection | Moving mouse automatically highlights windows, desktop screens, or taskbars with a blue border, white size badge (e.g. `888×777`), and exterior dimming (R6, R8, R9) |
| Click & Drag Selection | Click to select the detected region directly; or drag to draw a bounding box (R10, R11) |
| No toggle bar, no settings file | v2.1 removed the top "Hide DSH Window" / "Long Screenshot" bar and the `settings.json` persistence: there is no second hiding switch inside the capture UI (R3, R13) |
| Unified Editor | Every screenshot enters the same editor: shapes (rect/ellipse/line), arrow, pen, text (with color & thickness), and mosaic (R18, R20, R21) |
| Save / Cancel / Confirm | Right-side actions: Save PNG to disk, Cancel (red cross), Confirm (green checkmark) (R22, R24) |
| Composer Injection (No Auto-Send) | Confirmed image is injected into the DSH composer via synthetic paste event; never auto-sent (R23) |
| Quick Exit | Right-click outside selection or press Esc to cancel and restore DSH (R4, R17) |
| Warm Process | Fast launch via resident `SnipTool.exe --serve --parent <pid>` (R27) |
| Locale & Theme Sync | Follows DSH language (zh/en) and theme (light/dark) (R28) |
| 100% Local & Zero Telemetry | Native .NET Framework 4.8 / GDI+ implementation; zero network requests, zero telemetry (R26, R29) |

![Toolbar](docs/screenshots/toolbar.png)
> *Note: v2.1 toolbar: rectangle, ellipse, line, arrow, pen, text, mosaic | save, cancel (red cross), confirm (green check). Undo is `Ctrl+Z`.*

## Installation

Requires Windows 10/11 and DeepSeek Harness. No administrator privileges or external runtimes required.

1. Copy or clone this repository into your plugins directory, e.g. `D:\dsh-home\plugins\dsh-screenshot`.

2. Add the bundle and dependency to your DSH profile (`<DSH_HOME>/profiles/<name>/package.json`):

   ```json
   {
     "dsh": {
       "profile": {
         "bundles": ["@deepseek-ai/dsh-base", "@deepseek-ai/dsh-web-app", "dsh-screenshot"]
       }
     },
     "dependencies": {
       "dsh-screenshot": "link:D:/dsh-home/plugins/dsh-screenshot"
     }
   }
   ```

3. Launch DSH. The scissors button appears immediately to the left of the microphone button:

   ![Screenshot Button](docs/screenshots/button.png)
   > *Note: Diagram shows v1 button style. v2 scissors button is placed immediately before the mic in the same container, without the old chevron options menu.*

## Keyboard & Mouse Shortcuts

| Action | Result |
|---|---|
| Left-click scissors button | Open the capture overlay, DSH window left untouched |
| Right-click scissors button | Open the capture overlay with DSH minimized; restored on exit/confirm |
| Click | Confirm automatically detected window/screen/taskbar |
| Drag mouse | Manually select a rectangular region |
| Drag handles | Adjust selection bounds |
| `Ctrl+Z` | Undo last annotation |
| `C` or `Ctrl+C` | Copy color hex (`#RRGGBB`) under cursor |
| Enter or `✓` | Confirm and inject image into DSH composer (no auto-send) |
| `Esc`, Right Click, `✕` | Cancel screenshot and restore DSH window |

## Architecture

- **Host (lib/index.js)**: Cordis plugin service declaring `inject = ['webServer']`, starts one helper process per capture (`SnipTool.exe --parent <pid> --out <dir> --client`, run from a copy under `%LOCALAPPDATA%\dsh-screenshot\<hash>` so `node_modules` is never locked; the process runs a single session and exits, so nothing of this plugin is running between captures), handles `/shot/api/capture`, `/shot/api/last`, and `/shot/api/probe` routes (`/shot/api/probe` is disabled by default; `touch %TEMP%\dsh-shot-debug.on` and refresh, then POST `/shot/api/probe` will write front-end diagnostic JSON to `%TEMP%\dsh-shot-probe.json`), passes language and theme plus `hide=1|0` for this click (left-click 0, right-click 1).
- **Client (lib/client.js)**: Injects scissors button to the left of the microphone, removes legacy options menu, injects image into composer via synthetic paste event without auto-sending, provides readable bilingual errors.
- **Native (bin/SnipTool.exe)**: Native C# overlay implementing window/screen/taskbar detection, the unified annotation editor (no long screenshot, no settings file since v2.1).
