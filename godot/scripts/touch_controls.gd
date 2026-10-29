# -*- coding: utf-8 -*-
class_name TouchControls
extends Control
##
## dnfm-arena 移动端触控层：左侧静态摇杆 + 右侧四个动作键（跳 / 攻 / 技 / 鬼）。
##
## 真源契约：docs/contracts.md §6。
##
## 设计要点：
## - **按下当帧就写轴**：轴值不能只写在 InputEventScreenDrag 分支。手指按住不动时
##   Android 不再发 drag，只处理 drag 会导致方向恒 0、角色不动（本工程的已知 P0）。
## - **静态摇杆**：摇杆位置固定，肌肉记忆强；不做浮动摇杆。
## - **按下后捕获 index**：手指滑出按钮不丢按压，抬起才释放；拖动摇杆不会误触跳跃。
## - **一律用 event.index 追踪多指**，不做坐标匹配。
## - **通过 Input.action_press / action_release 注入**，不直接改角色状态。
## - 死区 0.20（Godot 官方默认）；摇杆命中半径 ≥ 44 逻辑px；所有按钮命中半径 ≥ 44 逻辑px。
## - 触控层放 CanvasLayer，**不受 Camera2D zoom / 平移影响**；坐标一律是逻辑像素。
##
## 公开 API：
##   set_active(active: bool)  —— main.gd 在 State.PLAY 时打开，其余状态关闭并清零
##   is_active() -> bool
##   move_axis() -> float      —— -1 / 0 / +1（只读便利接口，真实输出走 Input）
##   setup(font_path: String)  —— 可选，给动作键加中文标签
##   set_pause_mode(v: bool)    —— 暂停态：唯一暂停键的文案切「继续」，并只响应这一个键
##   arm_start_tap()           —— 标题态：等任意点击/触摸，发 start_tap_pressed 后自动复位
##   arm_restart_tap()         —— 结算态：等任意点击/触摸，发 restart_tap_pressed 后自动复位
##   signal action_button_pressed(action: StringName)
##   signal action_button_released(action: StringName)
##   signal start_tap_pressed()
##   signal restart_tap_pressed()
##

# =====================================================================
# 可调参数（顶部常量集中管理，不要在别处散落硬编码）
# =====================================================================

## 输入动作名（contracts.md §2：main.gd 运行时注册，player 只读）
const ACTION_LEFT := &"p_left"
const ACTION_RIGHT := &"p_right"
const ACTION_JUMP := &"p_jump"
const ACTION_ATTACK := &"p_attack"
const ACTION_SKILL := &"p_skill"
const ACTION_GHOST := &"p_ghost"
## 暂停：主控在 main.gd 运行时注册 p_pause；本键是「按下瞬间」语义。
const ACTION_PAUSE := &"p_pause"

# ---- 摇杆（左下角，静态）----
const STICK_CENTER := Vector2(62.0, 292.0)
## 摇杆可视半径（画出来多大）
const STICK_VISUAL_RADIUS := 30.0
## 摇杆命中半径（手指按多大范围有效）—— 契约要求 ≥ 44 逻辑px
const STICK_TOUCH_RADIUS := 46.0
## 摇杆把手半径
const STICK_KNOB_RADIUS := 14.0
## 死区比例 0.20（Godot 官方默认）
const STICK_DEADZONE := 0.20

# ---- 动作键（右半区 2×2 排布，命中半径全部 ≥ 44）----
## 跳跃：右下，最大最常用
const JUMP_CENTER := Vector2(596.0, 300.0)
const JUMP_VISUAL_RADIUS := 26.0
const JUMP_TOUCH_RADIUS := 46.0
## 普攻：右下偏左，连招主力
const ATTACK_CENTER := Vector2(504.0, 306.0)
const ATTACK_VISUAL_RADIUS := 26.0
const ATTACK_TOUCH_RADIUS := 46.0
## 蓄力斩：右上
const SKILL_CENTER := Vector2(596.0, 212.0)
const SKILL_VISUAL_RADIUS := 20.0
const SKILL_TOUCH_RADIUS := 44.0
## 鬼影斩：右上偏左
const GHOST_CENTER := Vector2(504.0, 212.0)
const GHOST_VISUAL_RADIUS := 20.0
const GHOST_TOUCH_RADIUS := 44.0

