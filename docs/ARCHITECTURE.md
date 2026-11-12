# 架构与协议

## 1. 角色分工

| 层 | 负责 |
|---|---|
| Godot | 界面、输入、状态机、掷骰、数值结算、存档、音效 |
| Node bridge | WebSocket 服务、任务路由、Prompt 组装、流式转发、JSON 校验、超时、离线回退 |
| Pi agent SDK | 模型调用、会话持久化、自动重试/压缩、流式事件 |
| LLM | 人物、委托、现场叙事、对话、后果与钩子 |

关键原则：**LLM 只提出叙事与建议效果，Godot 决定实际数值**。所有钱、热度、伤势、忠诚、成功/失败、警报都由 Godot 计算并夹取。

## 2. 传输

- 游戏连接 `ws://127.0.0.1:8791/ws`（可用 `--ws=` 覆盖，用于多实例测试）。
- 每帧一条 JSON，UTF-8，LF 分隔。
- 服务端无第三方依赖，自带最小 RFC6455 实现（`bridge/ws.mjs`）。

### 客户端 → 服务端

```json
{"type":"hello","campaign":"cp_...","player":"GHOST"}
{"type":"ask","id":"q1_...","task":"run_beat","input":{...},"stream":true,
 "actor":{"kind":"crew","id":"crew_x","persona":{...}}}
{"type":"status"}
{"type":"reset"}
{"type":"set_mode","mode":"mock"}
```

### 服务端 → 客户端

```json
{"type":"ready","campaign":"cp_...","mode":"real","model":"deepseek-flash",
 "pi":{"version":"1.4.0"}}
{"type":"accepted","id":"q1_..."}
{"type":"delta","id":"q1_...","text":"雨在澜港从不直落……"}
{"type":"done","id":"q1_...","ok":true,"narration":"...","data":{...},
 "ms":4180,"usage":{...},"degraded":false}
{"type":"error","id":"q1_...","message":"..."}
```

- `delta` 只用于对话/现场叙事。桥接层会把 `<<<NARRATION>>>` / `<<<DATA>>>` 协议过滤成纯叙事流，避免 UI 看到协议标记。
- `done` 中的 `data` 已由桥接层做字段校验、枚举夹取、数组截断和 ID 映射。

## 3. 任务清单

| task | 输出 | 说明 |
|---|---|---|
| `contracts` | JSON `{contracts:[...]}` | 3 份委托，含隐藏 `twist` |
| `crew` | JSON `{crew:[...]}` | 3 名佣兵，含性格、秘密、能力、分成 |
| `run_start` | tagged narration + JSON `{beat}` | 开场 + 第一个节拍 |
| `run_beat` | tagged narration + JSON `{effects,next,reveal,crew_line}` | 判定后推进 |
| `settle` | tagged narration + JSON extras | 收尾、战利品、世界变化、钩子 |
| `plan_audit` | JSON `{verdict,risk_score,notes,line}` | 蜃楼评估计划 |
| `event` | JSON `{title,text,severity,effects,hook}` | 休整时的世界事件 |
| `dialogue` | 纯文本 + 标记 | 中间人/佣兵自由对话 |
| `recruit` | 纯文本 + 标记 | 招募谈判 |

### 输出标记（对话）

对话正文末尾可以有：

```
[DEAL: pay=+200 advance=300 intel="..."]
[BOND: +1]
[SECRET: ...]
[WARN: ...]
[ACCEPT]
[REFUSE: ...]
```

桥接层把标记从正文剥离，限制数值上限（报酬最多 +20%，预付款最多 30%），Godot 决定应用于当前委托还是正在谈判的委托。

### 结构化叙事协议

```
<<<NARRATION>>>
雨在澜港从不直落……
<<<DATA>>>
{"effects":[...],"next":{...}}
```

解析器对 JSON 围栏、尾逗号、前后噪声做容错；解析失败时保留已流出的叙事，用本地引擎补齐缺失的机制数据，避免玩家卡死。

## 4. 状态与记忆

- 每名角色（GM、蜃楼、每个佣兵）在 Pi 中是独立 `AgentSession`。
- 会话文件：`bridge/sessions/<campaign>/<timestamp>_<uuid>.jsonl`，索引 `index.json` 以 `kind:id` 映射。
- 会话可跨 bridge 重启恢复，因此角色会记住上一次对话。
- 同时，Godot 每次请求都会注入精简世界状态：
  - 玩家代号/专精/日期/信用点/声望/热度/技能
  - 当前委托（包括隐藏 twist，供 GM 使用）
  - 队伍能力、忠诚、伤势、分成
  - 最近编年史（最近 10 条）
  - 已知标记 flags
