# -*- coding: utf-8 -*-
## Player —— dnfm-arena 玩家角色（三段连招 + 蓄力斩 + 鬼影斩）。
##
## 契约见 docs/contracts.md §2。要点：
##   * 节点 position = 脚底坐标；精灵 centered=false / offset=(-48,-96)。
##   * 碰撞体 18×40 @ (0,-20)，collision_layer=1（玩家层）/ collision_mask=4（地形层）。
##   * 攻击判定 Area2D `attack_box`：collision_layer=0 / collision_mask=2（敌人层）。
##   * 动画名取自 res://assets/export/index.json 的 action 字段：
##     idle_breathe / walk / attack1 / skill_slash / ghost_slash。
class_name Player extends CharacterBody2D

# ---------------- 信号（契约 §2） ----------------
signal attacked(kind: String)              # kind ∈ "attack" / "skill" / "ghost" / "combo3"
signal damaged(amount: int)
signal died()
signal jumped()
signal combo_changed(count: int)
signal leveled_up(level: int)
signal hit_enemy(enemy: Node2D, damage: int)

# ---------------- 公开成员（契约 §2） ----------------
var hp: int = GameConfig.PLAYER_MAX_HP
var max_hp: int = GameConfig.PLAYER_MAX_HP
var level: int = 1
var exp: int = 0
var gold: int = 0
var combo: int = 0            # 当前连段数
var combo_timer: float = 0.0  # 连段续接剩余时间
var alive: bool = true
var invuln: float = 0.0       # 无敌帧剩余时间
var facing: int = 1           # 1 = 右，-1 = 左

# ---------------- 内部状态 ----------------
const MAX_FALL := 520.0        # 本工程契约未给最大下落速度，取同系列通用值
const KNOCKBACK_X := 190.0
const KNOCKBACK_Y := -170.0
const FLICKER_STEP := 0.06
const FLASH_TIME := 0.12
const ANIM_FALLBACK: Array[String] = ["idle_breathe", "idle", "walk"]

var _sf: SpriteFrames = null
var _sprite: AnimatedSprite2D = null
var _attack_box: Area2D = null
var _attack_shape: CollisionShape2D = null
var _built: bool = false

var _coyote: float = 0.0
var _buffer: float = 0.0
var _jump_held: bool = false

var _attack_cd: float = 0.0        # 普攻间隔（ATTACK_CD）
var _attack_active: float = 0.0   # 判定框开启剩余时间
var _skill_cd: float = 0.0
var _ghost_cd: float = 0.0
var _attack_stage_total: int = 0  # 本轮连招内已出的段数（单调递增）
var _hits: int = 0                # 本轮连招内命中次数
var _hit_ids: Dictionary = {}     # 本次攻击已命中过的敌人 instance_id
var _action: String = ""          # "attack" / "skill" / "ghost" / ""
var _action_timer: float = 0.0    # 动作整体时长（用于切回待机）

var _flash: float = 0.0
var _flicker: float = 0.0
var _invuln_blink: bool = false


func _ready() -> void:
	_ensure_built()


# =========================================================
# 构建
# =========================================================
func _ensure_built() -> void:
	if _built:
		return
	_built = true

	collision_layer = 1
	collision_mask = 4
	motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
	floor_snap_length = 6.0
	add_to_group("player")

	var body_shape := CollisionShape2D.new()
	var body_rect := RectangleShape2D.new()
	body_rect.size = Vector2(18.0, 40.0)
	body_shape.shape = body_rect
	body_shape.position = Vector2(0.0, -20.0)
	add_child(body_shape)

	_sprite = AnimatedSprite2D.new()
	_sprite.centered = false
	_sprite.offset = Vector2(-48.0, -96.0)
	add_child(_sprite)
	if _sf != null:
		_sprite.sprite_frames = _sf
		_set_anim("idle_breathe")

	_attack_box = Area2D.new()
	_attack_box.name = "attack_box"
	_attack_box.collision_layer = 0
	_attack_box.collision_mask = 2
	_attack_box.monitoring = false
	_attack_box.monitorable = false
	# Area2D 节点锚点严格按契约放在 (ATTACK_RANGE * facing, ATTACK_CENTER_Y)；
	# 形状子节点反向偏移，使判定框实际覆盖玩家身前 0 ~ range 这一段。
	_attack_box.position = Vector2(GameConfig.ATTACK_RANGE * float(facing), GameConfig.ATTACK_CENTER_Y)
	_attack_shape = CollisionShape2D.new()
	var atk_rect := RectangleShape2D.new()
	atk_rect.size = Vector2(GameConfig.ATTACK_RANGE, GameConfig.ATTACK_HEIGHT)
	_attack_shape.shape = atk_rect
	_attack_shape.position = Vector2(-GameConfig.ATTACK_RANGE * 0.5 * float(facing), 0.0)
	_attack_box.add_child(_attack_shape)
	add_child(_attack_box)


