# dnfm-arena 工程契约（各模块并行实现的唯一真源）

> 所有模块只依赖本文件列出的接口与常量，不互相 import 业务脚本。
> 常量真源：`godot/scripts/game_config.gd`（class_name GameConfig）。

## 0. 通用约定

- Godot 4.7.2，GDScript，640×360，tile 16，锁定横屏，`gl_compatibility`，
  `textures/canvas_textures/default_texture_filter=0`（像素不糊）。
- **节点位置约定**：角色/敌人节点的 `position` = **脚底坐标**（贴地时 y = 地面行 y）。
- **精灵图约定**：所有精灵 96×96，脚底锚点 → `AnimatedSprite2D.centered = false`，
  `offset = Vector2(-48, -96)`。
- **精灵表来源**：`res://assets/export/index.json`，每个 action 一条横排精灵表；
  动画名 = index.json 里的 `action` 字段（如 `idle_breathe` / `walk` / `attack1` /
  `skill_slash` / `ghost_slash` / `goblin_walk` / `brute_walk`）。
  用 `SpriteFrames` + `AtlasTexture` 构造，`duration = frame_durations[i] / 1000.0`。
- 所有模块**全代码建场景**，不手拉 .tscn 引用（除 main.tscn 只挂 main.gd）。
- **信号方向**：角色/敌人只发信号或回调玩法层，不直接改玩法层状态。

## 1. GameConfig（常量真源）

```gdscript
class_name GameConfig extends RefCounted

const TILE := 16
const VIEW_W := 640
const VIEW_H := 360
const LEVEL_W := 60            # 60 格 = 960px 宽
const LEVEL_H := 22            # 22 格 = 352px 高
const GROUND_ROW := 18         # 地面行（脚底 y = 18*16 = 288）

# 玩家
const PLAYER_SPEED := 132.0
const PLAYER_ACCEL := 1500.0
const PLAYER_JUMP_V := -430.0
const PLAYER_GRAVITY := 1300.0
const PLAYER_COYOTE := 0.10
const PLAYER_BUFFER := 0.12
const PLAYER_JUMP_CUT := 0.45
const PLAYER_MAX_HP := 12
const PLAYER_INVULN := 0.7
const COMBO_WINDOW := 1.2      # 连段续接窗口（秒）

# 连招与技能
const ATTACK_CD := 0.30
const SKILL_CD := 1.2
const GHOST_CD := 3.0
const ATTACK_DAMAGE := [4, 4, 6]        # 三段普攻逐段递增
const ATTACK_ACTIVE := [0.16, 0.16, 0.22]  # 各段判定框开启时长
const SKILL_DAMAGE := 14
const SKILL_ACTIVE := 0.30
const GHOST_DAMAGE := 26
const GHOST_ACTIVE := 0.36
const ATTACK_RANGE := 30.0        # 判定框前伸距离（相对朝向）
const ATTACK_HEIGHT := 30.0       # 判定框高度
const ATTACK_CENTER_Y := -26.0    # 判定框中心相对脚底的高度
const SKILL_RANGE := 40.0
const GHOST_RANGE := 62.0

# 成长
const EXP_PER_LEVEL := 30         # 升 1 级所需经验（累进：每级 ×1.35）
const LEVEL_HP_STEP := 4          # 每级最大生命 +4
const LEVEL_DMG_STEP := 0.15      # 每级伤害系数 +15%

# 配色（Q 版暗石地牢）
const COL_BG_TOP := Color(0.16, 0.13, 0.24)
const COL_BG_BOTTOM := Color(0.09, 0.07, 0.14)
const COL_WALL := Color(0.24, 0.21, 0.32)
const COL_WALL_LINE := Color(0.18, 0.15, 0.26)
const COL_FLOOR := Color(0.34, 0.30, 0.42)
const COL_FLOOR_TOP := Color(0.46, 0.41, 0.55)
const COL_TORCH := Color(1.0, 0.72, 0.32)
const COL_HP := Color(0.88, 0.24, 0.28)
const COL_HP_BG := Color(0.24, 0.08, 0.10)
const COL_EXP := Color(0.42, 0.78, 1.0)
const COL_GOLD := Color(1.0, 0.83, 0.32)
const COL_TEXT := Color(0.96, 0.95, 0.98)
const COL_DIM := Color(0.72, 0.70, 0.80)
const COL_ACCENT := Color(1.0, 0.83, 0.32)
const COL_DANGER := Color(1.0, 0.45, 0.38)
const COL_PANEL := Color(0.09, 0.08, 0.14, 0.94)
const COL_OVERLAY := Color(0, 0, 0, 0.62)

const FONT_PATH := "res://assets/fonts/zpix.ttf"
const SFX_DIR := "res://assets/sfx/"
const EXPORT_INDEX := "res://assets/export/index.json"
```

