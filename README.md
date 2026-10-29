# 地下城勇士 Q 版 · DNFM Arena

Q 版 DNF 手游核心玩法复刻：横版动作战斗、三段连招、两档技能、怪物波次推进、掉落成长、结算评级。Godot 4.7.2 + GDScript。

> 状态：已发布 v1.0.0（GitHub Release + 通知邮件已发出）

## 是什么

一局完整可玩的地牢清版流程：

- 三段普通攻击连招（伤害 4 / 4 / 6，续接窗口 1.2s，第三段触发 combo3 事件与连击 HUD）
- 两档技能：蓄力斩（伤害 14 / CD 1.2s）、鬼影斩（范围 62 / 伤害 26 / CD 3.0s）
- 两种敌人 AI：哥布林（HP26 / 速56 / 攻距26）与壮汉（HP70 / 速38 / 攻距36），追击、近身挥击、受击闪红与击退
- 5 波刷图推进（14 只敌人），波间 1.6s 间隔、单个 0.35s 入场
- 掉落金币与经验球，拾取自动吸附；升级提升血量上限与伤害
- 结算页给出 S/A/B/C 评级与六项数据
- Q 版视觉：4 段渐变背景、错缝砖墙、3 根石柱、4 支呼吸火把、8 套动画

## 怎么跑

```bash
# 桌面运行
cd D:/my-projects/games/game-4/dnfm-arena/godot
"D:/apps/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe" --path .

# 无头冒烟（35 项检查）
"D:/apps/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe" --headless --path . res://smoke_test.tscn

# 截图（必须带窗口）
"D:/apps/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe" --path . res://screenshot.tscn -- play "<绝对路径>.png"

# Android 导出
export JAVA_HOME="D:/apps/jdk-17"
export ANDROID_HOME="D:/apps/android-sdk"
export ANDROID_SDK_ROOT="D:/apps/android-sdk"
"D:/apps/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe" --headless --path . --export-debug Android "D:/my-projects/games/game-4/dnfm-arena/build/dnfm-arena.apk"
```

> `--path` 必须指向含 `project.godot` 的那一级，即 `dnfm-arena/godot`。

## 操作

| 按键 | 作用 |
|---|---|
| ← → / A D | 移动 |
| 空格 / W / ↑ | 跳跃 |
| J | 普通攻击（三段连招） |
| K | 蓄力斩 |
| L | 鬼影斩 |
| 空格 / 回车 | 开始 |
| R | 重新挑战 |

移动端：左下摇杆 + 右下跳/攻/技/鬼四键。

## 产物

| 产物 | 位置 | 说明 |
|---|---|---|
| Android APK | `build/dnfm-arena.apk` | 30.5 MB，v1.0.0 (code 1)，arm64-v8a，182 条目 |
| 发布清单 | `dist/latest.json` | 含 SHA-256 与下载地址 |

线上分发：`github.com/zjj1769404838/dnfm-arena`（Release v1.0.0）。

## 目录结构

```
dnfm-arena/
├── game.json                  管线配置（genre beat_em_up / style hibit）
├── assets/
│   ├── raw/                   AI 生成原图
│   ├── final/                 像素化后的帧 + meta.json
│   └── export/                精灵表 + Aseprite JSON + godot/*.tres + index.json
├── docs/
│   ├── GDD.md                 策划书
│   ├── contracts.md           模块契约与数值真源（8 章）
│   ├── README.md              详细交付说明（7 章）
│   ├── stage_log.md           阶段日志
│   └── shots/                 标题/战斗/结算截图
├── godot/
│   ├── project.godot
│   ├── main.tscn
│   ├── scripts/               9 个 .gd（player/enemy/world/pickup/hud/touch/main/screenshot/game_config）
│   ├── assets/                export 精灵表 / sfx / fonts
│   └── export_presets.cfg
├── build/                     构建产物（不入库）
└── dist/                      发布产物（APK 不入库，清单入库）
```

## 代码分层

| 脚本 | 行数 | 职责 |
|---|---|---|
| `player.gd` | 598 | 三段连招 / 技能 / 受击 / 连击计数 / 升级 |
| `enemy.gd` | 405 | 追击 AI / 攻击判定 / 受击反馈 / 死亡 |
| `world.gd` | 302 | 地牢场景（背景/砖墙/石柱/火把/地面碰撞） |
| `pickup.gd` | 163 | 金币与经验球掉落、吸附拾取 |
| `hud.gd` | 507 | HUD / 横幅 / 标题页 / 结算页 |
| `touch_controls.gd` | 552 | 摇杆与四键触屏（按下当帧写轴） |
| `main.gd` | 535 | 状态机 / 波次编排 / 音频 / 结算 |
| `game_config.gd` | 93 | 全部数值常量真源 |
| `screenshot.gd` | 59 | 状态截图脚本 |

模块间只通过信号与契约方法通信，契约见 [docs/contracts.md](docs/contracts.md)。

## 已知限制

- 本机无 emulator / adb devices 为空，**未做真机安装与触控实测**
- 结算页无触屏重开按钮（只有键盘 R）
- 只有一个关卡，没有 BOSS
- 敌人没有受击/死亡动画，技能没有范围特效
- 成长只有等级，没有装备与技能树
- 音效复用同门工程，未重制
- 只出了 Android debug APK，未做 Windows / Web 端
