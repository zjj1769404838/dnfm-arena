# -*- coding: utf-8 -*-
## GameHUD —— dnfm-arena 的 HUD / 标题页 / 暂停页 / 结算页。
## 严格遵循 docs/contracts.md §5；颜色与尺寸一律引用 GameConfig 或 TS_ tokens，不硬编码色值。
##
## 触屏闭环：标题页「开始战斗」、结算页「再来一次」、游戏中右上角暂停键、暂停页「继续战斗 / 重新开始」，
## 全部通过信号抛给 main.gd；本文件不持有任何游戏逻辑。
class_name GameHUD extends CanvasLayer

## 触屏 / 鼠标操作入口。main.gd 负责连接实际逻辑（开始 / 重开 / 暂停 / 继续）。
signal title_start_pressed()
signal result_restart_pressed()
signal pause_pressed()
signal resume_pressed()
signal pause_restart_pressed()

# ---------- 字号（zpix 是 12px 点阵字体，只能取 12 的整数倍） ----------
const FS_BODY := 12
const FS_HEAD := 24

# ---------- UI tokens（新增元素统一走这套，色值/尺寸不再散落） ----------
const TS_TEXT_PRIMARY := Color(0.949, 0.961, 0.973)   # #F2F5F8
const TS_TEXT_TITLE := Color(1.0, 0.859, 0.251)       # #FFDB40
const TS_TEXT_ACCENT := Color(0.349, 0.902, 1.0)      # #59E6FF
const TS_TEXT_MUTED := Color(0.780, 0.839, 0.906)     # #C7D6E7
const TS_TEXT_DANGER := Color(1.0, 0.451, 0.349)      # #FF7359
const TS_SURFACE_PANEL := Color(0.047, 0.055, 0.078, 0.92)
const TS_OVERLAY := Color(0.0, 0.0, 0.0, 0.55)
const TS_SURFACE_HUD := Color(0.0, 0.0, 0.0, 0.35)
const TS_SPACING := [2, 4, 8, 12, 16, 24, 32]
# 按钮三态底色（像素风：圆角 0）
const TS_SURFACE_BTN := Color(0.098, 0.113, 0.145, 0.96)
const TS_SURFACE_BTN_HOVER := Color(0.161, 0.184, 0.239, 0.98)
const TS_SURFACE_BTN_PRESSED := Color(0.055, 0.063, 0.086, 1.0)

# ---------- 布局常量 ----------
const PAD := 4                  # HUD 底衬内边距
const HUD_POS := Vector2(4.0, 4.0)
const BAR_W := 92.0             # 血条 / 经验条长度
const BAR_H := 10.0
const COMBO_X := 452.0          # 连击数位置（屏幕中上方偏右）
const COMBO_Y := 76.0           # 下移，避开右上角暂停键
const BANNER_Y := 104.0
const ROW_H := 18.0             # 结算页数据行距

# 结算面板
const PANEL_W := 300.0
const PANEL_X := 170.0
const PANEL_Y := 8.0
const PANEL_H := 344.0

# 标题面板
const TITLE_PANEL_W := 320.0
const TITLE_PANEL_X := 160.0
const TITLE_PANEL_Y := 8.0
const TITLE_PANEL_H := 344.0

# 暂停面板
const PAUSE_PANEL_W := 260.0
const PAUSE_PANEL_X := 190.0
const PAUSE_PANEL_Y := 70.0
const PAUSE_PANEL_H := 220.0

# 按钮
const BTN_W := 160.0            # 主按钮 160×40 逻辑px（≈160dp，远超 44dp 触控下限）
const BTN_H := 40.0
const BTN_GAP := 8.0
const PAUSE_BTN_SIZE := 48.0    # 游戏中右上角暂停键
const PAUSE_BTN_X := 584.0
const PAUSE_BTN_Y := 4.0

# 底部/顶部操作提示（放在 HUD 面板右侧空白区，避开触屏控件与暂停键）
const HINT_X := 212.0
const HINT_Y := 6.0
const HINT_W := 232.0
const HINT_ROW := 18.0

# ---------- 字体与根节点 ----------
var _font: FontFile = null
var _labels: Array[Label] = []
var _buttons: Array[Button] = []
var _built := false

var hud_root: Control = null
var title_root: Control = null
var result_root: Control = null
var banner_root: Control = null
var pause_root: Control = null

