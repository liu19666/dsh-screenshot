# 长截图回退记录（2026-10-26）

## 决定
用户裁决：**长截图回退到 v2.0.0（旧版）行为**，不再尝试"失败可见 + 部分拼接"的改法。

## 为什么要回退
v2.0.0 装到 profile 后，用户报告：框选区域内滚轮不更新预览图（长截图功能不可用）。
overlay-dev 在 t38 上做了一轮"滚轮后 140ms 静默窗口取样 + FindVerticalOverlap + 失败提示 + MaxComposedHeight"的改动，
自测（build / --selftest / --longshot-probe / --crash-probe 全 exit 0）通过，但 captain 用真实覆盖层 + 真实注入滚轮黑盒复测（`out/cap-e2e/probe2.ps1`、`out/cap-e2e/drive6.ps1`）发现 4 个硬缺陷：

1. **静态内容被误报失败**：静态目标 3 次滚轮，只拼进 1 帧（旧版能拼到 4 帧），随即 `stitchFailed=true`，
   notice=「拼接失败：选区内容有动态变化，已保留可拼接部分」。
2. **没有滚轮也加帧**：动画腿 trace 在 `hook=0`（一次滚轮都没发）时帧数已 1→2→3；GUI 里预览显示「(4帧)」而目标窗口 `scrollY=0`。
3. **拼接位移算错**：每次滚 120px，offset 实际是 160/240/280 → composed 图会错位。
4. **GUI 链路更糟**：滚轮后预览面板消失、退回 hover 态，按 Enter 无任何反应（h4 与 h6 字节完全相同）。

因此 t38 不满足其契约（静态不回归、失败可见但不许静默/误报），captain 不予验收。

## 回退后的状态（当前仓库 = 已安装的 2.0.0 行为）
用恢复后的二进制（`git checkout` 到 HEAD 的 `bin/SnipTool.exe`，sha256 `4dc8c308…`）实测：

- **静态内容**：`out/cap-e2e-static/` —— 预览「长截图预览 (4帧)」，预览里能看到 MARKER 红带，
  Enter 直接进编辑器，编辑区里是拼好的长图（ROW #9…#19 + MARKER），无弹窗。**可用**。
- **选区内有动态内容**：`out/cap-e2e/` —— 预览停在「(1帧)」，滚轮没有任何反馈，Enter 直接进编辑器。
  **即用户最初报告的症状，作为已知限制保留**。

## 搁置的尝试（未提交，`out/` 被 gitignore）
`out/wip-t38/` 保存了 t38 的完整工作，供以后重做参考：

| 文件 | sha256 前 16 位 |
| --- | --- |
| SnipTool.cs | `fe82ccaac35b2f81` |
| SelfTest.cs | `73cedd6a4816d408` |
| longshot-e2e.ps1 | `db66d2a2d3193931` |
| LongShotTarget.cs | `86b83fd550745b88` |

注意：这批文件依赖 `--longshot-live` 探针契约（见 `docs/INTERFACES.md` 的历史版本），
与回退后的 src 不兼容；重做时应先重新确认契约，而不是直接覆盖 src。

## 教训
- 探针自证不算证据：`--longshot-live` 的绿灯与真实覆盖层链路是两条路，必须用真实输入黑盒复测。
- 改动"加帧判据"这类时序逻辑，必须给出逐 tick trace 并核对位移数值（offset），不能只看"帧数涨了"。
