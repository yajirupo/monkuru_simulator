# KuruSelectOverlay.gd
class_name KuruSelectOverlay
extends Window

var _grid: GridContainer
var _selected_callback: Callable
var _thumbnail_textures: Array[Texture2D] = []
var _kuru_frame_widths: Array[float] = []   # 各くるの元フレーム幅

func _ready() -> void:
	title = "くる選択"
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
	margin.add_theme_constant_override("margin_top",    4)
	margin.add_theme_constant_override("margin_bottom", 4)
	margin.add_theme_constant_override("margin_left",   6)
	margin.add_theme_constant_override("margin_right",  6)
	add_child(margin)

	_grid = GridContainer.new()
	_grid.columns = 6
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 2)
	margin.add_child(_grid)

	_load_thumbnails()
	var count := Constants.get_kuru_count()
	var cell_size := Vector2(93, 100)

	for i in range(count):
		var btn := Button.new()
		btn.custom_minimum_size = cell_size
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_kuru_button_pressed.bind(i))

		var vbox := VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
		vbox.add_theme_constant_override("separation", 0)
		vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		# ── くる画像（draw_offset_x を反映） ──
		var tex_rect := TextureRect.new()
		tex_rect.expand_mode    = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex_rect.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.custom_minimum_size = Vector2(56, 56)
		tex_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if i < _thumbnail_textures.size() and _thumbnail_textures[i]:
			tex_rect.texture = _thumbnail_textures[i]

		# draw_offset_x に応じた左余白
		var frame_w: float = _kuru_frame_widths[i] if i < _kuru_frame_widths.size() else 1.0
		var kdef := Constants.get_kuru_def(i)
		var draw_offset: float = float(kdef.get("draw_offset_x", 0.0))
		var offset_px := int(28 - draw_offset * (56.0 / maxi(frame_w, 1.0)))

		var image_wrapper := MarginContainer.new()
		image_wrapper.add_theme_constant_override("margin_left", offset_px)
		image_wrapper.add_child(tex_rect)
		vbox.add_child(image_wrapper)

		# ── くる名 ──
		var name_label := Label.new()
		name_label.text = Constants.get_kuru_name(i)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.clip_text     = true
		name_label.size_flags_horizontal = Control.SIZE_FILL
		name_label.custom_minimum_size.x = cell_size.x - 4
		name_label.add_theme_font_size_override("font_size", 10)
		vbox.add_child(name_label)

		# ── 能力＋補正 ──
		var speed: int    = int(kdef.get("speed", 0))
		var dankai: int   = int(kdef.get("dankai", 0))
		var kankaku: int  = int(kdef.get("kankaku", 0))
		var speed_up: int = int(kdef.get("speed_up", 0))
		var power_up: int = int(kdef.get("power_up", 0))
		var shot_up: int  = int(kdef.get("shot_up", 0))

		var perf_text := "速度:%d 段階:%d 間隔:%.1fs" % [speed, dankai, kankaku / 60.0]
		var bonus_text := _build_kuru_bonus_text(speed_up, power_up, shot_up)
		var stats_text := perf_text
		if bonus_text != "":
			stats_text += "\n" + bonus_text

		var stats_label := Label.new()
		stats_label.text = stats_text
		stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stats_label.add_theme_font_size_override("font_size", 8)
		stats_label.autowrap_mode        = TextServer.AUTOWRAP_OFF
		stats_label.size_flags_horizontal = Control.SIZE_FILL
		vbox.add_child(stats_label)

		btn.add_child(vbox)
		_grid.add_child(btn)

	reset_size()

func _build_kuru_bonus_text(speed_up: int, power_up: int, shot_up: int) -> String:
	var stats := [
		{"name": "速度",   "val": speed_up},
		{"name": "パワー", "val": power_up},
		{"name": "くる数", "val": shot_up},
	]
	var by_val: Dictionary = {}
	for s in stats:
		if s["val"] == 0:
			continue
		var key = s["val"]
		if not by_val.has(key):
			by_val[key] = []
		by_val[key].append(s["name"])

	if by_val.is_empty():
		return ""

	# 全能力同じ値かつ3つ揃っていればまとめる
	if by_val.size() == 1:
		var val = by_val.keys()[0]
		var names = by_val[val] as Array
		if names.size() == 3:
			return "全能力 %+d" % val

	var parts: Array[String] = []
	for val in by_val:
		var names = by_val[val] as Array
		parts.append("/".join(names) + " %+d" % val)
	return " ".join(parts)

func _load_thumbnails() -> void:
	_thumbnail_textures.clear()
	_kuru_frame_widths.clear()
	var count := Constants.get_kuru_count()
	for i in range(count):
		var kdef := Constants.get_kuru_def(i)
		var path: String = kdef.get("sheet_path", "")
		if path.is_empty() or not ResourceLoader.exists(path):
			_thumbnail_textures.append(null)
			_kuru_frame_widths.append(1.0)
			continue
		var sheet_tex := ImageManager.get_image(path)
		if sheet_tex == null:
			_thumbnail_textures.append(null)
			_kuru_frame_widths.append(1.0)
			continue
		@warning_ignore("integer_division")
		var frame_w := maxi(sheet_tex.get_width()  / Constants.KURU_SHEET_COLS, 1)
		@warning_ignore("integer_division")
		var frame_h := maxi(sheet_tex.get_height() / Constants.KURU_SHEET_ROWS, 1)
		var thumb := ImageManager.get_transparent_image(path, 0, 0, frame_w, frame_h)
		_thumbnail_textures.append(thumb)
		_kuru_frame_widths.append(float(frame_w))

func show_overlay(callback: Callable) -> void:
	_selected_callback = callback
	reset_size()
	popup_centered()

func _on_kuru_button_pressed(index: int) -> void:
	if _selected_callback.is_valid():
		_selected_callback.call(index)
	hide()

func _on_close_requested() -> void:
	_selected_callback = Callable()
	hide()
