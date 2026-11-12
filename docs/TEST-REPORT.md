# 测试记录（2026-10-26）

环境：Windows 11、Godot 4.6.1、Node 24.19、Pi 1.4.0、DeepSeek `deepseek-flash`（真实网络调用）。

## 1. Pi SDK 接入

```
node tools/sdk-test.mjs
```

- 两个独立 `AgentSession`，不同 system prompt，互不串味。
- 首个响应：约 1.7s 出首字，1.9s 完成。
- `tools/session-test.mjs`：写入会话、关闭、重新 `SessionManager.open`，能记住「我的代号是 GHOST，我欠你一条命」。

## 2. 真实 LLM 任务协议

```
node tools/bridge-test.mjs   # 需要 8791 上运行 real bridge
```

验证了 `contracts` / `crew` / `run_start` / `run_beat` / `dialogue` / `settle` 全部返回可解析结构；中文 JSON 委托的 `twist` 具备可回收的具体性。

## 3. 完整循环（mock）

```
godot --headless --path game -- --test-loop --ws=ws://127.0.0.1:8792/ws
```

输出：

```
=== NEON VEIL LOOP TEST ===
[ok] bridge handshake
[ok] contracts response ok
[ok] 3 contracts generated
[ok] accept contract
[ok] crew response ok
[ok] hire 2 crew
[ok] run_start response ok
[ok] run_beat 1..4 response ok
[ok] contract finalized
[ok] settlement computed
[ok] settle response ok
=== RESULT: PASS | beats=4 net=1104 ===
```

## 4. 完整循环（真实 LLM + 自由输入）

```
godot --headless --path game -- --test-loop
```

- 真实生成 3 份委托、3 名佣兵、行动开场、4 个节拍、收尾结算。
- 第 2 拍使用自由输入「让针贴在摄像头死角，等我把走廊画面循环起来」，以玩家「入侵」技能判定并成功。
- 结果：`PASS`，4/4 成功，`net=600`，退出码 0。
- 存档中的 `last_settlement.highlights` 可见：

```
沈鸦用技术完成「让沈鸦先掐掉读卡口的临时线再开门」，成功（9 vs DC6）
TESTER用入侵完成「让针贴在摄像头死角，等我把走廊画面循环起来」，成功（12 vs DC9）
沈鸦用潜行完成「让沈鸦趁盲区直接取走排期表原件」，成功（10 vs DC9）
沈鸦用潜行完成「让沈鸦从排风管道撤到后巷」，成功（10 vs DC9）
```

## 5. UI 路径截图

| 路径 | 截图 |
|---|---|
| 标题 / 继续 | `captures/visual-title2.png`、`captures/live-visual-inbox.png` |
| 建角 | `captures/visual-creation.png` |
| 委托板（新视觉） | `captures/visual-inbox3.png` |
| 团队 / 佣兵头像 | `captures/visual-crew-mercs.png` |
| 计划 / 蜃楼评估 | `captures/visual-plan.png` |
| 行动 / 现场画面与队友头像 | `captures/visual-run-mercs.png` |
| 行动 / D10 判定 | `captures/visual-roll-scene6.png` |
| 谈判 / 全息肖像 | `captures/visual-chat.png` |
| 结算 / 数字滚动 | `captures/visual-settle2.png` |
| 装备 / 档案 | `captures/visual-gear.png`、`captures/visual-archive2.png` |
| 真实加载中 | `captures/visual-loading.png` |
| 标题 | `captures/visual-title2.png` |

UI 截图由 Godot `get_viewport().get_texture().get_image()` 在实际渲染窗口中导出，非设计稿。

## 6. 存档 / 继续

- 完成真实行动后关闭游戏，再以 `--debug-continue` 启动：恢复日期、信用点、声望、热度、队伍、委托与世界编年史，并重新连上 Pi 会话。
- `captures/live-visual-inbox.png` 显示恢复真实存档后的委托板（第 1 天，3 份委托，3 名佣兵）；点击接受后进入 PLAN 的实测截图见 `captures/live-plan.png`。

## 7. 启动/停止脚本

```
pwsh -File start.ps1 -NoLaunch
# [bridge] 已就绪 (pid ...)
# mode=real model=deepseek-flash pi=1.4.0  （约 2.6s）

pwsh -File stop.ps1
# [bridge] 已停止 (pid ...)
```

- 在 Windows PowerShell 5.1 下也验证通过（健康检查使用 `curl --noproxy`，避免系统代理把 localhost 卡住）。
- `start.ps1` 会启动后台 Node bridge，并启动 Godot 游戏窗口；`stop.ps1 -IncludeGame` 可一并关闭游戏。

## 8. 当前运行状态

- Bridge：`http://127.0.0.1:8791/health`，`mode=real`，`model=deepseek-flash`，`piVersion=1.4.0`。
- 游戏进程：`Godot_v4.6.1-stable_win64`，窗口标题 `NEON VEIL (DEBUG)`，已加载恢复后的真实存档，当前停在委托板（`captures/live-visual-inbox.png`）。
- 真实 LLM 探针：`tools/probe-live.mjs` 通过 WebSocket 请求蜃楼对话，返回 `ok=true`、`degraded=false`，流式文本正常。

