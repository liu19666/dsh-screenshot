# DSH 截图插件 v2 — 手工验证清单（R1–R30）

本文件是 `docs/SPEC.md` 中 R1–R30 逐条的可执行验收步骤。自动化证据由
`tools/e2e.ps1` 产生，但覆盖层/编辑器的视觉效果与交互必须人工按本清单确认一遍。

## 前置条件

- Windows 10/11 x64，已安装 .NET Framework 4.8（系统自带）。
- Node.js ≥ 20 与 pnpm（只在打包/安装时需要）。
- DSH 桌面端已按 `docs/RELEASE.md` 安装本插件，并已重启 DSH。
- 在仓库根目录准备证据目录：`New-Item -ItemType Directory -Force out/evidence/manual`
  每条证据以 `out/evidence/manual/R<编号>-<简述>.png` 命名，便于归档与复查。

## 一键自动化证据

```powershell
# 只做接线自检（不构建、不启动原生工具、不碰 profile），应 exit 0
pwsh -NoProfile -File tools/e2e.ps1 -DryRun

# 完整证据链（12 步）：wiring -> build -Tests -> EngineTests -> SnipTool --selftest
#             -> SnipTool --longshot-probe -> SnipTool --longshot-probe wheelOnly=false（负控，必须非零退出）
#             -> SnipTool --crash-probe
#             -> 真实槽位契约门（tools/client-contract.mjs，第 8 步，硬门）
#             -> 插件冒烟 -> install.ps1 -WhatIf（安装计划）-> npm pack（打包自检）-> 文档检查
pwsh -NoProfile -File tools/e2e.ps1

# 契约门判定 PASS、但 lib/client.js 的字节与 tools/fixtures/client-baseline.json 记录不同时，
# 该步只报告 WARN、链路仍 exit 0。确认这批字节已复审后再显式接受（普通运行绝不自动改基线）：
pwsh -NoProfile -File tools/e2e.ps1 -AcceptClientSha
node tools/client-contract.mjs --update-baseline --reason "为什么这批字节已经复审"

# 原生程序已构建、暂时不想重编：仍然跑插件冒烟 + 安装计划 + 打包 + 文档检查
pwsh -NoProfile -File tools/e2e.ps1 -SkipBuild

# 跳过原生步骤（engine、selftest、longshot-probe、longshot-negative、crash-probe），只做 JS / 安装计划 / 打包 / 文档检查
pwsh -NoProfile -File tools/e2e.ps1 -SkipBuild -SkipNative

# 所有模块都应已实现时使用严格模式：pending 也算失败
pwsh -NoProfile -File tools/e2e.ps1 -Strict
```

产物：`out/evidence/report.json`（schema `dsh-screenshot-evidence/v2`）、
`out/evidence/SUMMARY.md`、`out/evidence/logs/*.log`、`out/evidence/selftest/*.png` + `summary.json`、
`out/evidence/engine.json` + `out/evidence/png/engine/*.png`、`out/evidence/ev-contract/client-contract.json`
（真实槽位契约门：15 项检查 + 旧 2.0.0 bundle 负控）、`out/evidence/plugin-smoke.json`、
`out/evidence/longshot/longshot_probe.json`（长截图真实链路探针）、
`out/evidence/crashprobe/crash_probe.json`（崩溃日志探针）、
以及 `npm pack` 产出的 `dsh-screenshot-<version>.tgz`（package 步骤会校验 tgz 文件白名单）。

### 版本化验收门禁 `tools/accept.ps1`（G-7）

`tools/e2e.ps1` 只负责跑链路并留下证据；`tools/accept.ps1` 是**判定版**：它调用前者，再逐条断言
各产物（engine.json 的 8 项检测、selftest 的 13 条 criteria、longshot 探针字段、crash 探针字节增长、
契约门 15 项 + 旧 bundle 三类负控、插件冒烟 8 项、文档步 PASS、可选 N1 回归 harness），
并对 `bin/*.exe`、`dist/*.tgz`、仓库根 `*.tgz` 取前后 sha256 快照。任一条失败即 `exit 1`。

```powershell
# 全量验收：构建 + 打包 + 全链路（等价于复现 captain 的收官脚本）
pwsh -NoProfile -File tools/accept.ps1

# 零字节验收：复用现有 bin/*.exe 与 dsh-screenshot-<version>.tgz，不重编不重打包；
# 若这四个产物的字节有任何变化（changed/added/removed）则 exit 1
pwsh -NoProfile -File tools/accept.ps1 -NoBuild -SkipPack
```

产物：`out/ev-accept/accept.json`（schema `dsh-screenshot-accept/v1`）、`out/ev-accept/ACCEPT.md`、
`out/ev-accept/e2e.log`（内含被委托的 e2e 输出）与前后字节对比表；`-OutDir` 越界同样 `exit 2`。
### 证据目录 `-OutDir` 的语义（N-9）

相对路径**一律相对仓库根**（`tools/e2e.ps1` 的父目录）解析，与你在哪个目录调用无关；
解析结果必须落在仓库内，否则直接 `exit 2` 并打印仓库根与实际解析路径。因此下面两条命令
写的是同一个目录 `<repo>/out/evidence-review`：

```powershell
cd <repo>;        pwsh -NoProfile -File tools/e2e.ps1 -OutDir out/evidence-review
cd <workspace>;   pwsh -NoProfile -File <repo>/tools/e2e.ps1 -OutDir out/evidence-review
```

绝对路径也可以用，但同样必须在仓库内；`-OutDir C:\Windows\Temp\x` 会被拒绝（exit 2）。
（历史上曾按调用方 cwd 解析，t15 复审时把证据写到了工作区根的 `out/review-t15`，即本条的由来。）

插件冒烟只有一份实现：`tools/plugin-smoke.mjs`（参数 `--root`、`--json`、`--quiet`，检查 meta / patch /
host-syntax / client-syntax / host-load / client-load / cli-sync / binary）。`test/plugin/smoke.mjs` 只是按
`import.meta.url` 求出仓库根后转发它的薄封装，供习惯在仓库根直接执行的旧脚本与文档使用。

状态含义：`pass` 通过、`pending` 依赖模块尚未实现（不算失败）、`fail` 失败（exit 1）、
`skipped` 因前置失败或 `-Skip*` 未执行、`planned` 仅 -DryRun 打印计划。

