# DSH 截图插件 v2 — 安装与验收报告（ACCEPTANCE）

> 状态：**已安装，等待生效**（首装 2026-10-25 18:30，备份目录 .backup-install-20261025-183055；t25 于 18:40 重打包并幂等重装，bundles 保持 23 项不变）。t25 收尾实测：运行中的 DSH 已加载 host 半边（/shot/api/version → 200），**先刷新页面**即可，必要时再重启 DSH（见 §6 开头）。t24 已修复 R21-1/R21-2/R21-3；门禁 out/captain-accept.ps1 12 步全绿之后才打包并装进 desktop profile。**本报告自 t25 起随包交付，且包内副本与仓库版逐字节一致**（t25 之前包内是 18:20 的 HOLD 骨架版，与仓库版 diff 106 行；见 §9）。§1/§2/§3 是实装的真实数字，证据件在 dist/（pack-final.json、install-verify.json、esm-check.json）。全程未重启、未停止任何 DSH 进程，未执行 git commit/push。**t26（2026-10-26）发现交付 tgz 里仍是会崩客户端启动的旧 lib/client.js（470abc0e），已用仓库字节重打包并幂等重装；包内 lib/client.js 现为 3c58aaa2，这段历史如实保留在 §9。** **t28 修复「按钮隐形」（搬 DOM 的 insertBefore/MutationObserver hack 删除，按钮改为自然驻留 conversation.input.right，浅色主题可见性修复），lib/client.js 变为 4979d9d9（14632 B）；t30 于 2026-10-26 03:16 用该字节重新打包并幂等重装，最终交付 tgz 与仓库、已安装三处 lib/client.js 字节一致（4979d9d9）。** **t34（文档诚实性 + G-7 版本化门禁 tools/accept.ps1）与 t35（`/shot/api/probe` 加固：默认关闭、POST-only、8KB 上限、不回传路径）之后，t36 于 2026-10-26 用仓库字节重新打包（23 files，精确字节见 dist/pack-final.json 的 releasedBatch=t36）并 install.ps1 -Force 幂等重装：lib/client.js=eb306de6（18891 B）、lib/index.js=b5c99e60（16504 B）在仓库 / tgz 解包 / 已安装 node_modules 三处完全一致；门禁 tools/accept.ps1 全量模式 22 项 PASS（唯一 WARN 是 bytes-unchanged，全量模式按设计允许重建/重打包）。**
> **v2.1（2026-10-26，用户裁决）**：取消长截图（删 `src/LongShot.cs`、覆盖层长截图驱动/预览窗、`--longshot-probe` 探针与顶栏开关栏），入口改为**左键＝保留 DSH 窗口 / 右键＝最小化 DSH 窗口**（悬停提示「左键保留窗口，右键最小化窗口」），版本号 2.0.0 → **2.1.0**。本文件 §0–§8 记录的是 2.0.0 交付批次的历史事实，未改动；v2.1 的口径见 §9 末行与 `docs/SPEC.md`（R1–R18 已按 v2.1 重写）。


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

## 1. 交付物（t36 最终批次，2026-10-26；t34 文档诚实性/版本化门禁 + t35 探针加固后重打包）

