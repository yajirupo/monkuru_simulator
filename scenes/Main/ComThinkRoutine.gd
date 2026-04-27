class_name ComThinkRoutine
extends RefCounted

# 依存クラス
const ComDangerDetectorClass = preload("res://scenes/Main/ComDangerDetector.gd")
const ComPathfinderClass      = preload("res://scenes/Main/ComPathfinder.gd")
const ComItemUserClass        = preload("res://scenes/Main/ComItemUser.gd")
const ComPlayerTrackerClass   = preload("res://scenes/Main/ComPlayerTracker.gd")

# ── 依存オブジェクト ─────────────────────────────────────────────────────────
var _detector:      ComDangerDetector
var _pathfinder:    ComPathfinder
var _item_user:     ComItemUser
var _player_tracker: ComPlayerTracker  # 透明マント中の敵位置推定

# ── COM の状態変数 ───────────────────────────────────────────────────────────
# 爆弾を置いた直後フラグ（次フレームで逃げを優先）
var _com_bomb_just_placed: bool = false
var _com_last_shot_frame:  int  = -1000000
var _com_last_shot_muki:   int  = Enums.Muki.DOWN
var _com_last_shot_origin: Vector2i = Vector2i(-9999, -9999)

# ── アイテム使用キーのインデックス ──────────────────────────────────────────
const ITEM_KEY_BASE := 5

# ── 移動速度定数 ─────────────────────────────────────────────────────────────
# スピード靴使用時のフレーム数
# SHOES_SPEED=100, move=100/2=50 sub-px/frame, ceildiv(320, 50) = 7
const _SPEED_MOVE_FRAMES := 7

# ── [追加] デバッグスナップショット ─────────────────────────────────────────
# ComDebugOverlay が毎フレーム参照する。
# _build_com_input() の各 return 直前に更新される。
# NOTE: ゲームロジックには一切影響しない（読み取り専用の診断データ）。
var debug_snapshot: Dictionary = {}


func _init() -> void:
	_detector       = ComDangerDetectorClass.new()
	_pathfinder     = ComPathfinderClass.new(_detector)
	_item_user      = ComItemUserClass.new(_detector)
	_player_tracker = ComPlayerTrackerClass.new()


# ============================================================
# update_com_keys()
#
# メインループから毎フレーム呼ばれるエントリポイント。
# プレイヤー0のキー入力を読み取り、COM（プレイヤー1）の入力を生成する。
# ============================================================
func update_com_keys(bomb_container: Node, kuru_container: Node) -> void:
	for i in range(8):
		GameState.use_key[0][i] = KeyInput.get_key(GameState.use_key_single[i])

	var desired := _build_com_input(bomb_container, kuru_container)
	for i in range(8):
		if desired[i]:
			GameState.use_key[1][i] += 1
		else:
			GameState.use_key[1][i] = 0


# ============================================================
# _get_move_frames()
#
# プレイヤーデータから「1マス移動にかかるフレーム数（切り上げ）」を返す。
#
# Player.gd _player_move() の実装:
#   move = speed / 2    ← integer division（sub-pixel/frame）
#   x += move           ← 毎フレームこれだけ動く
#   masu_x = (x + 160) / 320   ← マス変換（1マス = 320 sub-px）
#
# よってフレーム数 = ceil(320 / move) = ceil(320 / (speed / 2))
#
# 具体例:
#   PLAYER_DEFAULT_SPEED=35  move=17  → ceil(320/17) = 19 frame/masu
#   item_speed=1 の場合      move=20  → ceil(320/20) = 16 frame/masu
#   SHOES_SPEED=100          move=50  → ceil(320/50) =  7 frame/masu
# ============================================================
func _get_move_frames(me: Dictionary) -> int:
	var spd: int
	if int(me.get("cr_item_use", Enums.ItemType.NO_ITEM)) == Enums.ItemType.SHOES \
	   and int(me.get("cr_item_count", 0)) > 0:
		# スピード靴使用中
		spd = Constants.SHOES_SPEED
	else:
		spd = int(me.get("speed", Constants.PLAYER_DEFAULT_SPEED))
	@warning_ignore("integer_division")
	var move: int = spd / 2   # Player.gd と同一: integer division
	if move <= 0:
		return 999
	# ceildiv(320, move)
	@warning_ignore("integer_division")
	return (320 + move - 1) / move


