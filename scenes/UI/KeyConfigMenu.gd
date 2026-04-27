# KeyConfigMenu.gd
# キーコンフィグ選択メニュー ─ マウス操作版

extends Control

func _ready() -> void:
	_clear_children()
	GameState.key_config_menu_cursor = 0
	_build_ui()

func _clear_children() -> void:
	for child in get_children():
		child.free()

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.position = Vector2(50, 40)
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	_lbl(vbox, "── キーコンフィグ ──")
	vbox.add_child(HSeparator.new())

	_make_btn(vbox, 0, "練習・オンライン用", Enums.JoutaiType.KEY_CONFIG_SINGLE)
	_make_btn(vbox, 1, "VS 1P 用",           Enums.JoutaiType.KEY_CONFIG_VS_1P)
	_make_btn(vbox, 2, "VS 2P 用",           Enums.JoutaiType.KEY_CONFIG_VS_2P)

	vbox.add_child(HSeparator.new())


	var back_btn := Button.new()
	back_btn.text                = "メインメニューへ戻る"
	back_btn.custom_minimum_size = Vector2(220, 30)
	back_btn.focus_mode          = Control.FOCUS_NONE
	back_btn.pressed.connect(func(): GameState.joutai_flag = Enums.JoutaiType.MAIN_MENU)
	vbox.add_child(back_btn)

func _make_btn(parent: Control, cursor_idx: int, label: String, next_state: int) -> void:
	var btn := Button.new()
	btn.text                = label
	btn.custom_minimum_size = Vector2(220, 30)
	btn.focus_mode          = Control.FOCUS_NONE
	btn.pressed.connect(func():
		GameState.key_config_menu_cursor = cursor_idx
		GameState.key_config_cursor      = 0
		GameState.joutai_flag            = next_state)
	parent.add_child(btn)

func _lbl(parent: Control, text: String) -> Label:
	var l := Label.new(); l.text = text
	parent.add_child(l); return l