## 人工证据产出状态（截至 2026-10-26）

本检出的实际情况：`out/evidence/manual/` **目录不存在**，下表 43 个文件**一个都没有产出**。
判定命令（在仓库根执行，输出 0 即表示一张人工截图都没有）：

```powershell
Test-Path out/evidence/manual
Get-ChildItem -Recurse -File -Filter 'R*.png' | Measure-Object   # Count = 0
```

因此本文档里**每一处** `out/evidence/manual/*.png` 引用都带 ` ⚠ 未产出（待补人工截图）`。保留引用是为了让每条需求
都能追溯到该拍的图，**不代表图已经存在**；`docs/REVIEW-T29` / `docs/POSTMORTEM.md` 里「present=15 / missing=32」的
统计与这个检出不符，请以 `Test-Path` 的实际结果为准。补齐后把该行的 `⚠ 未产出（待补人工截图）` 改成 `已有`，
`tools/e2e.ps1` 的 docs 步会校验每条引用都带这两种标记之一（缺标记即 FAIL）。

**自动证据不能替代人工截图**：`out/evidence/selftest/*.png`、`out/evidence/png/engine/*.png` 证明的是「机制跑通」，
它们看不清位置是否在话筒左侧、提示文案是否可读、编辑器按钮是否被遮挡。下表最后一列只作定位参考。

| 需求 | 文件 | 状态 | 可参考的自动证据（机制性，不等同人工判定） |
| --- | --- | --- | --- |
| R1 | `out/evidence/manual/R1-scissors.png` | ⚠ 未产出（待补人工截图） | — |
| R2 | `out/evidence/manual/R2-overlay.png` | ⚠ 未产出（待补人工截图） | `out/evidence/selftest/a1_screen_highlight.png` |
| R3 | `out/evidence/manual/R3-switch-off.png` | ⚠ 未产出（待补人工截图） | — |
| R4 | `out/evidence/manual/R4-right-click.png` | ⚠ 未产出（待补人工截图） | — |
| R5 | `out/evidence/manual/R5-restored.png` | ⚠ 未产出（待补人工截图） | — |
| R6 | `out/evidence/manual/R6-desktop.png` | ⚠ 未产出（待补人工截图） | `out/evidence/selftest/a1_screen_highlight.png` |
| R6 | `out/evidence/manual/R6-taskbar.png` | ⚠ 未产出（待补人工截图） | `out/evidence/selftest/a1_taskbar_highlight.png` |
| R6 | `out/evidence/manual/R6-tray.png` | ⚠ 未产出（待补人工截图） | — |
| R6 | `out/evidence/manual/R6-window.png` | ⚠ 未产出（待补人工截图） | `out/evidence/selftest/a1_window_highlight.png` |
| R7 | `out/evidence/manual/R7-dual.png` | ⚠ 未产出（待补人工截图） | — |
| R8 | `out/evidence/manual/R8-drag-label.png` | ⚠ 未产出（待补人工截图） | — |
| R8 | `out/evidence/manual/R8-hover-label.png` | ⚠ 未产出（待补人工截图） | — |
| R9 | `out/evidence/manual/R9-dim.png` | ⚠ 未产出（待补人工截图） | `out/evidence/selftest/a1_*`（已暗化，不能证明观感） |
| R10 | `out/evidence/manual/R10-single-click.png` | ⚠ 未产出（待补人工截图） | `out/evidence/selftest/a2_drag_selection.png` |
| R11 | `out/evidence/manual/R11-dragging.png` | ⚠ 未产出（待补人工截图） | `out/evidence/selftest/a2_drag_selection.png` |
| R11 | `out/evidence/manual/R11-result.png` | ⚠ 未产出（待补人工截图） | `out/evidence/selftest/a2_drag_selection.png` |
| R12 | `out/evidence/manual/R12-misclick.png` | ⚠ 未产出（待补人工截图） | — |
| R13 | `out/evidence/manual/R13-topbar.png` | ⚠ 未产出（待补人工截图） | `out/evidence/selftest/a3_a4_topbar.png` |
| R14 | `out/evidence/manual/R14-longshot.png` | ⚠ 未产出（待补人工截图） | `out/evidence/png/engine/engine_longshot_composed.png` |
| R15 | `out/evidence/manual/R15-preview-grow.png` | ⚠ 未产出（待补人工截图） | `out/evidence/selftest/a5_longshot_preview.png` |
| R15 | `out/evidence/manual/R15-preview-start.png` | ⚠ 未产出（待补人工截图） | `out/evidence/selftest/a5_longshot_preview.png` |
| R16 | `out/evidence/manual/R16-longshot-editor.png` | ⚠ 未产出（待补人工截图） | `out/evidence/selftest/a5_longshot_preview.png` |
| R17 | `out/evidence/manual/R17-longshot-exit.png` | ⚠ 未产出（待补人工截图） | — |
| R18 | `out/evidence/manual/R18-editor-longshot.png` | ⚠ 未产出（待补人工截图） | `out/evidence/selftest/a6_editor_toolbar.png` |
| R18 | `out/evidence/manual/R18-editor-normal.png` | ⚠ 未产出（待补人工截图） | `out/evidence/selftest/a6_editor_toolbar.png` |
| R19 | `out/evidence/manual/R19-toolbar-en.png` | ⚠ 未产出（待补人工截图） | `out/evidence/selftest/a6_editor_toolbar.png` |
| R19 | `out/evidence/manual/R19-toolbar-zh.png` | ⚠ 未产出（待补人工截图） | `out/evidence/selftest/a6_editor_toolbar.png` |
| R20 | `out/evidence/manual/R20-saved.png` | ⚠ 未产出（待补人工截图） | — |
| R20 | `out/evidence/manual/R20-tools.png` | ⚠ 未产出（待补人工截图） | `out/evidence/selftest/a6_editor_toolbar.png` |
| R21 | `out/evidence/manual/R21-mosaic-after.png` | ⚠ 未产出（待补人工截图） | `out/evidence/selftest/a6_mosaic_before_after.png` |
| R21 | `out/evidence/manual/R21-mosaic-before.png` | ⚠ 未产出（待补人工截图） | `out/evidence/selftest/a6_mosaic_before_after.png` |
| R22 | `out/evidence/manual/R22-editor-buttons.png` | ⚠ 未产出（待补人工截图） | `out/evidence/selftest/a6_editor_toolbar.png` |
| R23 | `out/evidence/manual/R23-composer.png` | ⚠ 未产出（待补人工截图） | — |
| R23 | `out/evidence/manual/R23-state-cancel.png` | ⚠ 未产出（待补人工截图） | — |
| R24 | `out/evidence/manual/R24-save-dialog.png` | ⚠ 未产出（待补人工截图） | — |
| R25 | `out/evidence/manual/R25-after-restart.png` | ⚠ 未产出（待补人工截图） | — |
| R26 | `out/evidence/manual/R26-crash-log.png` | ⚠ 未产出（待补人工截图） | `out/evidence/crashprobe/crash_probe.json`（JSON 日志轮转证据，不是截图） |
| R27 | `out/evidence/manual/R27-single-instance.png` | ⚠ 未产出（待补人工截图） | — |
| R28 | `out/evidence/manual/R28-en-dark.png` | ⚠ 未产出（待补人工截图） | — |
| R28 | `out/evidence/manual/R28-en-light.png` | ⚠ 未产出（待补人工截图） | `out/evidence/selftest/a3_a4_topbar.png`（浅色顶栏） |
| R28 | `out/evidence/manual/R28-zh-dark.png` | ⚠ 未产出（待补人工截图） | — |
| R28 | `out/evidence/manual/R28-zh-light.png` | ⚠ 未产出（待补人工截图） | `out/evidence/selftest/a3_a4_topbar.png`（浅色顶栏） |
| R29 | `out/evidence/manual/R29-offline.png` | ⚠ 未产出（待补人工截图） | — |

