# PlayerIni.gd
# playerIni.cpp の移植（セーブ・ロード・デフォルト値設定）

extends Node

const SAVE_PATH := "user://settings.json"

const DEFAULT_KEYS_SINGLE: Array[int] = [
	KEY_RIGHT, KEY_LEFT, KEY_DOWN, KEY_UP,
	KEY_SPACE, KEY_A, KEY_S, KEY_D,
]
const DEFAULT_KEYS_VS_1P: Array[int] = [
	KEY_H, KEY_F, KEY_G, KEY_T,
	KEY_C, KEY_A, KEY_S, KEY_D,
]
const DEFAULT_KEYS_VS_2P: Array[int] = [
	KEY_RIGHT, KEY_LEFT, KEY_DOWN, KEY_UP,
	KEY_BACKSLASH, KEY_L, KEY_SEMICOLON, KEY_COLON,
]

func player_ini_open() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		_load_data()
	else:
		_set_defaults()

func player_ini_close() -> void:
	_save_data()

# ============================================================
# 読み込み
# ============================================================
func _load_data() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		_set_defaults()
		return

	var text := f.get_as_text()
	f.close()

	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		_set_defaults()
		return

	var root = json.data
	if typeof(root) != TYPE_DICTIONARY:
		_set_defaults()
		return

	var data: Dictionary = root
	# 先に規定値を適用し、不足フィールドは既定値のまま残す
	_set_defaults()

	var m: Dictionary = GameData.menu
	var menu_data: Dictionary = data.get("menu", {})
	m["name"] = str(menu_data.get("name", m["name"]))
	m["stage"] = GameState.clamp_stage(int(menu_data.get("stage", m["stage"])))
	m["speed"] = int(menu_data.get("speed", m["speed"]))
	m["shot"] = int(menu_data.get("shot", m["shot"]))
	m["power"] = int(menu_data.get("power", m["power"]))
	m["kuru_speed"] = int(menu_data.get("kuru_speed", m["kuru_speed"]))
	m["kuru_dankai"] = int(menu_data.get("kuru_dankai", m["kuru_dankai"]))
	m["kuru_kankaku"] = int(menu_data.get("kuru_kankaku", m["kuru_kankaku"]))
	var menu_item_type = menu_data.get("item_type", m["item_type"])
	if typeof(menu_item_type) == TYPE_ARRAY:
		for i in range(min(3, menu_item_type.size())):
			m["item_type"][i] = int(menu_item_type[i])

	var vm: Dictionary = GameData.vs_menu
	var vs_menu_data: Dictionary = data.get("vs_menu", {})
	vm["stage"] = GameState.clamp_stage(int(vs_menu_data.get("stage", vm["stage"])))

	var vm_name = vs_menu_data.get("name", vm["name"])
	if typeof(vm_name) == TYPE_ARRAY:
		for j in range(min(2, vm_name.size())):
			vm["name"][j] = str(vm_name[j])

	var vm_player_type = vs_menu_data.get("player_type", vm["player_type"])
	if typeof(vm_player_type) == TYPE_ARRAY:
		for j in range(min(2, vm_player_type.size())):
			vm["player_type"][j] = int(vm_player_type[j])

	var vm_kuru_type = vs_menu_data.get("kuru_type", vm["kuru_type"])
	if typeof(vm_kuru_type) == TYPE_ARRAY:
		for j in range(min(2, vm_kuru_type.size())):
			vm["kuru_type"][j] = int(vm_kuru_type[j])

	var vm_item_type = vs_menu_data.get("item_type", vm["item_type"])
	if typeof(vm_item_type) == TYPE_ARRAY:
		for j in range(min(2, vm_item_type.size())):
			if typeof(vm_item_type[j]) == TYPE_ARRAY:
				for i in range(min(3, vm_item_type[j].size())):
					vm["item_type"][j][i] = int(vm_item_type[j][i])



	var vcm: Dictionary = GameData.vs_com_menu
	var vs_com_menu_data: Dictionary = data.get("vs_com_menu", {})
	vcm["stage"] = GameState.clamp_stage(int(vs_com_menu_data.get("stage", vcm["stage"])))

	var vcm_name = vs_com_menu_data.get("name", vcm["name"])
	if typeof(vcm_name) == TYPE_ARRAY:
		for j in range(min(2, vcm_name.size())):
			vcm["name"][j] = str(vcm_name[j])

	var vcm_player_type = vs_com_menu_data.get("player_type", vcm["player_type"])
	if typeof(vcm_player_type) == TYPE_ARRAY:
		for j in range(min(2, vcm_player_type.size())):
			vcm["player_type"][j] = int(vcm_player_type[j])

	var vcm_kuru_type = vs_com_menu_data.get("kuru_type", vcm["kuru_type"])
	if typeof(vcm_kuru_type) == TYPE_ARRAY:
		for j in range(min(2, vcm_kuru_type.size())):
			vcm["kuru_type"][j] = int(vcm_kuru_type[j])

	var vcm_item_type = vs_com_menu_data.get("item_type", vcm["item_type"])
	if typeof(vcm_item_type) == TYPE_ARRAY:
		for j in range(min(2, vcm_item_type.size())):
			if typeof(vcm_item_type[j]) == TYPE_ARRAY:
				for i in range(min(3, vcm_item_type[j].size())):
					vcm["item_type"][j][i] = int(vcm_item_type[j][i])


	var use_key_single = data.get("use_key_single", GameState.use_key_single)
	if typeof(use_key_single) == TYPE_ARRAY:
		for i in range(min(8, use_key_single.size())):
			GameState.use_key_single[i] = int(use_key_single[i])

	var use_key_vs_1p = data.get("use_key_vs_1p", GameState.use_key_vs_1p)
	if typeof(use_key_vs_1p) == TYPE_ARRAY:
		for i in range(min(8, use_key_vs_1p.size())):
			GameState.use_key_vs_1p[i] = int(use_key_vs_1p[i])

	var use_key_vs_2p = data.get("use_key_vs_2p", GameState.use_key_vs_2p)
	if typeof(use_key_vs_2p) == TYPE_ARRAY:
		for i in range(min(8, use_key_vs_2p.size())):
			GameState.use_key_vs_2p[i] = int(use_key_vs_2p[i])

	var online_menu_data: Dictionary = data.get("online_menu", {})
	GameState.online_menu["name"] = str(online_menu_data.get("name", GameState.online_menu["name"]))
	GameState.online_menu["ip_address"] = str(online_menu_data.get("ip_address", GameState.online_menu["ip_address"]))
	GameState.online_menu["stage"] = GameState.clamp_stage(int(online_menu_data.get("stage", GameState.online_menu["stage"])))
	GameState.online_menu["character"] = int(online_menu_data.get("character", GameState.online_menu["character"]))
	GameState.online_menu["kuru_type"] = int(online_menu_data.get("kuru_type", GameState.online_menu["kuru_type"]))
	var online_item_type = online_menu_data.get("item_type", GameState.online_menu["item_type"])
	if typeof(online_item_type) == TYPE_ARRAY:
		for i in range(min(3, online_item_type.size())):
			GameState.online_menu["item_type"][i] = int(online_item_type[i])
	var audio_data: Dictionary = data.get("audio", {})
	GameState.bgm_volume_percent = clampf(float(audio_data.get("bgm_volume_percent", GameState.bgm_volume_percent)), 0.0, 100.0)
	GameState.se_volume_percent = clampf(float(audio_data.get("se_volume_percent", GameState.se_volume_percent)), 0.0, 100.0)

