extends Node2D

const HARD_BLOCK_DEFAULT_PATH := "res://assets/images/others/hardblock0.png"
const HARD_BLOCK_OFFSETS_BY_STAGE: Dictionary = {
	0: Vector2(-5.0, -20.0),
	1: Vector2(-5.0, -30.0),
	2: Vector2(-5.0, -16.0),
	3: Vector2(-5.0, -14.0),
}
const BASE_Z := 10

static var _loaded_hard_block_path: String = ""
static var _hard_block_transparent_texture: ImageTexture
static var _hard_block_offset: Vector2 = Vector2(-5.0, -20.0)

@onready var _sprite: Sprite2D = $Sprite2D

func init_hard_block(cell_x: int, cell_y: int) -> void:
	_ensure_hard_block_texture()
	if _hard_block_transparent_texture == null:
		visible = false
		return

	_sprite.texture = _hard_block_transparent_texture
	position = Vector2(
		Constants.to_godot_pos(Constants.MAP_LEFT_SIDE) + cell_x * Constants.MASU_SIZE,
		Constants.to_godot_pos(Constants.MAP_UP_SIDE) + cell_y * Constants.MASU_SIZE
	) + _hard_block_offset

	z_as_relative = false
	z_index = BASE_Z + Constants.to_godot_pos(Constants.MAP_UP_SIDE) + cell_y * Constants.MASU_SIZE - 15
	visible = true

func _ensure_hard_block_texture() -> void:
	var stage := GameState.clamp_stage(GameState.current_stage)
	var preferred_path := "res://assets/images/others/hardblock%d.png" % stage
	var path := preferred_path if ResourceLoader.exists(preferred_path) else HARD_BLOCK_DEFAULT_PATH
	var stage_offset: Variant = HARD_BLOCK_OFFSETS_BY_STAGE.get(stage, Vector2(-5.0, -20.0))
	_hard_block_offset = stage_offset as Vector2

	if _hard_block_transparent_texture != null and _loaded_hard_block_path == path:
		return

	_loaded_hard_block_path = path
	var hard_block_texture: Texture2D = ImageManager.get_image(path)
	if hard_block_texture == null:
		_hard_block_transparent_texture = null
		return
	_hard_block_transparent_texture = ImageManager.get_transparent_image(
		path,
		0,
		0,
		hard_block_texture.get_width(),
		hard_block_texture.get_height()
	)
