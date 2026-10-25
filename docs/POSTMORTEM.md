# POSTMORTEM — DSH 截图插件 v2.0.0 客户端启动崩溃事故

- 撰写：reviewer（t29 事故复盘），2026-10-26 (+08:00)
- 证据来源：我自己独立复跑的命令与退出码（见 `out/evidence/REVIEW-T29.md`）、真实 DSH 日志、真实 Cordis / web 前端字节、git 历史
- 本文只陈述**已验证**的事实；每条结论后面直接给证据位置

---

## 1. 时间线（本地时间 +08:00；括号内为 UTC）

| 时刻 | 事件 | 证据 |
| --- | --- | --- |
| 10-25 15:30 → 18:00 | t1–t21 交付与三轮评审（含我 t7/t15/t21 三份评审）。**全程没有任何一次真实客户端启动验证** | `git log`：仅 4 个提交（`8680bf7` scaffold → `a868a02` → `d970517` feat → `51346e0` docs） |
| 10-25 18:30:55 | **首次安装**到 desktop profile（用的就是会崩的 client.js） | profile 目录 `.backup-install-20261025-183055/` |
| 10-25 18:41–18:44 | t25 连续 4 次重装（184152 / 184317 / 184405 / 184433） | 同名备份目录 |
| **10-26 02:21:58**（18:21:57Z） | **客户端 web boot 失败**：`web boot: 1 entry did not activate` / `dsh-screenshot: failed` | `…dsh-desktop/logs/crash-2026-10-25T18-21-57-998Z-web-boot.log` |
| 02:33:35 | 同一失败复发 | `crash-2026-10-25T18-33-35-591Z-web-boot.log` |
| 02:34:21 | 第三次复发（captain 在 ACCEPTANCE §9 引用的就是这份） | `crash-2026-10-25T18-34-20-986Z-web-boot.log`（654 B，栈顶 `resources/app/lib/main.js:12466`） |
| 02:53:42 | DSH 重新启动成功（此后**再无** web-boot 日志） | `Get-Process` 现存 DeepSeek Harness 进程 StartTime=2026-10-26 02:53:42；日志目录里最新一份仍是 02:34 的失败 |
| 03:00:30 | **t26**：发现交付 tgz 里仍是旧字节 client.js，重打包 + 幂等重装 | `.backup-install-20261026-030030/`、`out/evidence/t26-unpack-check.txt` |
| 03:10–03:16 | **t27** 真实契约门禁落地；**t28** 客户端归位（删 DOM 搬运 hack）；**t30** 用 t28 字节第三次重打包 + 重装 | `tools/client-contract.mjs`(8e401151)、`lib/client.js`(4979d9d9)、`.backup-install-20261026-031631/`、`out/evidence/t30-unpack-check.txt` |
| 03:19–03:35 | **t29**（本文）：我独立复跑三条门禁 + 负控根 + Verify 命令，并核对三处字节一致 | `out/evidence/REVIEW-T29.md` |
| 03:10–03:16 | **t31 门禁基线缺陷暴露**：契约门禁把旧基线 `3c58aaa2` 当"必须相等"，t28 换成 `4979d9d9` 后 e2e 第 8 步直接 fail —— 门禁把合法修复判成缺陷。t31 改为 **sha 漂移只 WARN、契约检查才决定成败**，基线移到 `tools/fixtures/client-baseline.json`，且只允许给通过全部检查的 bundle 写基线 | 我实测：把旧 bundle 当被测对象时门禁先打印 `WARN : sha drift … warning only`，随后仍按 4 项 FAIL 判 exit 1 —— 漂移与违约被正确区分（`client-contract.mjs:46-51/885-904`） |
| 03:16 之后 | **图标隐形暴露 → t32**：t28 落点正确但**图标看不见**。t32（plugin-dev）做图标硬化（显式尺寸/viewBox/stroke/主题色回退），`lib/client.js` → `143b6cda134cfe07`（18825 B），并在 `lib/index.js` 加 `/shot/api/probe` 调试路由（当前 `ff1ea26942131250`） | 我实测 `node tools/client-contract.mjs` 对 t32 字节 exit 0、15/15 通过、注册仍是 `conversation.input.right/shot-action@100`，负控仍三类齐拒；`insertBefore`/`MutationObserver`/`findMic` 计数依旧 0 |
| 待做 | **t33**：用 t32 字节重新打包 + 重装。**本文不绑定 tgz 字节**（t30 批次 `41f6cf38…` 即将被覆盖），交付批次以 t33 的 `dist/pack-final.json` 为准 | §3 G-3/G-4：交付物=仓库=已安装三处逐文件 sha256 必须一致，由 t33 现场重算 |

