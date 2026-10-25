# 模块边界、所有权与验证协议

## 目录与所有权（并行开发，禁止越界修改）

| 路径 | 所有者 | 内容 |
| --- | --- | --- |
| `src/SnipTool.cs` | overlay-dev | 覆盖层、选区、顶部开关栏、编辑器、工具栏、IPC、CLI、暖进程 |
| `src/SelfTest.cs` | overlay-dev | 无头证据模式（--selftest / --auto / --detect） |
| `src/Detect.cs` | engine-dev | 目标识别（窗口/屏幕/任务栏）、多显示器与 DPI |
| `src/LongShot.cs` | engine-dev | 长截图拼接数学 + 预览尺寸 |
| `src/EngineTests.cs` | engine-dev | `bin/EngineTests.exe` 入口（JSON + PNG 证据） |
| `lib/client.js`, `lib/index.js`, `package.json`, `cordis.patch.yml`, `README*.md` | plugin-dev | DSH 插件两半：话筒左侧按钮、host 路由、图片入输入区、打包元数据 |
| `build.ps1` | captain | 构建脚本（已就绪，勿改签名；需要改动先找 captain） |
| `tools/`, `install.ps1`, `docs/VERIFY.md` | harness-dev | 证据采集、安装脚本、验证手册 |
| `docs/SPEC.md`, `docs/INTERFACES.md` | captain | 需求与契约（只读，成员不要改） |

## 模块契约（overlay 调用引擎）

`Detect`（`src/Detect.cs`）：

- `List<WindowInfo> EnumerateWindows(int excludePid)` — Z 序，front-most first，`ZOrder` 从 0 开始（0 = 最前）。
  - 必须过滤：本进程窗口、`!IsWindowVisible`、宽或高 <= 0、`IsIconic`（最小化）、cloaked UWP（`DWMWA_CLOAKED != 0`）、`WS_EX_TOOLWINDOW`。
  - 必须排除 shell 类窗口，交给任务栏/屏幕分支处理：`Shell_TrayWnd`、`Shell_SecondaryTrayWnd`（任务栏）、`Progman`、`WorkerW`（桌面）。
- `List<MonitorInfo> EnumerateMonitors()` — `Screen.AllScreens`，含 Bounds 与 WorkArea、Primary 标记；坐标必须是真实物理像素，**不得硬编码 1920x1080**。
- `TargetHit HitTest(Point pt, int excludePid)` — 判定顺序：任务栏 > 窗口（Z 序第一个命中）> 所在屏幕。任务栏优先是刻意的：任务栏恒为 topmost，且窗口列表已排除它，这样命中语义唯一。
  - `TargetHit.Label` 语义（供 UI 显示目标名，**尺寸标签由 overlay 自己用 Rect 渲染**）：窗口 = 标题（空则类名）；任务栏 = 本地化「任务栏」/`Taskbar`；屏幕 = 「屏幕 N」/`Display N`。
- `TargetRect TaskbarBounds(TargetRect monitorBounds)` — 自动隐藏（`ABM_GETSTATE` 的 `ABS_AUTOHIDE`）或该屏无任务栏时返回空矩形（`W`/`H` 为 0）。

`LongShot`（`src/LongShot.cs`）：

- `int FindVerticalOverlap(Bitmap prev, Bitmap next, int minOverlap, int maxOverlap)` — 无可靠重叠返回 -1。
- `Bitmap Compose(IList<Bitmap> frames, IList<int> offsets, int width, int height)`。
- `Size PreviewSize(int contentW, int contentH, int maxW, int maxH)` — 等比缩到框内。

签名变更必须先在 team 里广播（captain + overlay-dev），不得单方面改。

## 构建与运行

- 构建：`pwsh -File build.ps1 -Tests`（工作目录 = 仓库根）。产出 `bin/SnipTool.exe`、`bin/EngineTests.exe`。
- 源码必须是 **C# 5** 语法（net48 自带 csc 默认语言版本）：不要用 `$""`、`?.`、`nameof`、表达式体成员、`out var`。
- 依赖：只用 `System.*` / `System.Drawing` / `System.Windows.Forms` / `Microsoft.Win32`；禁止 NuGet。
- 运行：`bin/SnipTool.exe`（覆盖层）、`bin/SnipTool.exe --serve --parent <pid>`（暖进程）。
- 引擎自测：`bin/EngineTests.exe --json <file> --png <dir>`，退出码 0 = 全通过。

