# Player.gd
# player.cpp の移植
# ノード構成:
#   Player (CharacterBody2D) ← このスクリプト
#   ├── AnimationPlayer
#   ├── Sprite2D
#   └── NameLabel (Label)
#
# GameState.player[num] の辞書を参照・更新する。
# 辞書のキーは struct.h の player_t メンバーをスネークケース化したもの。
# 描画処理は PlayerRenderer に委譲する。

extends CharacterBody2D

# くるシーンはプリロードでキャッシュ（_spawn_kuru のたびに load() しない）
const KURU_SCENE: PackedScene = preload("res://scenes/Kuru/Kuru.tscn")

# ============================================================
# プレイヤーデータの辞書を生成するファクトリ関数
# struct player_t の移植
# ============================================================
static func make_player_data() -> Dictionary:
	return {
		"masu_x":        0,
		"masu_y":        0,
		"x":             0,     # 単位: 0.1px（C++互換）
		"y":             0,
		"speed":         Constants.PLAYER_DEFAULT_SPEED,
		"muki":          Enums.Muki.DOWN,
		"item_speed":    Constants.PLAYER_DEFAULT_ITEM_SPEED,
		"item_shot":     Constants.PLAYER_DEFAULT_ITEM_SHOT,
		"item_power":    Constants.PLAYER_DEFAULT_ITEM_POWER,
		"max_speed":     Constants.PLAYER_DEFAULT_ITEM_SPEED,
		"max_shot":      Constants.PLAYER_DEFAULT_ITEM_SHOT,
		"max_power":     Constants.PLAYER_DEFAULT_ITEM_POWER,
		"shot_count":    0,
		"shot_kuru":     0,
		"kuru_speed":    0,
		"kuru_dankai":   5,
		"kuru_kankaku":  12,
		"life_flag":     true,
		"kuru_type":     Enums.KuruType.KIHON,
		"cr_item":       [Enums.ItemType.NO_ITEM, Enums.ItemType.NO_ITEM, Enums.ItemType.NO_ITEM],
		"cr_item_use":   Enums.ItemType.NO_ITEM,
		"cr_item_count": 0,
		"name":          "player",
		"name_width":    0,
		"joutai":        Enums.PlayerJoutaiType.STAND_DOWN,
		"joutai_count":  0,
		"just_died":     false,
		"character":     Enums.PlayerType.YAMI,
	}


# ============================================================
# ノード参照
# ============================================================
@onready var anim:          AnimationPlayer = $AnimationPlayer
@onready var name_label:    Label           = $NameLabel
@onready var effect_sprite: Sprite2D        = $EffectSprite2D

# このノードが何番目のプレイヤーか（0 or 1）
@export var player_num: int = 0

# 省略形：GameState.player[player_num] への参照
var p: Dictionary:
	get: return GameState.player[player_num]

# 描画担当
var _renderer: PlayerRenderer


# ============================================================
# Godot ライフサイクル
# ============================================================
func _ready() -> void:
	# 描画クラスを初期化
	_renderer = PlayerRenderer.new()
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	_renderer.setup(player_num, sprite, name_label, effect_sprite)

	# オンライン: 相手プレイヤーの死亡通知を受け取る
	NetworkManager.remote_player_died.connect(_on_remote_player_died)

func _process(_delta: float) -> void:
	# player_calc() は Main.gd から呼ばれる。ここでは描画のみ。
	if GameState.player.size() > player_num:
		_sync_position()
		_renderer.update()