# ---------- HUD 部件 ----------
var _hp_bar: ProgressBar = null
var _hp_text: Label = null
var _exp_bar: ProgressBar = null
var _exp_text: Label = null
var _level_label: Label = null
var _gold_label: Label = null
var _wave_label: Label = null
var _combo_label: Label = null
var _hint_label: Label = null
var _keys_hint_label: Label = null
var _touch_hint_label: Label = null
var _pause_button: Button = null
var _banner_title: Label = null
var _banner_sub: Label = null

# ---------- 标题页部件 ----------
var _title_blink: Label = null
var _best_label: Label = null
var _start_button: Button = null

# ---------- 暂停页部件 ----------
var _resume_button: Button = null
var _pause_restart_button: Button = null

# ---------- 结算页部件 ----------
var _result_title: Label = null
var _result_rows: Array[Label] = []
var _result_values: Array[Label] = []
var _rating_label: Label = null
var _restart_button: Button = null

# ---------- 动效计时 ----------
var _blink_t := 0.0
var _pulse_t := 0.0
var _combo_count := 0


func _ready() -> void:
	layer = 100
	_ensure_built()


## 加载像素中文字体。三段回退都失败时不崩，沿用系统默认字体。
func setup(font_path: String) -> void:
	_ensure_built()
	_font = _load_font(font_path)
	if _font != null:
		# 像素风：关闭抗锯齿 / 次像素定位 / hinting，保持硬边缘
		_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		_font.hinting = TextServer.HINTING_NONE
		_font.allow_system_fallback = false
	for l in _labels:
		if _font != null:
			l.add_theme_font_override("font", _font)
	for b in _buttons:
		if _font != null:
			b.add_theme_font_override("font", _font)


func _load_font(font_path: String) -> FontFile:
	if font_path == "":
		return null
	# 方案一：走资源导入管线（zpix.ttf 已被导入为 FontFile 资源，最稳）
	if ResourceLoader.exists(font_path):
		var res := ResourceLoader.load(font_path)
		if res is FontFile:
			return res as FontFile
	# 方案二：FontFile.load_dynamic_font()
	var f := FontFile.new()
	if f.load_dynamic_font(font_path) == OK:
		return f
	# 方案三：读原始字节写入 data
	if FileAccess.file_exists(font_path):
		var bytes := FileAccess.get_file_as_bytes(font_path)
		if bytes.size() > 0:
			var f2 := FontFile.new()
			f2.data = bytes
			return f2
	return null


# ======================================================================
#  公开方法
# ======================================================================

func show_hud() -> void:
	_ensure_built()
	hud_root.visible = true
	title_root.visible = false
	result_root.visible = false
	pause_root.visible = false
	set_pause_button_visible(true)


func hide_hud() -> void:
	_ensure_built()
	hud_root.visible = false


func set_hp(hp: int, max_hp: int) -> void:
	_ensure_built()
	var total := maxi(max_hp, 1)
	_hp_bar.max_value = float(total)
	_hp_bar.value = clampf(float(hp), 0.0, float(total))
	_hp_text.text = "%d/%d" % [hp, total]


func set_exp(exp: int, need: int) -> void:
	_ensure_built()
	var total := maxi(need, 1)
	_exp_bar.max_value = float(total)
	_exp_bar.value = clampf(float(exp), 0.0, float(total))
	_exp_text.text = "%d/%d" % [exp, total]


func set_level(level: int) -> void:
	_ensure_built()
	_level_label.text = "Lv.%d" % level


func set_gold(gold: int) -> void:
	_ensure_built()
	_gold_label.text = "金币 %d" % gold


func set_wave(wave: int, total: int) -> void:
	_ensure_built()
	_wave_label.text = "波次 %d/%d" % [wave, total]


func set_combo(count: int) -> void:
	_ensure_built()
	_combo_count = count
	if count < 2:
		_combo_label.visible = false
		_combo_label.text = ""
		return
	_combo_label.visible = true
	_combo_label.text = "%d 连击" % count
	_combo_label.add_theme_font_size_override("font_size", FS_HEAD if count >= 10 else FS_BODY)
	# 字号切换后重新居中，避免左右跳动
	_combo_label.size = Vector2(180.0, 36.0 if count >= 10 else 20.0)
	_combo_label.position = Vector2(COMBO_X, COMBO_Y)


