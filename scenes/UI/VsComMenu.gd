# VsComMenu.gd
# VS COMメニュー ─ マウス操作版

extends "res://scenes/UI/VsMenu.gd"

func _ready() -> void:
	_apply_vs_com_defaults()
	super._ready()

func _apply_vs_com_defaults() -> void:
	if GameData.vs_com_menu["name"][1] == "" or GameData.vs_com_menu["name"][1] == "2P":
		GameData.vs_com_menu["name"][1] = "COM"

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	_lbl(root, "── VS COM メニュー ──")
	root.add_child(HSeparator.new())

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	root.add_child(cols)
	_make_player_panel(cols, 0, "1P")
	_make_player_panel(cols, 1, "COM")
	_add_stage_row(root)

	root.add_child(HSeparator.new())

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)

	var start_shortcut := Shortcut.new()
	var event := InputEventAction.new()
	event.action = "ui_accept"
	start_shortcut.events.append(event)

	var start_btn = _add_btn(action_row, "ゲームスタート", _on_start)
	start_btn.shortcut = start_shortcut

	_add_btn(action_row, "リプレイ保存",   _on_replay_save)
	_add_btn(action_row, "リプレイ読込",   _on_replay_load)
	_add_btn(action_row, "戻る",           _on_back)
	root.add_child(action_row)

func _on_start() -> void:
	_vs_menu_backup()
	GameState.joutai_flag = Enums.JoutaiType.VS_COM_GAME

func _on_replay_save() -> void:
	_vs_menu_backup()
	GameState.vs_replay_return_state = GameState.joutai_flag
	GameState.joutai_flag = Enums.JoutaiType.VS_COM_REPLAY_WRITE

func _on_replay_load() -> void:
	GameState.vs_replay_return_state = GameState.joutai_flag
	GameState.joutai_flag = Enums.JoutaiType.VS_COM_REPLAY_READ

func _vs_menu_backup() -> void:
	GameData.vs_com_menu_tmp = GameData.copy_menu(GameData.vs_com_menu)
