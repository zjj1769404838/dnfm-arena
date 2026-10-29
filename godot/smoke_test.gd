# -*- coding: utf-8 -*-
## dnfm-arena 无头自检。
## ★ 必须 extends Node（不能 extends SceneTree），等帧必须用 physics_frame
##   （无头模式下 process_frame 的位移恒为 0，会产生假失败）。
extends Node

var checks := 0
var fails: Array = []
var main: Node = null
var player: Node2D = null
var hub: Node = null


func _ready() -> void:
	await get_tree().physics_frame
	await _run()


func _check(cond: bool, label: String) -> void:
	checks += 1
	if not cond:
		fails.append(label)
		print("  FAILED: %s" % label)


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _press(action: String, frames: int = 3) -> void:
	Input.action_press(action)
	await _wait(frames)
	Input.action_release(action)


func _run() -> void:
	print("==== dnfm-arena 冒烟测试 ====")
	var packed: PackedScene = load("res://main.tscn")
	_check(packed != null, "main.tscn 可加载")
	if packed == null:
		_finish()
		return
	main = packed.instantiate()
	add_child(main)
	await get_tree().physics_frame
	await _wait(5)

	# [1] 场景与玩家
	print("[1] 场景装配")
	_check(main.has_method("start_game"), "主控提供 start_game()")
	player = main.get("player")
	_check(player != null, "玩家节点存在")
	_check(main.get("world") != null, "世界节点存在")
	_check(main.get("hud") != null, "HUD 节点存在")
	if player == null:
		_finish()
		return
	var sprite: AnimatedSprite2D = player.get_node_or_null("Sprite")
	if sprite == null:
		for c in player.get_children():
			if c is AnimatedSprite2D:
				sprite = c
				break
	_check(sprite != null, "玩家带 AnimatedSprite2D")
	if sprite != null:
		var names: Array = sprite.sprite_frames.get_animation_names()
		_check(names.size() >= 5, "玩家动画数 >= 5 (实际 %d)" % names.size())
		for need in ["idle_breathe", "walk", "attack1", "skill_slash", "ghost_slash"]:
			_check(names.has(need), "玩家含动画 %s" % need)

	# [2] 进入游戏
	print("[2] 状态机")
	main.call("start_game")
	await _wait(10)
	_check(int(main.get("state")) == 1, "start_game 后进入 PLAY 态 (实际 %s)" % str(main.get("state")))

	# [3] 移动
	print("[3] 移动")
	var x_before: float = player.get("position").x
	Input.action_press("p_right")
	await _wait(40)
	Input.action_release("p_right")
	var moved: float = player.get("position").x - x_before
	_check(moved > 30.0, "右移 40 帧位移 %.1fpx > 30" % moved)
	if sprite != null:
		_check(sprite.animation == "walk", "移动中播 walk (实际 %s)" % sprite.animation)

	# [4] 跳跃
	print("[4] 跳跃")
	var y_before: float = player.get("position").y
	Input.action_press("p_jump")
	await _wait(4)
	Input.action_release("p_jump")
	var peak := y_before
	for i in 30:
		await get_tree().physics_frame
		peak = minf(peak, player.get("position").y)
	_check(y_before - peak > 10.0, "起跳抬升 %.1fpx > 10" % (y_before - peak))
	await _wait(40)

	# [5] 连招
	print("[5] 连招")
	await _press("p_attack", 2)
	await _wait(18)
	await _press("p_attack", 2)
	await _wait(18)
	await _press("p_attack", 2)
	await _wait(10)
	var combo := int(player.get("combo"))
	_check(combo >= 2, "连续 3 次普攻连段数 >= 2 (实际 %d)" % combo)
	if sprite != null:
		_check(sprite.animation == "attack1", "攻击播 attack1 (实际 %s)" % sprite.animation)
	await _wait(30)

	# [6] 技能
	print("[6] 技能")
	var box: Area2D = null
	for c in player.get_children():
		if c is Area2D:
			box = c
			break
	_check(box != null, "玩家带攻击判定 Area2D")
	await _press("p_skill", 2)
	await _wait(6)
	if box != null:
		_check(box.monitoring, "技能判定框开启")
	await _wait(30)
	await _press("p_ghost", 2)
	await _wait(6)
	if box != null:
		_check(box.monitoring, "鬼影斩判定框开启")
	await _wait(40)

	# [7] 敌人与波次
	print("[7] 敌人与波次")
	var enemies: Array = main.get("enemies")
	_check(enemies.size() >= 1, "第 1 波已生成敌人 (实际 %d)" % enemies.size())
	if enemies.size() > 0:
		var e: Node2D = enemies[0]
		_check(e.has_method("take_damage"), "敌人可受击")
		player.set("position", e.get("position") + Vector2(-24, 0))
		await _wait(30)
		var dx: float = absf(e.get("position").x - player.get("position").x)
		_check(dx < 70.0, "敌人追击到 70px 内 (实际 %.1f)" % dx)
		var kills_before: int = int(main.get("kills"))
		for en in enemies.duplicate():
			if is_instance_valid(en):
				en.call("take_damage", 999, player.get("position"))
		await _wait(10)
		_check(int(main.get("kills")) > kills_before, "击杀敌人计数增加")
		await _wait(140)
		_check(int(main.get("wave")) >= 1, "清空第 1 波后进入第 2 波 (实际波次 %d)" % int(main.get("wave")))

	# [8] 掉落与成长
	print("[8] 掉落与成长")
	var gold_before: int = int(player.get("gold"))
	var exp_before: int = int(player.get("exp"))
	player.call("add_gold", 5)
	player.call("add_exp", 5)
	await _wait(3)
	_check(int(player.get("gold")) == gold_before + 5, "加金币生效")
	_check(int(player.get("exp")) == exp_before + 5, "加经验生效")
	var lvl_before: int = int(player.get("level"))
	var hp_max_before: int = int(player.get("max_hp"))
	player.call("add_exp", 500)
	await _wait(3)
	_check(int(player.get("level")) > lvl_before, "经验足够后升级 (实际 %d)" % int(player.get("level")))
	_check(int(player.get("max_hp")) > hp_max_before, "升级后生命上限提升")

	# [9] 音频
	print("[9] 音频")
	var bank: Dictionary = main.get("_sfx_bank")
	_check(bank.size() >= 5, "已载入 SFX >= 5 条 (实际 %d)" % bank.size())
	_check(main.get("_bgm") != null, "BGM 播放器已创建")

	# [10] 失败与重开
	print("[10] 失败与重开")
	player.set("invuln", 0.0)
	player.set("hp", 1)
	player.call("take_damage", 999, Vector2.ZERO)
	await _wait(8)
	_check(int(main.get("state")) == 3, "玩家死亡进入 LOSE 态 (实际 %s)" % str(main.get("state")))
	await _press("p_restart", 3)
	await _wait(10)
	_check(int(main.get("state")) == 1, "按 R 重开回到 PLAY 态 (实际 %s)" % str(main.get("state")))
	_check(int(main.get("kills")) == 0, "重开后击杀数归零")

	_finish()


func _finish() -> void:
	print("----")
	print("checks=%d fails=%d" % [checks, fails.size()])
	for f in fails:
		print("  FAILED: %s" % f)
	print("SMOKE %s" % ("PASS" if fails.is_empty() else "FAIL"))
	get_tree().quit(0 if fails.is_empty() else 1)
