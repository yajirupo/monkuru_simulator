# Constants.gd
# define.h の移植
# Autoload（Project > Project Settings > Autoload）に登録してください
# 名前: Constants

extends Node


# ============================================================
# 各キャラクター定義（名前 / ステータス / 画像情報）
# ============================================================
# 追加方法:
# 1) この CHARACTER_DEFS に 1 エントリ追加
# 2) assets/images に character{index}{suffix}.png を配置
#    suffix は StandD/U/L/R と RunD/U/L/R と Death
#
# ※ 各画像は「縦1枚 × 横N枚」固定。
#    stand は cols=9、run は cols=6、death は cols=20 を想定。
const CHARACTER_DEFS := [
	{
		"name": "ヤミ",
		"max_stats": {"speed": 6, "shot": 5, "power": 5},
		"sprites": {
			"stand_d": {"suffix": "StandD", "cols": 9},
			"stand_u": {"suffix": "StandU", "cols": 9},
			"stand_l": {"suffix": "StandL", "cols": 9},
			"stand_r": {"suffix": "StandR", "cols": 9},
			"run_d":   {"suffix": "RunD",   "cols": 6},
			"run_u":   {"suffix": "RunU",   "cols": 6},
			"run_l":   {"suffix": "RunL",   "cols": 6},
			"run_r":   {"suffix": "RunR",   "cols": 6},
			"death":   {"suffix": "Death",  "cols": 20},
		},
	},
	{"name": "シュンイ", "max_stats": {"speed": 4, "shot": 7, "power": 5}},
	{"name": "ウチ",     "max_stats": {"speed": 5, "shot": 7, "power": 4}},
	{"name": "シュガー", "max_stats": {"speed": 7, "shot": 5, "power": 3}},
	{"name": "ヌピ",     "max_stats": {"speed": 7, "shot": 3, "power": 5}},
	{"name": "ムンチ",   "max_stats": {"speed": 4, "shot": 5, "power": 7}},
	{"name": "ボドリ",   "max_stats": {"speed": 7, "shot": 7, "power": 7}},
]

const DEFAULT_CHARACTER_DEF := CHARACTER_DEFS[0]


# ============================================================
# 各くるのステータス
# ============================================================

