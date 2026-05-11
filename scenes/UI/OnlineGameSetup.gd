# OnlineGameSetup.gd
# ゲーム開始時のプレイヤーデータ構築
# OnlineMenu.gd の _on_game_start から呼び出される

class_name OnlineGameSetup

const ITEM_MAX := 5   # OnlineMenu.gd と同値

# ゲーム開始時に GameState.player を構築するエントリポイント
static func setup() -> void:
	GameState.player.clear()
	for i in range(Constants.MAX_PLAYER):
		GameState.player.append(GameData.make_player_data())

	var my_idx:  int = NetworkManager.my_player_index()
	var my      := _collect_my_params()
	var peer    := _collect_peer_params(my)

	_assign_base_info(my_idx, my, peer)
	_apply_my_stats(my_idx, my)
	_apply_peer_stats(my_idx, my)

# ── パラメータ収集 ──────────────────────────────────────────

static func _collect_my_params() -> Dictionary:
	return {
		"name":          GameState.online_menu.get("name", "Player") as String,
		"character":     GameState.online_menu["character"]     as int,
		"kuru_type":     GameState.online_menu["kuru_type"]     as int,
		"item_type":     GameState.online_menu["item_type"],
	}

static func _collect_peer_params(my: Dictionary) -> Dictionary:
	var rs: Dictionary = NetworkManager.remote_stats
	return {
		"name":          rs.get("name",          "Player")             as String,
		"character":     int(rs.get("character",     my["character"])),
		"kuru_type":     int(rs.get("kuru_type",     my["kuru_type"])),
	}

# ── データ書き込み ──────────────────────────────────────────

# 名前・キャラ・くる種別を両プレイヤーに割り当てる
static func _assign_base_info(my_idx: int, my: Dictionary, peer: Dictionary) -> void:
	for j in range(2):
		var pj: Dictionary = GameState.player[j]
		pj["name"]          = my["name"]          if j == my_idx else peer["name"]
		pj["character"]     = my["character"]     if j == my_idx else peer["character"]
		pj["kuru_type"]     = my["kuru_type"]     if j == my_idx else peer["kuru_type"]

# 自プレイヤーのステータス・アイテムを設定する
static func _apply_my_stats(my_idx: int, my: Dictionary) -> void:
	var pm:   Dictionary = GameState.player[my_idx]
	var pdef: Dictionary = Constants.get_character_max_stats(my["character"])
	var kdef: Dictionary = Constants.get_kuru_def(my["kuru_type"])

	pm["max_speed"] = pdef["speed"] + kdef["speed_up"]
	pm["max_shot"]  = pdef["shot"]  + kdef["shot_up"]
	pm["max_power"] = pdef["power"] + kdef["power_up"]

	pm["item_speed"] = pm["max_speed"]
	pm["item_shot"]  = pm["max_shot"]
	pm["item_power"] = pm["max_power"]

	pm["speed"]        = (Constants.PLAYER_DEFAULT_SPEED + pm["item_speed"] * Constants.PLAYER_SPEED_UP) / 2
	pm["kuru_speed"]   = Constants.kuru_speed_stat_to_move_speed(int(kdef["speed"]))
	pm["kuru_dankai"]  = kdef["dankai"]
	pm["kuru_kankaku"] = kdef["kankaku"]

	for i in range(3):
		pm["cr_item"][i] = clampi(my["item_type"][i], 0, ITEM_MAX - 1)

# 相手プレイヤーのステータス・アイテムを設定する
# remote_stats が空の場合は自分のデータをそのままコピーする
static func _apply_peer_stats(my_idx: int, my: Dictionary) -> void:
	var remote_idx: int      = NetworkManager.remote_player_index()
	var pr:         Dictionary = GameState.player[remote_idx]
	var pm:         Dictionary = GameState.player[my_idx]
	var rs:         Dictionary = NetworkManager.remote_stats
	var kdef:       Dictionary = Constants.get_kuru_def(my["kuru_type"])

	# 最大値・アイテム値は自分の設定をそのまま使用（対称ルール）
	pr["max_speed"]  = pm["max_speed"]
	pr["max_shot"]   = pm["max_shot"]
	pr["max_power"]  = pm["max_power"]
	pr["item_speed"] = pm["item_speed"]
	pr["item_shot"]  = pm["item_shot"]
	pr["item_power"] = pm["item_power"]
	pr["speed"]      = pm["speed"]

	if rs.is_empty():
		# 相手のデータが未受信の場合は自分と同じ設定を使用
		pr["kuru_speed"]   = Constants.kuru_speed_stat_to_move_speed(int(kdef["speed"]))
		pr["kuru_dankai"]  = kdef["dankai"]
		pr["kuru_kankaku"] = kdef["kankaku"]
		for i in range(3):
			pr["cr_item"][i] = pm["cr_item"][i]
	else:
		pr["character"]    = int(rs.get("character", pr["character"]))
		pr["kuru_speed"]   = rs["kuru_speed"]
		pr["kuru_dankai"]  = rs["kuru_dankai"]
		pr["kuru_kankaku"] = rs["kuru_kankaku"]
		for i in range(3):
			pr["cr_item"][i] = clampi(rs["item_type"][i], 0, ITEM_MAX - 1)