# ============================================================
# iniPlayer() の移植
# ゲーム開始時に呼ぶ
# ============================================================
func ini_player() -> void:
	var is_replay := (
		GameState.joutai_flag == Enums.JoutaiType.SINGLE_REPLAY or
		GameState.joutai_flag == Enums.JoutaiType.VS_REPLAY or
		GameState.joutai_flag == Enums.JoutaiType.VS_COM_REPLAY or
		GameState.joutai_flag == Enums.JoutaiType.ONLINE_REPLAY
	)
	var num := 2 if (
		GameState.joutai_flag == Enums.JoutaiType.VS_GAME or
		GameState.joutai_flag == Enums.JoutaiType.VS_COM_GAME or
		GameState.joutai_flag == Enums.JoutaiType.VS_REPLAY or
		GameState.joutai_flag == Enums.JoutaiType.VS_COM_REPLAY or
		GameState.joutai_flag == Enums.JoutaiType.ONLINE_GAME or
		GameState.joutai_flag == Enums.JoutaiType.ONLINE_REPLAY
	) else 1

	var is_online := GameState.joutai_flag == Enums.JoutaiType.ONLINE_GAME
	if not is_replay and not is_online:
		if num == 1:
			var d: Dictionary = GameData.menu
			p["name"]          = d["name"]
			p["item_speed"]    = d["speed"]
			p["max_speed"]     = d["speed"]
			p["item_shot"]     = d["shot"]
			p["max_shot"]      = d["shot"]
			p["item_power"]    = d["power"]
			p["max_power"]     = d["power"]
			p["kuru_speed"]    = d["kuru_speed"]
			p["kuru_dankai"]   = d["kuru_dankai"]
			p["kuru_kankaku"]  = d["kuru_kankaku"]
			p["speed"]         = Constants.PLAYER_DEFAULT_SPEED + p["item_speed"] * Constants.PLAYER_SPEED_UP
			for i in range(3):
				p["cr_item"][i] = d["item_type"][i]
		else:
			for j in range(2):
				var pj: Dictionary = GameState.player[j]
				if is_online:
					pass  # character/kuru_type は GameState.player[j] に設定済み
				else:
					var vm: Dictionary = GameData.vs_com_menu if GameState.joutai_flag == Enums.JoutaiType.VS_COM_GAME else GameData.vs_menu
					pj["kuru_type"]     = vm["kuru_type"][j]
					pj["character"]     = vm["player_type"][j]
					for i in range(3):
						pj["cr_item"][i] = vm["item_type"][j][i]
					pj["name"]          = vm["name"][j]

	# 共通初期化
	var stage := GameState.clamp_stage(GameState.current_stage)
	for i in range(num):
		var pi: Dictionary = GameState.player[i]
		var start_cell := GameState.get_stage_player_start_cell(stage, i)
		pi["masu_x"]      = start_cell.x
		pi["masu_y"]      = start_cell.y
		pi["x"]           = start_cell.x * 320
		pi["y"]           = start_cell.y * 320
		pi["muki"]        = Enums.Muki.DOWN
		pi["shot_count"]  = 0
		pi["shot_kuru"]   = 0
		pi["life_flag"]   = true

		if num == 1:
			pi["kuru_type"]  = Constants.get_practice_kuru_type()
			pi["character"]  = Enums.PlayerType.YAMI
		elif num == 2:
			var kt: int = pi["kuru_type"]
			var ch: int = pi["character"]
			var max_stats: Dictionary = Constants.get_character_max_stats(ch)
			var kuru_def:  Dictionary = Constants.get_kuru_def(kt)
			pi["max_speed"] = int(max_stats["speed"]) + int(kuru_def["speed_up"])
			pi["max_shot"]  = int(max_stats["shot"])  + int(kuru_def["shot_up"])
			pi["max_power"] = int(max_stats["power"]) + int(kuru_def["power_up"])

			pi["item_speed"] = pi["max_speed"]
			pi["item_shot"]  = pi["max_shot"]
			pi["item_power"] = pi["max_power"]

			pi["speed"]        = Constants.PLAYER_DEFAULT_SPEED + pi["item_speed"] * Constants.PLAYER_SPEED_UP
			pi["kuru_speed"]   = int(kuru_def["speed"])
			pi["kuru_dankai"]  = int(kuru_def["dankai"])
			pi["kuru_kankaku"] = int(kuru_def["kankaku"])

		pi["cr_item_use"]   = Enums.ItemType.NO_ITEM
		pi["cr_item_count"] = 0
		pi["joutai"]        = pi["muki"]  # STAND_DOWN = Muki.DOWN
		pi["joutai_count"]  = 0

	_sync_position()
	_renderer.reset()