# ============================================================
# _build_com_input()
#
# COM の思考ロジック本体。優先度順に行動を決定し、
# 入力フラグ配列 (keys) を返す。
#
# [変更点]
# ・各 return 直前に debug_snapshot を更新するようにした。
#   それ以外のロジックは元のコードと完全に同一。
# ============================================================
func _build_com_input(bomb_container: Node, kuru_container: Node) -> Array[bool]:
	var keys: Array[bool] = [false, false, false, false, false, false, false, false]
	if GameState.player.size() < 2:
		return keys

	var me: Dictionary    = GameState.player[1]
	var enemy: Dictionary = GameState.player[0]
	if not me["life_flag"]:
		return keys

	# 約1秒ごとに移動方向の優先順位をシャッフルする
	_pathfinder.refresh_dir_order()

	var me_x:    int = me["masu_x"]
	var me_y:    int = me["masu_y"]
	var my_power: int = int(me.get("item_power", 2))

	# ── 敵座標の解決（透明マント考慮） ─────────────────────────────────────
	var enemy_pos: Vector2i = _player_tracker.get_estimated_enemy_pos(enemy, kuru_container)
	var enemy_x: int = enemy_pos.x
	var enemy_y: int = enemy_pos.y

	# ── 危険判定・逃げ品質を事前計算（複数の優先度で共有） ─────────────────────
	var danger_info:    Dictionary = _detector.find_bomb_danger(me_x, me_y, bomb_container, kuru_container)
	var in_danger:      bool       = danger_info["danger"]
	var move_frames:    int        = _get_move_frames(me)
	var escape_quality: Dictionary = _pathfinder.pick_escape_quality(me_x, me_y, bomb_container, kuru_container, move_frames)

	# ── スピード靴チェック ────────────────────────────────────────────────────
	# 逃走フェーズかつ現在速度では安全経路がない場合、
	# スピード靴で安全経路が開けるなら靴を使う準備をする。
	var use_speed_shoes: bool = false
	if (in_danger or _com_bomb_just_placed) and not escape_quality.get("is_safe", false):
		var shoe_slot: int = _find_item_slot(me, Enums.ItemType.SHOES)
		if shoe_slot >= 0 and int(me.get("cr_item_count", 0)) == 0:
			var fast_quality: Dictionary = _pathfinder.pick_escape_quality(
				me_x, me_y, bomb_container, kuru_container, _SPEED_MOVE_FRAMES)
			if fast_quality.get("is_safe", false):
				use_speed_shoes = true
				escape_quality  = fast_quality  # 靴使用時の経路を採用

	# ── [追加] スナップショット用ベース情報 ─────────────────────────────────
	# 各 return 直前で "phase" だけ差し替えて debug_snapshot に代入する。
	var _base_snap: Dictionary = {
		"me_x":               me_x,
		"me_y":               me_y,
		"my_power":           my_power,
		"enemy_x":            enemy_x,
		"enemy_y":            enemy_y,
		"real_enemy_x":       int(enemy.get("masu_x", 0)),
		"real_enemy_y":       int(enemy.get("masu_y", 0)),
		"is_enemy_cloaked":   _player_tracker.is_tracking(),
		"in_danger":          in_danger,
		"danger_x":           danger_info.get("x", -1),
		"danger_y":           danger_info.get("y", -1),
		"escape_dir":         escape_quality.get("dir", -1),
		"escape_is_safe":     escape_quality.get("is_safe", false),
		"escape_path_margin": escape_quality.get("path_margin", 0),
		"escape_path":        escape_quality.get("escape_path", []),
		"move_frames":        move_frames,
		"use_speed_shoes":    use_speed_shoes,
		"bomb_just_placed":   _com_bomb_just_placed,
		"phase":              "IDLE",   # 各分岐で上書き
	}

	# ── 優先度0: アイテム使用 ───────────────────────────────────────────────
	var item_to_use: int = _item_user.decide(
		me, me_x, me_y, enemy_x, enemy_y, escape_quality, in_danger
	)
	if item_to_use != Enums.ItemType.NO_ITEM:
		var slot: int = _find_item_slot(me, item_to_use)
		if slot >= 0:
			keys[ITEM_KEY_BASE + slot] = true

	# ── 優先度1: 爆弾の危険範囲内 or 直前に爆弾を置いた → 安全マスへ逃げる ──
	if in_danger or _com_bomb_just_placed:
		_com_bomb_just_placed = false
		# スピード靴を使う場合: アイテムキーを押して発動
		if use_speed_shoes:
			var shoe_slot: int = _find_item_slot(me, Enums.ItemType.SHOES)
			if shoe_slot >= 0:
				keys[ITEM_KEY_BASE + shoe_slot] = true
		var dir2: int = escape_quality["dir"]
		if dir2 >= 0:
			keys[dir2] = true
		# [追加] スナップショット更新
		_base_snap["phase"] = "ESCAPE"
		debug_snapshot = _base_snap
		return keys

	# ── 優先度2: 敵が射程内 → 爆弾を置いて即逃げ ──────────────────────────
	if _is_enemy_in_bomb_range(me_x, me_y, enemy_x, enemy_y, my_power):
		var escape_dir: int = escape_quality["dir"]
		if escape_dir >= 0 and _can_com_shoot_kuru(me, kuru_container):
			keys[4] = true  # 爆弾設置
			keys[escape_dir] = true
			_com_bomb_just_placed = true
			_record_com_shot(me)
			# [追加] スナップショット更新
			_base_snap["phase"] = "ATTACK"
			debug_snapshot = _base_snap
			return keys

	# ── 優先度3: 敵の射程位置（同行・同列）を目指して接近 ─────────────────
	var dir := _pathfinder.pick_approach_direction(
		me_x, me_y, enemy_x, enemy_y, my_power, bomb_container, kuru_container
	)
	if dir >= 0:
		keys[dir] = true

	# [追加] スナップショット更新
	_base_snap["phase"] = "APPROACH"
	debug_snapshot = _base_snap
	return keys