# ---- 暂停键（顶部，与 HUD 层暂停按钮错开）----
## HUD 层另有一个暂停按钮（主控负责），两者会同处右上区域。
## 触屏暂停键因此**左移并下移**，放在 HUD 暂停键左侧，避免两个热区重叠导致误触。
## y 取 24 而非 lead 建议的 8：半径 20 的圆在 y=8 会被屏幕顶边裁掉一半。
## x 取 512：HUD 暂停键在 (584,4)、尺寸 48×48（占 x 584~632），
## 两键中心距 = sqrt(72²+20²) ≈ 75px > 44(本键热区) + 24(HUD 半宽) = 68px，
## 两个热区不重叠，不会误触。
## 坐标再经 _safe() 做安全区内缩，避开刘海 / 挖孔。
const PAUSE_CENTER := Vector2(512.0, 24.0)
const PAUSE_VISUAL_RADIUS := 20.0
const PAUSE_TOUCH_RADIUS := 44.0

## 控件底边与屏幕底边的最小留白（逻辑像素）
const BOTTOM_MARGIN := 10.0
## 是否启用安全区内缩（避开 Android 手势条与挖孔）
const USE_SAFE_AREA := true

## 调试：强制显示控件（桌面端调试用）
const DEBUG_FORCE_SHOW := false

## 触觉反馈（需要导出预设开 VIBRATE 权限，默认关）
const VIBRATE_ON_PRESS := false
const VIBRATE_MS := 10
const VIBRATE_AMPLITUDE := 0.25

# =====================================================================
# 颜色（Q 版暗石地牢配色，与 GameConfig 一致）
# =====================================================================

const COL_EDGE := Color(0.0, 0.0, 0.0, 0.85)
const COL_STICK := Color(1.0, 1.0, 1.0, 0.14)
const COL_KNOB := Color(0.96, 0.95, 0.98, 0.60)
const COL_JUMP := Color(1.0, 0.83, 0.32, 0.55)
const COL_JUMP_ON := Color(1.0, 0.90, 0.55, 0.88)
const COL_ATTACK := Color(1.0, 0.45, 0.38, 0.55)
const COL_ATTACK_ON := Color(1.0, 0.68, 0.62, 0.88)
const COL_SKILL := Color(0.42, 0.78, 1.0, 0.55)
const COL_SKILL_ON := Color(0.68, 0.90, 1.0, 0.88)
const COL_GHOST := Color(0.62, 0.45, 0.95, 0.55)
const COL_GHOST_ON := Color(0.80, 0.68, 1.0, 0.88)
const COL_PAUSE := Color(0.72, 0.78, 0.86, 0.55)
const COL_PAUSE_ON := Color(0.90, 0.94, 1.0, 0.88)
const COL_LABEL := Color(0.96, 0.95, 0.98, 0.92)
const COL_LABEL_EDGE := Color(0.0, 0.0, 0.0, 0.92)

# =====================================================================
# 角色标记
# =====================================================================

const ROLE_NONE := &""
const ROLE_STICK := &"stick"
const ROLE_JUMP := &"jump"
const ROLE_ATTACK := &"attack"
const ROLE_SKILL := &"skill"
const ROLE_GHOST := &"ghost"
const ROLE_PAUSE := &"pause"

## 桌面端调试用的鼠标虚拟 index
const POINTER_MOUSE := -1

## arm 模式：0=无，1=等「点屏幕开始」，2=等「点屏幕重开」（两者互斥）。
const ARM_NONE := 0
const ARM_START := 1
const ARM_RESTART := 2