# ============================================================
# playerCalc() の移植
# 毎フレームの更新処理（Main.gd から呼ぶ）
# ============================================================
func player_calc() -> void:
	var num := _get_active_player_count()

	var my_online_idx := -1
	if GameState.joutai_flag == Enums.JoutaiType.ONLINE_GAME:
		my_online_idx = NetworkManager.my_player_index()
	elif GameState.joutai_flag == Enums.JoutaiType.ONLINE_REPLAY:
		my_online_idx = GameState.online_replay_local_player_idx

	for i in range(num):
		var pi: Dictionary = GameState.player[i]
		if pi["life_flag"]:
			var shot_flag := _player_shot(i)
			_player_move(shot_flag, i)
			# ONLINE_GAME: 相手の処理はすべてRPC任せ（アイテム・被弾スキップ）
			# ONLINE_REPLAY: アイテムは両プレイヤーで再生。
			#   被弾はローカル側のみbomb検出し、リモート側はstate_eventで再現する。
			var _skip_remote_game   := GameState.joutai_flag == Enums.JoutaiType.ONLINE_GAME   and i != my_online_idx
			var _skip_remote_replay := GameState.joutai_flag == Enums.JoutaiType.ONLINE_REPLAY and i != my_online_idx
			if not _skip_remote_game:
				_player_cr_item(i)
			if not _skip_remote_game and not _skip_remote_replay:
				_player_hit_bomb(i)
				# 相手がこちらのくるに衝突したかの判定は各自の端末に任せる
				_player_hit_kuru(i)
		else:
			# 死亡アニメーション終了後に復活
			if pi["joutai"] == Enums.PlayerJoutaiType.DEATH and \
			   pi["joutai_count"] == 20 * Constants.REFRESH_PICTURE_TIME - 1:
				pi["life_flag"]    = true
				pi["joutai"]       = pi["muki"]
				pi["joutai_count"] = 0

		# カウンタ更新
		if pi["shot_count"] > 0:
			pi["shot_count"] -= 1

		# ONLINE_GAME中のリモートのみスキップ。ONLINE_REPLAYはカウンタを自前で管理する。
		var is_remote_online := GameState.joutai_flag == Enums.JoutaiType.ONLINE_GAME and i != my_online_idx
		if pi["cr_item_count"] > 0:
			if not is_remote_online:
				pi["cr_item_count"] -= 1
		else:
			if not is_remote_online:
				# 透明マント効果切れ時に効果音（自分のみ）
				if pi["cr_item_use"] == Enums.ItemType.INVISIBLE:
					SoundManager.play_cr_invisible_end()
				pi["cr_item_use"] = Enums.ItemType.NO_ITEM

		pi["joutai_count"] += 1


