class_name ComPathfinder
extends RefCounted

# ── 方向優先順位シャッフル ──────────────────────────────────────
# 同スコアの移動先が複数あるとき、どの方向を優先するかを決める順序。
# DIR_SHUFFLE_INTERVAL フレームごとに再シャッフルすることで、
# 毎回同じ動きにならないようにする。
const DIR_SHUFFLE_INTERVAL := 60  # 約1秒（60fps想定）

var _dir_order: Array[int] = [0, 1, 2, 3]
var _last_dir_tick: int = -1

# 危険判定ユーティリティへの参照（コンストラクタで注入）
var _detector: ComDangerDetector


func _init(detector: ComDangerDetector) -> void:
	_detector = detector


# ============================================================
# refresh_dir_order()
#
# DIR_SHUFFLE_INTERVAL フレームごとに _dir_order をシャッフルする。
# ============================================================
func refresh_dir_order() -> void:
	@warning_ignore("integer_division")
	var tick: int = Engine.get_process_frames() / DIR_SHUFFLE_INTERVAL
	if tick != _last_dir_tick:
		_last_dir_tick = tick
		_dir_order.shuffle()


# ============================================================
# pick_escape_direction_bfs()
#
# pick_escape_quality() の薄いラッパー。移動方向（int）だけを返す。
# 既存の呼び出し側に変更を加えずに済む。
# ============================================================
func pick_escape_direction_bfs(start_x: int, start_y: int, bomb_container: Node, kuru_container: Node, move_frames: int = 1) -> int:
	return pick_escape_quality(start_x, start_y, bomb_container, kuru_container, move_frames)["dir"]