# くる種別ごとの設定をまとめた配列
# 管理項目: 名前 / ステータス / 画像パス
# 画像は全種共通で「横8 × 縦4」想定
# 使用例: Constants.KURU_STATS[Enums.KuruType.KIHON]["speed"]
const KURU_STATS := [
	{"name": "基本くる",   "speed": 0,  "dankai": 5, "kankaku": 12, "speed_up": 0, "shot_up": 0,  "power_up": 0,  "sheet_path": "res://assets/images/kuru/cm_kuru000.png"},
	{"name": "マンゴ",     "speed": 1,  "dankai": 6, "kankaku": 0, "speed_up": 0, "shot_up": 1,  "power_up": 0,  "sheet_path": "res://assets/images/kuru/cm_kuru002.png"},
	{"name": "マロ",      "speed": -1, "dankai": 5, "kankaku": 18,  "speed_up": 1, "shot_up": 0,  "power_up": 0,  "sheet_path": "res://assets/images/kuru/cm_kuru004.png"},
	{"name": "クシィ",     "speed": 1,  "dankai": 5, "kankaku": 12, "speed_up": 0, "shot_up": 0,  "power_up": 1,  "sheet_path": "res://assets/images/kuru/cm_kuru001.png"},
	{"name": "ポプリ",     "speed": -2, "dankai": 4, "kankaku": 0,  "speed_up": 1, "shot_up": 0,  "power_up": 0,  "sheet_path": "res://assets/images/kuru/cm_kuru003.png"},
	{"name": "クリ",     "speed": -2, "dankai": 5, "kankaku": 0,  "speed_up": 0, "shot_up": 0,  "power_up": 0,  "sheet_path": "res://assets/images/kuru/cm_kuru027.png"},
	{"name": "ハニー",     "speed": 1, "dankai": 5, "kankaku": 12,  "speed_up": 0, "shot_up": 0,  "power_up": 0,  "sheet_path": "res://assets/images/kuru/cm_kuru011.png"},
	{"name": "モネ",      "speed": 1, "dankai": 4, "kankaku": 12,  "speed_up": 0, "shot_up": 1,  "power_up": 0,  "sheet_path": "res://assets/images/kuru/cm_kuru007.png"},
	{"name": "シャンプー",  "speed": 1, "dankai": 5, "kankaku": 0,  "speed_up": 1, "shot_up": 0,  "power_up": 0,  "sheet_path": "res://assets/images/kuru/cm_kuru006.png"},
	{"name": "ダミ",      "speed": 2, "dankai": 4, "kankaku": 18,  "speed_up": 0, "shot_up": 1,  "power_up": 0,  "sheet_path": "res://assets/images/kuru/cm_kuru005.png"},
	{"name": "シネ",      "speed": 3, "dankai": 4, "kankaku": 24,  "speed_up": 1, "shot_up": 0,  "power_up": 0,  "sheet_path": "res://assets/images/kuru/cm_kuru008.png"},
	{"name": "トト",      "speed": 1, "dankai": 4, "kankaku": 0,  "speed_up": 0, "shot_up": 0,  "power_up": 1,  "sheet_path": "res://assets/images/kuru/cm_kuru016.png"},
	{"name": "ヨラン",     "speed": 0, "dankai": 5, "kankaku": 18,  "speed_up": 0, "shot_up": 1,  "power_up": 0,  "sheet_path": "res://assets/images/kuru/cm_kuru009.png"},
	{"name": "チン",      "speed": -2, "dankai": 4, "kankaku": 12,  "speed_up": 0, "shot_up": 1,  "power_up": 0,  "sheet_path": "res://assets/images/kuru/cm_kuru012.png"},
	{"name": "ドトリ",     "speed": -1, "dankai": 5, "kankaku": 18,  "speed_up": 0, "shot_up": 0,  "power_up": 2,  "sheet_path": "res://assets/images/kuru/cm_kuru013.png"},
	{"name": "ソンイ",     "speed": 1, "dankai": 4, "kankaku": 12,  "speed_up": 0, "shot_up": 1,  "power_up": 0,  "sheet_path": "res://assets/images/kuru/cm_kuru010.png"},
	{"name": "ディバー",    "speed": -1, "dankai": 4, "kankaku": 18,  "speed_up": 0, "shot_up": 1,  "power_up": 0,  "sheet_path": "res://assets/images/kuru/cm_kuru017.png"},
	{"name": "カムチョ",    "speed": -1, "dankai": 4, "kankaku": 12,  "speed_up": 0, "shot_up": 1,  "power_up": 0,  "sheet_path": "res://assets/images/kuru/cm_kuru014.png"},
	{"name": "ヘバ",      "speed": -3, "dankai": 5, "kankaku": 0,  "speed_up": 0, "shot_up": 0,  "power_up": 1,  "sheet_path": "res://assets/images/kuru/cm_kuru021.png"},
	{"name": "カミ",      "speed": 0, "dankai": 5, "kankaku": 0,  "speed_up": 1, "shot_up": 0,  "power_up": 0,  "sheet_path": "res://assets/images/kuru/cm_kuru019.png"},
	{"name": "ポイ",      "speed": 0, "dankai": 4, "kankaku": 0,  "speed_up": 0, "shot_up": 0,  "power_up": 2,  "sheet_path": "res://assets/images/kuru/cm_kuru020.png"},
	{"name": "升ンガン",   "speed": 50, "dankai": 4, "kankaku": 0,  "speed_up": 5, "shot_up": 16, "power_up": 16, "sheet_path": "res://assets/images/kuru/cm_kuru999.png"},
]

const KURU_SHEET_COLS := 8
const KURU_SHEET_ROWS := 4