# ============================================================
# playerMove() の移植
# ============================================================
func _player_move(kuru_shot_flag: bool, num: int) -> void:
	var pi: Dictionary = GameState.player[num]
	var move: int

	if pi["cr_item_use"] != Enums.ItemType.SHOES:
		move = pi["speed"] / 2
	else:
		@warning_ignore("integer_division")
		move = Constants.SHOES_SPEED / 2

	if kuru_shot_flag:
		move = 0

	# 最も早く押されたキー（押下フレーム数が最小、かつ>0）を探す
	var min_key      := -1
	var min_key_time := 65535
	var use_key: Array = GameState.use_key[num]

	for i in range(4):
		if use_key[i] > 0 and use_key[i] < min_key_time:
			min_key_time = use_key[i]
			min_key      = i

	# 方向入力処理
	match min_key:
		0:  # RIGHT
			pi["muki"] = Enums.Muki.RIGHT
			if use_key[0] < Constants.WAIT:
				_set_joutai(pi, Enums.PlayerJoutaiType.STAND_RIGHT)
			else:
				var next_x: int = mini(pi["x"] + move, Constants.MAP_SIZE_X)
				@warning_ignore("integer_division")
				var front_x: int = (next_x + 319) / 320
				var cell_top: int = pi["y"] / 320
				var cell_bottom: int = (pi["y"] + 319) / 320
				var top_hard: bool = _is_hard_block_cell(front_x, cell_top)
				var bottom_hard: bool = _is_hard_block_cell(front_x, cell_bottom)

				if top_hard or bottom_hard:
					if top_hard and bottom_hard:
						pi["x"] = front_x * 320 - 320
					elif top_hard:
						var block_bottom_edge: int = cell_top * 320 + 319
						var overlap: int = block_bottom_edge - pi["y"] + 1
						if overlap > Constants.PLAYER_CORNER_SLIDE_THRESHOLD:
							pi["x"] = front_x * 320 - 320
						else:
							pi["x"] = front_x * 320 - 320
							pi["y"] = mini(pi["y"] + move, Constants.MAP_SIZE_Y)
					else: # bottom_hard
						var block_top_edge: int = cell_bottom * 320
						var overlap: int = (pi["y"] + 319) - block_top_edge + 1
						if overlap > Constants.PLAYER_CORNER_SLIDE_THRESHOLD:
							pi["x"] = front_x * 320 - 320
						else:
							pi["x"] = front_x * 320 - 320
							pi["y"] = maxi(pi["y"] - move, 0)
					_set_joutai(pi, Enums.PlayerJoutaiType.RUN_RIGHT)
				else:
					pi["x"] = next_x
					_set_joutai(pi, Enums.PlayerJoutaiType.RUN_RIGHT)
		1:  # LEFT
			pi["muki"] = Enums.Muki.LEFT
			if use_key[1] < Constants.WAIT:
				_set_joutai(pi, Enums.PlayerJoutaiType.STAND_LEFT)
			else:
				var next_x: int = maxi(pi["x"] - move, 0)
				@warning_ignore("integer_division")
				var front_x: int = next_x / 320
				var cell_top: int = pi["y"] / 320
				var cell_bottom: int = (pi["y"] + 319) / 320
				var top_hard: bool = _is_hard_block_cell(front_x, cell_top)
				var bottom_hard: bool = _is_hard_block_cell(front_x, cell_bottom)

				if top_hard or bottom_hard:
					if top_hard and bottom_hard:
						pi["x"] = (front_x + 1) * 320
					elif top_hard:
						var block_bottom_edge: int = cell_top * 320 + 319
						var overlap: int = block_bottom_edge - pi["y"] + 1
						if overlap > Constants.PLAYER_CORNER_SLIDE_THRESHOLD:
							pi["x"] = (front_x + 1) * 320
						else:
							pi["x"] = (front_x + 1) * 320
							pi["y"] = mini(pi["y"] + move, Constants.MAP_SIZE_Y)
					else: # bottom_hard
						var block_top_edge: int = cell_bottom * 320
						var overlap: int = (pi["y"] + 319) - block_top_edge + 1
						if overlap > Constants.PLAYER_CORNER_SLIDE_THRESHOLD:
							pi["x"] = (front_x + 1) * 320
						else:
							pi["x"] = (front_x + 1) * 320
							pi["y"] = maxi(pi["y"] - move, 0)
					_set_joutai(pi, Enums.PlayerJoutaiType.RUN_LEFT)
				else:
					pi["x"] = next_x
					_set_joutai(pi, Enums.PlayerJoutaiType.RUN_LEFT)
		2:  # DOWN
			pi["muki"] = Enums.Muki.DOWN
			if use_key[2] < Constants.WAIT:
				_set_joutai(pi, Enums.PlayerJoutaiType.STAND_DOWN)
			else:
				var next_y: int = mini(pi["y"] + move, Constants.MAP_SIZE_Y)
				@warning_ignore("integer_division")
				var front_y: int = (next_y + 319) / 320
				var cell_left: int = pi["x"] / 320
				var cell_right: int = (pi["x"] + 319) / 320
				var left_hard: bool = _is_hard_block_cell(cell_left, front_y)
				var right_hard: bool = _is_hard_block_cell(cell_right, front_y)

				if left_hard or right_hard:
					if left_hard and right_hard:
						pi["y"] = front_y * 320 - 320
					elif left_hard:
						var block_right_edge: int = cell_left * 320 + 319
						var overlap: int = block_right_edge - pi["x"] + 1
						if overlap > Constants.PLAYER_CORNER_SLIDE_THRESHOLD:
							pi["y"] = front_y * 320 - 320
						else:
							pi["y"] = front_y * 320 - 320
							pi["x"] = mini(pi["x"] + move, Constants.MAP_SIZE_X)
					else: # right_hard
						var block_left_edge: int = cell_right * 320
						var overlap: int = (pi["x"] + 319) - block_left_edge + 1
						if overlap > Constants.PLAYER_CORNER_SLIDE_THRESHOLD:
							pi["y"] = front_y * 320 - 320
						else:
							pi["y"] = front_y * 320 - 320
							pi["x"] = maxi(pi["x"] - move, 0)
					_set_joutai(pi, Enums.PlayerJoutaiType.RUN_DOWN)
				else:
					pi["y"] = next_y
					_set_joutai(pi, Enums.PlayerJoutaiType.RUN_DOWN)
		3:  # UP
			pi["muki"] = Enums.Muki.UP
			if use_key[3] < Constants.WAIT:
				_set_joutai(pi, Enums.PlayerJoutaiType.STAND_UP)
			else:
				var next_y: int = maxi(pi["y"] - move, 0)
				@warning_ignore("integer_division")
				var front_y: int = next_y / 320
				var cell_left: int = pi["x"] / 320
				var cell_right: int = (pi["x"] + 319) / 320
				var left_hard: bool = _is_hard_block_cell(cell_left, front_y)
				var right_hard: bool = _is_hard_block_cell(cell_right, front_y)

				if left_hard or right_hard:
					if left_hard and right_hard:
						pi["y"] = (front_y + 1) * 320
					elif left_hard:
						var block_right_edge: int = cell_left * 320 + 319
						var overlap: int = block_right_edge - pi["x"] + 1
						if overlap > Constants.PLAYER_CORNER_SLIDE_THRESHOLD:
							pi["y"] = (front_y + 1) * 320
						else:
							pi["y"] = (front_y + 1) * 320
							pi["x"] = mini(pi["x"] + move, Constants.MAP_SIZE_X)
					else: # right_hard
						var block_left_edge: int = cell_right * 320
						var overlap: int = (pi["x"] + 319) - block_left_edge + 1
						if overlap > Constants.PLAYER_CORNER_SLIDE_THRESHOLD:
							pi["y"] = (front_y + 1) * 320
						else:
							pi["y"] = (front_y + 1) * 320
							pi["x"] = maxi(pi["x"] - move, 0)
					_set_joutai(pi, Enums.PlayerJoutaiType.RUN_UP)
				else:
					pi["y"] = next_y
					_set_joutai(pi, Enums.PlayerJoutaiType.RUN_UP)
		-1:  # キー未入力
			_set_joutai(pi, pi["muki"])  # Muki と STAND_* が対応

	# マス座標を更新（四捨五入相当）
	pi["masu_x"] = (pi["x"] + 160) / 320
	pi["masu_y"] = (pi["y"] + 160) / 320

	if num == player_num:
		_sync_position()


