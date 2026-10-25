# DSH 截图插件 v2 — 安装与验收报告（ACCEPTANCE）

> 状态：**已安装，等待生效**（首装 2026-10-25 18:30，备份目录 .backup-install-20261025-183055；t25 于 18:40 重打包并幂等重装，bundles 保持 23 项不变）。t25 收尾实测：运行中的 DSH 已加载 host 半边（/shot/api/version → 200），**先刷新页面**即可，必要时再重启 DSH（见 §6 开头）。t24 已修复 R21-1/R21-2/R21-3；门禁 out/captain-accept.ps1 12 步全绿之后才打包并装进 desktop profile。**本报告自 t25 起随包交付，且包内副本与仓库版逐字节一致**（t25 之前包内是 18:20 的 HOLD 骨架版，与仓库版 diff 106 行；见 §9）。§1/§2/§3 是实装的真实数字，证据件在 dist/（pack-final.json、install-verify.json、esm-check.json）。全程未重启、未停止任何 DSH 进程，未执行 git commit/push。

## 0. 范围与基线

| 项 | 值 |
| --- | --- |
| 插件 | dsh-screenshot 2.0.0（DSH 桌面 profile 插件） |
| 目标 profile | C:\Users\Administrator\.dsh\profiles\desktop（DSH_PROFILE 未设置时的默认值） |
| 安装脚本 | dsh-screenshot-v2/install.ps1（-WhatIf 计划 / 真装 / -Rollback 回滚） |
| 需求基线 | docs/SPEC.md R1–R30 |
| 验收基线报告 | out/evidence/VERIFY-T23.md（30/30 pass，绑定 12 个文件 sha256，起止快照 diff=IDENTICAL） |
| 安装前置 | t24 修复 R21-1/R21-2/R21-3 后重新打包的 tgz（已满足，见 §1） |
| 安装时间 / 备份目录 | 2026-10-25 18:30 / <profile>\.backup-install-20261025-183055（首装）；t25 重装的备份目录与实测哈希见 dist/install-verify.json 的 backup 字段（时间戳随执行变化，故本文不硬编码） |

## 1. 交付物（t25 重打包，2026-10-25 18:40）

