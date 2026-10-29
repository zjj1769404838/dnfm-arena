# -*- coding: utf-8 -*-
## Enemy —— dnfm-arena 敌人（goblin / brute）。
##
## 契约见 docs/contracts.md §3。要点：
##   * 节点 position = 脚底坐标；精灵 centered=false / offset=(-48,-96)。
##   * 碰撞：collision_layer=2（敌人层，玩家攻击框 mask=2 命中它），
##     collision_mask=4（地形层）。敌人之间互斥用代码推开，不进物理层。
##   * AI：追击玩家 → 进入攻击距离停下挥击 → 回调 game.on_enemy_attack(self, damage)
##     → 受击闪红 + 击退（brute 减半）→ hp 归零 queue_free 并回调 game.on_enemy_killed(self)。
class_name Enemy extends CharacterBody2D

# ---------------- 数值表（契约 §3 表格） ----------------
const GOBLIN_HP := 26
const GOBLIN_SPEED := 56.0
const GOBLIN_ATTACK_RANGE := 26.0
const GOBLIN_DAMAGE := 4
const GOBLIN_ATTACK_INTERVAL := 0.9
const GOBLIN_EXP := 6
const GOBLIN_GOLD := 3
const GOBLIN_SIZE := Vector2(18.0, 38.0)

const BRUTE_HP := 70
const BRUTE_SPEED := 38.0
const BRUTE_ATTACK_RANGE := 36.0
const BRUTE_DAMAGE := 9
const BRUTE_ATTACK_INTERVAL := 1.5
const BRUTE_EXP := 16
const BRUTE_GOLD := 8
const BRUTE_SIZE := Vector2(26.0, 50.0)

const MAX_FALL := 520.0
const KNOCKBACK_DECAY := 6.0
const FLASH_TIME := 0.12
const WINDUP_TELL := 0.18     # 挥击前摇期间红色警示闪光的呼吸频率（Hz）
const SEPARATION := 14.0      # 敌人之间互斥间距
const SEPARATION_FORCE := 46.0
const ATTACK_WINDUP := 0.18   # 挥击前摇

# ---------------- 公开成员（契约 §3） ----------------
var hp: int = 0
var kind: String = "goblin"
var dead: bool = false

# ---------------- 内部状态 ----------------
var target: Node2D = null
var game: Node = null

var _sf: SpriteFrames = null
var _sprite: AnimatedSprite2D = null
var _built: bool = false

var _max_hp: int = GOBLIN_HP
var _speed: float = GOBLIN_SPEED
var _attack_range: float = GOBLIN_ATTACK_RANGE
var _damage: int = GOBLIN_DAMAGE
var _attack_interval: float = GOBLIN_ATTACK_INTERVAL
var _exp_value: int = GOBLIN_EXP
var _gold_value: int = GOBLIN_GOLD
var _body_size: Vector2 = GOBLIN_SIZE
var _knockback_scale: float = 1.0

var _attack_timer: float = 0.0
var _windup: float = 0.0
var _tell_phase: float = 0.0   # 前摇警示呼吸相位
var _flash: float = 0.0
var _knockback: Vector2 = Vector2.ZERO
var _facing: int = 1
var _spawn_pos: Vector2 = Vector2.ZERO


# =========================================================
# 构建
# =========================================================
func _ready() -> void:
	_ensure_built()


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	collision_layer = 2
	collision_mask = 4
	motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
	floor_snap_length = 6.0
	add_to_group("enemy")

	_sprite = AnimatedSprite2D.new()
	_sprite.centered = false
	_sprite.offset = Vector2(-48.0, -96.0)
	add_child(_sprite)
	if _sf != null:
		_sprite.sprite_frames = _sf
		_play_anim("walk")