# ============================================================
# playerShot() の移植
# ============================================================
func _player_shot(num: int) -> bool:
	var pi: Dictionary  = GameState.player[num]
	var use_key: Array  = GameState.use_key[num]

	var can_shot: bool = (
		use_key[4] == 1
		and pi["shot_count"] == 0
		and (
			(pi["cr_item_use"] != Enums.ItemType.ROCKET
			 and pi["cr_item_use"] != Enums.ItemType.BROTHER
			 and pi["shot_kuru"] < pi["item_shot"])
			or (pi["cr_item_use"] == Enums.ItemType.BROTHER and pi["shot_kuru"] < 11)
			or (pi["cr_item_use"] == Enums.ItemType.ROCKET  and pi["shot_kuru"] < 6)
		)
	)

	if not can_shot:
		return false

	SoundManager.play_shot(pi["character"])
	pi["shot_count"] = pi["kuru_kankaku"]

	if pi["cr_item_use"] != Enums.ItemType.BROTHER:
		_spawn_kuru(pi, num, pi["muki"])
		pi["shot_kuru"] += 1
	else:
		# くる兄弟：左右または上下に2発
		var dirs: Array
		match pi["muki"]:
			Enums.Muki.RIGHT, Enums.Muki.LEFT: dirs = [Enums.Muki.DOWN,  Enums.Muki.UP]
			Enums.Muki.DOWN,  Enums.Muki.UP:   dirs = [Enums.Muki.RIGHT, Enums.Muki.LEFT]
			_:                                  dirs = [Enums.Muki.DOWN,  Enums.Muki.UP]
		for d in dirs:
			_spawn_kuru(pi, num, d, true)
			pi["shot_kuru"] += 1

	return true