| 项 | 值 |
| --- | --- |
| 包文件 | dsh-screenshot-2.0.0.tgz（仓库根；同一份字节另存 dist/dsh-screenshot-2.0.0.tgz，sha256 相同） |
| 体积 / 文件数 | **约 269 KiB（275 KB 量级）/ 22 files**。本报告本身在包内：任何精确字节数写进来都会让 gzip 长度再漂移几十字节，所以这里只给量级；交付批次的精确字节数与 sha256 见包外 dist/pack-final.json（releasedSize / releasedSha256） |
| sha256（历史实测，非交付批次） | 本轮**首轮** pack 的实测值 9e4f0c744702463bf0925552c01518ca4356f2d5cf5fac5e95fc1997fae11e52（那一版内容 = 本报告的上一稿，非交付稿）；**交付 tgz 自身的 sha256 无法写进报告**（自指），见包外 dist/pack-final.json 的 releasedSha256 与自指说明 |
| 包内关键文件 | bin/SnipTool.exe、bin/EngineTests.exe、lib/index.js、lib/client.js、package.json、cordis.patch.yml、src/*.cs(5)、docs/{SPEC,INTERFACES,VERIFY,RELEASE,ACCEPTANCE}.md、docs/screenshots/*.png、README.md、README.en.md、LICENSE |
| 22 与 21 的差别 | HOLD 前预期 21 个条目；本次为 22，多出的是 docs/ACCEPTANCE.md（本报告，docs/ 在 package.json files 白名单内，属白名单内文档，不是夹带） |
| 自指说明 | 本报告随包交付，所以它与仓库版逐字节一致（这正是 t25 的断言）。但**报告无法记录自身字节的哈希与字节数**：写入 sha256 会改变内容（哈希自指，无解），写入精确字节数会让 gzip 长度随之漂移（几十字节量级，取决于这些数字的压缩性），所以本文只给带宽。因此 §1 只给出历史 pack 的实测 sha256（标明「非交付批次」）与体积带宽，交付批次的精确 sha256/体积/文件数一律以包外 dist/pack-final.json 为准；文件数 22 恒定，不受影响 |
| 解包核对 | dist/unpack/ 解包后 bin/SnipTool.exe（4dc8c308…）、bin/EngineTests.exe（925df12a…）、lib/index.js（b38d06f0…）、lib/client.js（470abc0e…）、package.json（803fb75f…）、cordis.patch.yml（347839b7…）、src/SnipTool.cs（68faf377…）全部与仓库 MATCH；**docs/ACCEPTANCE.md 与仓库版 diff 为空**（t25 的核心断言） |
| 打包清单 | dist/pack-final.json（npm pack --json 的机器可读清单：name/version/filename/size/unpackedSize/entryCount/packedAt/files[22]，并记录 deliveredSha256 / releasedSha256 与 pack 轮次） |
| 二进制一致性注意 | csc 输出非确定性（PE 时间戳）：同一源码重建会换 sha256（t25 跑门禁时 bin/SnipTool.exe 由 4dc8c308 变为 dad8aff7）。因此门禁跑完后把 t8 已验证的二进制按字节还原（src/ 未变，等价构建），再打包，保证包内二进制 = 仓库 bin/ = 已安装的 bin/ = 4dc8c308；还原后另跑 EngineTests 8/8、--selftest 13/13、--longshot-probe ok 复核可执行 |

## 2. 安装结果（2026-10-25 18:30 实装回填）

| 步骤 | 命令 | 结果 |
| --- | --- | --- |
| 门禁（装前） | pwsh -NoProfile -File out/captain-accept.ps1 | RESULT: ALL PASS（12 步），exit 0。首装前与 t25 重打包前各跑一次，两次均 12 步全绿（第二次的完整输出在 out/t25-captain-accept.log）；任一步失败即不装 |
| 计划（首装） | pwsh -NoProfile -File install.ps1 -WhatIf | exit 0；打印四段计划（备份 → pnpm add file:<tgz> cwd=profile → dsh.profile.bundles 22→23 → 需重启 DSH），末行 "-WhatIf: plan only, nothing was written"；profile 零改动 |
| 计划（t25 幂等核验） | pwsh -NoProfile -File install.ps1 -WhatIf -ProfileDir C:/Users/Administrator/.dsh/profiles/desktop | exit 0；注册段输出 **"dsh.profile.bundles already lists dsh-screenshot (23 entries) — no change"**，tarball 行指向本轮新包（体积随批次变化，见 §1）；末行 plan only；重装后复跑同样结果（out/evidence/t25-whatif-preinstall.log、out/evidence/t25-whatif-postinstall.log） |
| 备份 | 脚本自动 | 首装：C:\Users\Administrator\.dsh\profiles\desktop\.backup-install-20261025-183055\：package.json（2140 B）+ cordis.patch.yml（10356 B）+ pnpm-add.log；t25 重装：新建一份 .backup-install-<时间戳>\（package.json 为 23 项 bundles 的版本），目录名与 sha256 见 dist/install-verify.json |
| 安装 | 脚本自动 pnpm add file:F:/Workspace/测试/dsh-screenshot-v2/dsh-screenshot-2.0.0.tgz | exit 0；日志 "pnpm add ok (exit 0)"。t25 用新 tgz 再跑一次，同样 exit 0（功能文件未被改写，见下行） |
| 注册 | 脚本自动 dsh.profile.bundles 追加 dsh-screenshot | 首装 22 → 23；旧 22 项逐字未变、顺序不变（previousEntriesUnchangedInOrder=true），仅末尾追加 "dsh-screenshot"，无重复项。t25 重装 23 → 23（脚本识别已存在，不重复追加），去重后仍 23 项 |
| 产物核验 | pwsh -NoProfile -File dist/verify-install.ps1 → dist/install-verify.json | node_modules\dsh-screenshot 六个关键文件字节与 sha256 全部与仓库一致；version=2.0.0、name=dsh-screenshot、main=lib/index.js（明细见 §3）。t25 重装后：五个功能文件（bin/SnipTool.exe 4dc8c308、bin/EngineTests.exe 925df12a、lib/index.js b38d06f0、lib/client.js 470abc0e、package.json 803fb75f、cordis.patch.yml 347839b7）哈希与首装**完全相同**，只有 docs/ACCEPTANCE.md 变为新版本（与仓库逐字节一致） |
| ESM 可解析 | node --input-type=module -e "await import(<installed lib/index.js>)" | exit 0；exports = ["apply","inject"]，inject = ["webServer"]，typeof apply = function；未启动 webServer（证据 dist/esm-check.json） |
| profile package.json sha256（安装前） | dist/verify-install.ps1 读备份件 | 22dd2b0e4bb94d0758264b2b2840df509a70db22231596b5c1334da5b655785c（2140 B） |
| profile package.json sha256（安装后） | 同上 | cc8bfbc5ecf70f064c0fd429e6332754048e554d3f108d99b8bae9748a5bb807（2261 B） |
| 备份件 sha256 | 同上 | 首装：package.json 22dd2b0e…、cordis.patch.yml eef8dca1… —— 与安装前完全一致，证明备份就是原始字节 |
| 备份件 sha256（t25 重装） | dist/install-verify.json 的 backup 段 | 备份件 package.json = cc8bfbc5…（2261 B，即重装前的 profile 状态）、cordis.patch.yml = eef8dca1…（10356 B）；重装后 profile 仍为 cc8bfbc5…（bundles 未变），即重装只换 node_modules 内容、不动 profile 配置 |
| 其余配置零改动 | 逐键 diff（dist/install-verify.json 的 dependencies / bundles 段） | dependencies 仅新增 dsh-screenshot: file:…（removed=[]、changed=[]，18 → 19 项）；name/private/dsh 键集不变；cordis.patch.yml 未变（eef8dca1…，10356 B）；pnpm-lock.yaml 由 pnpm 重写（98350 B，属 pnpm 正常行为） |
| 进程纪律 | 全程未执行 | 未重启、未停止任何 DSH 进程，未 taskkill；脚本只打印「需重启 DSH 生效」，重启由用户决定 |
| tgz 可复现性说明 | — | npm pack 每次重写 mtime，**tgz 字节本身不可复现**（同源码两次打包 sha256 不同）；评审比的是解包后文件内容的 sha256，不是 tgz 本身 |
| 重装幂等性（t25） | 同上 | 第二次安装不新建 bundle 条目、不改 dependencies 的 spec（仍是 file:<tgz>）、不改 cordis.patch.yml；profile package.json 只可能因 pnpm 重写 lockfile 侧内容而变，bundles 数组逐项不变（dist/install-verify.json 的 bundles.prefixSame=true、appended=[]） |

## 3. 安装前后自检（2026-10-25 18:28 门禁实测回填）

下表「实测」列是本次在最终字节（src/SnipTool.cs 68faf377…、bin/SnipTool.exe 4dc8c308…）上的真实输出。

| 阶段 | 命令 | 通过标准 | 实测 |
| --- | --- | --- | --- |
| 构建 | pwsh -NoProfile -File build.ps1 -Tests | exit 0，0 error | PASS exit=0 errors=0（warning 仅 CS1690/CS0649/CS0169 一类） |
| 引擎 | bin/EngineTests.exe --json out/engine.json --png out/engine | exit 0，8/8 passed | PASS exit=0 checks=8 failed=[] |
| 覆盖层自测 | bin/SnipTool.exe --selftest out/selftest | exit 0，summary.json 13/13 criteria passed，8 PNG + longshot_probe.png | PASS exit=0 criteria=13 pngs=8 failed=[] |
| 长截图探针 | bin/SnipTool.exe --longshot-probe out/longshotprobe | exit 0，ok=true、fallbackUsed=false、n1RegressionOk=true、exportedHeight>=composedHeight、hookUnhooked=true | PASS exit=0 ok=true frames=4 selHeight=200 composedHeight=680 matchedMarkers=true |
| 长截图探针（补充断言） | 同上产物 | fallbackUsed=false / realPath=true / n1RegressionOk=true / exportedHeight=composedHeight / hookInstalled=true 且 unhooked=true | PASS fallbackUsed=False realPath=True；probe-n1 exported=680 composed=680；probe-hook installed=True unhooked=True |
| 长截图负控 | bin/SnipTool.exe --longshot-probe out/probe-neg wheelOnly=false | **必须非零退出**（ok=false） | PASS exit=1（探针确实能失败，说明正控不是自证） |
| N-1 裁剪回归门禁 | out/review-t21/LongShotCropRegression.exe | exportedHeight 不得被裁回视口 | PASS exit=0 exportedHeight=1480 stitchedHeight=1480 viewport=1080 verdict=PASS |
| 崩溃日志探针 | bin/SnipTool.exe --crash-probe out/crashprobe | exit 0，ok=true，日志字节增长 | PASS ok=True bytes 6732 -> 6776 |
| 插件冒烟 | node tools/plugin-smoke.mjs --root . | exit 0，8 pass / 0 fail | PASS 8 pass / 0 warn / 0 fail（e2e plugin 步同口径） |
| 端到端 | pwsh -NoProfile -File tools/e2e.ps1 | exit 0，report.json counts {pass:11, fail:0} | PASS exit=0 report=pass pass=11 fail=0 |
| 队长验收 | pwsh -NoProfile -File out/captain-accept.ps1 | 12 步全绿（winexe 一律 Start-Process -Wait -PassThru） | **RESULT: ALL PASS**（12 步），exit 0 |
| 安装产物 | dist/verify-install.ps1 | 六个关键文件与仓库一致 | PASS allMatch=True：package.json 833 B/803fb75f…、lib/index.js 15112 B/b38d06f0…、lib/client.js 14551 B/470abc0e…、bin/SnipTool.exe 143360 B/4dc8c308…、bin/EngineTests.exe 42496 B/925df12a…、cordis.patch.yml 62 B/347839b7… |

## 4. R1–R30 验收映射

完整逐条判定与命令证据见 **out/evidence/VERIFY-T23.md**（§「R1–R30 逐条判定」，每条含结论 + 本轮实测证据）。下表只给映射，不复制全文；结论列是 t23 在绑定哈希上的判定（30/30 pass）。t24 改动 src/ 后已在最终字节上用同一套命令复跑（§3 表）：captain-accept 12 步全 PASS、e2e 11 步 pass=11 fail=0，结论不变；差异与时间线见 §9。

| R | 要求（简） | 结论 | 证据指针 |
| --- | --- | --- | --- |
| R1 | 话筒左侧剪刀按钮，同尺寸 + hover | pass | VERIFY-T23 R1；lib/client.js insertBefore(btn, mic)；plugin-smoke client-load |
| R2 | 点击进入原生覆盖层 | pass | VERIFY-T23 R2；longshot_probe.json realPath=true；e2e plugin 步 |
| R3 | 「隐藏 DSH」开关默认勾选并持久化 | pass | VERIFY-T23 R3；out/selftest/a3_a4_topbar.png；%LOCALAPPDATA%\dsh-screenshot\settings.json |
| R4 | 右键退出不产生截图 | pass | VERIFY-T23 R4；探针 cancelLegOk=true（state=cancel，无新 PNG） |
| R5 | 退出/取消/确定恢复 DSH 窗口 | pass | VERIFY-T23 R5；SnipTool.cs 三条路径 ShowWindow(dshWnd,9)；dshWnd==Zero 时 LogCrash |
| R6 | 自动识别窗口/屏幕/任务栏 | pass | VERIFY-T23 R6；engine.json B1/B2/B3；a1_window_highlight.png / a1_screen_highlight.png / a1_taskbar_highlight.png |
| R7 | 不写死分辨率；多屏/DPI/负坐标 | pass | VERIFY-T23 R7；Detect.cs 无分辨率字面量；EngineTests B2 运行时读取 Bounds |
| R8 | 2–3px 蓝框 + 左上白底尺寸标签 | pass | VERIFY-T23 R8；a1 三张 PNG（888×777 / 1920×1080 / 1920×48） |
| R9 | 区域外暗化，区域内正常 | pass | VERIFY-T23 R9；a1_window_highlight.png 判读 |
| R10 | 单击确认自动识别 | pass | VERIFY-T23 R10；dragMode=4 确认路径；B3 HitTest 优先级 |
| R11 | 拖拽框选实时边框 + 尺寸标签 | pass | VERIFY-T23 R11；a2_drag_selection.png（580×360 + 对角虚线） |
| R12 | 0 尺寸无效；<3px 回待选 | pass | VERIFY-T23 R12；hasSel = W>=6 && H>=6 |
| R13 | 顶部开关栏：左隐藏 DSH / 右长截图 | pass | VERIFY-T23 R13；a3_a4_topbar.png（zh 223×36 / en 306×36 不裁切） |
| R14 | 长截图滚轮采集 + 拼接，上滚不重复 | pass | VERIFY-T23 R14；longshot_probe.json frames=4、composed=680；负控 wheelOnly=false → exit 1 |
| R15 | 选区旁等比缩小预览 | pass | VERIFY-T23 R15；a5_longshot_preview.png（190×430 双语面板，等比缩略） |
| R16 | 长截图结束进入同一编辑流 | pass | VERIFY-T23 R16；探针 FinishLongShot→ShowBar 真实路径 |
| R17 | 取消/完成合理恢复 DSH | pass | VERIFY-T23 R17；cancelLegOk=true |
| R18 | 普通与长截图同一编辑器 | pass | VERIFY-T23 R18；CommitFrame 单一入口 → ShowBar |
| R19 | 纯图标工具栏 + 悬停提示（双语跟随） | pass | VERIFY-T23 R19；a6_editor_toolbar.png（无文字，纯图标） |
| R20 | 矩形/椭圆/直线/箭头/画笔/文本 + 颜色粗细 | pass | VERIFY-T23 R20；六工具注册；PenWidth/PenColor 与色板 |
| R21 | 马赛克 | pass | VERIFY-T23 R21；a6_mosaic_before_after.png（4201-8888-9999 被打码）；**R21-1 内存泄漏已修（t24）**，见 §5 第 0 条 |
| R22 | 右侧保存/红叉/绿勾 | pass | VERIFY-T23 R22；a6_editor_toolbar.png 三键 |
| R23 | 确定后入输入区、不自动发送 | pass | VERIFY-T23 R23；lib/client.js 合成一次 paste；无 submit/click |
| R24 | 保存 = PNG 落盘；取消 = 丢弃 | pass | VERIFY-T23 R24；SaveFileDialog PNG；取消 → state=cancel |
| R25 | 可安装为桌面 profile 插件 | pass | VERIFY-T23 R25；package.json dsh.bundle.patch + files 白名单；install-plan 步 pass；本报告 §2 真装回填 |
| R26 | .NET 4.8 + csc，无 CLR 崩溃框，崩溃写日志 | pass | VERIFY-T23 R26；out/crashprobe/crash_probe.json（日志字节增长） |
| R27 | 单实例 + 暖进程 --serve | pass | VERIFY-T23 R27；%LOCALAPPDATA%\dsh-screenshot-snip Mutex；e2e 多会话无僵尸 |
| R28 | 语言/主题跟随 DSH | pass | VERIFY-T23 R28；a3_a4_topbar.png / a5 双语不裁切；--lang/--dark/--light 透传 |
| R29 | 全本地、无网络 | pass | VERIFY-T23 R29；src/*.cs + lib/*.js 网络 API grep 0 命中 |
| R30 | 可复现证据（PNG + JSON） | pass | VERIFY-T23 R30；engine 8/8、selftest 13/13、probe 双向、crash、smoke、report 11 步 |

## 5. 已知限制与未覆盖项（如实记录）

0. **R21-1（已修复，t24 —— 保留在此仅作追溯）**：长截图拼接画布 longComposed 原先不随 DisposeLongFrames 释放，暖进程常驻可占用数百 MB。t24 后 DisposeLongFrames 释放 longComposed 且幂等，FinishLongShot 走新的 DisposeLongFramesOnly，Cancel/OnFormClosed 走全量释放；leakcheck harness exit 0（longComposedNulledAfterDispose=True / saveAfterDisposeThrew=True / secondDisposeIdempotent=True）。R21-2 死字段、R21-3 CS0219 同批清除。
1. **F-14（not-fixed）**：UI 线程仍有 5 处 Thread.Sleep（最小化等待、粘贴前 220ms + 140ms 等）。属体感级延迟，不是功能缺陷；本轮未改，理由见 out/evidence/REPAIR-T14.md 的 F-14 小节。
2. **F-20（deferred）**：进程 DPI 感知为 system-DPI-aware，不是 per-monitor v2。多显示器**不同缩放比**下，跨屏选区的像素坐标与标签可能有 1–2px 级偏差；单一缩放比与常规多屏（同 DPI）不受影响，R7 的非写死坐标要求仍满足。改动风险大于收益，明确 deferred。
3. **长截图探针用的是自建 helper 窗口**（ScrollHelperForm：条纹 + 专属 marker），不是真实第三方目标应用。它证明「真实 SnipForm 覆盖层 + 真实 WM_MOUSEWHEEL 转发 + 真实抓屏 + 真实拼接 + 真实导出」这条链路成立（负控 wheelOnly=false 会 exit 1，说明 PASS 不可能来自兜底），但**不能替代**在浏览器/文档里手动滚动的体感验证。
4. **整链仍需真实 DSH 会话人工点验**：点剪刀 → 覆盖层 → 选区 → 编辑器 → 绿勾确定 → 图片进输入区且**不自动发送**。自动化只覆盖到「原生导出 + paste 合成 + 不 submit」（静态与冒烟级），端到端的 UI 注入在本仓库无头环境下无法断言。
5. 暖进程常驻：--serve 进程空闲 180 秒退出；卸载/回滚后若仍有残留进程，需结束 SnipTool.exe（安装脚本不会 stop 任何 DSH 进程，也不会杀用户手工启动的实例）。
6. 结果目录：默认 %TEMP%\dsh-screenshot-v2（非 ASCII 时退到 %PUBLIC%\dsh-screenshot-v2），只保留 last.png + state.json，长截图帧不落盘。

## 6. 人工确认清单（先试刷新页面，必要时再重启 DSH）

**先试刷新页面。** t25 收尾实测（2026-10-25 18:47，日志 out/evidence/t25-hotload-check.log）：运行中的 DSH（pid 18560，13:55:43 启动）**已经加载了插件的 host 半边** —— `http://127.0.0.1:64265/shot/api/version` → `200 {"version":"2.0.0"}`、`/shot/api/last` → `200 {"mtime":0}`、`/shot/api/state` → `200 {"at":0,"result":""}`（三个路由都由本插件的 lib/index.js 提供）。所以大概率**只需刷新一次页面**就能在话筒左侧拿到剪刀按钮，不必重启 DSH。

只有在下列情况才需要重启：(a) 刷新后剪刀按钮仍未出现（客户端 bundle 未重新加载）；或 (b) 改动的是启动期才读取的东西 —— 原生 bin/SnipTool.exe、cordis.patch.yml（bundle patch 在启动时装配）。重启由用户决定；安装脚本只打印「需重启 DSH 生效」，不重启也不 stop 任何进程。

无论刷新还是重启，都请按顺序确认：

| # | 确认项 | 期望 |
| --- | --- | --- |
| 1 | 话筒按钮左侧出现剪刀按钮 | 32×32、与话筒同高、hover 有背景反馈，不挤压原有按钮 |
| 2 | 点击剪刀 | 进入原生覆盖层：光标所在窗口/屏幕/任务栏自动高亮（粗蓝框 + 左上白底尺寸标签），区域外变暗 |
| 3 | 顶部开关栏 | 左「隐藏 DSH 窗口」默认勾选；右「长截图」默认不勾；切换后重开仍保持 |
| 4 | 拖拽框选 | 实时蓝框 + 尺寸标签随拖动更新；松开即确认 |
| 5 | 右键退出 | 覆盖层关闭，**不产生截图**，DSH 窗口恢复（若之前被隐藏） |
| 6 | 长截图 | 勾选长截图后框选 → 选区内滚轮 → 右侧等比预览实时变长 → Enter 完成 |
| 7 | 编辑器 | 纯图标工具栏：矩形/椭圆/直线/箭头/画笔/文本 + 颜色粗细、马赛克、保存/红叉/绿勾；悬停有中英提示 |
| 8 | 绿勾确定 | 图片进入 DSH 输入区（作为附件/缩略图），**不自动发送**；输入框内容与草稿保留 |
| 9 | 红叉取消 | 关闭编辑器，不插入任何图片，DSH 恢复 |
| 10 | 保存 | 弹出 PNG 另存对话框，落盘后可正常打开 |
| 11 | 语言/明暗 | 切到英文界面再开一次：顶栏、提示、文件名前缀均为英文；暗色主题下覆盖层/工具栏配色跟随 |

## 7. 回滚步骤

安装脚本改动 profile 的只有三处：`.backup-install-<stamp>/` 备份目录、`package.json` 的 `dependencies`、`dsh.profile.bundles`。回滚：

```powershell
# 1) 查看有哪些备份（最新的在最前）
Get-ChildItem C:\Users\Administrator\.dsh\profiles\desktop\.backup-install-* | Sort-Object Name -Descending | Select-Object -First 3 Name, LastWriteTime

# 2) 用脚本自动回滚（取最新备份，还原 package.json 与 cordis.patch.yml）
pwsh -NoProfile -File dsh-screenshot-v2/install.ps1 -Rollback

# 3) 需要回到更早的某次安装时（脚本只会取最新备份），手工把该备份的两个文件复制回去：
$b = 'C:\Users\Administrator\.dsh\profiles\desktop\.backup-install-<更早的stamp>'
Copy-Item "$b\package.json"      'C:\Users\Administrator\.dsh\profiles\desktop\package.json' -Force
Copy-Item "$b\cordis.patch.yml"  'C:\Users\Administrator\.dsh\profiles\desktop\cordis.patch.yml' -Force

# 4) 重启 DSH 使卸载生效（脚本只打印提醒，不重启）
```

回滚后核对：`dsh.profile.bundles` 中不再含 `dsh-screenshot`，`dependencies` 中不再有 `dsh-screenshot`；`node_modules\dsh-screenshot` 可留待 pnpm 下次 install 清理，或手工删除该目录。

## 8. 复验命令速查

```powershell
cd dsh-screenshot-v2
pwsh -NoProfile -File build.ps1 -Tests
./bin/EngineTests.exe --json out/engine.json --png out/engine
./bin/SnipTool.exe --selftest out/selftest
./bin/SnipTool.exe --longshot-probe out/longshotprobe
./bin/SnipTool.exe --longshot-probe out/probe-neg wheelOnly=false      # 必须非零退出
./bin/SnipTool.exe --crash-probe out/crashprobe
node tools/plugin-smoke.mjs --root .
pwsh -NoProfile -File tools/e2e.ps1                                    # 只看 out/evidence/report.json
pwsh -NoProfile -File install.ps1 -WhatIf
```

> 注意：bin/SnipTool.exe 是 winexe，PowerShell 里用 `&` 调用**不会等待**；要拿真实退出码请用 `Start-Process -Wait -PassThru`（e2e.ps1 与 captain-accept.ps1 内部已如此）。

## 9. 变更记录

| 时间 | 变更 | 证据 |
| --- | --- | --- |
| 2026-10-25 18:20 | 骨架落盘（安装一节为 HOLD 占位）；t24 前的预打包字节 sha256=1c30b5b1…（265871 B / 21 files），**不作为交付基线** | dist/pack-pret24.json |
| 2026-10-25 18:26 | t24 通过（R21-1/R21-2/R21-3）并放行；门禁 out/captain-accept.ps1 **RESULT: ALL PASS**（12 步），e2e 11 步 fail=0；bin/ 在门禁中重建（SnipTool.exe → 4dc8c308…） | out/captain-accept.ps1 输出；§3 表 |
| 2026-10-25 18:28 | 首次打包（t8 批次，已被 t25 取代）：**271600 B / 22 files / sha256 7dd8fba5…**；22 = 原 21 + docs/ACCEPTANCE.md（files 白名单内）；解包关键文件与仓库 MATCH | 历史批次，清单见 dist/pack-pret24.json 与本节 t25 行 |
| 2026-10-25 18:30 | install.ps1 -WhatIf exit 0（零改动）→ 真装 exit 0：备份 .backup-install-20261025-183055、bundles 22→23、deps 18→19、pnpm add ok；未重启 DSH | §2；dist/install-verify.json |
| 2026-10-25 18:35 | 装后核验：node_modules 六文件哈希全部 MATCH、ESM 可解析；回填本报告 §1/§2/§3/§5/§9 | dist/install-verify.json、dist/esm-check.json、本文件（同内容快照 dist/ACCEPTANCE.md） |
| 2026-10-25（t25 轮次，时钟见 dist/install-verify.json 与 out/evidence/t25-*.log） | **t25：重打包消除「包内报告说没装」的缺陷**。此前包内 docs/ACCEPTANCE.md 是 18:20 的 HOLD 骨架版（14333 B，正文写「状态：安装待放行」），与仓库版（19838 B，正文写「已安装」）diff 106 行；现在用仓库当前版本重打包，解包后与仓库版 **diff 为空**。功能文件（bin/、lib/、package.json、cordis.patch.yml）与首装逐字节相同，只有 docs/ACCEPTANCE.md 随包更新 | dist/pack-final.json、dist/unpack/、out/evidence/t25-doc-diff.txt |
| 同上（t25 轮次） | t25 幂等重装：install.ps1 -WhatIf 报 "already lists (23 entries) — no change" → 真跑 exit 0 → node_modules/dsh-screenshot 拿到新包，功能文件哈希与首装完全相同，bundles 仍 23 项无重复 | dist/install-verify.json、out/evidence/t25-whatif-*.log |
| 自指说明（替代原「已知文档时序说明」） | 本报告随包交付，因此它与仓库版**逐字节一致**；把交付 tgz 自身的 sha256 写进报告会让报告字节变化（哈希自指，数学上不可能自洽），故 §1 只列「历史实测，非交付批次」的 sha256（本轮首轮 pack），交付批次的真实 sha256 记在包外 dist/pack-final.json 的 releasedSha256；§1 的体积给带宽 + 文件数 22（解包实测），精确字节数同样在 dist/pack-final.json。功能文件（bin/、lib/、package.json、cordis.patch.yml）在包内 = 仓库 = 已安装，三处哈希一致 | dist/pack-final.json、本节 |
| 2026-10-25（t25 收尾，captain m01477 指示） | **新增「先刷新页面、必要时再重启」**：实测运行中的 DSH（pid 18560）已加载 host 半边 —— /shot/api/version → 200 `{"version":"2.0.0"}`、/shot/api/last → 200 `{"mtime":0}`、/shot/api/state → 200，故 §6 开头改写为「先刷新页面；刷新后仍无按钮、或改动了启动期读取的文件（bin/SnipTool.exe、cordis.patch.yml）再重启」。**按指示本条不重新打包**：交付 tgz 内仍为 060c4bbb…（24849 B），仓库文档此后多这一条，两者差异仅此一处；t25 的「解包 doc 与仓库 diff 为空」成立于打包/安装时点，之后的分叉是已知且有意的（包内副本哈希见 dist/pack-final.json 的 docInsidePackage） | out/evidence/t25-hotload-check.log；dist/pack-final.json |