## 2. 玩家 `godot/scripts/player.gd`（actors）

`class_name Player extends CharacterBody2D`

- 节点位置 = 脚底坐标。
- 碰撞：collision_layer=1，collision_mask=4（地形层）。碰撞体
  `RectangleShape2D` size `Vector2(18, 40)`，position `Vector2(0, -20)`。
- 精灵：AnimatedSprite2D，centered=false，offset=(-48,-96)。
- 攻击判定：Area2D `attack_box`，collision_layer=0，collision_mask=2，
  `RectangleShape2D` size `Vector2(30, 30)`，position `Vector2(30 * facing, -26)`。
- 公开成员（main.gd 会读）：
  - `hp: int`、`max_hp: int`、`level: int`、`exp: int`、`gold: int`
  - `combo: int`（当前连段数）、`combo_timer: float`
  - `alive: bool`、`invuln: float`、`facing: int`
- 公开方法：
  - `setup(sf: SpriteFrames)` —— 注入玩家精灵表
  - `take_damage(amount: int, from: Vector2) -> void`
  - `heal(amount: int) -> void`
  - `add_gold(n: int) -> void`
  - `add_exp(n: int) -> void`（内部处理升级：max_hp += LEVEL_HP_STEP，回满，level++）
  - `reset_for_new_game() -> void`
  - `reset_stats_keep_hp() -> void`（重开关卡时用）
- 信号：
  - `attacked(kind: String)` —— kind ∈ "attack" / "skill" / "ghost" / "combo3"
  - `damaged(amount: int)`
  - `died()`
  - `jumped()`
  - `combo_changed(count: int)`
  - `leveled_up(level: int)`
  - `hit_enemy(enemy: Node2D, damage: int)` —— 命中反馈（用于飘字/特效）
- 输入动作（运行时注册，main.gd 负责注册，player 只读）：
  `p_left` / `p_right` / `p_jump` / `p_attack` / `p_skill` / `p_ghost`
- 行为要求：
  1. 移动：加速度趋近 `PLAYER_SPEED`，朝向随移动翻转，精灵 flip_h。
  2. 跳跃：土狼时间 + 输入缓冲 + 松键截断（照抄常量）。
  3. **连招**：连续按 `p_attack` 触发三段普攻，第 1/2/3 段伤害 4/4/6，
     判定框开启时长 0.16/0.16/0.22，段间可被 `COMBO_WINDOW` 续接；
     每次命中把 `combo` +1，`combo_timer = COMBO_WINDOW`，超时归零。
     第 3 段发 `attacked("combo3")`（用于更重反馈）。
  4. **技能**：`p_skill` 释放蓄力斩（伤害 `SKILL_DAMAGE`，范围 `SKILL_RANGE`，
     冷却 `SKILL_CD`），`p_ghost` 释放鬼影斩（伤害 `GHOST_DAMAGE`，范围 `GHOST_RANGE`，
     冷却 `GHOST_CD`，**范围更大、可同时命中多个敌人**）。
  5. 受击：无敌帧 `PLAYER_INVULN` + 击退 + 闪红；hp 归零发 `died()`。
  6. 动画切换优先级：攻击/技能 > 跳跃 > 移动 > 呼吸待机。
     动画名必须来自 index.json 的 action 字段。

## 3. 敌人 `godot/scripts/enemy.gd`（actors）

`class_name Enemy extends CharacterBody2D`

- `setup(target: Node2D, game: Node, kind: String, sf: SpriteFrames)`。
- 两种 kind：
  | kind | HP | 速度 | 攻击距离 | 伤害 | 攻击间隔 | 经验 | 金币 | 体型 |
  |---|---|---|---|---|---|---|---|---|
  | `goblin` | 26 | 56 | 26 | 4 | 0.9 | 6 | 3 | 18×38 |
  | `brute` | 70 | 38 | 36 | 9 | 1.5 | 16 | 8 | 26×50 |
