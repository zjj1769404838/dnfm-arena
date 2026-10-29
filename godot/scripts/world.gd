class_name DungeonWorld
extends Node2D
##
## 地牢世界场景：背景渐变 + 后墙砖缝 + 石柱 + 整段地面 + 火把 + 装饰。
## 全部用代码建节点，不手写 .tscn。严格遵循 docs/contracts.md §4。
##
## 坐标约定：世界坐标原点在左上，Y 向下；地面行 GROUND_ROW → 地面顶 y = 288。
##

const TILE := GameConfig.TILE
const LEVEL_W := GameConfig.LEVEL_W
const LEVEL_H := GameConfig.LEVEL_H
const GROUND_ROW := GameConfig.GROUND_ROW
const GROUND_DEPTH := GameConfig.LEVEL_H - GameConfig.GROUND_ROW   # 地面占 4 行 = 64px

const WALL_BRICK_W := 32          # 砖块宽
const WALL_BRICK_H := 16          # 砖块高
const WALL_MORTAR := 1            # 砖缝线宽
const PILLAR_W := 24
const PILLAR_COUNT := 3
const TORCH_POSITIONS := [48.0, 176.0, 784.0, 912.0]
const TORCH_Y := 176.0
const DECOR_SEED := 20261029

# ---- 公开成员（main.gd 依赖）----
var ground_y: float = 0.0        # 地面顶面 y（= GROUND_ROW * TILE = 288）

var _torches: Array[Node2D] = []
var _time: float = 0.0

# ================================================================ 对外接口
## 由 main.gd 调用一次，搭出整个地牢。
func build() -> void:
	ground_y = GameConfig.ground_y()
	_build_background()
	_build_back_wall()
	_build_pillars()
	_build_ground()
	_build_torches()
	_build_decor()

func _process(delta: float) -> void:
	_time += delta
	# 火把呼吸：正弦缩放 + 轻微亮度脉动
	for i in _torches.size():
		var t := _torches[i]
		if not is_instance_valid(t):
			continue
		var phase := float(i) * 0.7
		var s := 1.0 + 0.12 * sin(_time * 4.0 + phase)
		t.scale = Vector2(s, s)
		var flame := t.get_node_or_null("Flame")
		if flame is Node2D:
			var c := GameConfig.COL_TORCH
			c.a = 0.82 + 0.18 * sin(_time * 6.0 + phase)
			(flame as Node2D).modulate = c

# ================================================================ 背景
## CanvasLayer(layer=-10) + 4 段像素色阶横条（顶 COL_BG_TOP → 底 COL_BG_BOTTOM）
func _build_background() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -10
	layer.name = "Background"
	add_child(layer)

	var vp := get_viewport()
	var view_size := Vector2(GameConfig.VIEW_W, GameConfig.VIEW_H)
	if vp != null:
		var r := vp.get_visible_rect().size
		if r.x > 1.0 and r.y > 1.0:
			view_size = r

	var bands := 4
	var band_h := view_size.y / float(bands)
	var top := GameConfig.COL_BG_TOP
	var bottom := GameConfig.COL_BG_BOTTOM
	for i in bands:
		var t := float(i) / float(bands - 1)
		var col := top.lerp(bottom, t)
		var rect := ColorRect.new()
		rect.color = col
		rect.position = Vector2(0.0, band_h * float(i))
		rect.size = Vector2(view_size.x, band_h + 1.0)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(rect)