---

## R1 剪刀按钮位于话筒左侧且外观一致

**真实结构（2026-10-26 按安装包渲染器源码核实，取代旧的「槽位回退 + DOM 搬运」描述）**

- 输入框右侧容器 `div.trailing` 内有 `div.standardControls`；它依次渲染 `renderSlot('conversation.input.right')`
  与 `renderSlot('conversation.input.model')`；`standardControls` 的**下一个兄弟节点**才是 `div.activity`（话筒按钮）。
- 本插件注册的是 multi 槽位 `conversation.input.right`（`id: 'shot-action'`，`order: 100`），所以实际顺序是
  「剪刀按钮 → `conversation.input.model` 区（block-picker 等）→ 话筒」：按钮在话筒左侧，也在 block-picker 左侧，
  **并不紧贴话筒**。
- 外观：32×32 透明按钮，圆角 8px，hover 底色取 `--dsw-alias-interactive-bg-hover`，内嵌 18×18 剪刀 SVG；
  `title` / `aria-label` 为「截图」（英文界面「Screenshot」）。

**已知限制（有意取舍，不修）**

- 话筒进入展开态（语音输入中）时，宿主给 `div.trailing` 挂 `hidden: activity`，整块 `div.standardControls` 被隐藏，
  本按钮**随话筒展开一起消失**，退出展开后自动回来。请不要把它当 bug 提：v2.0.0 的教训就是不能再往 single 槽位
  `conversation.input.activity` 里塞第二个注册（那会让整个 DSH 前端启动失败）。
- 因此「按钮永远可见」不成立；验证前必须先确认话筒处于收起态。

**操作**
1. 打开（或刷新）DSH 会话页，看输入框右侧从左到右的顺序：剪刀按钮 → 模型/block-picker → 话筒。
2. 鼠标悬停剪刀按钮读出提示文字；点击一次，确认进入截图模式（屏幕变暗 + 十字光标，细节见 R2）。
3. 与话筒按钮对比：点击区 32×32、圆角 8px、hover 底色一致；把窗口缩到很窄，确认按钮不被挤出（`flex: none`）。
4. 展开话筒（开始语音输入）→ 观察剪刀按钮消失；退出展开 → 确认按钮回来。

**预期**
- 位置：话筒左侧、block-picker 左侧。
- 外观：32×32、圆角 8px、hover 底色与话筒按钮同源变量；提示「截图」/「Screenshot」。
- 话筒展开期间按钮不可见（见「已知限制」），收起后立刻恢复。

**证据**
- 截图：`out/evidence/manual/R1-scissors.png` ⚠ 未产出（待补人工截图）；需要收起态、展开态各一张。
- 机器证据（可复现，但只证明槽位与 order，不证明观感）：`node tools/client-contract.mjs --json out/evidence/ev-contract/client-contract.json`
  → `registrations` 里出现 `conversation.input.right/shot-action@100`，15 项契约 checks 全 PASS。
- `node tools/plugin-smoke.mjs --root . --quiet`：`client-load` 走真实槽位契约门（一键链路第 8 步，见上文）。

## R2 点击剪刀进入原生截图覆盖层

**操作**
1. 记录点击前 DSH 窗口位置与是否可见。
2. 点击剪刀按钮，观察 ≤500 ms 内屏幕变化。

**预期**
- 出现覆盖整个虚拟桌面的原生覆盖层，鼠标变十字，屏幕整体变暗，DSH 窗口（若「隐藏 DSH 窗口」为开）消失。
- 不出现浏览器式的页面跳转、白屏或二次确认对话框。
- 启动管线：宿主 `lib/index.js` 以 `bin/SnipTool.exe --serve --parent <pid> --out <dir> --client` 启动暖进程；每次点击经命名管道 `\\.\pipe\dsh-snip-show` 发送 `show theme=dark lang=zh client=1 out=<dir>` 唤醒；暖进程不在时用同参数加 `--show` 启动一次性会话（`client=1` 表示由 DSH 前端自己粘贴，见 R23）。

**证据**
- 截图：`out/evidence/manual/R2-overlay.png` ⚠ 未产出（待补人工截图）。
- 自动化：`bin/SnipTool.exe --selftest out/evidence/selftest` 产出的 overlay PNG（`out/evidence/selftest/`）。
- 命令：`Get-CimInstance Win32_Process -Filter "Name='SnipTool.exe'" | Select-Object ProcessId,CommandLine`（命令行应含 `--serve --parent ... --out ... --client`，且只有一个热进程）。

## R3 顶部「隐藏 DSH 窗口」开关（默认开、持久化）

