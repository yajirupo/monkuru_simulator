# KeyConfig.gd
# キーコンフィグ ─ キー割り当て画面
#
# 【キー配列インデックスの実際の対応】
#   index 0 = Right / index 1 = Left / index 2 = Down / index 3 = Up
#   index 4 = Shot  / index 5 = Item1 / index 6 = Item2 / index 7 = Item3
#
# 【画面表示順】上・下・左・右・ショット・アイテム1・アイテム2・アイテム3
# CURSOR_TO_SLOT でカーソル位置 → 実際の配列インデックスを変換する。

extends Control

const ACTION_LABELS := ["上", "下", "左", "右", "ショット", "アイテム1", "アイテム2", "アイテム3"]

# カーソル位置（表示順）→ use_key_* 配列の実インデックス
# 表示: 上(0)・下(1)・左(2)・右(3)・Shot(4)・Item1(5)・Item2(6)・Item3(7)
# 実体: Up=3 / Down=2 / Left=1 / Right=0 / Shot=4 / Item1=5 / Item2=6 / Item3=7
const CURSOR_TO_SLOT: Array[int] = [3, 2, 1, 0, 4, 5, 6, 7]

var _title_lbl: Label
var _key_rows:  Array[Label] = []
var _guide_lbl: Label
var _row_nodes: Array[Node]  = []   # 各行ノードへの直接参照（マーカー更新用）

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
	root.add_theme_constant_override("separation", 2)
	add_child(root)

	_title_lbl = Label.new()
	root.add_child(_title_lbl)
	root.add_child(HSeparator.new())

	# ── キー一覧 ────────────────────────────────────────────
	for i in range(8):
		var hbox := HBoxContainer.new()

		var action_lbl := Label.new()
		action_lbl.text                = "%s：" % ACTION_LABELS[i]
		action_lbl.custom_minimum_size = Vector2(130, 0)
		hbox.add_child(action_lbl)

		var key_lbl := Label.new()
		key_lbl.custom_minimum_size = Vector2(120, 0)
		hbox.add_child(key_lbl)
		_key_rows.append(key_lbl)

		var marker := Label.new()
		marker.text    = "← 設定中"
		marker.visible = false
		hbox.add_child(marker)
		hbox.set_meta("marker", marker)

		root.add_child(hbox)
		_row_nodes.append(hbox)

	root.add_child(HSeparator.new())

	_guide_lbl = Label.new()
	root.add_child(_guide_lbl)

	root.add_child(HSeparator.new())

	var back_btn := Button.new()
	back_btn.text                = "キーコンフィグメニューへ戻る"
	back_btn.custom_minimum_size = Vector2(240, 28)
	back_btn.focus_mode          = Control.FOCUS_NONE
	back_btn.pressed.connect(func(): GameState.joutai_flag = Enums.JoutaiType.KEY_CONFIG_MENU)
	root.add_child(back_btn)

# ── キー検出 ────────────────────────────────────────────────
func _process(_delta: float) -> void:
	for i in range(256):
		if KeyInput.key[i] == 1 and i != KeyInput.KEY_INPUT_ESCAPE:
			var godot_key: int = KeyInput._dx_to_godot[i] if i < KeyInput._dx_to_godot.size() else 0
			# カーソル位置を実配列スロットに変換してから代入
			var slot: int = CURSOR_TO_SLOT[GameState.key_config_cursor]
			match GameState.joutai_flag:
				Enums.JoutaiType.KEY_CONFIG_SINGLE:
					GameState.use_key_single[slot] = godot_key
				Enums.JoutaiType.KEY_CONFIG_VS_1P:
					GameState.use_key_vs_1p[slot]  = godot_key
				Enums.JoutaiType.KEY_CONFIG_VS_2P:
					GameState.use_key_vs_2p[slot]  = godot_key
			if GameState.key_config_cursor < 7:
				GameState.key_config_cursor += 1
			else:
				GameState.joutai_flag = Enums.JoutaiType.KEY_CONFIG_MENU
			break
	_update_display()

# ── 表示更新 ────────────────────────────────────────────────
func _update_display() -> void:
	var jf := GameState.joutai_flag

	if _title_lbl:
		match jf:
			Enums.JoutaiType.KEY_CONFIG_SINGLE: _title_lbl.text = "KEY CONFIG ─ 練習 / オンライン用"
			Enums.JoutaiType.KEY_CONFIG_VS_1P:  _title_lbl.text = "KEY CONFIG ─ VS 1P 用"
			Enums.JoutaiType.KEY_CONFIG_VS_2P:  _title_lbl.text = "KEY CONFIG ─ VS 2P 用"

	var keys: Array[int] = GameState.use_key_single
	match jf:
		Enums.JoutaiType.KEY_CONFIG_VS_1P: keys = GameState.use_key_vs_1p
		Enums.JoutaiType.KEY_CONFIG_VS_2P: keys = GameState.use_key_vs_2p

	# 表示順（cursor i）に対応する実スロット CURSOR_TO_SLOT[i] のキー名を表示
	for i in range(_key_rows.size()):
		if _key_rows[i]:
			var slot: int = CURSOR_TO_SLOT[i]
			_key_rows[i].text = OS.get_keycode_string(keys[slot]) if keys[slot] > 0 else "---"

	# マーカー（← 設定中）の表示切替
	for i in range(_row_nodes.size()):
		var row_node := _row_nodes[i]
		if row_node and row_node.has_meta("marker"):
			var marker := row_node.get_meta("marker") as Label
			if marker:
				marker.visible = (i == GameState.key_config_cursor)

	if _guide_lbl:
		var cur := GameState.key_config_cursor
		if cur < 8:
			_guide_lbl.text = "「%s」のキーを押してください（%d / 8）" % [ACTION_LABELS[cur], cur + 1]
		else:
			_guide_lbl.text = "設定完了"
