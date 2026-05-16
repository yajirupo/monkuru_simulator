# GameState.gd
# globalVariable.h の移植（ゲーム進行・状態管理部分）
# Autoload に登録してください
# 名前: GameState

extends Node


# ============================================================
# 画面状態
# ============================================================
var joutai_flag: int = Enums.JoutaiType.MAIN_MENU


# ============================================================
# フレームカウンタ
# ============================================================
var count: int = 0

# ============================================================
# ステージ
# ============================================================
const STAGE_FILES: Array[String] = [
	"res://data/maps/map0.json",
	"res://data/maps/map1.json",
	"res://data/maps/map2.json",
	"res://data/maps/map3.json",
]
static var STAGE_COUNT: int = STAGE_FILES.size()
const MAP_CELL_HARD_BLOCK: int = 30
const MAP_CELL_PLAYER0_START: int = 40
const MAP_CELL_PLAYER7_START: int = 47
var current_stage: int = 0
var _stage_defs: Array[Dictionary] = []

# VS COM 用 開始位置の割り当て（プレイヤー i が使う開始位置インデックス）
var vs_com_start_assignments: Array[int] = []

# VS COM リプレイ中に使うプレイヤー数（1P + COM数）。リプレイファイルから復元される。
var vs_com_replay_player_count: int = 2
var vs_com_replay_frame_count: int = 0

# ============================================================
# フィールド（マス配列）
# masu[x][y]、FIELD_COLS=18、FIELD_ROWS=12
# 各要素は辞書: {"kind": Enums.MasuKind}
# ============================================================
var masu: Array = []

func _ready() -> void:
	_init_masu()
	_load_stage_defs()

func _init_masu() -> void:
	masu.clear()
	for x in range(Constants.FIELD_COLS):
		var col_arr: Array = []
		for y in range(Constants.FIELD_ROWS):
			col_arr.append({"kind": Enums.MasuKind.BROKEN})
		masu.append(col_arr)


# ============================================================
# プレイヤー
# player[0], player[1]
# struct_t の移植は PlayerData リソースを使用
# ============================================================
var player: Array = []   # PlayerData x MAX_PLAYER


# ============================================================
# チャット安全化
# ============================================================
const CHAT_MAX_NAME_LENGTH := 24
const CHAT_MAX_MESSAGE_LENGTH := 200

func sanitize_chat_text(text: String, max_length: int) -> String:
	var clean := text.replace("\r", " ").replace("\n", " ").replace("\t", " ").strip_edges()
	if clean.length() > max_length:
		clean = clean.substr(0, max_length)
	return clean


# ============================================================
# くるリスト（kuru_t 連結リスト → Node管理に変更）
# 実体は Field シーン内の KuruContainer ノードで管理。
# ここでは参照のみ保持。
# ============================================================
# （Nodeツリーで管理するため、グローバル変数としては不要）


# ============================================================
# 爆風リスト（bomb_t 連結リスト → Node管理に変更）
# 実体は Field シーン内の BombContainer ノードで管理。
# ============================================================
# （Nodeツリーで管理するため、グローバル変数としては不要）


# ============================================================
# リプレイ
# replayData[2][MAX_REPLAY_FLAME]
# ============================================================
var replay_data: Array = [
	PackedByteArray(), PackedByteArray(), PackedByteArray(), PackedByteArray(),
	PackedByteArray(), PackedByteArray(), PackedByteArray(), PackedByteArray(),
]
const REPLAY_TERMINATOR: int = 255
var p_replay_data: int = 0  # 現在の記録フレームポインタ
var vs_replay_return_state: int = Enums.JoutaiType.VS_MENU
var last_single_replay_data: PackedByteArray = PackedByteArray()
var last_single_replay_menu: Dictionary = {}
var last_single_replay_chat_events: Array[Dictionary] = []
var has_last_single_replay: bool = false
var last_vs_replay_data: Array = [PackedByteArray(), PackedByteArray(), PackedByteArray(), PackedByteArray(), PackedByteArray(), PackedByteArray(), PackedByteArray(), PackedByteArray()]
var last_vs_replay_menu: Dictionary = {}
var last_vs_replay_chat_events: Array[Dictionary] = []
var last_vs_replay_frame_count: int = 0
var last_vs_replay_is_com: bool = false
var has_last_vs_replay: bool = false
var last_online_replay_data: Array = [PackedByteArray(), PackedByteArray()]
var last_online_replay_menu: Dictionary = {}
var last_online_replay_chat_events: Array[Dictionary] = []
var last_online_replay_sync_events: Array[Dictionary] = []
var last_online_replay_kuru_events: Array[Dictionary] = []
var last_online_replay_state_events: Array[Dictionary] = []
var has_last_online_replay: bool = false
var online_replay_sync_events: Array[Dictionary] = []
var online_replay_sync_event_cursor: int = 0
var online_replay_kuru_events: Array[Dictionary] = []
var online_replay_kuru_event_cursor: int = 0
var online_replay_state_events: Array[Dictionary] = []
var online_replay_state_event_cursor: int = 0
var online_replay_local_player_idx: int = 0