## 承载绘制的内部节点：放在 CanvasLayer 里，避免被 Camera2D 平移/缩放影响。
class Pad extends Node2D:
	var ctrl: TouchControls = null

	func _draw() -> void:
		if ctrl != null:
			ctrl.paint_into(self)


# =====================================================================
# 运行时状态
# =====================================================================

## 是否响应玩法输入（只在 State.PLAY 打开）
var active := false

## pointer index -> role（按下后捕获，抬起才释放）
var _pointers := {}
## 当前水平轴：-1 / 0 / +1
var _axis := 0.0
## 摇杆把手当前偏移
var _knob_offset := Vector2.ZERO
## 已按下的按钮 role 集合（画高亮用）
var _pressed_roles := {}
## 是否见过真实触摸（之后忽略鼠标模拟事件）
var _touch_seen := false
## 是否收到过任何触摸/鼠标输入（桌面端隐藏判定）
var _input_seen := false
## 桌面端鼠标是否按下
var _mouse_down := false
## 标签字体（可选）
var _font: Font = null
## 是否处于暂停态：唯一暂停键的文案变「继续」，且只响应这一个键。
var _pause_mode := false
## arm 模式：0=无，1=等开始，2=等重开（两者互斥）。
var _arm_mode := ARM_NONE

var _layer: CanvasLayer
var _pad: Pad

signal action_button_pressed(action: StringName)
signal action_button_released(action: StringName)
## 标题态：任意点击/触摸（主控接它开一局）
signal start_tap_pressed()
## 结算态：任意点击/触摸（主控接它重开一局）
signal restart_tap_pressed()

# =====================================================================
# 初始化
# =====================================================================

func _ready() -> void:
	# 根节点只做输入与状态，不参与绘制；绘制交给 CanvasLayer 里的 Pad。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(true)

	_layer = CanvasLayer.new()
	_layer.name = "TouchLayer"
	_layer.layer = 10
	add_child(_layer)

	_pad = Pad.new()
	_pad.name = "Pad"
	_pad.ctrl = self
	_layer.add_child(_pad)

	_refresh_visibility()


## 可选：给动作键加中文标签（zpix.ttf）。
func setup(font_path: String = "") -> void:
	if font_path == "":
		return
	if ResourceLoader.exists(font_path):
		var res := ResourceLoader.load(font_path)
		if res is Font:
			_font = res as Font
	_redraw()


# =====================================================================
# 开关
# =====================================================================

## main.gd 在 State.PLAY 时 set_active(true)；其余状态 false。
## 关闭时隐藏控件并把所有虚拟输入清零，避免角色暂停时还在跑。
## 关闭同时复位 arm 模式（arm 模式只在标题/结算态有效）。
func set_active(value: bool) -> void:
	active = value
	if not active:
		_clear_all()
	# arm 模式只在「控件关闭」时有效：开控件（进 PLAY）必须复位，
	# 关控件（回标题/结算）也复位，避免 arm 状态跨态残留。
	_arm_mode = ARM_NONE
	_refresh_visibility()
	_redraw()

## 暂停态：唯一暂停键的文案切「继续」，且此时只响应这一个键（其余键不生效，
## 避免暂停时角色还在跑）。语义仍是「按下瞬间」发一次 action_button_pressed("p_pause")。
func set_pause_mode(v: bool) -> void:
	if _pause_mode == v:
		return
	_pause_mode = v
	if v:
		# 进入暂停态：把轴与所有按钮输入清零，防止暂停时角色仍在移动 / 连招仍在跑。
		_clear_all()
	_redraw()


## 标题态：等任意一次点击/触摸，发 start_tap_pressed 后自动退出 arm 模式。
## 与 arm_restart_tap() 互斥：后调用的那个覆盖先调用的。
func arm_start_tap() -> void:
	_arm_mode = ARM_START