func show_banner(title: String, sub: String) -> void:
	_ensure_built()
	_banner_title.text = title
	_banner_sub.text = sub
	banner_root.visible = true


func hide_banner() -> void:
	_ensure_built()
	banner_root.visible = false


## 提示条（main.gd 通过 has_method 探测后调用，契约未列，属于附加能力）。
## 空字符串即隐藏。
func set_hint(text: String) -> void:
	_ensure_built()
	if _hint_label == null:
		return
	if text.strip_edges() == "":
		_hint_label.visible = false
		_hint_label.text = ""
		return
	_hint_label.text = text
	_hint_label.visible = true


func show_title(best_score: int) -> void:
	_ensure_built()
	_best_label.text = "最高分 %d" % best_score
	hud_root.visible = false
	result_root.visible = false
	pause_root.visible = false
	banner_root.visible = false
	title_root.visible = true
	set_pause_button_visible(false)


func show_result(win: bool, stats: Dictionary) -> void:
	_ensure_built()
	_result_title.text = "通关成功！" if win else "挑战失败"
	_result_title.add_theme_color_override("font_color", GameConfig.COL_ACCENT if win else GameConfig.COL_DANGER)

	var waves := int(stats.get("waves", 0))
	var kills := int(stats.get("kills", 0))
	var max_combo := int(stats.get("max_combo", 0))
	var gold := int(stats.get("gold", 0))
	var level := int(stats.get("level", 1))
	var exp := int(stats.get("exp", 0))
	var time_sec := int(stats.get("time_sec", 0))

	var need := GameConfig.exp_to_next(level)
	var values := [
		"%d" % waves,
		"%d" % kills,
		"%d" % max_combo,
		"%d" % gold,
		"Lv.%d  (%d/%d)" % [level, exp, need],
		"%02d:%02d" % [time_sec / 60, time_sec % 60],
	]
	for i in _result_values.size():
		if i < values.size():
			_result_values[i].text = str(values[i])
	_rating_label.text = "评级 %s" % _rating(win, waves, kills, max_combo)
	hud_root.visible = false
	title_root.visible = false
	banner_root.visible = false
	pause_root.visible = false
	result_root.visible = true
	set_pause_button_visible(false)


## 暂停页：全屏遮罩 + 居中面板（继续战斗 / 重新开始）。
func show_pause() -> void:
	_ensure_built()
	hud_root.visible = false
	title_root.visible = false
	result_root.visible = false
	banner_root.visible = false
	pause_root.visible = true
	set_pause_button_visible(false)


func hide_all() -> void:
	_ensure_built()
	hud_root.visible = false
	title_root.visible = false
	result_root.visible = false
	banner_root.visible = false
	pause_root.visible = false


## 游戏中的暂停键只在 PLAY 态显示；TITLE / WIN / LOSE / PAUSE 隐藏，避免出现无意义的暂停入口。
func set_pause_button_visible(v: bool) -> void:
	_ensure_built()
	if _pause_button != null:
		_pause_button.visible = v


## 评级：按 waves / kills / max_combo 折算总分，失败一律 C。
func _rating(win: bool, waves: int, kills: int, max_combo: int) -> String:
	if not win:
		return "C"
	var score := waves * 100 + kills * 20 + max_combo * 10
	if score >= 800:
		return "S"
	if score >= 550:
		return "A"
	if score >= 300:
		return "B"
	return "C"


# ======================================================================
#  信号回调
# ======================================================================

func _on_start_pressed() -> void:
	title_start_pressed.emit()


func _on_restart_pressed() -> void:
	result_restart_pressed.emit()


func _on_pause_pressed() -> void:
	pause_pressed.emit()


func _on_resume_pressed() -> void:
	resume_pressed.emit()


func _on_pause_restart_pressed() -> void:
	pause_restart_pressed.emit()


# ======================================================================
#  构建
# ======================================================================

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_build_hud()
	_build_banner()
	_build_title()
	_build_pause()
	_build_result()
	# 建出来的根节点默认全隐藏，由 show_* / hide_all 显式切换。
	# 否则标题界面会同时显示 HUD 与结算面板（串屏）。
	hud_root.visible = false
	banner_root.visible = false
	title_root.visible = false
	pause_root.visible = false
	result_root.visible = false


