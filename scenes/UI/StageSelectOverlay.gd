# StageSelectOverlay.gd
class_name StageSelectOverlay
extends Window

var _grid: GridContainer
var _selected_callback: Callable
var _composite_textures: Array[Texture2D] = []

func _ready() -> void:
	title = "ステージ選択"
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
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	margin.add_child(_grid)

	_load_composite_textures()
	var count := GameState.STAGE_COUNT
	var cell_size := Vector2(120, 130)

	for i in range(count):
		var btn := Button.new()
		btn.custom_minimum_size = cell_size
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_stage_button_pressed.bind(i))

		var vbox := VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_theme_constant_override("separation", 4)
		vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		var tex_rect := TextureRect.new()
		tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.custom_minimum_size = Vector2(100, 100)
		tex_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if i < _composite_textures.size() and _composite_textures[i]:
			tex_rect.texture = _composite_textures[i]
		vbox.add_child(tex_rect)

		var name_label := Label.new()
		name_label.text = GameState.get_stage_name(i)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.clip_text = true
		name_label.size_flags_horizontal = Control.SIZE_FILL
		vbox.add_child(name_label)

		btn.add_child(vbox)
		_grid.add_child(btn)

	reset_size()

func _load_composite_textures() -> void:
	var count := GameState.STAGE_COUNT

	for stage in range(count):
		var bg_path := "res://assets/images/backGround/backGround%d.png" % stage
		var bg_tex: Texture2D = null
		if ResourceLoader.exists(bg_path):
			bg_tex = ImageManager.get_image(bg_path)

		var hb_path := "res://assets/images/others/hardblock%d.png" % stage
		var hb_tex: Texture2D = null
		if ResourceLoader.exists(hb_path):
			hb_tex = ImageManager.get_image(hb_path)

		if bg_tex == null:
			_composite_textures.append(null)
			continue

		var bg_img := bg_tex.get_image()
		if bg_img == null:
			_composite_textures.append(null)
			continue

		var src_w := bg_img.get_width()
		var src_h := bg_img.get_height()

		# 背景の中央 100x100 を切り抜き
		const CROP_SIZE := 100
		var crop_w := mini(CROP_SIZE, src_w)
		var crop_h := mini(CROP_SIZE, src_h)
		@warning_ignore("integer_division")
		var x := (src_w - crop_w) / 2
		@warning_ignore("integer_division")
		var y := (src_h - crop_h) / 2

		var composite := bg_img.get_region(Rect2i(x, y, crop_w, crop_h))
		composite.convert(Image.FORMAT_RGBA8)

		# ハードブロックを元のサイズのまま、中央にアルファブレンド
		if hb_tex != null:
			var hb_img := hb_tex.get_image()
			if hb_img != null:
				hb_img.convert(Image.FORMAT_RGBA8)
				var hb_w := hb_img.get_width()
				var hb_h := hb_img.get_height()

				# はみ出しを防ぐため、必要ならクリップ（ただし通常は小さいのでそのまま）
				@warning_ignore("integer_division")
				var paste_x := (crop_w - hb_w) / 2
				@warning_ignore("integer_division")
				var paste_y := (crop_h - hb_h) / 2

				# blend_rect でアルファ合成（アルファを考慮したブレンド）
				composite.blend_rect(hb_img,
					Rect2i(0, 0, hb_w, hb_h),
					Vector2i(paste_x, paste_y))

		var composite_tex := ImageTexture.create_from_image(composite)
		_composite_textures.append(composite_tex)

func show_overlay(callback: Callable) -> void:
	_selected_callback = callback
	reset_size()
	popup_centered()

func _on_stage_button_pressed(index: int) -> void:
	if _selected_callback.is_valid():
		_selected_callback.call(index)
	hide()

func _on_close_requested() -> void:
	_selected_callback = Callable()
	hide()