## 结算态：等任意一次点击/触摸，发 restart_tap_pressed 后自动退出 arm 模式。
## 与 arm_start_tap() 互斥。
func arm_restart_tap() -> void:
	_arm_mode = ARM_RESTART


func is_active() -> bool:
	return active


## 只读便利接口：当前水平轴 -1 / 0 / +1（真实输出走 Input.action_press）。
func move_axis() -> float:
	return _axis


func is_shown() -> bool:
	return _pad != null and _pad.visible


# =====================================================================
# 输入
# =====================================================================

func _input(event: InputEvent) -> void:
	# ★ arm 模式优先级最高：标题/结算态等「任意点击」，处理完立刻 return，
	#   不再走摇杆/按钮逻辑，也**不注入任何 Input.action_press**（避免误触攻击/移动）。
	if _arm_mode != ARM_NONE and not active:
		if _consume_arm_event(event):
			return
	if event is InputEventScreenTouch:
		var te := event as InputEventScreenTouch
		if not _touch_seen:
			_touch_seen = true
			# 触屏设备的触摸会被模拟成鼠标事件，清掉可能残留的鼠标指针。
			if _pointers.has(POINTER_MOUSE):
				_end_pointer(POINTER_MOUSE)
		_input_seen = true
		var pos := _to_design(te.position)
		if te.pressed:
			_begin_pointer(te.index, pos)
			# ★ 按下当帧就更新轴值：手指按住不动时 Android 不再发 drag。
			if _pointers.get(te.index, ROLE_NONE) == ROLE_STICK:
				_update_axis(pos)
		else:
			_end_pointer(te.index)
	elif event is InputEventScreenDrag:
		var de := event as InputEventScreenDrag
		_input_seen = true
		_move_pointer(de.index, _to_design(de.position))
	elif event is InputEventMouseButton:
		# 触屏设备（或已见过真实触摸）上忽略鼠标事件，避免同一根手指处理两次。
		if DisplayServer.is_touchscreen_available() or _touch_seen:
			return
		var me := event as InputEventMouseButton
		if me.button_index != MOUSE_BUTTON_LEFT:
			return
		_input_seen = true
		var mpos := _to_design(me.position)
		if me.pressed:
			_mouse_down = true
			_begin_pointer(POINTER_MOUSE, mpos)
			if _pointers.get(POINTER_MOUSE, ROLE_NONE) == ROLE_STICK:
				_update_axis(mpos)
		else:
			_mouse_down = false
			_end_pointer(POINTER_MOUSE)
	elif event is InputEventMouseMotion:
		if DisplayServer.is_touchscreen_available() or _touch_seen:
			return
		var mm := event as InputEventMouseMotion
		if not _mouse_down:
			return
		_input_seen = true
		_move_pointer(POINTER_MOUSE, _to_design(mm.position))


## arm 模式的事件消费：收到「按下」类事件就发对应信号并退出 arm 模式。
## 只认按下瞬间（pressed），拖动与抬起不触发；一次性，触发后 _arm_mode 复位。
## **绝不注入 Input.action_press**，避免标题/结算态误触攻击或移动。
func _consume_arm_event(event: InputEvent) -> bool:
	var hit := false
	if event is InputEventScreenTouch:
		var te := event as InputEventScreenTouch
		hit = te.pressed
	elif event is InputEventMouseButton:
		var me := event as InputEventMouseButton
		hit = me.pressed and me.button_index == MOUSE_BUTTON_LEFT
	if not hit:
		return false
	# 桌面端也要记住「用户动过屏幕」，否则进 PLAY 后控件仍判定为无输入而隐藏。
	_input_seen = true
	# 真实触摸一旦出现，后续忽略引擎模拟出的鼠标事件，避免同一根手指处理两次。
	if event is InputEventScreenTouch:
		_touch_seen = true
	var mode := _arm_mode
	_arm_mode = ARM_NONE
	if mode == ARM_START:
		start_tap_pressed.emit()
	elif mode == ARM_RESTART:
		restart_tap_pressed.emit()
	return true