## くるノードを生成してシーンに追加する
func _spawn_kuru(pi: Dictionary, num: int, move_muki: int, is_brother: bool = false) -> void:
	# オンライン時: 相手プレイヤーのくるは RPC で生成されるのでスキップ
	if GameState.joutai_flag == Enums.JoutaiType.ONLINE_GAME:
		if num != NetworkManager.my_player_index():
			return

	var kuru_node = KURU_SCENE.instantiate()
	kuru_node.init_kuru(pi, num, move_muki, is_brother)
	var current_scene := get_tree().current_scene
	var container := current_scene.get_node_or_null("KuruContainer") if current_scene else null
	if container == null:
		return
	container.add_child(kuru_node)

	# オンライン時: 自分のくる射出を相手に通知
	if GameState.joutai_flag == Enums.JoutaiType.ONLINE_GAME:
		NetworkManager.send_kuru_spawn(
			kuru_node.data["x"],
			kuru_node.data["y"],
			kuru_node.data["muki"],
			kuru_node.data["move_muki"],
			kuru_node.data["speed"],
			kuru_node.data["count"],
			kuru_node.data["power"],
			num,
			kuru_node.data["kuru_type"]
		)


# ============================================================
# playerHitBomb() の移植
# ============================================================
func _player_hit_bomb(num: int) -> void:
	var pi: Dictionary = GameState.player[num]
	var bomb_container := get_tree().current_scene.get_node_or_null("BombContainer")
	if bomb_container == null:
		return

	for bomb_node in bomb_container.get_children():
		var b: Dictionary = bomb_node.data
		var cnt: int = b["count"]

		# 爆風中心
		if cnt >= 0 and cnt <= Constants.BOMB_SPREAD_TIME:
			if pi["masu_x"] == b["masu_x"] and pi["masu_y"] == b["masu_y"]:
				_kill_player(num)
				return

		# 火力分の爆風
		for i in range(1, b["power"] + 1):
			if cnt >= i * Constants.BOMB_SPREAD_TIME and cnt <= (i + 1) * Constants.BOMB_SPREAD_TIME:
				var mx: int = pi["masu_x"]
				var my: int = pi["masu_y"]
				var bx: int = b["masu_x"]
				var by: int = b["masu_y"]
				if (
					(mx == bx + i and my == by and not _is_blast_blocked(bx, by, 1, 0, i)) or
					(mx == bx - i and my == by and not _is_blast_blocked(bx, by, -1, 0, i)) or
					(mx == bx and my == by + i and not _is_blast_blocked(bx, by, 0, 1, i)) or
					(mx == bx and my == by - i and not _is_blast_blocked(bx, by, 0, -1, i))
				):
					_kill_player(num)
					return


