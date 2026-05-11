# scenes/Main/ComPathfinder.gd
class_name ComPathfinder
extends Node

# ====================================================================
#  COM の移動方向を決定するクラス
#
#  【役割】
#   危険度マップ (ComDangerDetector) の情報をもとに、
#   BFS（幅優先探索）で脱出経路や接近経路を求め、
#   そこへ向かうための「最初の一歩」を返す。
#
#  【脱出経路探索の考え方（精密設計）】
#   プレイヤーの現在サブピクセル座標・向き・速度を引数に受け取り、
#   現在マスを始点として4方向BFSを行う。
#   キューの各ノードはサブピクセル入場座標・向き・経過フレーム・深さを保持し、
#   振り向き時間・残り脱出距離・当たり判定ウィンドウ（BOMB_SPREAD_TIME+1F持続）
#   を精密に考慮する。永続安全マスが見つかったら即採用して打ち切る。
#   見つからなければ経過フレーム数が最大のマスを採用する。
# ====================================================================

const DEPTH: int = 12

var _danger_detector: ComDangerDetector = null

var _debug_last_escape_path: Array = []
var _debug_last_approach_path: Array = []

# ThinkRoutine から渡される方向優先順位
var _dir_order: Array = [0, 1, 2, 3]


func initialize(detector: ComDangerDetector) -> void:
	_danger_detector = detector

func set_dir_order(order: Array) -> void:
	_dir_order = order


# --------------------------------------------------------------------
# 現在位置から指定方向の隣接マスへ入るまでに要するフレーム数を返す。
# Player.gd では方向キーを押しても Constants.WAIT フレーム未満の間は
# 向きだけ変わって移動しないため、押下継続フレーム数に応じた
# 振り向き待機時間も到着時刻へ加算する。
# --------------------------------------------------------------------
func _move_per_frame(player_num: int, speed: int = 0) -> float:
	if speed > 0:
		return float(speed)
	var p: Dictionary = GameState.player[player_num]
	if p["cr_item_use"] == Enums.ItemType.SHOES:
		return float(Constants.SHOES_SPEED)
	return float(p["speed"])

func _move_frames(player_num: int, speed: int = 0) -> int:
	var move: float = _move_per_frame(player_num, speed)
	if move <= 0:
		return 999
	return ceili(320.0 / move)

func _turn_wait_frames(player_num: int, current_dir: int, next_dir: int, is_current_cell: bool) -> int:
	if is_current_cell:
		var use_key: Array = GameState.use_key[player_num]
		return maxi(Constants.WAIT - (int(use_key[next_dir]) + 1), 0)
	return 0 if current_dir == next_dir else Constants.WAIT - 1

func _arrival_frames(player_num: int, from_cell: Vector2i, dir: int, move_frames: int, current_dir: int, move_per_frame: float) -> int:
	var p: Dictionary = GameState.player[player_num]
	var current_cell := Vector2i(p["masu_x"], p["masu_y"])
	var is_current_cell: bool = from_cell == current_cell
	var turn_wait: int = _turn_wait_frames(player_num, current_dir, dir, is_current_cell)
	if is_current_cell:
		var remaining_frames: int = _frames_to_leave_current_cell(player_num, dir, move_per_frame)
		return turn_wait + remaining_frames
	return turn_wait + move_frames

func _frames_to_leave_current_cell(player_num: int, dir: int, move: float) -> int:
	var p: Dictionary = GameState.player[player_num]
	if move <= 0:
		return 999

	return Utility.frames_to_exit_at(p["x"], p["y"], dir, int(move))


# ====================================================================
#  脱出方向の選択（緊急回避用）
#
#  内部で _bfs_evaluate_escape を呼び、最初の一歩を返す。
#  戻り値 Dictionary:
#    "dir"        : 最初の一歩の方向 (0～3)、移動不可時は -1
#    "safe"       : 安全な経路かどうか
# ====================================================================
func pick_escape_quality(player_num: int, _unused: ComDangerDetector = null) -> Dictionary:
	var p: Dictionary = GameState.player[player_num]
	var start_x: int = p["masu_x"]
	var start_y: int = p["masu_y"]
	var speed: int = int(_move_per_frame(player_num))

	var bfs_result: Dictionary = _bfs_evaluate_escape(p["x"], p["y"], p["muki"], speed)

	var result: Dictionary = {
		"dir": -1,
		"safe": bfs_result["safe"]
	}

	if bfs_result["chosen_key"] != "":
		var path: Array = []
		var current: String = bfs_result["chosen_key"]
		while bfs_result["parent"].has(current) and bfs_result["parent"][current] != Vector2i(-1, -1):
			var coords: PackedStringArray = current.split(",")
			path.push_front(Vector2i(int(coords[0]), int(coords[1])))
			var p_vec: Vector2i = bfs_result["parent"][current]
			current = "%d,%d" % [p_vec.x, p_vec.y]
		_debug_last_escape_path = path
		if not path.is_empty():
			var first_cell: Vector2i = path[0]
			var dx = first_cell.x - start_x
			var dy = first_cell.y - start_y
			if dx == 1 and dy == 0:    result["dir"] = 0
			elif dx == -1 and dy == 0: result["dir"] = 1
			elif dx == 0 and dy == 1:  result["dir"] = 2
			elif dx == 0 and dy == -1: result["dir"] = 3
	else:
		_debug_last_escape_path = []

	return result