# ============================================================
# 書き込み
# ============================================================
func _save_data() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("PlayerIni: セーブファイルを開けませんでした")
		return

	var data := {
		"menu": {
			"name": GameData.menu["name"],
			"stage": GameState.clamp_stage(GameData.menu["stage"]),
			"speed": GameData.menu["speed"],
			"shot": GameData.menu["shot"],
			"power": GameData.menu["power"],
			"kuru_speed": GameData.menu["kuru_speed"],
			"kuru_dankai": GameData.menu["kuru_dankai"],
			"kuru_kankaku": GameData.menu["kuru_kankaku"],
			"item_type": GameData.menu["item_type"].duplicate(),
		},
		"vs_menu": {
			"name": GameData.vs_menu["name"].duplicate(),
			"stage": GameState.clamp_stage(GameData.vs_menu["stage"]),
			"player_type": GameData.vs_menu["player_type"].duplicate(),
			"kuru_type": GameData.vs_menu["kuru_type"].duplicate(),
			"item_type": GameData.vs_menu["item_type"].duplicate(true),
		},
		"vs_com_menu": {
			"name": GameData.vs_com_menu["name"].duplicate(),
			"stage": GameState.clamp_stage(GameData.vs_com_menu["stage"]),
			"player_type": GameData.vs_com_menu["player_type"].duplicate(),
			"kuru_type": GameData.vs_com_menu["kuru_type"].duplicate(),
			"item_type": GameData.vs_com_menu["item_type"].duplicate(true),
		},
		"use_key_single": GameState.use_key_single.duplicate(),
		"use_key_vs_1p": GameState.use_key_vs_1p.duplicate(),
		"use_key_vs_2p": GameState.use_key_vs_2p.duplicate(),
		"online_menu": {
			"name": GameState.online_menu["name"],
			"ip_address": GameState.online_menu["ip_address"],
			"stage": GameState.clamp_stage(GameState.online_menu["stage"]),
			"character": GameState.online_menu["character"],
			"kuru_type": GameState.online_menu["kuru_type"],
			"item_type": GameState.online_menu["item_type"].duplicate(),
		},
		"audio": {
			"bgm_volume_percent": GameState.bgm_volume_percent,
			"se_volume_percent": GameState.se_volume_percent,
		},
	}
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