func init_replay() -> void:
	for i in range(Constants.MAX_PLAYER):
		replay_data[i] = PackedByteArray()
		replay_data[i].resize(Constants.MAX_REPLAY_FLAME)
	p_replay_data = 0
	vs_com_replay_frame_count = 0

func clamp_stage(stage: int) -> int:
	return clampi(stage, 0, STAGE_COUNT - 1)

func get_stage_name(stage: int) -> String:
	var idx := clamp_stage(stage)
	if idx >= 0 and idx < _stage_defs.size():
		return str(_stage_defs[idx].get("stage_name", "Stage%d" % idx))
	return "Stage%d" % idx

func get_stage_hard_block_cells(stage: int) -> Array[Vector2i]:
	var idx := clamp_stage(stage)
	if idx < 0 or idx >= _stage_defs.size():
		return []
	var src: Array = _stage_defs[idx].get("hard_blocks", [])
	var out: Array[Vector2i] = []
	for cell in src:
		if cell is Vector2i:
			out.append(cell)
	return out

func get_stage_player_start_cell(stage: int, player_idx: int) -> Vector2i:
	var idx := clamp_stage(stage)
	var fallback := Vector2i(17 * player_idx, 10 * player_idx)
	if idx < 0 or idx >= _stage_defs.size():
		return fallback
	var key := "player%d_start" % player_idx
	var cell: Variant = _stage_defs[idx].get(key, null)
	if cell is Vector2i:
		return cell as Vector2i
	return fallback

func pick_random_stage() -> int:
	return randi_range(0, STAGE_COUNT - 1)

func _load_stage_defs() -> void:
	_stage_defs.clear()
	for i in range(STAGE_FILES.size()):
		_stage_defs.append(_load_single_stage_def(STAGE_FILES[i], i))

func _load_single_stage_def(path: String, index: int) -> Dictionary:
	var default_def := {
		"stage_name": "Stage%d" % index,
		"player0_start": Vector2i(0, 0),
		"player1_start": Vector2i(17, 10),
		"hard_blocks": [],
	}
	for i in range(2, 8):
		default_def["player%d_start" % i] = Vector2i(17, 10)
	if not FileAccess.file_exists(path):
		push_warning("GameState: stage map not found: %s" % path)
		return default_def

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("GameState: failed to open stage map: %s" % path)
		return default_def

	var json_text := file.get_as_text()
	file.close()

	var parser := JSON.new()
	if parser.parse(json_text) != OK:
		push_warning("GameState: failed to parse stage map JSON: %s" % path)
		return default_def
	if typeof(parser.data) != TYPE_DICTIONARY:
		push_warning("GameState: stage map root is not dictionary: %s" % path)
		return default_def

	var root: Dictionary = parser.data
	default_def["stage_name"] = str(root.get("stage_name", default_def["stage_name"]))

	var map_data: Variant = root.get("map_data", [])
	if typeof(map_data) != TYPE_ARRAY:
		push_warning("GameState: map_data is not array: %s" % path)
		return default_def

	var hard_blocks: Array[Vector2i] = []
	for y in range(min(Constants.FIELD_ROWS, map_data.size())):
		var row: Variant = map_data[y]
		if typeof(row) != TYPE_ARRAY:
			continue
		for x in range(min(Constants.FIELD_COLS, row.size())):
			var code := int(row[x])
			match code:
				MAP_CELL_HARD_BLOCK:
					hard_blocks.append(Vector2i(x, y))
				_:
					if code >= MAP_CELL_PLAYER0_START and code <= MAP_CELL_PLAYER7_START:
						var idx_player := code - MAP_CELL_PLAYER0_START
						default_def["player%d_start" % idx_player] = Vector2i(x, y)
	default_def["hard_blocks"] = hard_blocks
	return default_def

