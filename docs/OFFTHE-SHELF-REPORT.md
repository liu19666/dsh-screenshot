# 成熟现成方案调研报告（截图标注 + 长截图）

> 目的：用户 m02082 要求「先找最成熟的现成方案，比照现状，给建议和报告」。本文件只做调研与对比，**不改任何代码**。
> 调研时间：2026-10-25/26 ｜ 执行：captain ｜ 仓库状态：`9e65313`（长截图已回退旧行为）

---

## 一、结论先行

1. **不存在「可直接装、可直接调用」的成熟库**。NuGet 上滚动截图相关包只有 `Lyo.Screenshot 3.0.0`（总下载 44 次），不具备工程价值；GitHub 上没有 Windows + C# + 可嵌入的滚动截图库。
2. **成熟方案都是完整应用**，共三个开源实现：
   - `ShareX/ShareX`（★40410，**GPL-3.0**，C#，Windows）：功能最全，但 GPL 传染 —— **代码不能拷进我们的插件**（我们的包是自有许可）。
   - `1003129155/jietuba`（★531，**MIT**，C++ Qt6 + Rust，Windows x64/ARM64）：**与我们需求重合度最高**，长截图内核 4 个 Rust 文件 + 3 个 C++ 文件，MIT 允许移植。
   - `netcrawlerr/CapScroll`（★33，MIT，C#/.NET 10 + Avalonia）：**仅 Linux**，拼接器只有 8.9 KB，算法简单，参考价值 > 使用价值。
3. **建议路线：把 jietuba 的 MIT 长截图内核（变更驱动抓帧 + 双哈希行指纹 + 候选打分 + 双向增量会话）移植成我们的 C#**，预计 700–1000 行、集中在 `src/LongShot.cs` 与覆盖层抓帧逻辑，不动编辑器与插件外壳。
4. **编辑/标注侧不需要换**。现成成熟方案（`nhn/tui.image-editor` ★7672 MIT、Fabric.js MIT、Pintura 商业）**全是 Web canvas**，而我们的原生编辑器已按 R18–R24 验收通过（形状/箭头/画笔/文本/颜色粗细/马赛克/保存/取消/确定），换掉等于重做输入与 DPI 集成，收益为零。

---

## 二、现成方案清单（实测数据）

