# dsh-screenshot 维护手册（交接版）

> **基线**：v2.1.6 · 2026-10-31 · 仓库 <https://github.com/liu19666/dsh-screenshot> · 本机仓库 `F:\Workspace\测试\dsh-screenshot-v2`
> **读者**：接手维护的 AI 助手。读完这份文档，你应当能独立完成：读懂架构 → 改功能 → 编译 → 打包 → 装机 → 发版 → 回滚 → 排障。
> **本文件自身也要维护**：每次发版更新顶部基线、CHANGELOG 对应小节和附录 A 的哈希。

---

## 0. 30 秒读懂

**它是什么**：DeepSeekRuntime（DSH）桌面端的截图插件。在会话输入框右侧加一个剪刀按钮，也支持 `F9`/`F10` 全局快捷键，唤起 Windows 原生全屏覆盖层：自动识别光标下的窗口 / 桌面 / 任务栏并高亮，选中后可以画矩形、椭圆、直线、箭头、画笔、文本、马赛克，最后**确定＝把 PNG 放进会话输入区（不自动发送）**、**复制＝只进剪贴板**、**保存＝存到你选的路径然后退出**。

**为什么必须有原生进程**：浏览器 API 拿不到 HWND、不能枚举其它应用的窗口、不能铺一层覆盖整个桌面的透明窗体、也不能按窗口抓图。所以这是一个「Node 宿主 + 浏览器前端 + C# 原生 exe」的三段式插件。

**装在哪**：`C:\Users\Administrator\.dsh\profiles\desktop`（DSH profile）的 `node_modules/dsh-screenshot`，并在该 profile 的 `package.json` 里以 `dsh.profile.bundles` 登记名字 `dsh-screenshot`。

**最重要的三条**：

1. **绝对不要重启用户的 DSH**（会杀掉他正在用的会话）。Host / 前端改动必须由**用户自己重启**才生效；**原生 exe 改动不需要重启**（每次截图按内容哈希取新副本运行）。
2. **不要让 `SnipTool.exe` 从 `node_modules` 里运行**（详见 §1.4，会把插件市场安装搞成 EPERM 并整单回滚）。
3. **用户讨厌为了跑测试而拖时间**。默认只做「编译 + 哈希核对 + 一次真机点击」；跑 `tools/e2e.ps1` 全套要用户明确要求。

---

## 1. 架构与进程模型

### 1.1 三个半边

| 半边 | 源文件 | 跑在哪里 | 职责 |
| --- | --- | --- | --- |
| 宿主（host） | `lib/index.js`（约 534 行） | DSH 主进程（Node） | 注册 `/shot/api/*` 路由；按需启动 / 唤醒 / 收尾原生进程；读 `dsh-snip-state.json`；把 PNG 以 base64 交给前端 |
| 前端（web） | `lib/client.js`（约 594 行） | DSH 的 Web GUI（浏览器） | 剪刀按钮、`F9`/`F10` 快捷键、轮询会话状态、把图片注入输入区、toast 提示 |
| 原生（native） | `src/SnipTool.cs`（约 4232 行） | 独立进程 `SnipTool.exe` | 全屏覆盖层、窗口/屏幕/任务栏命中测试、标注、马赛克、导出 PNG、写会话状态 |

辅助代码：`src/Detect.cs`（命中测试与几何，517 行）、`src/EngineTests.cs`（纯算法单测，无 UI）、`src/SelfTest.cs`（UI 自检，产出 PNG 证据）。

### 1.2 一次截图的完整时间线

1. 用户点剪刀（左键＝不隐藏 DSH，右键＝隐藏 DSH），或按 `F9`（不隐藏）/ `F10`（隐藏）→ `client.js` 的 `runCapture(hide, setBusy)`。
2. `POST /shot/api/capture {theme, lang, hide}`。
3. host `triggerSnip()`（lib/index.js:419）：
   - `resolveHelper()` 解析出真正的 exe（`%LOCALAPPDATA%\dsh-screenshot\<id8>\SnipTool.exe`）；
   - 先试 `wakeWarm()`（命名管道）4 次 × 90ms，命中「余温」进程就秒开；
   - 没命中 → `killWedgedTool()` 清掉卡死的旧进程 → `spawn(--serve --show --parent <pid> --out <dir> --client --hide|--no-hide …)` → `watchLinger(baseMtime)`。
4. 原生侧：`Program.Main`（src/SnipTool.cs:71）解析参数，`--serve` 时进服务循环（:155-200），收到唤醒行 → `RunSession(hide)`（:204）→ `new SnipForm(hide)`。
5. 用户在覆盖层里选区域 / 标注 / 点工具栏。
6. 收尾时原生写 `<结果目录>\dsh-snip-state.json`：`{"at": <ms>, "result": "ok|copy|cancel|error", "file": "<绝对路径>", "error": "…"}`。
7. 前端 `pollSession()` 轮询 `GET /shot/api/state`，`at` 一变就判定「本次会话结束」。
8. `result === "ok"` → `GET /shot/api/last`（PNG → base64）→ `injectImageIntoComposer()` 塞进输入区；`copy` → 弹「已复制到剪贴板」；`cancel` → 静默结束；`error` → 弹错误。
9. host 的 `watchLinger()` 每秒看一次 state 文件的 mtime；本次会话结束后 `HELPER_LINGER_MS`（30 秒）到点就 `killHelper()`；另有 `HELPER_MAX_SESSION_MS`（15 分钟）硬上限兜底。

