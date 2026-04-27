# VsMenu.gd
# 2P対戦メニュー ─ マウス操作版

extends Control

const ITEM_NAMES      := ["無し", "くるロケット", "透明マント", "スピード靴", "くる兄弟"]

var _name_btns:  Array[Button]   = [null, null]
var _name_edits: Array[LineEdit] = [null, null]
var _update_fns: Array[Callable] = []
var _status_lbls: Array[Label] = [null, null]

func _ready() -> void:
	_clear_children()
	_build_ui()
	_update_display()

func _clear_children() -> void:
	for child in get_children():
		child.free()

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	_lbl(root, "── 2P対戦メニュー ──")
	root.add_child(HSeparator.new())

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	root.add_child(cols)
	_make_player_panel(cols, 0, "1P")
	_make_player_panel(cols, 1, "2P")
	_add_stage_row(root)

	root.add_child(HSeparator.new())

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)

	# 1. Enterキー用のショートカットを作成
	var start_shortcut := Shortcut.new()
	var event := InputEventAction.new()
	event.action = "ui_accept" # デフォルトでEnterやSpaceが割り当てられているアクション
	start_shortcut.events.append(event)

	# 2. ボタン生成（戻り値としてボタンを受け取れるようにするか、直接設定する）
	var start_btn = _add_btn(action_row, "ゲームスタート", _on_start)
	start_btn.shortcut = start_shortcut # ここでショートカットを割り当て
	
	_add_btn(action_row, "リプレイ保存",   _on_replay_save)
	_add_btn(action_row, "リプレイ読込",   _on_replay_load)
	_add_btn(action_row, "戻る",           _on_back)
	root.add_child(action_row)

func _make_player_panel(parent: Control, pi: int, title: String) -> void:
	var menu := GameData.active_vs_menu()
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	parent.add_child(vbox)

	_lbl(vbox, "── %s ──" % title)

	# 名前
	var name_row := HBoxContainer.new()
	_lbl_w(name_row, "名前：", 90)
	_name_btns[pi] = _mk_btn("")
	_name_btns[pi].custom_minimum_size.x = 80
	_name_btns[pi].pressed.connect(func(): _on_name_btn_pressed(pi))
	name_row.add_child(_name_btns[pi])
	_name_edits[pi] = LineEdit.new()
	_name_edits[pi].custom_minimum_size.x = 80
	_name_edits[pi].visible = false
	_name_edits[pi].text_submitted.connect(func(t: String): _on_name_submitted(pi, t))
	name_row.add_child(_name_edits[pi])
	vbox.add_child(name_row)
	_update_fns.append(func():
		if not _name_edits[pi].visible:
			_name_btns[pi].text = menu["name"][pi])

	# キャラ
	_arrow_row(vbox, "キャラ",
		func(): return Constants.get_character_name(menu["player_type"][pi]),
		func(): menu["player_type"][pi] = wrapi(menu["player_type"][pi] - 1, 0, Constants.get_character_count()),
		func(): menu["player_type"][pi] = wrapi(menu["player_type"][pi] + 1, 0, Constants.get_character_count()))

	# くる
	_arrow_row(vbox, "くる",
		func(): return Constants.get_kuru_name(menu["kuru_type"][pi]),
		func(): menu["kuru_type"][pi] = wrapi(menu["kuru_type"][pi] - 1, 0, Constants.get_kuru_count()),
		func(): menu["kuru_type"][pi] = wrapi(menu["kuru_type"][pi] + 1, 0, Constants.get_kuru_count()))

	_status_lbls[pi] = Label.new()
	_status_lbls[pi].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_lbls[pi].custom_minimum_size.x = 300
	vbox.add_child(_status_lbls[pi])
	_update_fns.append(func():
		var st := Constants.get_status_with_kuru_bonus(menu["player_type"][pi], menu["kuru_type"][pi])
		_status_lbls[pi].text = "速度:%d%s  パワー:%d%s  くる数:%d%s\nくる速度:%d  くる段階:%d  発射間隔:%.1f秒" % [
			st["speed_base"], Constants.format_signed_bonus(st["speed_bonus"]),
			st["power_base"], Constants.format_signed_bonus(st["power_bonus"]),
			st["shot_base"], Constants.format_signed_bonus(st["shot_bonus"]),
			st["kuru_speed"], st["kuru_dankai"], st["kuru_kankaku"] / 60.0
		])

	# アイテム
	for i in range(3):
		var slot := i
		_arrow_row(vbox, "アイテム%d" % (i + 1),
			func(): return ITEM_NAMES[menu["item_type"][pi][slot]],
			func(): menu["item_type"][pi][slot] = wrapi(menu["item_type"][pi][slot] - 1, 0, 5),
			func(): menu["item_type"][pi][slot] = wrapi(menu["item_type"][pi][slot] + 1, 0, 5))


