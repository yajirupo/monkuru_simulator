# VsComMenu.gd
# VS COMメニュー ─ マウス操作版

extends "res://scenes/UI/VsMenu.gd"

var _com_view_index: int = 1

func _ready() -> void:
	randomize()
	_apply_vs_com_defaults()
	super._ready()

func _apply_vs_com_defaults() -> void:
	for i in range(1, Constants.MAX_PLAYER):
		if GameData.vs_com_menu["name"][i] == "" or GameData.vs_com_menu["name"][i] == "2P" or GameData.vs_com_menu["name"][i] == "COM":
			GameData.vs_com_menu["name"][i] = "COM%d" % i

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	_lbl(root, "── VS COM メニュー ──")
	root.add_child(HSeparator.new())
	
	_ensure_character_overlay()
	_ensure_kuru_overlay()
	_ensure_item_overlay()
	_ensure_stage_overlay()

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	root.add_child(cols)
	_make_player_panel(cols, 0, "1P")
	_make_com_panel(cols)
	_add_stage_row(root)
	_arrow_row(root, "COM人数",
		func(): return str(int(GameData.vs_com_menu.get("com_count", 1))),
		func(): GameData.vs_com_menu["com_count"] = Constants.MAX_PLAYER - 1 if int(GameData.vs_com_menu.get("com_count", 1)) <= 1 else int(GameData.vs_com_menu.get("com_count", 1)) - 1,
		func(): GameData.vs_com_menu["com_count"] = 1 if int(GameData.vs_com_menu.get("com_count", 1)) >= Constants.MAX_PLAYER - 1 else int(GameData.vs_com_menu.get("com_count", 1)) + 1)

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

	_add_btn(action_row, "全ランダム",       _on_random)
	_add_btn(action_row, "COMランダム",       _on_com_random)
	_add_btn(action_row, "COM統一",           _on_com_bundle)
	_add_btn(action_row, "リプレイ保存",   _on_replay_save)
	_add_btn(action_row, "リプレイ読込",   _on_replay_load)
	var back_btn = _add_btn(action_row, "戻る", _on_back)
	back_btn.shortcut_in_tooltip = false
	back_btn.tooltip_text = "Esc"
	root.add_child(action_row)

func _make_com_panel(parent: Control) -> void:
	var menu := GameData.vs_com_menu
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	parent.add_child(vbox)
	_lbl(vbox, "── COM ──")

	var name_row := HBoxContainer.new()
	_lbl_w(name_row, "名前：", 90)
	var bl := _mk_btn("◀")
	bl.pressed.connect(func():
		_normalize_com_view_index()
		var com_count := _active_com_count()
		_com_view_index = ((_com_view_index - 2 + com_count) % com_count) + 1
		_update_display())
	name_row.add_child(bl)
	var name_lbl := Label.new()
	name_lbl.custom_minimum_size.x = 70
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_row.add_child(name_lbl)
	var br := _mk_btn("▶")
	br.pressed.connect(func():
		_normalize_com_view_index()
		var com_count := _active_com_count()
		_com_view_index = (_com_view_index % com_count) + 1
		_update_display())
	name_row.add_child(br)
	vbox.add_child(name_row)
	_update_fns.append(func(): name_lbl.text = menu["name"][_com_view_index])

	_make_character_row(vbox,
		func(): return menu["player_type"][_com_view_index],
		func(v: int): menu["player_type"][_com_view_index] = v)
	_make_kuru_row(vbox,
		func(): return menu["kuru_type"][_com_view_index],
		func(v: int): menu["kuru_type"][_com_view_index] = v)

	var status_lbl := Label.new()
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_lbl.custom_minimum_size.x = 300
	vbox.add_child(status_lbl)
	_update_fns.append(func():
		var st := Constants.get_status_with_kuru_bonus(menu["player_type"][_com_view_index], menu["kuru_type"][_com_view_index])
		status_lbl.text = "速度:%d%s  パワー:%d%s  くる数:%d%s\nくる速度:%d  くる段階:%d  発射間隔:%.1f秒" % [
			st["speed_base"], Constants.format_signed_bonus(st["speed_bonus"]),
			st["power_base"], Constants.format_signed_bonus(st["power_bonus"]),
			st["shot_base"], Constants.format_signed_bonus(st["shot_bonus"]),
			st["kuru_speed_stat"], st["kuru_dankai"], st["kuru_kankaku"] / 60.0
		])
	for i in range(3):
		var slot := i
		_arrow_row(vbox, "アイテム%d" % (i + 1),
			func(): return ITEM_NAMES[menu["item_type"][_com_view_index][slot]],
			func(): menu["item_type"][_com_view_index][slot] = wrapi(menu["item_type"][_com_view_index][slot] - 1, 0, 5),
			func(): menu["item_type"][_com_view_index][slot] = wrapi(menu["item_type"][_com_view_index][slot] + 1, 0, 5),
			# ▼ オーバーレイ表示用コールバックを追加
			func():
				_item_overlay.show_overlay(func(new_val: int):
					menu["item_type"][_com_view_index][slot] = new_val
					_update_display()
				)
		)
		
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

	var com_count: int = int(menu.get("com_count", 1))
	for pi in range(com_count + 1):
		menu["player_type"][pi] = _pick_random(char_candidates)
		menu["kuru_type"][pi] = _pick_random(kuru_candidates)
		for slot in range(3):
			menu["item_type"][pi][slot] = _pick_random(item_candidates)

	menu["stage"] = _pick_random(stage_candidates)
	_update_display()

func _on_com_random() -> void:
	var menu := GameData.vs_com_menu

	var char_candidates := _candidate_indices(Constants.get_character_count(),
		func(i: int): return Constants.get_character_name(i) != "ボドリ")
	var kuru_candidates := _candidate_indices(Constants.get_kuru_count(),
		func(i: int): return Constants.get_kuru_name(i) != "升ンガン")
	var item_candidates := _candidate_indices(ITEM_NAMES.size(),
		func(i: int): return i != 0)

	for i in range(1, Constants.MAX_PLAYER):
		menu["player_type"][i] = _pick_random(char_candidates)
		menu["kuru_type"][i] = _pick_random(kuru_candidates)
		for slot in range(3):
			menu["item_type"][i][slot] = _pick_random(item_candidates)

	_update_display()

func _on_com_bundle() -> void:
	var menu := GameData.vs_com_menu
	_normalize_com_view_index()
	var src = _com_view_index
	for i in range(1, Constants.MAX_PLAYER):
		menu["player_type"][i] = menu["player_type"][src]
		menu["kuru_type"][i] = menu["kuru_type"][src]
		menu["item_type"][i] = menu["item_type"][src].duplicate(true)
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

func _update_display() -> void:
	_normalize_com_view_index()
	super._update_display()

func _active_com_count() -> int:
	return clampi(int(GameData.vs_com_menu.get("com_count", 1)), 1, Constants.MAX_PLAYER - 1)

func _normalize_com_view_index() -> void:
	var com_count := _active_com_count()
	_com_view_index = clampi(_com_view_index, 1, com_count)
