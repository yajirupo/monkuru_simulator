# scenes/Main/ComDebugOverlay.gd
extends Control

var bomb_container: Node
var kuru_container: Node
var com_think: ComThinkRoutine

var _font: Font
var _line_height: int = 14
var _small_font_size: int = 10

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_line_height = 14
	visible = false
	z_index = 4090   # 最前面表示

var _redraw_interval: int = 6

func _process(_delta: float) -> void:
	if not visible:
		return
	if GameState.count % _redraw_interval == 0:
		queue_redraw()

func _draw() -> void:
	if not visible or com_think == null:
		return

	var snap: Dictionary = com_think.debug_snapshot
	if snap.is_empty():
		return

	# 危険度グリッド（数値表示）
	var danger_grid: Array = snap.get("danger_grid", [])
	if not danger_grid.is_empty():
		for x in range(Constants.FIELD_COLS):
			if x >= danger_grid.size():
				break
			for y in range(Constants.FIELD_ROWS):
				if y >= danger_grid[x].size():
					break
				var hit_frame: int = danger_grid[x][y]
				if hit_frame != 9999:
					_draw_danger_number(x, y, hit_frame)

	# COM の現在位置
	var player_pos: Vector2i = snap.get("player_pos", Vector2i(-1, -1))
	if player_pos.x >= 0 and player_pos.y >= 0:
		_draw_player_marker(player_pos.x, player_pos.y)

	# フェーズに応じた経路表示
	var phase: String = snap.get("phase", "")

	# 脱出経路（ESCAPE または CHAIN_ATTACK のとき）
	if phase in ["ESCAPE", "CHAIN_ATTACK"]:
		var escape_path: Array = snap.get("escape_path", [])
		if not escape_path.is_empty():
			_draw_arrow_path(escape_path, Color.RED, 3.0)

	# 接近：選択した1マス方向の矢印
	if phase == "APPROACH" and snap.has("approach_dir"):
		var dir: int = snap["approach_dir"]
		if dir >= 0 and player_pos.x >= 0:
			var from_pos: Vector2 = _cell_to_screen(player_pos.x, player_pos.y) + Vector2(16, 16)
			var step := Utility.dir_to_vec(dir)
			var to_cell := player_pos + step
			var to_pos: Vector2 = _cell_to_screen(to_cell.x, to_cell.y) + Vector2(16, 16)
			_draw_arrow_segment(from_pos, to_pos, Color.BLUE, 5.0)

	# テキスト情報
	_draw_text_info(snap)


func _cell_to_screen(mx: int, my: int) -> Vector2:
	return Vector2(
		(Constants.MAP_LEFT_SIDE + mx * 320) * 0.1,
		(Constants.MAP_UP_SIDE   + my * 320) * 0.1
	)


func _draw_danger_number(x: int, y: int, hit_frame: int) -> void:
	var cell_center: Vector2 = _cell_to_screen(x, y) + Vector2(16, 28)
	var text: String = str(hit_frame)
	var color: Color
	if hit_frame <= 60:
		color = Color.RED
	elif hit_frame <= 180:
		color = Color.MAGENTA
	else:
		color = Color.BLUE

	var text_size: Vector2 = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, _small_font_size)
	draw_string(_font, cell_center - text_size / 2, text, HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font_size, color)


func _draw_player_marker(x: int, y: int) -> void:
	var pos: Vector2 = _cell_to_screen(x, y)
	var cell_size: Vector2 = Vector2(32, 32)
	draw_rect(Rect2(pos, cell_size), Color.GREEN, false, 2.0)


# BFS経路用の矢印つきポリライン（脱出用）
func _draw_arrow_path(path: Array, color: Color, width: float) -> void:
	if path.size() < 2:
		return
	var points: PackedVector2Array = []
	for cell in path:
		var screen_pos: Vector2 = _cell_to_screen(cell.x, cell.y) + Vector2(16, 16)
		points.append(screen_pos)

	draw_polyline(points, color, width)

	var last_index: int = points.size() - 1
	var tip: Vector2 = points[last_index]
	var base: Vector2 = points[last_index - 1]
	var direction: Vector2 = (tip - base).normalized()
	var arrow_size: float = 12.0

	var perpendicular: Vector2 = Vector2(-direction.y, direction.x) * arrow_size * 0.5
	var arrow_base_center: Vector2 = tip - direction * arrow_size
	var p1: Vector2 = arrow_base_center + perpendicular
	var p2: Vector2 = arrow_base_center - perpendicular

	var arrow_points: PackedVector2Array = [tip, p1, p2]
	draw_polygon(arrow_points, PackedColorArray([color, color, color]))


# 1セグメントの矢印（接近用）
func _draw_arrow_segment(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var points: PackedVector2Array = [from, to]
	draw_polyline(points, color, width)

	var direction: Vector2 = (to - from).normalized()
	var arrow_size: float = 12.0
	var perpendicular: Vector2 = Vector2(-direction.y, direction.x) * arrow_size * 0.5
	var arrow_base_center: Vector2 = to - direction * arrow_size
	var p1: Vector2 = arrow_base_center + perpendicular
	var p2: Vector2 = arrow_base_center - perpendicular

	var arrow_points: PackedVector2Array = [to, p1, p2]
	draw_polygon(arrow_points, PackedColorArray([color, color, color]))


func _draw_text_info(snap: Dictionary) -> void:
	var y: float = 16.0
	var x: float = get_viewport_rect().size.x - 300
	var col: Color = Color.GREEN

	var lines: Array = [
		"Phase: %s" % snap.get("phase", "?"),
		"Reason: %s" % snap.get("reason", ""),
		"In Danger: %s" % snap.get("in_danger", false),
		"Shot: %d/%d" % [snap.get("shot_count", 0), snap.get("shot_kuru", 0)],
		"Item: %d cnt:%d" % [snap.get("item_use", 0), snap.get("item_count", 0)],
	]
	for line in lines:
		draw_string(_font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, _line_height, col)
		y += _line_height + 2
	#print("Reason: %s" % snap.get("reason", ""))