## 契约 §3：setup(target, game, kind, sf)。
func setup(target_node: Node2D, game_node: Node, enemy_kind: String, sf: SpriteFrames) -> void:
	kind = enemy_kind
	target = target_node
	game = game_node
	_sf = sf
	_spawn_pos = position

	match kind:
		"brute":
			_max_hp = BRUTE_HP
			_speed = BRUTE_SPEED
			_attack_range = BRUTE_ATTACK_RANGE
			_damage = BRUTE_DAMAGE
			_attack_interval = BRUTE_ATTACK_INTERVAL
			_exp_value = BRUTE_EXP
			_gold_value = BRUTE_GOLD
			_body_size = BRUTE_SIZE
			_knockback_scale = 0.5      # brute 击退减半
		_:
			kind = "goblin"
			_max_hp = GOBLIN_HP
			_speed = GOBLIN_SPEED
			_attack_range = GOBLIN_ATTACK_RANGE
			_damage = GOBLIN_DAMAGE
			_attack_interval = GOBLIN_ATTACK_INTERVAL
			_exp_value = GOBLIN_EXP
			_gold_value = GOBLIN_GOLD
			_body_size = GOBLIN_SIZE
			_knockback_scale = 1.0

	hp = _max_hp
	dead = false

	_ensure_built()
	_apply_body_shape()
	_repair_frames(sf)
	if _sprite != null and sf != null:
		_sprite.sprite_frames = sf
		_play_anim("walk")


# =========================================================
# 精灵表校正
# =========================================================
## 导出数据里 goblin / brute 的 action 同名（都叫 "walk"），
## 主控按 action 建表会把两者混进同一动画、甚至建出空表。
## 这里按 index.json 的 char + frames 期望值校正一次，主控修好后即为空操作。
func _repair_frames(sf: SpriteFrames) -> void:
	if sf == null:
		return
	var spec: Dictionary = _enemy_animspec()
	for anim_name in spec.keys():
		var info: Dictionary = spec[anim_name]
		var want: int = int(info.get("frames", 1))
		if sf.has_animation(anim_name) and sf.get_frame_count(anim_name) == want:
			continue
		_rebuild_animation(sf, anim_name, String(info.get("godot", "")))


## index.json 里 char == kind 的动画清单：{ action: { frames, godot } }。
func _enemy_animspec() -> Dictionary:
	var spec: Dictionary = {}
	for entry in _export_actions():
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = entry
		if String(e.get("char", "")) != kind:
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


## 用导出的 .tres 重建单个动画。
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


func _apply_body_shape() -> void:
	for c in get_children():
		if c is CollisionShape2D:
			c.queue_free()
	var shape_node := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = _body_size
	shape_node.shape = rect
	shape_node.position = Vector2(0.0, -_body_size.y * 0.5)
	add_child(shape_node)


# =========================================================
# 主循环
# =========================================================
func _physics_process(delta: float) -> void:
	if dead:
		return

	_attack_timer = maxf(0.0, _attack_timer - delta)
	_flash = maxf(0.0, _flash - delta)
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta * 60.0)

	velocity.y = minf(velocity.y + GameConfig.PLAYER_GRAVITY * delta, MAX_FALL)

	if _windup > 0.0:
		# 挥击前摇：短暂停顿，播攻击表现
		_windup = maxf(0.0, _windup - delta)
		_tell_phase += delta
		velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
		if _windup <= 0.0:
			_swing()
	elif _knockback.length() > 1.0:
		velocity.x = _knockback.x
	else:
		_chase(delta)

	velocity.x += _separation_push() * delta

	move_and_slide()
	_update_visual()


