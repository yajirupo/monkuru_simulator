# Field.gd
# field.cpp の移植
# ノード構成:
#   Field (Node2D) ← このスクリプト
#   ├── BackGround (Sprite2D)        ← img_backGround0 / img_backGround0VS
#   ├── TileMapLayer (TileMapLayer)  ← マス目（ブロック描画）
#   ├── ItemDisplay (Node2D)         ← アイテムアイコン
#   │   └── CrItemSprite[0..2] (Sprite2D) x 最大2プレイヤー
#   ├── StatusDisplay (Node2D)       ← ステータスサークル
#   └── ChatDisplay (Node2D)         ← チャットラベル
#       ├── ChatLabel0 (Label)
#       ├── ChatLabel1 (Label)
#       └── ChatLabel2 (Label)
# 
# 背景テクスチャをキャッシュし、毎フレームの再ロードを回避

extends Node2D

# ============================================================
# テクスチャキャッシュ（AtlasTexture）
# ============================================================
var _tex_cache: Dictionary = {}

func _get_atlas(path: String, col: int, row: int, w: int, h: int) -> AtlasTexture:
	var key := "%s_%d_%d" % [path, col, row]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var base := ImageManager.get_image(path)
	if base == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = base
	at.region = Rect2(col * w, row * h, w, h)
	_tex_cache[key] = at
	return at

# ============================================================
# ノード参照（シーンエディタで @export してもOK）
# ============================================================
@onready var back_ground:    Sprite2D     = $BackGround
@onready var tile_map:       TileMapLayer = $TileMapLayer
@onready var item_display:   Node2D       = $ItemDisplay
@onready var status_display: Node2D       = $StatusDisplay
@onready var chat_display:   Node2D       = $ChatDisplay


# ============================================================
# 背景テクスチャキャッシュ
# ============================================================
var _cached_bg_path: String = ""
var _cached_bg_tex: Texture2D = null

## 背景テクスチャをキャッシュ付きで取得する
func _get_or_load_bg(path: String) -> Texture2D:
	if path != _cached_bg_path:
		_cached_bg_tex = ImageManager.get_image(path)
		_cached_bg_path = path
	return _cached_bg_tex


# ============================================================
# ステータスサークルのオフセット座標
# （circleX / circleY をそのまま移植）
# ============================================================
const CIRCLE_X: Array[int] = [474, 478, 486, 495, 502, 503, 498, 490]
const CIRCLE_Y: Array[int] = [440, 432, 427, 429, 436, 445, 453, 457]

# アイテムアイコンX間隔
const ITEM_SPACING: int = 42


# ============================================================
# シングルプレイ用フィールド描画
# void fieldDisp() の移植
# ============================================================
func field_disp() -> void:
	# 背景切り替え（シングル用）→ キャッシュ利用
	var bg_path := _single_stage_bg_path()
	var bg := _get_or_load_bg(bg_path)
	if bg and back_ground:
		back_ground.texture = bg

	_reset_item_sprites()
	_draw_items_single_for(0)
	_draw_chat()
	_draw_status_single()


# ============================================================
# VSモード用フィールド描画
# void fieldDisp2() の移植
# ============================================================
func field_disp2() -> void:
	# 背景切り替え（VS用）→ キャッシュ利用
	var bg_path := _vs_stage_bg_path()
	var bg := _get_or_load_bg(bg_path)
	if bg and back_ground:
		back_ground.texture = bg

	_reset_item_sprites()
	# ステータス白丸を一括リセット
	if status_display:
		for child in status_display.get_children():
			child.visible = false
	for j in range(2):
		_draw_items_vs(j)
		_draw_status_vs(j)

	_draw_chat()


