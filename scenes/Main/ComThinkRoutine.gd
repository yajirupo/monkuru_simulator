# scenes/Main/ComThinkRoutine.gd
class_name ComThinkRoutine
extends Node

# 依存モジュール（初期化は _init() で行う）
var _danger_detector: ComDangerDetector
var _pathfinder: ComPathfinder
var _item_user: ComItemUser
var _player_tracker: ComPlayerTracker
var _rush_controller: ComRushController   # ラッシュ行動を管理
var _chain_attacker: ComChainAttacker     # 連鎖攻撃を管理

# 内部状態
var _dir_order: Array = [0, 1, 2, 3]  # 右, 左, 下, 上、後にシャッフルされる
var _shuffle_timer: int = 60
var _recent_shots: Array = []  # { "frame": int, "x": int, "y": int, "muki": int }

# デバッグ用スナップショット（毎フレーム更新）
var debug_snapshot: Dictionary = {}

const BOMB_KEY: int = 4
const ITEM_KEY_BASE: int = 5

# ---- 接近目標（優先度6の新ルール用） ----
var _approach_wx: int = 0
var _approach_wy: int = 0


func _init() -> void:
	_danger_detector = ComDangerDetector.new()
	_pathfinder = ComPathfinder.new()
	_item_user = ComItemUser.new()
	_player_tracker = ComPlayerTracker.new()
	_rush_controller = ComRushController.new()
	_chain_attacker = ComChainAttacker.new()
	_approach_wx = 0
	_approach_wy = 0


func setup(field_masu: Array) -> void:
	_danger_detector.initialize(field_masu)
	_pathfinder.initialize(_danger_detector)
	_item_user.initialize(GameState, _danger_detector, _pathfinder)
	_rush_controller.initialize(_danger_detector)
	_chain_attacker.initialize(_danger_detector)


func update_com_keys(bomb_container: Node, kuru_container: Node) -> void:
	_danger_detector.build_event_list(bomb_container, kuru_container)
	_build_com_input(kuru_container)


func reset_for_new_game() -> void:
	_shuffle_timer = 60
	_recent_shots.clear()
	_player_tracker.reset()
	_rush_controller.reset()
	_approach_wx = 0
	_approach_wy = 0


## Main.gd から呼ばれる（被弾時などにラッシュを中断）
func cancel_rush() -> void:
	_rush_controller.cancel_rush()