func remember_last_single_game_replay() -> void:
	var p: Dictionary = player[0]
	var replay_menu_src: Dictionary = GameData.menu_tmp
	last_single_replay_menu = {
		"name": p["name"],
		"stage": current_stage,
		"speed": p["max_speed"],
		"shot": p["max_shot"],
		"power": p["max_power"],
		"kuru_speed": replay_menu_src["kuru_speed"],
		"kuru_dankai": p["kuru_dankai"],
		"kuru_kankaku": p["kuru_kankaku"],
		# リプレイヘッダの装備アイテムは「試合終了時の残弾」ではなく
		# 「試合開始時に選択した内容」を保存する。
		"item_type": [
			replay_menu_src["item_type"][0],
			replay_menu_src["item_type"][1],
			replay_menu_src["item_type"][2],
		],
	}
	last_single_replay_data = _copy_replay_until_terminator(replay_data[0])
	last_single_replay_chat_events = replay_chat_events.duplicate(true)
	has_last_single_replay = true

func remember_last_vs_game_replay(is_vs_com: bool) -> void:
	# リプレイヘッダの装備アイテムは「試合終了時の残弾」ではなく
	# 「試合開始時に選択した内容」を保存する。
	# （特に VS COM では COM がアイテムを使用すると cr_item が NO_ITEM になり、
	#  その状態を保存すると再生時に同じアイテム使用が再現できないため）
	var replay_menu_src: Dictionary = GameData.vs_com_menu_tmp if is_vs_com else GameData.vs_menu_tmp
	var player_count := 2
	if is_vs_com:
		player_count = clampi(int(replay_menu_src.get("com_count", 1)), 1, Constants.MAX_PLAYER - 1) + 1
	var names: Array = []
	var player_types: Array = []
	var kuru_types: Array = []
	var item_types: Array = []
	for i in range(player_count):
		names.append(replay_menu_src["name"][i])
		player_types.append(replay_menu_src["player_type"][i])
		kuru_types.append(replay_menu_src["kuru_type"][i])
		item_types.append([replay_menu_src["item_type"][i][0], replay_menu_src["item_type"][i][1], replay_menu_src["item_type"][i][2]])
	last_vs_replay_menu = {"stage": current_stage, "name": names, "player_type": player_types, "kuru_type": kuru_types, "item_type": item_types, "player_count": player_count}
	# 開始位置割り当てもスナップショットとして保存
	last_vs_replay_menu["start_assignments"] = GameState.vs_com_start_assignments.duplicate()
	var data_copy_count := Constants.MAX_PLAYER if is_vs_com else 2
	if is_vs_com:
		last_vs_replay_frame_count = clampi(p_replay_data, 0, Constants.MAX_REPLAY_FLAME - 1)
		for i in range(data_copy_count):
			last_vs_replay_data[i] = _copy_replay_frames(replay_data[i], last_vs_replay_frame_count)
	else:
		last_vs_replay_frame_count = 0
		for i in range(data_copy_count):
			last_vs_replay_data[i] = _copy_replay_until_terminator(replay_data[i])
	last_vs_replay_chat_events = replay_chat_events.duplicate(true)
	last_vs_replay_is_com = is_vs_com
	has_last_vs_replay = true