## 事件坐标 → 640×360 设计空间坐标。
## 引擎派发触摸事件时已经把窗口坐标逆变换回视口坐标，
## 事件里的 position 就是视口坐标；这里只需要按可见视口比例归一到设计分辨率。
func _to_design(pos: Vector2) -> Vector2:
	var view := get_viewport().get_visible_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		return pos
	return Vector2(
		pos.x * float(GameConfig.VIEW_W) / view.x,
		pos.y * float(GameConfig.VIEW_H) / view.y)


# =====================================================================
# 指针管理
# =====================================================================

func _begin_pointer(index: int, pos: Vector2) -> void:
	if not active:
		return
	if _pointers.has(index):
		return
	var role := _role_at(pos)
	if role == ROLE_NONE:
		return
	# 暂停态只响应暂停键（唯一那个「继续」键），其余键一律不捕获，
	# 避免暂停时误触攻击/技能。
	if _pause_mode and role != ROLE_PAUSE:
		return
	# 捕获：该手指从此归属于这个控件，滑出不释放。
	_pointers[index] = role
	_apply_role(role, true)
	if VIBRATE_ON_PRESS:
		Input.vibrate_handheld(VIBRATE_MS, VIBRATE_AMPLITUDE)


func _end_pointer(index: int) -> void:
	var role: StringName = _pointers.get(index, ROLE_NONE)
	if role == ROLE_NONE:
		return
	_pointers.erase(index)
	# 同一角色可能有多根手指，只有最后一根抬起才释放。
	for k in _pointers.keys():
		if _pointers[k] == role:
			return
	_apply_role(role, false)


func _move_pointer(index: int, pos: Vector2) -> void:
	# 位置只在摇杆角色上有意义；其它角色靠捕获维持按压态。
	var role: StringName = _pointers.get(index, ROLE_NONE)
	if role != ROLE_STICK:
		return
	_update_axis(pos)


# =====================================================================
# 摇杆轴值
# =====================================================================

## 按落点计算摇杆方向并更新轴值。按下当帧与拖动时都调用。
func _update_axis(pos: Vector2) -> void:
	var center := _stick_center()
	var delta := pos - center
	var limit := STICK_VISUAL_RADIUS
	if delta.length() > limit:
		delta = delta.normalized() * limit
	_knob_offset = delta
	var nx := delta.x / STICK_VISUAL_RADIUS
	if nx > STICK_DEADZONE:
		_set_axis(1.0)
	elif nx < -STICK_DEADZONE:
		_set_axis(-1.0)
	else:
		_set_axis(0.0)
	_redraw()


## 轴值 → Input 的 p_left / p_right（与物理键盘同动作并存，InputMap 自动合并）。
func _set_axis(value: float) -> void:
	if absf(value - _axis) < 0.001:
		return
	_axis = value
	_action_set(ACTION_LEFT, value < 0.0)
	_action_set(ACTION_RIGHT, value > 0.0)


# =====================================================================
# 命中判定
# =====================================================================

## 返回该坐标命中的控件角色。判定一律用「命中半径」，绘制用「可视半径」。
## 命中多个时取最近的那个。
func _role_at(pos: Vector2) -> StringName:
	var best := ROLE_NONE
	var best_d := INF
	for b in _buttons():
		var d: float = (b["center"] as Vector2).distance_to(pos)
		if d <= float(b["touch"]) and d < best_d:
			best_d = d
			best = b["role"]
	if best != ROLE_NONE:
		return best
	if pos.distance_to(_stick_center()) <= STICK_TOUCH_RADIUS:
		return ROLE_STICK
	return ROLE_NONE