**根因（三条叠加，全部可在字节层面复核）**：崩溃版本 `lib/client.js` = sha256 `470abc0e7b6d35fb…`（14551 B），它就是 git 提交 `d970517` 里的那一份（我用 `git show d970517:lib/client.js` 取出算哈希 = `470abc0e7b6d35fb`，与 `tools/fixtures/client-470abc0e.js` 逐字节相同）。它违反三条真实契约：

1. **读未声明的服务**：它调用 `ctx.slots.inject(...)` 但**没有** `exports.inject = ['slots']`。真实 Cordis 的 context proxy 就是这么实现的：`cordis/src/reflect.ts:144` → `new Error(\`cannot get property "${prop}" without inject\`)`，压缩后同样存在于真实前端包 `dsh-web-frontend/dist/assets/index-CN7NIWNw.js`（`cannot get property` 出现在偏移 16463）。
2. **把描述符对象当回调传**：它写 `slots.inject(key, { id, order, component })`。真实 `ctx.effect()` 只接受可执行体，非函数返回物抛 `TypeError('Invalid effect')`（`cordis/src/fiber.ts:363/372/397`，压缩串 `Invalid effect` 在前端包里出现 3 次）。
3. **注册进已满的 single 槽**：它首选 `conversation.input.activity`，而该槽在真实定义里 `kind:"single"`（`dsh-client-ui-conversation/lib/client.js:19912-19915`），唯一注册位已被话筒按钮占用（`dsh-experimental-client-ui-voice-input/lib/client.js:2919`）。真实 register 抛：`single slot "<name>" already has a registration at priority <n>`（前端包偏移 487707）。

三条任一都足以让 entry 停在非 active 状态，而 web boot 的收尾断言是**硬失败**：`if (r.length > 0) throw new Error(\`web boot: ${n} entr… did not activate\`)`（前端包偏移 914507）——**一个插件的槽位注册错误 = 整个客户端页面打不开**。这就是"严重事故"的量级来源。

---

## 2. 为什么 25 个任务、4 轮 e2e、3 轮代码评审都没拦住

### 2.1 桩测试与真实契约之间的鸿沟（主因）

`tools/plugin-smoke.mjs` 的 `client-load` 检查在事故前做的是：造一个 `window.__ModuleLoader__ = { load(def){ captured = def } }`、一个 React Proxy 桩、一个 DOM 桩，然后 `captured.factory(requireStub)`，只要**返回的对象有 apply 函数**就判 pass（旧代码 366-371 行的判定就是 `typeof api.apply === 'function'`）。

这个桩**根本不实现契约**：
- 它不检查 `exports.inject` 是否声明了 `slots` —— 桩里的 `ctx` 是随便造的，读什么都有；
- 它的 `slots.inject` 若存在也只是记录参数，不做"回调必须是函数"的校验；
- 它没有"single 槽已被话筒占用"的世界状态。

于是崩溃版本在事故前的表现是：**8 项检查全绿**。门禁测的是"我的桩能不能被这个 bundle 调用"，而不是"真实壳能不能装载这个 bundle"。

### 2.2 评审者（包括我）对着假 API 审代码

我 t7（round 1）与 t15（round 2）都逐行读过 `lib/client.js`，两份评审都**没有**指出这三条违约。原因不是没读，而是**没有可对照的真实契约**：