- 敌人精灵：goblin 用 `goblin_walk` 动画表，brute 用 `brute_walk`；
  复用玩家 `SpriteFrames` 不适用（各自动画表分开建），由 main.gd 注入对应表。
- AI：追击玩家 → 进入攻击距离后停下并挥击（每次挥击回调
  `game.on_enemy_attack(self, damage)`）→ 受击闪红 + 击退（brute 击退减半）→
  hp 归零时 `queue_free()` 并回调 `game.on_enemy_killed(self)`。
- 敌人之间要**轻微互斥**避免完全重叠（同层横向推开）。
- 公开成员：`hp: int`、`kind: String`、`dead: bool`。

## 4. 世界与掉落 `godot/scripts/world.gd` + `godot/scripts/pickup.gd`（level）

`godot/scripts/world.gd`：`class_name DungeonWorld extends Node2D`

- `build() -> void`：
  - 背景：CanvasLayer(layer=-10) + 全屏渐变（顶部 `COL_BG_TOP` → 底部 `COL_BG_BOTTOM`，
    用 `GradientTexture2D` 或多个 ColorRect 分段），像素风可用 3~4 段色阶横条。
  - 后墙：砖块纹理（用 `Polygon2D`/`ColorRect` 画砖缝网格，颜色 `COL_WALL`/`COL_WALL_LINE`），
    覆盖可视高度；再画 2~3 根**石柱**（竖直 ColorRect + 柱头）制造纵深。
  - 地面：`StaticBody2D`（collision_layer=4，mask=0），地面行 `GROUND_ROW`，
    整段地面合并**一个矩形碰撞体**；视觉上画地砖（每 16px 一格，顶面亮色 `COL_FLOOR_TOP`）。
  - 火把：左右两侧各 1~2 个，`Polygon2D` 圆 + `COL_TORCH`，带正弦呼吸缩放动画。
  - 装饰：碎石/骨头用小 `ColorRect` 随机摆放（固定种子，保证可复现）。
- 公开：`ground_y: float`（= GROUND_ROW * TILE）。

`godot/scripts/pickup.gd`：`class_name Pickup extends Area2D`

- `setup(kind: String, value: int, sf: SpriteFrames)` —— kind ∈ "gold" / "exp"。
- 外观：`gold` 用黄色菱形 `Polygon2D` + `COL_GOLD`；`exp` 用蓝色圆珠 + `COL_EXP`；
  两者都带上下浮动动画（sin）。
- 玩家靠近自动拾取：检测到 `target`（玩家）距离 < 14 → 通知
  `game.on_pickup(kind, value)` 并 `queue_free()`。
- 掉落规则由 main.gd 决定（敌人死亡时按概率在尸体位置生成）。

## 5. UI `godot/scripts/hud.gd`（interface）

`class_name GameHUD extends CanvasLayer`

- `setup(font_path: String)`：加载 `zpix.ttf`（三段回退：
  `ResourceLoader.load` → `FontFile.load_dynamic_font` → 字节写入 data）。
- 公开方法：
  - `show_hud()` / `hide_hud()`
  - `set_hp(hp: int, max_hp: int)`
  - `set_exp(exp: int, need: int)`
  - `set_level(level: int)`
  - `set_gold(gold: int)`
  - `set_wave(wave: int, total: int)`
  - `set_combo(count: int)` —— count <= 0 时隐藏；>= 2 时显示并放大脉冲
  - `show_banner(title: String, sub: String)` / `hide_banner()`
  - `show_title(best_score: int)` —— 开场标题页（标题 + 操作说明 + “按空格开始”）
  - `show_result(win: bool, stats: Dictionary)` —— 结算页：
    stats 键 `waves` / `kills` / `max_combo` / `gold` / `level` / `exp` / `time_sec`
  - `hide_all()`
- 视觉要求（Q 版地牢 + 暗底衬）：
  - 全部文字带描边（`font_outline_color` 黑色 + `outline_size` 2~3）。
  - HUD 面板用半透明深色底衬 `Color(0,0,0,0.35)` + 4px 内边距，避免压背景看不清。
  - 字号只用 12 / 24（zpix 是 12px 点阵，只能取 12 的整数倍）。
  - 血条：底 `COL_HP_BG`，前景 `COL_HP`；经验条：底暗色，前景 `COL_EXP`；
    金币用 `COL_GOLD`，等级用 `COL_ACCENT`。
  - 连击数：屏幕中上方偏右，`COL_ACCENT`，随连段数增大字号（12 → 24 → 36 不行，
    只用 12/24），带 alpha 脉冲。
  - 结算页：全屏遮罩 `COL_OVERLAY` + 居中面板 `COL_PANEL` + 标题 + 6 行数据 + 评级
    （S/A/B/C，按 waves/kills/max_combo 算），底部“按 R 重新挑战”。
  - 标题页：标题「地下城勇士 Q版」+ 操作说明（←/→ 移动、↑ 跳、J 连招、K 蓄力斩、
    L 鬼影斩、R 重开）+ “按 空格 / 回车 开始”。