## 注入玩家精灵表（契约 §2 setup）。
func setup(sf: SpriteFrames) -> void:
	_sf = sf
	_ensure_built()
	_repair_frames(sf)
	if _sprite != null and sf != null:
		_sprite.sprite_frames = sf
		_set_anim("idle_breathe")


# =========================================================
# 精灵表校正
# =========================================================
## 导出数据里 hero / goblin / brute 的 action 同名（都叫 "walk"），
## 主控按 action 建表会把不同角色的帧混进同一动画（hero 的 walk 被追加成 14 帧），
## 敌人表则整表为空。这里按 index.json 的 char + frames 期望值做一次校正：
## 帧数对不上就用导出的 .tres 重建该动画。主控修好后这里自动变成空操作。
func _repair_frames(sf: SpriteFrames) -> void:
	if sf == null:
		return
	var spec: Dictionary = _hero_animspec()
	for anim_name in spec.keys():
		var info: Dictionary = spec[anim_name]
		var want: int = int(info.get("frames", 1))
		if _frames_ok(sf, anim_name, want):
			continue
		_rebuild_animation(sf, anim_name, String(info.get("godot", "")))


## 帧数是否合理：恰好 want，或 pingpong 展开后的 want + (want - 2)。
func _frames_ok(sf: SpriteFrames, anim_name: String, want: int) -> bool:
	if not sf.has_animation(anim_name):
		return false
	var count: int = sf.get_frame_count(anim_name)
	if count == want:
		return true
	if want > 2 and count == want + (want - 2):
		return true
	return false


## index.json 里 char == "hero" 的动画清单：{ action: { frames, godot } }。
func _hero_animspec() -> Dictionary:
	var spec: Dictionary = {}
	for entry in _export_actions():
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = entry
		if String(e.get("char", "")) != "hero":
			continue
		var anim_name: String = String(e.get("action", ""))
		if anim_name == "":
			continue
		spec[anim_name] = {
			"frames": int(e.get("frames", 1)),
			"godot": String(e.get("godot", "")),
		}
	return spec


func _export_actions() -> Array:
	var f := FileAccess.open(GameConfig.EXPORT_INDEX, FileAccess.READ)
	if f == null:
		return []
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	var actions: Array = parsed.get("actions", [])
	return actions


## 用导出的 .tres 重建单个动画（拷帧，不改 SpriteFrames 引用）。
func _rebuild_animation(sf: SpriteFrames, anim_name: String, tres_path: String) -> void:
	if tres_path == "":
		return
	var res: Resource = load("res://" + tres_path)
	var src: SpriteFrames = res as SpriteFrames
	if src == null:
		return
	var src_anim: String = anim_name
	if not src.has_animation(src_anim):
		if src.has_animation("walk"):
			src_anim = "walk"
		else:
			return
	if sf.has_animation(anim_name):
		sf.remove_animation(anim_name)
	sf.add_animation(anim_name)
	sf.set_animation_speed(anim_name, src.get_animation_speed(src_anim))
	sf.set_animation_loop(anim_name, src.get_animation_loop(src_anim))
	var count: int = src.get_frame_count(src_anim)
	for i in count:
		sf.add_frame(anim_name, src.get_frame_texture(src_anim, i), src.get_frame_duration(src_anim, i))


