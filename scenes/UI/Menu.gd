# Menu.gd
# 練習メニュー ─ マウス操作版

extends Control

const ITEM_NAMES := ["無し", "くるロケット", "透明マント", "スピード靴", "くる兄弟"]

var _name_btn:   Button
var _name_edit:  LineEdit
var _update_fns: Array[Callable] = []

var _item_overlay: ItemSelectOverlay = null
var _stage_overlay: StageSelectOverlay = null

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
	root.add_theme_constant_override("separation", 3)
	add_child(root)
	
	_ensure_item_overlay()
	_ensure_stage_overlay()

	_lbl(root, "── 練習メニュー ──")
	root.add_child(HSeparator.new())

	# ── 名前（クリックで入力欄表示） ──────────────────────────
	var name_row := HBoxContainer.new()
	_lbl_w(name_row, "名前：", 110)
	_name_btn = _mk_btn("")
	_name_btn.custom_minimum_size.x = 100
	_name_btn.pressed.connect(_on_name_btn_pressed)
	name_row.add_child(_name_btn)
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size.x = 100
	_name_edit.visible = false
	_name_edit.text_submitted.connect(_on_name_submitted)
	name_row.add_child(_name_edit)
	root.add_child(name_row)
	_update_fns.append(func():
		if not _name_edit.visible:
			_name_btn.text = GameData.menu["name"])

	root.add_child(HSeparator.new())

	# ── パラメータ行（◀ 値 ▶） ──────────────────────────────
	_arrow_row(root, "速度",
		func(): return str(GameData.menu["speed"]),
		func(): GameData.menu["speed"] = _wrap(GameData.menu["speed"] - 1, 0, 50),
		func(): GameData.menu["speed"] = _wrap(GameData.menu["speed"] + 1, 0, 50))
	_arrow_row(root, "パワー",
		func(): return str(GameData.menu["power"]),
		func(): GameData.menu["power"] = _wrap(GameData.menu["power"] - 1, 0, 20),
		func(): GameData.menu["power"] = _wrap(GameData.menu["power"] + 1, 0, 20))
	_arrow_row(root, "くる数",
		func(): return str(GameData.menu["shot"]),
		func(): GameData.menu["shot"] = _wrap(GameData.menu["shot"] - 1, 0, 50),
		func(): GameData.menu["shot"] = _wrap(GameData.menu["shot"] + 1, 0, 50))
	_arrow_row(root, "くる速度",
		func(): return str(GameData.menu["kuru_speed"]),
		func(): GameData.menu["kuru_speed"] = _wrap(GameData.menu["kuru_speed"] - 1, -3, 50),
		func(): GameData.menu["kuru_speed"] = _wrap(GameData.menu["kuru_speed"] + 1, -3, 50))
	_arrow_row(root, "くる段階",
		func(): return str(GameData.menu["kuru_dankai"]),
		func(): GameData.menu["kuru_dankai"] = _wrap(GameData.menu["kuru_dankai"] - 1, 4, 10),
		func(): GameData.menu["kuru_dankai"] = _wrap(GameData.menu["kuru_dankai"] + 1, 4, 10))
	_arrow_row(root, "発射間隔",
		func(): return "%.2f" % (GameData.menu["kuru_kankaku"] / 60.0),
		func(): GameData.menu["kuru_kankaku"] = _wrap(GameData.menu["kuru_kankaku"] - 3, 0, 30),
		func(): GameData.menu["kuru_kankaku"] = _wrap(GameData.menu["kuru_kankaku"] + 3, 0, 30))
	
	root.add_child(HSeparator.new())

	# ── アイテム行 ────────────────────────────────────────────
	for i in range(3):
		var slot := i
		_arrow_row(root, "アイテム%d" % (i + 1),
			func(): return ITEM_NAMES[GameData.menu["item_type"][slot]],
			func(): GameData.menu["item_type"][slot] = _wrap(GameData.menu["item_type"][slot] - 1, 0, 4),
			func(): GameData.menu["item_type"][slot] = _wrap(GameData.menu["item_type"][slot] + 1, 0, 4),
			# ▼ 追加：オーバーレイ表示用コールバック
			func():
				_item_overlay.show_overlay(func(new_val: int):
					GameData.menu["item_type"][slot] = new_val
					_update_display()
				)
		)
	
	root.add_child(HSeparator.new())
	
	_arrow_row(root, "ステージ",
		func(): return GameState.get_stage_name(GameData.menu["stage"]),
		func(): GameData.menu["stage"] = _wrap(GameData.menu["stage"] - 1, 0, GameState.STAGE_COUNT - 1),
		func(): GameData.menu["stage"] = _wrap(GameData.menu["stage"] + 1, 0, GameState.STAGE_COUNT - 1),
		# ▼ 追加
		func():
			_stage_overlay.show_overlay(func(new_val: int):
				GameData.menu["stage"] = new_val
				_update_display()
			)
	)
	
	root.add_child(HSeparator.new())

	# ── アクションボタン ─────────────────────────────────────
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
	start_btn.shortcut_in_tooltip = false
	start_btn.tooltip_text = "Enter"
	
	_add_btn(action_row, "リプレイ保存",   _on_replay_save)
	_add_btn(action_row, "リプレイ読込",   _on_replay_load)
	var back_btn = _add_btn(action_row, "戻る", _on_back)
	back_btn.shortcut_in_tooltip = false
	back_btn.tooltip_text = "Esc"
	root.add_child(action_row)

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
		get_fn: Callable, dec_fn: Callable, inc_fn: Callable,
		overlay_callback: Callable = Callable()) -> void:   # ★ 引数を追加
	var hbox := HBoxContainer.new()
	_lbl_w(hbox, label_text + "：", 110)
	var bl := _mk_btn("◀")
	bl.pressed.connect(func(): dec_fn.call(); _update_display())
	hbox.add_child(bl)

	# ★ オーバーレイ用コールバックがあれば Button、なければ Label
	if overlay_callback.is_valid():
		var val_btn := _mk_btn("")
		val_btn.custom_minimum_size.x = 80
		val_btn.pressed.connect(overlay_callback)
		hbox.add_child(val_btn)
		_update_fns.append(func(): val_btn.text = get_fn.call())
	else:
		var vl := Label.new()
		vl.custom_minimum_size.x = 80
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hbox.add_child(vl)
		_update_fns.append(func(): vl.text = get_fn.call())

	var br := _mk_btn("▶")
	br.pressed.connect(func(): inc_fn.call(); _update_display())
	hbox.add_child(br)
	parent.add_child(hbox)