## 6. 触控 `godot/scripts/touch_controls.gd`（touch）

`class_name TouchControls extends Control`

- 左侧静态摇杆（**按下当帧就写轴**，不能等 ScreenDrag）+ 右侧动作键
  （跳 / 攻 / 技 / 鬼）。
- 死区 `0.20`（Godot 官方默认），摇杆热区半径 44 逻辑px，按钮热区 ≥ 44 逻辑px。
- 通过 `Input.action_press/action_release` 注入，**不直接改角色状态**。
- 多指安全：按 `event.index` 追踪摇杆手指；抬起立即归零防漂移。
- 只在 PLAY 状态显示（由 main.gd 控制 `set_active(bool)`）。

## 7. 主控 `godot/scripts/main.gd`（lead）

`class_name DnfmArena extends Node2D`

- 状态机：`enum State { TITLE, PLAY, WIN, LOSE }`。
- 流程：TITLE →（空格/回车/点屏）→ PLAY →（清完全部波次）→ WIN；
  玩家 hp 归零 → LOSE；结算页按 R → 重开回 PLAY。
- 波次表（5 波）：
  ```
  WAVES = [
    {"goblin": 2, "brute": 0},
    {"goblin": 3, "brute": 0},
    {"goblin": 2, "brute": 1},
    {"goblin": 3, "brute": 2},
    {"goblin": 4, "brute": 2},
  ]
  ```
  每波从右侧随机 x 生成，间隔 0.35s 逐个入场；清空后 1.6s 进入下一波并显示横幅。
- 掉落：敌人死亡时按 `goblin` 60% gold / 40% exp、`brute` 40% gold / 60% exp 生成掉落。
- 公开回调（enemy / pickup 调用）：
  - `on_enemy_killed(enemy: Node2D) -> void`
  - `on_enemy_attack(enemy: Node2D, amount: int) -> void`
  - `on_pickup(kind: String, value: int) -> void`
- 公开成员：`state`、`wave`、`kills`、`max_combo`、`elapsed`、`player`、`hud`。
- 事件接线：玩家 `attacked` → 播音效 + 命中反馈；`combo_changed` → HUD；
  `leveled_up` → HUD + 提示条；`died` → LOSE。
- 音频：音效池 6 个 + BGM（`AudioStreamWAV`，`loop_end = int(get_length()*mix_rate)-1`，
  **写 0 会导致永不循环**）；音效键：jump / hit / hurt / coin / powerup / win / lose。

## 8. 自检 `godot/smoke_test.gd`（lead）

- `extends Node`（**不要 extends SceneTree**），用 `await get_tree().physics_frame` 等帧
  （**不能用 process_frame**，无头模式下位移恒 0）。
- 覆盖断言：
  1. 场景加载 / 玩家节点 / 精灵表注入（动画数 ≥ 6 且含 idle_breathe/walk/attack1/skill_slash/ghost_slash）
  2. 移动位移 > 40px 且播 walk
  3. 跳跃抬升 > 10px
  4. 攻击：播 attack1、判定框开启后按时关闭
  5. **连招**：连续 3 次 `p_attack` → `combo` 达到 3，第 3 段发 `combo3`
  6. 技能：`p_skill` 伤害高于普攻；`p_ghost` 冷却更长
  7. 敌人：能受击、追击到 60px 内、死亡回调计分
  8. 波次：清空第 1 波后进入第 2 波，敌人数增加
  9. 掉落：击杀后生成 pickup，拾取后 gold/exp 增加
  10. 升级：给足够经验 → level 提升且 max_hp 增加
  11. 胜负：玩家死亡 → LOSE；R 重开 → PLAY 且 stats 归零
  12. 音频：SFX ≥ 5 条、BGM 在播
- 输出格式：`checks=N fails=M` + `SMOKE PASS/FAIL`，`get_tree().quit(0/1)`。
