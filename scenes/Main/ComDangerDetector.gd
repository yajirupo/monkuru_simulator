# scenes/Main/ComDangerDetector.gd
class_name ComDangerDetector
extends Node

# ====================================================================
#  COM の危険予測・危険度マップ管理クラス
#
#  【役割】
#   フィールド上の爆弾 (Bomb) と くる (Kuru) の爆発予測を行い、
#   各マスの「被弾開始までのフレーム数」を計算して危険度マップとして保持する。
#
#  【主な機能】
#   ・既存の爆弾の危険情報を参照し、危険マップに登録する
#   ・くるが現在の爆弾の爆風に巻き込まれて早期爆発するかどうかを判定する
#   ・くるが壁に衝突して早期爆発、または寿命で爆発する場合の爆発位置と時刻を計算する
#   ・得られた爆発を危険マップに反映する
#
#  【危険度マップのデータ構造】
#   _danger_map[x][y] : int
#     9999  → 安全（被弾しない）
#        0  → 現在すでに危険（当たり判定が存在する）
#       >0  → そのフレーム数後に爆風の当たり判定が発生し始める
#
#  【定数】
#   DANGER_FRAME_THRESHOLD : このフレーム数以内に被弾し始めるマスを「危険」と判定する閾値
#   EARLY_EXPLOSION_THRESHOLD : 壁衝突時に爆発する残り寿命の閾値 (180 フレーム)
#
#  【注意】
#   くる同士の連鎖誘爆は考慮しない（計算量削減のため）。爆弾との誘爆のみ判定する。
# ====================================================================

# --- 危険度マップ本体（外部から問い合わせ可能） ---
var _danger_map: Array = []          # 座標系: [x][y] (x: 0..17, y: 0..11)

# --- 外部から注入されるコンテナ ---
var _bomb_container: Node = null     # 爆弾ノードの親
var _kuru_container: Node = null     # くるノードの親
var _field_masu: Array = []          # フィールドのマス情報 (壁かどうかなど)

# --- 危険判定の閾値（被弾開始までの猶予フレーム） ---
const DANGER_FRAME_THRESHOLD: int = 60   # 1 秒以内に被弾し始めるなら「危険」とみなす

# --- 壁衝突による早期爆発の閾値 ---
const EARLY_EXPLOSION_THRESHOLD: int = 3 * Constants.KURU_DANKAI_TIME  # 180 フレーム


# ====================================================================
#  初期化
# ====================================================================
func initialize(field_masu: Array) -> void:
	_field_masu = field_masu
	_reset_map()


# --------------------------------------------------------------------
# 危険度マップを全マス 9999 (安全) でリセットする
# --------------------------------------------------------------------
func _reset_map() -> void:
	_danger_map.clear()
	for x in range(Constants.FIELD_COLS):
		var col: Array = []
		col.resize(Constants.FIELD_ROWS)
		col.fill(9999)        # 9999 = 安全
		_danger_map.append(col)


# ====================================================================
#  メインエントリ：毎フレーム呼ばれる
# ====================================================================
#  処理の流れ：
#   1. 既存の爆弾 (Bomb) を危険マップに登録する
#   2. 各くるについて、危険マップを参照しながら爆発判定を行い、
#      その爆発を逐次に危険マップに追加する
#   3. くるを踏んで自爆することを防ぐため、赤くなりかけているくる周辺のマスの危険度を超高くする
# ====================================================================
func build_event_list(bomb_container: Node, kuru_container: Node) -> void:
	_bomb_container = bomb_container
	_kuru_container = kuru_container
	_reset_map()

	# 1. 既存 Bomb の危険を危険マップに登録
	if _bomb_container:
		for bomb in _bomb_container.get_children():
			_register_bomb_danger(bomb)

	# 2. 各くるの爆発を計算し、危険マップに反映
	#    （危険マップは逐次更新され、後続のくるの誘爆判定にも使われる）
	if _kuru_container:
		for _pass in range(5): # 誘爆を 5 段階まで考慮
			for kuru in _kuru_container.get_children():
				# くるの爆発計算（現在の危険マップ全体を参照し、爆弾＋既に計算したくるの爆発を考慮）
				var explosion = _compute_kuru_explosion(kuru, _danger_map)
				if not explosion.is_empty():
					_register_kuru_explosion(explosion["bomb_x"], explosion["bomb_y"],
											explosion["power"], explosion["explosion_frame"])
	
	# 3. くるを踏んで自爆してしまうことの抑制
	if _kuru_container:
		for kuru in _kuru_container.get_children():
			var kd: Dictionary = kuru.data			
			# 爆発まで3秒（触れると即爆発する状態）
			if kd["count"] < 3 * Constants.KURU_DANKAI_TIME:
				# 現在くるがいるマスを即危険に設定（踏むの防止）
				var mx: int = kd["masu_x"]
				var my: int = kd["masu_y"]
				if Utility.is_walkable_cell(mx, my):
					if _danger_map[mx][my] > 1:
						_danger_map[mx][my] = 1
				
				# 爆心地マスを即危険に設定（踏んじゃったときの即死防止）
				var bx: int = kd["bomb_x"]
				var by: int = kd["bomb_y"]
				if Utility.is_walkable_cell(bx, by):
					if _danger_map[bx][by] > 9:
						_danger_map[bx][by] = 9