| 项目 | 星 | 许可 | 语言/平台 | 长截图 | 标注 | 能否直接用于我们 |
|---|---|---|---|---|---|---|
| [ShareX](https://github.com/ShareX/ShareX) | 40410 | **GPL-3.0** | C# / Windows | ✅ `ScrollingCaptureManager.cs`(14.1 KB)+`ScrollingCaptureService.cs`(1.8 KB)+`ScrollingCaptureOptions.cs` | ✅ 全套 | ❌ 许可传染，只能读设计不能拷代码 |
| [jietuba](https://github.com/1003129155/jietuba) | 531 | **MIT** | C++ Qt6 + Rust / Windows x64+ARM64 | ✅ 内核 `rust_libs/longstitch/`（`stitch.rs` 19.9 KB、`session.rs` 63.3 KB、`hash.rs` 7.5 KB、`lcs.rs` 7.4 KB）+ `cpp/src/stitch/`（`auto_scroll.cpp` 4.1 KB、`change_watch.h` 2.6 KB、`incremental.h` 5.6 KB、`scroll_window.h` 10.6 KB） | ✅ | ⚠️ 是完整 GUI 应用（release-2.1.9，lite 17 MB / pp 48 MB），**无长截图 CLI**；但 MIT → **算法可移植** |
| [CapScroll](https://github.com/netcrawlerr/CapScroll) | 33 | MIT | C# .NET10 + Avalonia / **Linux only** | ⚠️ `Stitching/Stitcher.cs` 8.9 KB，重叠搜索较朴素 | ✅ 基础 | ❌ 平台不符，算法弱于 jietuba |
| [tui.image-editor](https://github.com/nhn/tui.image-editor) | 7672 | MIT | JS / Canvas | ❌ | ✅ 形状/线条/箭头/文字/图标/滤镜（含像素化、模糊） | ⚠️ Web 侧可用，但我们的原生编辑器已验收 |
| [LongPortraitScreenshot](https://github.com/abiemann/LongPortraitScreenshot) | 1 | MIT | C# / Windows | ⚠️ 极简 | ❌ | ❌ 玩具级 |
| [screenStitch](https://github.com/jaflo/screenStitch) | 13 | MIT | Python | ⚠️ 只有拼接算法 | ❌ | ❌ 仅算法参考 |

---

## 三、最成熟方案的内核（jietuba 源码实测）

> 全部结论均来自读源码，不是猜的。文件路径已标注，可复核。

### 1. 抓帧：**变更驱动 + 静默等待**，不依赖滚轮事件
`cpp/src/stitch/change_watch.h`（原文注释）：
> 后台线程每隔 IDLE_MS 抓一次区域做比较，检测到变化就切到 ACTIVE_MS，静默 ACTIVE_HOLD_MS 后回 idle；**它只判断画面有没有动，帧仍由窗口自己抓**。慢机器自然看得更少，不会堆积。

`cpp/src/stitch/scroll_window.h`（原文注释）：
> 一个**点击穿透**的框标记捕获区域。**只要区域画面变了就抓**（滚轮、拖滚动条、拖内容、键盘翻页），**先等画面稳定**再抓，避免抓到动画中间态；自动滚动是可选的。

→ 这一条直接解释我们为什么卡在第 1 帧：**我们靠"整块像素完全一致"（`ImagesIdentical`，只采样 5 行 × ~16 列）来放行抓帧，画面里任何一点动画都会让这个门永远关死**；jietuba 反过来用「变了就抓、稳定才定稿」。

### 2. 拼接：**增量会话 + 每行两种哈希 + 候选打分 + 双向生长**
`rust_libs/longstitch/src/session.rs` 文件头（原文要点翻译）：
- 逐帧推入，会话内只保留**拼接结果的像素 + 逐行哈希**；每帧只算新帧的行哈希，已拼好的长图不再编解码。
- 会话记着**最新一帧在结果里的位置**，下一帧先在它附近找 —— **回滚到哪都能定位**。
- 帧落在已拼内容之内 → **只更新位置**；伸出结果开头或末尾 → **在那一头接上，两个方向都能长**。
- 帧正好停在结果一头时，那一头对不上的行**换成这一帧的**（停下后才加载出来的内容）。
- 每行算**两种哈希**：先按逐像素指纹找位置，找不到再按平均色哈希找。
- **位置要有能单独定位的行支撑；只零星对上一小段时视为不重叠，不硬接**。
- 都找不到、或找到位置但整帧比对不上时，在上一帧附近按像素相近再找（`locate_similar`）。
- 输入输出用 BGRA（Windows 截屏原生布局）。

`rust_libs/longstitch/src/stitch.rs`：`stitch_two_images_smart` / `..._smart_auto`（多候选纠错、**自动检测正/反向滚动**）、`select_best_candidate` 按 `overlap_ratio = overlap_length / min(len1,len2)` 与「结果高度是否收缩」打分。

### 3. 自动滚动：**先判系统路由，再注入滚轮**
`cpp/src/stitch/auto_scroll.cpp`：
```cpp
constexpr UINT SPI_GETMOUSEWHEELROUTING_VALUE = 0x201C;
constexpr UINT MOUSEWHEEL_ROUTING_MOUSE_HOVER_VALUE = 2;
bool wheel_follows_focus() { ... SystemParametersInfoW(SPI_GETMOUSEWHEELROUTING_VALUE, ...); return ok && routing != 2; }
void inject_wheel(int delta, bool horizontal) { mouse_event(... MOUSEEVENTF_WHEEL ...); }
```
→ **和我 10-26 的实验完全对上**：本机 `MouseWheelRouting = 2`（滚轮给光标下的窗口），所以覆盖层收不到 `WM_MOUSEWHEEL`；正确做法是**由程序自己注入滚轮**给光标下的窗口（jietuba 用 `mouse_event`，我用 `SendInput`/`mouse_event` 都行），而不是在钩子里转发。

### 4. 交互与失败可见（jietuba README 中文版原文）
> 滚动长截图：**上下左右四个方向自动拼接，可自动滚动；往回滚只定位不截短，一键裁掉多余部分。**

PixPin 官方文档列的失败条件（与我们用户口径一致）：动态内容、选区内有固定侧栏、含滚动条、纯色/大量重复排版、滚动过快。

---

## 四、我们现状 vs 成熟方案（逐条对照）

我们当前实现（HEAD `9e65313`，`src/SnipTool.cs` + `src/LongShot.cs`）：

| 维度 | 成熟方案（jietuba） | 我们现在 | 差距 |
|---|---|---|---|
| 何时抓帧 | 区域画面变化即抓，稳定后定稿 | 90 ms 定时器，且要求**整块像素完全一致**（`ImagesIdentical` 只抽 5 行×16 列，`src/SnipTool.cs:1294`）才放行 | ❌ 致命：画面有动画 → 门永远关死 → 卡 1 帧（已黑盒复现） |
| 触发来源 | 滚轮/滚动条/键盘/拖动都算 | 只认 `OnMouseWheel`（`src/SnipTool.cs:2623`）+ 低层钩子置的标志；而覆盖层**收不到** `WM_MOUSEWHEEL` | ❌ 结构性缺陷 |
| 匹配算法 | 逐行双哈希 + 多候选 + 打分 + 置信度 | `FindVerticalOverlap(prev,next,10,selH-10)` 单候选、无置信度、阈值死板 | ❌ 真实页面 `overlap=-1` 直接失败 |
| 方向 | 上下双向生长，回滚只定位 | 只向下追加，无回滚定位 | ⚠️ 次要 |
| 自动滚动 | 支持（注入滚轮 + settle） | 无 | ⚠️ 需求未强制 |
| 失败可见 | 明确报失败并保留已拼部分 | 静默停在 1 帧 | ❌ 用户直接痛点 |
| 性能 | 只算新帧哈希，后台线程拼 | 每帧整块比较 + 整图重拼 | ⚠️ 选区大时卡 |
| 证据链 | 有单测（`cpp/tests/test_stitch.cpp`、`test_scroll_capture.cpp`） | 探针自测（曾两次"自证式绿灯"，见 POSTMORTEM） | ⚠️ 需外部黑盒证据 |

**编辑/标注侧对照**：需求 R18–R24 已全部通过（用户 m01534 原话「其他功能测试也都完全正常」）。成熟 Web 方案（tui.image-editor / Fabric.js）能覆盖形状/箭头/文字/滤镜，但要重做输入集成、DPI、剪贴板回填，**没有收益**。

---

## 五、可选路线与成本

| 路线 | 做法 | 成本 | 风险 | 结论 |
|---|---|---|---|---|
| **A. 外挂 jietuba** | 把 jietuba 当独立程序，我们的插件去调它 | 低 | ❌ 它是完整 GUI 应用（17–48 MB），**没有长截图 CLI**，且自带一整套 UI 与我们的覆盖层冲突 | 不可行 |
| **B. 移植 jietuba 内核（推荐）** | 把 `session.rs`/`hash.rs`/`lcs.rs`/`stitch.rs` 的算法翻成 C#，装进现有 `src/LongShot.cs`；抓帧改成「变了就抓、稳定定稿」；失败必弹提示 | 中：约 700–1000 行 C#（C#5 语法，net48，`LockBits` 取行指纹） | 中：行哈希性能要靠 `LockBits`+指针；需重新立黑盒门禁（动画/静态/过长/负控四条腿） | ✅ 建议 |
| **C. 继续自研** | 在现有 `FindVerticalOverlap` 上打补丁 | 低 | ❌ 已失败两轮（t38 黑盒判定不合格：静态误报、无滚轮加帧、offset 错、GUI 预览消失） | 不建议 |
| **D. 换 Web 编辑器** | 用 tui.image-editor 替换原生编辑器 | 高 | 与长截图无关，收益为零 | 不建议 |

---

## 六、需要你拍板的事

1. **长截图**：走路线 B（移植 MIT 内核）吗？若走，我会先只做**最小可用切片**——静态页面 1 帧→多帧、动画页面立刻提示「拼接失败」、回滚不截短——验收靠黑盒四条腿，不再自证。
2. **编辑/标注**：维持现状（我建议）还是换 Web 方案？
3. **节奏**：是否仍然「先请示再派活」，我不再自行建任务。

---

## 附：调研来源
- jietuba 源码：`https://github.com/1003129155/jietuba`（分支 `master2`）— `rust_libs/longstitch/src/{session,hash,lcs,stitch}.rs`、`cpp/src/stitch/{auto_scroll.cpp,change_watch.h,incremental.h,scroll_window.h}`
- ShareX：`https://github.com/ShareX/ShareX` — `ShareX.ScreenCaptureLib/ScrollingCapture*.cs`（GPL-3.0）
- CapScroll：`https://github.com/netcrawlerr/CapScroll` — `src/CapScroll.Platform/Stitching/Stitcher.cs`
- tui.image-editor：`https://github.com/nhn/tui.image-editor`
- QQ/商业工具行为机理：`https://www.clicksun.com.cn/bbs.asp?id=39530`、`https://pixpin.cn/docs/capture/long-capture`
