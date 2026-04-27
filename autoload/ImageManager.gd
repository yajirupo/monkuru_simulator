extends Node

var _image_textures: Dictionary = {}      # canonical_path -> Texture2D
var _transparent_cache: Dictionary = {}   # "path_col_row_w_h" -> ImageTexture
var _images_loaded: bool = false

## 画像キャッシュの事前読み込み処理を開始する。
func load_all() -> void:
	_load_images()

## ゲームで使う主要画像と分割画像を一度だけキャッシュへ展開する。
func _load_images() -> void:
	if _images_loaded:
		return
	_images_loaded = true

	var base_paths: Array[String] = []
	for stage in range(4):
		base_paths.append("res://assets/images/backGround/backGround%d.png" % stage)
		base_paths.append("res://assets/images/backGround/backGround%dVS.png" % stage)
	for stage in range(4):
		base_paths.append("res://assets/images/others/hardblock%d.png" % stage)
	base_paths.append_array([
		"res://assets/images/others/crItem.png",
		"res://assets/images/others/status.png",
		"res://assets/images/others/bomb1.png",
		"res://assets/images/others/bomb2.png",
		"res://assets/images/others/kuru0.png",
		"res://assets/images/others/kuru1.png",
		"res://assets/images/others/kuru2.png",
		"res://assets/images/others/crRocketEffect.png",
		"res://assets/images/others/crInvisibleEffect.png",
		"res://assets/images/others/crShoesEffect.png",
		"res://assets/images/others/crBrotherEffect.png",
	])
	for path in base_paths:
		_cache_base_texture(path)

	for col in range(4):
		_cache_transparent_region("res://assets/images/others/crItem.png", col, 0, 32, 32)
	for idx in range(6):
		var col := idx % 3
		@warning_ignore("integer_division")
		var row := idx / 3
		_cache_transparent_region("res://assets/images/others/status.png", col, row, 7, 7)
	for i in range(9):
		_cache_transparent_region("res://assets/images/others/bomb2.png", i, 0, 70, 78)
	_cache_transparent_region("res://assets/images/others/bomb1.png", 0, 0, 32, 32)

	for kuru_type in range(Constants.get_kuru_count()):
		var kdef: Dictionary = Constants.get_kuru_def(kuru_type)
		var kuru_path := str(kdef.get("sheet_path", ""))
		if kuru_path == "":
			continue
		var kuru_tex: Texture2D = _cache_base_texture(kuru_path)
		if kuru_tex == null:
			continue
		@warning_ignore("integer_division")
		var kuru_frame_w: int = maxi(kuru_tex.get_width() / Constants.KURU_SHEET_COLS, 1)
		@warning_ignore("integer_division")
		var kuru_frame_h: int = maxi(kuru_tex.get_height() / Constants.KURU_SHEET_ROWS, 1)
		for frame in range(32):
			var col := frame % 8
			@warning_ignore("integer_division")
			var row := frame / 8
			_cache_transparent_region(kuru_path, col, row, kuru_frame_w, kuru_frame_h)

	for ch in range(Constants.get_character_count()):
		var cdef: Dictionary = Constants.get_character_def(ch)
		var sprites: Dictionary = cdef.get("sprites", {})
		for sheet_key in sprites.keys():
			var info: Dictionary = Constants.get_character_sprite_info(ch, sheet_key)
			if info.is_empty():
				continue
			var cols: int = int(info.get("cols", 1))
			var rows: int = int(info.get("rows", 1))
			var suffix: String = str(info.get("suffix", ""))
			var path := "res://assets/images/character/character%d%s.png" % [ch, suffix]
			if not ResourceLoader.exists(path):
				continue
			var char_tex: Texture2D = _cache_base_texture(path)
			if char_tex == null:
				continue
			@warning_ignore("integer_division")
			var frame_w: int = maxi(char_tex.get_width() / maxi(cols, 1), 1)
			@warning_ignore("integer_division")
			var frame_h: int = maxi(char_tex.get_height() / maxi(rows, 1), 1)
			for col in range(cols):
				for row in range(rows):
					_cache_transparent_region(path, col, row, frame_w, frame_h)

## 通常画像を取得する（未キャッシュ時は読み込んで保存する）。
func get_image(path: String) -> Texture2D:
	var canonical := _canonical_image_path(path)
	if _image_textures.has(canonical):
		return _image_textures[canonical]
	return _cache_base_texture(canonical)

## 透過済みの分割画像を取得する（未キャッシュ時は切り出して保存する）。
func get_transparent_image(path: String, col: int, row: int, w: int, h: int) -> ImageTexture:
	var canonical := _canonical_image_path(path)
	var key := _region_cache_key(canonical, col, row, w, h)
	if _transparent_cache.has(key):
		return _transparent_cache[key]
	return _cache_transparent_region(canonical, col, row, w, h)

## 指定シートを col×row で分割し、AtlasTexture 配列として返す。
static func make_atlas_textures(path: String, col: int, row: int, w: int, h: int) -> Array[AtlasTexture]:
	var result: Array[AtlasTexture] = []
	if not ResourceLoader.exists(path):
		return result
	var base := load(path) as Texture2D
	if base == null:
		return result
	for r in range(row):
		for c in range(col):
			var at := AtlasTexture.new()
			at.atlas = base
			at.region = Rect2(c * w, r * h, w, h)
			result.append(at)
	return result

## ベース画像をキャッシュし、同一パスの再ロードを防ぐ。
func _cache_base_texture(path: String) -> Texture2D:
	var canonical := _canonical_image_path(path)
	if _image_textures.has(canonical):
		return _image_textures[canonical]
	if not ResourceLoader.exists(canonical):
		return null
	var tex := load(canonical) as Texture2D
	_image_textures[canonical] = tex
	return tex

## 指定セル領域を切り出して ImageTexture 化し、キャッシュして返す。
func _cache_transparent_region(path: String, col: int, row: int, w: int, h: int) -> ImageTexture:
	var canonical := _canonical_image_path(path)
	var key := _region_cache_key(canonical, col, row, w, h)
	if _transparent_cache.has(key):
		return _transparent_cache[key]
	var base := _cache_base_texture(canonical)
	if base == null:
		return null
	var img := base.get_image()
	if img == null:
		return null
	var sub := img.get_region(Rect2i(col * w, row * h, w, h))
	sub.convert(Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(sub)
	_transparent_cache[key] = tex
	return tex

## 分割領域キャッシュ用の一意キーを生成する。
func _region_cache_key(path: String, col: int, row: int, w: int, h: int) -> String:
	return "%s_%d_%d_%d_%d" % [path, col, row, w, h]

## 旧形式/簡略形式の画像パスを assets/images 配下の実パスへ正規化する。
func _canonical_image_path(path: String) -> String:
	var base_dir := "res://assets/images/"
	if not path.begins_with(base_dir):
		return path

	var relative := path.trim_prefix(base_dir)
	if relative.contains("/"):
		return path

	if relative.begins_with("cm_kuru"):
		return "%skuru/%s" % [base_dir, relative]
	if relative.begins_with("character"):
		return "%scharacter/%s" % [base_dir, relative]
	if relative.begins_with("backGround") or relative.begins_with("background"):
		var bg_name := relative
		if bg_name.begins_with("background"):
			bg_name = "backGround" + bg_name.trim_prefix("background")
		return "%sbackGround/%s" % [base_dir, bg_name]
	return "%sothers/%s" % [base_dir, relative]