**操作**
1. 首次进入覆盖层，观察顶栏开关初始状态。
2. 关闭该开关，右键退出，再进入一次。
3. 完全退出 DSH 并重新启动，再进入覆盖层。

**预期**
- 初始为「开」；关闭后本次覆盖层出现时 DSH 不隐藏，退出后也不恢复。
- 重启 DSH 后仍保持上一次的选择（持久化到设置文件，而非仅内存）。

**证据**
- 截图：`out/evidence/manual/R3-switch-off.png` ⚠ 未产出（待补人工截图）。
- 命令：`Get-Content "$env:LOCALAPPDATA\dsh-screenshot\settings.json"`，确认 `hideDsh`（本次截图是否隐藏 DSH 窗口）与 `longShot`（是否默认开启长截图）两个字段；设置由覆盖层顶栏开关写入，重启 DSH 后仍生效。

## R4 右键退出

**操作**
1. 进入覆盖层后不选区，直接右键。
2. 观察 DSH 是否恢复、是否产生新截图文件。

**预期**
- 覆盖层立即关闭，无截图、无编辑器；「最近一次截图」保持不变；DSH 按 R5 恢复。

**证据**
- 截图：`out/evidence/manual/R4-right-click.png` ⚠ 未产出（待补人工截图）。
- 命令：`Invoke-RestMethod http://127.0.0.1:<DSH端口>/shot/api/last`（返回 `{mtime,bytes,name,data}`，不再返回任何绝对路径），确认 `mtime` 未变。
- 命令：`Get-Content "$env:TEMP\dsh-screenshot-v2\dsh-snip-state.json"`，`result` 应为 `cancel`（取消会话只改状态、不出图）。

## R5 退出后恢复 DSH

**操作**
1. 让「隐藏 DSH 窗口」为开，进入覆盖层后分别用右键、ESC、取消（红色 X）退出。
2. 检查 DSH 窗口位置、尺寸、是否置顶、是否获得焦点。

**预期**
- 三种退出方式都能把 DSH 恢复到进入前的状态（位置/尺寸/层级），并重新获得焦点。

**证据**
- 截图：`out/evidence/manual/R5-restored.png` ⚠ 未产出（待补人工截图）。
- 命令：`Get-Process | Where-Object MainWindowTitle -like '*DSH*' | Select-Object Id,MainWindowTitle`。

## R6 hover 自动识别窗口 / 桌面 / 任务栏

**操作**
1. 缓慢移动鼠标经过：桌面空白处、任意窗口标题栏与内容区、任务栏空白处、开始按钮、托盘图标、另一个窗口再切回。
2. 每次停留 0.5 s 观察高亮框。

**预期**
- 高亮框跟随当前目标：窗口=完整窗口矩形（不含阴影），桌面=该显示器全屏，任务栏=任务栏矩形。
- 切换目标时无闪烁残留，优先级为窗口 > 任务栏 > 显示器。

**证据**
- 截图 4 张：`out/evidence/manual/R6-window.png` / `R6-desktop.png` / `R6-taskbar.png` / `R6-tray.png` ⚠ 未产出（待补人工截图）。
- 自动化：`bin/EngineTests.exe --json out/evidence/engine.json --png out/evidence/png/engine` 中的 HitTest 优先级用例。

## R7 多显示器、每屏 DPI、负坐标

**操作**
1. 接双屏（主屏 + 副屏，DPI 不同），把副屏摆到主屏左侧，使副屏坐标为负。
2. 进入覆盖层，观察覆盖层是否覆盖整个虚拟桌面；分别在两块屏 hover 与拖拽。
3. 在高 DPI 屏上截图后检查尺寸标签与保存像素。

**预期**
- 覆盖层覆盖所有显示器；高亮框与真实窗口像素级对齐；尺寸标签数值 = 实际像素（不是缩放后的逻辑像素）。
- 不出现硬编码分辨率导致的偏移、黑边或内容缩放。

**证据**
- 截图：`out/evidence/manual/R7-dual.png` + 系统显示设置截图 ⚠ 未产出（待补人工截图）。
- 自动化：EngineTests 的多显示器/负坐标用例（`EnumerateMonitors`、`HitTest`）。

## R8 蓝色边框与尺寸标签

**操作**
1. hover 一个窗口；再拖拽框选一个区域。
2. 观察边框粗细/颜色、尺寸标签位置；把选区拖到屏幕右上角，让标签可能溢出。

**预期**
- 边框 2–3 px 蓝色，选区内保持原亮度、外侧变暗（见 R9）。
- 尺寸标签显示 `宽x高`（例如 `888x777`），位于选区上方（或内侧），不遮挡选区内容；靠近屏幕边缘时自动翻转到另一侧，不溢出屏幕。

**证据**
- 截图：`out/evidence/manual/R8-hover-label.png` 与 `R8-drag-label.png` ⚠ 未产出（待补人工截图）。

## R9 选区外暗化

**操作**
1. 观察 hover 与拖拽两种状态下的选区内外亮度。
2. 用图像工具量取选区外与选区内的像素亮度差。

**预期**
- 选区外均匀变暗（约 40%–60% 不透明度），选区内保持原样，边界无渐变带、无接缝。

**证据**
- 截图：`out/evidence/manual/R9-dim.png` ⚠ 未产出（待补人工截图）。
- 自动化：`out/evidence/selftest/` 中的 dim 遮罩 PNG（--selftest 产出）。

## R10 单击确认

**操作**
1. hover 到某个窗口，单击左键（不拖动）。
2. 观察是否直接进入编辑器。

**预期**
- 立即以高亮矩形截图并进入统一编辑器；无二次确认；编辑器内图片尺寸与标签数值一致。

**证据**
- 截图：`out/evidence/manual/R10-single-click.png`（编辑器内图片 + 原标签数值对照） ⚠ 未产出（待补人工截图）。

## R11 拖拽框选

**操作**
1. 按住左键从左上向右下拖出矩形，中途反向拖拽（从右下回到左上）。
2. 松开左键；再把选区拖出屏幕边界。

**预期**
- 拖拽过程实时显示边框与尺寸标签，反向拖拽同样有效；松开即确认并进入编辑器；选区被裁剪到虚拟桌面范围内。

**证据**
- 截图：`out/evidence/manual/R11-dragging.png` + `R11-result.png` ⚠ 未产出（待补人工截图）。

