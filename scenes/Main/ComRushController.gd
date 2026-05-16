# scenes/Main/ComRushController.gd
class_name ComRushController
extends RefCounted

# ====================================================================
#  ラッシュ行動の管理クラス
#
#  【役割】
#   スピード靴を使って一直線に突撃しながらくるを連射する
#   「ラッシュ」行動の開始判定・継続処理・終了をまとめて担う。
#
#  【主な公開メソッド】
#   initialize(danger_detector)  : 初期化（setup() 前に呼ぶ）
#   setup_game()                 : ゲーム開始時の状態初期化
#   reset()                      : ゲームリセット時の状態初期化
#   is_active() -> bool          : ラッシュ中かどうか
#   get_dir() -> int             : 現在のラッシュ方向（非アクティブ時は -1）
#   should_start_rush(pnum, op)  : ラッシュ開始条件を満たすか
#   can_safely_rush(dir)         : 指定方向への突撃が安全か
#   start_rush(dir)              : ラッシュを開始する
#   process_rush(keys, pnum)     : ラッシュ中キーを keys に書き込み
#                                  {"phase","reason"} を返す
#   cancel_rush()                : 強制中断（被弾時など）
# ====================================================================

var _danger_detector: ComDangerDetector

# ---- 内部状態 ----
var _rush_active: bool = false
var _rush_dir: int = -1
var _rush_last_shot_cell: Vector2i = Vector2i(-1, -1)   # 最後に発射したマスのセル座標

const BOMB_KEY: int = 4


func initialize(danger_detector: ComDangerDetector) -> void:
	_danger_detector = danger_detector


func reset() -> void:
	_rush_active = false
	_rush_dir = -1
	_rush_last_shot_cell = Vector2i(-1, -1)


func is_active() -> bool:
	return _rush_active


func get_dir() -> int:
	return _rush_dir


# ====================================================================
# ラッシュ開始判定
# ====================================================================

## ラッシュ開始条件を満たすか
func should_start_rush(player_num: int, op_estimated: Dictionary) -> bool:
	var p: Dictionary = GameState.player[player_num]
	if p["kuru_kankaku"] != 0:  # 発射間隔が 0.0 秒でないとラッシュはできない
		return false
	if p["kuru_speed"] >= Constants.kuru_speed_stat_to_move_speed(3):  # 速すぎるくるはラッシュに不向き
		return false
	if p["item_shot"] - p["shot_kuru"] < 3:  # 3 個は即置けないと最初に隙間が空きそう
		return false
	if p["cr_item_use"] == Enums.ItemType.ROCKET:  # スピード靴以外のアイテム使用中はラッシュ不可
		return false
	if p["cr_item_use"] == Enums.ItemType.INVISIBLE:
		return false
	if p["cr_item_use"] == Enums.ItemType.BROTHER:
		return false

	# 前方 1 マスの被弾開始フレームが 40 未満なら引火しそうなのでラッシュのチャンス
	var front: Vector2i = Utility.get_front_cell(p, p["muki"])
	if front.x >= 0 and front.x < Constants.FIELD_COLS and front.y >= 0 and front.y < Constants.FIELD_ROWS:
		var hit_frame: int = _danger_detector.hit_frame_from_events(front.x, front.y)
		if hit_frame <= 10 or hit_frame >= 40:
			return false

	var rush_dir: int = p["muki"]
	if not _rush_can_hit_opponent(rush_dir, op_estimated):
		return false
	if not _rush_opponent_trapped(rush_dir, op_estimated):
		return false
	return true