# --------------------------------------------------------------------
# 既存の爆弾 (Bomb) を危険マップに登録する
# count 値に応じて被弾開始フレームを計算してマップに記録する
# --------------------------------------------------------------------
func _register_bomb_danger(bomb: Node) -> void:
	if not bomb.has_method("get_data") and not "data" in bomb:
		return
	var data: Dictionary = bomb.data
	var bx: int = data["masu_x"]
	var by: int = data["masu_y"]
	if bx < 0 or bx >= Constants.FIELD_COLS or by < 0 or by >= Constants.FIELD_ROWS:
		return
	var count: int = data["count"]
	# count が BOMB_SPREAD_TIME を超えている爆弾はすでに消えているので無視
	if count > Constants.BOMB_SPREAD_TIME:
		return
	# count の符号から被弾開始フレームを計算（負の値なら未来、正の値なら現在危険）
	var start_frame: int = -count if count < 0 else 0

	# そのマスの既存の値より早い開始なら更新
	if start_frame < _danger_map[bx][by]:
		_danger_map[bx][by] = start_frame


# ====================================================================
#  くる一体分の爆発予測（このクラスの中核）
#
#  【処理の流れ】
#   1. くるがすでに爆発寸前なら即爆発とみなす
#   2. 壁があるかどうかを実際の Kuru.gd と同じロジックで判定し、
#      衝突位置と衝突フレームを求める
#   3. 爆弾専用マップと照合し、くるが移動経路上で被弾するか調べる
#      被弾した場合は被弾フレーム + 1 を爆発フレーム候補とする
#   4. 引火がなければ、壁衝突 or 寿命で爆発するタイミングを決定する
#   5. 最終的な爆発フレームと爆心地 (bomb_x, bomb_y) を返す
#
#  【引火判定の詳細】
#   くるの将来の移動経路を辿り、各区間のマスが爆弾の危険に曝される時間帯と重なるか調べる。
#   重なっていれば、そのマスに入った瞬間 or 爆風が到達した瞬間のうち遅い方で被弾し、
#   次のフレームで爆発するとみなす。
# ====================================================================
func _compute_kuru_explosion(kuru: Node, danger_map: Array) -> Dictionary:
	if not kuru.has_method("get_data") and not "data" in kuru:
		return {}
	var data: Dictionary = kuru.data

	# --- すでに爆発する場合 ---
	if data["count"] <= 0:
		var pos = Utility.kuru_bomb_center(data["x"], data["y"], data["muki"])
		return {"bomb_x": pos.x, "bomb_y": pos.y, "power": data["power"], "explosion_frame": 0}

	# 基本パラメータ
	var start_x: int = data["x"]
	var start_y: int = data["y"]
	var move_muki: int = data["move_muki"]   # 移動方向
	var muki: int = data["muki"]             # 向き（爆心地計算用）
	var speed: int = data["speed"]
	var count: int = data["count"]
	var power: int = data["power"]

	var natural_lifespan: int = count   # 寿命
	var move_per_frame: int = speed
	if move_per_frame == 0:
		move_per_frame = 1 # 0 はやばいので嘘でもいいから 1 ってことにする（ヘバ対策）

	# ----- 壁衝突の判定（最適化版：マス探索 + 距離 → フレーム計算） -----
	var collision_x: int = 0
	var collision_y: int = 0
	var collision_frame: int = 999999
	var has_wall: bool = false

	# 移動方向に応じて最初の非歩行マス（ハードブロック or 範囲外）を調べる
	var first_block_cell: int = -1       # その方向でのマス座標（列または行）

	# 現在のマス座標（中心）
	var current_cell := Utility.world_to_cell(start_x, start_y)
	var cur_masu_x: int = current_cell.x
	var cur_masu_y: int = current_cell.y

	var scan_x: int = cur_masu_x
	var scan_y: int = cur_masu_y

	match move_muki:
		Enums.Muki.RIGHT:
			# 右方向にスキャン（非歩行マス=ハードブロック or 範囲外）
			while Utility.is_walkable_cell(scan_x + 1, cur_masu_y):
				scan_x += 1
			first_block_cell = scan_x + 1
			has_wall = true
			if first_block_cell >= Constants.FIELD_COLS:
				# マップ端（MAP_SIZE_X）を右端とみなす
				var dist: int = Constants.MAP_SIZE_X - start_x
				collision_frame = Utility.calc_collision_frames(dist, move_per_frame, false)
				collision_x = Constants.MAP_SIZE_X
				collision_y = start_y
			else:
				# ハードブロックのマスに入る手前で停止する条件
				var trigger_x: int = first_block_cell * 320 - 319
				var dist: int = trigger_x - start_x
				collision_frame = Utility.calc_collision_frames(dist, move_per_frame, true)
				collision_x = first_block_cell * 320 - 320
				collision_y = start_y

		Enums.Muki.LEFT:
			while Utility.is_walkable_cell(scan_x - 1, cur_masu_y):
				scan_x -= 1
			first_block_cell = scan_x - 1
			has_wall = true
			if first_block_cell < 0:
				var dist: int = start_x
				collision_frame = Utility.calc_collision_frames(dist, move_per_frame, false)
				collision_x = 0
				collision_y = start_y
			else:
				var trigger_x: int = (first_block_cell + 1) * 320
				var dist: int = start_x - trigger_x
				collision_frame = Utility.calc_collision_frames(dist, move_per_frame, false)
				collision_x = (first_block_cell + 1) * 320
				collision_y = start_y

		Enums.Muki.DOWN:
			while Utility.is_walkable_cell(cur_masu_x, scan_y + 1):
				scan_y += 1
			first_block_cell = scan_y + 1
			has_wall = true
			if first_block_cell >= Constants.FIELD_ROWS:
				var dist: int = Constants.MAP_SIZE_Y - start_y
				collision_frame = Utility.calc_collision_frames(dist, move_per_frame, false)
				collision_x = start_x
				collision_y = Constants.MAP_SIZE_Y
			else:
				var trigger_y: int = first_block_cell * 320 - 319
				var dist: int = trigger_y - start_y
				collision_frame = Utility.calc_collision_frames(dist, move_per_frame, true)
				collision_x = start_x
				collision_y = first_block_cell * 320 - 320

		Enums.Muki.UP:
			while Utility.is_walkable_cell(cur_masu_x, scan_y - 1):
				scan_y -= 1
			first_block_cell = scan_y - 1
			has_wall = true
			if first_block_cell < 0:
				var dist: int = start_y
				collision_frame = Utility.calc_collision_frames(dist, move_per_frame, false)
				collision_x = start_x
				collision_y = 0
			else:
				var trigger_y: int = (first_block_cell + 1) * 320
				var dist: int = start_y - trigger_y
				collision_frame = Utility.calc_collision_frames(dist, move_per_frame, false)
				collision_x = start_x
				collision_y = (first_block_cell + 1) * 320

	# 寿命（natural_lifespan）より先なら壁衝突は無効
	if has_wall and collision_frame >= natural_lifespan:
		has_wall = false
		collision_frame = 999999

	# ----- 爆弾による引火判定 -----
	var chain_explosion_frame: int = 999999   # 引火爆発までのフレーム（大きい値で初期化）
	var cur_t: int = 0
	var cur_x: int = start_x
	var cur_y: int = start_y
	var moving: bool = true

	# くるの移動経路を区間に区切って、各マスで爆弾の危険と重ならないか調べる
	while cur_t < natural_lifespan and moving:
		# 現在いるマス
		var cur_cell := Utility.world_to_cell(cur_x, cur_y)
		var masu_x: int = cur_cell.x
		var masu_y: int = cur_cell.y

		# 次のセル境界または壁衝突までの時刻 next_t を求める
		var next_t: int = natural_lifespan
		if has_wall and collision_frame > cur_t:
			next_t = mini(next_t, collision_frame)

		if move_muki == Enums.Muki.RIGHT or move_muki == Enums.Muki.LEFT:
			@warning_ignore("integer_division")
			var cell = (cur_x + 160) / 320
			var boundary: int
			if move_muki == Enums.Muki.RIGHT:
				boundary = (cell + 1) * 320 - 160
				if boundary > cur_x:
					@warning_ignore("integer_division")
					var t_boundary = cur_t + (boundary - cur_x + move_per_frame - 1) / move_per_frame
					if t_boundary < next_t:
						next_t = t_boundary
			else:
				boundary = cell * 320 - 160
				if boundary < cur_x:
					@warning_ignore("integer_division")
					var t_boundary = cur_t + (cur_x - boundary + move_per_frame - 1) / move_per_frame
					if t_boundary < next_t:
						next_t = t_boundary
		else:
			@warning_ignore("integer_division")
			var cell = (cur_y + 160) / 320
			var boundary: int
			if move_muki == Enums.Muki.DOWN:
				boundary = (cell + 1) * 320 - 160
				if boundary > cur_y:
					@warning_ignore("integer_division")
					var t_boundary = cur_t + (boundary - cur_y + move_per_frame - 1) / move_per_frame
					if t_boundary < next_t:
						next_t = t_boundary
			else:
				boundary = cell * 320 - 160
				if boundary < cur_y:
					@warning_ignore("integer_division")
					var t_boundary = cur_t + (cur_y - boundary + move_per_frame - 1) / move_per_frame
					if t_boundary < next_t:
						next_t = t_boundary

		# この区間内に爆弾の危険があるか調べる
		var t_enter: int = cur_t          # 区間開始フレーム
		var t_exit: int = next_t - 1      # 区間終了フレーム（次の境界の直前）
		if t_enter <= t_exit:
			if masu_x >= 0 and masu_x < Constants.FIELD_COLS and masu_y >= 0 and masu_y < Constants.FIELD_ROWS:
				var respite: int = danger_map[masu_x][masu_y]   # そのマスの被弾開始フレーム
				if respite != 9999:
					var danger_start: int = respite
					var danger_end: int = respite + Constants.BOMB_SPREAD_TIME
					# 区間と危険時間に重なりがあるか
					if t_enter <= danger_end and t_exit >= danger_start:
						var hit_frame: int = maxi(t_enter, danger_start)
						# 被弾したフレーム + 1 で爆発（誘爆は次のフレーム）
						chain_explosion_frame = mini(chain_explosion_frame, hit_frame + 1)

		cur_t = next_t
		# 壁に到達したら移動停止
		if has_wall and cur_t >= collision_frame:
			moving = false
			cur_x = collision_x
			cur_y = collision_y
		elif moving:
			# 次の位置を計算（各方向に応じて座標を進める）
			var elapsed: int = cur_t
			var d = Utility.dir_to_vec(move_muki)
			cur_x = start_x + d.x * move_per_frame * elapsed
			cur_y = start_y + d.y * move_per_frame * elapsed

	# 壁に停止後も、寿命まで同じマスにいるので危険チェック
	if not moving and has_wall:
		var stop_cell := Utility.world_to_cell(collision_x, collision_y)
		var stop_masu_x: int = stop_cell.x
		var stop_masu_y: int = stop_cell.y
		var t_stop_start: int = collision_frame
		var t_stop_end: int = natural_lifespan - 1
		if t_stop_start <= t_stop_end:
			if stop_masu_x >= 0 and stop_masu_x < Constants.FIELD_COLS and stop_masu_y >= 0 and stop_masu_y < Constants.FIELD_ROWS:
				var respite: int = danger_map[stop_masu_x][stop_masu_y]
				if respite != 9999:
					var danger_start: int = respite
					var danger_end: int = respite + Constants.BOMB_SPREAD_TIME
					if t_stop_start <= danger_end and t_stop_end >= danger_start:
						var hit_frame: int = maxi(t_stop_start, danger_start)
						chain_explosion_frame = mini(chain_explosion_frame, hit_frame + 1)

	# ----- 最終的な爆発フレームと位置の決定 -----
	# デフォルトは寿命で爆発
	var explosion_frame: int = natural_lifespan

	# 壁衝突時の特殊処理（引火していなければ）
	if has_wall and chain_explosion_frame > natural_lifespan:
		var remaining_at_collision: int = natural_lifespan - collision_frame
		if remaining_at_collision < EARLY_EXPLOSION_THRESHOLD:
			# 残り寿命が 3 秒未満 → 衝突と同時に即爆発
			explosion_frame = collision_frame
		else:
			# 寿命が長い → 壁に張り付き、残り寿命が 3 秒になった瞬間に爆発
			explosion_frame = natural_lifespan - EARLY_EXPLOSION_THRESHOLD

	# 引火の方が早ければそれを採用
	if chain_explosion_frame < explosion_frame:
		explosion_frame = chain_explosion_frame

	# ----- 爆発位置 (bomb_x, bomb_y) の計算 -----
	var bomb_x: int
	var bomb_y: int
	if explosion_frame == 0:
		# 即時爆発の場合は現在のデータから計算
		var center = Utility.kuru_bomb_center(data["x"], data["y"], data["muki"])
		bomb_x = center.x
		bomb_y = center.y
	else:
		# 爆発する瞬間の座標を求める
		var ex: int
		var ey: int
		if (not has_wall) or explosion_frame < collision_frame:
			# 移動中に爆発するケース
			var elapsed: int = explosion_frame
			var dir_vec := Utility.dir_to_vec(move_muki)
			ex = start_x + dir_vec.x * move_per_frame * elapsed
			ey = start_y + dir_vec.y * move_per_frame * elapsed
		else:
			# 壁で停止後に爆発
			ex = collision_x
			ey = collision_y

		# 向き (muki) に応じて爆心地セルを計算（Kuru.gd と同一ロジック）
		var bomb_center := Utility.kuru_bomb_center(ex, ey, muki)
		bomb_x = bomb_center.x
		bomb_y = bomb_center.y

	# フィールド範囲内にクランプ（安全策）
	bomb_x = clampi(bomb_x, 0, Constants.FIELD_COLS - 1)
	bomb_y = clampi(bomb_y, 0, Constants.FIELD_ROWS - 1)
	
	return {"bomb_x": bomb_x, "bomb_y": bomb_y, "power": power, "explosion_frame": explosion_frame}