## R12 零面积与误点

**操作**
1. 在覆盖层内点击一次（不移动，产生 0×0）。
2. 拖拽小于 3 px 后松开。
3. 检查是否崩溃、是否产生空图片。

**预期**
- 0 面积不进入编辑器；<3 px 视为误点：停留在覆盖层或安全退出，绝不产生 0 字节/0 像素 PNG，也不弹 CLR 异常框。

**证据**
- 截图：`out/evidence/manual/R12-misclick.png` ⚠ 未产出（待补人工截图）。
- 命令：`Get-Content "$env:TEMP\dsh-snip-error.log" -Tail 20`（文件不存在或没有新行即未崩溃；崩溃日志为无条件追加写入，见 R26）。

## R13 顶栏开关（隐藏 DSH、长截图）

**操作**
1. 观察覆盖层顶栏的开关数量、位置与默认值。
2. 用 Tab 键尝试键盘聚焦，按空格切换。

**预期**
- 顶栏包含「隐藏 DSH 窗口」与「长截图」两个开关；长截图默认关闭；开关可键盘聚焦与切换；位置固定不随目标变化。

**证据**
- 截图：`out/evidence/manual/R13-topbar.png` ⚠ 未产出（待补人工截图）。

## R14 长截图滚轮捕获与回滚

**操作**
1. 打开「长截图」，在内容较长的窗口内拖选区域。
2. 向下滚动滚轮 5–10 次；中途向上滚动一次；继续向下滚到文档底部。

**预期**
- 每次向下滚动追加新内容并无缝拼接，无重复条带、无缺失；向上滚动立即停止捕获并回滚上一帧（内容不重复不缺失）；到达底部自动停止。

**证据**
- 截图：`out/evidence/manual/R14-longshot.png`（最终长图，高度远大于选区） ⚠ 未产出（待补人工截图）。
- 自动化：EngineTests 中 `FindVerticalOverlap` / `Compose` 用例（`out/evidence/engine.json`）。

## R15 长截图等比缩小预览

**操作**
1. 长截图内容从少量增长到一屏以上，观察预览窗口的位置与尺寸。
2. 把选区放到屏幕边缘，确认预览不溢出。

**预期**
- 预览贴在选区旁不遮挡选区；始终按比例缩放（保持纵横比），内容增长时同步变长，最大不超过屏幕可用高度。

**证据**
- 截图 2 张：`out/evidence/manual/R15-preview-start.png`、`R15-preview-grow.png` ⚠ 未产出（待补人工截图）。
- 自动化：EngineTests 中 `PreviewSize` 用例。

## R16 长截图完成后进入同一编辑器

**操作**
1. 长截图捕获若干帧后点击「完成」或按 Enter。
2. 观察进入的编辑器与普通截图是否同一个。

**预期**
- 进入同一个编辑器，画布为拼接后的长图；工具栏与普通截图一致；取消/确定行为按 R22/R24。

**证据**
- 截图：`out/evidence/manual/R16-longshot-editor.png` ⚠ 未产出（待补人工截图）。

## R17 长截图退出后恢复 DSH

**操作**
1. 长截图模式右键退出（再试一次取消按钮）。
2. 检查预览窗口、临时文件、DSH 状态。

**预期**
- 覆盖层与预览全部关闭，DSH 按 R5 恢复；结果目录 `%TEMP%\dsh-screenshot-v2` 只保留最近一次结果与状态文件（`dsh-snip-last.png`、`dsh-snip-state.json`），不产生逐帧临时文件堆积（长截图帧在内存中合成）。

**证据**
- 截图：`out/evidence/manual/R17-longshot-exit.png` ⚠ 未产出（待补人工截图）。
- 命令：`Get-ChildItem "$env:TEMP\dsh-screenshot-v2" | Select-Object Name,Length,LastWriteTime`（只应有上面两个文件）。

## R18 单一编辑器

**操作**
1. 普通截图进入编辑器，记录工具栏顺序、窗口标题、快捷键。
2. 长截图完成后进入编辑器，逐项对比。

**预期**
- 同一套工具栏与同一窗口类（标题/图标一致），工具状态、快捷键、颜色粗细默认值一致。

**证据**
- 截图：`out/evidence/manual/R18-editor-normal.png` 与 `R18-editor-longshot.png` ⚠ 未产出（待补人工截图）。

## R19 图标工具栏与本地化提示

**操作**
1. 依次 hover 每个工具图标 1 s，记录 tooltip 文本。
2. 在 DSH 中切换语言 zh↔en，重新进入编辑器再 hover。

**预期**
- 工具栏只有图标（无文字标签）；tooltip 跟随 DSH 语言切换；图标顺序稳定、无缺图标。

**证据**
- 截图：`out/evidence/manual/R19-toolbar-zh.png` 与 `R19-toolbar-en.png` ⚠ 未产出（待补人工截图）。

## R20 图形 / 箭头 / 画笔 / 文本 + 颜色粗细

**操作**
1. 依次绘制矩形、椭圆、直线、箭头、自由画笔，并插入一段中文文本。
2. 每次切换颜色与线宽；拖动已绘制对象调整位置；把对象拖出画布边缘。

**预期**
- 六种工具都能正确绘制，颜色与粗细立即生效；文本支持中文输入与拖动；超出画布的内容被裁剪；撤销/重绘不产生残影。

**证据**
- 截图：`out/evidence/manual/R20-tools.png` + 保存后的 PNG `R20-saved.png` ⚠ 未产出（待补人工截图）。

## R21 马赛克

**操作**
1. 找到马赛克工具（工具栏中部，位于图形与文本之间）。
2. 在含敏感文字的截图上涂抹；放大到 400% 检查原始像素。
3. 若支持强度/粒度调节，各试一档。

**预期**
- 涂抹区域原始文字不可辨认（放大后只有色块）；可连续涂抹、可调整笔触大小。

**证据**
- 前后对比图：`out/evidence/manual/R21-mosaic-before.png` / `R21-mosaic-after.png` ⚠ 未产出（待补人工截图）。
- 自动化：`out/evidence/selftest/` 中的 mosaic before/after PNG。

## R22 保存 / 取消 / 确定三键

**操作**
1. 观察编辑器右下角按钮组（图标、颜色、顺序、hover 提示）。
2. 分别 hover 三个按钮。

