# -*- coding: utf-8 -*-
## GameHUD —— dnfm-arena 的 HUD / 标题页 / 结算页。
## 严格遵循 docs/contracts.md §5；颜色与尺寸一律引用 GameConfig，不硬编码色值。
class_name GameHUD extends CanvasLayer

# ---------- 字号（zpix 是 12px 点阵字体，只能取 12 的整数倍） ----------
const FS_BODY := 12
const FS_HEAD := 24

# ---------- 布局常量 ----------
const PAD := 4                  # HUD 底衬内边距
const HUD_POS := Vector2(4.0, 4.0)
const BAR_W := 92.0             # 血条 / 经验条长度
const BAR_H := 10.0
const COMBO_X := 452.0          # 连击数位置（屏幕中上方偏右）
const COMBO_Y := 44.0
const BANNER_Y := 104.0
const PANEL_W := 300.0
const PANEL_X := 170.0
const PANEL_Y := 26.0
const PANEL_H := 308.0
const ROW_H := 18.0             # 结算页数据行距

# ---------- 字体与根节点 ----------
var _font: FontFile = null
var _labels: Array[Label] = []
var _built := false

var hud_root: Control = null
var title_root: Control = null
var result_root: Control = null
var banner_root: Control = null

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
var _banner_title: Label = null
var _banner_sub: Label = null

# ---------- 标题页部件 ----------
var _title_blink: Label = null
var _best_label: Label = null

# ---------- 结算页部件 ----------
var _result_title: Label = null
var _result_rows: Array[Label] = []
var _result_values: Array[Label] = []
var _rating_label: Label = null

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
	if count <= 0:
		_combo_label.visible = false
		_combo_label.text = ""
		return
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
	title_root.visible = true


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
	result_root.visible = true


func hide_all() -> void:
	_ensure_built()
	hud_root.visible = false
	title_root.visible = false
	result_root.visible = false
	banner_root.visible = false


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
#  构建
# ======================================================================

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_build_hud()
	_build_banner()
	_build_title()
	_build_result()
	# 建出来的根节点默认全隐藏，由 show_* / hide_all 显式切换。
	# 否则标题界面会同时显示 HUD 与结算面板（串屏）。
	hud_root.visible = false
	banner_root.visible = false
	title_root.visible = false
	result_root.visible = false


func _build_hud() -> void:
	hud_root = _make_root("HudRoot")

	var panel := PanelContainer.new()
	panel.name = "HudPanel"
	panel.position = HUD_POS
	panel.custom_minimum_size = Vector2(196.0, 0.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = GameConfig.COL_HUD_BG
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

	# 提示条（屏幕中部下方，默认隐藏）
	_hint_label = _make_label(hud_root, "", FS_BODY, GameConfig.COL_TEXT, 360.0)
	_hint_label.size = Vector2(360.0, 20.0)
	_hint_label.position = Vector2((float(GameConfig.VIEW_W) - 360.0) * 0.5, float(GameConfig.VIEW_H) - 44.0)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.visible = false


func _build_banner() -> void:
	banner_root = _make_root("BannerRoot")
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
	title_root = _make_root("TitleRoot")

	var t := _make_label(title_root, "地下城勇士 Q版", FS_HEAD, GameConfig.COL_ACCENT, 400.0)
	t.size = Vector2(400.0, 36.0)
	t.position = Vector2((float(GameConfig.VIEW_W) - 400.0) * 0.5, 44.0)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var sub := _make_label(title_root, "Q 版横版动作 · 5 波地牢", FS_BODY, GameConfig.COL_DIM, 400.0)
	sub.size = Vector2(400.0, 20.0)
	sub.position = Vector2((float(GameConfig.VIEW_W) - 400.0) * 0.5, 84.0)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var ops := ["←  →  移动", "↑  跳跃", "J  连招", "K  蓄力斩", "L  鬼影斩", "R  重新开始"]
	var y := 122.0
	for line in ops:
		var l := _make_label(title_root, str(line), FS_BODY, GameConfig.COL_TEXT, 260.0)
		l.size = Vector2(260.0, 20.0)
		l.position = Vector2((float(GameConfig.VIEW_W) - 260.0) * 0.5, y)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		y += ROW_H

	_best_label = _make_label(title_root, "最高分 0", FS_BODY, GameConfig.COL_GOLD, 260.0)
	_best_label.size = Vector2(260.0, 20.0)
	_best_label.position = Vector2((float(GameConfig.VIEW_W) - 260.0) * 0.5, 246.0)
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_title_blink = _make_label(title_root, "按 空格 / 回车 开始", FS_BODY, GameConfig.COL_TEXT, 300.0)
	_title_blink.size = Vector2(300.0, 20.0)
	_title_blink.position = Vector2((float(GameConfig.VIEW_W) - 300.0) * 0.5, 280.0)
	_title_blink.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _build_result() -> void:
	result_root = _make_root("ResultRoot")

	# 全屏遮罩
	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.color = GameConfig.COL_OVERLAY
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_root.add_child(overlay)

	# 居中面板
	var panel := PanelContainer.new()
	panel.name = "ResultPanel"
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = PANEL_X
	panel.offset_top = PANEL_Y
	panel.offset_right = PANEL_X + PANEL_W
	panel.offset_bottom = PANEL_Y + PANEL_H
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = GameConfig.COL_PANEL
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

	var footer := _make_label(box, "按 R 重新挑战", FS_BODY, GameConfig.COL_ACCENT, 0.0)
	footer.custom_minimum_size = Vector2(PANEL_W - 16.0, 20.0)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


# ======================================================================
#  构件辅助
# ======================================================================

func _make_root(node_name: String) -> Control:
	var c := Control.new()
	c.name = node_name
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