## 指定方向へのラッシュが安全に実行可能か検証する
func can_safely_rush(dir: int) -> bool:
	var p: Dictionary = GameState.player[1]
	var start_x: int = p["x"]
	var start_y: int = p["y"]
	var masu_x: int = p["masu_x"]
	var masu_y: int = p["masu_y"]
	var cr_item_count: int = p["cr_item_count"]

	# スピード靴未使用の場合は、即使用したと仮定して判定
	if cr_item_count <= 0:
		cr_item_count = 360

	var move_per_frame: int = Constants.SHOES_SPEED

	var step := Utility.dir_to_vec(dir)
	var dx: int = step.x
	var dy: int = step.y

	# 壁に当たるまでの通過セルをリスト化
	var cells_to_traverse: Array[Vector2i] = []
	var cur_cell := Vector2i(masu_x, masu_y)
	cells_to_traverse.append(cur_cell)
	var next_cell := cur_cell
	while true:
		next_cell = Vector2i(next_cell.x + dx, next_cell.y + dy)
		if not Utility.is_walkable_cell(next_cell.x, next_cell.y):
			break
		cells_to_traverse.append(next_cell)

	if cells_to_traverse.size() <= 1:
		return false  # すでに壁際

	# 各セルへの進入フレームを計算
	var entry_frames: Array[int] = []
	entry_frames.append(0)  # 現在地

	var time_per_full_cell: int = ceili(320.0 / move_per_frame) + 1  # 移動 ＋ ショット

	if dx != 0:
		var dist_to_next: int
		if dx > 0:
			dist_to_next = (masu_x + 1) * 320 - start_x
		else:
			dist_to_next = start_x - (masu_x - 1) * 320
		var frames_to_first_boundary: int = ceili(float(dist_to_next) / move_per_frame)
		var next_entry_frame: int = frames_to_first_boundary + 1
		for i in range(1, cells_to_traverse.size()):
			entry_frames.append(next_entry_frame + (i - 1) * time_per_full_cell)
	else:  # dy != 0
		var dist_to_next: int
		if dy > 0:
			dist_to_next = (masu_y + 1) * 320 - start_y
		else:
			dist_to_next = start_y - (masu_y - 1) * 320
		var frames_to_first_boundary: int = ceili(float(dist_to_next) / move_per_frame)
		var next_entry_frame: int = frames_to_first_boundary + 1
		for i in range(1, cells_to_traverse.size()):
			entry_frames.append(next_entry_frame + (i - 1) * time_per_full_cell)

	var total_frames_needed: int = entry_frames[entry_frames.size() - 1]
	if total_frames_needed > cr_item_count:
		return false

	# 各セル進入タイミングでの危険度チェック
	for i in range(cells_to_traverse.size()):
		var cell: Vector2i = cells_to_traverse[i]
		var hit_frame: int = _danger_detector.hit_frame_from_events(cell.x, cell.y)
		if hit_frame <= entry_frames[i]:
			return false  # 到着時すでに被弾、または被弾と同時

	# 最後のセルに到達した後、しばらく滞在できるマージンを見る
	var last_cell: Vector2i = cells_to_traverse[cells_to_traverse.size() - 1]
	var last_cell_hit_frame: int = _danger_detector.hit_frame_from_events(last_cell.x, last_cell.y)
	if last_cell_hit_frame <= total_frames_needed + time_per_full_cell:
		# 壁到着後すぐに被弾し始めるなら安全とは言えない
		return false

	return true


# ====================================================================
# ラッシュ実行
# ====================================================================

## ラッシュ開始処理（_recent_shots のクリアは呼び出し側で行う）
func start_rush(dir: int) -> void:
	_rush_active = true
	_rush_dir = dir
	_rush_last_shot_cell = Vector2i(-1, -1)   # 初回フレームで必ず発射させる


## ラッシュ中のキー生成。keys を直接変更し {"phase", "reason"} を返す
func process_rush(keys: Array, player_num: int) -> Dictionary:
	var p: Dictionary = GameState.player[player_num]

	# 移動キー
	keys[_rush_dir] = true

	# 現在のマス座標
	var current_cell := Vector2i(p["masu_x"], p["masu_y"])
	var shot_fired_this_frame: bool = false

	# 発射判断：初回、または前回発射マスと異なるマスに移動したとき
	if _rush_last_shot_cell == Vector2i(-1, -1) or current_cell != _rush_last_shot_cell:
		keys[BOMB_KEY] = true
		_rush_last_shot_cell = current_cell
		shot_fired_this_frame = true

	# ラッシュ終了条件：_rush_last_shot_cell が壁の1歩手前のマスになったら終了
	if shot_fired_this_frame:
		var dx: int = Utility.dx_from_dir(_rush_dir)
		var dy: int = Utility.dy_from_dir(_rush_dir)
		var next_cell := Vector2i(_rush_last_shot_cell.x + dx, _rush_last_shot_cell.y + dy)
		if not Utility.is_walkable_cell(next_cell.x, next_cell.y):
			_rush_active = false
			_rush_dir = -1

	# ------------------------------------------------------------
	# 追加：危険予測による中断
	# このまま直進して次のマスに入った瞬間に被弾が始まる or すでに
	# 危険な場合はラッシュを中断する
	# ------------------------------------------------------------
	if _rush_active:
		var next_cell := Vector2i(
			current_cell.x + Utility.dx_from_dir(_rush_dir),
			current_cell.y + Utility.dy_from_dir(_rush_dir)
		)
		# 壁などの通行不能マスは既存の壁チェックで対処済み
		if Utility.is_walkable_cell(next_cell.x, next_cell.y):
			# 現在の移動速度（ラッシュ中はスピード靴が前提）
			var move_per_frame: int = Constants.SHOES_SPEED

			# 次のセル境界までの距離 (0.1px) を計算
			var dist: int
			match _rush_dir:
				0: # 右
					dist = (current_cell.x + 1) * 320 - p["x"]
				1: # 左
					dist = p["x"] - current_cell.x * 320
				2: # 下
					dist = (current_cell.y + 1) * 320 - p["y"]
				3: # 上
					dist = p["y"] - current_cell.y * 320
				_:
					dist = 0

			dist = maxi(0, dist)  # 境界誤差対策
			var entry_frames: int = ceili(float(dist) / move_per_frame)

			# そのセルがいつから危険になるか
			var hit_frame: int = _danger_detector.hit_frame_from_events(next_cell.x, next_cell.y)
			# 到着時点ですでに被弾が始まっている（hit_frame <= 到着フレーム）なら中断
			if hit_frame <= entry_frames:
				cancel_rush()   # 中断
				# 中断理由を明示して返す
				return {
					"phase": "RUSH_CANCEL",
					"reason": "Danger at next cell (%d,%d) in %d frames (rush cancelled)" % [next_cell.x, next_cell.y, hit_frame]
				}

	# 通常の継続（または壁衝突による自然終了）
	return { "phase": "RUSH", "reason": "Rush dir %d" % _rush_dir }