func _kill_player(num: int) -> void:
	var pi: Dictionary = GameState.player[num]
	var is_practice_mode := GameState.joutai_flag == Enums.JoutaiType.SINGLE_GAME
	SoundManager.play_death(int(pi.get("character", 0)), is_practice_mode)
	pi["life_flag"]    = false
	pi["joutai_count"] = 0
	pi["joutai"]       = Enums.PlayerJoutaiType.DEATH
	if GameState.joutai_flag == Enums.JoutaiType.ONLINE_GAME:
		NetworkManager.send_death_event(num)
	_update_chat(num)

func _update_chat(player_num_idx: int) -> void:
	var pi: Dictionary = GameState.player[player_num_idx]
	var line: int = 0
	if GameState.chat_str[0] != "":
		if GameState.chat_str[1] != "":
			line = 2
			if GameState.chat_str[2] != "":
				GameState.chat_str[0]   = GameState.chat_str[1]
				GameState.chat_str[1]   = GameState.chat_str[2]
				GameState.chat_color[0] = GameState.chat_color[1]
				GameState.chat_color[1] = GameState.chat_color[2]
		else:
			line = 1
	var c: int = GameState.count
	@warning_ignore("integer_division")
	var minutes: int = c / 3600
	@warning_ignore("integer_division")
	var seconds: int = (c % 3600) / 60
	var frames:  int = c % 60
	var csec:    int = frames + int(frames * 2 / 3.0)
	GameState.chat_str[line]   = "[被弾] %s (%d分%02d秒%02d)" % [pi["name"], minutes, seconds, csec]
	GameState.chat_color[line] = Color.BLACK


# ============================================================
# playerHitKuru() の移植
# ============================================================
func _player_hit_kuru(num: int) -> void:
	var pi: Dictionary = GameState.player[num]
	var kuru_container := get_tree().current_scene.get_node_or_null("KuruContainer")
	if kuru_container == null:
		return

	for kuru_node in kuru_container.get_children():
		var k: Dictionary = kuru_node.data
		if k["count"] < 3 * Constants.KURU_DANKAI_TIME:
			if pi["masu_x"] == k["masu_x"] and pi["masu_y"] == k["masu_y"]:
				k["count"] = 0


# ============================================================
# playerCrItem() の移植
# ============================================================
func _player_cr_item(num: int) -> void:
	var pi: Dictionary = GameState.player[num]
	if pi["cr_item_count"] != 0:
		return
	var use_key: Array = GameState.use_key[num]
	for slot in range(3):
		if use_key[5 + slot] == 1:
			_player_use_cr_item(slot, num)
			break


func _player_use_cr_item(cr_num: int, num: int) -> void:
	var pi: Dictionary = GameState.player[num]
	match pi["cr_item"][cr_num]:
		Enums.ItemType.ROCKET:
			SoundManager.play_cr_rocket()
			pi["cr_item_count"] = 5 * Constants.ITEM_USE_TIMES
			pi["cr_item_use"]   = Enums.ItemType.ROCKET
		Enums.ItemType.INVISIBLE:
			SoundManager.play_cr_invisible_start()
			pi["cr_item_count"] = 8 * Constants.ITEM_USE_TIMES
			pi["cr_item_use"]   = Enums.ItemType.INVISIBLE
		Enums.ItemType.SHOES:
			SoundManager.play_cr_shoes()
			pi["cr_item_count"] = 8 * Constants.ITEM_USE_TIMES
			pi["cr_item_use"]   = Enums.ItemType.SHOES
		Enums.ItemType.BROTHER:
			SoundManager.play_cr_brother()
			pi["cr_item_count"] = 5 * Constants.ITEM_USE_TIMES
			pi["cr_item_use"]   = Enums.ItemType.BROTHER
	pi["cr_item"][cr_num] = Enums.ItemType.NO_ITEM