func _build_hud() -> void:
	hud_root = _make_root("HudRoot", true)

	var panel := PanelContainer.new()
	panel.name = "HudPanel"
	panel.position = HUD_POS
	panel.custom_minimum_size = Vector2(196.0, 0.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = TS_SURFACE_HUD
	sb.set_content_margin_all(PAD)
	panel.add_theme_stylebox_override("panel", sb)
	hud_root.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)

	# 血条
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 4)
	box.add_child(hp_row)
	_hp_bar = _make_bar(hp_row, GameConfig.COL_HP_BG, GameConfig.COL_HP)
	_hp_text = _make_label(hp_row, "0/0", FS_BODY, GameConfig.COL_TEXT, 48.0)
	_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# 经验条
	var exp_row := HBoxContainer.new()
	exp_row.add_theme_constant_override("separation", 4)
	box.add_child(exp_row)
	_exp_bar = _make_bar(exp_row, GameConfig.COL_EXP_BG, GameConfig.COL_EXP)
	_exp_text = _make_label(exp_row, "0/0", FS_BODY, GameConfig.COL_TEXT, 48.0)
	_exp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# 等级 / 金币 / 波次
	var info_row := HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 8)
	box.add_child(info_row)
	_level_label = _make_label(info_row, "Lv.1", FS_BODY, GameConfig.COL_ACCENT, 40.0)
	_gold_label = _make_label(info_row, "金币 0", FS_BODY, GameConfig.COL_GOLD, 68.0)
	_wave_label = _make_label(info_row, "波次 0/0", FS_BODY, GameConfig.COL_TEXT, 72.0)

	# 连击数（屏幕中上方偏右）
	_combo_label = _make_label(hud_root, "", FS_BODY, GameConfig.COL_ACCENT, 180.0)
	_combo_label.size = Vector2(180.0, 20.0)
	_combo_label.position = Vector2(COMBO_X, COMBO_Y)
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_label.visible = false

	# 右上角暂停键（触屏 / 鼠标可点）
	_pause_button = _make_button(hud_root, "暂停", TS_SURFACE_BTN, TS_TEXT_TITLE, PAUSE_BTN_SIZE, PAUSE_BTN_SIZE)
	_pause_button.position = Vector2(PAUSE_BTN_X, PAUSE_BTN_Y)
	_pause_button.pressed.connect(Callable(self, "_on_pause_pressed"))

	# 操作提示：放在 HUD 面板右侧的空白带，不与触屏控件（画布下缘）重叠。
	_keys_hint_label = _make_label(hud_root, "键盘：A/D 移动 · J 攻击", FS_BODY, TS_TEXT_MUTED, HINT_W)
	_keys_hint_label.size = Vector2(HINT_W, 16.0)
	_keys_hint_label.position = Vector2(HINT_X, HINT_Y)
	_touch_hint_label = _make_label(hud_root, "触屏：左摇杆 · 右下按钮", FS_BODY, TS_TEXT_MUTED, HINT_W)
	_touch_hint_label.size = Vector2(HINT_W, 16.0)
	_touch_hint_label.position = Vector2(HINT_X, HINT_Y + HINT_ROW)

	# 提示条（屏幕下部偏左，避开触屏控件的虚拟摇杆与右下动作键）
	_hint_label = _make_label(hud_root, "", FS_BODY, GameConfig.COL_TEXT, 320.0)
	_hint_label.size = Vector2(320.0, 20.0)
	_hint_label.position = Vector2(112.0, float(GameConfig.VIEW_H) - 40.0)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.visible = false


func _build_banner() -> void:
	banner_root = _make_root("BannerRoot", false)
	_banner_title = _make_label(banner_root, "", FS_HEAD, GameConfig.COL_ACCENT, 300.0)
	_banner_title.size = Vector2(300.0, 36.0)
	_banner_title.position = Vector2((float(GameConfig.VIEW_W) - 300.0) * 0.5, BANNER_Y)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_banner_sub = _make_label(banner_root, "", FS_BODY, GameConfig.COL_TEXT, 300.0)
	_banner_sub.size = Vector2(300.0, 20.0)
	_banner_sub.position = Vector2((float(GameConfig.VIEW_W) - 300.0) * 0.5, BANNER_Y + 40.0)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	banner_root.visible = false


