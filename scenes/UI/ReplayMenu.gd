# ReplayMenu.gd
# リプレイ保存 / 読込スロット選択 ─ クリック即実行版

extends Control

const GRID_SIZE := 10
const REPLAY_DIR := "user://replays/"
const REPLAY_EXT := ".dat"
const TERMINATOR := 255

var _title_lbl: Label
var _back_btn:  Button   # 直接参照でテキストを更新する
var _slot_btns: Array[Button] = []
var _hover_info_lbl: RichTextLabel

func _ready() -> void:
	_clear_children()
	_build_ui()
	_update_display()

func _clear_children() -> void:
	for child in get_children():
		child.free()

func _build_ui() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	root.add_child(left)

	_title_lbl = Label.new()
	left.add_child(_title_lbl)
	left.add_child(HSeparator.new())

	# ── 10×10 スロットグリッド ─────────────────────────────
	var grid := GridContainer.new()
	grid.columns = GRID_SIZE
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	left.add_child(grid)

	for n in range(GRID_SIZE * GRID_SIZE):
		var btn := Button.new()
		btn.text                = "%02d" % n
		btn.custom_minimum_size = Vector2(36, 22)
		btn.focus_mode          = Control.FOCUS_NONE
		var slot := n
		btn.pressed.connect(func(): _on_slot_pressed(slot))
		btn.mouse_entered.connect(func(): _on_slot_hovered(slot))
		btn.mouse_exited.connect(_on_slot_hover_exited)
		grid.add_child(btn)
		_slot_btns.append(btn)

	left.add_child(HSeparator.new())

	# ── 戻るボタン ────────────────────────────────────────
	_back_btn = Button.new()
	_back_btn.custom_minimum_size = Vector2(180, 28)
	_back_btn.focus_mode          = Control.FOCUS_NONE
	_back_btn.pressed.connect(_on_back)
	left.add_child(_back_btn)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(240, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)

	var info_title := Label.new()
	info_title.text = "リプレイ情報（スロットにカーソル）"
	right.add_child(info_title)
	right.add_child(HSeparator.new())

	_hover_info_lbl = RichTextLabel.new()
	_hover_info_lbl.bbcode_enabled = true
	_hover_info_lbl.fit_content = true
	_hover_info_lbl.scroll_active = true
	_hover_info_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hover_info_lbl.text = "スロットにカーソルを合わせると内容を表示します。"
	right.add_child(_hover_info_lbl)

# ── スロットクリック → 即実行 ──────────────────────────────
func _on_slot_pressed(slot: int) -> void:
	var jf := GameState.joutai_flag
	match jf:
		Enums.JoutaiType.SINGLE_REPLAY_READ:
			if ReplayManager.replay_data_read(slot):
				GameState.joutai_flag = Enums.JoutaiType.SINGLE_REPLAY
		Enums.JoutaiType.SINGLE_REPLAY_WRITE:
			ReplayManager.replay_data_write(slot)
			GameState.joutai_flag = Enums.JoutaiType.SINGLE_MENU
		Enums.JoutaiType.VS_REPLAY_READ:
			if VsReplayManager.vs_replay_data_read(slot):
				GameState.joutai_flag = Enums.JoutaiType.VS_REPLAY
		Enums.JoutaiType.VS_REPLAY_WRITE:
			VsReplayManager.vs_replay_data_write(slot)
			GameState.joutai_flag = Enums.JoutaiType.VS_MENU
		Enums.JoutaiType.VS_COM_REPLAY_READ:
			if VsComReplayManager.vs_com_replay_data_read(slot):
				GameState.joutai_flag = Enums.JoutaiType.VS_COM_REPLAY
		Enums.JoutaiType.VS_COM_REPLAY_WRITE:
			VsComReplayManager.vs_com_replay_data_write(slot)
			GameState.joutai_flag = Enums.JoutaiType.VS_COM_MENU
		Enums.JoutaiType.ONLINE_REPLAY_READ:
			if OnlineReplayManager.online_replay_data_read(slot):
				GameState.joutai_flag = Enums.JoutaiType.ONLINE_REPLAY
		Enums.JoutaiType.ONLINE_REPLAY_WRITE:
			OnlineReplayManager.online_replay_data_write(slot)
			GameState.joutai_flag = Enums.JoutaiType.ONLINE_MENU

func _on_back() -> void:
	var jf := GameState.joutai_flag
	match jf:
		Enums.JoutaiType.SINGLE_REPLAY_READ, Enums.JoutaiType.SINGLE_REPLAY_WRITE:
			GameState.joutai_flag = Enums.JoutaiType.SINGLE_MENU
		Enums.JoutaiType.VS_REPLAY_READ, Enums.JoutaiType.VS_REPLAY_WRITE:
			GameState.joutai_flag = Enums.JoutaiType.VS_MENU
		Enums.JoutaiType.VS_COM_REPLAY_READ, Enums.JoutaiType.VS_COM_REPLAY_WRITE:
			GameState.joutai_flag = Enums.JoutaiType.VS_COM_MENU
		Enums.JoutaiType.ONLINE_REPLAY_READ, Enums.JoutaiType.ONLINE_REPLAY_WRITE:
			GameState.joutai_flag = Enums.JoutaiType.ONLINE_MENU

func _on_slot_hovered(slot: int) -> void:
	if _hover_info_lbl == null:
		return
	_hover_info_lbl.text = _build_slot_info_text(slot)

func _on_slot_hover_exited() -> void:
	if _hover_info_lbl == null:
		return
	_hover_info_lbl.text = "スロットにカーソルを合わせると内容を表示します。"

func _update_display() -> void:
	var jf := GameState.joutai_flag

	if _title_lbl:
		match jf:
			Enums.JoutaiType.SINGLE_REPLAY_READ:  _title_lbl.text = "PRACTICE REPLAY ─ 読み込むスロットをクリック"
			Enums.JoutaiType.SINGLE_REPLAY_WRITE: _title_lbl.text = "PRACTICE REPLAY ─ 保存先スロットをクリック"
			Enums.JoutaiType.VS_REPLAY_READ:      _title_lbl.text = "VS REPLAY ─ 読み込むスロットをクリック"
			Enums.JoutaiType.VS_REPLAY_WRITE:     _title_lbl.text = "VS REPLAY ─ 保存先スロットをクリック"
			Enums.JoutaiType.VS_COM_REPLAY_READ:  _title_lbl.text = "VS COM REPLAY ─ 読み込むスロットをクリック"
			Enums.JoutaiType.VS_COM_REPLAY_WRITE: _title_lbl.text = "VS COM REPLAY ─ 保存先スロットをクリック"
			Enums.JoutaiType.ONLINE_REPLAY_READ:  _title_lbl.text = "ONLINE REPLAY ─ 読み込むスロットをクリック"
			Enums.JoutaiType.ONLINE_REPLAY_WRITE: _title_lbl.text = "ONLINE REPLAY ─ 保存先スロットをクリック"

	# _back_btn は直接参照なので確実にテキストを更新できる
	if _back_btn:
		match jf:
			Enums.JoutaiType.SINGLE_REPLAY_READ, Enums.JoutaiType.SINGLE_REPLAY_WRITE:
				_back_btn.text = "練習メニューへ戻る"
			Enums.JoutaiType.VS_REPLAY_READ, Enums.JoutaiType.VS_REPLAY_WRITE:
				_back_btn.text = "対戦メニューへ戻る"
			Enums.JoutaiType.VS_COM_REPLAY_READ, Enums.JoutaiType.VS_COM_REPLAY_WRITE:
				_back_btn.text = "VS COMメニューへ戻る"
			Enums.JoutaiType.ONLINE_REPLAY_READ, Enums.JoutaiType.ONLINE_REPLAY_WRITE:
				_back_btn.text = "オンラインメニューへ戻る"

func _build_slot_info_text(slot: int) -> String:
	var path := _get_replay_path(slot)
	if not FileAccess.file_exists(path):
		return "[b]Slot %02d[/b]\n未保存です。" % slot

	var jf := GameState.joutai_flag
	if jf == Enums.JoutaiType.SINGLE_REPLAY_READ or jf == Enums.JoutaiType.SINGLE_REPLAY_WRITE:
		return _build_single_info_text(path, slot)
	return _build_vs_info_text(path, slot)

func _get_replay_path(slot: int) -> String:
	var jf := GameState.joutai_flag
	if jf == Enums.JoutaiType.SINGLE_REPLAY_READ or jf == Enums.JoutaiType.SINGLE_REPLAY_WRITE:
		return REPLAY_DIR + "plac%02d%s" % [slot, REPLAY_EXT]
	if jf == Enums.JoutaiType.VS_REPLAY_READ or jf == Enums.JoutaiType.VS_REPLAY_WRITE:
		return REPLAY_DIR + "vs%02d%s" % [slot, REPLAY_EXT]
	if jf == Enums.JoutaiType.ONLINE_REPLAY_READ or jf == Enums.JoutaiType.ONLINE_REPLAY_WRITE:
		return REPLAY_DIR + "online%02d%s" % [slot, REPLAY_EXT]
	return REPLAY_DIR + "vscom%02d%s" % [slot, REPLAY_EXT]

func _build_single_info_text(path: String, slot: int) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "[b]Slot %02d[/b]\n読み込みに失敗しました。" % slot

	var stage := int(f.get_8())
	var name2 := _read_string(f, 32)
	var speed := int(f.get_32())
	var shot := int(f.get_32())
	var power := int(f.get_32())
	var kuru_speed_raw := int(f.get_32())
	var kuru_speed := kuru_speed_raw if kuru_speed_raw < 0x80000000 else kuru_speed_raw - 0x100000000
	var kuru_dankai := int(f.get_32())
	var kuru_kankaku := int(f.get_32())
	for _i in range(3):
		f.get_32()
	_skip_single_replay_input(f)
	var chats := _read_chat_preview(f)
	f.close()

	var lines: Array[String] = []
	lines.append("[b]Slot %02d[/b]（練習）" % slot)
	lines.append("ステージ: %s" % GameState.get_stage_name(stage))
	lines.append("名前: %s" % name2)
	lines.append("ステータス: 速度%d / 弾数%d / 火力%d" % [speed, shot, power])
	lines.append("くる: 速度%d / 段階%d / 間隔%d" % [kuru_speed, kuru_dankai, kuru_kankaku])
	lines.append(_format_chat_lines(chats))
	return "\n".join(lines)

func _build_vs_info_text(path: String, slot: int) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "[b]Slot %02d[/b]\n読み込みに失敗しました。" % slot

	var stage := int(f.get_8())
	var players: Array[Dictionary] = []
	for _i in range(2):
		var pname := _read_string(f, 32)
		var character := int(f.get_32())
		var kuru_type := int(f.get_32())
		for _j in range(3):
			f.get_32()
		players.append({
			"name": pname,
			"character": character,
			"kuru_type": kuru_type,
		})
	_skip_vs_replay_input(f)
	var chats := _read_chat_preview(f)
	f.close()

	var lines: Array[String] = []
	lines.append("[b]Slot %02d[/b]" % slot)
	lines.append("ステージ: %s" % GameState.get_stage_name(stage))
	lines.append("")
	for i in range(players.size()):
		var p := players[i]
		lines.append("P%d: %s" % [i + 1, p["name"]])
		lines.append("  キャラ: %s" % Constants.get_character_name(int(p["character"])))
		lines.append("  くる: %s" % Constants.get_kuru_name(int(p["kuru_type"])))
		lines.append("")
	lines.append(_format_chat_lines(chats))
	return "\n".join(lines)

func _read_online_sync_count(f: FileAccess) -> int:
	if f.get_position() >= f.get_length():
		return 0
	return int(f.get_16())

func _skip_single_replay_input(f: FileAccess) -> void:
	while f.get_position() < f.get_length():
		var b := f.get_8()
		if b == TERMINATOR:
			break

func _skip_vs_replay_input(f: FileAccess) -> void:
	while f.get_position() < f.get_length():
		var _b0 := f.get_8()
		if f.get_position() >= f.get_length():
			break
		var b1 := f.get_8()
		if b1 == TERMINATOR:
			break

func _read_chat_preview(f: FileAccess) -> Array[String]:
	var chats: Array[String] = []
	if f.get_position() >= f.get_length():
		return chats
	var count := int(f.get_16())
	for _i in range(count):
		if f.get_position() >= f.get_length():
			break
		f.get_32()
		f.get_8()
		f.get_8()
		f.get_8()
		f.get_8()
		var name_len := int(f.get_16())
		var name2 := f.get_buffer(name_len).get_string_from_utf8()
		var msg_len := int(f.get_16())
		var message := f.get_buffer(msg_len).get_string_from_utf8()
		chats.append("%s: %s" % [name2, message])
	return chats

func _format_chat_lines(chats: Array[String]) -> String:
	if chats.is_empty():
		return "チャット: なし"
	var lines: Array[String] = []
	lines.append("チャット:")
	var max_preview := mini(chats.size(), 4)
	for i in range(max_preview):
		lines.append("  • %s" % chats[i])
	if chats.size() > max_preview:
		lines.append("  …ほか%d件" % (chats.size() - max_preview))
	return "\n".join(lines)

func _read_string(f: FileAccess, length: int) -> String:
	var bytes := f.get_buffer(length)
	var end := bytes.size()
	for i in range(bytes.size()):
		if bytes[i] == 0:
			end = i
			break
	return bytes.slice(0, end).get_string_from_utf8()