func _build_com_input(kuru_container: Node) -> void:
	var keys: Array = [false, false, false, false, false, false, false, false]
	var player_num: int = 1
	var opponent_num: int = 0
	var p: Dictionary = GameState.player[player_num]
	var op: Dictionary = GameState.player[opponent_num]

	# 敵の推定座標を取得し、op を上書き
	var estimated_pos: Vector2i = _player_tracker.get_estimated_enemy_pos(op, kuru_container)
	var op_estimated: Dictionary = op.duplicate()
	op_estimated["masu_x"] = estimated_pos.x
	op_estimated["masu_y"] = estimated_pos.y

	_shuffle_timer += 1
	if _shuffle_timer >= 60:
		_shuffle_timer = 0
		_dir_order.shuffle()
		_pathfinder.set_dir_order(_dir_order)
		_approach_wx = randi() % 3  # 0, 1, 2
		_approach_wy = randi() % 3

	var px: int = p["masu_x"]
	var py: int = p["masu_y"]
	var in_danger: bool = _danger_detector.is_cell_danger(px, py)

	var phase: String = "NONE"
	var reason: String = ""

	# 優先度1: ラッシュモード（継続）
	if _rush_controller.is_active():
		var result: Dictionary = _rush_controller.process_rush(keys, player_num)
		_apply_keys(keys, player_num)
		_update_debug_snapshot(result["phase"], result["reason"], keys, false)
		return

	# ---- ラッシュ開始条件判定 ----
	if _rush_controller.should_start_rush(op_estimated):
		var rush_dir: int = p["muki"]  # 現在の向きで突撃
		if _rush_controller.can_safely_rush(rush_dir):
			var can_start_rush: bool = true
			if p["cr_item_count"] == 0:
				var shoes_slot: int = _item_user._find_item_slot(p, Enums.ItemType.SHOES)
				if shoes_slot == -1:
					can_start_rush = false
				else:
					keys[ITEM_KEY_BASE + shoes_slot] = true
			if can_start_rush:
				_recent_shots.clear()
				_rush_controller.start_rush(rush_dir)
				var result: Dictionary = _rush_controller.process_rush(keys, player_num)  # 初回ラッシュフレーム
				_apply_keys(keys, player_num)
				_update_debug_snapshot(result["phase"], result["reason"], keys, false)
				return

	# 優先度2: アイテム使用
	var item_slot: int = _item_user.decide(player_num, op_estimated)
	if item_slot != -1:
		keys[ITEM_KEY_BASE + item_slot] = true
		var item_reason: String = _item_user.debug_decision_reason
		reason += "Item slot %d (%s); " % [item_slot, item_reason]

	# 優先度3: 緊急回避
	if in_danger:
		phase = "ESCAPE"
		var escape_quality: Dictionary = _pathfinder.pick_escape_quality(player_num, _danger_detector)
		var escape_dir: int = escape_quality.get("dir", -1)
		if escape_dir >= 0:
			keys[escape_dir] = true
			reason += "Escaping dir %d from cell(%d,%d) sub(%d,%d)" % [escape_dir, px, py, p["x"], p["y"]]
		else:
			keys[p["muki"]] = true
			reason += "Cannot escape, desperate move dir %d from cell(%d,%d) sub(%d,%d)" % [p["muki"], px, py, p["x"], p["y"]]
		_apply_keys(keys, player_num)
		_update_debug_snapshot(phase, reason, keys, in_danger)
		return

	# 優先度4: 連鎖狙い（永続安全地点から隣接危険マスへ）
	if (
		_danger_detector.is_cell_eternally_safe(px, py)
		and p["cr_item_use"] != Enums.ItemType.ROCKET
		and p["cr_item_use"] != Enums.ItemType.BROTHER
		and not _chain_attacker.is_cell_near_wall(px, py)
		and _can_com_shoot_kuru_in_chain(player_num, op_estimated)
	):
		var chain_dir: int = _chain_attacker.get_chain_dir(player_num, _dir_order)
		var safe_dir: int = _chain_attacker.get_safe_neighbor_dir(player_num, chain_dir, _dir_order)
		if chain_dir != -1 and safe_dir != -1:
			var p_muki: int = GameState.player[player_num]["muki"]
			if p_muki == chain_dir:
				# すでに向いている → くる発射 + 安全方向へ移動
				keys[BOMB_KEY] = true
				_record_com_shot(player_num)
				keys[safe_dir] = true
				phase = "CHAIN_ATTACK"
				reason += "Chain attack dir %d" % chain_dir
			else:
				# まだ向いていない → 向き変更
				keys[chain_dir] = true
				phase = "CHAIN_TURN"
				reason += "Turn for chain dir %d" % chain_dir
			_apply_keys(keys, player_num)
			_update_debug_snapshot(phase, reason, keys, in_danger)
			return

	# 優先度5: 攻撃
	var can_shoot: bool = _can_com_shoot_kuru(player_num, op_estimated)
	if can_shoot:
		# 今向いている方向以外の3方向の隣接マスを調べ、永続安全マスがあればそちらへ逃げる
		var escape_dir: int = -1
		var p_muki: int = p["muki"]
		for d in _dir_order:
			if d == p_muki:
				continue
			var nx: int = px + Utility.dx_from_dir(d)
			var ny: int = py + Utility.dy_from_dir(d)
			if Utility.is_walkable_cell(nx, ny) and _danger_detector.is_cell_eternally_safe(nx, ny):
				escape_dir = d
				break

		if escape_dir != -1:
			phase = "ATTACK"
			keys[BOMB_KEY] = true
			keys[escape_dir] = true
			_record_com_shot(player_num)
			reason += "Shoot and escape dir %d" % escape_dir
			_apply_keys(keys, player_num)
			_update_debug_snapshot(phase, reason, keys, in_danger)
			return

	# 優先度6: 接近（囲碁で言うカタツキっぽく追い込む。あわよくばラッシュに繋がる）
	var op_x: int = op_estimated["masu_x"]
	var op_y: int = op_estimated["masu_y"]

	# 敵が左壁に近ければ dx=1（右方向）、右壁に近ければ dx=-1（左方向）
	var dx: int
	if op_x < Constants.FIELD_COLS - 1 - op_x:
		dx = 1
	else:
		dx = -1
	# 敵が上壁に近ければ dy=1（下方向）、下壁に近ければ dy=-1（上方向）
	var dy: int
	if op_y < Constants.FIELD_ROWS - 1 - op_y:
		dy = 1
	else:
		dy = -1

	var target_x: int = op_x + _approach_wx * dx
	var target_y: int = op_y + _approach_wy * dy
	target_x = clampi(target_x, 0, Constants.FIELD_COLS - 1)
	target_y = clampi(target_y, 0, Constants.FIELD_ROWS - 1)

	if not Utility.is_walkable_cell(target_x, target_y):
		target_x = op_x
		target_y = op_y

	# 透明マント使用中は、プレイヤーに重なりに行く
	if p["cr_item_use"] == Enums.ItemType.INVISIBLE and p["cr_item_count"] > 0:
		target_x = op_x
		target_y = op_y

	var move_dir: int = _choose_direction_toward_target(player_num, target_x, target_y)
	if move_dir >= 0:
		phase = "APPROACH"
		keys[move_dir] = true
		reason += "Approach dir %d from cell(%d,%d) sub(%d,%d) toward (%d,%d)" % [
			move_dir, px, py, p["x"], p["y"], target_x, target_y
		]
		_apply_keys(keys, player_num)
		_update_debug_snapshot(phase, reason, keys, in_danger)
		debug_snapshot["approach_dir"] = move_dir  # 1マス矢印用に方向を保存
		return

	phase = "IDLE"
	_apply_keys(keys, player_num)
	_update_debug_snapshot(phase, reason, keys, in_danger)


