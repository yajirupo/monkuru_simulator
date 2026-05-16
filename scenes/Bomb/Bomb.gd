extends Node2D

var data: Dictionary = {
	"masu_x": 0,
	"masu_y": 0,
	"count":  0,
}

var _bomb1_tex: ImageTexture = null
var _bomb2_frames: Array[ImageTexture] = []

func init_bomb_from_cell(masu_x: int, masu_y: int, distance: int) -> void:
	data["masu_x"] = masu_x
	data["masu_y"] = masu_y
	data["count"] = -(2 + distance) * Constants.BOMB_SPREAD_TIME
	_sync_position()

# ============================================================
# bombCalc() 相当：毎フレーム呼ぶ
# ============================================================
func bomb_calc() -> bool:
	if data["count"] >= Constants.BOMB_STAY_TIME:
		return false
	_check_play_sound()
	data["count"] += 1
	_update_visuals()
	return true

# ============================================================
# スプライトシート情報（init.cpp の LoadDivGraph に対応）
# bomb1.png  : 単体画像
# bomb2.png  : 9フレーム横1列 70x78px
# ============================================================
func _load_textures() -> void:
	if _bomb1_tex != null:
		return
	_bomb1_tex = ImageManager.get_transparent_image("res://assets/images/others/bomb1.png", 0, 0, 33, 26)
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
		sp.visible = true
		sp.texture = _bomb1_tex
		sp.position = Vector2(data["masu_x"] * 32 + 16, data["masu_y"] * 32 + 16)
	elif cnt < Constants.BOMB_STAY_TIME:
		sp.visible = true
		@warning_ignore("integer_division")
		var f: int = mini(cnt / 2, 8)
		if f < _bomb2_frames.size():
			sp.texture = _bomb2_frames[f]
		sp.position = Vector2(data["masu_x"] * 32 + 17, data["masu_y"] * 32 - 9)
	else:
		sp.visible = false

func _check_play_sound() -> void:
	if data["count"] == 0:
		SoundManager.play_bomb()


func prepare_for_free() -> void:
	var sp: Sprite2D = get_node_or_null("CenterSprite")
	if sp:
		sp.texture = null
	_bomb1_tex = null
	_bomb2_frames.clear()
	data.clear()


func _sync_position() -> void:
	position = Vector2(Constants.MAP_LEFT_SIDE * 0.1, Constants.MAP_UP_SIDE * 0.1)