# ============================================================
# デフォルト値
# ============================================================
func _set_defaults() -> void:
	var m: Dictionary = GameData.menu
	m["name"]         = "1P"
	m["stage"]        = 0
	m["speed"]        = 6
	m["shot"]         = 5
	m["power"]        = 5
	m["kuru_speed"]   = 0
	m["kuru_dankai"]  = 5
	m["kuru_kankaku"] = 12
	for i in range(3):
		m["item_type"][i] = Enums.ItemType.NO_ITEM

	var vm: Dictionary = GameData.vs_menu
	for j in range(2):
		vm["name"][j]          = "1P" if j == 0 else "2P"
		vm["player_type"][j]   = Enums.PlayerType.YAMI
		vm["kuru_type"][j]     = Enums.KuruType.KIHON
		for i in range(3):
			vm["item_type"][j][i] = Enums.ItemType.NO_ITEM
	vm["stage"] = 0

	var vcm: Dictionary = GameData.vs_com_menu
	for j in range(2):
		vcm["name"][j]          = "1P" if j == 0 else "COM"
		vcm["player_type"][j]   = Enums.PlayerType.YAMI
		vcm["kuru_type"][j]     = Enums.KuruType.KIHON
		for i in range(3):
			vcm["item_type"][j][i] = Enums.ItemType.NO_ITEM
	vcm["stage"] = 0

	for i in range(8):
		GameState.use_key_single[i] = DEFAULT_KEYS_SINGLE[i]
		GameState.use_key_vs_1p[i]  = DEFAULT_KEYS_VS_1P[i]
		GameState.use_key_vs_2p[i]  = DEFAULT_KEYS_VS_2P[i]

	# online_menu のデフォルト（GameState.gdで設定済みだが念のため）
	GameState.online_menu["name"]         = "1P"
	GameState.online_menu["ip_address"]   = "127.0.0.1"
	GameState.online_menu["stage"]        = 0
	GameState.online_menu["character"]    = 0
	GameState.online_menu["kuru_type"]    = 0
	for i in range(3):
		GameState.online_menu["item_type"][i] = 0
	GameState.bgm_volume_percent = 100.0
	GameState.se_volume_percent = 100.0
