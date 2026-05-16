# scenes/Main/ComChainAttacker.gd
class_name ComChainAttacker
extends RefCounted

# ====================================================================
#  連鎖攻撃の管理クラス
#
#  【役割】
#   「永続安全地点から隣接する危険マスへくるを打ち込み、
#    爆風で誘爆させる」連鎖攻撃の判定処理をまとめる。
#
#  【主な公開メソッド】
#   initialize(danger_detector)              : 初期化
#   get_chain_dir(player_num, dir_order)     : 誘爆可能な方向を返す（なければ -1）
#   get_safe_neighbor_dir(pnum, ex, order)   : 除外方向以外の安全隣接方向を返す
#
#  【設計メモ】
#   ・1 マス先での誘爆を優先し、不可能な場合のみ 2 マス先をチェックする
#   ・誘爆が 6 フレーム以内に起こる場合は自爆防止のため除外
#   ・誘爆が MAX_CHAIN_HIT_FRAME を超える未来なら意味が薄いため除外
# ====================================================================

var _danger_detector: ComDangerDetector

const MAX_CHAIN_HIT_FRAME: int = 90  # 誘爆が有効な未来の限界フレーム


func initialize(danger_detector: ComDangerDetector) -> void:
	_danger_detector = danger_detector


# ====================================================================
# 公開メソッド
# ====================================================================

## 誘爆が狙える方向を返す。なければ -1
## dir_order : ComThinkRoutine の _dir_order をそのまま渡す
func get_chain_dir(player_num: int, dir_order: Array) -> int:
	var p: Dictionary = GameState.player[player_num]
	var mx: int = p["masu_x"]
	var my: int = p["masu_y"]

	# COM の現在地が永続安全でなければ何もしない
	if _danger_detector.hit_frame_from_events(mx, my) < 9999:
		return -1

	var move_per_frame: int
	if p["cr_item_use"] == Enums.ItemType.ROCKET:
		move_per_frame = Constants.KURU_ROCKET_SPEED
	else:
		move_per_frame = p["kuru_speed"]
	move_per_frame = maxi(int(move_per_frame), 0)
	if move_per_frame <= 0:
		return -1  # 遅すぎて誘爆に向かない

	# 1 マスを通過するのに要するフレーム数（端数は切り上げ）
	var cell_time: int = ceili(320.0 / move_per_frame)

	var px: int = p["x"]  # 0.1px 単位の現在位置
	var py: int = p["y"]

	# --- 1 マス先（隣接セル）での誘爆を全方向チェック ---
	for d in dir_order:
		var nx1: int = mx + Utility.dx_from_dir(d)
		var ny1: int = my + Utility.dy_from_dir(d)
		if not Utility.is_walkable_cell(nx1, ny1):
			continue

		var entry1: int = _frames_to_cell_entry(d, px, py, mx, my, move_per_frame)
		if entry1 < 0:
			continue

		# 隣接セルから先が歩行可能なら、そこを出る時間も考慮
		var nx2: int = mx + 2 * Utility.dx_from_dir(d)
		var ny2: int = my + 2 * Utility.dy_from_dir(d)
		var exit1: int = entry1 + cell_time - 1 if Utility.is_walkable_cell(nx2, ny2) else 999999

		var hit1: int = _danger_detector.hit_frame_from_events(nx1, ny1)
		if hit1 == 9999:
			continue

		# 誘爆発生フレーム（くるの存在と危険が重なる最初のフレーム）
		var exp_frame: int = maxi(entry1, hit1)
		if exp_frame > 6 and _is_chain_overlap(entry1, exit1, hit1):
			return d  # 1 マス先で誘爆可能な方向を発見

	# --- 1 マス先で誘爆不可だった場合のみ、2 マス先をチェック ---
	for d in dir_order:
		var nx1: int = mx + Utility.dx_from_dir(d)
		var ny1: int = my + Utility.dy_from_dir(d)
		if not Utility.is_walkable_cell(nx1, ny1):
			continue

		var nx2: int = mx + 2 * Utility.dx_from_dir(d)
		var ny2: int = my + 2 * Utility.dy_from_dir(d)
		if not Utility.is_walkable_cell(nx2, ny2):
			continue

		var entry1: int = _frames_to_cell_entry(d, px, py, mx, my, move_per_frame)
		if entry1 < 0:
			continue
		var entry2: int = entry1 + cell_time

		# 2 マス先から先が歩行可能なら退室時間も考慮
		var nx3: int = mx + 3 * Utility.dx_from_dir(d)
		var ny3: int = my + 3 * Utility.dy_from_dir(d)
		var exit2: int = entry2 + cell_time - 1 if Utility.is_walkable_cell(nx3, ny3) else 999999

		var hit2: int = _danger_detector.hit_frame_from_events(nx2, ny2)
		if hit2 == 9999:
			continue

		var exp_frame: int = maxi(entry2, hit2)
		if exp_frame > 6 and _is_chain_overlap(entry2, exit2, hit2):
			return d  # 2 マス先で誘爆可能

	return -1


## 安全な隣接マスの方向を返す（最初に見つかったもの）。なければ -1
## exclude_dir とその逆方向はスキップする（連鎖方向の軸を外す用途）
func get_safe_neighbor_dir(player_num: int, exclude_dir: int, dir_order: Array) -> int:
	var p: Dictionary = GameState.player[player_num]
	var mx: int = p["masu_x"]
	var my: int = p["masu_y"]
	for d in dir_order:
		if exclude_dir != -1 and (d == exclude_dir or d == Utility.opposite_dir(exclude_dir)):
			continue
		var nx: int = mx + Utility.dx_from_dir(d)
		var ny: int = my + Utility.dy_from_dir(d)
		if Utility.is_walkable_cell(nx, ny) and not _danger_detector.is_cell_danger(nx, ny):
			return d
	return -1


# ====================================================================
# プライベート：連鎖計算
# ====================================================================

## 指定方向へ 1 マス移動したとき、くるが「隣のマスへ進入開始する」までの
## 相対フレーム数を返す（現在位置からセル境界までの距離による）
func _frames_to_cell_entry(dir: int, x: int, y: int, mx: int, my: int, move_per_frame: int) -> int:
	var dist: int = 0
	match dir:
		0:  # 右
			dist = (mx + 1) * 320 - 160 - x
		1:  # 左
			dist = x - (mx * 320 - 160)
		2:  # 下
			dist = (my + 1) * 320 - 160 - y
		3:  # 上
			dist = y - (my * 320 - 160)
		_:
			return -1
	if dist <= 0:
		return 0  # すでに境界上
	return Utility.ceil_div(dist, move_per_frame)


## くるが滞在する時間 [entry, exit] と、危険時間 [hit, hit+BOMB_SPREAD_TIME-1] が
## 重なっているかどうか。危険開始が MAX_CHAIN_HIT_FRAME を超えていたら無効。
func _is_chain_overlap(entry: int, exit: int, hit: int) -> bool:
	if hit > MAX_CHAIN_HIT_FRAME:
		return false
	var danger_start: int = hit
	var danger_end: int = hit + Constants.BOMB_SPREAD_TIME
	# 重なり条件: not (exit < danger_start or entry > danger_end)
	return (exit >= danger_start) and (entry <= danger_end)