# ============================================================
# アイテムアイコン描画（VS）
# DrawGraph(41+42*i+305*j, 425, img_crItem[...], TRUE)
# ============================================================
func _draw_items_vs(player_idx: int) -> void:
	var p: Dictionary = GameState.player[player_idx]
	for i in range(3):
		var sprite: Sprite2D = item_display.get_node_or_null("P%dItem%d" % [player_idx, i])
		if sprite == null:
			continue
		var item: int = p["cr_item"][i]
		if item != Enums.ItemType.NO_ITEM:
			var tex := _get_transparent("res://assets/images/others/crItem.png", item - 1, 0, 32, 32)
			sprite.texture = tex
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.position = Vector2(41 + ITEM_SPACING * i + 306 * player_idx + 16, 425 + 16)
			sprite.visible = true
		else:
			sprite.visible = false

func _reset_item_sprites() -> void:
	if not item_display:
		return
	for child in item_display.get_children():
		var sprite := child as Sprite2D
		if sprite:
			sprite.visible = false


# ============================================================
# チャット描画
# DrawFormatStringToHandle(32, 427+15*i, ...)
# ============================================================
func _draw_chat() -> void:
	var cd: Node = chat_display if chat_display else get_node_or_null("ChatDisplay")
	if cd == null:
		return
	for i in range(3):
		var label: Label = cd.get_node_or_null("ChatLabel%d" % i)
		if label:
			label.text = GameState.chat_str[i]
			label.add_theme_color_override("font_color", GameState.chat_color[i])
			label.add_theme_font_size_override("font_size", 11)
			# 縁取りなし（黒字のみ）
			label.add_theme_constant_override("shadow_outline_size", 0)


# ============================================================
# ステータスサークル描画（シングル）
# ============================================================
func _draw_status_single() -> void:
	if status_display:
		for child in status_display.get_children():
			child.visible = false
	var p: Dictionary = GameState.player[0]
	_draw_status_circles(p, 0, 0, 0)


# ============================================================
# ステータスサークル描画（VS）
# circleX[i] - 296 + 305*j のオフセット
# ============================================================
func _draw_status_vs(player_idx: int) -> void:
	var p: Dictionary = GameState.player[player_idx]
	var offset_x: int = -297 + 306 * player_idx
	_draw_status_circles(p, offset_x, 0, player_idx)


# ============================================================
# ステータスサークル共通描画
# --------------------------------------------------------
# C++元ロジック:
#   火力ON : i=0 .. itemPower-2  → img_status[0] at (cx, cy)
#   火力OFF: i=maxPower-1 .. 7   → img_status[3] at (cx, cy+1)
#   くる数ON : +51x              → img_status[1]
#   くる数OFF: +51x              → img_status[4]
#   速度ON : +102x               → img_status[2]  cy+1
#   速度OFF: +102x               → img_status[5]  cy+2
# ============================================================
func _draw_status_circles(p: Dictionary, offset_x: int, offset_y: int, player_idx: int = 0) -> void:
	var status_node := status_display
	var prefix := "P%d_" % player_idx

	# --- 火力 ---
	for i in range(min(p["item_power"] - 1, 8)):
		_set_circle_sprite(status_node, prefix + "Power_On_%d" % i,
			Vector2(CIRCLE_X[i] + offset_x, CIRCLE_Y[i] + offset_y),
			0)  # img_status[0]
	for i in range(p["max_power"] - 1, 8):
		_set_circle_sprite(status_node, prefix + "Power_Off_%d" % i,
			Vector2(CIRCLE_X[i] + offset_x, CIRCLE_Y[i] + 1 + offset_y),
			3)  # img_status[3]

	# --- くる数 ---
	for i in range(min(p["item_shot"] - 1, 8)):
		_set_circle_sprite(status_node, prefix + "Shot_On_%d" % i,
			Vector2(51 + CIRCLE_X[i] + offset_x, CIRCLE_Y[i] + offset_y),
			1)  # img_status[1]
	for i in range(p["max_shot"] - 1, 8):
		_set_circle_sprite(status_node, prefix + "Shot_Off_%d" % i,
			Vector2(51 + CIRCLE_X[i] + offset_x, CIRCLE_Y[i] + 1 + offset_y),
			4)  # img_status[4]

	# --- 速度 ---
	for i in range(min(p["item_speed"] - 1, 8)):
		_set_circle_sprite(status_node, prefix + "Speed_On_%d" % i,
			Vector2(102 + CIRCLE_X[i] + offset_x, CIRCLE_Y[i] + 1 + offset_y),
			2)  # img_status[2]
	for i in range(p["max_speed"] - 1, 8):
		_set_circle_sprite(status_node, prefix + "Speed_Off_%d" % i,
			Vector2(102 + CIRCLE_X[i] + offset_x, CIRCLE_Y[i] + 2 + offset_y),
			5)  # img_status[5]