## 誰かが被弾した等でラッシュを強制中断する
func cancel_rush() -> void:
	if _rush_active:
		_rush_active = false
		_rush_dir = -1
		_rush_last_shot_cell = Vector2i(-1, -1)


# ====================================================================
# ラッシュ攻撃で相手に爆風が届くかどうかを検証
# rush_dir : COM の現在の向き（= ラッシュ方向）
# 戻り値   : 相手を攻撃可能なら true
# ====================================================================
func _rush_can_hit_opponent(rush_dir: int, op: Dictionary) -> bool:
	var p: Dictionary = GameState.player[1]
	var mx: int = p["masu_x"]
	var my: int = p["masu_y"]
	var ox: int = op["masu_x"]
	var oy: int = op["masu_y"]
	var power: int = p["item_power"]

	# ラッシュ経路上の全セルを取得
	var path_cells: Array[Vector2i] = []
	var cur_x: int = mx
	var cur_y: int = my
	while true:
		match rush_dir:
			0: cur_x += 1
			1: cur_x -= 1
			2: cur_y += 1
			3: cur_y -= 1
		if !Utility.is_walkable_cell(cur_x, cur_y):
			break
		path_cells.append(Vector2i(cur_x, cur_y))

	if path_cells.is_empty():
		return false  # すでに壁際ならラッシュできない

	# 相手が経路上どこかのセルの爆風範囲に入るか調べる
	for cell in path_cells:
		# 同一行チェック
		if cell.y == oy:
			var step: int = 1 if ox > cell.x else -1
			var dist: int = abs(ox - cell.x)
			if dist <= power:
				var blocked := false
				for x in range(cell.x + step, ox, step):
					if GameState.masu[x][cell.y]["kind"] == Enums.MasuKind.HARD_BLOCK:
						blocked = true
						break
				if not blocked:
					return true
		# 同一列チェック
		if cell.x == ox:
			var step: int = 1 if oy > cell.y else -1
			var dist: int = abs(oy - cell.y)
			if dist <= power:
				var blocked := false
				for y in range(cell.y + step, oy, step):
					if GameState.masu[cell.x][y]["kind"] == Enums.MasuKind.HARD_BLOCK:
						blocked = true
						break
				if not blocked:
					return true
	return false


# ====================================================================
# ラッシュ方向に対して相手が「壁際に追い詰められている」かどうか
#
# 縦ラッシュ (UP/DOWN) → 相手の x 座標が COM の列と左右の近い方の壁の間にある
# 横ラッシュ (LEFT/RIGHT) → 相手の y 座標が COM の行と上下の近い方の壁の間にある
# ====================================================================
func _rush_opponent_trapped(rush_dir: int, op: Dictionary) -> bool:
	var p: Dictionary = GameState.player[1]
	var com_x: int = p["masu_x"]
	var com_y: int = p["masu_y"]
	var op_x: int = op["masu_x"]
	var op_y: int = op["masu_y"]
	var power: int = p["item_power"]

	match rush_dir:
		2, 3:  # 縦方向 (DOWN/UP)
			var dist_left: int = com_x                              # 左壁までのマス数
			var dist_right: int = Constants.FIELD_COLS - 1 - com_x  # 右壁までのマス数
			if dist_left <= dist_right:
				# 左の壁が近い → 相手は COM より左側にいる必要がある
				if not (op_x < com_x):
					return false
				return com_x <= power
			else:
				# 右の壁が近い → 相手は COM より右側にいる必要がある
				if not (op_x > com_x):
					return false
				return (Constants.FIELD_COLS - 1 - com_x) <= power
		0, 1:  # 横方向 (RIGHT/LEFT)
			var dist_top: int = com_y
			var dist_bottom: int = Constants.FIELD_ROWS - 1 - com_y
			if dist_top <= dist_bottom:
				# 上の壁が近い → 相手は COM より上側にいる必要がある
				if not (op_y < com_y):
					return false
				return com_y <= power
			else:
				# 下の壁が近い → 相手は COM より下側にいる必要がある
				if not (op_y > com_y):
					return false
				return (Constants.FIELD_ROWS - 1 - com_y) <= power
	return false