# ====================================================================
#  爆発を危険マップに反映する関数群
# ====================================================================

# くるの爆発を中心と十字方向に展開して危険マップに登録する
func _register_kuru_explosion(cx: int, cy: int, power: int, explosion_frame: int) -> void:
	# 範囲外なら何もしない
	if cx < 0 or cx >= Constants.FIELD_COLS or cy < 0 or cy >= Constants.FIELD_ROWS:
		return
	
	# 中心
	_register_bomb_at(cx, cy, 0, explosion_frame)
	# 十字方向（壁で遮られるまで）
	var dirs: Array = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for d in dirs:
		for i in range(1, power + 1):
			var nx: int = cx + d.x * i
			var ny: int = cy + d.y * i
			if nx < 0 or nx >= Constants.FIELD_COLS or ny < 0 or ny >= Constants.FIELD_ROWS:
				break
			if !Utility.is_walkable_cell(nx, ny):
				break
			_register_bomb_at(nx, ny, i, explosion_frame)

# 単一の爆風マスを危険マップに記録する
func _register_bomb_at(mx: int, my: int, distance: int, base_frame: int) -> void:
	# 爆発中心からの距離に応じて爆風到達が遅れる (BOMB_SPREAD_TIME ごとに 1 マス拡大)
	var start_frame: int = base_frame + (2 + distance) * Constants.BOMB_SPREAD_TIME
	if start_frame < _danger_map[mx][my]:
		_danger_map[mx][my] = start_frame