- 仓库内唯一的"契约文档" `docs/INTERFACES.md` 在提交 `d970517` 时**一次都没有提到 slots / exports.inject**（我 `git show d970517:docs/INTERFACES.md` 全文 grep：`slots` 0 命中、`exports.inject` 0 命中）。它只写了"lib/client.js … 话筒左侧按钮"这种需求级描述。
- `docs/SPEC.md` R1 只说"输入框话筒按钮左侧新增截图按钮"，没有说槽位、kind、注册语义。
- 我 t7 的 G2 八项专项检查里"不自动发送"是通过读 `client.js` 的 `dispatchEvent(new ClipboardEvent('paste'))` 判定的 —— 我确认了"不会自动发送"，也就顺手默认了"注入方式是对的"。**评审没有对"插槽 API 用错了"建立任何检查项**，因为当时没人能给出正确答案。

结论：评审的失察是**结构性**的（无契约可对照），不是疏忽式的。修法只能是"把真实契约变成可执行门禁"，而不是"下次评审更仔细"。

### 2.3 打包物与仓库脱钩（第二因，t26 的成因）

t25 交付的 tgz（275239 B / `ea938d68…`）里 `lib/client.js` 仍是 `470abc0e`，而仓库与已安装副本已是修好的 `3c58aaa2`。**修好的代码从没进入交付物**。这说明"npm pack 的清单核对"（e2e 的 package 步只校验文件路径白名单）不校验内容哈希 —— 交付批次与仓库字节之间没有任何绑定。t26/t30 才补上解包逐文件 sha256 核对。

### 2.4 真实启动验证被系统性推迟（第三因）

事故前唯一一次真实启动就是 02:21–02:34 那三次崩溃。此前 25 个任务的验收全部是"无头/桩/脚本"证据，理由写在纪律里：**不重启 DSH**（会杀掉当前会话）。这条纪律本身没错，但它让"客户端能否装载该插件"永远落在验收范围之外，而没有任何人把这个缺口显式登记为风险。

---

## 3. 从今往后必须存在的门禁（缺一不可）

| # | 门禁 | 为什么必须 | 现状 |
| --- | --- | --- | --- |
| G-1 | **真实契约门禁**：用与真实 Cordis 同语义的模型跑 `apply(ctx)`，断言 ①未声明服务读取必抛 ②`slots.inject(key, cb)` 的 cb 必须是函数 ③single 槽冲突必抛 ④list 槽可共存且可 dispose ⑤`options.name` 必须等于注入键 | 本次事故的三条根因全部落在这里；桩加载测不出来 | **已存在**：`tools/client-contract.mjs`（15 项，含 5 项 `sem-*` 自检模型自身）。我独立跑：当前 bundle exit 0；把旧 bundle 当被测对象 exit 1，4 项 FAIL 命中三类错误 |
| G-2 | **负控必失败**：门禁必须拿"已知会崩的那一版"当输入并断言它被拒；负控通过（即旧版没被抓到）判 harness-broken | 没有负控的门禁无法自证有效性——G-1 若被写成"永远绿"，与事故前的桩无异 | **已存在**：`runNegative` 校验 fixture sha256 == `470abc0e…`（防漂移），要求三类错误齐备；`--update-baseline` 只允许给**通过全部检查**的 bundle 写基线（`client-contract.mjs:885-904`），这条设计正确 |
| G-3 | **交付批次 = 仓库字节**：打包后必须解包逐文件 sha256 比对，并把批次 sha 写进包外文件（避免自指） | t25→t26 的教训：代码修好了，交付物没修好 | **已存在**：`out/evidence/t30-unpack-check.txt`；我独立解包 22 条目核对，仅 `docs/ACCEPTANCE.md` 差 3 行（打包后追加的自指行，已在文中声明），其余全 MATCH；tgz `41f6cf38…` 与声明一致 |
| G-4 | **已安装副本 = 仓库字节**：装完必须回头读 `node_modules/<pkg>` 逐文件比对 | 同 G-3，且覆盖"装错包/装旧包" | **已存在**：`dist/install-verify.json`；我独立核对 installed == repo == package 三处 `4979d9d9357b3a2a` 全等 |
| G-5 | **真实启动验证**：至少一次"刷新页面/重启后 web boot 无 `did not activate`"的机器可读证据（成功也要留痕，不能只靠"没有崩溃日志"） | 事故的唯一暴露点就是真实启动；"无新崩溃日志"是弱证据 | **缺失**。现存 DSH 进程 StartTime=02:53:42，早于 t26(03:00) 与 t30(03:16) 两次重装 —— 也就是说**当前运行的进程从未装载过 4979d9d9**；日志目录里最新一份 web-boot 仍是 02:34 的失败。ACCEPTANCE 写"已安装，等待生效"是诚实的，但这一条不能算已验收 |
| G-6 | **UI 位置的真实证据**：R1"话筒左侧"需要一张真实渲染截图或 DOM rect 实测 | 见 §4：目前只有源码级推理 | **缺失**：`docs/VERIFY.md` 引用的 `out/evidence/manual/*.png` **32 个文件全部不存在**（我逐个 stat，present=15 / missing=32） |
| G-7 | **门禁不得破坏刚验收的交付批次**：跑门禁会重建 `bin/`、并由 e2e 的 package 步重写 tgz | 我实测：跑完 `out/captain-accept.ps1` 后 `bin/SnipTool.exe`、`bin/EngineTests.exe`、根 tgz 三处字节都变了（我为此先做快照再还原，还原后 tgz 回到 `41f6cf38…`） | **未处理**：建议门禁加 `-SkipPack` 或跑完自动还原，否则"验收过的批次"与"磁盘上的批次"会静默分叉 |

