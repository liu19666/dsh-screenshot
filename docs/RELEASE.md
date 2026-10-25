# DSH 截图插件 v2 — 发布说明（构建 / 打包 / 安装 / 回滚）

本文件说明如何把一个可用的 v2 版本从源码变成 DSH 桌面 profile 里的插件，以及出问题时如何
安全回滚。所有命令都在仓库根目录（`dsh-screenshot-v2/`）执行。

## 版本

- 当前版本号以 `package.json` 的 `version` 为准（v2.1 交付时为 `2.1.0`，语义化版本）；插件路由 `/shot/api/version` 返回同一版本号（只返回版本号，不暴露结果目录等本机路径），可用来确认 profile 里装的是哪一版。
- 版本号只由 Plugin 负责人在 `package.json` 中提升；本文件不规定新版本号，避免与
  `docs/SPEC.md` 的发布纪律冲突。
- 兼容矩阵：
  - 运行平台：Windows 10/11 x64（`os: win32`）。
  - 运行时：.NET Framework 4.8（系统自带，用 `csc.exe` 编译，无 NuGet 依赖）+ Node.js ≥ 20。
  - 宿主：DSH 桌面端 desktop profile（`~/.dsh/profiles/desktop`）。
- 版本与证据的对应关系：每个发布版本应附带一次 `tools/e2e.ps1` 的
  `out/evidence/report.json`（含 `gitHead`），以及 `docs/VERIFY.md` 的 R1–R30 人工确认记录。

## 构建

```powershell
# 全量构建（含引擎测试程序），产物：bin/SnipTool.exe、bin/EngineTests.exe
pwsh -NoProfile -File build.ps1 -Tests

# 只构建主程序
pwsh -NoProfile -File build.ps1
```

- 编译器：`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`（.NET Framework 4.8），
  语言级别为 C# 5（不用字符串插值、`?.`、`nameof`、表达式体成员、`out var`）。
- 产物：`bin/SnipTool.exe`（WinExe，覆盖层 + 编辑器 + 热进程服务）、
  `bin/EngineTests.exe`（目标识别与长截图算法的无界面测试）。
- 构建后自检：`pwsh -NoProfile -File tools/e2e.ps1 -SkipNative` 或完整 `tools/e2e.ps1`。
- 构建失败排查：`out/evidence/logs/build.log` 里有完整 stdout/stderr（`tools/e2e.ps1` 生成）。

## 打包

```powershell
# 生成 dsh-screenshot-<version>.tgz（默认落在仓库根目录）
pnpm pack

# 或者指定目录
pnpm pack --pack-destination out/dist
```

- 打包内容由 `package.json` 的 `files` 决定：`bin/`、`lib/`、`src/`、`cordis.patch.yml`、`docs/`；
  `main` 为 `lib/index.js`，`exports` 暴露 `.`、`./client`、`./package.json`。
- 打包后自检：
  1. `tar -tzf dsh-screenshot-<version>.tgz` 确认包含 `lib/index.js`、`lib/client.js`、`bin/SnipTool.exe`、
     `cordis.patch.yml`。
  2. `node tools/plugin-smoke.mjs --root . --quiet` 退出码 0（桩加载宿主与客户端两半；这是冒烟的唯一实现，
     `test/plugin/smoke.mjs` 只是按 `import.meta.url` 求根后转发它）。
  3. 记录 tgz 大小与 sha256，便于安装时确认用的是同一个包。
- `*.tgz` 已在 `.gitignore` 中，不要提交构建产物。
- 也可以让证据链代劳：`tools/e2e.ps1` 的 package 步骤执行 `npm pack --json` 并校验 tgz 必含
  `lib/index.js`、`lib/client.js`、`bin/SnipTool.exe`、`package.json`、`cordis.patch.yml`，且不夹带
  `tools/`、`test/`、`out/`、`.agent-teams/`、`install.ps1`、`build.ps1`，同时逐条核对 `package.json` 的
  `files` 白名单。

## 安装

安装到 DSH desktop profile，由仓库根的 `install.ps1` 完成。**先看计划，再实跑**：

```powershell
# 1. 只打印计划：备份路径、pnpm 命令、bundles 增量、重启提示；不写任何文件
pwsh -NoProfile -File install.ps1 -WhatIf

# 2. 实跑（默认 profile：DSH_PROFILE_DIR / DSH_HOME+DSH_PROFILE / ~/.dsh/profiles/desktop）
pwsh -NoProfile -File install.ps1 -Tgz out/dist/dsh-screenshot-2.1.0.tgz

# 指定 profile（推荐先在临时 profile 里演练）
pwsh -NoProfile -File install.ps1 -ProfileDir <profile目录> -Tgz <tgz路径>
```