# ====================================================================
#  危険度マップの問い合わせ（COM の意思決定で使用）
# ====================================================================

# そのマスが「危険」（近い将来被弾する）かどうか
func is_cell_danger(x: int, y: int) -> bool:
	if x < 0 or x >= Constants.FIELD_COLS or y < 0 or y >= Constants.FIELD_ROWS:
		return false
	return _danger_map[x][y] <= DANGER_FRAME_THRESHOLD
	
# そのマスが「永続安全」（当たり判定の発生の予定なし）かどうか
func is_cell_eternally_safe(x: int, y: int) -> bool:
	if x < 0 or x >= Constants.FIELD_COLS or y < 0 or y >= Constants.FIELD_ROWS:
		return false
	return _danger_map[x][y] >= 9999
	
# 指定マスの被弾開始フレームを返す（安全なら 9999）
func hit_frame_from_events(x: int, y: int) -> int:
	if x < 0 or x >= Constants.FIELD_COLS or y < 0 or y >= Constants.FIELD_ROWS:
		return 9999
	return _danger_map[x][y]

# デバッグオーバーレイ用に危険度マップのコピーを返す
func get_danger_grid() -> Array:
	var copy: Array = []
	for x in range(Constants.FIELD_COLS):
		var col: Array = []
		col.assign(_danger_map[x].duplicate())
		copy.append(col)
	return copy