## 证据协议（R30）

每个实现任务完成时，必须提交**可复现**的证据，写进 `docs/VERIFY.md` 或在 task output 里给出命令 + 结果：

1. 构建通过：`pwsh -File build.ps1 -Tests`，exit 0。
2. 引擎：`bin/EngineTests.exe --json out/engine.json --png out/`，exit 0，JSON 里每项 check 通过。
3. 覆盖层 UI：`bin/SnipTool.exe --selftest out/` 生成 PNG（候选高亮、暗化、尺寸标签、顶部开关栏、长截图预览、编辑器工具栏、马赛克前后），截图必须肉眼可判读。
4. 插件：`node --check lib/*.js` 或等价语法检查；`package.json` 字段与 `cordis.patch.yml` 与 v1.0.5 一致且可安装。
5. 图片入输入区链路：给出 host 路由 → client 插入的代码位置与手工验证步骤（不自动发送）。

## 环境事实

- 仓库：`F:\Workspace\测试\dsh-screenshot-v2`（git 仓库，基线 = v1.0.5 HEAD）。
- csc：`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`（Roslyn 4.8，C# 5 默认）。
- dotnet SDK 8.0.426 / WindowsDesktop 8.0.32 也在，但**不要**改成 net8（会增加运行时依赖）。
- DSH 安装目录：`C:\Users\Administrator\AppData\Local\Programs\DeepSeekRuntime\resources\app\dsh`（注意目录名里有空格）。
- DSH profile：`C:\Users\Administrator\.dsh\profiles\desktop`（`package.json` + `cordis.patch.yml` + pnpm workspace）。
- Web GUI：`http://127.0.0.1:62916`（当前会话所在实例，**不要**重启它）。
- 参考实现（v1.0.5 原仓库，只读）：`F:\Workspace\测试\dsh-screenshot-recovered`（`git show HEAD:<path>`）。

## 纪律

- 只改自己名下的文件；跨文件改动先在 team 消息里说明。
- 不执行 `git commit`/`git push`（captain 统一提交）；不重启 DSH 桌面进程。
- 不删除 `bin/SnipTool.exe` 之外的任何交付文件；不写仓库外的路径（除 `out/`、`%TEMP%`）。
- 每个任务完成时用 `agent_teams_update_task` 提交：status=completed、changedPaths、acceptanceResults、commandsRun。

## 集成注意项（captain 记录，t5 必须逐条处理）

1. **两个冒烟脚本重复**：`tools/plugin-smoke.mjs`（harness-dev，支持 `--root`/`--json`，e2e 第 5 步用它）与 `test/plugin/smoke.mjs`（plugin-dev，桩加载 5 条路由）。t5 需收敛为唯一入口，或在 `docs/VERIFY.md` 写清各自职责。
2. **`test/plugin/smoke.mjs` 依赖 cwd**：它按 `dsh-screenshot-v2/lib/index.js` 相对当前目录解析，在仓库根跑会 `ERR_MODULE_NOT_FOUND`，在 workspace 根跑才 exit 0。t5 必须改成基于 `import.meta.url` 解析仓库根，任何 cwd 下都能跑。
3. **README 配图**：`docs/screenshots/*.png` 是 v1.0.5 旧图，v2 已加顶部开关栏与底部马赛克/三键工具栏。t5 用 `out/selftest` 新图替换，或在图下标注示意图。
4. **隐藏逻辑归属**：隐藏 DSH 由原生按 `%LOCALAPPDATA%\dsh-screenshot\settings.json` 决定，插件不得再传 `hide`；t5 复核 `lib/index.js` 参数与 `Program.Main` 参数表一致。
5. **Web GUI 端口已变**：当前实例是 `http://127.0.0.1:64265`（旧文档写的 62916 已失效）；任何成员都不要重启 DSH。