安装脚本做且只做三件事：

1. **备份**：把 profile 的 `package.json` 与 `cordis.patch.yml` 复制到
   `<profile>/.backup-install-<yyyyMMdd-HHmmss>/`，并写 `manifest.json`（含安装前的
   `dsh.profile.bundles` 列表）与 `pnpm-add.log`。
2. **安装**：在 profile 目录执行 `pnpm add "file:<tgz>"`。失败时自动把上面两个文件还原，再以
   exit 1 结束（不会留下半安装状态）。
3. **注册**：把包名追加到 `package.json` 的 `dsh.profile.bundles` 数组末尾；写入前会校验
   原有条目名称与顺序完全保留、新数组长度 = 原长度 + 1，校验失败则还原备份并退出 1。

最后打印「**需重启 DSH 生效**」。脚本**不会**重启 DSH、不会停止 DSH 进程、不会修改
`resources/app` 或任何其它 bundle。

手动等价步骤（脚本不可用时）：

```powershell
$p = "$env:USERPROFILE\.dsh\profiles\desktop"
New-Item -ItemType Directory -Force "$p\.backup-manual-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item "$p\package.json","$p\cordis.patch.yml" "$p\.backup-manual-*"
Set-Location $p
pnpm add "file:<tgz绝对路径>"
# 然后手工在 package.json 的 dsh.profile.bundles 末尾追加 "dsh-screenshot"
```

重启 DSH 后的验收：会话页输入框话筒按钮左侧出现剪刀按钮；点击进入覆盖层；按
`docs/VERIFY.md` 的 R1–R30 抽查关键项（至少 R1、R2、R10、R11、R22、R23、R25）。

## 回滚

```powershell
# 用最近一次备份还原 profile 的 package.json 与 cordis.patch.yml
pwsh -NoProfile -File install.ps1 -Rollback

# 指定 profile
pwsh -NoProfile -File install.ps1 -Rollback -ProfileDir <profile目录>

# 只看回滚计划
pwsh -NoProfile -File install.ps1 -Rollback -WhatIf
```

- 回滚会打印「需重启 DSH 生效」，同样不会重启 DSH。若希望顺带清理 `node_modules` 里已安装的包，
  在 profile 目录执行 `pnpm install`（回滚后的 package.json 已不含该依赖）。
- 完全手工回滚：把 `<profile>/.backup-install-<stamp>/package.json` 与 `cordis.patch.yml`
  覆盖回 profile 根目录即可；`dsh.profile.bundles` 也随之恢复到安装前。
- 回滚后确认：`dsh.profile.bundles` 不再包含 `dsh-screenshot`；重启 DSH 后剪刀按钮消失，
  其余插件行为不变（对比 `manifest.json` 的 `bundlesBefore`）。
- 备份目录不要删除，直到新版本稳定运行；也可以整体打包备份目录用于工单复现。

## 已知限制

- 仅支持 Windows（`os: win32`）。Linux/macOS 无法运行 `bin/SnipTool.exe`。
- 依赖 .NET Framework 4.8 的系统自带 `csc.exe`，因此构建机必须是 Windows；没有 NuGet 依赖，
  也就无法使用现代 C# 语法（C# 5 限制见「构建」）。
- 安装需要本机 pnpm；没有 pnpm 时 `install.ps1` 会在第 2 步前明确报错退出，不会半途修改文件。
- 安装脚本按 profile 的 `package.json`/`cordis.patch.yml` 两个文件备份与回滚；若用户在同一
  时间段内手工改过这两个文件，回滚会覆盖这些手工改动。
- 长截图只能捕获「在选区内随滚轮滚动」的内容；不随滚轮滚动（虚拟化列表一次性渲染、原生窗口
  自绘而忽略滚轮）的界面可能拼不出完整长图，需要改用普通截图。
- 马赛克是对当前画布像素的破坏性编辑，插件不提供「还原原像素」；取消/不保存即可放弃整张编辑。
- 覆盖层按像素坐标工作：显示器热插拔、运行中修改缩放比例后，需退出覆盖层重新进入才能拿到新布局。
- 单实例约束由 `SnipTool.exe --serve` 热进程提供；若该进程被外部强行结束，下一次点击会重建，
  但此前的「最近一次截图」若已写入临时文件则仍然可用。