# ── ユーティリティ ──────────────────────────────────────────
func _mk_btn(text: String) -> Button:
	var b := Button.new()
	b.text       = text
	b.focus_mode = Control.FOCUS_NONE
	return b

func _add_btn(parent: Control, text: String, cb: Callable) -> Button:
	var b := _mk_btn(text)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _lbl(parent: Control, text: String) -> Label:
	var l := Label.new(); l.text = text
	parent.add_child(l); return l

func _lbl_w(parent: Control, text: String, w: float) -> Label:
	var l := _lbl(parent, text)
	l.custom_minimum_size.x = w; return l

func _arrow_row(parent: Control, label_text: String,
		get_fn: Callable, dec_fn: Callable, inc_fn: Callable) -> void:
	var hbox := HBoxContainer.new()
	_lbl_w(hbox, label_text + "：", 90)
	var bl := _mk_btn("◀")
	bl.pressed.connect(func(): dec_fn.call(); _update_display())
	hbox.add_child(bl)
	var vl := Label.new()
	vl.custom_minimum_size.x = 70
	vl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(vl)
	var br := _mk_btn("▶")
	br.pressed.connect(func(): inc_fn.call(); _update_display())
	hbox.add_child(br)
	parent.add_child(hbox)
	_update_fns.append(func(): vl.text = get_fn.call())

func _add_stage_row(parent: Control) -> void:
	var menu := GameData.active_vs_menu()
	_arrow_row(parent, "ステージ",
		func(): return GameState.get_stage_name(menu["stage"]),
		func(): menu["stage"] = wrapi(menu["stage"] - 1, 0, GameState.STAGE_COUNT),
		func(): menu["stage"] = wrapi(menu["stage"] + 1, 0, GameState.STAGE_COUNT))

# ── 名前入力 ────────────────────────────────────────────────
func _on_name_btn_pressed(pi: int) -> void:
	var menu := GameData.active_vs_menu()
	_name_edits[pi].text    = menu["name"][pi]
	_name_btns[pi].visible  = false
	_name_edits[pi].visible = true
	_name_edits[pi].grab_focus()
	_name_edits[pi].select_all()

func _on_name_submitted(pi: int, new_name: String) -> void:
	var menu := GameData.active_vs_menu()
	var t := new_name.strip_edges()
	if t != "":
		menu["name"][pi] = t
	_name_btns[pi].text     = menu["name"][pi]
	_name_edits[pi].visible = false
	_name_btns[pi].visible  = true

# ── アクション ──────────────────────────────────────────────
func _on_start() -> void:
	_vs_menu_backup()
	GameState.joutai_flag = Enums.JoutaiType.VS_GAME

func _on_replay_save() -> void:
	_vs_menu_backup()
	GameState.vs_replay_return_state = GameState.joutai_flag
	GameState.joutai_flag = Enums.JoutaiType.VS_REPLAY_WRITE

func _on_replay_load() -> void:
	GameState.vs_replay_return_state = GameState.joutai_flag
	GameState.joutai_flag = Enums.JoutaiType.VS_REPLAY_READ

func _on_back() -> void:
	GameState.joutai_flag = Enums.JoutaiType.MAIN_MENU

func _vs_menu_backup() -> void:
	GameData.vs_menu_tmp = GameData.copy_menu(GameData.vs_menu)

func _update_display() -> void:
	for fn in _update_fns:
		fn.call()