func _wrap(val: int, lo: int, hi: int) -> int:
	if val > hi: return lo
	if val < lo: return hi
	return val

# ── 名前入力 ────────────────────────────────────────────────
func _on_name_btn_pressed() -> void:
	_name_edit.text    = GameData.menu["name"]
	_name_btn.visible  = false
	_name_edit.visible = true
	_name_edit.grab_focus()
	_name_edit.select_all()

func _on_name_submitted(new_name: String) -> void:
	var t := new_name.strip_edges()
	if t != "":
		GameData.menu["name"] = t
	_name_btn.text     = GameData.menu["name"]
	_name_edit.visible = false
	_name_btn.visible  = true

# ── アクション ──────────────────────────────────────────────
func _on_start() -> void:
	_menu_backup()
	GameState.joutai_flag = Enums.JoutaiType.SINGLE_GAME

func _on_replay_save() -> void:
	_menu_backup()
	GameState.joutai_flag = Enums.JoutaiType.SINGLE_REPLAY_WRITE

func _on_replay_load() -> void:
	GameState.joutai_flag = Enums.JoutaiType.SINGLE_REPLAY_READ

func _on_back() -> void:
	GameState.joutai_flag = Enums.JoutaiType.MAIN_MENU

func _menu_backup() -> void:
	GameData.menu_tmp = GameData.copy_menu(GameData.menu)

func _update_display() -> void:
	for fn in _update_fns:
		fn.call()

func _ensure_item_overlay() -> void:
	if _item_overlay == null:
		_item_overlay = ItemSelectOverlay.new()
		add_child(_item_overlay)

func _ensure_stage_overlay() -> void:
	if _stage_overlay == null:
		_stage_overlay = StageSelectOverlay.new()
		add_child(_stage_overlay)