- `SnipTool.exe --selftest`（由 `tools/e2e.ps1` 的 selftest 步骤调用）只能证明 PNG 存在且尺寸合理，
  「高亮是否准确、暗化是否均匀、工具图标是否美观」仍需按 `docs/VERIFY.md` 人工判断。
- 崩溃日志固定追加到 `%TEMP%\dsh-snip-error.log`：没有轮转、没有大小上限，也不受 `DSH_SNIP_DEBUG` 门控
  （只有详细跟踪日志 `%TEMP%\dsh-text.log` 需要该变量）；`--crash-probe` 只写一条探针记录，不制造真实崩溃。
- 最近一次截图与会话状态放在系统临时目录 `%TEMP%\dsh-screenshot-v2`，随临时目录清理而消失；换用户或换机器后
  历史截图不保留（需要长期保存请用编辑器的「保存」落盘）。
- 证据目录 `out/evidence/` 默认不纳入版本控制；发布时请把 `report.json` 与 `SUMMARY.md`
  附在发布说明里（不要提交二进制 PNG 或 tgz）。

## 运行时文件与排障

- 结果目录：宿主默认用 `%TEMP%\dsh-screenshot-v2\`；若该路径含非 ASCII 字符（中文用户名等），改用
  `%PUBLIC%\dsh-screenshot-v2`。宿主用 `--out` 显式传给原生程序，管道消息里也带 `out=`；原生程序以
  `--out` 为准，并把**实际**落盘路径回写状态文件。两边目录对不上时 `/shot/api/state` 返回 `error`
  （不静默降级），排障见 `out/evidence/` 与 `%TEMP%\dsh-snip-error.log`。
  - `dsh-snip-last.png`：最近一次「确定」的 PNG，`GET /shot/api/last` 以 base64 返回它（响应里只有
    `{mtime,bytes,name,data}`，不含绝对路径）。
  - `dsh-snip-state.json`：会话结果 `{"result": "ok"|"cancel", "at": <ticks>, "file": <绝对路径>, "error"?: <消息>}`，
    是「本次会话是否出图、图在哪」的唯一权威来源；`GET /shot/api/state` 只透传 `at`/`result`/`error`，
    `at` 变化表示「又结束了一次会话」。
- 崩溃日志：`%TEMP%\dsh-snip-error.log`，未处理异常无条件追加（`HH:mm:ss` + 异常栈）。
- 详细跟踪：设置 `DSH_SNIP_DEBUG=1` 后 `%TEMP%\dsh-text.log` 才有输出。
- 原生进程：`SnipTool.exe --serve --parent <pid> --out <dir> --client`，命名管道 `\\.\pipe\dsh-snip-show`，
  唤醒消息 `show theme=dark|light lang=zh|en client=1 out=<dir>`；父进程退出或空闲 180 秒后自行退出。
- 路由（宿主 `lib/index.js`，挂在 DSH 端口上）：`/shot/api/capture`、`/shot/api/snip`（别名）、
  `/shot/api/state`、`/shot/api/last`、`/shot/api/lang`、`/shot/api/version`。
- `--client` 的含义：原生程序只把 DSH 前置、**不**合成 `Ctrl+V`；粘贴由 `lib/client.js` 合成一次 `paste`
  完成，因此确定后图片只出现一次。若手工再按 `Ctrl+V`，会再粘一张（剪贴板里仍留有该图）。

## 交付检查清单

```markdown
- [ ] build.ps1 -Tests 退出码 0，bin/SnipTool.exe 与 bin/EngineTests.exe 存在
- [ ] tools/e2e.ps1 退出码 0，out/evidence/report.json 中无 fail 步骤
- [ ] tools/e2e.ps1 -Strict 退出码 0（无 pending）
- [ ] tools/e2e.ps1 共 10 步全 PASS（含 selftest 逐项 summary.json 全 passed、longshot-probe：ok=true、frames>=2、composedHeight>selHeight、crash-probe：ok=true、afterBytes > beforeBytes、docs：VERIFY 30/30 + RELEASE 6/6）
- [ ] crash_probe.json 的 marker 出现在 %TEMP%\dsh-snip-error.log 尾部（日志是追加写的）
- [ ] docs/VERIFY.md 的 R1–R30 已按表格记录结论与证据路径
- [ ] pnpm pack 产物已自检（tar 列表 + plugin-smoke）
- [ ] install.ps1 -WhatIf 输出包含 备份 / pnpm add / dsh.profile.bundles / 需重启 DSH 生效
- [ ] 在临时 profile 演练过安装与回滚
- [ ] 版本号、README 与 cordis.patch.yml 一致
```