# ================================================================ 后墙
## 砖缝网格：逐行铺 COL_WALL 底块 + COL_WALL_LINE 竖缝/横缝
func _build_back_wall() -> void:
	var wall := Node2D.new()
	wall.name = "BackWall"
	wall.z_index = -20
	add_child(wall)

	var cols := int(LEVEL_W * TILE)
	var wall_h := int(GROUND_ROW * TILE)
	var rows := int(ceil(float(wall_h) / float(WALL_BRICK_H)))

	for r in rows:
		var y := float(r * WALL_BRICK_H)
		var brick := ColorRect.new()
		brick.color = GameConfig.COL_WALL
		brick.position = Vector2(0.0, y)
		brick.size = Vector2(float(cols), float(WALL_BRICK_H))
		wall.add_child(brick)

		# 竖缝：偶数行从 0 开始，奇数行错半块（错缝排列）
		var offset := 0 if r % 2 == 0 else WALL_BRICK_W / 2
		var x := offset
		while x < cols:
			var seam := ColorRect.new()
			seam.color = GameConfig.COL_WALL_LINE
			seam.position = Vector2(float(x) - float(WALL_MORTAR), y)
			seam.size = Vector2(float(WALL_MORTAR), float(WALL_BRICK_H))
			wall.add_child(seam)
			x += WALL_BRICK_W

		# 横缝
		var line := ColorRect.new()
		line.color = GameConfig.COL_WALL_LINE
		line.position = Vector2(0.0, y + float(WALL_BRICK_H) - float(WALL_MORTAR))
		line.size = Vector2(float(cols), float(WALL_MORTAR))
		wall.add_child(line)

# ================================================================ 石柱
## 2~3 根竖直石柱（柱身 + 柱头 + 柱础），制造纵深
func _build_pillars() -> void:
	var layer := Node2D.new()
	layer.name = "Pillars"
	layer.z_index = -15
	add_child(layer)

	var cols := int(LEVEL_W * TILE)
	for i in PILLAR_COUNT:
		var fx := (float(i) + 0.5) / float(PILLAR_COUNT)
		var cx := fx * float(cols)
		var top_y := 32.0 + 24.0 * float(i % 2)

		var body := ColorRect.new()
		body.color = GameConfig.COL_WALL.lerp(GameConfig.COL_BG_TOP, 0.15)
		body.position = Vector2(cx - float(PILLAR_W) * 0.5, top_y)
		body.size = Vector2(float(PILLAR_W), ground_y - top_y)
		layer.add_child(body)

		# 柱身描边（两侧竖线）
		for side in 2:
			var edge := ColorRect.new()
			edge.color = GameConfig.COL_WALL_LINE
			edge.position = Vector2(
				cx - float(PILLAR_W) * 0.5 + (0.0 if side == 0 else float(PILLAR_W) - float(WALL_MORTAR)),
				top_y
			)
			edge.size = Vector2(float(WALL_MORTAR), ground_y - top_y)
			layer.add_child(edge)

		# 柱头
		var cap := ColorRect.new()
		cap.color = GameConfig.COL_WALL.lerp(GameConfig.COL_FLOOR_TOP, 0.25)
		cap.position = Vector2(cx - float(PILLAR_W) * 0.5 - 4.0, top_y - 10.0)
		cap.size = Vector2(float(PILLAR_W) + 8.0, 10.0)
		layer.add_child(cap)

		# 柱础
		var base := ColorRect.new()
		base.color = GameConfig.COL_WALL.lerp(GameConfig.COL_FLOOR_TOP, 0.15)
		base.position = Vector2(cx - float(PILLAR_W) * 0.5 - 3.0, ground_y - 8.0)
		base.size = Vector2(float(PILLAR_W) + 6.0, 8.0)
		layer.add_child(base)

