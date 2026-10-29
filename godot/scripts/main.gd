# -*- coding: utf-8 -*-
## DnfmArena —— 地下城勇士 Q版 主控。
## 状态机 / 波次调度 / 掉落 / 成长 / 结算 / 音频 / 相机。
## 各模块接口见 res://scripts/game_config.gd 与 docs/contracts.md。
class_name DnfmArena extends Node2D

enum State { TITLE, PLAY, WIN, LOSE, PAUSE }

const SPAWN_INTERVAL := 0.35
const WAVE_CLEAR_DELAY := 1.6

# ---- 战斗反馈（hit-stop 定格 / 屏震 / 触觉） ----
## hit-stop：命中瞬间冻结一小段时间，模拟打击的「顿帧」。用 Engine.time_scale 实现。
var _hitstop: float = 0.0
## 屏震：相机偏移量，随时间线性衰减。
var _shake_amount: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO
## 触觉震动防抖：避免同一帧多次触发。
var _last_vibrate_ms: int = 0

# ---- 公开状态（冒烟测试与 HUD 读取） ----
var state: int = State.TITLE
var wave: int = 0
var kills: int = 0
var max_combo: int = 0
var elapsed: float = 0.0
var player: Node2D = null
var hud: Node = null

# ---- 内部 ----
var world: Node2D = null
var camera: Camera2D = null
var touch: Node = null
var enemies: Array = []
var pickups: Array = []
var _bgm: AudioStreamPlayer = null
var _sfx_pool: Array = []
var _sfx_index: int = 0
var _sfx_bank: Dictionary = {}
var _pending_spawns: Array = []
var _spawn_timer: float = 0.0
var _wave_clear_timer: float = 0.0
var _state_timer: float = 0.0
var _hint_text: String = ""
var _hint_timer: float = 0.0
var _frames_cache: Dictionary = {}
var _hero_sf: SpriteFrames = null
var _goblin_sf: SpriteFrames = null
var _brute_sf: SpriteFrames = null
var _rng := RandomNumberGenerator.new()
## hit-stop 结束时刻（真实毫秒，不受 time_scale 影响）
var _hitstop_until_ms: int = 0
## hit-stop 已持续的帧数（墙钟不推进时的兜底）
var _hitstop_frames: int = 0
## hit-stop 最多持续的帧数。0.08s 定格在 60fps 下约 5 帧，8 帧留足余量。
## 必须有帧数上限：无头/无 vsync 环境下墙钟推进远慢于帧推进，
## 只靠墙钟会让 time_scale 长时间停在 0.05，把按 delta 计时的波次推进一起拖死。
const HITSTOP_MAX_FRAMES := 8
## 上一次真实时间戳，用于屏震/定格的实时衰减
var _last_real_ms: int = 0
## 暂停时冻结的节点（玩家/敌人/掉落），恢复时逐个还原
var _frozen_nodes: Array = []
## 同帧防抖：暂停键可能同时来自键盘与触屏，避免一帧内切换两次
var _pause_toggle_frame: int = -1


func _ready() -> void:
	_rng.randomize()
	_setup_actions()
	_build_world()
	_build_sprites()
	_spawn_player()
	_build_camera()
	_spawn_hud()
	_spawn_touch()
	_setup_audio()
	_enter_title()
	print("[dnfm] ready: waves=%d" % GameConfig.WAVE_TOTAL)


