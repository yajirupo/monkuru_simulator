# PlayerRenderer.gd
# Player の描画処理（スプライト・エフェクト・名前ラベル）を担当
# Player._ready() で生成し、_process() 毎フレーム update() を呼ぶ
# res://scenes/Player/PlayerRenderer.gd に配置

class_name PlayerRenderer
extends RefCounted

# ============================================================
# エフェクトスプライト定数
# ============================================================
const _ITEM_EFFECT_PATHS := {
	Enums.ItemType.SHOES:     "res://assets/images/others/crShoesEffect.png",
	Enums.ItemType.BROTHER:   "res://assets/images/others/crBrotherEffect.png",
	Enums.ItemType.ROCKET:    "res://assets/images/others/crRocketEffect.png",
	Enums.ItemType.INVISIBLE: "res://assets/images/others/crInvisibleEffect.png",
}
const _ITEM_EFFECT_SHEET_COLS := {
	Enums.ItemType.SHOES:     8,
	Enums.ItemType.BROTHER:   5,
	Enums.ItemType.ROCKET:    6,
	Enums.ItemType.INVISIBLE: 8,
}
const _ITEM_EFFECT_FRAMES_PER_CELL: int = 4

# ============================================================
# 内部状態
# ============================================================
var _player_num:    int
var _sprite:        Sprite2D
var _name_label:    Label
var _effect_sprite: Sprite2D

var _tex_cache:         Dictionary = {}
var _effect_tex_cache:  Dictionary = {}
var _prev_item_use:     int = Enums.ItemType.NO_ITEM
var _effect_elapsed_frames: int = 0
var _effect_item_playing:   int = Enums.ItemType.NO_ITEM


# ============================================================
# セットアップ
# ============================================================

func setup(player_num: int, sprite: Sprite2D, name_label: Label, effect_sprite: Sprite2D) -> void:
	_player_num    = player_num
	_sprite        = sprite
	_name_label    = name_label
	_effect_sprite = effect_sprite

## ゲーム開始時にエフェクト状態をリセットする（ini_player() から呼ぶ）
func reset() -> void:
	_prev_item_use         = Enums.ItemType.NO_ITEM
	_effect_elapsed_frames = 0
	_effect_item_playing   = Enums.ItemType.NO_ITEM
	if _effect_sprite:
		_effect_sprite.visible = false
		_effect_sprite.texture = null


# ============================================================
# 毎フレーム描画更新（_process から呼ぶ）
# playerDisp() の移植
# ============================================================
func update() -> void:
	var p: Dictionary = GameState.player[_player_num]
	var using_invisible: bool = p["cr_item_use"] == Enums.ItemType.INVISIBLE

	_update_item_effect_sprite(p)

	# 透明マント処理
	if GameState.joutai_flag == Enums.JoutaiType.ONLINE_GAME:
		var is_remote: bool = (_player_num != NetworkManager.my_player_index())
		if using_invisible and is_remote:
			if _sprite:     _sprite.modulate.a  = 0.0
			if _name_label: _name_label.visible = false
		else:
			if _sprite:     _sprite.modulate.a  = 0.5 if using_invisible else 1.0
			if _name_label: _name_label.visible = true
	else:
		if _sprite:
			var is_vs_com_com: bool = (
				GameState.joutai_flag == Enums.JoutaiType.VS_COM_GAME and _player_num == 1
			)
			if using_invisible and is_vs_com_com:
				_sprite.modulate.a = 0.0
				if _name_label: _name_label.visible = false
			else:
				_sprite.modulate.a = 0.5 if using_invisible else 1.0
				if _name_label: _name_label.visible = true
	if _effect_sprite:
		_effect_sprite.modulate.a = 1.0

	# スプライトフレーム決定
	var jc:  int = p["joutai_count"]
	var rpt: int = Constants.REFRESH_PICTURE_TIME
	var tex: ImageTexture = null

	match p["joutai"]:
		Enums.PlayerJoutaiType.STAND_RIGHT, \
		Enums.PlayerJoutaiType.STAND_LEFT,  \
		Enums.PlayerJoutaiType.STAND_DOWN,  \
		Enums.PlayerJoutaiType.STAND_UP:
			var sheet := "stand_d"
			match p["joutai"]:
				Enums.PlayerJoutaiType.STAND_RIGHT: sheet = "stand_r"
				Enums.PlayerJoutaiType.STAND_LEFT:  sheet = "stand_l"
				Enums.PlayerJoutaiType.STAND_UP:    sheet = "stand_u"
				_:                                  sheet = "stand_d"
			@warning_ignore("integer_division")
			tex = _get_frame_tex(p, sheet, int(int(jc % (8 * rpt)) / rpt))
		Enums.PlayerJoutaiType.RUN_RIGHT:
			@warning_ignore("integer_division")
			tex = _get_frame_tex(p, "run_r", int(int(jc % (6 * rpt)) / rpt))
		Enums.PlayerJoutaiType.RUN_LEFT:
			@warning_ignore("integer_division")
			tex = _get_frame_tex(p, "run_l", int(int(jc % (6 * rpt)) / rpt))
		Enums.PlayerJoutaiType.RUN_DOWN:
			@warning_ignore("integer_division")
			tex = _get_frame_tex(p, "run_d", int(int(jc % (6 * rpt)) / rpt))
		Enums.PlayerJoutaiType.RUN_UP:
			@warning_ignore("integer_division")
			tex = _get_frame_tex(p, "run_u", int(int(jc % (6 * rpt)) / rpt))
		Enums.PlayerJoutaiType.DEATH:
			var death_info: Dictionary = Constants.get_character_sprite_info(p.get("character", 0), "death")
			var death_cols: int = int(death_info.get("cols", 1))
			@warning_ignore("integer_division")
			var death_frame: int = mini(int(jc / rpt), maxi(death_cols - 1, 0))
			tex = _get_frame_tex(p, "death", death_frame)

	if _sprite and tex:
		_sprite.texture = tex

	# 名前ラベル
	if _name_label:
		_name_label.text = p["name"]
		_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		_name_label.position = Vector2(-32, 34)
		_name_label.size     = Vector2(96, 16)
		_name_label.add_theme_color_override("font_color",        Color(0.0, 0.5, 0.0))
		_name_label.add_theme_color_override("font_shadow_color", Color.WHITE)
		_name_label.add_theme_constant_override("shadow_outline_size", 3)
		_name_label.add_theme_font_size_override("font_size", 12)


