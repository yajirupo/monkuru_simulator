# ItemSelectOverlay.gd
class_name ItemSelectOverlay
extends Window

const ITEM_NAMES := ["無し", "くるロケット", "透明マント", "スピード靴", "くる兄弟"]
const ITEM_DESCRIPTIONS := [
	"なし",
	"発射したくるの移動スピードがアップします",
	"キャラクターが透明になり他の人から見えなくなります",
	"キャラクターが猛ダッシュします",
	"キャラクターの両サイドからくるが発射されます"
]

var _grid: GridContainer
var _selected_callback: Callable
var _item_textures: Array[Texture2D] = []

func _ready() -> void:
	title = "アイテム選択"
	popup_window = true
	unresizable = true
	close_requested.connect(_on_close_requested)
	wrap_controls = true
	_build_grid()
	hide()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and visible:
		_on_close_requested()

func _build_grid() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top",    8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.add_theme_constant_override("margin_left",   8)
	margin.add_theme_constant_override("margin_right",  8)
	add_child(margin)

	_grid = GridContainer.new()
	_grid.columns = 5   # 1行5列に変更
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	margin.add_child(_grid)

	_load_item_textures()
	var count := ITEM_NAMES.size()
	var cell_size := Vector2(110, 130)

	for i in range(count):
		var btn := Button.new()
		btn.custom_minimum_size = cell_size
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_item_button_pressed.bind(i))

		var vbox := VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_theme_constant_override("separation", 2)
		vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		# アイテム画像（NO_ITEM 以外は crItem.png から切り出し）
		var tex_rect := TextureRect.new()
		tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.custom_minimum_size = Vector2(64, 64)
		tex_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if i > 0 and _item_textures.size() > i - 1 and _item_textures[i - 1]:
			tex_rect.texture = _item_textures[i - 1]
		vbox.add_child(tex_rect)

		# アイテム名
		var name_label := Label.new()
		name_label.text = ITEM_NAMES[i]
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.clip_text = true
		name_label.size_flags_horizontal = Control.SIZE_FILL
		vbox.add_child(name_label)

		# 説明文
		var desc_label := Label.new()
		desc_label.text = ITEM_DESCRIPTIONS[i]
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.add_theme_font_size_override("font_size", 10)
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.size_flags_horizontal = Control.SIZE_FILL
		vbox.add_child(desc_label)

		btn.add_child(vbox)
		_grid.add_child(btn)

	reset_size()

func _load_item_textures() -> void:
	var path := "res://assets/images/others/crItem.png"
	if not ResourceLoader.exists(path):
		return
	# crItem.png は 4列 (ROCKET, INVISIBLE, SHOES, BROTHER) 32x32
	for col in range(4):
		var tex := ImageManager.get_transparent_image(path, col, 0, 32, 32)
		_item_textures.append(tex)

func show_overlay(callback: Callable) -> void:
	_selected_callback = callback
	reset_size()
	popup_centered()

func _on_item_button_pressed(index: int) -> void:
	if _selected_callback.is_valid():
		_selected_callback.call(index)
	hide()

func _on_close_requested() -> void:
	_selected_callback = Callable()
	hide()
