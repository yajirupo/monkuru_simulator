# VsComMenu.gd
# VS COMメニュー ─ マウス操作版

extends "res://scenes/UI/VsMenu.gd"

func _ready() -> void:
	randomize()
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
	start_btn.shortcut_in_tooltip = false
	start_btn.tooltip_text = "Enter"

	_add_btn(action_row, "ランダム選択",       _on_random)
	_add_btn(action_row, "リプレイ保存",   _on_replay_save)
	_add_btn(action_row, "リプレイ読込",   _on_replay_load)
	var back_btn = _add_btn(action_row, "戻る", _on_back)
	back_btn.shortcut_in_tooltip = false
	back_btn.tooltip_text = "Esc"
	root.add_child(action_row)

func _on_random() -> void:
	var menu := GameData.vs_com_menu

	var char_candidates := _candidate_indices(Constants.get_character_count(),
		func(i: int): return Constants.get_character_name(i) != "ボドリ")
	var kuru_candidates := _candidate_indices(Constants.get_kuru_count(),
		func(i: int): return Constants.get_kuru_name(i) != "升ンガン")
	var item_candidates := _candidate_indices(ITEM_NAMES.size(),
		func(i: int): return i != 0)
	var stage_candidates := _candidate_indices(GameState.STAGE_COUNT,
		func(_i: int): return true)

	for pi in range(2):
		menu["player_type"][pi] = _pick_random(char_candidates)
		menu["kuru_type"][pi] = _pick_random(kuru_candidates)
		for slot in range(3):
			menu["item_type"][pi][slot] = _pick_random(item_candidates)

	menu["stage"] = _pick_random(stage_candidates)
	_update_display()

func _candidate_indices(count: int, predicate: Callable) -> Array[int]:
	var result: Array[int] = []
	for i in range(count):
		if predicate.call(i):
			result.append(i)
	return result

func _pick_random(candidates: Array[int]) -> int:
	if candidates.is_empty():
		return 0
	return candidates[randi_range(0, candidates.size() - 1)]

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