### 1.3 进程模型（用户最敏感的地方）

- **平时 0 个 `SnipTool.exe`**。点截图才起，会话结束 30 秒后自杀。
- 相关常量在 `lib/index.js:29-31`：`HELPER_LINGER_MS = 30000`、`LINGER_POLL_MS = 1000`、`HELPER_MAX_SESSION_MS = 15 * 60 * 1000`。
- 历史沿革（别重犯）：v2.1.0–2.1.2 曾经「加载即常驻 + 45 秒保活」，用户强烈反弹；v2.1.3 改成「一次一进程、截完即退」，但每次截图要冷启动；v2.1.4 起改为「按需启动 + 结束后 30 秒余温」，这是用户选定的折中。
- 想调这个窗口：只改常量即可（不必动 C#），但要清楚**任何超过 30 秒的驻留都可能被用户当成"后台偷偷跑东西"**。

### 1.4 为什么 exe 要复制到 `%LOCALAPPDATA%`（重要，别改回去）

2026-10-26 的事故：用户从插件市场安装别的插件，pnpm 报 **EPERM** 并整单回滚，结果「什么都没装进去」。根因是运行中的 `SnipTool.exe` 正从 `node_modules\dsh-screenshot\bin\` 执行，Windows 会锁住正在运行的镜像文件，pnpm 重新导入这个包时替换不了它。

现行方案（lib/index.js:32-86）：

- `bin/SnipTool.exe` 只当**源文件**；
- `resolveHelper()` 读它 → `sha256` 前 8 位 → `%LOCALAPPDATA%\dsh-screenshot\<id8>\SnipTool.exe`；
- 目标已存在且大小相同 → 直接复用；否则写 `.tmp` 再 `rename`；
- 成功后 `pruneHelperCopies()` 清掉其它 id 目录（正在运行的那份删不掉，忽略即可）；
- 任何一步失败都回退到打包内的路径（保证极端情况下仍能用）。

**好处**：升级插件时不会锁文件；换 exe 不用重启 DSH（下一次截图自然取到新哈希副本）。

---

## 2. 契约（改代码前必须保住的东西）

### 2.1 命令行 / 管道协议

**serve 形式**（host 现在用的唯一形式）：

```
SnipTool.exe --serve --show --parent <dsh-pid> --out <ascii-dir> --client [--hide|--no-hide] [--dark|--light] [--lang zh|en]
```

**唤醒行**（命名管道 `\\.\pipe\dsh-snip-show`，**必须是纯 ASCII**）：

```
show theme=dark|light lang=zh|en hide=1|0 client=1 out=<ascii-dir>
```

原生侧回一行 `ok`。协议细节写在 `lib/index.js` 文件头（:1-13）和 `Program.Main` 的参数解析里（src/SnipTool.cs:121-147）。

**一次性形式**：不带 `--serve` 时，Main 直接 `Application.Run(new SnipForm(hide))`，窗口关闭即进程退出。当前 host 不用它，但保留着——如果要彻底干掉常驻进程，这是现成的落点。

**一条必须保住的规则：一次点击 = 一个覆盖层。**
2026-10-31 修过的真实 bug：一次点击可能排队多条唤醒行（host 唤醒重试 / 第二个进程来唤醒已在运行的进程），serve 循环「一行唤醒＝一次会话」，于是用户关掉第一个覆盖层后队列里那条立刻又弹一个——表现是「点复制/保存后，截图界面又自己重新打开了一遍」。
修法：`static volatile bool SessionRunning` + `DrainPending()`（`RequestEvent.Reset(); PendingRequest = null;`）；管道线程写 ack 之后判断 `if (!SessionRunning) { PendingRequest = line; RequestEvent.Set(); }`，会话结束（`finally`）时 `SessionRunning = false; DrainPending();`。
**动 serve 循环 / 唤醒逻辑时，这条必须原样保住**，否则老 bug 立刻回归。

### 2.2 会话状态文件（唯一的会话结果通道）

`<结果目录>\dsh-snip-state.json`，原生每次会话结束重写：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `at` | number | 会话结束时间（Unix ms）。**必须严格递增**，前端靠它判断「这是新的一次会话」 |
| `result` | string | `ok` / `copy` / `cancel` / `error` |
| `file` | string | 实际写出的 PNG 绝对路径（`ok` 时必须有；host 以它为准，不从自己的 `--out` 猜） |
| `error` | string | `error` 时的失败文本，前端原样展示 |

写它的函数是 `Program.WriteState(result, error)`（src/SnipTool.cs:257）；`OnFormClosed`（:1295）在 `!confirmed` 时补写 `cancel`。

**坑（踩过）**：任何「先 Close() 再想写别的结果」的路径，都必须**先**把 `confirmed = true` 设好，否则 `OnFormClosed` 会用 `cancel` 覆盖掉你刚写的 `ok`/`copy`。`CopyOnlyAndClose()`（:2422）里就是这么处理的。

### 2.3 结果目录：必须纯 ASCII

`%TEMP%\dsh-screenshot-v2`（lib/index.js:91-98；非 ASCII 时回退 `%PUBLIC%\dsh-screenshot-v2`）。
原因：唤醒行是 ASCII 文本，非 ASCII 路径没法在协议里一致地传递。若两半边的目录不一致，`resultPathFromState()` 会直接报
`result directory mismatch: the native side wrote to … but the host reads …` —— 这是**故意的**，别改成"猜一个文件名糊过去"。

### 2.4 HTTP 路由（host 半边）

| 路由 | 方法 | 用途 | 备注 |
| --- | --- | --- | --- |
| `/shot/api/capture` | POST | 发起一次截图 | body `{theme, lang, hide}` |
| `/shot/api/snip` | POST | 同上（旧客户端的别名） | 别删，兼容用 |
| `/shot/api/state` | GET | 当前会话结果 | 前端每秒轮询 |
| `/shot/api/last` | GET | 本次 PNG（base64） | 上限 `MAX_IMAGE_BYTES` = 32 MiB |
| `/shot/api/lang` | GET | 宿主语言 | 读 profile 区域设置 |
| `/shot/api/version` | GET | 版本号 | **发版必须同步改这里**（lib/index.js:519） |
| `/shot/api/probe` | POST | 调试探针：把请求体写到 `%TEMP%\dsh-shot-probe.json` | **默认禁用**，只有 `%TEMP%\dsh-shot-debug.on` 存在时才启用 |

**路由陷阱**：DSH 的 `webServer` 在同一进程里对「精确路由」只允许注册一次。插件被**加载两遍**（两个副本 / 热更新两代共存 / bundles 重复登记）就会抛
`Error: webserver: duplicate exact route "/shot/api/capture"`，整个插件激活失败（web boot 里显示 `1 entry did not activate`）。
看到这个报错**先查重复安装**（`npm ls dsh-screenshot` / profile 里有没有两个副本），不要急着改代码。同理，其它插件（例如 wallpaper-engine）报同名错误也是它们自己的重复挂载问题。

### 2.5 前端槽位（Cordis slots）

```js
exports.inject = ['slots']
slots.inject('conversation.input.right', function () {
  return slots.register({ name: 'conversation.input.right', id: 'shot-action', order: 100 }, ShotActionFallback)
})
```

必须遵守的四条（违反任何一条都会让整个 client 入口激活失败）：

1. `exports.inject = ['slots']` 不能省。未声明的服务读取会抛 `cannot get property "slots" without inject`。
2. `slots.inject(key, cb)` 是 **effect API**：第二个参数必须是**函数**，且要 `return` 出 `slots.register(...)` 产生的 disposer。传一个对象会抛 `callback is not a function`。
3. `register(options, Component)` 的 `options.name` 必须**等于**注入的槽键。
4. **不要碰 `conversation.input.activity`**：那是**单值槽**，话筒按钮已经占了唯一名额，再注册会抛 `single slot "conversation.input.activity" already has a registration at priority 0`；用更低优先级注册会**遮住话筒**。本插件只用多值槽 `conversation.input.right`。

这套规则有机器可读的实现：`tools/client-contract.mjs`（对真实 Cordis 语义建模，自带 5 个合成自检 + 一个「必须失败」的旧 bundle 负控夹具 `tools/fixtures/client-470abc0e.js`）。**改 `lib/client.js` 必须先跑它**：

```bash
node tools/client-contract.mjs --json out/ev-contract/client-contract.json
```

### 2.6 四种收尾语义

| result | 含义 | 前端行为 | 原生入口 |
| --- | --- | --- | --- |
| `ok` | 确认截图，PNG 已写到结果目录 | 取图 → 注入输入区（**不自动发送**） | 绿勾 / 回车 |
| `copy` | 只复制到剪贴板，不写磁盘 | toast「已复制到剪贴板」，不注入 | 工具栏「复制」 |
| `cancel` | 放弃 | 静默结束，无提示 | Esc / 右键 / 红叉 / **保存成功后** |
| `error` | 原生侧失败 | 弹出错误文本 | 写盘失败等 |

---

## 3. 代码地图

> 行号会随改动漂移，**按函数名/注释搜索**更可靠。

| 文件 | 行数 | 职责 | 关键锚点 |
| --- | --- | --- | --- |
| `src/SnipTool.cs` | 4232 | 原生 main + 覆盖层窗体 + 工具栏 + 导出 | 见 §3.1 |
| `src/Detect.cs` | 517 | 窗口 / 屏幕 / 任务栏命中测试，DPI 处理 | `SetProcessDPIAware` :73 / :146 |
| `src/EngineTests.cs` | 746 | 纯算法单测，输出 JSON + PNG | `--json <file> --png <dir>` |
| `src/SelfTest.cs` | 656 | UI 自检（覆盖层 / 编辑器截图证据） | `SnipTool.exe --selftest <dir>` |
| `lib/index.js` | 534 | 宿主：路由、进程管理、linger | §3.2 |
| `lib/client.js` | 594 | 前端：按钮、快捷键、轮询、注入 | §3.3 |
| `build.ps1` | — | csc 编译（含输出锁重试） | `-Tests` 同时编测试器 |
| `install.ps1` | — | 装进 profile（备份 / pnpm add / 登记 bundle / `-Rollback`） | 只改 profile 三处 |
| `tools/e2e.ps1` | 1374 | 12 步证据链 | 见 §6 |
| `tools/accept.ps1` | 359 | 版本化验收门（字节不变校验） | `-NoBuild -SkipPack` |
| `tools/plugin-smoke.mjs` | 510 | 两半边 stub 加载 | client-load 必须同时过契约门 |
| `tools/client-contract.mjs` | 977 | Cordis slots 契约模型 + 负控 | §2.5 |
| `docs/SPEC.md` | — | 需求 R1–R30（**已取消长截图**，对应 R 条目有注记） | 改动前先读 |
| `docs/VERIFY.md` | — | 逐条需求的验证方法 + 人工证据状态 | 很长，按 R 编号查 |
| `docs/RELEASE.md` | — | 发版清单 | 发版前对照 |
| `docs/ACCEPTANCE.md` | — | 历次验收记录（含事故史，**不要抹掉**） | |
| `docs/POSTMORTEM.md` | — | 事故复盘与门禁由来 | **接手必读第 3 节** |
| `docs/INTERFACES.md` | — | 文件所有权 / 证据协议 | |

### 3.1 原生侧关键点（按功能）

- **参数解析**：`Program.Main` src/SnipTool.cs:71，参数表 :121-147；证据模式强制安静（`SuppressDialogs` :83-84）。
- **单实例**：`new Mutex(true, @"Local\dsh-screenshot-snip")` :101。非首个实例会找已有「截图」窗口并 `SetForegroundWindow`；找不到就 `WakeWarmOwner()`（:362，管道 400ms + 等 ack 600ms）。
- **serve 循环 / 会话**：:155-200、`RunSession` :204、`SessionRunning` + `DrainPending()`（§2.1）。
- **状态写入**：`Program.WriteState` :257；`StatePath` :251。
- **覆盖层窗体**：`class SnipForm : Form` :440；`OnLoad` 里按 `hide` 最小化 DSH 并记住 `dshWasZoomed`。
- **工具栏**：`BuildToolBar` :663-673（11 个按钮：矩形/椭圆/直线/箭头/画笔/文本｜马赛克｜复制/保存/取消/确定）。`ToolBarStrip.Add(name, tip, click, icons)` 会在第 7/8 项后自动插分隔线——**增删按钮会改变分组位置**，注意图标坐标与悬停提示。
- **绘制**：自定义 GDI 双缓冲（`BitBlt` :2636 起），DPI 相关 :2668-2672。
- **导出**：`RenderResult()` 合成标注 → `CopyAndClose()`（:2406，绿勾/回车）、`CopyOnlyAndClose()`（:2422）、`SaveToFile()`（:1235）。
- **恢复 DSH**：`RestoreDsh()`（:622）用 `IsZoomed`（:16）判断原本是否最大化，只恢复一次（`dshRestored`）。**别写死 `SW_RESTORE`**：对已最大化的窗口调用它会把窗口变回普通尺寸（2.1.1 修过的 bug）。

### 3.2 宿主侧关键点（lib/index.js）

| 位置 | 内容 |
| --- | --- |
| :24-31 | 路径与 linger 常量 |
| :32-86 | `HELPER_ROOT` / `helperTarget` / `pruneHelperCopies` / `resolveHelper` |
| :88-98 | 结果目录（ASCII 约束）、`RESULT_NAME`、`STATE_NAME`、体积上限 |
| :143-177 | `readStateFile` / `stateMtime` / `resultPathFromState` |
| :193-199 | `spawnArgs`（serve 形式） |
| :207-244 | `wakeWarm(theme, lang, hide)`（管道写唤醒行，等 `ok`） |
| :246-290 | `killWedgedTool` / `stopLinger` / `killHelper` / `watchLinger` |
| :312-417 | CORS、JSON 读写、`route()` 注册器 |
| :419-466 | `triggerSnip()` |
| :468-533 | 路由表（§2.4） |

### 3.3 前端关键点（lib/client.js）

| 位置 | 内容 |
| --- | --- |
| :8-62 | 语言/主题探测（`serviceLocale` 用 try/catch 包住，`locale` 是可选的） |
| :64-94 | `showError` / `showNote`（1.6 秒 toast） |
| :96-119 | `ScissorsIcon()`（SVG，22 单位网格） |
| :228-265 | `findComposer` / `injectImageIntoComposer`（**DSH 改版最容易坏的地方**） |
| :283-347 | `pollSession`（轮询 + 结果分派） |
| :349-404 | `runCapture(hide, setBusy)`（按钮与快捷键共用） |
| :406-417 | `bindShortcuts()`（F9/F10，捕获阶段，忽略修饰键） |
| :419-495 | `ShotButton()`（左键 hide=false / 右键 hide=true，`contextmenu` 里 `preventDefault`） |
| :497-555 | `injectStyles()`（样式 id `dsh-screenshot-v2-style`） |
| :561-591 | `exports.inject` / `exports.apply`（槽注册） |

---

## 4. 构建与运行环境

### 4.1 工具链事实

| 项 | 值 |
| --- | --- |
| 编译器 | `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`（**只能是 C# 5**） |
| 目标 | `/target:winexe`、`/platform:anycpu`、`/optimize+`，引用 System / System.Drawing / System.Windows.Forms / System.Core |
| 脚本 | PowerShell **7**（`pwsh`）；`install.ps1` 有 `#Requires -Version 7.0` |
| 打包 | `pnpm pack --pack-destination dist`（产物名 `dsh-screenshot-<version>.tgz`） |
| 发布 | `gh` CLI，账号 `liu19666`（scopes: repo / workflow / gist / read:org） |
| 运行时 | Node ≥ 20（`package.json` 的 engines），Windows 10/11 x64 |

