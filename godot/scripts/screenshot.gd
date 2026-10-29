extends Node
## 窗口模式截图工具（--headless 会卡死，必须带窗口跑）
## 用法：Godot --path . res://screenshot.tscn -- <mode> <输出png绝对路径>
## mode: title / play / result

var _mode: String = "title"
var _out: String = ""
var _frames: int = 0
var _shots: int = 0
var _game: Node = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_mode = String(args[0])
	if args.size() >= 2:
		_out = String(args[1])
	if _out == "":
		_out = "C:/Users/zjj/AppData/Local/Temp/dnfm_shot.png"
	_game = load("res://main.tscn").instantiate()
	add_child(_game)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_run()


func _run() -> void:
	match _mode:
		"title":
			await get_tree().create_timer(0.4).timeout
			_capture()
		"play":
			_game.call("start_game")
			await get_tree().create_timer(1.2).timeout
			_capture()
		"result":
			_game.call("start_game")
			await get_tree().create_timer(0.6).timeout
			_game.call("_enter_win")
			await get_tree().create_timer(0.5).timeout
			_capture()
		_:
			_capture()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0)


func _capture() -> void:
	var img: Image = get_viewport().get_texture().get_image()
	_shots += 1
	var path := _out
	if _shots > 1:
		var base := _out.get_basename()
		var ext := _out.get_extension()
		path = base + "_" + str(_shots) + "." + ext
	img.save_png(path)
	print("[shot] %s -> %s" % [_mode, path])