## 四个动作键的布局表（中心、可视半径、命中半径、动作、配色、标签）。
func _buttons() -> Array:
	return [
		{"role": ROLE_JUMP, "center": _safe(JUMP_CENTER), "visual": JUMP_VISUAL_RADIUS,
			"touch": JUMP_TOUCH_RADIUS, "action": ACTION_JUMP,
			"color": COL_JUMP, "color_on": COL_JUMP_ON, "label": "跳"},
		{"role": ROLE_ATTACK, "center": _safe(ATTACK_CENTER), "visual": ATTACK_VISUAL_RADIUS,
			"touch": ATTACK_TOUCH_RADIUS, "action": ACTION_ATTACK,
			"color": COL_ATTACK, "color_on": COL_ATTACK_ON, "label": "攻"},
		{"role": ROLE_SKILL, "center": _safe(SKILL_CENTER), "visual": SKILL_VISUAL_RADIUS,
			"touch": SKILL_TOUCH_RADIUS, "action": ACTION_SKILL,
			"color": COL_SKILL, "color_on": COL_SKILL_ON, "label": "技"},
		{"role": ROLE_GHOST, "center": _safe(GHOST_CENTER), "visual": GHOST_VISUAL_RADIUS,
			"touch": GHOST_TOUCH_RADIUS, "action": ACTION_GHOST,
			"color": COL_GHOST, "color_on": COL_GHOST_ON, "label": "鬼"},
		{"role": ROLE_PAUSE, "center": _safe(PAUSE_CENTER), "visual": PAUSE_VISUAL_RADIUS,
			"touch": PAUSE_TOUCH_RADIUS, "action": ACTION_PAUSE,
			"color": COL_PAUSE, "color_on": COL_PAUSE_ON,
			"label": "继续" if _pause_mode else "暂停"},
	]


# =====================================================================
# 按下态
# =====================================================================

func _apply_role(role: StringName, pressed: bool) -> void:
	match role:
		ROLE_STICK:
			if not pressed:
				_reset_stick()
		ROLE_JUMP:
			_set_button_pressed(role, pressed)
			_action_set(ACTION_JUMP, pressed)
		ROLE_ATTACK:
			_set_button_pressed(role, pressed)
			_action_set(ACTION_ATTACK, pressed)
		ROLE_SKILL:
			_set_button_pressed(role, pressed)
			_action_set(ACTION_SKILL, pressed)
		ROLE_GHOST:
			_set_button_pressed(role, pressed)
			_action_set(ACTION_GHOST, pressed)
		ROLE_PAUSE:
			# 暂停键只走信号，不做 Input.action_press。
			# 原因：主控同时监听 action_button_pressed("p_pause") 与
			# Input.is_action_just_pressed("p_pause")，两条路径都触发会
			# 「进暂停后同帧又退出暂停」。信号是按下瞬间的一次性语义。
			_set_button_pressed(role, pressed)
			if pressed:
				action_button_pressed.emit(ACTION_PAUSE)
			else:
				action_button_released.emit(ACTION_PAUSE)
	_redraw()


func _set_button_pressed(role: StringName, pressed: bool) -> void:
	if pressed:
		_pressed_roles[role] = true
	else:
		_pressed_roles.erase(role)


func _reset_stick() -> void:
	_knob_offset = Vector2.ZERO
	_set_axis(0.0)


func _clear_all() -> void:
	_pointers.clear()
	_pressed_roles.clear()
	_knob_offset = Vector2.ZERO
	_axis = 0.0
	_action_set(ACTION_LEFT, false)
	_action_set(ACTION_RIGHT, false)
	_action_set(ACTION_JUMP, false)
	_action_set(ACTION_ATTACK, false)
	_action_set(ACTION_SKILL, false)
	_action_set(ACTION_GHOST, false)
	_redraw()


## 通过 Input 注入动作（不直接改角色状态）。
func _action_set(action: StringName, pressed: bool) -> void:
	if not InputMap.has_action(action):
		return
	if pressed:
		Input.action_press(action)
		if action != ACTION_LEFT and action != ACTION_RIGHT:
			action_button_pressed.emit(action)
	else:
		Input.action_release(action)
		if action != ACTION_LEFT and action != ACTION_RIGHT:
			action_button_released.emit(action)