# ============================================================
# pick_escape_quality()  ── タイミング考慮型BFS脱出ルーティン（品質情報つき）
#
# 戻り値 Dictionary:
#   "dir"         : int  最善の移動方向（0〜3）。逃げ場がなければ -1
#   "is_safe"     : bool 真に安全な経路（到達時も含め爆風ゼロ）が存在するか
#   "path_margin" : int  経路上の最小余裕フレーム
#   "dest_fuh"    : int  目的地の hit_frame
#   "escape_path" : Array[Vector2i]  最良経路のマス列
#
# ■ 3段階の優先度（上ほど優先）
#   TIER 3 SAFE_DEST  : 経路安全 かつ 目的地が永久安全（SAFE_INF）
#                       → 最も近い（depth最小）を選ぶ。同距離なら余裕最大。
#   TIER 2 ROUTE_SAFE : 経路安全 かつ 目的地はいずれ爆風に巻き込まれる
#                       → dest_fuh が最大のものを選ぶ。
#   TIER 1 DESPERATE  : 爆風壁チェックなし。最も遅く被弾するマスへ。
#
# ■ 移動速度の考慮（move_frames パラメータ）
#   depth d マスへの到達フレーム = d * move_frames
#   hit_frame(sq) <= 到達フレーム なら通過不可（爆風壁として扱う）
#
# ■ ブロックチェック
#   GameState.masu[ny][nx] が BROKEN（空きマス）以外は通過不可。
# ============================================================
func pick_escape_quality(start_x: int, start_y: int, bomb_container: Node, kuru_container: Node, move_frames: int = 1) -> Dictionary:
	const DEPTH := 8                         # 探索深さ（マス数）
	const DIRS  := [[1, 0], [-1, 0], [0, 1], [0, -1]]
	# 優先度 tier 定数
	const TIER_SAFE_DEST  := 3  # 到達時も永久安全
	const TIER_ROUTE_SAFE := 2  # 経路は安全だが目的地はいずれ爆風
	const TIER_DESPERATE  := 1  # 爆風壁なし・最長生存
	var safe_inf: int = ComDangerDetector.SAFE_INF
	var dangerous_kuru_cells := _build_dangerous_kuru_cell_cache(kuru_container)

	# ── イベントリストを 1 回だけ構築 ─────────────────────────────────────
	var events: Array = _detector.build_event_list(bomb_container, kuru_container)

	# ── BFS キュー ────────────────────────────────────────────────────────
	# 要素: x, y, dir（最初の1歩）, depth, path_min_margin, path
	var queue: Array = []
	var best_margin_to: Dictionary = {}  # Vector2i → path_min_margin の最良値

	for di in range(4):
		var d: int = _dir_order[di]
		var nx: int = start_x + DIRS[d][0]
		var ny: int = start_y + DIRS[d][1]
		if not _is_walkable(nx, ny, dangerous_kuru_cells):
			continue
		var key   := Vector2i(nx, ny)
		var fuh:  int = _detector.hit_frame_from_events(nx, ny, events)
		var arr:  int = 1 * move_frames  # depth=1 での到達フレーム
		# 到達時に爆風 → 爆風壁としてスキップ
		if fuh < safe_inf and fuh <= arr:
			continue
		var margin: int = safe_inf if fuh >= safe_inf else (fuh - arr)
		if not best_margin_to.has(key) or margin > best_margin_to[key]:
			best_margin_to[key] = margin
			queue.append({
				"x": nx, "y": ny, "dir": d,
				"depth": 1, "path_min_margin": margin,
				"path": [key]
			})

	# ── 最良候補 ──────────────────────────────────────────────────────────
	var best_tier:       int   = 0
	var best_dir:        int   = -1
	var best_depth:      int   = 999999  # TIER 3 では距離最小化に使用
	var best_dest_fuh:   int   = -1
	var best_path_margin:int   = -99999
	var best_path:       Array = []

	while queue.size() > 0:
		var node: Dictionary = queue.pop_front()
		var nx:              int  = node["x"]
		var ny:              int  = node["y"]
		var dir:             int  = node["dir"]
		var depth:           int  = node["depth"]
		var path_min_margin: int  = node["path_min_margin"]

		var dest_fuh:   int  = _detector.hit_frame_from_events(nx, ny, events)
		# このノードの tier 判定（主BFSではpath_min_margin > 0が保証される）
		var tier: int
		if dest_fuh >= safe_inf:
			tier = TIER_SAFE_DEST
		else:
			tier = TIER_ROUTE_SAFE

		# ── 候補更新判定 ──
		var better: bool = false
		if tier > best_tier:
			better = true
		elif tier == best_tier:
			match tier:
				TIER_SAFE_DEST:
					# 最近傍優先、同距離なら経路余裕最大
					if depth < best_depth:
						better = true
					elif depth == best_depth and path_min_margin > best_path_margin:
						better = true
				TIER_ROUTE_SAFE, TIER_DESPERATE:
					# 目的地の被弾タイミングが遅いほど良い
					if dest_fuh > best_dest_fuh:
						better = true
					elif dest_fuh == best_dest_fuh and path_min_margin > best_path_margin:
						better = true

		if better:
			best_tier        = tier
			best_dir         = dir
			best_depth       = depth
			best_dest_fuh    = dest_fuh
			best_path_margin = path_min_margin
			best_path        = node["path"]

		# ── 展開 ──
		if depth < DEPTH:
			for di2 in range(4):
				var d2:  int = _dir_order[di2]
				var nnx: int = nx + DIRS[d2][0]
				var nny: int = ny + DIRS[d2][1]
				if not _is_walkable(nnx, nny, dangerous_kuru_cells):
					continue
				var nkey      := Vector2i(nnx, nny)
				var nfuh:  int = _detector.hit_frame_from_events(nnx, nny, events)
				var narr:  int = (depth + 1) * move_frames
				# 到達時に爆風 → 爆風壁としてスキップ
				if nfuh < safe_inf and nfuh <= narr:
					continue
				var step_margin: int = safe_inf if nfuh >= safe_inf else (nfuh - narr)
				var new_min: int     = mini(path_min_margin, step_margin)
				if not best_margin_to.has(nkey) or new_min > best_margin_to[nkey]:
					best_margin_to[nkey] = new_min
					var np: Array = node["path"].duplicate()
					np.append(nkey)
					queue.append({
						"x": nnx, "y": nny, "dir": dir,
						"depth": depth + 1, "path_min_margin": new_min,
						"path": np
					})

	# ── TIER 1 DESPERATE: 全面爆風時の多段BFS ────────────────────────────
	# 主BFSが安全経路を1本も見つけられなかった場合のみ実行。
	#
	# 「経路上で最初に爆風に当たるフレーム（death_frame）」を最大化する方向を選ぶ。
	# 爆風壁チェックなしで全マスを探索し、最も長生きできる経路の先頭方向を返す。
	#
	# death_frame の定義:
	#   あるステップで到達するマス C に対し、fuh(C) <= 到達フレーム なら
	#   そのマスに踏み込んだ瞬間に被弾する（death_frame = fuh(C)）。
	#   SAFE_INF = その経路上ではまだ被弾していない（通過可能）。
	#   経路全体の death_frame = ステップごとの death_frame の最小値。
	#
	# 「当たり判定が最も遅く発生するマス」を目指すことで、
	# 全面爆風でも被弾を最大限遅らせられる方向に移動する。
	if best_dir < 0:
		var desp_best_dir:       int   = -1
		var desp_best_death:     int   = -1    # 経路全体での最初の被弾フレーム
		var desp_best_dest_fuh:  int   = -1    # 目的地の hit_frame（タイブレーク用）
		var desp_best_path:      Array = []
		# このマスに至る最良 death_frame を記録（重複展開防止）
		var desp_best_death_to: Dictionary = {}
		var desp_queue: Array = []

		# ── 初期ノード（隣接4マス） ──
		for di in range(4):
			var d:   int = _dir_order[di]
			var nx:  int = start_x + DIRS[d][0]
			var ny:  int = start_y + DIRS[d][1]
			if nx < 0 or nx >= Constants.FIELD_COLS or ny < 0 or ny >= Constants.FIELD_ROWS:
				continue
			if _is_hard_block(nx, ny):
				continue
			if _has_dangerous_kuru_at_cached(nx, ny, dangerous_kuru_cells):
				continue
			var arr:   int = 1 * move_frames
			var fuh:   int = _detector.hit_frame_from_events(nx, ny, events)
			# 到達時に被弾するなら death_frame = fuh、通過可能なら SAFE_INF
			var death: int = fuh if (fuh < safe_inf and fuh <= arr) else safe_inf
			var key := Vector2i(nx, ny)
			if not desp_best_death_to.has(key) or death > desp_best_death_to[key]:
				desp_best_death_to[key] = death
				desp_queue.append({
					"x": nx, "y": ny, "dir": d, "depth": 1,
					"death_frame": death, "path": [key]
				})

		# ── BFS ループ ──
		while desp_queue.size() > 0:
			var node: Dictionary = desp_queue.pop_front()
			var nx:          int   = node["x"]
			var ny:          int   = node["y"]
			var dir:         int   = node["dir"]
			var depth:       int   = node["depth"]
			var death_frame: int   = node["death_frame"]

			var dest_fuh: int = _detector.hit_frame_from_events(nx, ny, events)

			# 候補更新:
			#   1. death_frame が大きいほど良い（長生き）
			#   2. 同点なら dest_fuh が大きい方（目的地の被弾が遅い）
			var better: bool = false
			if desp_best_dir < 0:
				better = true
			elif death_frame > desp_best_death:
				better = true
			elif death_frame == desp_best_death and dest_fuh > desp_best_dest_fuh:
				better = true

			if better:
				desp_best_dir      = dir
				desp_best_death    = death_frame
				desp_best_dest_fuh = dest_fuh
				desp_best_path     = node["path"]

			# 被弾済み経路はこれ以上展開しない（踏み込んだ時点で死亡）
			if death_frame < safe_inf:
				continue

			# ── 展開 ──
			if depth < DEPTH:
				for di2 in range(4):
					var d2:  int = _dir_order[di2]
					var nnx: int = nx + DIRS[d2][0]
					var nny: int = ny + DIRS[d2][1]
					if nnx < 0 or nnx >= Constants.FIELD_COLS or nny < 0 or nny >= Constants.FIELD_ROWS:
						continue
					if _is_hard_block(nnx, nny):
						continue
					if _has_dangerous_kuru_at_cached(nnx, nny, dangerous_kuru_cells):
						continue
					var narr:  int = (depth + 1) * move_frames
					var nfuh:  int = _detector.hit_frame_from_events(nnx, nny, events)
					var step_death: int = nfuh if (nfuh < safe_inf and nfuh <= narr) else safe_inf
					# 経路の death_frame = これまでの最小 と この一歩の最小
					var new_death: int = mini(death_frame, step_death)
					var nkey := Vector2i(nnx, nny)
					if not desp_best_death_to.has(nkey) or new_death > desp_best_death_to[nkey]:
						desp_best_death_to[nkey] = new_death
						var np: Array = node["path"].duplicate()
						np.append(nkey)
						desp_queue.append({
							"x": nnx, "y": nny, "dir": d2, "depth": depth + 1,
							"death_frame": new_death, "path": np
						})

		# ── 留まる方が長生きできる場合は移動しない ──
		# 例: 自分のいるマスの hit_frame が、どの方向に移動した場合の death_frame より大きければ
		#     その場に留まる（dir = -1 → ComThinkRoutine でキー未入力 = 停止）
		var stay_fuh: int = _detector.hit_frame_from_events(start_x, start_y, events)
		if stay_fuh > desp_best_death:
			# 留まる方が長生き → dir は -1 のまま（移動しない）
			best_tier     = TIER_DESPERATE
			best_dest_fuh = stay_fuh
			best_path     = []
		elif desp_best_dir >= 0:
			best_dir      = desp_best_dir
			best_tier     = TIER_DESPERATE
			best_dest_fuh = desp_best_dest_fuh
			best_path     = desp_best_path

	return {
		"dir":         best_dir,
		"is_safe":     best_tier >= TIER_SAFE_DEST,  # SAFE_DEST のみ真の安全
		"path_margin": best_path_margin,
		"dest_fuh":    best_dest_fuh,
		"escape_path": best_path,
	}