# ============================================================
# _is_enemy_in_bomb_range()
# ============================================================
func _is_enemy_in_bomb_range(me_x: int, me_y: int, ex: int, ey: int, power: int) -> bool:
	if me_x == ex and abs(me_y - ey) <= power and not _is_blast_blocked(me_x, me_y, ex, ey):
		return true
	if me_y == ey and abs(me_x - ex) <= power and not _is_blast_blocked(me_x, me_y, ex, ey):
		return true
	return false


func _is_blast_blocked(from_x: int, from_y: int, to_x: int, to_y: int) -> bool:
	if from_x != to_x and from_y != to_y:
		return true
	var step_x: int = sign(to_x - from_x)
	var step_y: int = sign(to_y - from_y)
	var x: int = from_x + step_x
	var y: int = from_y + step_y
	while x != to_x or y != to_y:
		if _is_hard_block(x, y):
			return true
		x += step_x
		y += step_y
	return false


func _is_hard_block(x: int, y: int) -> bool:
	var masu: Array = GameState.masu
	if masu.size() <= y or masu[y].size() <= x:
		return false
	return masu[y][x].kind != Enums.MasuKind.BROKEN


func _find_item_slot(me: Dictionary, item_type: int) -> int:
	var items: Array = me.get("cr_item", [])
	for i in range(min(items.size(), 3)):
		if int(items[i]) == item_type:
			return i
	return -1


# ============================================================
# _can_com_shoot_kuru()
# ============================================================
func _can_com_shoot_kuru(me: Dictionary, kuru_container: Node) -> bool:
	if int(me.get("shot_count", 0)) > 0:
		return false

	var shot_kuru: int = int(me.get("shot_kuru", 0))
	var item_shot: int = int(me.get("item_shot", 0))
	var item_use:  int = int(me.get("cr_item_use", Enums.ItemType.NO_ITEM))
	if item_use == Enums.ItemType.BROTHER:
		if shot_kuru >= 11:
			return false
	elif item_use == Enums.ItemType.ROCKET:
		if shot_kuru >= 6:
			return false
	elif shot_kuru >= item_shot:
		return false

	var now_frame: int = Engine.get_process_frames()
	if now_frame - _com_last_shot_frame < 5:
		return false

	var origin: Vector2i = Vector2i(int(me.get("masu_x", 0)), int(me.get("masu_y", 0)))
	var facing: int = int(me.get("muki", Enums.Muki.DOWN))
	if facing == _com_last_shot_muki \
		and abs(origin.x - _com_last_shot_origin.x) + abs(origin.y - _com_last_shot_origin.y) <= 1:
		return false

	if kuru_container != null:
		for kuru_node in kuru_container.get_children():
			var kd: Dictionary = kuru_node.data
			if int(kd.get("player", -1)) != 1:
				continue
			if int(kd.get("muki", Enums.Muki.DOWN)) != facing:
				continue
			var kx: int = int(kd.get("bomb_x", kd.get("masu_x", -9999)))
			var ky: int = int(kd.get("bomb_y", kd.get("masu_y", -9999)))
			if abs(kx - origin.x) + abs(ky - origin.y) <= 1:
				return false

	return true


# ============================================================
# _record_com_shot()
# ============================================================
func _record_com_shot(me: Dictionary) -> void:
	_com_last_shot_frame  = Engine.get_process_frames()
	_com_last_shot_muki   = int(me.get("muki", Enums.Muki.DOWN))
	_com_last_shot_origin = Vector2i(int(me.get("masu_x", 0)), int(me.get("masu_y", 0)))