# ================================================================ 地面
## 整段地面合并成 1 个矩形碰撞体；视觉逐 16px 画地砖，顶面亮色
func _build_ground() -> void:
	var body := StaticBody2D.new()
	body.name = "Ground"
	body.collision_layer = 4      # 地形层（玩家 mask=4）
	body.collision_mask = 0       # 静态物体不需要掩码
	body.position = Vector2(0.0, ground_y)
	add_child(body)

	var cols := int(LEVEL_W * TILE)
	var depth_px := float(GROUND_DEPTH * TILE)

	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(float(cols), depth_px)
	shape.shape = rect
	shape.position = Vector2(float(cols) * 0.5, depth_px * 0.5)
	body.add_child(shape)

	# 视觉：顶面逐砖亮色条 + 砖缝竖线；下方整体暗色
	var top_h := 6.0
	for c in LEVEL_W:
		var x := float(c * TILE)
		var tile := ColorRect.new()
		tile.color = GameConfig.COL_FLOOR_TOP
		tile.position = Vector2(x, 0.0)
		tile.size = Vector2(float(TILE), top_h)
		body.add_child(tile)

		var gap := ColorRect.new()
		gap.color = GameConfig.COL_WALL_LINE
		gap.position = Vector2(x + float(TILE) - float(WALL_MORTAR), 0.0)
		gap.size = Vector2(float(WALL_MORTAR), top_h)
		body.add_child(gap)

	var fill := ColorRect.new()
	fill.color = GameConfig.COL_FLOOR
	fill.position = Vector2(0.0, top_h)
	fill.size = Vector2(float(cols), depth_px - top_h)
	body.add_child(fill)

	# 顶面下方一道暗色阴影带，增加层次
	var shade := ColorRect.new()
	shade.color = GameConfig.COL_WALL_LINE
	shade.position = Vector2(0.0, top_h)
	shade.size = Vector2(float(cols), 2.0)
	body.add_child(shade)

# ================================================================ 火把
## 两侧各 2 个：Polygon2D 火焰 + 正弦呼吸缩放
func _build_torches() -> void:
	for i in TORCH_POSITIONS.size():
		var x: float = TORCH_POSITIONS[i]
		var torch := Node2D.new()
		torch.name = "Torch%d" % i
		torch.position = Vector2(x, TORCH_Y)
		torch.z_index = -5
		add_child(torch)

		# 支架
		var stick := ColorRect.new()
		stick.color = GameConfig.COL_WALL_LINE
		stick.position = Vector2(-1.0, 6.0)
		stick.size = Vector2(2.0, 18.0)
		torch.add_child(stick)

		# 火焰（菱形）
		var flame := Polygon2D.new()
		flame.name = "Flame"
		flame.color = GameConfig.COL_TORCH
		flame.polygon = PackedVector2Array([
			Vector2(0.0, -10.0),
			Vector2(5.0, -2.0),
			Vector2(0.0, 6.0),
			Vector2(-5.0, -2.0),
		])
		torch.add_child(flame)

		# 内焰（亮色小菱形）
		var core := Polygon2D.new()
		core.name = "Core"
		core.color = Color(1.0, 0.92, 0.72)
		core.polygon = PackedVector2Array([
			Vector2(0.0, -5.0),
			Vector2(2.0, 0.0),
			Vector2(0.0, 3.0),
			Vector2(-2.0, 0.0),
		])
		torch.add_child(core)

		_torches.append(torch)

# ================================================================ 装饰
## 固定种子随机摆放碎石 / 骨头，保证每次运行一致
func _build_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = DECOR_SEED

	var layer := Node2D.new()
	layer.name = "Decor"
	layer.z_index = -8
	add_child(layer)

	var cols := int(LEVEL_W * TILE)

	# 地面碎石
	for i in 26:
		var x := rng.randf_range(8.0, float(cols) - 8.0)
		var w := rng.randf_range(2.0, 5.0)
		var h := rng.randf_range(2.0, 3.0)
		var rock := ColorRect.new()
		rock.color = GameConfig.COL_FLOOR.lerp(GameConfig.COL_BG_TOP, rng.randf_range(0.1, 0.5))
		rock.position = Vector2(x, ground_y - h)
		rock.size = Vector2(w, h)
		layer.add_child(rock)

	# 墙上骨头（横放的一节 + 两端骨节）
	for i in 8:
		var bx := rng.randf_range(16.0, float(cols) - 32.0)
		var by := rng.randf_range(40.0, ground_y - 60.0)
		var bone := ColorRect.new()
		bone.color = GameConfig.COL_DIM.lerp(GameConfig.COL_WALL, 0.45)
		bone.position = Vector2(bx, by)
		bone.size = Vector2(12.0, 3.0)
		layer.add_child(bone)
		for k in 2:
			var knob := ColorRect.new()
			knob.color = bone.color
			knob.position = Vector2(bx + (0.0 if k == 0 else 10.0), by - 1.5)
			knob.size = Vector2(3.0, 6.0)
			layer.add_child(knob)