# ============================================================
# pick_approach_direction()
#
# 敵の射程位置（同行・同列）を目指して移動する方向を返す。
# _dir_order 順に評価するため、同スコア時の優先方向が約1秒ごとに変わる。
# ============================================================
func pick_approach_direction(me_x: int, me_y: int, enemy_x: int, enemy_y: int, power: int, bomb_container: Node, kuru_container: Node) -> int:
	const DIRS := [[1, 0], [-1, 0], [0, 1], [0, -1]]
	# 1手の貪欲評価だけだと、硬いブロック裏の敵に対して往復しやすい。
	# ここでは「爆弾を当てられる候補マス」まで BFS で最短経路を探索し、
	# その first-step を返すことで、迂回移動を選択できるようにする。
	const MAX_DEPTH := 12
	var dangerous_kuru_cells := _build_dangerous_kuru_cell_cache(kuru_container)

	var best_dir: int = -1
	var best_depth: int = 999999
	var best_target_danger: int = -999999
	var best_target_distance: int = 999999

	var queue: Array = []
	var visited: Dictionary = {}

	for di in range(4):
		var d: int = _dir_order[di]
		var nx: int = me_x + DIRS[d][0]
		var ny: int = me_y + DIRS[d][1]
		if not _is_walkable(nx, ny, dangerous_kuru_cells):
			continue
		var dscore := _detector.bomb_danger_score(nx, ny, bomb_container)
		if dscore < 0:
			continue
		var key := Vector2i(nx, ny)
		visited[key] = 1
		queue.append({"x": nx, "y": ny, "dir": d, "depth": 1})

	while queue.size() > 0:
		var node: Dictionary = queue.pop_front()
		var x: int = node["x"]
		var y: int = node["y"]
		var dir: int = node["dir"]
		var depth: int = node["depth"]

		var dscore := _detector.bomb_danger_score(x, y, bomb_container)
		if dscore >= 0 and _is_enemy_in_bomb_range(x, y, enemy_x, enemy_y, power):
			var target_distance: int = abs(enemy_x - x) + abs(enemy_y - y)
			var better := false
			if depth < best_depth:
				better = true
			elif depth == best_depth and dscore > best_target_danger:
				better = true
			elif depth == best_depth and dscore == best_target_danger and target_distance < best_target_distance:
				better = true
			if better:
				best_depth = depth
				best_target_danger = dscore
				best_target_distance = target_distance
				best_dir = dir

		if depth >= MAX_DEPTH:
			continue

		for di2 in range(4):
			var d2: int = _dir_order[di2]
			var nx2: int = x + DIRS[d2][0]
			var ny2: int = y + DIRS[d2][1]
			if not _is_walkable(nx2, ny2, dangerous_kuru_cells):
				continue
			var dscore2 := _detector.bomb_danger_score(nx2, ny2, bomb_container)
			if dscore2 < 0:
				continue
			var key2 := Vector2i(nx2, ny2)
			if visited.has(key2):
				continue
			visited[key2] = depth + 1
			queue.append({"x": nx2, "y": ny2, "dir": dir, "depth": depth + 1})

	# 射程位置に行けない場合は、BFS で敵に最短接近できる first-step を選ぶ。
	if best_dir >= 0:
		return best_dir

	var fallback_dir: int = -1
	var fallback_depth: int = 999999
	var fallback_dist: int = 999999
	var fallback_danger: int = -999999
	queue.clear()
	visited.clear()

	for di in range(4):
		var d: int = _dir_order[di]
		var nx: int = me_x + DIRS[d][0]
		var ny: int = me_y + DIRS[d][1]
		if not _is_walkable(nx, ny, dangerous_kuru_cells):
			continue
		var dscore := _detector.bomb_danger_score(nx, ny, bomb_container)
		if dscore < 0:
			continue
		var key := Vector2i(nx, ny)
		visited[key] = 1
		queue.append({"x": nx, "y": ny, "dir": d, "depth": 1})

	while queue.size() > 0:
		var node: Dictionary = queue.pop_front()
		var x: int = node["x"]
		var y: int = node["y"]
		var dir: int = node["dir"]
		var depth: int = node["depth"]
		var dist: int = abs(enemy_x - x) + abs(enemy_y - y)
		var dscore := _detector.bomb_danger_score(x, y, bomb_container)

		var better := false
		if dist < fallback_dist:
			better = true
		elif dist == fallback_dist and depth < fallback_depth:
			better = true
		elif dist == fallback_dist and depth == fallback_depth and dscore > fallback_danger:
			better = true
		if better:
			fallback_dist = dist
			fallback_depth = depth
			fallback_danger = dscore
			fallback_dir = dir

		if depth >= MAX_DEPTH:
			continue

		for di2 in range(4):
			var d2: int = _dir_order[di2]
			var nx2: int = x + DIRS[d2][0]
			var ny2: int = y + DIRS[d2][1]
			if not _is_walkable(nx2, ny2, dangerous_kuru_cells):
				continue
			var dscore2 := _detector.bomb_danger_score(nx2, ny2, bomb_container)
			if dscore2 < 0:
				continue
			var key2 := Vector2i(nx2, ny2)
			if visited.has(key2):
				continue
			visited[key2] = depth + 1
			queue.append({"x": nx2, "y": ny2, "dir": dir, "depth": depth + 1})

	return fallback_dir