**预期**
- 保存=磁盘图标、取消=红色 X、确定=绿色对勾；顺序与位置固定；hover 提示本地化且与行为一致。

**证据**
- 截图：`out/evidence/manual/R22-editor-buttons.png` ⚠ 未产出（待补人工截图）。

## R23 确定后图片进入输入区且不自动发送

**操作**
1. 编辑截图后点「确定」（绿色对勾）。
2. 观察原生进程行为：DSH 窗口被前置并获得焦点，覆盖层关闭。
3. 观察 DSH 输入区与会话消息列表；不要手动按 `Ctrl+V`，也不要按发送键。
4. 再走一次「取消」（红色 X 或右键），确认不会误插入图片。

**预期**
- 原生进程在 `--client` 模式下只把 DSH 前置、**不再自己合成 `Ctrl+V`**：粘贴由 `lib/client.js` 在 `/shot/api/state` 报告 `result=ok` 后取回 PNG、合成**一次** `paste` 事件完成，因此图片只出现一次。
- 图片以缩略图/附件形式出现在输入区，输入框文本为空、会话中不产生新消息气泡；可以继续输入文字后手动发送。
- 取消时 `result=cancel`，前端不取图、不粘贴，输入区保持不变。

**证据**
- 截图：`out/evidence/manual/R23-composer.png`（输入区恰好一张图、会话无新消息） ⚠ 未产出（待补人工截图）。
- 命令：`Invoke-RestMethod http://127.0.0.1:<DSH端口>/shot/api/state` 返回 `result=ok`；`Invoke-RestMethod http://127.0.0.1:<DSH端口>/shot/api/last` 返回的 base64 PNG 与输入区缩略图一致（同一张图不应出现两次）。
- 命令：`Get-Process SnipTool`（只有一个进程，排除第二个实例造成重复粘贴）。

### 补充：会话状态接口与 busy 解除（GET /shot/api/state）

**操作**
1. 点击剪刀进入覆盖层后直接右键退出（或按 Esc / 红色 X 取消）。
2. 立刻观察剪刀按钮的 busy 态（禁用 + 样式类 `shot-btn is-busy`）。
3. 轮询状态接口：`1..10 | ForEach-Object { Invoke-RestMethod http://127.0.0.1:<DSH端口>/shot/api/state; Start-Sleep -Milliseconds 300 }`。

**预期**
- 接口读宿主 `--out` 目录下的 `dsh-snip-state.json`，返回 `{at,result}`（保存失败时另带 `error`，中英双语提示由前端弹出），`result` 为 `ok`（已出图）或 `cancel`（取消）。为收敛暴露面，接口**不再返回** `file`/`dir` 等绝对路径；真实落盘路径只存在于状态文件里，客户端需要时才从文件读取。
- 结果目录由宿主决定：默认 `%TEMP%\dsh-screenshot-v2`，该路径含非 ASCII 字符时自动退到 `%PUBLIC%\dsh-screenshot-v2`，并通过 `--out` 与管道消息 `out=` 同时告知原生程序——**原生程序把 --out 当权威，实际落盘路径回写状态文件**；两边不一致时接口报 `error`（不静默降级）。
- 取消后 `at` 立即变化、`result=cancel`，前端在下一次轮询（约 0.4 秒后，退避上限 2 秒）解除 busy，不必等到旧的 120 秒超时（安全网约 240 次轮询）。
- 尚无状态文件时接口返回 `at=0`（表示还没有任何一次会话结束），前端继续等待本次会话的 `at` 变化；旧版原生程序（只写 PNG 不写状态）不再被兼容，必须与 v2 原生程序配套。

**证据**
- 截图：`out/evidence/manual/R23-state-cancel.png`（取消后按钮已恢复可点） ⚠ 未产出（待补人工截图）。
- 命令：`Get-Content "$env:TEMP\dsh-screenshot-v2\dsh-snip-state.json"`（`result`、`at` 与接口返回一致）。

## R24 保存 = 落盘，取消 = 丢弃并恢复

**操作**
1. 编辑后点「保存」，在文件对话框选择路径并确认。
2. 再次截图编辑后点「取消」（红色 X）。

**预期**
- 保存：按 PNG 落盘（默认文件名含时间戳），成功后有提示，不进入输入区；取消：丢弃编辑、关闭编辑器、按 R5 恢复 DSH，且不写入任何文件。

**证据**
- 截图：`out/evidence/manual/R24-save-dialog.png` ⚠ 未产出（待补人工截图）。
- 命令：`Get-ChildItem <保存目录> -Filter *.png | Sort-Object LastWriteTime -Descending | Select-Object -First 3`（取消后文件数不变）。

## R25 可安装为桌面 profile 插件

**操作**
1. 构建并打包：`pwsh -NoProfile -File build.ps1 -Tests`，然后 `pnpm pack`。
2. 先看计划：`pwsh -NoProfile -File install.ps1 -WhatIf`。
3. 在一个测试 profile（`-ProfileDir out/install-selftest/profile`）或真实 desktop profile 上实跑安装。
4. 完全重启 DSH，确认剪刀按钮出现、截图功能可用。

**预期**
- `-WhatIf` 只打印计划：`备份` → `pnpm add file:<tgz>` → `dsh.profile.bundles` → 「需重启 DSH 生效」，且不写任何文件、不重启 DSH。
- 实跑生成 `<profile>/.backup-install-<stamp>/`（含 `package.json`、`cordis.patch.yml`、`manifest.json`、`pnpm-add.log`），profile `dependencies` 增加 `file:<tgz>`，`dsh.profile.bundles` 追加 `dsh-screenshot` 且其它 bundle 名称与顺序完全不变。

**证据**
- 命令：`pwsh -NoProfile -File tools/e2e.ps1`（install-plan 步骤必须 PASS）。
- 备份目录 `manifest.json` 的 `bundlesBefore` 与安装后 `dsh.profile.bundles` 的前缀一致。
- 截图：`out/evidence/manual/R25-after-restart.png` ⚠ 未产出（待补人工截图）。

## R26 .NET Framework 4.8 + csc，无 CLR 崩溃弹窗并有崩溃日志

**操作**
1. 查看 `bin/SnipTool.exe` 的目标运行时：`[System.Reflection.AssemblyName]::GetAssemblyName('bin/SnipTool.exe').Version` 与 `bin\SnipTool.exe.config`。
2. 不制造真实崩溃，直接跑崩溃日志探针：`bin/SnipTool.exe --crash-probe out/evidence/crashprobe`。
3. 读 `out/evidence/crashprobe/crash_probe.json` 的 `ok`/`beforeBytes`/`afterBytes`，并 `Get-Content "$env:TEMP\dsh-snip-error.log" -Tail 10` 找探针 marker。
4. 再制造一次失败（例如临时把 `--out` 设成不可写目录，或注入一个已知异常分支），确认仍不弹 .NET 崩溃对话框。

**预期**
- 目标框架为 .NET Framework 4.8，系统自带即可运行，不依赖额外运行时或 NuGet 包。
- 未处理异常一律追加写入 `%TEMP%\dsh-snip-error.log`：`LogCrash` 不再受 `DSH_SNIP_DEBUG` 门控（只有详细跟踪日志 `%TEMP%\dsh-text.log` 才需要该变量）。
- 探针**不制造真实崩溃**：它直接调用 `LogCrash` 写一条带 marker 的记录（设计意图是不触发 WER/CLR 崩溃对话框，也能稳定断言「日志是追加写的」）。
- 断言：`--crash-probe` exit 0、`crash_probe.json` 的 `ok == true`、`afterBytes > beforeBytes`、marker 在日志尾部；`tools/e2e.ps1` 的 crash-probe 步骤会重复这些断言。
- 崩溃时同样不出现 Windows 错误报告/CLR 对话框，进程以非 0 退出码结束；随后再次点剪刀能正常启动。

**证据**
- 命令：`bin/SnipTool.exe --crash-probe out/evidence/crashprobe`（exit 0）与 `out/evidence/crashprobe/crash_probe.json`。
- 命令：`tools/e2e.ps1` 的 crash-probe 步骤 PASS，详情含 `%TEMP%\dsh-snip-error.log <before> -> <after> bytes`。
- 命令输出：运行时版本、`Get-Content "$env:TEMP\dsh-snip-error.log" -Tail 20`（含异常栈或探针 marker）。
- 截图：`out/evidence/manual/R26-crash-log.png` ⚠ 未产出（待补人工截图）。

## R27 单实例与热进程

**操作**
1. 连续快速点击剪刀 3 次，每次截图后退出。
2. 打开任务管理器查看 `SnipTool.exe` 数量；记录首次与后续的响应时间。

**预期**
- 始终只有一个 `SnipTool.exe` 常驻（`--serve` 热进程，命令行形如 `SnipTool.exe --serve --parent <pid> --out <dir> --client`），后续截图由命名管道 `\\.\pipe\dsh-snip-show` 唤醒（消息形如 `show theme=dark lang=zh client=1 out=<dir>`）并复用同一进程（后续明显快于首次）；父进程退出或空闲 180 秒后热进程自行退出，进程被结束后下次点击会自动重建。

**证据**
- 命令：`Get-Process SnipTool -ErrorAction SilentlyContinue | Select-Object Id,StartTime`。
- 命令：`Get-CimInstance Win32_Process -Filter "Name='SnipTool.exe'" | Select-Object ProcessId,CommandLine`（核对 `--serve --parent ... --out ... --client`）。
- 截图：`out/evidence/manual/R27-single-instance.png` ⚠ 未产出（待补人工截图）。

## R28 语言与明暗主题跟随 DSH

**操作**
1. 在 DSH 中切换 zh↔en；再切换浅色↔深色主题。
2. 每次进入覆盖层与编辑器，观察文字、tooltip、背景、边框。

**预期**
- 覆盖层与编辑器的文案、tooltip 跟随 DSH 语言；深色主题下背景/文字对比度足够、选区边框仍清晰；浅色主题下暗化遮罩仍可分辨。

**证据**
- 截图 4 张：`out/evidence/manual/R28-zh-light.png` / `R28-zh-dark.png` / `R28-en-light.png` / `R28-en-dark.png` ⚠ 未产出（待补人工截图）。

## R29 全本地、无外部网络

**操作**
1. 截图功能运行中，用资源监视器或 `Get-NetTCPConnection` 观察 `SnipTool.exe` 的连接。
2. 断网（禁用网卡）后重复一次 R2–R11 的关键步骤。

**预期**
- 不存在任何外部网络连接（仅本机 `127.0.0.1` 与 DSH 通信）；断网情况下全部功能可用（本插件不做云上传、OCR、录屏）。

**证据**
- 命令：`Get-NetTCPConnection -OwningProcess (Get-Process SnipTool).Id | Select-Object RemoteAddress,RemotePort,State`（RemoteAddress 只有 127.0.0.1）。
- 截图：`out/evidence/manual/R29-offline.png` ⚠ 未产出（待补人工截图）。

## R30 可复现的证据链

**操作**
1. 在干净检出上执行 `pwsh -NoProfile -File tools/e2e.ps1 -DryRun`（应 exit 0）。
2. 执行 `pwsh -NoProfile -File tools/e2e.ps1`（完整链路）。
3. 检查 `out/evidence/report.json`、`out/evidence/SUMMARY.md` 与各步骤日志。
4. 若第 8 步只报告 sha256 漂移的 WARN：记下 WARN 里的当前 sha 与基线 sha，确认这批字节已复审，
   再执行 `pwsh -NoProfile -File tools/e2e.ps1 -AcceptClientSha`（或
   `node tools/client-contract.mjs --update-baseline --reason "..."`）把基线更新到当前字节；重跑
   链路后 WARN 应消失，`tools/fixtures/client-baseline.json` 里出现新的 sha256、reason 与 updatedAt。

