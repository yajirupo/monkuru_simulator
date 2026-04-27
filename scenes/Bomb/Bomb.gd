# Bomb.gd
# bomb.cpp の移植
# ノード: Area2D（BombContainer の子として動的に生成）
# Bomb.tscn を Kuru.gd の kuru_bomb() から instantiate する

extends Node2D

# bomb_t 構造体の移植
var data: Dictionary = {
	"masu_x": 0,
	"masu_y": 0,
	"power":  1,
	"count":  0,
}

# スプライト参照

# ============================================================
# iniBomb(pBomb, pKuru) の移植
# ============================================================
func init_bomb(kuru_data: Dictionary) -> void:
	data["masu_x"] = kuru_data["bomb_x"]
	data["masu_y"] = kuru_data["bomb_y"]
	data["power"]  = kuru_data["power"]
	data["count"]  = -Constants.BOMB_SPREAD_TIME * 2
	_sync_position()


# ============================================================
# bombCalc() 相当：毎フレーム呼ぶ
# ============================================================
func bomb_calc() -> bool:
	var limit: int = (data["power"] + 1) * Constants.BOMB_SPREAD_TIME * 2
	if data["count"] >= limit:
		return false  # 削除すべき

	# 爆発音（中心・火力分それぞれ）
	_check_play_sound()

	data["count"] += 1
	_update_visuals()
	return true


# ============================================================
# スプライトシート情報（init.cpp の LoadDivGraph に対応）
# bomb1.png  : 単体画像
# bomb2.png  : 9フレーム横1列 70x78px
# ============================================================
var _bomb1_tex: ImageTexture = null
var _bomb2_frames: Array[ImageTexture] = []

func _make_black_transparent(img: Image) -> void:
	img.convert(Image.FORMAT_RGBA8)

func _load_textures() -> void:
	if _bomb1_tex != null:
		return
	_bomb1_tex = ImageManager.get_transparent_image("res://assets/images/others/bomb1.png", 0, 0, 32, 32)
	for i in range(9):
		var frame := ImageManager.get_transparent_image("res://assets/images/others/bomb2.png", i, 0, 70, 78)
		if frame:
			_bomb2_frames.append(frame)

func _get_center_sprite() -> Sprite2D:
	var sp: Sprite2D = get_node_or_null("CenterSprite")
	if sp == null:
		sp = Sprite2D.new()
		sp.name = "CenterSprite"
		add_child(sp)
	return sp

# ============================================================
# bombDisp() 相当：ビジュアル更新
# ============================================================
func _update_visuals() -> void:
	_load_textures()
	var cnt: int = data["count"]
	var sp := _get_center_sprite()

	if cnt < 0:
		# 爆発前：bomb1 を表示
		sp.visible = true
		sp.texture = _bomb1_tex
		# bomb1: 32x32 → 中心が原点のため +16 offset
		sp.position = Vector2(data["masu_x"] * 32 + 16, data["masu_y"] * 32 + 3 + 16)
	elif cnt < Constants.BOMB_STAY_TIME:
		# 爆発中：bomb2 のフレームを表示
		sp.visible = true
		@warning_ignore("integer_division")
		var f: int = mini(cnt / 2, 8)
		if f < _bomb2_frames.size():
			sp.texture = _bomb2_frames[f]
	else:
		sp.visible = false

	queue_redraw()


func _draw() -> void:
	_load_textures()
	var cnt: int = data["count"]
	var pw: int  = data["power"]
	var msx: int = data["masu_x"]
	var msy: int = data["masu_y"]
	var cell: int = Constants.MASU_SIZE

	if cnt < 0 or cnt >= (pw + 1) * Constants.BOMB_SPREAD_TIME * 2:
		return

	# 火力分の爆風を bomb1 画像で描画
	for i in range(1, pw + 1):
		if cnt < i * Constants.BOMB_SPREAD_TIME + Constants.BOMB_STAY_TIME:
			var use_bomb2: bool = (cnt >= i * Constants.BOMB_SPREAD_TIME and cnt < i * Constants.BOMB_SPREAD_TIME + Constants.BOMB_STAY_TIME)
			_draw_spread_cell(msx, msy, i, use_bomb2, cnt, cell, 1, 0)
			_draw_spread_cell(msx, msy, i, use_bomb2, cnt, cell, -1, 0)
			_draw_spread_cell(msx, msy, i, use_bomb2, cnt, cell, 0, 1)
			_draw_spread_cell(msx, msy, i, use_bomb2, cnt, cell, 0, -1)


func _check_play_sound() -> void:
	var cnt: int = data["count"]
	var pw: int  = data["power"]
	# 爆発タイミングのみ音を鳴らす（毎フレームではなく瞬間のみ）
	if cnt == 0:
		SoundManager.play_bomb()
		return
	for i in range(1, pw + 1):
		if cnt == i * Constants.BOMB_SPREAD_TIME and _has_any_spread_target(i):
			SoundManager.play_bomb()
			return

func _draw_spread_cell(msx: int, msy: int, i: int, use_bomb2: bool, cnt: int, cell: int, step_x: int, step_y: int) -> void:
	if _is_blast_blocked(msx, msy, step_x, step_y, i):
		return
	var nx: int = msx + step_x * i
	var ny: int = msy + step_y * i
	if nx < 0 or nx >= Constants.FIELD_COLS or ny < 0 or ny >= Constants.FIELD_ROWS:
		return
	var px: float = nx * cell
	var py: float = ny * cell + 3
	if use_bomb2 and _bomb2_frames.size() > 0:
		@warning_ignore("integer_division")
		var f: int = mini((cnt - i * Constants.BOMB_SPREAD_TIME) / 2, 8)
		if f < _bomb2_frames.size():
			draw_texture(_bomb2_frames[f], Vector2(px - 19, py - 46))
	elif _bomb1_tex:
		draw_texture(_bomb1_tex, Vector2(px, py), Color.WHITE)

func _has_any_spread_target(distance: int) -> bool:
	return (
		not _is_blast_blocked(data["masu_x"], data["masu_y"], 1, 0, distance) or
		not _is_blast_blocked(data["masu_x"], data["masu_y"], -1, 0, distance) or
		not _is_blast_blocked(data["masu_x"], data["masu_y"], 0, 1, distance) or
		not _is_blast_blocked(data["masu_x"], data["masu_y"], 0, -1, distance)
	)

func _is_blast_blocked(origin_x: int, origin_y: int, step_x: int, step_y: int, distance: int) -> bool:
	for step in range(1, distance + 1):
		var tx: int = origin_x + step_x * step
		var ty: int = origin_y + step_y * step
		if _is_hard_block_cell(tx, ty):
			return true
	return false

func _is_hard_block_cell(cell_x: int, cell_y: int) -> bool:
	if cell_x < 0 or cell_x >= Constants.FIELD_COLS:
		return false
	if cell_y < 0 or cell_y >= Constants.FIELD_ROWS:
		return false
	return GameState.masu[cell_y][cell_x]["kind"] == Enums.MasuKind.HARD_BLOCK


func _sync_position() -> void:
	# C++: DrawGraph(MAP_LEFT_SIDE/10 + masuX*32,  MAP_UP_SIDE/10 + masuY*32 + 3)
	# この Node2D 自体は原点に置き、_draw() と center_sprite で相対描画する
	position = Vector2(
		Constants.MAP_LEFT_SIDE * 0.1,
		Constants.MAP_UP_SIDE   * 0.1
	)