func remember_last_online_game_replay() -> void:
	var om: Dictionary = GameState.online_menu
	var my_idx     := NetworkManager.my_player_index()
	var remote_idx := NetworkManager.remote_player_index()
	var remote: Dictionary = NetworkManager.remote_stats

	var names:        Array = ["", ""]
	var player_types: Array = [0, 0]
	var kuru_types:   Array = [0, 0]
	var item_types:   Array = [[0, 0, 0], [0, 0, 0]]

	if my_idx >= 0 and my_idx < Constants.MAX_PLAYER:
		names[my_idx]        = String(om.get("name", "Player"))
		player_types[my_idx] = int(om.get("character", Enums.PlayerType.YAMI))
		kuru_types[my_idx]   = int(om.get("kuru_type", Enums.KuruType.KIHON))
		var om_items = om.get("item_type", [0, 0, 0])
		item_types[my_idx]   = [int(om_items[0]), int(om_items[1]), int(om_items[2])]

	if remote_idx >= 0 and remote_idx < Constants.MAX_PLAYER:
		names[remote_idx]        = String(remote.get("name", "Player2"))
		player_types[remote_idx] = int(remote.get("character", Enums.PlayerType.YAMI))
		kuru_types[remote_idx]   = int(remote.get("kuru_type", Enums.KuruType.KIHON))
		var rm_items = remote.get("item_type", [0, 0, 0])
		item_types[remote_idx]   = [int(rm_items[0]), int(rm_items[1]), int(rm_items[2])]

	last_online_replay_menu = {
		"stage":       current_stage,
		"name":        names,
		"player_type": player_types,
		"kuru_type":   kuru_types,
		"item_type":   item_types,
	}
	last_online_replay_data[0] = _copy_replay_until_terminator(replay_data[0])
	last_online_replay_data[1] = _copy_replay_until_terminator(replay_data[1])
	last_online_replay_chat_events = replay_chat_events.duplicate(true)
	last_online_replay_sync_events = online_replay_sync_events.duplicate(true)
	last_online_replay_kuru_events = online_replay_kuru_events.duplicate(true)
	last_online_replay_state_events = online_replay_state_events.duplicate(true)
	has_last_online_replay = true

func _copy_replay_until_terminator(src: PackedByteArray) -> PackedByteArray:
	var term_pos := src.find(REPLAY_TERMINATOR)
	if term_pos >= 0:
		return src.slice(0, term_pos + 1)   # ターミネータを含めてスライス
	var out := src.duplicate()
	out.append(REPLAY_TERMINATOR)
	return out

func _copy_replay_frames(src: PackedByteArray, frame_count: int) -> PackedByteArray:
	var safe_count := clampi(frame_count, 0, mini(src.size(), Constants.MAX_REPLAY_FLAME - 1))
	var out := src.slice(0, safe_count)
	out.append(REPLAY_TERMINATOR)
	return out

# ============================================================
# チャット文字列（chatStr[3][50]）
# ============================================================
var chat_str: Array[String] = ["", "", ""]
var chat_color: Array = [Color.BLACK, Color.BLACK, Color.BLACK]
var replay_chat_events: Array[Dictionary] = []
var replay_chat_event_cursor: int = 0

func reset_replay_chat_events() -> void:
	replay_chat_events.clear()
	replay_chat_event_cursor = 0

func reset_online_replay_sync_events() -> void:
	online_replay_sync_events.clear()
	online_replay_sync_event_cursor = 0
	online_replay_kuru_events.clear()
	online_replay_kuru_event_cursor = 0
	online_replay_state_events.clear()
	online_replay_state_event_cursor = 0
	online_replay_local_player_idx = 0

func append_replay_chat_event(player_name: String, message: String, color: Color, frame: int = -1) -> void:
	replay_chat_events.append({
		"frame": GameState.count if frame < 0 else frame,
		"player_name": sanitize_chat_text(player_name, CHAT_MAX_NAME_LENGTH),
		"message": sanitize_chat_text(message, CHAT_MAX_MESSAGE_LENGTH),
		"color": color,
	})