# ============================================================
# エフェクトスプライト更新
# ============================================================

func _update_item_effect_sprite(p: Dictionary) -> void:
	if _effect_sprite == null:
		return
	var item_use: int = int(p.get("cr_item_use", Enums.ItemType.NO_ITEM))

	# アイテム状態の変化を検知してエフェクト再生を開始
	if item_use != _prev_item_use:
		if _ITEM_EFFECT_PATHS.has(item_use):
			_effect_item_playing   = item_use
			_effect_elapsed_frames = 0
		elif _prev_item_use == Enums.ItemType.INVISIBLE and item_use == Enums.ItemType.NO_ITEM:
			# 透明マント効果切れ時も使用時と同じエフェクトを再生
			_effect_item_playing   = Enums.ItemType.INVISIBLE
			_effect_elapsed_frames = 0

	_prev_item_use = item_use

	if _effect_item_playing == Enums.ItemType.NO_ITEM:
		_effect_sprite.visible = false
		_effect_sprite.texture = null
		return

	var sheet_cols:   int = int(_ITEM_EFFECT_SHEET_COLS.get(_effect_item_playing, 1))
	var total_frames: int = sheet_cols * _ITEM_EFFECT_FRAMES_PER_CELL

	if _ITEM_EFFECT_PATHS.has(_effect_item_playing) and _effect_elapsed_frames < total_frames:
		@warning_ignore("integer_division")
		var cell_frame: int = int(_effect_elapsed_frames / _ITEM_EFFECT_FRAMES_PER_CELL)
		var tex := _get_effect_frame_tex(_ITEM_EFFECT_PATHS[_effect_item_playing], cell_frame, sheet_cols)
		if tex != null:
			_effect_sprite.texture = tex
			_effect_sprite.visible = true
		else:
			_effect_sprite.visible = false
			_effect_sprite.texture = null
		_effect_elapsed_frames += 1
	else:
		# アニメーション終了
		_effect_sprite.visible = false
		_effect_sprite.texture = null
		_effect_item_playing   = Enums.ItemType.NO_ITEM


# ============================================================
# テクスチャキャッシュ
# ============================================================

func _get_frame_tex(p: Dictionary, sheet_key: String, frame: int) -> ImageTexture:
	var ch: int = p.get("character", 0)
	var cache_key := str(ch) + "_" + sheet_key + str(frame)
	if _tex_cache.has(cache_key):
		return _tex_cache[cache_key]

	var info: Dictionary = Constants.get_character_sprite_info(ch, sheet_key)
	if info.is_empty():
		return null

	var file_path := "res://assets/images/character/character%d%s.png" % [ch, info["suffix"]]
	if ImageManager.get_image(file_path) == null:
		file_path = "res://assets/images/character/character0%s.png" % info["suffix"]
		if ImageManager.get_image(file_path) == null:
			return null

	var cols: int = int(info.get("cols", 1))
	var rows: int = int(info.get("rows", 1))
	var base_tex: Texture2D = ImageManager.get_image(file_path)
	if base_tex == null:
		return null

	@warning_ignore("integer_division")
	var fw: int = maxi(base_tex.get_width()  / maxi(cols, 1), 1)
	@warning_ignore("integer_division")
	var fh: int = maxi(base_tex.get_height() / maxi(rows, 1), 1)
	var col: int = frame % cols
	var t := ImageManager.get_transparent_image(file_path, col, 0, fw, fh)
	_tex_cache[cache_key] = t
	return t

func _get_effect_frame_tex(path: String, frame: int, cols: int) -> ImageTexture:
	var cache_key := "%s_%d_%d" % [path, frame, cols]
	if _effect_tex_cache.has(cache_key):
		return _effect_tex_cache[cache_key]

	var base_tex: Texture2D = ImageManager.get_image(path)
	if base_tex == null:
		return null

	@warning_ignore("integer_division")
	var fw: int = maxi(base_tex.get_width() / maxi(cols, 1), 1)
	var fh: int = base_tex.get_height()
	var safe_frame: int = clampi(frame, 0, maxi(cols - 1, 0))
	var tex: ImageTexture = ImageManager.get_transparent_image(path, safe_frame, 0, fw, fh)
	_effect_tex_cache[cache_key] = tex
	return tex

func _make_trans_from_region(base: Texture2D, col: int, row: int, w: int, h: int) -> ImageTexture:
	var img := base.get_image()
	if img == null:
		return null
	var sub := img.get_region(Rect2i(col * w, row * h, w, h))
	sub.convert(Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(sub)