**C# 5 红线**：不能用字符串插值 `$"…"`、空条件运算符 `?.`、`nameof`、表达式体成员（`=>`）、`out var`、元组、`using static`、默认接口实现等。写 `String.Format(...)` 或 `+` 拼接。

**必须用 `pwsh -File build.ps1` 编译**。从 bash/git-bash 直接调 `csc.exe` 会被 MSYS 的路径与参数转换破坏（`/r:...` 会被改写成 `C:/...`）。

### 4.2 编译

```powershell
cd F:\Workspace\测试\dsh-screenshot-v2
pwsh -NoProfile -File build.ps1          # 只编 bin/SnipTool.exe
pwsh -NoProfile -File build.ps1 -Tests   # 再编 bin/EngineTests.exe
```

`build.ps1` 会先编译到临时文件再换名，并对「旧进程/杀毒软件短暂锁住输出文件」做重试（`CS0016`）。所以**不要**手动 `csc` 覆盖 `bin/SnipTool.exe`。

### 4.3 装机

```powershell
pnpm pack --pack-destination dist
pwsh -NoProfile -Command "Stop-Process -Name SnipTool -Force -ErrorAction SilentlyContinue"
pwsh -NoProfile -File install.ps1 -Force -ProfileDir "C:/Users/Administrator/.dsh/profiles/desktop" -Tgz "F:/Workspace/测试/dsh-screenshot-v2/dist/dsh-screenshot-<ver>.tgz"
```

