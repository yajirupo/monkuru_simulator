# Constants.gd
# define.h の移植
# Autoload（Project > Project Settings > Autoload）に登録してください
# 名前: Constants

extends Node


# ============================================================
# JSON定義の読み込み（キャラクター / くる）
# ============================================================

const CHARACTER_DATA_DIR := "res://data/character"
const KURU_DATA_DIR := "res://data/kuru"

const DEFAULT_CHARACTER_DEF := {
	"name": "不明キャラ",
	"max_stats": {"speed": 6, "shot": 5, "power": 5},
	"sprites": {
		"stand_d": {"suffix": "StandD", "cols": 9},
		"stand_u": {"suffix": "StandU", "cols": 9},
		"stand_l": {"suffix": "StandL", "cols": 9},
		"stand_r": {"suffix": "StandR", "cols": 9},
		"run_d": {"suffix": "RunD", "cols": 6},
		"run_u": {"suffix": "RunU", "cols": 6},
		"run_l": {"suffix": "RunL", "cols": 6},
		"run_r": {"suffix": "RunR", "cols": 6},
		"death": {"suffix": "Death", "cols": 20},
		"appear": {"suffix": "Appear", "cols": 23},
	},
}

const DEFAULT_KURU_DEF := {
	"name": "不明くる",
	"speed": 0, "dankai": 5, "kankaku": 12, "speed_up": 0, "shot_up": 0, "power_up": 0,
	"sheet_path": "res://assets/images/kuru/cm_kuru999.png",
	"draw_offset_x": 18.0,
}

const KURU_SHEET_COLS := 8
const KURU_SHEET_ROWS := 4

var _character_defs_runtime: Array = []
var _kuru_stats_runtime: Array = []
var _status_data_loaded: bool = false

func _ready() -> void:
	_load_status_data_from_files()

func _load_status_data_from_files() -> void:
	if _status_data_loaded:
		return
	_status_data_loaded = true
	_character_defs_runtime = _load_indexed_json_array(CHARACTER_DATA_DIR, "character")
	_kuru_stats_runtime = _load_indexed_json_array(KURU_DATA_DIR, "kuru")

func _load_indexed_json_array(dir_path: String, prefix: String) -> Array:
	var result: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("ステータス定義ディレクトリを開けませんでした: %s" % dir_path)
		return result

	var files: Array = []
	var re := RegEx.new()
	var index_pattern := "\\d{2}"
	if re.compile("^%s(%s)\\.json$" % [prefix, index_pattern]) != OK:
		push_error("ファイル名正規表現の初期化に失敗しました: %s" % prefix)
		return result

	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name == "":
			break
		if dir.current_is_dir():
			continue
		var matched := re.search(file_name)
		if matched == null:
			continue
		files.append({"index": int(matched.get_string(1)), "name": file_name})
	dir.list_dir_end()

	files.sort_custom(func(a, b): return int(a["index"]) < int(b["index"]))
	for info in files:
		var idx: int = int(info["index"])
		if idx < 0:
			continue
		if idx != result.size():
			push_warning("連番が欠けています: %s%d.json" % [prefix, idx])
		var path := "%s/%s" % [dir_path, info["name"]]
		var data := _load_json_dict(path)
		if data.is_empty():
			continue
		result.append(data)
	return result