# =========================================================
# 输入
# =========================================================
## 输入统一走轮询：既兼容真机按键，也兼容触控层/自检脚本用
## Input.action_press() 注入（那类注入不会产生 InputEvent）。
func _act_pressed(action: String) -> bool:
	if not InputMap.has_action(action):
		return false
	return Input.is_action_pressed(action)


func _act_just(action: String) -> bool:
	if not InputMap.has_action(action):
		return false
	return Input.is_action_just_pressed(action)


func _physics_process(delta: float) -> void:
	_tick_timers(delta)

	if _act_just("p_jump"):
		_buffer = GameConfig.PLAYER_BUFFER
		_jump_held = true
	elif not _act_pressed("p_jump"):
		_jump_held = false

	if _act_just("p_attack"):
		_try_attack()
	if _act_just("p_skill"):
		_try_skill()
	if _act_just("p_ghost"):
		_try_ghost()

	if not alive:
		velocity.y = minf(velocity.y + GameConfig.PLAYER_GRAVITY * delta, MAX_FALL)
		move_and_slide()
		return

	_move(delta)
	_jump(delta)
	_update_hitbox(delta)
	_update_visual(delta)
	move_and_slide()


func _tick_timers(delta: float) -> void:
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_skill_cd = maxf(0.0, _skill_cd - delta)
	_ghost_cd = maxf(0.0, _ghost_cd - delta)
	_attack_active = maxf(0.0, _attack_active - delta)
	_action_timer = maxf(0.0, _action_timer - delta)
	_flash = maxf(0.0, _flash - delta)
	invuln = maxf(0.0, invuln - delta)

	if combo_timer > 0.0:
		combo_timer = maxf(0.0, combo_timer - delta)
		if combo_timer <= 0.0:
			_attack_stage_total = 0
			_hits = 0
			_set_combo(0)


# =========================================================
# 移动与跳跃
# =========================================================
func _move(delta: float) -> void:
	var axis: float = 0.0
	if _act_pressed("p_right"):
		axis += 1.0
	if _act_pressed("p_left"):
		axis -= 1.0

	if absf(axis) > 0.01:
		velocity.x = move_toward(velocity.x, GameConfig.PLAYER_SPEED * axis, GameConfig.PLAYER_ACCEL * delta)
		var new_facing: int = 1 if axis > 0.0 else -1
		if new_facing != facing:
			facing = new_facing
			if _sprite != null:
				_sprite.flip_h = facing < 0
			if _attack_shape != null:
				_attack_shape.position = Vector2(-GameConfig.ATTACK_RANGE * 0.5 * float(facing), 0.0)
			if _attack_box != null:
				_attack_box.position = Vector2(GameConfig.ATTACK_RANGE * float(facing), GameConfig.ATTACK_CENTER_Y)
	else:
		velocity.x = move_toward(velocity.x, 0.0, GameConfig.PLAYER_ACCEL * delta)


func _jump(delta: float) -> void:
	if is_on_floor():
		_coyote = GameConfig.PLAYER_COYOTE
	else:
		_coyote = maxf(0.0, _coyote - delta)

	velocity.y = minf(velocity.y + GameConfig.PLAYER_GRAVITY * delta, MAX_FALL)

	if _buffer > 0.0 and _coyote > 0.0:
		_buffer = 0.0
		_coyote = 0.0
		_jump_held = true
		velocity.y = GameConfig.PLAYER_JUMP_V
		jumped.emit()
	elif _buffer > 0.0:
		_buffer = maxf(0.0, _buffer - delta)

	if not _act_pressed("p_jump") and velocity.y < 0.0:
		velocity.y *= GameConfig.PLAYER_JUMP_CUT


# =========================================================
# 攻击：普攻三段 + 两个技能
# =========================================================
func _try_attack() -> void:
	if _attack_cd > 0.0 or not alive:
		return
	_attack_stage_total += 1
	var stage: int = ((_attack_stage_total - 1) % 3) + 1

	_attack_cd = GameConfig.ATTACK_CD
	_action = "attack"
	_action_timer = 0.34
	_hit_ids.clear()
	_open_box(GameConfig.ATTACK_RANGE, GameConfig.ATTACK_HEIGHT)
	_attack_active = float(GameConfig.ATTACK_ACTIVE[stage - 1])

	_set_anim("attack1")
	# 连段续接：刷新窗口并推进连段数
	combo_timer = GameConfig.COMBO_WINDOW
	_set_combo(maxi(combo, _attack_stage_total))
	attacked.emit("combo3" if stage == 3 else "attack")