# ====================================================================
# デバッグ・キー適用
# ====================================================================

func _update_debug_snapshot(phase: String, reason: String, keys: Array, in_danger: bool) -> void:
	var p: Dictionary = GameState.player[1]
	debug_snapshot = {
		"phase": phase,
		"reason": reason,
		"keys": keys.duplicate(),
		"player_pos": Vector2i(p["masu_x"], p["masu_y"]),
		"in_danger": in_danger,
		"shot_count": p["shot_count"],
		"shot_kuru": p["shot_kuru"],
		"item_use": p["cr_item_use"],
		"item_count": p["cr_item_count"],
		"danger_grid": _danger_detector.get_danger_grid(),
		"escape_path": _pathfinder.get_last_escape_path(),
		"approach_path": _pathfinder.get_last_approach_path(),
	}


func _apply_keys(keys: Array, player_num: int) -> void:
	var uk: Array = GameState.use_key[player_num]
	for i in range(8):
		if keys[i]:
			uk[i] += 1
		else:
			uk[i] = 0


# ====================================================================
# 射撃判定・履歴
# ====================================================================

func _can_com_shoot_kuru(player_num: int, op_estimated: Dictionary) -> bool:
	var p: Dictionary = GameState.player[player_num]

	# マンハッタン距離が火力以下かどうか
	var mx: int = p["masu_x"]
	var my: int = p["masu_y"]
	var ox: int = op_estimated["masu_x"]
	var oy: int = op_estimated["masu_y"]
	var manhattan: int = abs(mx - ox) + abs(my - oy)
	if manhattan > p["item_power"]:
		return false

	# 進行方向の1マス先が危険マスなら射出しない（連鎖狙いでないなら危ないことはしない）
	var front_cell: Vector2i = Utility.get_front_cell(p, p["muki"])
	if _danger_detector.is_cell_danger(front_cell.x, front_cell.y):
		return false

	# COMが透明マント使用中は距離1以下でのみ発射許可（遠距離からは撃たず、まず接近する）
	if p["cr_item_use"] == Enums.ItemType.INVISIBLE and p["cr_item_count"] > 0:
		if manhattan > 1:
			return false

	if p["shot_count"] > 0:
		return false

	# 60フレーム以上古いエントリを削除（ループ前に一括除去）
	var now: int = GameState.count
	while _recent_shots.size() > 0 and now - _recent_shots[0].frame >= 60:
		_recent_shots.pop_front()

	# 直近8フレーム以内の連射禁止（_recent_shots の末尾を参照）
	if _recent_shots.size() > 0 and now - _recent_shots.back().frame < 8:
		return false

	# 最近60フレームに同じマス・同じ向きでの発射があったか
	for shot in _recent_shots:
		if shot.x == p["masu_x"] and shot.y == p["masu_y"] and (p["kuru_speed"] < Constants.kuru_speed_stat_to_move_speed(0) or shot.muki == p["muki"]):
			return false

	var max_shot: int = p["item_shot"]
	var current_shot: int = p["shot_kuru"]
	if p["cr_item_use"] == Enums.ItemType.ROCKET:
		max_shot = 6
	elif p["cr_item_use"] == Enums.ItemType.BROTHER:
		max_shot = 12
	if current_shot >= max_shot:
		return false
	return true


