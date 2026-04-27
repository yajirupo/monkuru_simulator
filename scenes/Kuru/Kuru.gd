# Kuru.gd
# kuru.cpp の移植
# ノード: Node2D（KuruContainer の子として動的生成）

extends Node2D

# kuru_t 構造体の移植
var data: Dictionary = {
	"bomb_x":   0,
	"bomb_y":   0,
	"masu_x":   0,
	"masu_y":   0,
	"x":        0,
	"y":        0,
	"speed":    0,
	"count":    0,
	"muki":     Enums.Muki.DOWN,
	"move_muki":Enums.Muki.DOWN,
	"power":    1,
	"player":   0,
	"kuru_type": 0,
}



# ============================================================
# iniKuru(pKuru, num) の移植
# Player.gd の _spawn_kuru() から呼ばれる
# ============================================================
func init_kuru(player_data: Dictionary, player_num: int, move_muki: int, is_brother: bool = false) -> void:
	var p := player_data
	match p["muki"]:
		Enums.Muki.RIGHT, Enums.Muki.LEFT:
			data["x"] = p["x"]
			data["y"] = p["masu_y"] * 320
		Enums.Muki.DOWN, Enums.Muki.UP:
			data["x"] = p["masu_x"] * 320
			data["y"] = p["y"]

	data["masu_x"]    = p["masu_x"]
	data["masu_y"]    = p["masu_y"]
	data["bomb_x"]    = p["masu_x"]
	data["bomb_y"]    = p["masu_y"]

	if p["cr_item_use"] == Enums.ItemType.ROCKET:
		data["speed"] = Constants.KURU_ROCKET_SPEED
	elif p["kuru_speed"] > 0:
		data["speed"] = Constants.DEFAULT_KURU_SPEED + p["kuru_speed"] * Constants.KURU_SPEED_UP
	else:
		data["speed"] = Constants.DEFAULT_KURU_SPEED + p["kuru_speed"] * Constants.KURU_SPEED_DOWN
	data["speed"] = maxi(int(data["speed"]), 0)

	data["count"]     = p["kuru_dankai"] * Constants.KURU_DANKAI_TIME - 1
	data["muki"]      = p["muki"]
	data["move_muki"] = move_muki if is_brother else p["muki"]
	data["power"]     = mini(p["item_power"], p["max_power"])
	data["player"]    = player_num
	data["kuru_type"] = p["kuru_type"]  # 表示用に保存

	_sync_position()
	_update_sprite()


# ============================================================
# kuruCalc() 相当：毎フレーム Main.gd から呼ばれる
# 戻り値: false なら queue_free() すべき
# ============================================================
func kuru_calc() -> bool:
	kuru_move()
	var exploded := kuru_bomb()
	if exploded:
		return false
	kuru_hit_bomb()
	_update_sprite()
	return true


# ============================================================
# kuruMove() の移植
# ============================================================
func kuru_move() -> void:
	var move: int = data["speed"] / 2

	match data["move_muki"]:
		Enums.Muki.RIGHT:
			var next_x: int = data["x"] + move
			if next_x > Constants.MAP_SIZE_X:
				data["x"] = Constants.MAP_SIZE_X
				_trigger_early_explosion_on_collision()
			else:
				@warning_ignore("integer_division")
				var front_x: int = (next_x + 319) / 320
				var front_y: int = (data["y"] + 160) / 320
				if _is_hard_block_cell(front_x, front_y):
					data["x"] = front_x * 320 - 320
					_trigger_early_explosion_on_collision()
				else:
					data["x"] = next_x
		Enums.Muki.LEFT:
			var next_x: int = data["x"] - move
			if next_x < 0:
				data["x"] = 0
				_trigger_early_explosion_on_collision()
			else:
				@warning_ignore("integer_division")
				var front_x: int = next_x / 320
				var front_y: int = (data["y"] + 160) / 320
				if _is_hard_block_cell(front_x, front_y):
					data["x"] = (front_x + 1) * 320
					_trigger_early_explosion_on_collision()
				else:
					data["x"] = next_x
		Enums.Muki.DOWN:
			var next_y: int = data["y"] + move
			if next_y > Constants.MAP_SIZE_Y:
				data["y"] = Constants.MAP_SIZE_Y
				_trigger_early_explosion_on_collision()
			else:
				var front_x: int = (data["x"] + 160) / 320
				@warning_ignore("integer_division")
				var front_y: int = (next_y + 319) / 320
				if _is_hard_block_cell(front_x, front_y):
					data["y"] = front_y * 320 - 320
					_trigger_early_explosion_on_collision()
				else:
					data["y"] = next_y
		Enums.Muki.UP:
			var next_y: int = data["y"] - move
			if next_y < 0:
				data["y"] = 0
				_trigger_early_explosion_on_collision()
			else:
				var front_x: int = (data["x"] + 160) / 320
				@warning_ignore("integer_division")
				var front_y: int = next_y / 320
				if _is_hard_block_cell(front_x, front_y):
					data["y"] = (front_y + 1) * 320
					_trigger_early_explosion_on_collision()
				else:
					data["y"] = next_y

	# 爆風発生中心座標の更新
	match data["muki"]:
		Enums.Muki.RIGHT:
			data["bomb_x"] = (data["x"] + 319) / 320
			data["bomb_y"] = (data["y"] + 160) / 320
		Enums.Muki.LEFT:
			data["bomb_x"] = data["x"] / 320
			data["bomb_y"] = (data["y"] + 160) / 320
		Enums.Muki.DOWN:
			data["bomb_x"] = (data["x"] + 160) / 320
			data["bomb_y"] = (data["y"] + 319) / 320
		Enums.Muki.UP:
			data["bomb_x"] = (data["x"] + 160) / 320
			data["bomb_y"] = data["y"] / 320

	data["masu_x"] = (data["x"] + 160) / 320
	data["masu_y"] = (data["y"] + 160) / 320
	_sync_position()


