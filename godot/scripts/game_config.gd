# -*- coding: utf-8 -*-
## GameConfig —— dnfm-arena 全部常量的唯一真源。
## 其它脚本一律引用这里的常量，不要再各自硬编码数值。
class_name GameConfig extends RefCounted

# ---------- 画布与关卡 ----------
const TILE := 16
const VIEW_W := 640
const VIEW_H := 360
const LEVEL_W := 60
const LEVEL_H := 22
const GROUND_ROW := 18

# ---------- 玩家手感 ----------
const PLAYER_SPEED := 132.0
const PLAYER_ACCEL := 1500.0
const PLAYER_JUMP_V := -430.0
const PLAYER_GRAVITY := 1300.0
const PLAYER_COYOTE := 0.10
const PLAYER_BUFFER := 0.12
const PLAYER_JUMP_CUT := 0.45
const PLAYER_MAX_HP := 12
const PLAYER_INVULN := 0.7
const COMBO_WINDOW := 1.2

# ---------- 连招与技能 ----------
const ATTACK_CD := 0.30
const SKILL_CD := 1.2
const GHOST_CD := 3.0
const ATTACK_DAMAGE := [4, 4, 6]
const ATTACK_ACTIVE := [0.16, 0.16, 0.22]
const SKILL_DAMAGE := 14
const SKILL_ACTIVE := 0.30
const GHOST_DAMAGE := 26
const GHOST_ACTIVE := 0.36
const ATTACK_RANGE := 30.0
const ATTACK_HEIGHT := 30.0
const ATTACK_CENTER_Y := -26.0
const SKILL_RANGE := 40.0
const GHOST_RANGE := 62.0

# ---------- 成长 ----------
const EXP_PER_LEVEL := 30
const LEVEL_HP_STEP := 4
const LEVEL_DMG_STEP := 0.15

# ---------- 配色（Q 版暗石地牢） ----------
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
const COL_EXP_BG := Color(0.10, 0.18, 0.28)
const COL_GOLD := Color(1.0, 0.83, 0.32)
const COL_TEXT := Color(0.96, 0.95, 0.98)
const COL_DIM := Color(0.72, 0.70, 0.80)
const COL_ACCENT := Color(1.0, 0.83, 0.32)
const COL_DANGER := Color(1.0, 0.45, 0.38)
const COL_PANEL := Color(0.09, 0.08, 0.14, 0.94)
const COL_OVERLAY := Color(0, 0, 0, 0.62)
const COL_HUD_BG := Color(0, 0, 0, 0.35)

# ---------- 路径 ----------
const FONT_PATH := "res://assets/fonts/zpix.ttf"
const SFX_DIR := "res://assets/sfx/"
const EXPORT_INDEX := "res://assets/export/index.json"

# ---------- 波次 ----------
const WAVES := [
	{"goblin": 2, "brute": 0},
	{"goblin": 3, "brute": 0},
	{"goblin": 2, "brute": 1},
	{"goblin": 3, "brute": 2},
	{"goblin": 4, "brute": 2},
]
const WAVE_TOTAL := 5


static func ground_y() -> float:
	return float(GROUND_ROW * TILE)


static func exp_to_next(level: int) -> int:
	## 升到 level+1 所需经验：基础 30，每级 ×1.35。
	var need := float(EXP_PER_LEVEL)
	for i in range(level):
		need *= 1.35
	return int(round(need))