---

## 4. 位置与加固（t28）判定

**位置**：`lib/client.js:381-389` 注册进 `conversation.input.right`（`list` 槽，`dsh-client-ui-conversation/lib/client.js:19904-19907`）。真实渲染顺序（同文件 19077-19088）：

```
div.trailing
 ├─ div.standardControls   ← renderSlot("conversation.input.right") 在前，renderSlot("conversation.input.model") 在后
 ├─ div.activity           ← renderSlot("conversation.input.activity") = 话筒按钮
 └─ 停止/发送按钮
```

话筒在 `activity` 容器里（它是 `div.trailing` 的**下一个兄弟 div**），而我们的按钮在**它前面**的 `standardControls` 容器里，且排在同容器内 `conversation.input.model`（模型选择器 / block-picker）**左边** → **结构上落在话筒左侧、模型选择器左侧**，与 R1 自洽；用户已确认接受该落位（captain 记为"方案 A"）。因此位置结论成立，遗留的只是下面第 1 点的取舍，需要在 UI 文档里对用户可见。`dsh-cordis-client-runner/lib/client.js:3671-3675` 对该槽的官方描述也是 "Compact controls before the composer submit action."，与我的读码结论一致。

**但必须写清两个代价**（t28 报告没写）：
1. 话筒一旦进入"展开"态（`onActiveChange(true)`，见 voice-input `:1832-1848`），真实代码把 `div.standardControls` 整体 `hidden`（`:19079 hidden: activity`）——**我们的剪刀按钮会随之消失**，直到话筒收起。这是选择 `input.right` 而非 `activity` 换来的行为，属于需求级取舍，必须让 captain/用户知情。
2. 位置证据仍是**源码级推理**，没有真实 UI 截图（G-6 缺失）。我本轮无法补做：内置浏览器工具在本委派会话不可用（`dsh_browser_open` 报 `sidebar unavailable (this host supplied no conversation id)`），且纪律禁止重启 DSH。

**加固**：`insertBefore`/`MutationObserver`/`findMic`/`useEffect` 在 `lib/client.js` 中计数均为 0（我独立正则计数），DOM 搬运 hack 确实消失；`apply()` 只注册一次、无"已存在就渲染空白"分支；`exports.inject = ['slots']`（:362）与真实 `ctx.slots` 读取（:374）匹配；`rootCtx.locale` 的读取包在 try/catch 里（:8-25），未声明 `locale` 不会致命 —— 这一点设计正确。