**预期**
- 链路依次执行 preflight/wiring → build -Tests → EngineTests → `SnipTool.exe --selftest` → `SnipTool.exe --longshot-probe` → `SnipTool.exe --longshot-probe <dir> wheelOnly=false`（负控）→ `SnipTool.exe --crash-probe` → 真实槽位契约门（`tools/client-contract.mjs`，第 8 步）→ 插件冒烟 → `install.ps1 -WhatIf` → `npm pack`（校验 tgz 文件白名单）→ 文档检查，共 12 步，并写出 report.json 与 SUMMARY.md。
- 全部通过 exit 0（期望 12/12 步 PASS）；任一 fail exit 非 0；尚未实现的模块记 `pending` 且不中断（`-Strict` 下 pending 视为失败）。
- **第 8 步（client-contract）的判定：契约是硬门，sha256 不是。** 该步用真实 Cordis 语义跑 15 项检查——未声明 `exports.inject` 就读 `ctx.slots` 必须抛 `cannot get property "slots" without inject`；`slots.inject(key, callback)` 的回调必须是函数、返回值即 disposer（否则 `callback is not a function`）；single slot 同优先级重复注册抛 `single slot "conversation.input.activity" already has a registration at priority 0`；multi slot 可共存；`slots.register({name}, Component)` 的 `name` 必须等于注入键。当前 `lib/client.js` 必须 15/15 通过，且打包的 2.0.0 旧 bundle 必须被拒并给出 missing-inject / non-function-callback / single-slot-conflict 三类错误；任一条不满足即 fail（`-AcceptClientSha` 也无法把它变绿）。
- **sha256 漂移只 WARN**：`tools/fixtures/client-baseline.json` 记录的是「这批字节被复审过」。当前 `lib/client.js` 与它不同时，第 8 步仍 PASS、链路仍 exit 0，该步 `warnings[]` 会写明当前 sha、基线 sha、基线文件名与接受命令。基线只能由 `-AcceptClientSha` 或 `node tools/client-contract.mjs --update-baseline --reason "..."` 显式写入；后者在契约检查失败时拒绝写（exit 1）、缺 `--reason` 时 exit 2，普通运行绝不改写基线。（历史：sha 曾作为硬失败，t28 拆分 client 的合法改动静被读成回归，因此降级为 WARN。）
- **判定入口只有 `out/evidence/report.json`**：看 `ok`/`status`/`counts.fail`，不要去 grep 控制台文本——负控子进程的 FAIL 字样可能异步漏进父进程控制台，那是预期输出。
- selftest 步不只看 PNG：必须解析同目录 `summary.json`，逐条 `status` 都是 `passed`，且 **13 条 criteria 全部在场**：A1–A8、`A9/R26`、`N1`、`N2`、`N2b`、`N3`。少一条即 fail（套件缩水不能被读成「全部通过」）；`attested` 仅在非核心项上可接受，核心 A1–A6 必须是探针真实断言。
- longshot-probe 步读 `longshot_probe.json`，除 `ok==true`、`frames>=2`、`composedHeight > selHeight` 外还要求：`fallbackUsed` 字段**存在且不为 true**（缺字段即 fail——reviewer 曾证明探针只靠 `ScrollBy` 兜底也能 PASS，pixelHash 逐字节相同）、`realPath==true`、`n1RegressionOk==true`、`hookUnhooked==true`、`exportedHeight >= composedHeight`。开关尚未实现时显式记 `skipped` 并写明「不声称通过」，因为该项曾出现过只裁回一屏的致命缺陷。
- longshot-negative 步是**负控**：以 `wheelOnly=false` 关掉滚轮转发后，探针必须**非零退出**且 JSON 为 `ok=false`。它退出 0、或退出非零却写 `ok=true`，都判 fail——说明探针分不清「真滚动捕获」和「兜底」。
- `--selftest` 至少产出 8 张可人工判读的 PNG（窗口/任务栏/屏幕高亮、拖拽选区、顶栏、长截图预览、编辑器工具栏、马赛克前后），见 `out/evidence/selftest/`。
- `tools/plugin-smoke.mjs` 是插件冒烟的唯一实现（含 cli-sync：`lib/index.js` 传给原生程序的每个开关都必须被 `Program.Main` 解析）；`test/plugin/smoke.mjs` 只是按 `import.meta.url` 求根后转发它。

**证据**
- `out/evidence/report.json`（schema `dsh-screenshot-evidence/v2`，含每步 status/exitCode/artifacts/warnings）、`out/evidence/SUMMARY.md`、`out/evidence/logs/*.log`、`out/evidence/selftest/*.png` 与 `out/evidence/selftest/summary.json`、`out/evidence/longshot/longshot_probe.json`（正控）、`out/evidence/longshot-negative/longshot_probe.json`（负控）、`out/evidence/crashprobe/crash_probe.json`、`out/evidence/ev-contract/client-contract.json`（第 8 步原始判定，含 `baseline`、`drift`、`checks`、`negative`）、`dsh-screenshot-<version>.tgz`。

## 记录模板

每条验证完成后在下面表格追加一行（可复制到交付 PR 描述）：

```markdown
| 需求 | 结论 | 证据路径 | 备注 |
| --- | --- | --- | --- |
| R1 | 通过 | out/evidence/manual/R1-scissors.png | ⚠ 未产出（待补人工截图） |
| R2 | 通过 | out/evidence/manual/R2-overlay.png | ⚠ 未产出（待补人工截图）；首次点击 180ms |
```

## 常见坑（troubleshooting）

- **`error CS0016` / `cannot replace bin\SnipTool.exe`**：刚退出的 `SnipTool.exe`（暖进程、`--selftest`、`--longshot-probe`）或杀软扫描会短暂占用映像文件。`build.ps1` 自 t19 起先编译到临时文件，再带重试（10 × 400ms）替换目标；若仍报 `cannot replace ... locked by a running process`，说明确实有实例在跑：`taskkill /IM SnipTool.exe /F` 后重跑即可，不要怀疑源码。
- **同一条 e2e 命令手跑绿、脚本里跑红**：先看失败步是 `build` 还是 `engine`。前者见上一条（文件被占用），后者是 B8 探针竞态（已在 t19 用 `[STAThread]` + 自枚举自检 + 有界轮询修掉）。报告里 `[FAIL]` 的 `detail` 字段会给出 `direct` 枚举数、轮询轮数、helper 是否退出，不要只看 exit code。
- **严格 JSON 解析器报错**：t19 起所有机器可读 JSON（`out/engine.json`、`summary.json`、`longshot_probe.json`、`crash_probe.json`）统一 UTF-8 **无 BOM**；若你在旧产物上看到 `EF BB BF`，重跑该步骤生成新文件。
- **不要重启 DSH 来"修"构建**：本仓库的验证链路完全离屏（`--selftest`、`--longshot-probe` 不依赖桌面交互），重启宿主只会让会话丢失，对构建无帮助。