# --------------------------------------------------------------------
# 現在の速度または指定された速度で、安全な脱出先があるかどうか
# speed=0 なら現在の速度、それ以外は 0.1px 単位の速度指定
# --------------------------------------------------------------------
func can_escape_safely(player_num: int, speed: int = 0) -> bool:
	var p: Dictionary = GameState.player[player_num]
	var actual_speed: int = int(_move_per_frame(player_num, speed))
	if actual_speed <= 0:
		return false
	var result: Dictionary = _bfs_evaluate_escape(p["x"], p["y"], p["muki"], actual_speed)
	return result["safe"]


# ====================================================================
#  BFS 探索本体（精密設計）
#
#  引数:
#    x, y  : プレイヤーの現在サブピクセル座標（0.1px 単位整数）
#    dir   : 現在の向き（0=RIGHT, 1=LEFT, 2=DOWN, 3=UP）
#    speed : 移動速度（0.1px/frame 単位整数）
#
#  (x,y) の属するマス (masu_x, masu_y) を始点として4方向BFSを行う。
#
#  キューの各ノードは以下を保持する:
#    "x","y"   : そのマスへの入場時サブピクセル座標
#    "mx","my" : マス座標
#    "dir"     : 入場時の向き
#    "elapsed" : BFS開始からの経過フレーム数
#    "depth"   : 何マス目か（DEPTHで打ち切り）
#
#  隣接マスへの追加条件:
#    1. 未探索マスである
#    2. 移動可能マスである
#    3. 今居るマスの当たり判定が来る前に脱出できる
#       （dir と移動方向が異なる場合は振り向きに Constants.WAIT F かかる）
#    4. 隣接マスへの到着時、当たり判定が発生中でない
#       （当たり判定は発生から BOMB_SPREAD_TIME+1 F 持続するため、
#        到着が判定ウィンドウを過ぎた後なら進入可能）
#    ソート: 到着直後から当たり判定が発生するまでの猶予フレーム数の降順
#
#  永続安全マス（hit_frame>=9999）に到達したら即座に採用して打ち切る。
#  見つからなければ経過フレーム数が最大のマスを採用する。
#
#  戻り値 Dictionary:
#    "safe"       : 安全な経路かどうか
#    "chosen_key" : 採用された目的地の "mx,my" 文字列
#    "parent"     : 経路復元用の親マップ
#    "dest_hit"   : 目的地の被弾開始フレーム
# ====================================================================
func _bfs_evaluate_escape(x: int, y: int, dir: int, speed: int) -> Dictionary:
	# 開始マス座標
	var start_cell := Utility.world_to_cell(x, y)
	var smx: int = start_cell.x
	var smy: int = start_cell.y

	var queue: Array = []
	var visited: Dictionary = {}
	var parent: Dictionary = {}  # "mx,my" -> Vector2i(parent_mx, parent_my)

	var start_key: String = "%d,%d" % [smx, smy]
	queue.append({
		"x": x, "y": y,
		"mx": smx, "my": smy,
		"dir": dir,
		"elapsed": 0,
		"depth": 0
	})
	parent[start_key] = Vector2i(-1, -1)

	var best_key: String = ""
	var best_elapsed: int = -1
	var best_hit: int = -1

	while not queue.is_empty():
		var cur: Dictionary = queue.pop_front()
		var key: String = "%d,%d" % [cur["mx"], cur["my"]]
		if visited.has(key):
			continue
		visited[key] = true

		var cell_hit: int = _danger_detector.hit_frame_from_events(cur["mx"], cur["my"])

		# 永続安全マス → 即採用して打ち切り
		if cell_hit >= 9999:
			return {
				"safe": true,
				"chosen_key": key,
				"parent": parent,
				"dest_hit": 9999
			}

		# 経過フレーム最大を更新（安全でない最善候補）
		if cur["elapsed"] > best_elapsed:
			best_elapsed = cur["elapsed"]
			best_hit = cell_hit
			best_key = key

		if cur["depth"] >= DEPTH:
			continue

		# このマスで、入場時点からの残り猶予フレーム
		# （cell_hit: BFS開始時点からの被弾開始フレーム）
		# remaining_safe <= 0 → 入場時すでに当たり判定中 → 脱出不可
		var remaining_safe: int = cell_hit - cur["elapsed"]

		# 隣接4マスを探索
		var neighbors: Array = []
		for d in range(4):
			var nx: int = cur["mx"] + Utility.dx_from_dir(d)
			var ny: int = cur["my"] + Utility.dy_from_dir(d)
			var nkey: String = "%d,%d" % [nx, ny]

			if not Utility.is_walkable_cell(nx, ny) or visited.has(nkey):
				continue

			# 振り向き時間（dir と移動方向が異なる場合は WAIT フレーム）
			var turn_wait: int = 0 if cur["dir"] == d else Constants.WAIT
			# 現在サブピクセル位置から方向 d にこのマスを出るまでのフレーム数
			var exit_frames: int = Utility.frames_to_exit_at(cur["x"], cur["y"], d, speed)
			var time_to_exit: int = turn_wait + exit_frames

			# 条件3: 当たり判定が来る前にこのマスを脱出できるか
			# time_to_exit < remaining_safe が必要（厳密な不等号）
			if time_to_exit >= remaining_safe:
				continue

			# 隣接マスへの到着フレーム（BFS開始時点からの絶対フレーム）
			var arrival: int = cur["elapsed"] + time_to_exit

			# 隣接マスの当たり判定情報
			var n_hit: int = _danger_detector.hit_frame_from_events(nx, ny)

			# 条件4: 到着時に当たり判定が発生中でないか
			# 当たり判定の有効ウィンドウ: [n_hit, n_hit + BOMB_SPREAD_TIME]（BOMB_SPREAD_TIME+1 F 持続）
			# 到着が判定ウィンドウの前 or 後なら進入可能
			var can_enter: bool
			if n_hit >= 9999:
				can_enter = true                                      # 永続安全
			elif arrival < n_hit:
				can_enter = true                                      # 判定前に到着
			elif arrival > n_hit + Constants.BOMB_SPREAD_TIME:
				can_enter = true                                      # 判定ウィンドウ終了後に到着
			else:
				can_enter = false                                     # 判定中に到着

			if not can_enter:
				continue

			# ソート用マージン: 到着直後から当たり判定が来るまでの猶予フレーム数
			# （降順でソートするため、安全なものが大きい値になる）
			var margin: int
			if n_hit >= 9999 or arrival > n_hit + Constants.BOMB_SPREAD_TIME:
				margin = 9999   # 永続安全 or 判定終了後到着 → 最優先
			else:
				margin = n_hit - arrival

			neighbors.append({
				"nx": nx, "ny": ny, "nkey": nkey,
				"d": d,
				"arrival": arrival,
				"margin": margin,
				"ex": Utility.entry_x(nx, d),
				"ey": Utility.entry_y(ny, d)
			})

		# 猶予フレームの降順でソート（キューへの積み順が探索優先度に影響）
		neighbors.sort_custom(func(a, b): return a["margin"] > b["margin"])

		for nb in neighbors:
			if not parent.has(nb["nkey"]):
				parent[nb["nkey"]] = Vector2i(cur["mx"], cur["my"])
			queue.append({
				"x": nb["ex"], "y": nb["ey"],
				"mx": nb["nx"], "my": nb["ny"],
				"dir": nb["d"],
				"elapsed": nb["arrival"],
				"depth": cur["depth"] + 1
			})

	# 永続安全マスが見つからなかった場合、経過フレーム最大のマスを採用
	if best_key != "":
		return {
			"safe": false,
			"chosen_key": best_key,
			"parent": parent,
			"dest_hit": best_hit
		}

	# 一切展開できなかった場合
	return {
		"safe": false,
		"chosen_key": "",
		"parent": parent,
		"dest_hit": -1
	}


# ====================================================================
#  外部公開用
# ====================================================================
func get_last_escape_path() -> Array:
	return _debug_last_escape_path

func get_last_approach_path() -> Array:
	return _debug_last_approach_path