# くる種別ごとの描画X補正（Godot座標: px）
# index は Enums.KuruType に対応
const KURU_DRAW_OFFSET_X := [
	18.0, # 基本くる
	17.0, # マンゴ
	16.0, # マロ
	16.5, # クシィ
	15.0, # ポプリ
	19.0, # クリ
	21.5, # ハニー
	15.0, # モネ
	15.5, # シャンプー
	19.0, # ダミ
	22.0, # シネ
	22.0, # トト
	15.0, # ヨラン
	14.0, # チン
	13.0, # ドトリ
	16.0, # ソンイ
	17.0, # ディバー
	15.0, # カムチョ
	18.0, # ヘバ
	16.0, # カミ
	18.5, # ポイ
	16.0, # 升ンガン
]

const DEFAULT_KURU_DEF := {
	"name": "不明くる",
	"speed": 0, "dankai": 5, "kankaku": 12, "speed_up": 0, "shot_up": 0, "power_up": 0,
	"sheet_path": "res://assets/images/kuru/cm_kuru999.png"
}

func get_practice_kuru_type() -> int:
	for i in range(KURU_STATS.size()):
		if str(KURU_STATS[i].get("sheet_path", "")) == "res://assets/images/kuru/cm_kuru999.png":
			return i
	return 0

func get_kuru_count() -> int:
	return KURU_STATS.size()

func get_kuru_def(kuru_type: int) -> Dictionary:
	if kuru_type < 0 or kuru_type >= KURU_STATS.size():
		return DEFAULT_KURU_DEF
	return KURU_STATS[kuru_type]

func get_kuru_name(kuru_type: int) -> String:
	return str(get_kuru_def(kuru_type).get("name", DEFAULT_KURU_DEF["name"]))

func get_kuru_draw_offset_x(kuru_type: int) -> float:
	if kuru_type < 0 or kuru_type >= KURU_DRAW_OFFSET_X.size():
		return 0.0
	return float(KURU_DRAW_OFFSET_X[kuru_type])

func get_character_count() -> int:
	return CHARACTER_DEFS.size()

func get_character_def(character_type: int) -> Dictionary:
	if character_type < 0 or character_type >= CHARACTER_DEFS.size():
		return DEFAULT_CHARACTER_DEF
	var base: Dictionary = DEFAULT_CHARACTER_DEF.duplicate(true)
	base.merge(CHARACTER_DEFS[character_type], true)
	if not base.has("sprites"):
		base["sprites"] = DEFAULT_CHARACTER_DEF.get("sprites", {}).duplicate(true)
	else:
		var merged_sprites: Dictionary = DEFAULT_CHARACTER_DEF.get("sprites", {}).duplicate(true)
		merged_sprites.merge(base["sprites"], true)
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
		"kuru_speed": int(kuru_def.get("speed", 0)),
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
# メニュー
# ============================================================

const MAX_MENU_LINE := 10


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
const MAP_RIGHT_SIDE  := MAP_LEFT_SIDE + MAP_SIZE_X   # 5760
const MAP_DOWN_SIDE   := MAP_UP_SIDE   + MAP_SIZE_Y   # 3825

# マス目サイズ（ピクセル）
const MASU_SIZE := 32

# フィールドのマス数
const FIELD_COLS := 18   # globalVariable.h: masu[12][18] の列数
const FIELD_ROWS := 12   # globalVariable.h: masu[12][18] の行数

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

# 速度0時の実速度（単位: 0.1px/frame）
const DEFAULT_KURU_SPEED  := 10

# 速度上昇・減少の単位
const KURU_SPEED_UP   := 3
const KURU_SPEED_DOWN := 4

# ロケット使用時の速度
const KURU_ROCKET_SPEED := 30


# ============================================================
# プレイヤー速度
# ============================================================

# スピードアイテム1段階あたりの上昇値（単位: 0.1px/frame）
const PLAYER_SPEED_UP      := 6

# 初期速度（単位: 0.1px/frame）
const PLAYER_DEFAULT_SPEED := 35

# スピード靴使用時の速度（単位: 0.1px/frame）
const SHOES_SPEED          := 100

# ---- 座標変換ヘルパー ----
# C++の座標（0.1px単位整数）→ Godotのfloat px
func to_godot_pos(cpp_val: int) -> float:
	return cpp_val * 0.1

# Godotのfloat px → C++の座標（0.1px単位整数）
func to_cpp_pos(godot_val: float) -> int:
	return int(godot_val * 10.0)


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
const MAX_PLAYER := 2