- 因此记忆有两层：Pi 的对话记忆 + Godot 的权威世界状态。前者提供语气与关系连续性，后者保证数值与事实不漂移。

## 5. 结算

```
gross   = pay × (0.3 + 0.7 × successes/4) × (0.8 if alarms>=3)
net     = max(0, gross − advance − crew_cuts − injury_cost + loot)
min_net = pay × 8%（successes>=2 且未中止时保底）
```

判定：`d10 + 能力 + 装备/支援` 对 `DC`。

```
DC = 6 + 风险(1..3) + 节拍(0..3) + 手段修正 + 行动风险 + 伤势 + 警报修正
大成功: total >= DC+4；成功: >= DC；勉强: >= DC−2；否则失败
```

Godot 记录每拍的高光、警报、成功数，结算页以表格展示；LLM 只负责写“这一单留下了什么”。

## 6. 回退与可用性

- 模型调用失败 → 当前请求使用 `mock.mjs` 的本地叙事引擎，并在 UI 标记 `LINK DEGRADED`。
- 连续失败 2 次 → 90 秒熔断，直接走本地引擎；模型恢复后自动重试真实链路。
- `BRIDGE_MODE=mock` 或 `start.ps1 -Mock` 可完全离线演示。
- 超时 150 秒；期间 UI 显示加载计时。
- WebSocket 断开时 Bridge 自动重连并握手；未完成请求收到错误，界面提示重试。

## 7. 表现层（视觉阶段）

- `UI.city_texture` / `UI.fixer_texture` / `UI.operation_texture` / `UI.mercenary_atlas` 在启动时从 `game/assets/generated/` 读取 PNG（`Image.load_png_from_buffer` → `ImageTexture`），不依赖编辑器导入。
- `ui/Background.gd`：全屏 TextureRect + Shader。Shader 内完成暗化调色、双层雨幕、扫描线、暗角、数据扫光；`_process` 只更新两个 uniform（视差、缩放），鼠标视差做 lerp。
- `ui/Portrait.gd`：全息肖像组件。Shader 对白色背景做键控透明、青色调色、扫描线、横向撕裂与闪烁；Tween 做呼吸缩放和透明度循环；`FrameCorners` 绘制 HUD 角标。用于标题、通讯、委托详情、计划、结算、加载层。
- `autoload/FX.gd`：统一表现层工具，不持有游戏状态。提供 `flash`、`pulse`、`fade_in`、`stagger`、`message_in`、`money_count`、`number_count`、`stamp`。
- RunView 的 `SITE CAM 03 / LIVE` 面板使用 `neon-operation-scene.png`：Shader 暗化、雨幕、扫描线、暗角与节拍平移；`_process` 做鼠标视差；右侧独立文字栏保证 HUD 清晰。
- `mercenary-portrait-atlas.png` 由 `UI.mk_merc_portrait` 用 `AtlasTexture` 裁成 4 格（2×2），按职业映射到稳定索引；`ui/MercPortrait.gd` 提供轻微全息扫描、闪烁、轮廓辉光与详情页呼吸。映射是派生数据，不修改存档字段。
- 卡片入场、按钮 hover、视图切换、通讯消息、阶段脉冲、D10 滚动、结算数字滚动、热度/警报脉冲都由这些 Tween 实现；除骰子结算动画期间短暂禁用行动输入外，不阻塞输入。
- 工作台在背景之上加 46% 暗色 scrim；标题界面隐藏 scrim 并使用左侧渐变遮罩，兼顾城市可见性与文字可读性。

## 8. 扩展点

- 新任务：在 `prompts.mjs` 添加 prompt + 在 `server.mjs` 的 `normalizeResponse` 添加校验。
- 新装备：`GameState.GEAR_CATALOG`；在 `compute_bonus` / `compute_settlement` 中生效。
- 新事件：`event` 任务或结算 extras；Godot 负责实际效果。
- 新角色：为 crew 生成卡片并 `ensureActor`；系统 prompt 由 `crewSystem` 构造。



