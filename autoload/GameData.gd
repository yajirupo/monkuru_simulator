# GameData.gd
# globalVariable.h の移植（メニューデータ・設定データ部分）
# Autoload 名: GameData

extends Node


func make_menu() -> Dictionary:
	return {
		"name":         "",
		"stage":        0,
		"power":        1,
		"shot":         1,
		"speed":        1,
		"kuru_speed":   0,
		"kuru_dankai":  5,
		"kuru_kankaku": 12,
		"item_type":    [
			Enums.ItemType.NO_ITEM,
			Enums.ItemType.NO_ITEM,
			Enums.ItemType.NO_ITEM,
		],
		"cursor":       0,
	}

var menu:     Dictionary = {}
var menu_tmp: Dictionary = {}

func make_vs_menu() -> Dictionary:
	return {
		"name":          ["", ""],
		"stage":         0,
		"player_type":   [
			Enums.PlayerType.YAMI,
			Enums.PlayerType.YAMI,
		],
		"kuru_type":     [
			Enums.KuruType.KIHON,
			Enums.KuruType.KIHON,
		],
		"item_type":     [
			[Enums.ItemType.NO_ITEM, Enums.ItemType.NO_ITEM, Enums.ItemType.NO_ITEM],
			[Enums.ItemType.NO_ITEM, Enums.ItemType.NO_ITEM, Enums.ItemType.NO_ITEM],
		],
		"cursor":        0,
	}

var vs_menu:      Dictionary = {}
var vs_menu_tmp:  Dictionary = {}
var vs_com_menu:  Dictionary = {}
var vs_com_menu_tmp: Dictionary = {}

func make_replay_menu() -> Dictionary:
	return {
		"cursor_x": 0,
		"cursor_y": 0,
		"num":      0,
	}

var replay_menu: Dictionary = {}

func _ready() -> void:
	menu            = make_menu()
	menu_tmp        = make_menu()
	vs_menu         = make_vs_menu()
	vs_menu_tmp     = make_vs_menu()
	vs_com_menu     = make_vs_menu()
	vs_com_menu_tmp = make_vs_menu()
	replay_menu     = make_replay_menu()

func copy_menu(src: Dictionary) -> Dictionary:
	return src.duplicate(true)

func make_player_data() -> Dictionary:
	return {
		"masu_x": 0, "masu_y": 0,
		"x": 0, "y": 0,
		"speed": Constants.PLAYER_DEFAULT_SPEED,
		"muki": Enums.Muki.DOWN,
		"item_speed": Constants.PLAYER_DEFAULT_ITEM_SPEED,
		"item_shot":  Constants.PLAYER_DEFAULT_ITEM_SHOT,
		"item_power": Constants.PLAYER_DEFAULT_ITEM_POWER,
		"max_speed":  Constants.PLAYER_DEFAULT_ITEM_SPEED,
		"max_shot":   Constants.PLAYER_DEFAULT_ITEM_SHOT,
		"max_power":  Constants.PLAYER_DEFAULT_ITEM_POWER,
		"shot_count": 0, "shot_kuru": 0,
		"kuru_speed": 0, "kuru_dankai": 5, "kuru_kankaku": 12,
		"life_flag": true,
		"kuru_type": Enums.KuruType.KIHON,
		"cr_item": [Enums.ItemType.NO_ITEM, Enums.ItemType.NO_ITEM, Enums.ItemType.NO_ITEM],
		"cr_item_use": Enums.ItemType.NO_ITEM,
		"cr_item_count": 0,
		"name": "player", "name_width": 0,
		"joutai": Enums.PlayerJoutaiType.STAND_DOWN,
		"joutai_count": 0,
		"character": Enums.PlayerType.YAMI,
	}

func active_vs_menu() -> Dictionary:
	if GameState.joutai_flag in [Enums.JoutaiType.VS_COM_MENU, Enums.JoutaiType.VS_COM_GAME, Enums.JoutaiType.VS_COM_REPLAY]:
		return vs_com_menu
	return vs_menu

func active_vs_menu_tmp() -> Dictionary:
	if GameState.joutai_flag in [Enums.JoutaiType.VS_COM_MENU, Enums.JoutaiType.VS_COM_GAME, Enums.JoutaiType.VS_COM_REPLAY]:
		return vs_com_menu_tmp
	if GameState.vs_replay_return_state == Enums.JoutaiType.VS_COM_MENU:
		return vs_com_menu_tmp
	return vs_menu_tmp