func _try_skill() -> void:
	if _skill_cd > 0.0 or not alive:
		return
	_skill_cd = GameConfig.SKILL_CD
	_action = "skill"
	_action_timer = GameConfig.SKILL_ACTIVE
	_hit_ids.clear()
	_open_box(GameConfig.SKILL_RANGE, GameConfig.ATTACK_HEIGHT)
	_attack_active = GameConfig.SKILL_ACTIVE
	_set_anim("skill_slash")
	attacked.emit("skill")


func _try_ghost() -> void:
	if _ghost_cd > 0.0 or not alive:
		return
	_ghost_cd = GameConfig.GHOST_CD
	_action = "ghost"
	_action_timer = GameConfig.GHOST_ACTIVE
	_hit_ids.clear()
	_open_box(GameConfig.GHOST_RANGE, GameConfig.ATTACK_HEIGHT)
	_attack_active = GameConfig.GHOST_ACTIVE
	_set_anim("ghost_slash")
	attacked.emit("ghost")


## 判定框几何：Area2D 锚点贴在 (range * facing, ATTACK_CENTER_Y)，
## 形状反向偏移 half range，使判定覆盖玩家身前 0 ~ range 这一段。
func _open_box(width: float, height: float) -> void:
	if _attack_box == null or _attack_shape == null:
		return
	var rect: RectangleShape2D = _attack_shape.shape
	rect.size = Vector2(width, height)
	_attack_shape.position = Vector2(-width * 0.5 * float(facing), 0.0)
	_attack_box.position = Vector2(width * float(facing), GameConfig.ATTACK_CENTER_Y)
	_attack_box.monitoring = true


func _close_box() -> void:
	if _attack_box != null:
		_attack_box.monitoring = false
		_attack_box.position = Vector2(GameConfig.ATTACK_RANGE * float(facing), GameConfig.ATTACK_CENTER_Y)
	if _attack_shape != null:
		var rect: RectangleShape2D = _attack_shape.shape
		rect.size = Vector2(GameConfig.ATTACK_RANGE, GameConfig.ATTACK_HEIGHT)
		_attack_shape.position = Vector2(-GameConfig.ATTACK_RANGE * 0.5 * float(facing), 0.0)


func _update_hitbox(delta: float) -> void:
	if _attack_active <= 0.0:
		if _attack_box != null and _attack_box.monitoring:
			_close_box()
		return

	var dmg_base: int = _current_damage()
	for body in _attack_box.get_overlapping_bodies():
		var enemy: Node2D = body as Node2D
		if enemy == null:
			continue
		var id: int = enemy.get_instance_id()
		if _hit_ids.has(id):
			continue
		_hit_ids[id] = true
		_deal_damage(enemy, dmg_base)


func _current_damage() -> int:
	var dmg: int = 0
	if _action == "skill":
		dmg = GameConfig.SKILL_DAMAGE
	elif _action == "ghost":
		dmg = GameConfig.GHOST_DAMAGE
	else:
		var stage: int = ((_attack_stage_total - 1) % 3) + 1
		dmg = int(GameConfig.ATTACK_DAMAGE[stage - 1])
	return int(round(float(dmg) * _damage_scale()))


func _damage_scale() -> float:
	return 1.0 + GameConfig.LEVEL_DMG_STEP * float(level - 1)


func _deal_damage(enemy: Node2D, dmg: int) -> void:
	if enemy.has_method("take_damage"):
		enemy.call("take_damage", dmg, global_position)
	_hits += 1
	combo_timer = GameConfig.COMBO_WINDOW
	_set_combo(maxi(combo, _hits))
	hit_enemy.emit(enemy, dmg)


