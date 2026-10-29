# -*- coding: utf-8 -*-
## 截图工具：Godot --path <project> res://screenshot.tscn -- <输出png绝对路径> [title|play|wave|combo|result]
## ★ 必须窗口模式跑（--headless 下 take_screenshot 会卡死）。
## ★ save_png 必须绝对路径且带扩展名。
extends Node

var out_path: String = ""
var mode: String = "play"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_path = args[0]
	if args.size() > 1:
		mode = args[1]
	if out_path == "":
		out_path = "C:/Users/zjj/AppData/Local/Temp/dnfm_shot.png"
	await get_tree().physics_frame
	await _drive()
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(out_path)
	print("[shot] %s err=%d" % [out_path, err])
	get_tree().quit(0 if err == OK else 1)


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _drive() -> void:
	var main: Node = null
	for c in get_tree().root.get_children():
		if c.has_method("start_game"):
			main = c
			break
	if main == null:
		return
	match mode:
		"title":
			await _wait(20)
		"result":
			main.call("start_game")
			await _wait(20)
			main.set("state", 3)
		_:
			main.call("start_game")
			await _wait(60)
