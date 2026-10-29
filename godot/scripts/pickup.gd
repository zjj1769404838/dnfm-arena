class_name Pickup
extends Area2D
##
## 掉落物：gold（黄色菱形）/ exp（蓝色圆珠），上下浮动，玩家靠近 14px 自动拾取。
## 严格遵循 docs/contracts.md §4。
##
## 节点 position = 掉落物中心的世界坐标（由 main.gd 在敌人尸体位置调用 spawn_at 传入）。
##

const PICK_RADIUS := 14.0
const FLOAT_AMP := 3.0
const FLOAT_SPEED := 3.0

# ---- 公开成员 ----
var kind: String = "gold"        # "gold" | "exp"
var value: int = 0
var game: Node = null             # main.gd，on_pickup(kind, value) 回调
var target: Node2D = null         # 玩家

var _base_y: float = 0.0
var _time: float = 0.0
var _taken: bool = false
var _sprite: Node2D = null

# ================================================================ 生命周期
func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = false
	_base_y = position.y
	if _sprite == null:
		_build_visual()

# ================================================================ 对外接口
## kind: "gold" | "exp"；value: 金币数 / 经验数；sf: 精灵表（可选，本对象用几何图形绘制，保留入参以对齐契约）
func setup(kind: String, value: int, sf: SpriteFrames = null) -> void:
	self.kind = kind
	self.value = value
	_build_visual()
	_base_y = position.y

## 静态工厂：在 pos 处生成一个已 add_child 完成的掉落物。
## 返回节点实例（调用方可直接改 game / target）。
static func spawn_at(parent: Node, kind: String, value: int, pos: Vector2) -> Pickup:
	var p := Pickup.new()
	p.setup(kind, value, null)
	p.position = pos
	if parent != null:
		# parent 视为玩法层（main.gd），自动接上 game 回调
		p.game = parent
		parent.add_child(p)
	return p

## 绑定玩法层：game 提供 on_pickup(kind, value)，target 为玩家节点
func bind(game_ref: Node, target_ref: Node2D) -> void:
	game = game_ref
	target = target_ref

## 单独设置拾取目标（main.gd 用 set_target 调用）
func set_target(target_ref: Node2D) -> void:
	target = target_ref

## 单独设置玩法层引用
func set_game(game_ref: Node) -> void:
	game = game_ref

# ================================================================ 主循环
func _process(delta: float) -> void:
	_time += delta
	if _sprite != null:
		_sprite.position.y = -sin(_time * FLOAT_SPEED) * FLOAT_AMP

	if _taken:
		return
	if target == null or not is_instance_valid(target):
		return
	var dist := global_position.distance_to(target.global_position)
	if dist <= PICK_RADIUS:
		_collect()

func _collect() -> void:
	_taken = true
	if game != null and is_instance_valid(game):
		if game.has_method("on_pickup"):
			game.call("on_pickup", kind, value)
	queue_free()

# ================================================================ 内部
func _build_visual() -> void:
	if _sprite != null and is_instance_valid(_sprite):
		_sprite.queue_free()
		_sprite = null

	var node: Node2D = null
	match kind:
		"exp":
			node = _make_exp()
		_:
			node = _make_gold()
	if node == null:
		return
	_sprite = node
	add_child(node)

## 黄色菱形 + 深色描边
func _make_gold() -> Node2D:
	var root := Node2D.new()
	root.name = "Gold"

	var shadow := Polygon2D.new()
	shadow.color = GameConfig.COL_EXP_BG
	shadow.polygon = PackedVector2Array([
		Vector2(0.0, -7.0), Vector2(6.0, 0.0), Vector2(0.0, 7.0), Vector2(-6.0, 0.0),
	])
	shadow.position = Vector2(0.0, 1.0)
	root.add_child(shadow)

	var body := Polygon2D.new()
	body.color = GameConfig.COL_GOLD
	body.polygon = PackedVector2Array([
		Vector2(0.0, -6.0), Vector2(5.0, 0.0), Vector2(0.0, 6.0), Vector2(-5.0, 0.0),
	])
	root.add_child(body)

	# 左上高光
	var shine := Polygon2D.new()
	shine.color = Color(1.0, 0.95, 0.72)
	shine.polygon = PackedVector2Array([
		Vector2(0.0, -3.5), Vector2(2.0, -1.0), Vector2(0.0, 0.5), Vector2(-2.0, -1.0),
	])
	root.add_child(shine)
	return root

## 蓝色圆珠 + 深色描边环
func _make_exp() -> Node2D:
	var root := Node2D.new()
	root.name = "Exp"

	var ring := Polygon2D.new()
	ring.color = GameConfig.COL_EXP_BG
	ring.polygon = _circle_points(6.0, 10)
	root.add_child(ring)

	var body := Polygon2D.new()
	body.color = GameConfig.COL_EXP
	body.polygon = _circle_points(5.0, 10)
	root.add_child(body)

	var shine := Polygon2D.new()
	shine.color = Color(0.78, 0.92, 1.0)
	shine.polygon = _circle_points(1.8, 8)
	shine.position = Vector2(-1.6, -1.6)
	root.add_child(shine)
	return root

## 用多边形近似圆（像素风：边数少更硬朗）
func _circle_points(radius: float, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps:
		var a := TAU * float(i) / float(steps)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts
