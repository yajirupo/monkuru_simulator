# ChatInputManager.gd
# チャット入力UIの生成・管理・メッセージ表示処理
# res://scenes/Main/ChatInputManager.gd に配置

class_name ChatInputManager
extends RefCounted

# ============================================================
# 定数
# ============================================================
const CHAT_COLOR_PLAYER := Color(162.0/255.0, 162.0/255.0, 64.0/255.0)

# ============================================================
# 公開プロパティ
# ============================================================
var is_active: bool = false

# ============================================================
# 内部 UI ノード参照
# ============================================================
var _panel:     PanelContainer = null
var _line_edit: LineEdit       = null


# ============================================================
# セットアップ
# ============================================================

## チャット入力 UI を構築して parent の子として追加する
func build_ui(parent: Node) -> void:
	# CanvasLayer：ゲーム画面の上に常に重ねる
	var layer := CanvasLayer.new()
	layer.name  = "ChatInputLayer"
	layer.layer = 10
	parent.add_child(layer)

	# PanelContainer：背景パネル本体
	_panel      = PanelContainer.new()
	_panel.name = "ChatInputPanel"
	_panel.visible = false

	# 画面右下に配置
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.offset_right  = -16.0
	_panel.offset_bottom = -16.0
	_panel.offset_left   = -16.0 - 320.0
	_panel.offset_top    = -16.0 - 68.0

	# パネル背景スタイル（白基調）
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.98, 0.98, 0.98, 0.9)
	style.set_border_width_all(1)
	style.border_color = Color(0.8, 0.8, 0.8)
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6
	style.set_content_margin_all(8.0)
	_panel.add_theme_stylebox_override("panel", style)
	layer.add_child(_panel)

	# レイアウト
	var margin := MarginContainer.new()
	margin.name = "MarginContainer"
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	# ラベル
	var lbl := Label.new()
	lbl.text = "チャット入力 (Enter で送信)"
	lbl.add_theme_color_override("font_color", Color(0.2, 0.2, 0.2))
	lbl.add_theme_font_size_override("font_size", 12)
	vbox.add_child(lbl)

	# テキスト入力欄
	_line_edit                        = LineEdit.new()
	_line_edit.name                   = "ChatLineEdit"
	_line_edit.placeholder_text       = "メッセージを入力..."
	_line_edit.max_length             = GameState.CHAT_MAX_MESSAGE_LENGTH
	_line_edit.custom_minimum_size    = Vector2(300, 32)
	_line_edit.caret_blink            = true
	_line_edit.caret_blink_interval   = 0.5
	_line_edit.add_theme_color_override("font_color",             Color(0.1, 0.1, 0.1))
	_line_edit.add_theme_color_override("caret_color",            Color(0.1, 0.1, 0.1))
	_line_edit.add_theme_color_override("font_placeholder_color", Color(0.6, 0.6, 0.6))
	_line_edit.add_theme_constant_override("outline_size", 0)

	var le_style := StyleBoxFlat.new()
	le_style.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	le_style.set_border_width_all(1)
	le_style.border_color = Color(0.8, 0.8, 0.8)
	le_style.set_content_margin_all(4.0)
	_line_edit.add_theme_stylebox_override("normal", le_style)
	_line_edit.add_theme_stylebox_override("focus",  le_style)

	vbox.add_child(_line_edit)
	_line_edit.text_submitted.connect(_on_line_edit_submitted)


# ============================================================
# 入力ハンドリング
# ============================================================

# 追加：送信直後のチャット再オープン防止フラグ
var _submitted_frame: int = -1   # ← bool → フレーム番号に変更

## _unhandled_input から呼び出す。処理済みなら true を返す
func handle_unhandled_key(key_event: InputEventKey) -> bool:
	if key_event.keycode not in [KEY_ENTER, KEY_KP_ENTER]:
		return false

	if is_active:
		# LineEdit フォーカスが外れた場合のフォールバック
		if not _line_edit or not _line_edit.has_focus():
			_submit_message()
		return true

	# 同一フレーム内の再オープンのみブロック（次フレーム以降は通常通り開く）
	if Engine.get_process_frames() == _submitted_frame:
		return true   # イベントを消費するが open はしない
		
	if not _can_open():
		return false

	_open()
	return true


# ============================================================
# チャット開閉
# ============================================================

func _can_open() -> bool:
	return GameState.joutai_flag in [
		Enums.JoutaiType.SINGLE_GAME,
		Enums.JoutaiType.VS_COM_GAME,
		Enums.JoutaiType.ONLINE_GAME,
	]

func _open() -> void:
	is_active = true
	if _panel:
		_panel.visible = true
	if _line_edit:
		_line_edit.text = ""
		_line_edit.grab_focus()

func close() -> void:
	is_active = false
	if _panel:
		_panel.visible = false
	if _line_edit and _line_edit.has_focus():
		_line_edit.release_focus()


# ============================================================
# メッセージ送信・受信
# ============================================================

func _submit_message() -> void:
	var message := ""
	if _line_edit:
		message = GameState.sanitize_chat_text(_line_edit.text, GameState.CHAT_MAX_MESSAGE_LENGTH)
	if message != "":
		var my_idx := 0
		if GameState.joutai_flag == Enums.JoutaiType.ONLINE_GAME:
			my_idx = NetworkManager.my_player_index()
			NetworkManager.send_chat_message(my_idx, message)
		append_message(GameState.player[my_idx].get("name", "Player"), message)
	_submitted_frame = Engine.get_process_frames()  # ← フレーム番号を記録
	close()

## NetworkManager.remote_chat_received シグナルのコールバック
func on_remote_chat_received(player_idx: int, message: String) -> void:
	if GameState.joutai_flag != Enums.JoutaiType.ONLINE_GAME:
		return
	if player_idx < 0 or player_idx >= GameState.player.size():
		return
	var sender: String = GameState.player[player_idx].get("name", "Remote")
	append_message(sender, message, Color.BLACK)


# ============================================================
# チャット表示（GameState.chat_str / chat_color への書き込み）
# ============================================================

## メッセージを最大 280px で折り返して chat_str へ追加する
func append_message(player_name: String, message: String, color: Color = CHAT_COLOR_PLAYER) -> void:
	GameState.append_chat_message(player_name, message, color, true)

## max_w px 以内に収まる最長前方部分文字列を返す（二分探索）
func _fit_text(text: String, font: Font, font_size: int, max_w: float) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
		return text
	var lo := 0
	var hi := text.length()
	while lo < hi:
		@warning_ignore("integer_division")
		var mid := (lo + hi + 1) / 2
		var w   := font.get_string_size(text.substr(0, mid), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if w <= max_w:
			lo = mid
		else:
			hi = mid - 1
	return text.substr(0, lo)

## chat_str / chat_color へ 1 行プッシュ（超えた分は上にスクロール）
func _push_chat_line(text: String, color: Color) -> void:
	GameState._push_chat_line(text, color)


# ============================================================
# シグナルコールバック
# ============================================================

func _on_line_edit_submitted(_text: String) -> void:
	if is_active:
		_submit_message()