func _is_hard_block_cell(cell_x: int, cell_y: int) -> bool:
	if cell_x < 0 or cell_x >= Constants.FIELD_COLS:
		return false
	if cell_y < 0 or cell_y >= Constants.FIELD_ROWS:
		return false
	return GameState.masu[cell_y][cell_x]["kind"] == Enums.MasuKind.HARD_BLOCK


func _trigger_early_explosion_on_collision() -> void:
	if data["count"] <= 3 * Constants.KURU_DANKAI_TIME:
		data["count"] = 0

func _is_blast_blocked(origin_x: int, origin_y: int, step_x: int, step_y: int, distance: int) -> bool:
	for step in range(1, distance + 1):
		if _is_hard_block_cell(origin_x + step_x * step, origin_y + step_y * step):
			return true
	return false


# ============================================================
# kuruBomb() の移植
# 爆発時に Bomb ノードを生成。true を返したらこのノードを削除
# ============================================================
func kuru_bomb() -> bool:
	if data["count"] == 0:
		# 爆風生成
		var bomb_scene: PackedScene = load("res://scenes/Bomb/Bomb.tscn")
		if bomb_scene:
			var bomb_node = bomb_scene.instantiate()
			bomb_node.init_bomb(data)
			get_parent().get_parent().get_node("BombContainer").add_child(bomb_node)

		# プレイヤーのshotKuruを減らす
		GameState.player[data["player"]]["shot_kuru"] -= 1
		return true
	else:
		data["count"] -= 1
		return false


# ============================================================
# kuruHitBomb() の移植
# ============================================================
func kuru_hit_bomb() -> void:
	var bomb_container := get_parent().get_parent().get_node_or_null("BombContainer")
	if bomb_container == null:
		return

	for bomb_node in bomb_container.get_children():
		var b: Dictionary = bomb_node.data
		var cnt: int = b["count"]
		var bx: int  = b["masu_x"]
		var by: int  = b["masu_y"]

		if cnt >= 0 and cnt <= Constants.BOMB_SPREAD_TIME:
			if (data["bomb_x"] == bx and data["bomb_y"] == by) or \
			   (data["masu_x"] == bx and data["masu_y"] == by):
				data["count"] = 0

		for i in range(1, b["power"] + 1):
			if cnt >= i * Constants.BOMB_SPREAD_TIME and cnt <= (i + 1) * Constants.BOMB_SPREAD_TIME:
				if (
					(
						(data["bomb_x"] == bx + i and data["bomb_y"] == by) or
						(data["masu_x"] == bx + i and data["masu_y"] == by)
					) and not _is_blast_blocked(bx, by, 1, 0, i)
				):
					data["count"] = 0
				elif (
					(
						(data["bomb_x"] == bx - i and data["bomb_y"] == by) or
						(data["masu_x"] == bx - i and data["masu_y"] == by)
					) and not _is_blast_blocked(bx, by, -1, 0, i)
				):
					data["count"] = 0
				elif (
					(
						(data["bomb_x"] == bx and data["bomb_y"] == by + i) or
						(data["masu_x"] == bx and data["masu_y"] == by + i)
					) and not _is_blast_blocked(bx, by, 0, 1, i)
				):
					data["count"] = 0
				elif (
					(
						(data["bomb_x"] == bx and data["bomb_y"] == by - i) or
						(data["masu_x"] == bx and data["masu_y"] == by - i)
					) and not _is_blast_blocked(bx, by, 0, -1, i)
				):
					data["count"] = 0