## 9. 视觉与动效阶段验证

2026-10-26 下午，按用户反馈接入生成素材与表现层动效，保持玩法、存档结构、玩家不露面的设定不变。

### 9.1 素材接入

- `game/assets/generated/neon-city-background.png`（1672×941）：启动时通过 `Image.load_png_from_buffer` 读入并创建 `ImageTexture`；用于标题与全部主界面。
- `game/assets/generated/fixer-mirage-portrait.png`（1145×1374）：同样运行时加载；Shader 键控白色背景并做青色调色、扫描线、横向撕裂、闪烁；用于标题、通讯、委托详情、计划评估、结算、加载。
- `game/assets/generated/neon-operation-scene.png`（1672×941）：RunView 的 `SITE CAM 03 / LIVE` 现场面板；Shader 暗化、雨幕、扫描线、暗角与节拍平移，鼠标视差；文字栏独立，不遮挡画面。
- `game/assets/generated/mercenary-portrait-atlas.png`（1254×1254，2×2 透明底）：`AtlasTexture` 按格裁切；按职业确定性映射到 4 格，旧存档无需迁移；CrewView 卡片/详情与 RunView 现场队友栏使用，带轻微全息扫描、闪烁、轮廓辉光和详情呼吸。
- 启动日志：`[art] city=true fixer=true operation=true mercs=true`（headless 与窗口运行均出现）。

### 9.2 动效验证

| 动效 | 实现 | 验证 |
|---|---|---|
| 雨幕/视差 | `ui/Background.gd` Shader + `_process` 视差 lerp | 窗口运行背景随鼠标/时间变化 |
| 全息肖像呼吸/闪烁 | `ui/Portrait.gd` Shader + Tween | 标题/通讯/委托详情/加载均可见 |
| 卡片入场 | `FX.stagger` | 委托/团队/装备列表错峰淡入 |
| 按钮悬停 | `UI._hover_button` Tween | 1.022× 缩放 + 原有边框 |
| 阶段切换 | `RunView._render_stage_state` + 处境文字淡入 | `visual-run-mercs.png` 显示当前阶段高亮、处境文字与队友头像 |
| D10 滚动/判定反馈 | `RunView._play_roll_animation` + `FX.flash` | `visual-roll-scene6.png`（定格 10 / 大成功） |
| 结算数字滚动 | `FX.money_count` | `visual-settle2.png` 显示含 +¥220 战利品的净收入 |
| 热度/警报脉冲 | `Main._refresh_header` + `RunView._update_status` | 运行截图可见热度/警报状态；代码路径已实测 |
| 现场画面 | `RunView` SITE CAM Shader + `_process` 视差 | `visual-run-mercs.png` |
| 佣兵头像 | `AtlasTexture` + `MercPortrait` Shader + 职业映射 | `visual-crew-mercs.png`、`visual-run-mercs.png` |
| 页面/通讯入场 | `FX.fade_in` / `FX.message_in` | 视图与消息淡入 |

### 9.3 保持玩法与存档

- 未修改 `GameState` 存档版本、字段或结算规则；仅新增表现层和调试参数。佣兵头像索引为显示时按职业派生，旧存档无需迁移；如未来写入 `portrait_index` 也可直接覆盖。
- 动效测试前备份了真实存档 `tools/live-save-backup.json`，测试后恢复；恢复后以新构建继续真实战役，`captures/live-visual-inbox.png` 为实际运行窗口。
- 行动输入仅在 D10 结算动画的约 1.2 秒内禁用；其余 Tween 不阻塞点击与自由输入。

### 9.4 当前运行

- Bridge：8791，real，`deepseek-flash`，Pi 1.4.0，0 errors。
- 游戏：新构建，窗口 `NEON VEIL (DEBUG)`，已恢复存档并进入委托板（第 1 天、¥900、3 份委托、3 名佣兵）。
- 现场图：RunView 左栏已接入 `neon-operation-scene.png` 的 `SITE CAM 03 / LIVE` 面板；`visual-run-mercs.png` 为实际渲染，`visual-roll-scene6.png` 为判定时的暗场反馈。
- 佣兵头像：旧存档三名佣兵（撤离/交涉/重装）自动映射到图集 3/2/1 格，CrewView 卡片、详情页和 RunView 队友栏均正常，无需迁移存档。
- 真实点击验证：实际在运行窗口中点击「接受委托」，进入 PLAN，信用点从 900 变为 1300（预付款 400），蜃楼评估肖像与计划 UI 正常；随后恢复测试前的存档备份并重新启动，最终停在委托板。
- 真实 LLM 探针仍通过；新构建未改动桥接协议。

## 10. 已知的非致命问题

- 真实模型偶尔会在台词里与机制数值轻微不一致（例如嘴上抱怨报价，但仍被机制判定接受）；数值由桥接层夹取、Godot 裁决，不会破坏状态。
- 首次真实生成（尤其委托）需要 15–30 秒；加载层有计时和阶段提示。
- 截图用视口导出，不含操作系统窗口边框。