func _can_com_shoot_kuru_in_chain(player_num: int, op_estimated: Dictionary) -> bool:
	var p: Dictionary = GameState.player[player_num]

	# COMが透明マント使用中は距離1以下でのみ発射許可
	var mx: int = p["masu_x"]
	var my: int = p["masu_y"]
	var ox: int = op_estimated["masu_x"]
	var oy: int = op_estimated["masu_y"]
	var manhattan: int = abs(mx - ox) + abs(my - oy)
	if p["cr_item_use"] == Enums.ItemType.INVISIBLE and p["cr_item_count"] > 0:
		if manhattan > 1:
			return false

	if p["shot_count"] > 0:
		return false

	# 直近8フレーム以内の連射禁止
	if _recent_shots.size() > 0 and GameState.count - _recent_shots.back().frame < 8:
		return false

	var max_shot: int = p["item_shot"]
	var current_shot: int = p["shot_kuru"]
	if current_shot >= max_shot:
		return false
	return true


func _record_com_shot(player_num: int) -> void:
	var p: Dictionary = GameState.player[player_num]
	_recent_shots.append({
		"frame": GameState.count,
		"x": p["masu_x"],
		"y": p["masu_y"],
		"muki": p["muki"]
	})


# ====================================================================
# 接近行動ヘルパー
# ====================================================================

# 1マス移動に要するフレーム数
func _com_move_frames(player_num: int) -> int:
	var p: Dictionary = GameState.player[player_num]
	var speed: int = p["speed"]
	var move: float
	if p["cr_item_use"] == Enums.ItemType.SHOES:
		move = float(Constants.SHOES_SPEED)
	else:
		move = float(speed)
	if move <= 0:
		return 999
	return ceili(320.0 / move)


# 指定セルが安全に移動できるか（移動先に到着した時点で被弾していない）
func _is_cell_safe_for_move(x: int, y: int, move_frames: int) -> bool:
	var hit_frame: int = _danger_detector.hit_frame_from_events(x, y)
	return hit_frame > move_frames


# 目標地点へ向かう最初の一歩の方向を返す（安全で歩行可能な隣接セルの中から選択）
func _choose_direction_toward_target(player_num: int, target_x: int, target_y: int) -> int:
	var p: Dictionary = GameState.player[player_num]
	var sx: int = p["masu_x"]
	var sy: int = p["masu_y"]
	var mf: int = _com_move_frames(player_num)

	var candidates: Array = []
	for d in _dir_order:
		var nx: int = sx + Utility.dx_from_dir(d)
		var ny: int = sy + Utility.dy_from_dir(d)
		if Utility.is_walkable_cell(nx, ny) and _is_cell_safe_for_move(nx, ny, mf):
			candidates.append({
				"dir": d,
				"dist": abs(nx - target_x) + abs(ny - target_y)
			})

	if candidates.is_empty():
		return -1

	# 目標に近い順にソート
	candidates.sort_custom(func(a, b): return a["dist"] < b["dist"])
	return candidates[0]["dir"]