func _chase(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
		return

	var to_target: Vector2 = target.global_position - global_position
	var dist: float = absf(to_target.x)

	if dist <= _attack_range:
		# 进入攻击距离 → 停下并周期性挥击
		velocity.x = move_toward(velocity.x, 0.0, 500.0 * delta)
		_face(int(signf(to_target.x)))
		if _attack_timer <= 0.0:
			_attack_timer = _attack_interval
			_windup = ATTACK_WINDUP
			_tell_phase = 0.0
			_play_anim("walk")
	else:
		_face(int(signf(to_target.x)))
		velocity.x = move_toward(velocity.x, _speed * float(_facing), 600.0 * delta)

	# 掉出世界 → 自我清除
	if global_position.y > float(GameConfig.LEVEL_H * GameConfig.TILE) + 64.0:
		dead = true
		queue_free()


func _face(dir: int) -> void:
	var d: int = 1 if dir >= 0 else -1
	if d != _facing:
		_facing = d
		if _sprite != null:
			_sprite.flip_h = d < 0


## 敌人之间轻微互斥：同层横向推开，避免完全重叠。
func _separation_push() -> float:
	var push: float = 0.0
	for other in get_tree().get_nodes_in_group("enemy"):
		if other == self or not is_instance_valid(other):
			continue
		var e := other as Enemy
		if e == null or e.dead:
			continue
		if e.position.y != position.y:
			continue
		var dx: float = global_position.x - e.global_position.x
		var gap: float = absf(dx)
		if gap < SEPARATION and gap > 0.01:
			var dir: float = signf(dx)
			push += dir * (SEPARATION - gap) * SEPARATION_FORCE / SEPARATION
	return push


# =========================================================
# 攻击与受击
# =========================================================
func _swing() -> void:
	if game != null and is_instance_valid(game) and game.has_method("on_enemy_attack"):
		game.call("on_enemy_attack", self, _damage)
	# 挥击后短暂僵直，避免贴脸无限连击
	_attack_timer = maxf(_attack_timer, _attack_interval * 0.5)


## 玩家攻击框命中入口（契约 §2 hit_enemy 反馈 + §3 受击闪红击退）。
func take_damage(amount: int, from: Vector2) -> void:
	if dead or amount <= 0:
		return
	hp -= amount
	_flash = FLASH_TIME

	var dir: float = signf(global_position.x - from.x)
	if dir == 0.0:
		dir = -_facing
	var power: float = 150.0 * _knockback_scale
	_knockback = Vector2(dir * power, -90.0 * _knockback_scale)
	velocity.x = _knockback.x

	if hp <= 0:
		_die()


func _die() -> void:
	if dead:
		return
	dead = true
	hp = 0
	if game != null and is_instance_valid(game) and game.has_method("on_enemy_killed"):
		game.call("on_enemy_killed", self)
	queue_free()


# =========================================================
# 视觉
# =========================================================
func _update_visual() -> void:
	if _sprite == null:
		return
	# 受击：白闪 + 过曝（分量 >1 在加色混合下发白，「被砍中」一眼可见）
	if _flash > 0.0:
		_sprite.modulate = Color(1.8, 1.2, 1.2, 1.0)
		return
	# 攻击前摇：红色警示呼吸，给玩家预判窗口
	if _windup > 0.0:
		var pulse: float = 0.5 + 0.5 * sin(_tell_phase * TAU * WINDUP_TELL)
		_sprite.modulate = Color(1.0, 1.0 - 0.4 * pulse, 1.0 - 0.4 * pulse, 1.0)
		return
	_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)


func _play_anim(name: String) -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return
	var sf: SpriteFrames = _sprite.sprite_frames
	var target: String = name
	if not sf.has_animation(target):
		# 契约写的是 goblin_walk / brute_walk，导出的 .tres 里动画名是 walk，
		# 两种命名都兜住。
		var alt: String = kind + "_walk"
		if sf.has_animation(alt):
			target = alt
		elif sf.has_animation("walk"):
			target = "walk"
		else:
			return
	if _sprite.animation != target or not _sprite.is_playing():
		_sprite.play(target)


# =========================================================
# 公开工具
# =========================================================
## 世界 AABB（脚底坐标 → 矩形）。
func get_rect() -> Rect2:
	return Rect2(global_position.x - _body_size.x * 0.5, global_position.y - _body_size.y, _body_size.x, _body_size.y)


func is_alive() -> bool:
	return not dead


## 掉落用的经验 / 金币数值。
func get_exp_value() -> int:
	return _exp_value


func get_gold_value() -> int:
	return _gold_value


## 复位到出生点（重开关卡时用）。
func reset() -> void:
	dead = false
	hp = _max_hp
	position = _spawn_pos
	velocity = Vector2.ZERO
	_knockback = Vector2.ZERO
	_attack_timer = 0.0
	_windup = 0.0
	_tell_phase = 0.0
	_flash = 0.0