# ============================================================
# kuruDisp() 相当：Sprite2D + AtlasTexture で直接フレーム制御
# ============================================================
var _tex_cache: Dictionary = {}
var _frame_w: int = 40
var _frame_h: int = 40

func _make_trans(base: Texture2D, col: int, row: int, w: int, h: int) -> ImageTexture:
	var img := base.get_image()
	if img == null: return null
	var sub := img.get_region(Rect2i(col * w, row * h, w, h))
	sub.convert(Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(sub)

func _get_kuru_tex(kuru_type: int, frame: int) -> ImageTexture:
	var key := str(kuru_type) + "_" + str(frame)
	if _tex_cache.has(key):
		return _tex_cache[key]
	var kdef: Dictionary = Constants.get_kuru_def(kuru_type)
	var path: String = str(kdef.get("sheet_path", ""))
	var base_tex: Texture2D = ImageManager.get_image(path)
	if base_tex == null:
		return null
	@warning_ignore("integer_division")
	var fw: int = maxi(base_tex.get_width() / Constants.KURU_SHEET_COLS, 1)
	@warning_ignore("integer_division")
	var fh: int = maxi(base_tex.get_height() / Constants.KURU_SHEET_ROWS, 1)
	var col: int = frame % Constants.KURU_SHEET_COLS
	@warning_ignore("integer_division")
	var row: int = frame / Constants.KURU_SHEET_COLS
	var t := ImageManager.get_transparent_image(path, col, row, fw, fh)
	_tex_cache[key] = t
	return t

func _update_sprite() -> void:
	var dankai: int = data["count"] / Constants.KURU_DANKAI_TIME
	var in_dankai: int = data["count"] % Constants.KURU_DANKAI_TIME
	@warning_ignore("integer_division")
	var frame_in_dankai: int = (Constants.KURU_DANKAI_TIME - in_dankai) / (Constants.KURU_DANKAI_TIME / Constants.KURU_SHEET_COLS + 1)
	var row: int = clampi(Constants.KURU_SHEET_ROWS - 1 - dankai, 0, Constants.KURU_SHEET_ROWS - 1)
	var max_frame: int = Constants.KURU_SHEET_COLS * Constants.KURU_SHEET_ROWS - 1
	var img_num: int = clampi(row * Constants.KURU_SHEET_COLS + frame_in_dankai, 0, max_frame)
	var kuru_type: int = data["kuru_type"]  # GameState非依存
	var kdef: Dictionary = Constants.get_kuru_def(kuru_type)
	var path: String = str(kdef.get("sheet_path", ""))
	var base_tex: Texture2D = ImageManager.get_image(path)
	if base_tex:
		@warning_ignore("integer_division")
		_frame_w = maxi(base_tex.get_width() / Constants.KURU_SHEET_COLS, 1)
		@warning_ignore("integer_division")
		_frame_h = maxi(base_tex.get_height() / Constants.KURU_SHEET_ROWS, 1)
	
	# AnimatedSprite2D の代わりに Sprite2D を使う
	var sp: Sprite2D = get_node_or_null("Sprite2D")
	if sp == null:
		# AnimatedSprite2D が存在する場合は Sprite2D に差し替え
		var old_sp := get_node_or_null("AnimatedSprite2D")
		if old_sp:
			old_sp.queue_free()
		sp = Sprite2D.new()
		sp.name = "Sprite2D"
		add_child(sp)
	var tex: ImageTexture = _get_kuru_tex(kuru_type, img_num)
	if tex:
		sp.texture = tex


func _sync_position() -> void:
	# C++: DrawGraph((MAP_LEFT_SIDE+x)/10, (MAP_UP_SIDE+y)/10-10)
	# Sprite2D のアンカーは中心なので KURU_W/2, KURU_H/2 を加算
	var draw_offset_x: float = Constants.get_kuru_draw_offset_x(int(data["kuru_type"]))
	position = Vector2(
		(Constants.MAP_LEFT_SIDE + data["x"]) * 0.1 + (Constants.MASU_SIZE + _frame_w) / 2.0 - draw_offset_x,
		(Constants.MAP_UP_SIDE   + data["y"]) * 0.1 + Constants.MASU_SIZE - _frame_h / 2.0 - 3
	)