安装脚本**只改 profile 的三处**：备份 `.backup-install-<stamp>`、`pnpm add file:<tgz>`、在 `dsh.profile.bundles` 末尾追加 `dsh-screenshot`（已存在则不动）。它**从不**重启 DSH、从不改别的插件的 bundles。

回滚：`pwsh -File install.ps1 -Rollback -ProfileDir <profile>`（恢复最新备份）。

### 4.4 什么时候需要重启 DSH

| 改了什么 | 何时生效 |
| --- | --- |
| `src/*.cs` → `bin/SnipTool.exe` | **不用重启**。每次截图 `resolveHelper()` 按内容哈希取新副本（前提是已装机） |
| `lib/index.js`（host） | 需要重启 DSH（host 在 DSH 主进程里加载） |
| `lib/client.js`（web） | 需要重启 DSH 或至少刷新页面（客户端入口在 web boot 时加载） |
| `package.json` / `cordis.patch.yml` | 需要重启 DSH |
| 只改文档 / README | 不需要 |

---

## 5. 标准作业流程（SOP）

### SOP-1 发一个补丁版（最常用）

1. 改代码（先读 `docs/SPEC.md` 对应条目，别破坏 R 约束）。
2. 改原生则编译：`pwsh -NoProfile -File build.ps1 -Tests`。
3. 版本号三处 + 变更记录：
   - `package.json:3`
   - `lib/index.js` 的 `route('version', …)`（约 :519）
   - `README.md` / `README.en.md` 的 `version-<x.y.z>-blue` 徽章
   - `CHANGELOG.md` 顶部新增小节（英文，说明「改了什么 / 为什么 / 影响面」）
4. `pnpm pack --pack-destination dist`。
5. 杀残留 helper（否则安装时可能撞锁）：`Stop-Process -Name SnipTool -Force`。
6. `install.ps1 -Force -ProfileDir … -Tgz …`。
7. **核对三份哈希**（仓库 vs 已装副本，必须逐字节一致）：`bin/SnipTool.exe`、`lib/index.js`、`lib/client.js`；再确认安装副本 `package.json` 的 version。
8. `git add -A` → `git commit -m "…"` → `git push origin main` → `git tag -a vX.Y.Z` → `git push origin vX.Y.Z` → `gh release create vX.Y.Z dist/dsh-screenshot-X.Y.Z.tgz --title … --notes …`。
9. 告诉用户：改的是哪一半、**要不要重启**、验证方式一句话。

> 网络提示：到 github.com 的链路经常抖（`RPC failed` / `curl 52 empty reply`）。用 `timeout 45 git push origin main` 重试即可；SSH 22 端口在本机被封，只能用 https。

### SOP-2 只改原生（exe）

编译 → 打包 → 杀进程 → 装机 → 核对 exe 哈希 → 版本 +1 → 提交/发版。**不用让用户重启**。
注意：如果 CHANGELOG / Release 说明里写了哈希，记得同步真实值（`sha256sum bin/SnipTool.exe`）。

### SOP-3 只改宿主（host）

改 `lib/index.js` → 打包装机 → 核对哈希 → **必须让用户重启 DSH** 才生效。语法自检：`node --input-type=module --check < lib/index.js`。