func _set_circle_sprite(parent: Node, node_name: String, pos: Vector2, tex_idx: int) -> void:
	var sprite: Sprite2D = parent.get_node_or_null(node_name)
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = node_name
		parent.add_child(sprite)
	# status.png: 3列2行 7x7px
	var col: int = tex_idx % 3
	@warning_ignore("integer_division")
	var row: int = tex_idx / 3
	var tex := _get_transparent("res://assets/images/others/status.png", col, row, 7, 7)
	sprite.texture = tex
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Sprite2D は中心が原点なので 7x7 の半分(3.5px)を加算
	sprite.position = pos + Vector2(3.5, 3.5)
	sprite.visible = true


# ============================================================
# 背景テクスチャ読み込み
# ============================================================

# ── 黒色を透明に変換 ──────────────────────────────────────
func _make_transparent_atlas(path: String, col: int, row: int, w: int, h: int) -> ImageTexture:
	return ImageManager.get_transparent_image(path, col, row, w, h)

var _trans_cache: Dictionary = {}

func _get_transparent(path: String, col: int, row: int, w: int, h: int) -> ImageTexture:
	var key := "%s_%d_%d" % [path, col, row]
	if _trans_cache.has(key): return _trans_cache[key]
	var t := _make_transparent_atlas(path, col, row, w, h)
	_trans_cache[key] = t
	return t

# ============================================================
# オンライン対戦用表示
# 練習モードの背景 + 自分のステータスのみ表示
# ============================================================
func field_disp_online(my_idx: int) -> void:
	# 背景 → キャッシュ利用
	var bg_path := _single_stage_bg_path()
	var bg := _get_or_load_bg(bg_path)
	if bg and back_ground:
		back_ground.texture = bg

	_reset_item_sprites()
	if status_display:
		for child in status_display.get_children():
			child.visible = false

	_draw_items_single_for(my_idx)
	_draw_status_for(my_idx)
	_draw_chat()

func _draw_items_single_for(player_idx: int) -> void:
	var p: Dictionary = GameState.player[player_idx]
	for i in range(3):
		# P0Item0〜P0Item2（シングル用ノード名で統一）
		var sprite: Sprite2D = item_display.get_node_or_null("P0Item%d" % i)
		if sprite == null:
			continue
		var item: int = p["cr_item"][i]
		if item > Enums.ItemType.NO_ITEM:
			var tex := _get_transparent("res://assets/images/others/crItem.png", item - 1, 0, 32, 32)
			sprite.texture = tex
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.position = Vector2(316 + ITEM_SPACING * i + 16, 425 + 16)
			sprite.visible = true
		else:
			sprite.visible = false

func _draw_status_for(player_idx: int) -> void:
	var p: Dictionary = GameState.player[player_idx]
	_draw_status_circles(p, 0, 0, 0)

func _single_stage_bg_path() -> String:
	return "res://assets/images/backGround/backGround%d.png" % GameState.clamp_stage(GameState.current_stage)

func _vs_stage_bg_path() -> String:
	return "res://assets/images/backGround/backGround%dVS.png" % GameState.clamp_stage(GameState.current_stage)
