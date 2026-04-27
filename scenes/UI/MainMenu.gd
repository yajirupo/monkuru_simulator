# MainMenu.gd
# メインメニュー ─ マウス操作版

extends Control

const NEXT_STATES := [
	Enums.JoutaiType.SINGLE_MENU,
	Enums.JoutaiType.VS_MENU,
	Enums.JoutaiType.VS_COM_MENU,
	Enums.JoutaiType.ONLINE_MENU,
	Enums.JoutaiType.KEY_CONFIG_MENU,
	Enums.JoutaiType.SOUND_CONFIG_MENU,
]
const MENU_ITEMS := ["練習モード", "2P対戦", "VS COM", "オンライン対戦", "キーコンフィグ", "音量設定"]

func _ready() -> void:
	_clear_children()
	_build_ui()

func _clear_children() -> void:
	for child in get_children():
		child.free()

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.position = Vector2(50, 40)
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	_lbl(vbox, "── MAIN MENU ──")
	vbox.add_child(HSeparator.new())

	for i in range(MENU_ITEMS.size()):
		var btn := _mk_btn(MENU_ITEMS[i], Vector2(200, 30))
		var idx := i
		btn.pressed.connect(func(): _on_select(idx))
		vbox.add_child(btn)

	vbox.add_child(HSeparator.new())


	var quit_btn := _mk_btn("ゲームを終了", Vector2(200, 30))
	quit_btn.pressed.connect(_on_quit_pressed)
	vbox.add_child(quit_btn)

func _on_select(index: int) -> void:
	GameState.main_menu_cursor = index
	GameState.joutai_flag      = NEXT_STATES[index]

func _on_quit_pressed() -> void:
	var node: Node = self
	while node != null:
		if node.has_method("_quit"):
			node.call("_quit")
			return
		node = node.get_parent()

	var scene := get_tree().current_scene
	if scene != null and scene.has_method("_quit"):
		scene.call("_quit")
		return

	get_tree().quit()

# ── ユーティリティ ──────────────────────────────────────────
# Enterキーで誤作動しないよう全ボタンに FOCUS_NONE を設定
func _mk_btn(text: String, min_size: Vector2 = Vector2.ZERO) -> Button:
	var b := Button.new()
	b.text                = text
	b.focus_mode          = Control.FOCUS_NONE
	b.custom_minimum_size = min_size
	return b

func _lbl(parent: Control, text: String) -> Label:
	var l := Label.new(); l.text = text
	parent.add_child(l); return l