### SOP-4 只改前端（web）

改 `lib/client.js` → **先跑契约门禁** `node tools/client-contract.mjs --json out/x.json`（必须全 PASS，且负控必须 FAIL）→ 打包装机 → 核对哈希 → 让用户重启或刷新页面。

### SOP-5 回滚

- 装机回滚：`pwsh -File install.ps1 -Rollback -ProfileDir <profile>`（用最新 `.backup-install-*`）。
- 代码回滚：`git revert <sha>` 或 `git checkout <tag> -- <file>`，然后按 SOP-1 重新发一版（**不要**改历史 tag）。

### SOP-6 更新社区市场条目

- 目录源仓库：`awesome-dsh-plugin/awesome-dsh-plugin`，条目文件 `data/plugins/liu19666__dsh-screenshot.yml`。
- 现在条目里的 `tarball:` 钉在 `…/releases/download/v2.1.4/dsh-screenshot-2.1.4.tgz` —— **每次发版应改指最新 Release 附件**（改完提 PR，一 PR ≤3 条）。
- 客户端可见有延迟：市场目录来自 npm 包 `dsh-plugin-catalog`（版本号即缓存键），每天 UTC ~04:30 重新发一次包，合并后**次日**才在 App 里看到。
- 上架要求（已满足，供核对）：`package.json` 有 `dsh.bundle` + 根 `cordis.patch.yml`、仓库 topic `dsh-plugin`、仓库创建满 1 天、描述与代码一致。

### SOP-7 重拍 README 截图

脚本在 `out/shots/`（不入库）：`samplewin.ps1`（自建 WinForms 示例窗口）+ `shoot12.ps1`（最小化浏览器与 DSH → 隐藏桌面图标 → 起示例窗口置顶 → 起已装 exe 截图 → 截 `hover8.png` / `editor10.png` → 恢复现场）。
产物：`docs/screenshots/overview-zh.png`（1920×1080 实拍）与 `docs/screenshots/toolbar.png`（裁剪 + 2 倍放大）。
踩过的坑：① 脚本里有中文必须存成 **UTF-8 with BOM**（PowerShell 5.1 否则按 ANSI 读成乱码）；② 不要用 `notepad.exe`（商店应用拿不到 MainWindowHandle）；③ 枚举窗口别用 `FindWindow($null, …)`；④ 抬 Z 序用 `SetWindowPos(HWND_TOPMOST)`，别指望后台进程 `SetForegroundWindow`；⑤ `Start-Process powershell.exe` 不加 `-WindowStyle Hidden` 会留黑窗入镜；⑥ 文本用 `Label` 不要 `TextBox`（会被选中变蓝）；⑦ 桌面图标显隐用 `WM_COMMAND 0x7402` 发给 `SHELLDLL_DefView`，务必 `try/finally` 恢复。
**注意**：`package.json` 的 `files` 里有 `"!docs/screenshots/"`，图片不进包（否则 tgz 从 210KB 涨到 1.6MB）。别删这行。

### SOP-8 用户报 bug 时的标准动作

1. **先只读取证**：`GET /shot/api/version`、`Get-CimInstance Win32_Process -Filter "Name='SnipTool.exe'"`、`%TEMP%\dsh-screenshot-v2\dsh-snip-state.json` 的 mtime 与内容、浏览器控制台报错。**不要先改代码**。
2. 复现要贴近真实链路：真实鼠标/键盘事件、真实进程启动。**不要**用 `PostMessage` 直接把消息塞进窗体——历史教训：`SelfTest` 曾直接把 `WM_MOUSEWHEEL` PostMessage 给 helper 窗体，绕过了整条输入链路，导致长截图的 bug 一直"绿灯"（详见 `docs/POSTMORTEM.md`）。
3. 修完只做最小核对（编译 + 哈希 + 一次真机点击），除非用户要求跑全套。
4. 汇报时明确写出「我验证了什么 / 没验证什么」，不要把"编译通过"说成"功能可用"。

---

## 6. 验证体系

| 工具 | 覆盖 | 命令 | 备注 |
| --- | --- | --- | --- |
| `build.ps1 -Tests` | 编译两个 exe | 见 §4.2 | 必须 pwsh |
| `bin/EngineTests.exe` | 命中测试 / 几何算法（无 UI） | `bin/EngineTests.exe --json out/engine.json --png out/engine-png` | 纯算法，快 |
| `SnipTool.exe --selftest <dir>` | 覆盖层 / 编辑器渲染证据 | `bin/SnipTool.exe --selftest out/self` | 产出 PNG + `summary.json` |
| `tools/client-contract.mjs` | Cordis slots 契约（含负控） | 见 §2.5 | **硬门禁** |
| `tools/plugin-smoke.mjs` | 两半边 stub 加载 | `node tools/plugin-smoke.mjs --json out/smoke.json` | client-load 复用契约门结果 |
| `tools/e2e.ps1` | 12 步证据链（preflight→build→engine→selftest→…→package→docs） | `pwsh -NoProfile -File tools/e2e.ps1 -OutDir out/evidence` | 慢；`-DryRun` 只列计划 |
| `tools/accept.ps1` | 版本化验收门 + 字节不变校验 | `pwsh -NoProfile -File tools/accept.ps1 -NoBuild -SkipPack` | 会校验 `bin/*.exe`、`dist/*.tgz` 前后哈希 |