---

## 5. 还没消除的"验证剧场"风险（诚实清单）

1. **C# 侧 selftest 仍有一半是自证**。`src/SelfTest.cs` 的 A1/A2/A4/A6 断言只是"PNG 存在且 >1000 B"（`:142-155`），画的是**合成 mock**，不执行覆盖层真实绘制路径；A3/A8 在 t22 才改成真断言（A3 驱动真 `Close()` 断言 state=cancel，A8 做几何+像素非均匀检查）。也就是说"高亮/暗化/尺寸标签长什么样"至今只有 mock 图，没有真机图。
2. **长截图探针仍依赖一个自建 helper 窗口**。`ScrollHelperForm` 是我们自己写的、自己响应 `WM_MOUSEWHEEL` 的窗口（`SelfTest.cs:804-831`），它证明"滚轮消息→覆盖层采样→拼接"这条链路通，但**不证明真实第三方应用**（浏览器/IDE）的滚动行为一致；t22 已把 60px/notch 改成 160px 来凑 marker 带，这属于为让断言通过而调整被测环境，需要标注。
3. **契约门禁是"模型"，不是真实壳**。`client-contract.mjs` 的三条串里只有两条是真实存在的（`cannot get property … without inject`、`single slot … already has a registration`）；`callback is not a function` 与 `options.name … does not match the injected slot` 在真实 cordis/前端包里**搜不到**（真实抛 `TypeError('Invalid effect')`，且 register 并不校验 name===key）。文件头注释写"message text matches the real DSH log"，这句**不准确**。行为判定仍然有效（两种串都代表同一失败类别），但注释误导后来人。
4. **模型的世界状态与真实不完全一致**：`PRE_EXISTING_SLOTS` 里的 `conversation.input.below`、`sidebar.footer` 在真实前端包里 0 命中；真实 list 槽要求 `options.id` 且同 id+priority 重复会抛（前端包 `case"list"`），模型只按 single/multi 二分；真实还有 `keyed`/`chain` 两种 kind 与"priority 越低越先渲染"的遮蔽语义，模型没有。**下一次事故可能正好落在这些没建模的分支上。**
5. **真实启动验证缺位**（G-5）与 **manual 截图 32 项缺失**（G-6）——见上表。
6. **`docs/VERIFY.md` 的 R1 证据段仍在描述被删掉的旧设计**：`:86` 写"按钮位置由 `ctx.slots.inject('conversation.input.activity', { order: -100 })` 首选注入，slot 不可用时回退 `conversation.input.right`，再回退为 DOM 插到话筒按钮前"。这三段在当前 `lib/client.js` 里**都不存在**。文档与代码不符，且它正是事故前那版的设计 —— 留着会让后来人以为 hack 还在。

---

## 6. 立即要做的三件事（按优先级）

1. **补 G-5**：由 captain 在人工窗口刷新页面（必要时重启 DSH），确认 web boot 无 `did not activate`，并把成功证据写成机器可读文件（例如 `out/evidence/web-boot-ok.json`，记录时间戳 + 已加载 entry 列表 + `lib/client.js` sha）。当前运行的进程（02:53:42）**没有**装载过 4979d9d9。
2. **补 G-6 + 修 §5.6**：真实 UI 截图（剪刀在话筒左侧、浅色主题可见）替换 `docs/VERIFY.md` 里 32 个不存在的 `out/evidence/manual/*.png` 引用；把 R1 证据段改成当前真实实现（`conversation.input.right` + `id: 'shot-action'` + `order: 100`），并写明"话筒展开态会隐藏本按钮"这个取舍。
3. **补 G-7 与 §5.3/§5.4**：门禁加 `-SkipPack`/跑完还原；`client-contract.mjs` 的文件头把"matches the real DSH log"改为"其中 2 条为真实串，1 条为等价自造串"；模型补 `list` 槽的 `options.id` 重复规则与 `keyed`/`chain` kind，并把 `PRE_EXISTING_SLOTS` 里不存在的两个键删掉或标注为假想键。

---