func _build_title() -> void:
	title_root = _make_root("TitleRoot", true)

	# 全屏遮罩：标题文字压天空蓝时对比度不足（白字仅 2.85:1），加遮罩 + 面板底衬。
	var overlay := ColorRect.new()
	overlay.name = "TitleOverlay"
	overlay.color = TS_OVERLAY
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_root.add_child(overlay)

	var panel := PanelContainer.new()
	panel.name = "TitlePanel"
	panel.position = Vector2(TITLE_PANEL_X, TITLE_PANEL_Y)
	panel.custom_minimum_size = Vector2(TITLE_PANEL_W, TITLE_PANEL_H)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var sb := StyleBoxFlat.new()
	sb.bg_color = TS_SURFACE_PANEL
	sb.set_border_width_all(2)
	sb.border_color = TS_TEXT_TITLE
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	title_root.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var inner := TITLE_PANEL_W - 20.0

	var t := _make_label(box, "地下城勇士 Q版", FS_HEAD, TS_TEXT_TITLE, inner)
	t.custom_minimum_size = Vector2(inner, 36.0)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var sub := _make_label(box, "Q 版横版动作 · 5 波地牢", FS_BODY, TS_TEXT_MUTED, inner)
	sub.custom_minimum_size = Vector2(inner, 20.0)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var ops := ["←  →  移动", "↑  跳跃", "J  连招", "K  蓄力斩", "L  鬼影斩", "R  重新开始"]
	for line in ops:
		var l := _make_label(box, str(line), FS_BODY, TS_TEXT_PRIMARY, inner)
		l.custom_minimum_size = Vector2(inner, 20.0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_best_label = _make_label(box, "最高分 0", FS_BODY, TS_TEXT_TITLE, inner)
	_best_label.custom_minimum_size = Vector2(inner, 20.0)
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# 触屏主入口
	_start_button = _make_button(box, "开始战斗", TS_SURFACE_BTN, TS_TEXT_TITLE, BTN_W, BTN_H)
	_start_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_start_button.pressed.connect(Callable(self, "_on_start_pressed"))

	# 桌面端提示（移动到按钮下方并改用弱化色，不与按钮重叠）
	_title_blink = _make_label(box, "按 空格 / 回车 开始", FS_BODY, TS_TEXT_MUTED, inner)
	_title_blink.custom_minimum_size = Vector2(inner, 20.0)
	_title_blink.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _build_pause() -> void:
	pause_root = _make_root("PauseRoot", true)

	var overlay := ColorRect.new()
	overlay.name = "PauseOverlay"
	overlay.color = TS_OVERLAY
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_root.add_child(overlay)

	var panel := PanelContainer.new()
	panel.name = "PausePanel"
	panel.position = Vector2(PAUSE_PANEL_X, PAUSE_PANEL_Y)
	panel.custom_minimum_size = Vector2(PAUSE_PANEL_W, PAUSE_PANEL_H)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var sb := StyleBoxFlat.new()
	sb.bg_color = TS_SURFACE_PANEL
	sb.set_border_width_all(2)
	sb.border_color = TS_TEXT_TITLE
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	pause_root.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var inner := PAUSE_PANEL_W - 20.0

	var head := _make_label(box, "已暂停", FS_HEAD, TS_TEXT_TITLE, inner)
	head.custom_minimum_size = Vector2(inner, 36.0)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var l1 := _make_label(box, "按 ESC / P 继续", FS_BODY, TS_TEXT_MUTED, inner)
	l1.custom_minimum_size = Vector2(inner, 20.0)
	l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var l2 := _make_label(box, "或点击下方按钮继续", FS_BODY, TS_TEXT_MUTED, inner)
	l2.custom_minimum_size = Vector2(inner, 20.0)
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_resume_button = _make_button(box, "继续战斗", TS_SURFACE_BTN, TS_TEXT_ACCENT, BTN_W, BTN_H)
	_resume_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_resume_button.pressed.connect(Callable(self, "_on_resume_pressed"))

	_pause_restart_button = _make_button(box, "重新开始", TS_SURFACE_BTN, TS_TEXT_MUTED, BTN_W, BTN_H)
	_pause_restart_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_pause_restart_button.pressed.connect(Callable(self, "_on_pause_restart_pressed"))


func _build_result() -> void:
	result_root = _make_root("ResultRoot", true)

	# 全屏遮罩
	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.color = TS_OVERLAY
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	result_root.add_child(overlay)

	# 居中面板
	var panel := PanelContainer.new()
	panel.name = "ResultPanel"
	panel.position = Vector2(PANEL_X, PANEL_Y)
	panel.custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var sb := StyleBoxFlat.new()
	sb.bg_color = TS_SURFACE_PANEL
	sb.border_color = GameConfig.COL_WALL_LINE
	sb.set_border_width_all(2)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	result_root.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	_result_title = _make_label(box, "", FS_HEAD, GameConfig.COL_ACCENT, 0.0)
	_result_title.custom_minimum_size = Vector2(PANEL_W - 16.0, 36.0)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var rows := ["通过波次", "击杀数", "最高连击", "金币", "等级", "用时"]
	for r in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		var k := _make_label(row, str(r), FS_BODY, GameConfig.COL_DIM, 96.0)
		k.custom_minimum_size = Vector2(96.0, 20.0)
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		var v := _make_label(row, "-", FS_BODY, GameConfig.COL_TEXT, 150.0)
		v.custom_minimum_size = Vector2(150.0, 20.0)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_result_rows.append(k)
		_result_values.append(v)

	_rating_label = _make_label(box, "评级 C", FS_HEAD, GameConfig.COL_GOLD, 0.0)
	_rating_label.custom_minimum_size = Vector2(PANEL_W - 16.0, 36.0)
	_rating_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var footer := _make_label(box, "按 R 重新挑战", FS_BODY, TS_TEXT_MUTED, 0.0)
	footer.custom_minimum_size = Vector2(PANEL_W - 16.0, 20.0)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# 触屏重开入口
	_restart_button = _make_button(box, "再来一次", TS_SURFACE_BTN, TS_TEXT_TITLE, BTN_W, BTN_H)
	_restart_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_restart_button.pressed.connect(Callable(self, "_on_restart_pressed"))


# ======================================================================
#  构件辅助
# ======================================================================

## interactive=true 时根节点用 MOUSE_FILTER_PASS：让子按钮能收到点击，同时不吞掉未处理的事件。
func _make_root(node_name: String, interactive: bool = false) -> Control:
	var c := Control.new()
	c.name = node_name
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_PASS if interactive else Control.MOUSE_FILTER_IGNORE
	c.z_index = 100
	add_child(c)
	return c


func _make_label(parent: Node, text: String, font_size: int, color: Color, width: float) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	l.add_theme_constant_override("outline_size", 3 if font_size >= FS_HEAD else 2)
	if _font != null:
		l.add_theme_font_override("font", _font)
	if width > 0.0:
		l.custom_minimum_size = Vector2(width, 0.0)
	parent.add_child(l)
	_labels.append(l)
	return l


## 像素风按钮：圆角 0、2px 边框、hover 提亮 / pressed 压暗。
func _make_button(parent: Node, text: String, bg_color: Color, fg_color: Color, width: float, height: float) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.custom_minimum_size = Vector2(width, height)
	b.add_theme_font_size_override("font_size", FS_BODY)
	b.add_theme_color_override("font_color", fg_color)
	b.add_theme_color_override("font_hover_color", fg_color)
	b.add_theme_color_override("font_pressed_color", fg_color)
	b.add_theme_color_override("font_focus_color", fg_color)
	b.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	b.add_theme_constant_override("outline_size", 2)
	if _font != null:
		b.add_theme_font_override("font", _font)

	var normal := StyleBoxFlat.new()
	normal.bg_color = bg_color
	normal.border_color = fg_color
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(0)
	normal.set_content_margin_all(4)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = TS_SURFACE_BTN_HOVER

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = TS_SURFACE_BTN_PRESSED

	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", normal)
	b.add_theme_stylebox_override("disabled", normal)

	parent.add_child(b)
	_buttons.append(b)
	return b


func _make_bar(parent: Node, bg_color: Color, fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(BAR_W, BAR_H)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.max_value = 1.0
	bar.value = 0.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = bg_color
	bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	return bar


# ======================================================================
#  动效
# ======================================================================

func _process(delta: float) -> void:
	# 标题页「按空格开始」闪烁
	if _title_blink != null and title_root.visible:
		_blink_t += delta
		_title_blink.self_modulate.a = 0.35 + 0.65 * (0.5 + 0.5 * sin(_blink_t * 4.0))

	# 连击数 alpha 脉冲
	if _combo_label != null and _combo_label.visible:
		_pulse_t += delta
		_combo_label.self_modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(_pulse_t * 8.0))