func _exit_tree() -> void:
	_clear_all()


# =====================================================================
# 绘制（零素材：多边形近似圆，无抗锯齿，贴像素风）
# =====================================================================

## 由内部 Pad 节点调用，在 CanvasLayer 空间里画所有控件。
func paint_into(canvas: CanvasItem) -> void:
	if not active:
		return
	if not (DEBUG_FORCE_SHOW or DisplayServer.is_touchscreen_available() or _input_seen):
		return

	# 摇杆底盘 + 把手（暂停态只留暂停键，画面更干净也避免误触）
	if not _pause_mode:
		var center := _stick_center()
		_draw_disc(canvas, center, STICK_VISUAL_RADIUS, COL_STICK)
		_draw_disc(canvas, center + _knob_offset, STICK_KNOB_RADIUS, COL_KNOB)

	# 动作键
	for b in _buttons():
		var role: StringName = b["role"]
		# 暂停态只画暂停键（文案「继续」）。
		if _pause_mode and role != ROLE_PAUSE:
			continue
		var pressed: bool = _pressed_roles.has(role)
		var col: Color = b["color_on"] if pressed else b["color"]
		var pos: Vector2 = b["center"]
		_draw_disc(canvas, pos, float(b["visual"]), col)
		if _font != null:
			var label: String = b["label"]
			var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var origin := pos - Vector2(w * 0.5, -2.0)
			canvas.draw_string_outline(_font, origin + Vector2(1.0, 1.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, COL_LABEL_EDGE)
			canvas.draw_string(_font, origin, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_LABEL)


## 画一个「黑描边 + 半透明纯色填充」的圆（16 边形近似，像素风无抗锯齿）。
func _draw_disc(canvas: CanvasItem, center: Vector2, radius: float, fill: Color) -> void:
	canvas.draw_colored_polygon(_disc_points(center, radius + 2.0), COL_EDGE)
	canvas.draw_colored_polygon(_disc_points(center, radius), fill)


func _disc_points(center: Vector2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var segments := 16
	for i in segments:
		var a := TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	return pts


func _redraw() -> void:
	if _pad != null:
		_pad.queue_redraw()


# =====================================================================
# 安全区
# =====================================================================

## 摇杆中心（按安全区内缩后的实际落点）。
func _stick_center() -> Vector2:
	return _safe(STICK_CENTER)


## 把常量坐标按安全区内缩后的实际落点返回。
## Godot 4 只有 DisplayServer.get_display_safe_area()，没有单独的刘海/挖孔边距 API。
func _safe(pos: Vector2) -> Vector2:
	if not USE_SAFE_AREA:
		return pos
	var rect := _safe_area_in_canvas()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return pos
	var out := pos
	# 底边与右边内缩，避开手势条与挖孔。
	out.x = min(out.x, rect.position.x + rect.size.x - BOTTOM_MARGIN)
	out.y = min(out.y, rect.position.y + rect.size.y - BOTTOM_MARGIN)
	out.x = max(out.x, rect.position.x + BOTTOM_MARGIN)
	out.y = max(out.y, rect.position.y + BOTTOM_MARGIN)
	return out


## 安全区（物理像素）换算到画布（逻辑像素）。
func _safe_area_in_canvas() -> Rect2:
	var win := DisplayServer.window_get_size()
	var view := get_viewport().get_visible_rect().size
	if view.x <= 0.0 or win.x <= 0:
		return Rect2()
	var scale := float(win.x) / view.x
	var safe := DisplayServer.get_display_safe_area()
	return Rect2(Vector2(safe.position) / scale, Vector2(safe.size) / scale)


# =====================================================================
# 显隐
# =====================================================================

func _refresh_visibility() -> void:
	if _pad != null:
		_pad.visible = active