**可信证据原则**（血泪）：

- 只信 **JSON 产物**（`report.json`、`summary.json`、`client-contract.json`），不信控制台文本——负控子进程会故意把自己的 FAIL 行打到控制台。
- 每个门禁都要有**负控**：故意喂一个坏输入，必须 FAIL。只跑正控等于没跑。
- 断言要读**产物**而不是脚本自己的结论字段；脚本里 `exit 0` 不等于功能对（曾出现 PowerShell 吞参数导致负控假绿）。
- 用户视角的验收永远是最后一步：真机点一次。

---

## 7. 已知问题与遗留风险（接手时心里要有数）

| 编号 | 问题 | 影响 | 建议动作 |
| --- | --- | --- | --- |
| K-1 | 会话结束后 helper 存活 30 秒（`HELPER_LINGER_MS`） | 用户曾因"后台进程"强烈不满 | 别擅自加长；要改先问用户 |
| K-2 | 父进程看门狗只在 serve 循环里（`ParentAlive`） | DSH 若在截图过程中崩溃，覆盖层可能留在屏幕上 | 用户仍可右键退出；要彻底解决需在 SnipForm 里加独立看门狗线程 |
| K-3 | 单实例 mutex + "唤醒已有窗口" | 第二个实例的行为依赖时序（会把已有覆盖层提到前台） | 改动唤醒逻辑时要一起回归 |
| K-4 | 保存成功即退出（2.1.6 起） | 想"另存为后继续编辑"的用户会觉得状态丢了 | 若收到此类反馈，可加"保存后保持打开"的偏好开关 |
| K-5 | 剪贴板重试 5×80ms | 剪贴板被远程桌面/其它程序长时间占用时仍可能失败（会弹框且不关窗） | 需要的话提高重试次数或改用延迟重试 |
| K-6 | GDI `CopyFromScreen` 抓屏 | DRM 保护内容 / 硬件叠加层（部分视频、游戏）可能截成黑屏 | 无法用纯 GDI 解决；需换 Windows.Graphics.Capture（新依赖，慎重） |
| K-7 | `SetProcessDPIAware()`（系统级 DPI 感知，非 per-monitor v2） | 多屏混合缩放时坐标/尺寸可能偏 | 改这块要真机多屏验证（R7） |
| K-8 | `/shot/api/probe` 是任意内容写盘原语 | 安全面 | 默认已关（需 `%TEMP%\dsh-shot-debug.on`），**别在生产打开** |
| K-9 | 市场条目 `tarball:` 仍钉 v2.1.4 | 市场用户装到旧版 | 每次发版提 PR 更新（SOP-6） |
| K-10 | `publish.ps1` 里的仓库描述/topics 是 v1 时代文案（WeChat/QQ 风格） | 与实际不符，误用会改坏仓库描述 | 用 `gh repo edit` 或先改脚本 |
| K-11 | 仓库根有两只历史 tgz（被 `.gitignore` 的 `*.tgz` 忽略）、嵌套空目录 `dsh-screenshot-v2/out/` | 只是杂物 | 可以删，别误删 `dist/` 里最新的包 |
| K-12 | 没有 CI（GitHub Actions 未配置） | 回归全靠本地脚本 | 若要加 CI，注意 windows runner + csc 路径（`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe` 在 windows-latest 上存在） |
| K-13 | 插件被安装两份会 `duplicate exact route` | 整个插件不激活，页面无按钮 | 先查重复安装，再查代码 |
| K-14 | 每次截图冷启动约 0.3–0.5 秒（首次） | 用户已知并接受 | 想更快只能靠 linger，别再加常驻 |

---

## 8. 排障手册

| 症状 | 先看什么 | 处置 |
| --- | --- | --- |
| 输入区没有剪刀按钮 | `GET /shot/api/version` 是否 200；浏览器控制台有没有 `web boot: 1 entry did not activate`；插件是否在 `dsh.profile.bundles` | 版本路由 404 → 插件没装/没登记；激活失败 → 看报错（§2.4 / §2.5） |
| 点按钮没反应 | `Get-CimInstance Win32_Process -Filter "Name='SnipTool.exe'"`；state 文件 mtime | 没进程 → host 报错（看 DSH 日志）；有进程无覆盖层 → 可能卡死，杀进程重试 |
| 覆盖层弹出两次 | 是否回退了 `SessionRunning`/`DrainPending`（§2.1） | 恢复该逻辑 |
| 截图后 DSH 窗口变小/位置变了 | `RestoreDsh()` 是否仍用 `IsZoomed` 决定 `SW_SHOWMAXIMIZED`/`SW_RESTORE`；是否只恢复一次 | 恢复原逻辑（2.1.1 修过） |
| 图片没进输入区 | `findComposer()` 的选择器是否随 DSH 改版失效；`/shot/api/last` 是否返回 data | 更新选择器；这通常是 DSH 升级后的第一处破裂点 |
| 截图全黑 | 是否 DRM/硬件叠加层内容 | 告知限制（K-6） |
| 点「复制」没反应 | 剪贴板是否被占用；toast 有没有出现；state 是否写成 `copy` | 失败会弹框且不关窗；重复失败提高重试 |
| 保存后界面不退出 | 是否 2.1.6+；`SaveToFile()` 成功分支是否 `Close()` | 已修（2.1.6） |
| 市场装其它插件 EPERM | `SnipTool.exe` 的 `CommandLine` 是否指向 `node_modules` | 不应该（§1.4）；若出现说明 `resolveHelper()` 回退了，查 `%LOCALAPPDATA%` 权限 |
| `duplicate exact route` | 是否装了两份 / 热更新两代共存 | 卸载重复副本、重启 |
| `screenshot is larger than 33554432 bytes` | `MAX_IMAGE_BYTES`（32 MiB） | 正常限制；极端大图可调 |