# ── 内部ヘルパー ──────────────────────────────────────────────
# 敵がCOMの爆弾射程内にいるか（同行か同列で距離 <= power）
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


# フィールド内かつブロックなし かつ 危険なくる不在 であることを確認する。
# BFS ノード生成・展開の両方で使う共通ゲートウェイ。
func _is_walkable(x: int, y: int, dangerous_kuru_cells: Dictionary) -> bool:
	if x < 0 or x >= Constants.FIELD_COLS or y < 0 or y >= Constants.FIELD_ROWS:
		return false
	# 壁・ブロックチェック
	if _is_hard_block(x, y):
		return false
	# 危険なくるがいるマスは回避
	if _has_dangerous_kuru_at_cached(x, y, dangerous_kuru_cells):
		return false
	return true


func _build_dangerous_kuru_cell_cache(kuru_container: Node) -> Dictionary:
	var cache: Dictionary = {}
	if kuru_container == null:
		return cache
	for kuru_node in kuru_container.get_children():
		var kd: Dictionary = kuru_node.data
		var cnt: int = int(kd.get("count", ComDangerDetector.KURU_DANGER_FRAMES))
		if cnt >= ComDangerDetector.KURU_DANGER_FRAMES:
			continue
		var cell := Vector2i(
			int(kd.get("masu_x", -9999)),
			int(kd.get("masu_y", -9999))
		)
		cache[cell] = true
	return cache


func _has_dangerous_kuru_at_cached(x: int, y: int, dangerous_kuru_cells: Dictionary) -> bool:
	return dangerous_kuru_cells.has(Vector2i(x, y))


# ブロック（壊せない壁 or 壊せるブロック）ならば true を返す。
# ソフトブロック（SOFT_BLOCK）は爆弾で壊れるが、逃走中には通り抜けられない。
func _is_hard_block(x: int, y: int) -> bool:
	var masu: Array = GameState.masu
	if masu.size() <= y or masu[y].size() <= x:
		return false  # masu 未初期化なら安全側（通れる）と見なす
	return masu[y][x].kind != Enums.MasuKind.BROKEN
