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
var _appear_sprite: Sprite2D
var _effect_sprite: Sprite2D
var _shadow_sprite: Sprite2D
var _pin_sprite: Sprite2D
var _pin_elapsed_frames: int = 0
const PIN_FRAMES: int = 12

var _tex_cache:         Dictionary = {}
var _effect_tex_cache:  Dictionary = {}
var _prev_item_use:     int = Enums.ItemType.NO_ITEM
var _effect_elapsed_frames: int = 0
var _effect_item_playing:   int = Enums.ItemType.NO_ITEM

# appear アニメーション中の固定座標（開始時に一度だけ記録）
var _appear_pos_locked:       bool    = false
var _appear_locked_global_pos: Vector2 = Vector2.ZERO


# ============================================================
# セットアップ
# ============================================================

func setup(player_num: int, sprite: Sprite2D, appear_sprite: Sprite2D, name_label: Label, effect_sprite: Sprite2D, shadow_sprite: Sprite2D, pin_sprite: Sprite2D) -> void:
	_player_num    = player_num
	_sprite        = sprite
	_appear_sprite = appear_sprite
	_name_label    = name_label
	_effect_sprite = effect_sprite
	_shadow_sprite = shadow_sprite
	_pin_sprite    = pin_sprite
	_apply_layer_order()

func _apply_layer_order() -> void:
	if _shadow_sprite:
		_shadow_sprite.z_index = 0
	if _sprite:
		_sprite.z_index = 1
	if _appear_sprite:
		_appear_sprite.z_index = 1
	if _effect_sprite:
		_effect_sprite.z_index = 3
	if _pin_sprite:
		_pin_sprite.z_index = 4
	if _name_label:
		_name_label.z_index = 4000

## ゲーム開始時にエフェクト状態をリセットする（ini_player() から呼ぶ）
func reset() -> void:
	_prev_item_use         = Enums.ItemType.NO_ITEM
	_effect_elapsed_frames = 0
	_effect_item_playing   = Enums.ItemType.NO_ITEM
	_pin_elapsed_frames    = 0
	_appear_pos_locked     = false
	if _effect_sprite:
		_effect_sprite.visible = false
		_effect_sprite.texture = null
	if _appear_sprite:
		_appear_sprite.visible = false
		_appear_sprite.texture = null
	if _shadow_sprite:
		_shadow_sprite.visible = false
	if _pin_sprite:
		_pin_sprite.visible = false