# ───────────────────────── 输入映射（运行时注册，免手写 Object(...) 段）
func _setup_actions() -> void:
	var defs := {
		"p_left": [KEY_LEFT, KEY_A],
		"p_right": [KEY_RIGHT, KEY_D],
		"p_jump": [KEY_SPACE, KEY_W, KEY_UP],
		"p_attack": [KEY_J],
		"p_skill": [KEY_K],
		"p_ghost": [KEY_L],
		"p_start": [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER],
		"p_restart": [KEY_R],
		"p_pause": [KEY_ESCAPE, KEY_P],
	}
	for action in defs.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for code in defs[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = code
			InputMap.action_add_event(action, ev)


# ───────────────────────── 世界
func _build_world() -> void:
	world = DungeonWorld.new()
	world.name = "World"
	add_child(world)
	if world.has_method("build"):
		world.call("build")


# ───────────────────────── 精灵表
func _build_sprites() -> void:
	# 注意：index.json 里 action 字段是「去掉角色前缀后的动作名」，
	# hero_walk 与 goblin_walk 的 action 都是 "walk" —— 必须按实体名筛选，
	# 否则一个 SpriteFrames 里会重复 add_animation("walk")。
	_hero_sf = _frames_for(["hero_idle", "hero_idle_breathe", "hero_walk",
			"hero_attack1", "hero_skill_slash", "hero_ghost_slash"])
	_goblin_sf = _frames_for(["goblin_walk"])
	_brute_sf = _frames_for(["brute_walk"])


func _load_index() -> Dictionary:
	if not _frames_cache.is_empty():
		return _frames_cache
	var parsed: Variant = {}
	var f := FileAccess.open(GameConfig.EXPORT_INDEX, FileAccess.READ)
	if f != null:
		parsed = JSON.parse_string(f.get_as_text())
		f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("cannot parse %s" % GameConfig.EXPORT_INDEX)
		parsed = {}
	_frames_cache = parsed
	return parsed


func _frames_for(entity_names: Array) -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	var parsed := _load_index()
	var actions: Array = parsed.get("actions", [])
	for action in actions:
		var entity := String(action.get("name", ""))
		if entity == "" or not entity_names.has(entity):
			continue
		var anim_name := String(action.get("action", ""))
		if anim_name == "":
			continue
		var sheet_path := "res://assets/export/" + String(action.get("sheet", "")).get_file()
		var sheet: Texture2D = load(sheet_path)
		if sheet == null:
			continue
		var size_arr: Array = action.get("size", [96, 96])
		var fw := int(size_arr[0])
		var fh := int(size_arr[1])
		var count := int(action.get("frames", 1))
		var durations: Array = action.get("durations", [])
		var play := String(action.get("play", "forward"))
		sf.add_animation(anim_name)
		sf.set_animation_speed(anim_name, 1.0)
		sf.set_animation_loop(anim_name, bool(action.get("loop", true)))
		for i in count:
			var ms := 125.0
			if i < durations.size():
				ms = float(durations[i])
			var at := AtlasTexture.new()
			at.atlas = sheet
			at.region = Rect2(i * fw, 0, fw, fh)
			sf.add_frame(anim_name, at, ms / 1000.0)
		if play == "pingpong" and count > 2:
			for i in range(count - 2, 0, -1):
				var back_ms := 125.0
				if i < durations.size():
					back_ms = float(durations[i])
				var at2 := AtlasTexture.new()
				at2.atlas = sheet
				at2.region = Rect2(i * fw, 0, fw, fh)
				sf.add_frame(anim_name, at2, back_ms / 1000.0)
	return sf


# ───────────────────────── 玩家
func _spawn_player() -> void:
	player = Player.new()
	player.name = "Player"
	player.setup(_hero_sf)
	player.position = Vector2(5 * GameConfig.TILE, GameConfig.ground_y())
	add_child(player)
	if not player.has_signal("attacked"):
		return
	player.connect("attacked", Callable(self, "_on_player_attacked"))
	player.connect("damaged", Callable(self, "_on_player_damaged"))
	player.connect("died", Callable(self, "_on_player_died"))
	player.connect("jumped", Callable(self, "_on_player_jumped"))
	player.connect("combo_changed", Callable(self, "_on_player_combo"))
	player.connect("leveled_up", Callable(self, "_on_player_levelup"))
	player.connect("hit_enemy", Callable(self, "_on_player_hit_enemy"))


func _build_camera() -> void:
	camera = Camera2D.new()
	camera.name = "Camera"
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	camera.limit_left = 0
	camera.limit_right = GameConfig.LEVEL_W * GameConfig.TILE
	camera.limit_top = 0
	camera.limit_bottom = GameConfig.LEVEL_H * GameConfig.TILE
	add_child(camera)
	camera.make_current()
	camera.position = player.position


# ───────────────────────── HUD / 触控
func _spawn_hud() -> void:
	hud = GameHUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.call("setup", GameConfig.FONT_PATH)
	_connect_hud_signals()


func _spawn_touch() -> void:
	touch = TouchControls.new()
	touch.name = "Touch"
	add_child(touch)
	if touch.has_method("set_active"):
		touch.call("set_active", false)
	_connect_touch_signals()


## HUD 信号接线。队友实现可能晚于主控落地，全部走 has_signal 防御式连接，
## 缺信号时静默跳过，保证任何组合下都能编译与运行。
func _connect_hud_signals() -> void:
	if hud == null:
		return
	var pairs := {
		"title_start_pressed": "_on_hud_title_start",
		"result_restart_pressed": "_on_hud_result_restart",
		"pause_pressed": "_on_hud_pause",
		"resume_pressed": "_on_hud_resume",
		"pause_restart_pressed": "_on_hud_pause_restart",
	}
	for sig in pairs.keys():
		if hud.has_signal(sig):
			hud.connect(sig, Callable(self, str(pairs[sig])))


func _connect_touch_signals() -> void:
	if touch == null:
		return
	if touch.has_signal("start_tap_pressed"):
		touch.connect("start_tap_pressed", Callable(self, "_on_touch_start_tap"))
	if touch.has_signal("restart_tap_pressed"):
		touch.connect("restart_tap_pressed", Callable(self, "_on_touch_restart_tap"))
	if touch.has_signal("action_button_pressed"):
		touch.connect("action_button_pressed", Callable(self, "_on_touch_action"))


# ───────────────────────── 音频
func _setup_audio() -> void:
	for key in ["jump", "hit", "hurt", "coin", "powerup", "win", "lose", "land"]:
		var path: String = GameConfig.SFX_DIR + String(key) + ".wav"
		if not ResourceLoader.exists(path):
			continue
		var stream: AudioStream = load(path)
		if stream == null:
			continue
		_sfx_bank[key] = stream
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_pool.append(p)
	var bgm_path := GameConfig.SFX_DIR + "bgm.wav"
	if ResourceLoader.exists(bgm_path):
		var bgm_stream: AudioStream = load(bgm_path)
		if bgm_stream != null:
			_bgm = AudioStreamPlayer.new()
			add_child(_bgm)
			_bgm.stream = bgm_stream
			# loop_end 必须按采样数算，写 0 会导致永不循环。
			if bgm_stream is AudioStreamWAV:
				var w := bgm_stream as AudioStreamWAV
				w.loop_mode = AudioStreamWAV.LOOP_FORWARD
				w.loop_begin = 0
				w.loop_end = int(w.get_length() * w.mix_rate) - 1
			_bgm.play()


func play_sfx(key: String, vol_db: float = 0.0) -> void:
	if not _sfx_bank.has(key):
		return
	var p: AudioStreamPlayer = _sfx_pool[_sfx_index]
	_sfx_index = (_sfx_index + 1) % _sfx_pool.size()
	p.stream = _sfx_bank[key]
	p.volume_db = vol_db
	p.play()


# ───────────────────────── 状态切换
func _enter_title() -> void:
	state = State.TITLE
	_state_timer = 0.0
	if touch != null and touch.has_method("set_active"):
		touch.call("set_active", false)
	if touch != null and touch.has_method("arm_start_tap"):
		touch.call("arm_start_tap")
	if hud != null:
		hud.call("show_title", 0)


func start_game() -> void:
	state = State.PLAY
	wave = 0
	kills = 0
	max_combo = 0
	elapsed = 0.0
	_hint_timer = 0.0
	_hitstop_until_ms = 0
	_hitstop_frames = 0
	_shake_amount = 0.0
	_shake_offset = Vector2.ZERO
	Engine.time_scale = 1.0
	_clear_enemies()
	_clear_pickups()
	if player != null:
		player.call("reset_for_new_game")
		player.set("position", Vector2(5 * GameConfig.TILE, GameConfig.ground_y()))
	if camera != null:
		camera.position = player.position
		camera.reset_smoothing()
		camera.offset = Vector2.ZERO
	if hud != null:
		hud.call("hide_all")
		hud.call("show_hud")
	_update_hud_values()
	if touch != null and touch.has_method("set_active"):
		touch.call("set_active", true)
	if touch != null and touch.has_method("set_pause_mode"):
		touch.call("set_pause_mode", false)
	_start_wave(0)


func _enter_win() -> void:
	state = State.WIN
	_state_timer = 0.0
	play_sfx("win")
	if touch != null and touch.has_method("set_active"):
		touch.call("set_active", false)
	if touch != null and touch.has_method("arm_restart_tap"):
		touch.call("arm_restart_tap")
	if hud != null:
		hud.call("show_result", true, _collect_stats())


func _enter_lose() -> void:
	state = State.LOSE
	_state_timer = 0.0
	play_sfx("lose")
	if touch != null and touch.has_method("set_active"):
		touch.call("set_active", false)
	if touch != null and touch.has_method("arm_restart_tap"):
		touch.call("arm_restart_tap")
	if hud != null:
		hud.call("show_result", false, _collect_stats())


# ───────────────────────── 暂停
func _enter_pause() -> void:
	if state != State.PLAY:
		return
	state = State.PAUSE
	_state_timer = 0.0
	Engine.time_scale = 1.0
	_hitstop_until_ms = 0
	_freeze_world(true)
	if touch != null and touch.has_method("set_pause_mode"):
		touch.call("set_pause_mode", true)
	if hud != null and hud.has_method("show_pause"):
		hud.call("show_pause")


func _exit_pause() -> void:
	if state != State.PAUSE:
		return
	state = State.PLAY
	_state_timer = 0.0
	_freeze_world(false)
	if touch != null and touch.has_method("set_pause_mode"):
		touch.call("set_pause_mode", false)
	if hud != null and hud.has_method("hide_all"):
		hud.call("hide_all")
	if hud != null and hud.has_method("show_hud"):
		hud.call("show_hud")


## 冻结/恢复世界里的可动节点（玩家、敌人、掉落）。
## 不依赖 process_mode 的写法，避免误伤 UI 层。
func _freeze_world(frozen: bool) -> void:
	var targets: Array = []
	if player != null:
		targets.append(player)
	for e in enemies:
		if is_instance_valid(e):
			targets.append(e)
	for p in pickups:
		if is_instance_valid(p):
			targets.append(p)
	for n in targets:
		if frozen:
			if not _frozen_nodes.has(n):
				_frozen_nodes.append(n)
			n.set("process_mode", Node.PROCESS_MODE_DISABLED)
		else:
			n.set("process_mode", Node.PROCESS_MODE_INHERIT)
			if _frozen_nodes.has(n):
				_frozen_nodes.erase(n)


# ───────────────────────── HUD / 触控 回调
func _on_hud_title_start() -> void:
	if state == State.TITLE:
		start_game()


func _on_hud_result_restart() -> void:
	if state == State.WIN or state == State.LOSE:
		start_game()


func _on_hud_pause() -> void:
	_enter_pause()


func _on_hud_resume() -> void:
	_exit_pause()


func _on_hud_pause_restart() -> void:
	_exit_pause()
	start_game()


func _on_touch_start_tap() -> void:
	if state == State.TITLE:
		start_game()


func _on_touch_restart_tap() -> void:
	if state == State.WIN or state == State.LOSE:
		start_game()


func _on_touch_action(action: String) -> void:
	if action == "p_pause":
		# 同帧可能同时收到键盘与触屏的暂停，做一次防抖
		var frame: int = Engine.get_process_frames()
		if frame == _pause_toggle_frame:
			return
		_pause_toggle_frame = frame
		if state == State.PLAY:
			_enter_pause()
		elif state == State.PAUSE:
			_exit_pause()


func _collect_stats() -> Dictionary:
	var lvl := 1
	var exp_now := 0
	var gold_now := 0
	if player != null:
		lvl = int(player.get("level"))
		exp_now = int(player.get("exp"))
		gold_now = int(player.get("gold"))
	return {
		"waves": wave,
		"kills": kills,
		"max_combo": max_combo,
		"gold": gold_now,
		"level": lvl,
		"exp": exp_now,
		"time_sec": int(elapsed),
	}


# ───────────────────────── 波次
func _start_wave(index: int) -> void:
	wave = index
	_pending_spawns.clear()
	_spawn_timer = 0.0
	_wave_clear_timer = 0.0
	var spec: Dictionary = GameConfig.WAVES[index]
	var y := GameConfig.ground_y()
	for i in int(spec.get("goblin", 0)):
		_pending_spawns.append({"kind": "goblin", "x": _spawn_x()})
	for i in int(spec.get("brute", 0)):
		_pending_spawns.append({"kind": "brute", "x": _spawn_x()})
	_pending_spawns.shuffle()
	if hud != null:
		hud.call("set_wave", index + 1, GameConfig.WAVE_TOTAL)
		hud.call("show_banner", "第 %d 波" % (index + 1), "清光所有敌人")


func _spawn_x() -> float:
	var right := float(GameConfig.LEVEL_W * GameConfig.TILE) - 40.0
	var left := 260.0
	return _rng.randf_range(left, right)


func _spawn_enemy(kind: String, x: float) -> void:
	var sf: SpriteFrames = _goblin_sf if kind == "goblin" else _brute_sf
	var e := Enemy.new()
	e.name = "Enemy_%s_%d" % [kind, enemies.size()]
	e.setup(player, self, kind, sf)
	e.position = Vector2(x, GameConfig.ground_y())
	add_child(e)
	enemies.append(e)


# ───────────────────────── 主循环
func _process(delta: float) -> void:
	_state_timer += delta
	_tick_feedback(delta)
	match state:
		State.TITLE:
			if Input.is_action_just_pressed("p_start") or Input.is_action_just_pressed("p_attack"):
				start_game()
		State.PLAY:
			_tick_play(delta)
			if Input.is_action_just_pressed("p_pause"):
				_enter_pause()
		State.WIN, State.LOSE:
			if Input.is_action_just_pressed("p_restart"):
				start_game()
		State.PAUSE:
			if Input.is_action_just_pressed("p_pause"):
				_exit_pause()
	_update_camera(delta)
	_update_hint(delta)
	_apply_camera_shake()


func _tick_play(delta: float) -> void:
	elapsed += delta
	# 逐个入场
	if not _pending_spawns.is_empty():
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_spawn_timer = SPAWN_INTERVAL
			var spec: Dictionary = _pending_spawns.pop_front()
			_spawn_enemy(String(spec.get("kind", "goblin")), float(spec.get("x", 400.0)))
		return
	# 全部入场后，等清场
	if enemies.is_empty():
		_wave_clear_timer += delta
		if _wave_clear_timer >= WAVE_CLEAR_DELAY:
			_wave_clear_timer = 0.0
			if wave + 1 < GameConfig.WAVE_TOTAL:
				_start_wave(wave + 1)
			else:
				_enter_win()


func _update_camera(delta: float) -> void:
	if camera == null or player == null:
		return
	var target: Variant = player.get("position")
	if typeof(target) != TYPE_VECTOR2:
		return
	camera.position = target + Vector2(0, -GameConfig.TILE * 2)


func _update_hint(delta: float) -> void:
	if _hint_timer <= 0.0:
		return
	_hint_timer -= delta
	if _hint_timer <= 0.0 and hud != null and hud.has_method("set_hint"):
		hud.call("set_hint", "")


func _show_hint(text: String) -> void:
	_hint_text = text
	_hint_timer = 2.2
	if hud != null and hud.has_method("set_hint"):
		hud.call("set_hint", text)


# ───────────────────────── 敌人回调
func on_enemy_killed(enemy: Node2D) -> void:
	kills += 1
	enemies.erase(enemy)
	# 掉落
	var kind := String(enemy.get("kind")) if enemy.get("kind") != null else "goblin"
	var roll := _rng.randf()
	var gold_chance := 0.6 if kind == "goblin" else 0.4
	var exp_value := 0
	var gold_value := 0
	if kind == "goblin":
		exp_value = 6
		gold_value = 3
	else:
		exp_value = 16
		gold_value = 8
	if roll < gold_chance:
		_spawn_pickup("gold", gold_value, enemy.get("position"))
	else:
		_spawn_pickup("exp", exp_value, enemy.get("position"))


func on_enemy_attack(enemy: Node2D, amount: int) -> void:
	if player == null or state != State.PLAY:
		return
	# 受伤音效由玩家 damaged 信号统一触发，这里只负责结算伤害。
	player.call("take_damage", amount, enemy.get("position"))


func _spawn_pickup(kind: String, value: int, pos: Vector2) -> void:
	var p := Pickup.new()
	p.setup(kind, value)
	p.position = pos
	add_child(p)
	if p.has_method("bind"):
		p.call("bind", self, player)
	else:
		if p.has_method("set_target"):
			p.call("set_target", player)
		if p.has_method("set_game"):
			p.call("set_game", self)
	pickups.append(p)


func on_pickup(kind: String, value: int) -> void:
	if player == null:
		return
	if kind == "gold":
		player.call("add_gold", value)
		play_sfx("coin")
	else:
		player.call("add_exp", value)
		play_sfx("coin")
	_update_hud_values()


func _clear_enemies() -> void:
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()


func _clear_pickups() -> void:
	for p in pickups:
		if is_instance_valid(p):
			p.queue_free()
	pickups.clear()


# ───────────────────────── 玩家事件
func _on_player_attacked(kind: String) -> void:
	match kind:
		"attack":
			play_sfx("hit", -4.0)
		"skill":
			play_sfx("powerup", -3.0)
		"ghost":
			play_sfx("powerup", 0.0)
		"combo3":
			play_sfx("powerup", -1.0)


func _on_player_hit_enemy(enemy: Node2D, damage: int) -> void:
	# 打击感三件套：命中定格 + 屏震 + 触觉震动
	_apply_hitstop(GameConfig.HITSTOP_HIT)
	_apply_shake(GameConfig.SHAKE_HIT)
	_vibrate(GameConfig.VIBRATE_HIT_MS)
	# 击杀比普通命中更重：更强的定格与屏震
	if enemy != null and is_instance_valid(enemy) and bool(enemy.get("dead")):
		_apply_hitstop(GameConfig.HITSTOP_KILL)
		_apply_shake(GameConfig.SHAKE_KILL)
		_vibrate(GameConfig.VIBRATE_HIT_MS * 2)


func _on_player_damaged(amount: int) -> void:
	play_sfx("hurt")
	_apply_shake(GameConfig.SHAKE_HURT)
	_vibrate(GameConfig.VIBRATE_HURT_MS)
	_update_hud_values()


# =========================================================
# 战斗反馈：命中定格 / 屏震 / 触觉震动
# =========================================================
## 命中定格：用 Engine.time_scale 降到 0 附近再线性恢复。
## 必须在 _process 里用真实时间恢复，否则 time_scale=0 时自己也不会动。
func _apply_hitstop(seconds: float) -> void:
	if seconds <= 0.0:
		return
	var now: int = Time.get_ticks_msec()
	if now < _hitstop_until_ms:
		return
	_hitstop_until_ms = now + int(seconds * 1000.0)
	_hitstop_frames = 0
	Engine.time_scale = 0.05


func _apply_shake(amount: float) -> void:
	_shake_amount = maxf(_shake_amount, amount)


func _vibrate(ms: int) -> void:
	if not GameConfig.VIBRATE_ENABLED or ms <= 0:
		return
	Input.vibrate_handheld(ms, GameConfig.VIBRATE_AMPLITUDE)


## 每帧推进定格恢复与屏震衰减。使用真实时间，不受 time_scale 影响。
func _tick_feedback(delta: float) -> void:
	# time_scale 生效时 delta 会被压缩，屏震与定格必须按真实时间推进，
	# 否则定格期间连恢复都恢复不了（死锁在慢动作里）。
	var scale: float = maxf(0.0001, Engine.time_scale)
	var real_delta: float = delta / scale
	var now: int = Time.get_ticks_msec()
	if Engine.time_scale < 1.0:
		# 双保险：墙钟到点，或已累计够帧数（无头/卡顿时墙钟可能不推进）。
		# 帧数兜底保证定格一定会结束，否则 time_scale 永久停在 0.05，
		# 会把所有按 delta 计时的逻辑（波次推进）一起拖死。
		_hitstop_frames += 1
		if now >= _hitstop_until_ms or _hitstop_frames >= HITSTOP_MAX_FRAMES:
			Engine.time_scale = 1.0
			_hitstop_frames = 0
	else:
		_shake_amount = maxf(0.0, _shake_amount - GameConfig.SHAKE_DECAY * real_delta)
	if _shake_amount > 0.05:
		_shake_offset = Vector2(
			_rng.randf_range(-_shake_amount, _shake_amount),
			_rng.randf_range(-_shake_amount, _shake_amount))
	else:
		_shake_amount = 0.0
		_shake_offset = Vector2.ZERO


## 相机跟随 + 屏震偏移
func _apply_camera_shake() -> void:
	if camera == null:
		return
	camera.offset = _shake_offset


func _on_player_died() -> void:
	if state == State.PLAY:
		_enter_lose()


func _on_player_jumped() -> void:
	play_sfx("jump", -6.0)


func _on_player_combo(count: int) -> void:
	if count > max_combo:
		max_combo = count
	if hud != null:
		hud.call("set_combo", count)


func _on_player_levelup(level: int) -> void:
	play_sfx("powerup")
	_show_hint("升级！Lv.%d 生命上限提升" % level)
	_update_hud_values()


func _update_hud_values() -> void:
	if hud == null or player == null:
		return
	hud.call("set_hp", int(player.get("hp")), int(player.get("max_hp")))
	hud.call("set_level", int(player.get("level")))
	hud.call("set_gold", int(player.get("gold")))
	var need := GameConfig.exp_to_next(int(player.get("level")))
	hud.call("set_exp", int(player.get("exp")), need)