| 项 | 值 |
| --- | --- |
| 包文件 | dsh-screenshot-2.0.0.tgz（仓库根；同一份字节另存 dist/dsh-screenshot-2.0.0.tgz，sha256 相同） |
| 体积 / 文件数 | **约 291 KiB（298 KB 量级）/ 23 files**（t36 实测；t33 批次为 276 KiB / 22 files）。本报告本身在包内：任何精确字节数写进来都会让 gzip 长度再漂移几十字节，所以这里只给量级；本次交付批次（t36）的精确字节数与 sha256 见包外 dist/pack-final.json（releasedBatch / releasedSize / releasedSha256） |
| sha256（历史实测，非交付批次） | t25 交付批次的实测值 ea938d6862a5e19eb8a0d0d6bf76cbda245f1259406a8ed9bd4aedca34742367（275239 B），**已被 t26 取代**：那一版包内 lib/client.js 是 470abc0e（会崩客户端启动，见 §9 的 t26 行）。t26 交付批次实测 e8f2d61387e81b2a4dabe7895bd6dec5c1fd76f2e49fd6f8db462085a662c160（277387 B），**又已被 t30 取代**（t28 改了 lib/client.js）；t30 交付批次自身的 sha256 同样**无法写进本报告**（自指），见包外 dist/pack-final.json 的 releasedSha256 与自指说明。**t30 的 41f6cf382b752a80…（279633 B）已被 t33 取代**（t32 改了 lib/client.js 与 lib/index.js：图标硬化 + 自检探针，见下两行与 §9 的 t33 行）；**t33 的 24cf04a5f93a7bb0…（282767 B）现已被 t36 取代**（t34 改了 docs/VERIFY.md 与 tools/、t35 改了 lib/index.js 与 lib/client.js，见下方 t34/t35/t36 行与 §9） |
| 包内关键文件 | bin/SnipTool.exe、bin/EngineTests.exe、lib/index.js、lib/client.js、package.json、cordis.patch.yml、src/*.cs(5)、docs/{SPEC,INTERFACES,VERIFY,RELEASE,ACCEPTANCE,POSTMORTEM}.md、docs/screenshots/*.png、README.md、README.en.md、LICENSE |
| t26 关键修正 | 包内 **lib/client.js**：470abc0e7b6d35fb（14551 B，旧版，客户端启动即崩）→ **3c58aaa2c38ebcfa（15616 B，修好版：exports.inject = ['slots'] + ctx.slots.inject(key, callback)，只注册 conversation.input.right）**。其余 21 个条目与 t25 批次逐字节相同：bin/SnipTool.exe 4dc8c308、bin/EngineTests.exe 925df12a、lib/index.js b38d06f0、package.json 803fb75f、cordis.patch.yml 347839b7、src/*.cs 五个哈希不变 |
| t28/t30 关键修正 | 包内 **lib/client.js**：3c58aaa2c38ebcfa（15616 B）→ **4979d9d9357b3a2a（14632 B）**。t28 删除了 ShotButton 里的 DOM 搬运 hack（仓库实测 `insertBefore` / `MutationObserver` / `findMic` 计数均为 0），剪刀按钮改为一进 `conversation.input.right` 槽就自然渲染（该槽排在 activity/话筒左侧，即最终落在话筒左边），并用 `--dsw-alias-label-secondary` / `--color-text-secondary` / `--dsw-alias-label-secondary-hover` 修复浅色主题下的可见性；t30 用这份字节重新打包，交付物不再落后于代码。其余 21 个条目与 t26 批次逐字节相同（bin/SnipTool.exe 4dc8c308、bin/EngineTests.exe 925df12a、lib/index.js b38d06f0、package.json 803fb75f、cordis.patch.yml 347839b7、src/*.cs 五个） |
| t32/t33 关键修正 | 包内 **lib/client.js**：4979d9d9（14632 B）→ **143b6cda134cfe07d7cd4cca6902a6fba110851bca3160f84e50ce1979f5a9c5（18825 B）**：t32 做图标硬化——SVG `stroke` 改为字面量 `#8a8f98`（不再依赖主题变量，全文 `currentColor` 出现 0 次）、button 32×32 与 svg 18×18 用内联 `style` 写死尺寸、hover 用 `.shot-btn:hover svg { stroke: #5b6169 }`；并在组件挂载 ~800ms 后用 `collectProbe` 把真实 DOM 状态经 `fetch` 上报到 `/shot/api/probe`（失败仅 try/catch 吞掉）。包内 **lib/index.js**：b38d06f0（15112 B）→ **ff1ea269421312502ec8778886bf80a609d709b02cf54341d2e455125d5b0b7b（16388 B）**：新增 GET/POST `/shot/api/probe` 路由（解析 `d` 参数原样落盘到 `%TEMP%/dsh-shot-probe.json`，非法 JSON 返回 400）。其余 20 个条目与 t30 批次逐字节相同（bin/SnipTool.exe 4dc8c308、bin/EngineTests.exe 925df12a、package.json 803fb75f、cordis.patch.yml 347839b7、src/*.cs 五个） |
| t34/t35/t36 关键修正 | 包内 **lib/client.js**：143b6cda（18825 B）→ **eb306de64ff3eb074ef414bf79eb5d5103f23bddc5c316a5c5320d228d16975a（18891 B）**：t35 把探针上报从 GET+query 改为 `POST /shot/api/probe` + JSON body，整段包在 try/catch 里（失败只吞掉，不影响按钮）；DOM 搬运 hack 计数仍为 0（`insertBefore` / `MutationObserver` / `findMic` / `alignPosition` 均为 0）。包内 **lib/index.js**：ff1ea269（16388 B）→ **b5c99e6009dde5caf6cc2840ac9eab9235dc08401ed7fc820d593ee8e13d784d（16504 B）**：t35 加固探针路由——默认**关闭**（开关文件 `%TEMP%\dsh-shot-debug.on` 不存在时返回 404）、**POST-only**（非 POST → 405 + `Allow: POST`）、**8KB 体积上限**（超限 413 不落盘）、非法 JSON 400 不落盘、成功只回 `{ ok: true }`（**不回传落盘路径**）。docs/VERIFY.md 由 t34 重写为 634 行（人工证据产出状态总表 + 75 处 manual 引用带「⚠ 未产出」标记 + R1 段按真实槽位结构重写），tools/accept.ps1（26269 B，sha256 2723352d…）为 t34 新增的版本化门禁（G-7），t34 另把 client-contract 的 provenance 如实划分为 VERBATIM / GUARDRAILS。其余 20 个条目与 t33 批次逐字节相同（bin/SnipTool.exe 4dc8c308、bin/EngineTests.exe 925df12a、package.json 803fb75f、cordis.patch.yml 347839b7、src/*.cs 五个） |
| 22 与 21 的差别 | HOLD 前预期 21 个条目；t8..t33 各批次为 22，多出的是 docs/ACCEPTANCE.md（本报告，docs/ 在 package.json files 白名单内，属白名单内文档，不是夹带）。**t36 起为 23**：docs/POSTMORTEM.md（t31 新增的复盘文档，同属 docs/ 白名单）也随包交付，故本批次 entryCount=23，全部条目都能对上 package.json 的 files 白名单 |
| 自指说明 | 本报告随包交付，所以它与仓库版逐字节一致（这正是 t25 的断言）。但**报告无法记录自身字节的哈希与字节数**：写入 sha256 会改变内容（哈希自指，无解），写入精确字节数会让 gzip 长度随之漂移（几十字节量级，取决于这些数字的压缩性），所以本文只给带宽。因此 §1 只给出历史 pack 的实测 sha256（标明「非交付批次」）与体积带宽，交付批次的精确 sha256/体积/文件数一律以包外 dist/pack-final.json 为准；文件数固定（t8..t33 为 22，t36 起为 23），不随报告内容变化 |
| 解包核对 | dist/unpack/ 解包后 bin/SnipTool.exe（4dc8c308…）、bin/EngineTests.exe（925df12a…）、lib/index.js（**b5c99e60…，16504 B —— t36 最终交付字节**；t33 批次为 ff1ea269…、t30/t26 批次为 b38d06f0…）、lib/client.js（**eb306de6…，18891 B —— t36 最终交付字节**；t33 批次为 143b6cda…、t30 批次为 4979d9d9…、t26 为 3c58aaa2…、t25 误为 470abc0e…）、package.json（803fb75f…）、cordis.patch.yml（347839b7…）、src/SnipTool.cs（68faf377…）全部与仓库 MATCH；**docs/ACCEPTANCE.md 与仓库版 diff 为空**（t25 的核心断言；t26 起仓库版末尾多一行「打包实测」，见 §9，这是唯一差异） |
| 打包清单 | dist/pack-final.json（npm pack --json 的机器可读清单：name/version/filename/size/unpackedSize/entryCount/packedAt/files[23]，并记录 deliveredSha256 / releasedSha256 与 pack 轮次） |
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
| t26 重装（修正包内 client.js） | pwsh -NoProfile -File install.ps1 -Force -ProfileDir C:/Users/Administrator/.dsh/profiles/desktop -Tgz <t26 tgz> | exit 0（**不带 -Force 时脚本按设计 no-op**：「already installed … use -Force to reinstall」，不跑 pnpm add）；新建备份目录 .backup-install-<t26 时间戳>；node_modules/dsh-screenshot/lib/client.js 变为 3c58aaa2（15616 B）= 仓库字节；bundles 23 → 23、无重复；profile package.json 仍 cc8bfbc5…；逐文件哈希见 dist/install-verify.json |
| tgz 内容一致性（t26） | tar -xzf 后逐文件比对 | 22 个条目里 21 个与 t25 批次相同，唯一差异是 lib/client.js（470abc0e → 3c58aaa2）；解包后 `grep -c "exports.inject = ['slots']"` = 1、`grep -c conversation.input.activity` = 0（证据 out/evidence/t26-unpack-check.txt） |
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
| 2026-10-26（t26，captain 指派） | **修正交付 tgz 内含崩溃版客户端的问题（历史保留，不抹掉）**：t25 交付的 tgz（ea938d68…，275239 B）包内 lib/client.js 仍是旧字节 470abc0e7b6d35fb（14551 B）。该版本声明 `exports.inject = ['webServer']` 却调用 `ctx.slots.inject(...)`，在客户端加载期抛错 → 实机 web boot 失败（`web boot: 1 entry did not activate` / `dsh-screenshot: failed`，日志 C:/Users/Administrator/AppData/Roaming/@deepseek-ai/dsh-desktop/logs/crash-2026-10-25T18-34-20-986Z-web-boot.log）。当时仓库与**已安装副本**都已是修好的 3c58aaa2，只有随包交付的 tgz 是旧字节——也就是说任何人用那个 tgz 重装都会复发客户端启动崩溃。t26 用仓库当前字节重新 npm pack（22 files，体积见 §1），解包核对 lib/client.js = 3c58aaa2（15616 B）、`exports.inject = ['slots']` 命中 1 次、无 conversation.input.activity 注册；随后 install.ps1 -Force 幂等重装，node_modules 与仓库逐字节一致、bundles 仍 23 无重复、profile package.json 仍 cc8bfbc5…；全程未重启/未停止任何 DSH 进程、未 git commit。本行即为这段缺陷历史的正式记录 | dist/pack-final.json（releasedBatch=t26）、dist/install-verify.json、out/evidence/t26-unpack-check.txt、out/t26-captain-accept.log、dist/unpack/package/lib/client.js |
| 2026-10-26（t26 打包实测；**本行在打包之后写入，故只存在于仓库版**） | t26 交付批次实测：**dsh-screenshot-2.0.0.tgz = 277387 B（270.9 KiB）/ 22 files / unpackedSize 730156 / sha256 e8f2d61387e81b2a4dabe7895bd6dec5c1fd76f2e49fd6f8db462085a662c160**；dist/ 内同字节副本 sha256 相同。因为本报告随包交付，把这段数字写进包内会让包字节再变（自指），所以**包内副本不含本行**；这是 t26 之后仓库版与包内副本的唯一差异，且有意保留——包内副本 = 打包时点的报告（29857 B / sha256 77f5d1c1…，见 dist/pack-final.json 的 docInsidePackage 与 dist/unpack/package/docs/ACCEPTANCE.md） | dist/pack-final.json（releasedBatch=t26、releasedSha256）、dist/dsh-screenshot-2.0.0.tgz、out/evidence/t26-unpack-check.txt |
| 2026-10-26（t28 + t30，captain 指派） | **t28 修复「按钮隐形」**：旧 client.js（3c58aaa2…，15616 B）渲染后靠 `insertBefore`/`MutationObserver` 把节点硬搬到话筒旁——落点与槽位不一致、依赖脆弱的 DOM 观察，实际表现就是按钮看不见（交付 tgz 里那份也是隐形版）。t28 删除全部搬运代码（`insertBefore`/`MutationObserver`/`findMic` 计数均为 0，仓库实测），改为一进 `conversation.input.right` 槽就自然渲染（该槽位于 activity/话筒左侧），并按 `--dsw-alias-label-secondary` / `--color-text-secondary` 修复浅色主题可见性；新 lib/client.js = **4979d9d9357b3a2a7a057999680b5907ad52e935b0dbf67a4966bfad3cdb5338**（14632 B），真实契约门禁 15/15 PASS、旧 bundle 负控仍按三类错误被拒。**t30 重打包（最终交付批次）**：t26 的 tgz（e8f2d613…，277387 B）包内仍是 3c58aaa2，交付物落后于代码，故用仓库当前字节重新 npm pack，解包逐字节核对 22/22 MATCH，再 install.ps1 -Force 幂等重装（node_modules/dsh-screenshot/lib/client.js == 仓库 == 包内；bundles 仍 23 无重复；profile package.json 未变）。全程未重启/未停止任何 DSH 进程、未 git commit | dist/pack-final.json（releasedBatch=t30）、dist/install-verify.json、out/evidence/t30-unpack-check.txt、out/evidence/client-contract.json、out/t30-captain-accept.log |
| 2026-10-26（t30 打包实测；**本行在打包之后写入，故只存在于仓库版**） | t30 最终交付批次实测：**dsh-screenshot-2.0.0.tgz = 279633 B（273.1 KiB）/ 22 files / unpackedSize 735223 / sha256 41f6cf382b752a80df1ee53bf84d0992884130751c009860c4e8da8c6e2086e3**（npm shasum 02d20deb7008da9abd79062c06edf138e16517fd）；dist/ 内同字节副本 sha256 相同。因为本报告随包交付，把这段数字写进包内会让包字节再变（自指），所以**包内副本不含本行**；这是 t30 之后仓库版与包内副本的唯一差异，且有意保留——包内副本 = 打包时点的报告（33209 B / sha256 745b89bd5c94b16f…，见 dist/pack-final.json 的 docInsidePackage 与 dist/unpack/package/docs/ACCEPTANCE.md） | dist/pack-final.json（releasedBatch=t30、releasedSha256）、dist/dsh-screenshot-2.0.0.tgz、out/evidence/t30-unpack-check.txt、out/evidence/client-contract.json |
| 2026-10-26（t32 + t33，captain 指派） | **t32 图标硬化 + 自检探针**：用户反馈剪刀图标仍看不见，t32 定位为「图标颜色依赖主题变量」+「未写死尺寸」两条风险，改为字面量色 `#8a8f98`（全文 `currentColor` 出现 0 次）、button/svg 内联尺寸（32×32 / 18×18 `display:block`）、hover 独立色 `.shot-btn:hover svg{stroke:#5b6169}`，并在挂载 ~800ms 后用 `collectProbe` 把真实 DOM 状态上报；host 半边新增 GET/POST `/shot/api/probe`（`d` 参数原样落盘 `%TEMP%/dsh-shot-probe.json`，非法 JSON 400），单测 `test/plugin/probe-route.mjs` exit 0。**t33 重打包并重装（本批次交付）**：lib/client.js 4979d9d9/14632 → **143b6cda/18825**、lib/index.js b38d06f0/15112 → **ff1ea269/16388**；npm pack 后解包 22/22 MATCH，`install.ps1 -Force` 幂等（bundles 23→23、deps 19→19、profile package.json 哈希不变），仓库/包内/已安装三处 `lib/client.js` 与 `lib/index.js` 同 sha256。**注意：probe 路由为宿主半边新增，需 DSH 重启后才会对运行实例生效；本次交付按纪律未重启，故实机 `curl '/shot/api/probe?d=...'` 预期 404（`/shot/api/version` 仍 200），路由正确性由 `test/plugin/probe-route.mjs` 单测 + 已安装代码 grep（`route('probe'` 命中 1 处）证明**。全程未重启/未停止任何 DSH 进程、未 git commit | dist/pack-final.json（releasedBatch=t33）、dist/install-verify.json、out/evidence/t33-unpack-check.txt、out/evidence/client-contract.json、out/evidence/t33-probe-route.log、out/t33-captain-accept.log |
| 2026-10-26（t33 打包实测；**本行在打包之后写入，故只存在于仓库版**） | t33 交付批次实测：**dsh-screenshot-2.0.0.tgz = 282767 B（276.1 KiB）/ 22 files / unpackedSize 745025 / sha256 24cf04a5f93a7bb00eee1bf2aca681b4339a26a706173f7548f4563a2f31473f**（npm shasum e6e0dfaac0d4ee1266446bd7f2ed49f72d881de5）；dist/ 内同字节副本 sha256 相同。三处字节一致（六值）：`lib/client.js` 18825 B / 143b6cda…、`lib/index.js` 16388 B / ff1ea269… 在仓库、tgz 解包、已安装 node_modules 三处完全相同；其余 21 条目逐字节 == 仓库。因为本报告随包交付，把这段数字写进包内会让包字节再变（自指），所以**包内副本不含本行**；包内副本 = 打包时点报告（37427 B / sha256 6837532d9681349e…，见 dist/pack-final.json 的 docInsidePackage 与 dist/unpack/package/docs/ACCEPTANCE.md） | dist/pack-final.json（releasedBatch=t33、releasedSha256）、dist/dsh-screenshot-2.0.0.tgz、out/evidence/t33-unpack-check.txt、dist/install-verify.json |
| 2026-10-26（t34 + t35 + t36，captain 指派） | **t34 文档诚实性 + 版本化门禁**：docs/VERIFY.md 重写为 634 行（新增「人工证据产出状态（截至 2026-10-26）」总表：out/evidence/manual/ 不存在、43 个文件全部未产出，75 处 manual 引用全部带「⚠ 未产出（待补人工截图）」标记；R1 段按真实结构重写：div.trailing → div.standardControls → 下一兄弟 div.activity 话筒，注册 conversation.input.right / shot-action / order 100，并写明「话筒展开时 standardControls 被隐藏，按钮随之消失」为已知限制）；tools/accept.ps1 新增（G-7 版本化门禁，替代 out/captain-accept.ps1；-NoBuild / -SkipPack / -SkipNative / -OutDir / -E2eTimeoutSec，前后 sha256 快照 + 逐条断言产物）；tools/e2e.ps1 新增 -SkipPack 与文档诚实门；client-contract 的 provenance 如实拆成 VERBATIM / GUARDRAILS。**t35 探针加固（M-1）**：/shot/api/probe 默认关闭（开关文件 %TEMP%\dsh-shot-debug.on 不存在即 404）、POST-only（非 POST → 405 + `Allow: POST`）、8KB 体积上限（超限 413 不落盘）、非法 JSON 400 不落盘、成功仅回 `{ ok: true }` 不回传路径；client 上报改为 POST JSON body 且失败不影响按钮。**t36 重打包并重装（本批次交付）**：lib/client.js 143b6cda/18825 → eb306de6/18891、lib/index.js ff1ea269/16388 → b5c99e60/16504；门禁 `pwsh -NoProfile -File tools/accept.ps1 -OutDir out/ev-t36` **全量模式 exit 0（22 PASS / 1 WARN bytes-unchanged，全量模式按设计允许重建与重打包）**，含 build errors=0、engine 8 checks、selftest 13 criteria + 8 PNG、longshot-probe frames=4、longshot 负控、crash-probe、client-contract 15/15 + 旧 bundle 负控三类被拒、plugin-smoke 8、docs 步、N1-crop-gate；跑完按 t25/t33 惯例把 bin/*.exe 按字节还原为 4dc8c308 / 925df12a 再打包（csc 输出非确定性）并复跑 EngineTests 8/8 与 --selftest 复核。**重要事实：探针默认关闭，且 /shot/api/probe 属宿主半边（lib/index.js）新增，需开关文件 + DSH 重启后才对运行实例生效；本批次按纪律未重启 DSH（探针实测由 captain 重启后再做），故实机 curl 预期 404，正确性由 test/plugin/probe-route.mjs 单测（6 类断言 exit 0）与已安装代码 grep 证明**。漂移基线：t34 之后基线文件归入可更新范围，本次执行 `node tools/client-contract.mjs --update-baseline --reason "t35 探针加固后重打包（t36 最终交付批次）…"`，fixture 由 4979d9d9 更新为 eb306de6（理由同时写入 fixture 的 reason 字段），此后 e2e 不再报 sha 漂移 WARN。全程未重启/未停止任何 DSH 进程、未 git commit | out/ev-t36/accept.log、out/ev-t36/accept.json、dist/pack-final.json（releasedBatch=t36）、dist/install-verify.json、out/ev-client/t36.json、out/ev-t36/t36-unpack-check.txt |
| 2026-10-26（t36 打包实测；**本行在打包之后写入，故只存在于仓库版**） | t36 最终交付批次实测（**取代 t33 的 24cf04a5…**）：**dsh-screenshot-2.0.0.tgz = 298119 B（291.1 KiB）/ 23 files / unpackedSize 784511 / sha256 4b9f52c19216fa711a7410b4de3370575d5def5b16c4fd8ab5ef0d7a6771e5e3**（npm shasum 851787e794e224e16a08f93af8f7c7ca68bb32e6）；dist/ 内同字节副本 sha256 相同，`npm pack --json` 清单与 package.json files 白名单逐条对应（23 = 原 22 + docs/POSTMORTEM.md，同属 docs/ 白名单）。解包核对 **23/23 MATCH、mismatches=0**（out/ev-t36/t36-unpack-check.txt；bin/SnipTool 4dc8c308、bin/EngineTests 925df12a、lib/client.js eb306de6、lib/index.js b5c99e60）。**三处字节一致（六值）**：lib/client.js 18891 / eb306de6 与 lib/index.js 16504 / b5c99e60 在「仓库 worktree = tgz 解包 = 已安装 node_modules/dsh-screenshot」三处完全相同（dist/install-verify.json allMatch=True）。包内断言：`insertBefore`/`MutationObserver`/`currentColor`/`conversation.input.activity` 注册计数均为 0，`route('probe'` 命中 1，探针开关 `dsh-shot-debug.on` 存在（默认关闭），`POST` 探针路径命中 2。门禁 `tools/accept.ps1 -OutDir out/ev-t36` → **exit 0，ACCEPT（22 PASS / 1 WARN bytes-unchanged，全量模式按设计允许重建与重打包）**；重建后 bin 已按字节还原为门禁验证过的 4dc8c308 / 925df12a。重装 `install.ps1 -Force` → **exit 0**，备份 `.backup-install-20261026-040739`，bundles 23→23（idempotent，无重复）、deps 19 不变、profile package.json 仍 `cc8bfbc5…`。三条 Verify 全 exit 0：契约 15/15 + 旧 2.0.0 bundle 负控三类被拒、probe-route 6 断言、plugin smoke 8 项（cli-sync 复核「无 hide 依赖」）。**诚实说明（探针）**：`/shot/api/probe` 属宿主半边，只在 DSH 启动时加载；本批次**按纪律未重启 DSH**，故运行中实例对该路由实测预期 404，正确性由 probe-route 单测（无开关 404 / GET 405+Allow / POST 200 `{ok:true}` / 落盘一致 / 413 / 400）与「已安装 index.js 字节 = 仓库字节」共同证明。**契约基线**：tools/fixtures/client-baseline.json 的 sha256 由 t30 的 4979d9d9… 更新为 eb306de6…（reason 已写入 fixture，fixture 现 402 B / b2ee81b3…、updatedAt 2026-10-25T20:06:06.567Z；证据见 out/ev-t36/t36-baseline-evidence.txt 与 out/ev-t36/t36-contract.log），因为 t35 探针改动改变了 client.js 字节而 hack 计数仍为 0。**自指说明**：本行数字写于打包之后，包内 docs/ACCEPTANCE.md 副本 = 打包时点仓库版（44001 B / 9ca06bc9…），不含本行；dist/ACCEPTANCE.md 与包内副本一致，仓库版（本文件）因追加本行而更新。 |
| 2026-10-26（captain 亲自执行，用户 m02421 裁决） | **v2.1：删除长截图 + 入口改左右键**。删除：`src/LongShot.cs`（整文件）、覆盖层长截图驱动/预览窗 `LongPreviewForm`、顶栏 `TopBarForm`、`Settings`（含 `%LOCALAPPDATA%\dsh-screenshot\settings.json`）、`--longshot-probe` 探针与 SelfTest 的 A3/A4/A5/A8/N1/N2/N2b/N3 断言、EngineTests 的 3 个长截图用例。新增：`lib/client.js` 左键 `hide:false` / 右键 `hide:true`（`onContextMenu` + `preventDefault`）、tooltip「左键保留窗口，右键最小化窗口」；`lib/index.js` 唤醒行 `hide=1|0`、冷启动 `--hide`/`--no-hide`。版本 2.1.0。自测：EngineTests 5/5、selftest 5 条 criteria + 6 张 PNG、e2e 10/10 步 PASS、plugin-smoke 8 pass、client-contract 15/15 + 旧 bundle 负控。 |