# ============================================================
# オンライン: 相手プレイヤー死亡通知
# ============================================================

func _on_remote_player_died() -> void:
	var remote_idx := NetworkManager.remote_player_index()
	if player_num != remote_idx:
		return
	_apply_remote_death(remote_idx)

## 相手プレイヤーに死亡状態を適用する（RPC 送信はしない）
func _apply_remote_death(num: int) -> void:
	var pi: Dictionary = GameState.player[num]
	if not pi["life_flag"]:
		return  # 二重処理防止
	SoundManager.play_death(int(pi.get("character", 0)), false)
	pi["life_flag"]    = false
	pi["joutai_count"] = 0
	pi["joutai"]       = Enums.PlayerJoutaiType.DEATH
	_update_chat(num)


# ============================================================
# ヘルパー
# ============================================================

func _set_joutai(pi: Dictionary, new_joutai: int) -> void:
	if pi["joutai"] != new_joutai:
		pi["joutai_count"] = 0
		pi["joutai"]       = new_joutai

func _is_hard_block_cell(cell_x: int, cell_y: int) -> bool:
	if cell_x < 0 or cell_x >= Constants.FIELD_COLS:
		return false
	if cell_y < 0 or cell_y >= Constants.FIELD_ROWS:
		return false
	return GameState.masu[cell_y][cell_x]["kind"] == Enums.MasuKind.HARD_BLOCK

func _is_blast_blocked(origin_x: int, origin_y: int, step_x: int, step_y: int, distance: int) -> bool:
	for step in range(1, distance + 1):
		if _is_hard_block_cell(origin_x + step_x * step, origin_y + step_y * step):
			return true
	return false

func _is_hard_block_collision_right(next_x: int, current_y: int) -> bool:
	@warning_ignore("integer_division")
	var front_x: int = (next_x + 319) / 320
	@warning_ignore("integer_division")
	return _is_hard_block_cell(front_x, current_y / 320) \
		or _is_hard_block_cell(front_x, (current_y + 319) / 320)

func _is_hard_block_collision_left(next_x: int, current_y: int) -> bool:
	@warning_ignore("integer_division")
	var front_x: int = next_x / 320
	@warning_ignore("integer_division")
	return _is_hard_block_cell(front_x, current_y / 320) \
		or _is_hard_block_cell(front_x, (current_y + 319) / 320)

func _is_hard_block_collision_down(current_x: int, next_y: int) -> bool:
	@warning_ignore("integer_division")
	var front_y: int = (next_y + 319) / 320
	@warning_ignore("integer_division")
	return _is_hard_block_cell(current_x / 320, front_y) \
		or _is_hard_block_cell((current_x + 319) / 320, front_y)

func _is_hard_block_collision_up(current_x: int, next_y: int) -> bool:
	@warning_ignore("integer_division")
	var front_y: int = next_y / 320
	@warning_ignore("integer_division")
	return _is_hard_block_cell(current_x / 320, front_y) \
		or _is_hard_block_cell((current_x + 319) / 320, front_y)

func _sync_position() -> void:
	# C++ 座標（0.1px 単位）→ Godot float px
	position = Vector2(
		(Constants.MAP_LEFT_SIDE + p["x"]) * 0.1,
		(Constants.MAP_UP_SIDE   + p["y"]) * 0.1
	)

func _get_active_player_count() -> int:
	match GameState.joutai_flag:
		Enums.JoutaiType.VS_GAME, Enums.JoutaiType.VS_COM_GAME, \
		Enums.JoutaiType.VS_REPLAY, Enums.JoutaiType.VS_COM_REPLAY, \
		Enums.JoutaiType.ONLINE_GAME, Enums.JoutaiType.ONLINE_REPLAY:
			return 2
		_:
			return 1