---

## 9. 红线（Do NOT）

1. **不重启、不 kill 用户的 DSH 进程**（除非用户明确要求）。
2. **不改用户 profile 里其它插件的依赖或 bundles 顺序**（install.ps1 已经保证只追加自己）。
3. **不让 exe 从 `node_modules` 运行**（§1.4）。
4. **不碰 `conversation.input.activity` 单值槽**（§2.5）。
5. **不在生产打开 `/shot/api/probe`**。
6. **不写死分辨率**（需求明确要求 1920×1080 只是示例）。
7. **不自动发送消息**：确定后只填入输入区。
8. **不删 `package.json` 里 `"!docs/screenshots/"`**（否则包体积暴涨）。
9. **不把"编译通过/自测通过"当成"功能可用"**（§6 可信证据原则）。
10. **改完必须核对已装副本与仓库哈希一致**，再告诉用户"好了"。

---

## 10. 交接清单（第一次上手做这 6 件事）

1. 读 `docs/SPEC.md`（需求）、`docs/POSTMORTEM.md` 第 3 节（必守门禁）、`docs/VERIFY.md` 的 R 列表（怎么验）。
2. 跑一次 `pwsh -NoProfile -File build.ps1 -Tests`，确认工具链可用（约 10–30 秒）。
3. 跑一次 `node tools/client-contract.mjs`，确认前端契约门禁是绿的（几十秒）。
4. 打开 `http://127.0.0.1:<当前端口>/shot/api/version`（端口每次启动都变，看运行时上下文），确认返回当前版本。
5. 装一次最新 tgz（先杀 helper），核对三份哈希。
6. 把当前版本号与哈希记进附录 A（每次发版都更新）。

---

## 附录 A 基线哈希（v2.1.6，2026-10-31）

| 产物 | 大小 | sha256 |
| --- | --- | --- |
| `bin/SnipTool.exe` | 115712 B | `d3ed7ace1a852a1162d40b6ef4898f9a36b06021e896dd6d84a0fbba4a660ee0` |
| `lib/client.js` | 21475 B | `e79165879d222dbdfb2fa5d80b2f1aafa911c21f8673e25e5133b2a1677a39d5` |
| `lib/index.js` | 21229 B | `097cc1099b8104ac97764164967b8cbb122f09a5329478f02f5dc6160a345ddb` |
| `dist/dsh-screenshot-2.1.6.tgz` | 210572 B | `7c79ee9d50014a1701ef41f167da9646c351aa2c1c3ba8205e743cdb1221b774` |

（包内 20 个条目；`docs/screenshots/` 已被排除。）

## 附录 B 命令速查

```powershell
# 编译
pwsh -NoProfile -File build.ps1 -Tests

# 打包
pnpm pack --pack-destination dist

# 装机（先杀 helper）
pwsh -NoProfile -Command "Stop-Process -Name SnipTool -Force -ErrorAction SilentlyContinue"
pwsh -NoProfile -File install.ps1 -Force -ProfileDir "C:/Users/Administrator/.dsh/profiles/desktop" -Tgz "F:/Workspace/测试/dsh-screenshot-v2/dist/dsh-screenshot-2.1.6.tgz"

# 回滚
pwsh -NoProfile -File install.ps1 -Rollback -ProfileDir "C:/Users/Administrator/.dsh/profiles/desktop"

# 核对哈希（仓库 vs 已装）
sha256sum bin/SnipTool.exe lib/index.js lib/client.js
cd "/c/Users/Administrator/.dsh/profiles/desktop/node_modules/dsh-screenshot" && sha256sum bin/SnipTool.exe lib/index.js lib/client.js

# 契约门禁
node tools/client-contract.mjs --json out/ev-contract/client-contract.json

# 证据链（慢，按需）
pwsh -NoProfile -File tools/e2e.ps1 -OutDir out/evidence
pwsh -NoProfile -File tools/accept.ps1 -NoBuild -SkipPack

# 运行时探测（端口每次启动都变）
curl -s http://127.0.0.1:<port>/shot/api/version
Get-CimInstance Win32_Process -Filter "Name='SnipTool.exe'" | Select ProcessId,CreationDate,CommandLine

# 发版
git add -A; git commit -m "feat(x.y.z): ..."; timeout 45 git push origin main
git tag -a vX.Y.Z -m "vX.Y.Z: ..."; timeout 45 git push origin vX.Y.Z
gh release create vX.Y.Z dist/dsh-screenshot-X.Y.Z.tgz --title "..." --notes "..."
```