func _load_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("JSONファイルが見つかりません: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("JSONファイルを開けませんでした: %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("JSONの形式が不正です(辞書を期待): %s" % path)
		return {}
	return _normalize_numeric_types(parsed)

func _normalize_numeric_types(value: Variant, key_name: String = "") -> Variant:
	if value is Dictionary:
		var normalized: Dictionary = {}
		for key in value.keys():
			var key_str := str(key)
			normalized[key] = _normalize_numeric_types(value[key], key_str)
		return normalized
	if value is Array:
		var normalized_array: Array = []
		normalized_array.resize(value.size())
		for i in range(value.size()):
			normalized_array[i] = _normalize_numeric_types(value[i], key_name)
		return normalized_array
	if typeof(value) == TYPE_FLOAT and key_name != "draw_offset_x":
		return int(value)
	return value

func get_practice_kuru_type() -> int:
	_load_status_data_from_files()
	for i in range(_kuru_stats_runtime.size()):
		if str(_kuru_stats_runtime[i].get("sheet_path", "")) == "res://assets/images/kuru/cm_kuru999.png":
			return i
	return 0

func get_kuru_count() -> int:
	_load_status_data_from_files()
	return _kuru_stats_runtime.size()

func get_kuru_def(kuru_type: int) -> Dictionary:
	_load_status_data_from_files()
	if kuru_type < 0 or kuru_type >= _kuru_stats_runtime.size():
		return DEFAULT_KURU_DEF
	return _kuru_stats_runtime[kuru_type]

func get_kuru_name(kuru_type: int) -> String:
	return str(get_kuru_def(kuru_type).get("name", DEFAULT_KURU_DEF["name"]))

func get_kuru_draw_offset_x(kuru_type: int) -> float:
	var kdef: Dictionary = get_kuru_def(kuru_type)
	return float(kdef.get("draw_offset_x", DEFAULT_KURU_DEF["draw_offset_x"]))

func get_character_count() -> int:
	_load_status_data_from_files()
	return _character_defs_runtime.size()

func get_character_def(character_type: int) -> Dictionary:
	_load_status_data_from_files()
	if character_type < 0 or character_type >= _character_defs_runtime.size():
		return DEFAULT_CHARACTER_DEF
	var base: Dictionary = DEFAULT_CHARACTER_DEF.duplicate(true)
	base.merge(_character_defs_runtime[character_type], true)
	var merged_sprites: Dictionary = DEFAULT_CHARACTER_DEF.get("sprites", {}).duplicate(true)
	merged_sprites.merge(base.get("sprites", {}), true)
	base["sprites"] = merged_sprites
	return base

func get_character_name(character_type: int) -> String:
	return str(get_character_def(character_type).get("name", "不明キャラ"))

func get_character_max_stats(character_type: int) -> Dictionary:
	var cdef: Dictionary = get_character_def(character_type)
	return cdef.get("max_stats", DEFAULT_CHARACTER_DEF["max_stats"])

func get_status_with_kuru_bonus(character_type: int, kuru_type: int) -> Dictionary:
	var max_stats: Dictionary = get_character_max_stats(character_type)
	var kuru_def: Dictionary = get_kuru_def(kuru_type)
	return {
		"speed_base": int(max_stats.get("speed", 0)),
		"shot_base": int(max_stats.get("shot", 0)),
		"power_base": int(max_stats.get("power", 0)),
		"speed_bonus": int(kuru_def.get("speed_up", 0)),
		"shot_bonus": int(kuru_def.get("shot_up", 0)),
		"power_bonus": int(kuru_def.get("power_up", 0)),
		"kuru_speed": kuru_speed_stat_to_move_speed(int(kuru_def.get("speed", 0))),
		"kuru_speed_stat": int(kuru_def.get("speed", 0)),
		"kuru_dankai": int(kuru_def.get("dankai", 0)),
		"kuru_kankaku": int(kuru_def.get("kankaku", 0)),
	}

func format_signed_bonus(v: int) -> String:
	if v == 0:
		return ""
	if v > 0:
		return "(+%d)" % v
	return "(%d)" % v

func get_character_sprite_info(character_type: int, sprite_key: String) -> Dictionary:
	var cdef: Dictionary = get_character_def(character_type)
	var sprites: Dictionary = cdef.get("sprites", {})
	var default_sprites: Dictionary = DEFAULT_CHARACTER_DEF.get("sprites", {})
	if sprites.has(sprite_key):
		return sprites[sprite_key]
	if default_sprites.has(sprite_key):
		return default_sprites[sprite_key]
	return {}


# ============================================================
# プレイヤー操作
# ============================================================

# 振り向き受け付け時間（フレーム）
const WAIT := 4


# ============================================================
# フィールド情報
# ============================================================

const MAP_SIZE_X    := 5440
const MAP_SIZE_Y    := 3520
const MAP_LEFT_SIDE := 320
const MAP_UP_SIDE   := 305

# マス目サイズ（ピクセル）
const MASU_SIZE := 32

# フィールドのマス数
const FIELD_COLS := 18 
const FIELD_ROWS := 12

# プレイヤーのコーナースライド閾値（0.1px単位）
const PLAYER_CORNER_SLIDE_THRESHOLD = 160


# ============================================================
# プレイヤー初期ステータス
# ============================================================

const PLAYER_DEFAULT_ITEM_SPEED := 1
const PLAYER_DEFAULT_ITEM_SHOT  := 1
const PLAYER_DEFAULT_ITEM_POWER := 1


# ============================================================
# くる速度
# ============================================================

# 速度0時の定数値（単位: 0.1px/frame。実際の移動量はこの値の1/2）
const DEFAULT_KURU_SPEED  := 10

# 速度上昇・減少の定数値（単位: 0.1px/frame。実際の移動量はこの値の1/2）
const KURU_SPEED_UP   := 3
const KURU_SPEED_DOWN := 4

# ロケット使用時に1フレームで移動するサブピクセル数
const KURU_ROCKET_SPEED := 15

# KURU_STATS の speed 段階値を、実際に1フレームで移動するサブピクセル数へ変換する。
# GameState.player[*]["kuru_speed"] と Kuru.data["speed"] は変換後の値を保持する。
func kuru_speed_stat_to_move_speed(kuru_speed_stat: int) -> int:
	var speed: int
	if kuru_speed_stat > 0:
		speed = DEFAULT_KURU_SPEED + kuru_speed_stat * KURU_SPEED_UP
	else:
		speed = DEFAULT_KURU_SPEED + kuru_speed_stat * KURU_SPEED_DOWN
	@warning_ignore("integer_division")
	return maxi(int(speed / 2), 0)


# ============================================================
# プレイヤー速度
# ============================================================

# スピードアイテム1段階あたりの上昇定数（単位: 0.1px/frame。実際の移動量はこの値の1/2）
const PLAYER_SPEED_UP      := 6

# 初期速度定数（単位: 0.1px/frame。実際の移動量はこの値の1/2）
const PLAYER_DEFAULT_SPEED := 35

# スピード靴使用時の実速度（単位: 0.1px/frame）
const SHOES_SPEED          := 50

# ---- 座標変換ヘルパー ----
# C++の座標（0.1px単位整数）→ Godotのfloat px
func to_godot_pos(cpp_val: int) -> float:
	return cpp_val * 0.1


# ============================================================
# 爆風
# ============================================================

# 爆風の広がる速さ 兼 当たり判定持続時間（フレーム）
const BOMB_SPREAD_TIME := 6

# 爆風しぶき残留時間（フレーム）
const BOMB_STAY_TIME   := 18


# ============================================================
# リプレイ
# ============================================================

const MAX_REPLAY_FLAME := 36000


# ============================================================
# 描画
# ============================================================

# 描画更新頻度（フレーム）
const REFRESH_PICTURE_TIME := 4


# ============================================================
# アイテム
# ============================================================

# アイテム使用制限時間の比例定数
const ITEM_USE_TIMES := 60


# ============================================================
# くる段階
# ============================================================

# くる1段階あたりの時間（フレーム）
const KURU_DANKAI_TIME := 60


# ============================================================
# FPS / プレイヤー数
# ============================================================

const FPS        := 60
const MAX_PLAYER := 8