## 6.5 人工可执行验收（门禁之外，用户侧 4 步）

本次事故证明：绿灯的门禁不等于能用的产品。这一段不依赖任何桩/脚本，用户只需 4 步，**任何一步失败即视为未验收**：

1. **刷新页面**（客户端半边 `lib/client.js` 由 web boot 装载，刷新即生效）。若改的是宿主半边 `lib/index.js`，刷新无效，必须重启 DSH（见 §6.6）。
2. **看剪刀图标**：输入区右侧、话筒与模型选择器左边应出现一个**可见**的剪刀图标按钮，浅色与深色主题都要可见、hover 有底色。看不到 = t32 的图标硬化未生效（这正是 t28→t32 的返工点）。
3. **点击进截图模式**：≤500 ms 内出现全屏暗化覆盖层，鼠标移动时窗口/屏幕/任务栏被高亮并带尺寸标签；拖拽可框选。
4. **右键退出**：一次右键即退出且不产生截图；若进入时 DSH 被隐藏，退出后 DSH 必须回到前台。

自动化只能证明这 4 步的**前置条件**（契约可装载、三处字节一致、覆盖层无头证据），不能替代这 4 步本身。

## 6.6 热加载边界（本次事故的一半来源）

| 半边 | 装载时机 | 改仓库后的生效方式 | 在事故中的角色 |
| --- | --- | --- | --- |
| `lib/index.js`（host） | DSH 启动时由 profile 加载器 import（Node ESM，求值后常驻进程） | **必须重启 DSH** | t25 写的"host 已加载 /shot/api/version → 200"只证明**当时那个进程**加载了它，不证明加载的是哪一版字节 |
| `lib/client.js`（web） | 每次 web boot 由前端装载 | **刷新页面即可** | 崩溃发生在这一侧；重装后无需重启就能生效——但**没有任何门禁验证过 boot 成功**（§3 G-5） |

推论（今后写进交付声明的固定格式）：任何"已安装"的结论必须同时给出 (a) 装的是哪一版字节、(b) 当前运行实例是否已装载该字节、(c) 装载后的 boot 结果证据。t30 的 ACCEPTANCE 给了 (a) 并诚实写了"等待生效"，缺的是 (b)/(c) 的正面证据；t33 应把 (c) 补成机器可读文件（例如 `out/evidence/web-boot-ok.json`：时间戳 + 已激活 entry 列表 + `lib/client.js` sha）。

## 6.7 本轮（t29）新发现的一条真实缺陷：`/shot/api/probe` 是任意内容写盘原语

t32 为调试 UI 加的这条路由（`lib/index.js:412-439`）把请求里任意 JSON `payload` 直接 `writeFileSync(join(tmpdir(), "dsh-shot-probe.json"))`，并把**绝对路径**回给前端。问题：
- 它是 GET 可读的写路由（`methods: ['GET', 'POST']`），与 F-9 修完的"写路由 POST-only"原则相反；
- 内容无大小上限、无 schema 白名单（只有 `receivedAt` 是它自己加的），任何同机页面都能反复写；
- 它回传 `path`，正是 F-9 里刚从 `/last`、`/state`、`/version` 剥掉的绝对路径暴露。

影响有限（写入路径固定、仅 %TEMP% 单文件、无仓库外目录逃逸），但它把刚收住的本地攻击面又开了一道缝，且它是**调试用途**——不该随交付包发布。建议 t33 之前：改为 POST-only + body 上限（复用 `MAX_BODY_BYTES`）+ 只回 `{ok:true}` 不回路径，或直接把探针留在 client 侧 `console`/`localStorage` 而不落盘。

## 7. 一句话结论

事故不是"代码写错了没看出来"，而是**我们所有的绿灯都建立在自造桩上，而真实壳对桩的任何约定都不负责**。t27 的契约门禁 + 负控是这条链上第一道真正有牙的门（我独立验证它对旧版必红、对新版必绿）；但在"真实启动"与"真实 UI"两项补上之前，v2.0.0 的客户端半边仍只能说**已修复、未验证生效**，不能说已验收。