func append_chat_message(player_name: String, message: String, color: Color = Color(162.0/255.0, 162.0/255.0, 64.0/255.0), record_replay_event: bool = true) -> void:
	var safe_name := sanitize_chat_text(player_name, CHAT_MAX_NAME_LENGTH)
	if safe_name == "":
		safe_name = "Player"
	var safe_message := sanitize_chat_text(message, CHAT_MAX_MESSAGE_LENGTH)
	if safe_message == "":
		return
	var full_text := "%s : %s" % [safe_name, safe_message]
	var font: Font = ThemeDB.fallback_font
	var font_size: int = ThemeDB.fallback_font_size
	var max_width_px := 280.0

	var line1 := _fit_chat_text(full_text, font, font_size, max_width_px)
	_push_chat_line(line1, color)

	if line1.length() < full_text.length():
		var rest := full_text.substr(line1.length()).strip_edges()
		var line2 := _fit_chat_text(" " + rest, font, font_size, max_width_px)
		_push_chat_line(line2, color)

	if record_replay_event:
		append_replay_chat_event(safe_name, safe_message, color)

func process_replay_chat_events() -> void:
	while replay_chat_event_cursor < replay_chat_events.size():
		var ev: Dictionary = replay_chat_events[replay_chat_event_cursor]
		if int(ev.get("frame", 0)) != GameState.count:
			return
		append_chat_message(
			String(ev.get("player_name", "")),
			String(ev.get("message", "")),
			ev.get("color", Color.BLACK),
			false
		)
		replay_chat_event_cursor += 1

func _fit_chat_text(text: String, font: Font, font_size: int, max_w: float) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
		return text
	var lo := 0
	var hi := text.length()
	while lo < hi:
		@warning_ignore("integer_division")
		var mid := (lo + hi + 1) / 2
		var w := font.get_string_size(text.substr(0, mid), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if w <= max_w:
			lo = mid
		else:
			hi = mid - 1
	return text.substr(0, lo)

func _push_chat_line(text: String, color: Color) -> void:
	var idx: int
	if GameState.chat_str[0] == "":
		idx = 0
	elif GameState.chat_str[1] == "":
		idx = 1
	elif GameState.chat_str[2] == "":
		idx = 2
	else:
		idx = 2
		GameState.chat_str[0] = GameState.chat_str[1]
		GameState.chat_str[1] = GameState.chat_str[2]
		GameState.chat_color[0] = GameState.chat_color[1]
		GameState.chat_color[1] = GameState.chat_color[2]
	GameState.chat_str[idx] = text
	GameState.chat_color[idx] = color


# ============================================================
# メインメニューカーソル
# ============================================================
var main_menu_cursor: int = 0


# ============================================================
# 音量設定（%）
# ============================================================
var bgm_volume_percent: float = 100.0
var se_volume_percent: float = 100.0


# ============================================================
# キーコンフィグ
# ============================================================
var key_config_menu_cursor: int = 0
var key_config_cursor: int = 0

# useKey[2][8]: プレイヤー別・8アクションのキー設定
# インデックス: [player_index][action_index]
var use_key: Array = [
	[0, 0, 0, 0, 0, 0, 0, 0],  # Player 0
	[0, 0, 0, 0, 0, 0, 0, 0],  # Player 1
	[0, 0, 0, 0, 0, 0, 0, 0],  # Player 2
	[0, 0, 0, 0, 0, 0, 0, 0],  # Player 3
	[0, 0, 0, 0, 0, 0, 0, 0],  # Player 4
	[0, 0, 0, 0, 0, 0, 0, 0],  # Player 5
	[0, 0, 0, 0, 0, 0, 0, 0],  # Player 6
	[0, 0, 0, 0, 0, 0, 0, 0],  # Player 7
]

# シングル・VS用の別キーセット
var use_key_single: Array[int]  = [0, 0, 0, 0, 0, 0, 0, 0]
var use_key_vs_1p:  Array[int]  = [0, 0, 0, 0, 0, 0, 0, 0]
var use_key_vs_2p:  Array[int]  = [0, 0, 0, 0, 0, 0, 0, 0]


# ネット対戦設定（永続化対象）
var online_menu: Dictionary = {
	"name": "Player",
	"ip_address": "127.0.0.1",
	"stage": 0,
	"character": 0, "kuru_type": 0,
	"item_type": [0, 0, 0],
}