# ============================================================
# 毎フレーム描画更新（_process から呼ぶ）
# playerDisp() の移植
# ============================================================
func update() -> void:
	var p: Dictionary = GameState.player[_player_num]
	var is_vs_com_mode: bool = GameState.joutai_flag in [Enums.JoutaiType.VS_COM_GAME, Enums.JoutaiType.VS_COM_REPLAY]
	var death_cols: int = int(p.get("death_cols", 1))
	var death_end_frame: int = death_cols * Constants.REFRESH_PICTURE_TIME - 1
	var is_eliminated_in_vs_com: bool = (
		is_vs_com_mode
		and not p["life_flag"]
		and p["joutai"] == Enums.PlayerJoutaiType.DEATH
		and p["joutai_count"] >= death_end_frame
	)
	if is_eliminated_in_vs_com:
		if _sprite:
			_sprite.visible = false
		if _name_label:
			_name_label.visible = false
		if _appear_sprite:
			_appear_sprite.visible = false
		if _effect_sprite:
			_effect_sprite.visible = false
			_effect_sprite.texture = null
		if _shadow_sprite:
			_shadow_sprite.visible = false
		if _pin_sprite:
			_pin_sprite.visible = false
		return
	if _sprite:
		_sprite.visible = true
		
	var using_invisible: bool = p["cr_item_use"] == Enums.ItemType.INVISIBLE	
	# 勝敗表示中は透明マント効果を無効化（キャラを通常表示）
	if p["joutai"] in [Enums.PlayerJoutaiType.WIN, Enums.PlayerJoutaiType.LOSE]:
		using_invisible = false
	
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
				GameState.joutai_flag == Enums.JoutaiType.VS_COM_GAME and _player_num >= 1
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
	var use_appear_sprite: bool = false

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
			var stand_cols_map: Dictionary = p.get("stand_cols", {})
			var stand_cols: int = int(stand_cols_map.get(sheet, 1))
			@warning_ignore("integer_division")
			tex = _get_frame_tex(p, sheet, int(int(jc % (stand_cols * rpt)) / rpt))
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
			@warning_ignore("integer_division")
			var death_frame: int = mini(int(jc / rpt), maxi(death_cols - 1, 0))
			tex = _get_frame_tex(p, "death", death_frame)
		Enums.PlayerJoutaiType.APPEAR:
			use_appear_sprite = true
			var ch: int = int(p.get("character", 0))
			var appear_info := Constants.get_character_sprite_info(ch, "appear")
			var appear_cols: int = int(appear_info.get("cols", 23))
			@warning_ignore("integer_division")
			#tex = _get_appear_frame_tex(ch, appear_frame, appear_cols)
			tex = _get_frame_tex(p, "appear", int(int(jc % (appear_cols * rpt)) / rpt))
		Enums.PlayerJoutaiType.WIN:
			var ch_w: int = int(p.get("character", 0))
			var win_info := Constants.get_character_sprite_info(ch_w, "win")
			var win_cols: int = int(win_info.get("cols", 17))
			@warning_ignore("integer_division")
			tex = _get_frame_tex(p, "win", int(int(jc % (win_cols * rpt)) / rpt))
		Enums.PlayerJoutaiType.LOSE:
			var ch_l: int = int(p.get("character", 0))
			var lose_info := Constants.get_character_sprite_info(ch_l, "lose")
			var lose_cols: int = int(lose_info.get("cols", 29))
			@warning_ignore("integer_division")
			tex = _get_frame_tex(p, "lose", int(int(jc % (lose_cols * rpt)) / rpt))

	if _sprite and tex:
		_sprite.texture = tex
	
	if _sprite and _appear_sprite:
		if use_appear_sprite:
			_sprite.visible = false
			_appear_sprite.visible = true
			# APPEAR開始時に一度だけグローバル座標を記録し、以降はその位置に固定する
			if not _appear_pos_locked:
				_appear_locked_global_pos = _sprite.global_position + Vector2(4, 0)
				_appear_pos_locked = true
			_appear_sprite.global_position = _appear_locked_global_pos
			if tex:
				_appear_sprite.texture = tex
		else:
			_appear_sprite.visible = false
			_appear_pos_locked = false
			_sprite.visible = true
			if tex:
				_sprite.texture = tex
				
	# ── 影 ──
	# use_appear_sprite 確定後に、実際に描画しているスプライトに追従する
	var active_sprite: Sprite2D = _appear_sprite if use_appear_sprite else _sprite
	var show_player_graphic: bool = active_sprite != null and active_sprite.visible
	if _shadow_sprite:
		_shadow_sprite.visible = show_player_graphic
		if _shadow_sprite.visible:
			_shadow_sprite.texture = ImageManager.get_image("res://assets/images/others/shadow.png")
			# 半透明状態をプレイヤー画像に同期
			_shadow_sprite.modulate.a = active_sprite.modulate.a

	# ── ピン（VS COM / VS COM REPLAY の人間プレイヤーのみ） ──
	if _pin_sprite:
		var is_vs_com := GameState.joutai_flag in [Enums.JoutaiType.VS_COM_GAME, Enums.JoutaiType.VS_COM_REPLAY]
		# プレイヤーグラフィックが表示されているときだけピンも表示
		var show_pin := is_vs_com and _player_num == 0 and show_player_graphic
		if show_pin:
			@warning_ignore("integer_division")
			var frame_idx := (_pin_elapsed_frames / Constants.REFRESH_PICTURE_TIME) % PIN_FRAMES
			var pin_tex := _get_pin_frame_tex(frame_idx)
			if pin_tex:
				_pin_sprite.texture = pin_tex
				_pin_sprite.visible = true
			_pin_elapsed_frames += 1
		else:
			_pin_sprite.visible = false
			_pin_elapsed_frames = 0

	# 名前ラベル
	if _name_label:
		_name_label.text = p["name"]
		_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		_name_label.position = Vector2(-32, 32)
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
			# 勝敗表示時のマント解除エフェクトは不要
			if not p.get("joutai", 0) in [Enums.PlayerJoutaiType.WIN, Enums.PlayerJoutaiType.LOSE]:
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

func _get_pin_frame_tex(frame: int) -> ImageTexture:
	const PIN_PATH := "res://assets/images/others/my_pin.png"
	var cache_key := "pin_%d" % frame
	if _tex_cache.has(cache_key):
		return _tex_cache[cache_key]
	var base_tex: Texture2D = ImageManager.get_image(PIN_PATH)
	if base_tex == null:
		return null
	@warning_ignore("integer_division")
	var fw: int = maxi(base_tex.get_width() / PIN_FRAMES, 1)
	var fh: int = base_tex.get_height()
	var tex: ImageTexture = ImageManager.get_transparent_image(PIN_PATH, frame, 0, fw, fh)
	_tex_cache[cache_key] = tex
	return tex