# =========================================================
# 动画与视觉
# =========================================================
func _update_visual(delta: float) -> void:
	if _action != "" and _action_timer <= 0.0:
		_action = ""
		_close_box()

	# 动画优先级：攻击/技能 > 跳跃 > 移动 > 待机
	if _action == "attack":
		_set_anim("attack1")
	elif _action == "skill":
		_set_anim("skill_slash")
	elif _action == "ghost":
		_set_anim("ghost_slash")
	elif not is_on_floor():
		_set_anim("jump")
	elif absf(velocity.x) > 6.0:
		_set_anim("walk")
	else:
		_set_anim("idle_breathe")

	if _sprite == null:
		return

	# 受击闪红
	if _flash > 0.0:
		_sprite.modulate = Color(1.0, 0.42, 0.42, 1.0)
		return
	# 无敌帧闪烁
	if invuln > 0.0:
		_flicker += delta
		if _flicker >= FLICKER_STEP:
			_flicker = 0.0
			_invuln_blink = not _invuln_blink
		_sprite.modulate = Color(1.0, 1.0, 1.0, 0.35 if _invuln_blink else 1.0)
		return
	_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)


func _set_anim(name: String) -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return
	var sf: SpriteFrames = _sprite.sprite_frames
	var target: String = name
	if not sf.has_animation(target):
		target = ""
		for fb in ANIM_FALLBACK:
			if sf.has_animation(fb):
				target = fb
				break
		if target == "":
			return
	if _sprite.animation != target or not _sprite.is_playing():
		_sprite.play(target)


# =========================================================
# 受伤 / 治疗 / 成长
# =========================================================
func take_damage(amount: int, from: Vector2) -> void:
	if not alive or invuln > 0.0 or amount <= 0:
		return
	hp -= amount
	invuln = GameConfig.PLAYER_INVULN
	_flash = FLASH_TIME
	var dir: float = signf(global_position.x - from.x)
	if dir == 0.0:
		dir = 1.0
	velocity.x = dir * KNOCKBACK_X
	if is_on_floor():
		velocity.y = KNOCKBACK_Y
	damaged.emit(amount)
	if hp <= 0:
		hp = 0
		alive = false
		died.emit()


func heal(amount: int) -> void:
	if amount <= 0:
		return
	hp = mini(hp + amount, max_hp)


func add_gold(n: int) -> void:
	gold += n


func add_exp(n: int) -> void:
	if n <= 0:
		return
	exp += n
	while exp >= GameConfig.exp_to_next(level):
		exp -= GameConfig.exp_to_next(level)
		level += 1
		max_hp += GameConfig.LEVEL_HP_STEP
		hp = max_hp
		leveled_up.emit(level)


## 开新局：等级/经验/金币/生命全部重置。
func reset_for_new_game() -> void:
	level = 1
	exp = 0
	gold = 0
	max_hp = GameConfig.PLAYER_MAX_HP
	hp = max_hp
	alive = true
	invuln = 0.0
	combo = 0
	combo_timer = 0.0
	_attack_stage_total = 0
	_hits = 0
	_hit_ids.clear()
	_action = ""
	_attack_active = 0.0
	_attack_cd = 0.0
	_skill_cd = 0.0
	_ghost_cd = 0.0
	_close_box()


## 重开关卡：数值归位，但保留当前生命。
func reset_stats_keep_hp() -> void:
	var keep_hp: int = clampi(hp, 1, max_hp)
	level = 1
	exp = 0
	gold = 0
	max_hp = GameConfig.PLAYER_MAX_HP
	hp = clampi(keep_hp, 1, max_hp)
	alive = true
	invuln = 0.0
	combo = 0
	combo_timer = 0.0
	_attack_stage_total = 0
	_hits = 0
	_hit_ids.clear()
	_action = ""
	_attack_active = 0.0
	_attack_cd = 0.0
	_skill_cd = 0.0
	_ghost_cd = 0.0
	_close_box()


# =========================================================
# 工具
# =========================================================
func _set_combo(value: int) -> void:
	if combo == value:
		return
	combo = value
	combo_changed.emit(value)


## 玩家世界 AABB（脚底坐标 → 矩形）。
func get_rect() -> Rect2:
	return Rect2(global_position.x - 9.0, global_position.y - 40.0, 18.0, 40.0)


func is_dead() -> bool:
	return not alive
