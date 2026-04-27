class_name ComDangerDetector
extends RefCounted

# 「被弾しない安全なマスなし」を表す定数
const SAFE_INF := 99999

# くるの残り爆発フレーム閾値：この値未満になると接触で即爆発
# count は 正 → 0（爆発）へカウントダウンする前提。
const KURU_DANGER_FRAMES := 180

# find_bomb_danger()（即時危険フラグ）でくるを「今すぐ逃げるべき危険」と判断する
# 爆発残りフレームの上限。この値以上先に爆発するくるは BFS に任せ、
# 即時危険扱いにしない。値を大きくすると逃げが早まる（攻撃積極性が落ちる）。
const KURU_IMMDANGER_FRAMES: int = KURU_DANGER_FRAMES


# ============================================================
# _predict_kuru_explosion()
#
# くるが実際に爆発するときの予測マス座標と爆発フレームを返す。
#
# ■ 戻り値 Dictionary
#   "pos"   : Vector2i  爆発中心マス（bomb_x / bomb_y 相当）
#   "frame" : int       今から何フレーム後に爆発するか
#                       （壁衝突による早期爆発を含む）
#
# ■ 壁での早期爆発（kuru_move() の count = 0 強制）
#   進行方向に壁があり、壁到達時の count が 3*KURU_DANKAI_TIME 以下なら即爆発する。
#
# ■ speed == 0 の場合
#   move = 0 となり位置は変化しない。"frame" = count（通常爆発）。
# ============================================================
func _predict_kuru_explosion(kd: Dictionary) -> Dictionary:
	var sx:        int = int(kd.get("x",         0))
	var sy:        int = int(kd.get("y",         0))
	var speed:     int = int(kd.get("speed",     0))
	var count:     int = int(kd.get("count",     0))
	var muki:      int = int(kd.get("muki",      Enums.Muki.DOWN))
	var move_muki: int = int(kd.get("move_muki", muki))

	# Kuru.gd kuru_move() と同一: 1フレームあたりの移動量（サブピクセル）
	@warning_ignore("integer_division")
	var move: int = speed / 2

	# ── count フレーム後のサブピクセル座標と実際の爆発フレームを計算 ──────
	var final_x:        int = sx
	var final_y:        int = sy
	var explosion_frame: int = count  # デフォルト: カウントダウン通り

	# くるの爆発閾値（3段階時間 * 3 = 3秒相当）
	var threshold: int = 3 * Constants.KURU_DANKAI_TIME
	
	if move > 0:
		match move_muki:
			Enums.Muki.RIGHT:
				var raw: int = sx + move * count
				if raw >= Constants.MAP_SIZE_X:
					@warning_ignore("integer_division")
					var frames_to_wall: int = (Constants.MAP_SIZE_X - sx + move - 1) / move
					final_x = Constants.MAP_SIZE_X
					# 壁到達時、カウントが閾値以下なら即爆発。
					explosion_frame = max(frames_to_wall, count - threshold)
				else:
					final_x = raw
			Enums.Muki.LEFT:
				var raw: int = sx - move * count
				if raw <= 0:
					@warning_ignore("integer_division")
					var frames_to_wall: int = (sx + move - 1) / move
					final_x = 0
					explosion_frame = max(frames_to_wall, count - threshold)
				else:
					final_x = raw
			Enums.Muki.DOWN:
				var raw: int = sy + move * count
				if raw >= Constants.MAP_SIZE_Y:
					@warning_ignore("integer_division")
					var frames_to_wall: int = (Constants.MAP_SIZE_Y - sy + move - 1) / move
					final_y = Constants.MAP_SIZE_Y
					explosion_frame = max(frames_to_wall, count - threshold)
				else:
					final_y = raw
			Enums.Muki.UP:
				var raw: int = sy - move * count
				if raw <= 0:
					@warning_ignore("integer_division")
					var frames_to_wall: int = (sy + move - 1) / move
					final_y = 0
					explosion_frame = max(frames_to_wall, count - threshold)
				else:
					final_y = raw

	# ── bomb_x / bomb_y を Kuru.gd kuru_move() と同一の式で計算 ─────────────
	# muki（発射方向）に応じて「先端マス」を求める。
	# move_muki（実移動方向）ではなく muki を使う点に注意。
	var bomb_x: int
	var bomb_y: int
	match muki:
		Enums.Muki.RIGHT:
			@warning_ignore("integer_division")
			bomb_x = (final_x + 319) / 320
			@warning_ignore("integer_division")
			bomb_y = (final_y + 160) / 320
		Enums.Muki.LEFT:
			@warning_ignore("integer_division")
			bomb_x = final_x / 320
			@warning_ignore("integer_division")
			bomb_y = (final_y + 160) / 320
		Enums.Muki.DOWN:
			@warning_ignore("integer_division")
			bomb_x = (final_x + 160) / 320
			@warning_ignore("integer_division")
			bomb_y = (final_y + 319) / 320
		Enums.Muki.UP:
			@warning_ignore("integer_division")
			bomb_x = (final_x + 160) / 320
			@warning_ignore("integer_division")
			bomb_y = final_y / 320
		_:
			@warning_ignore("integer_division")
			bomb_x = (final_x + 160) / 320
			@warning_ignore("integer_division")
			bomb_y = (final_y + 160) / 320

	return {
		"pos": Vector2i(
			clampi(bomb_x, 0, Constants.FIELD_COLS - 1),
			clampi(bomb_y, 0, Constants.FIELD_ROWS - 1)
		),
		"frame": explosion_frame,
	}



# ============================================================
# has_dangerous_kuru_at()
#
# マス (x, y) に「爆発まで KURU_DANGER_FRAMES フレーム未満のくる」が
# 存在するかどうかを返す。
# そのようなくるに触れると即爆発するため、BFS 経路から除外する。
#
# count は 正 → 0（0 で爆発）へカウントダウンする前提。
#   "残り KURU_DANGER_FRAMES フレーム未満" = count < KURU_DANGER_FRAMES
# 位置フィールドは masu_x / masu_y を使用する。
# ============================================================
func has_dangerous_kuru_at(x: int, y: int, kuru_container: Node) -> bool:
	if kuru_container == null:
		return false
	for kuru_node in kuru_container.get_children():
		var kd: Dictionary = kuru_node.data
		var kx: int = int(kd.get("masu_x", -9999))
		var ky: int = int(kd.get("masu_y", -9999))
		if kx != x or ky != y:
			continue
		# count が KURU_DANGER_FRAMES 未満 = 爆発まで残り 180 フレーム以内
		# デフォルト値を閾値以上にしてフィールドなし時は安全扱い
		var cnt: int = int(kd.get("count", KURU_DANGER_FRAMES))
		if cnt < KURU_DANGER_FRAMES:
			return true
	return false



# ============================================================
# ── くる・連鎖対応の拡張爆発マップ ─────────────────────────────
#
# 以下の 3 関数を組み合わせて使う。
#
#   build_event_list()         : 爆弾 + くるを「爆発イベント」リストに変換し、
#                                引火連鎖を解決して返す
#   _propagate_chains()        : イベント間の引火を伝播させる内部処理
#   hit_frame_from_events()    : イベントリストから任意マスの被弾フレームを取得
#
# BFS ループ内では build_event_list() を1回だけ呼び、
# hit_frame_from_events() を各マスへの問い合わせに使うことで効率化する。
# ============================================================


# ============================================================
# build_event_list()
#
# 爆弾・くるの全爆発イベントを構築し、引火連鎖を解決した結果を返す。
#
# 各イベント（Dictionary）:
#   "x", "y"       : 爆発中心マス（bomb_x / bomb_y 相当）
#   "power"        : 爆風射程
#   "center_frame" : 今から何フレーム後に中心マスが爆風に巻き込まれるか（0 = 今）
#
# ■ くるの爆発位置・タイミング
#   _predict_kuru_explosion() で位置と実際の爆発フレームを取得する。
#   壁衝突による早期爆発（count > 3*KURU_DANKAI_TIME の壁到達後に
#   残りカウントが 3*KURU_DANKAI_TIME 以下になる場合）も正確に反映する。
# ============================================================
func build_event_list(bomb_container: Node, kuru_container: Node) -> Array:
	var events: Array = []
	var bst: int = Constants.BOMB_SPREAD_TIME

	# ── 爆弾を追加 ──────────────────────────────────────────────────────────
	# 爆弾の count (t) と center_frame の対応:
	#   t < 0      : まだ爆発していない。center_frame = -t（t フレーム後に爆発）
	#   t ∈ [0,bst]: 中心が爆発中。center_frame = 0（今すでに当たっている）
	#   それ以外の有効範囲 : 拡散爆風が進行中。center は既に 0 なので center_frame = 0
	for bomb in bomb_container.get_children():
		var bd: Dictionary = bomb.data
		var t: int  = int(bd["count"])
		var pw: int = int(bd["power"])
		if t < -bst * 2 or t > (pw + 1) * bst:
			continue
		# ■ center_frame の符号の意味
		#   t < 0 (未爆発):  center_frame = -t > 0 → あと -t フレームで中心着火
		#   t >= 0 (展開中): center_frame = -t <= 0 → |t| フレーム前に中心が着火済み
		# hit_frame_from_events() は maxi(0, center_frame + d * bst) で正しく計算する。
		events.append({
			"x":            int(bd["masu_x"]),
			"y":            int(bd["masu_y"]),
			"power":        pw,
			"center_frame": -t
		})

	# ── くるを追加（壁衝突早期爆発を含む実際の爆発フレームを使用） ──────────
	# _predict_kuru_explosion() が壁到達判定を行い、早期爆発する場合は
	# frames_to_wall を "frame" として返す。これを center_frame に使うことで
	# 危険度マップが正確になる。
	if kuru_container != null:
		for kuru_node in kuru_container.get_children():
			var kd: Dictionary = kuru_node.data
			var c:  int = int(kd.get("count", SAFE_INF))
			if c <= 0 or c >= SAFE_INF:
				continue
			var kp:       int        = int(kd.get("power", 2))
			var explosion: Dictionary = _predict_kuru_explosion(kd)
			events.append({
				"x":            explosion["pos"].x,
				"y":            explosion["pos"].y,
				"power":        kp,
				"center_frame": explosion["frame"],  # 壁早期爆発を反映した実際のフレーム
			})

	# ── 引火連鎖の解決 ──────────────────────────────────────────────────────
	_propagate_chains(events)

	return events


# ============================================================
# _propagate_chains()
#
# 爆発イベントリストに引火連鎖（chain explosion）を反映させる。
#
# ■ 判定ルール
#   爆発 A の爆風が爆発 B の中心に届く場合（同行 or 同列かつ距離 ≤ A.power）、
#   B の center_frame を min(B.center_frame, A.center_frame + dist * BST) に更新する。
#
# ■ 収束保証
#   center_frame は単調減少しかしないため、最大でも爆発数回の反復で収束する。
#   無限ループ防止のため上限を 20 回に設定。
# ============================================================
func _propagate_chains(events: Array) -> void:
	var bst:      int = Constants.BOMB_SPREAD_TIME
	var max_iter: int = 20
	for _iter in range(max_iter):
		var changed: bool = false
		for i in range(events.size()):
			var a: Dictionary = events[i]
			var ax: int = a["x"]
			var ay: int = a["y"]
			var ap: int = a["power"]
			var af: int = a["center_frame"]
			for j in range(events.size()):
				if i == j:
					continue
				var b: Dictionary = events[j]
				var bx: int = b["x"]
				var by: int = b["y"]
				# 同行 or 同列かつ射程内か確認
				var dist: int = -1
				if ax == bx and ay != by:
					dist = abs(ay - by)
				elif ay == by and ax != bx:
					dist = abs(ax - bx)
				if dist < 0 or dist > ap:
					continue
				if _is_blast_blocked(ax, ay, bx, by):
					continue
				# A の爆風が B の中心に届くフレーム
				var chain_frame: int = af + dist * bst
				if chain_frame < b["center_frame"]:
					b["center_frame"] = chain_frame
					events[j]         = b
					changed           = true
		if not changed:
			break


# ============================================================
# hit_frame_from_events()
#
# 事前構築済みイベントリストから、マス (x, y) が最初に
# 爆風に巻き込まれるまでのフレーム数を返す。
# いずれの爆発も届かない場合は SAFE_INF を返す。
#
# BFS ループ内で繰り返し呼ぶ用途のため、イベント構築コストは含まない。
#
# ■ 爆風ウィンドウモデル（修正）
#   爆風は中心から外向きに伝播し、距離 d のリングは
#   爆発開始から [d*bst, (d+1)*bst) フレームの間だけ当たり判定を持つ。
#   内側のリングは外側より先に当たり判定が消滅する。
#
#   ef = center_frame（負なら爆発開始から |ef| フレーム経過）
#   距離 d のリングが現在・将来に有効かどうかの条件:
#     ef + (d+1)*bst > 0  ← 偽なら爆風はすでにこの距離を通過済み → 無効
#   有効な場合の被弾フレーム:
#     maxi(0, ef + d*bst)
# ============================================================
func hit_frame_from_events(x: int, y: int, events: Array) -> int:
	var bst:      int = Constants.BOMB_SPREAD_TIME
	var earliest: int = SAFE_INF
	for e in events:
		var ex: int = e["x"]
		var ey: int = e["y"]
		var ep: int = e["power"]
		var ef: int = e["center_frame"]
		# ef < 0: 爆弾がすでに |ef| フレーム前に爆発開始済み（展開中）
		# ef >= 0: あと ef フレームで中心着火（またはくるの残りカウント）

		# ── 中心マス（距離 0）──
		# 中心リングのウィンドウは [0, bst)。
		# ef + bst <= 0 なら中心爆風はすでに通過済み → このイベントは無効
		if x == ex and y == ey:
			if ef + bst > 0:
				earliest = mini(earliest, maxi(0, ef))
			continue

		# ── 拡散爆風（距離 d マス）──
		# 距離 d のリングは [d*bst, (d+1)*bst) の間だけ当たり判定あり。
		# ef + (d+1)*bst <= 0 なら爆風波面はすでに距離 d を通過済み → 無効
		if x == ex:
			var d: int = abs(y - ey)
			if d <= ep and not _is_blast_blocked(ex, ey, x, y):
				if ef + (d + 1) * bst > 0:
					earliest = mini(earliest, maxi(0, ef + d * bst))
		elif y == ey:
			var d: int = abs(x - ex)
			if d <= ep and not _is_blast_blocked(ex, ey, x, y):
				if ef + (d + 1) * bst > 0:
					earliest = mini(earliest, maxi(0, ef + d * bst))
	return earliest


# ============================================================
# find_bomb_danger()
#
# マス (x, y) が「今すぐ逃げるべき危険」にあるかを判定する。
# 戻り値: { "danger": bool, "x": int, "y": int }
#
# ■ 判定対象と基準
#   爆弾    : 有効爆発範囲内にいる。ただし爆発展開中（t > 0）の場合は
#             爆風波面がすでにそのマスを通過済みなら除外する。
#   くる    : 実際の爆発フレーム（壁衝突による早期爆発を含む）が
#             KURU_IMMDANGER_FRAMES 以内 かつ 爆発予測位置の爆風範囲内
#             → 遠い将来のくるは BFS（hit_frame_from_events）に任せ、
#               即時危険とはみなさない。攻撃積極性を損なわないための閾値。
#   物理接触: 残りカウントが KURU_DANGER_FRAMES 未満のくるが現在地にいる
#
# ■ 爆風波面の通過チェック（修正）
#   爆発展開中の爆弾（t > 0）について、距離 d のマスが危険なのは
#   [d*bst, (d+1)*bst) の間だけ。t >= (d+1)*bst ならすでに通過済み → 除外。
# ============================================================
func find_bomb_danger(x: int, y: int, bomb_container: Node, kuru_container: Node) -> Dictionary:
	var bst: int = Constants.BOMB_SPREAD_TIME
	# ── 爆弾の直接射程判定 ──────────────────────────────────────────────────
	for bomb in bomb_container.get_children():
		var bd: Dictionary = bomb.data
		var t: int  = int(bd["count"])
		var pw: int = int(bd["power"])
		if t < -bst * 2 or t > Constants.BOMB_STAY_TIME + pw * bst:
			continue
		var bx: int = int(bd["masu_x"])
		var by: int = int(bd["masu_y"])

		# 同行または同列かつ射程内かを確認し、距離 d を求める
		var d: int = -1
		if x == bx:
			d = abs(y - by)
		elif y == by:
			d = abs(x - bx)
		if d < 0 or d > pw:
			continue
		if _is_blast_blocked(bx, by, x, y):
			continue

		# ■ 爆発展開中（t > 0）かつ爆風波面がすでにこの距離を通過済みなら除外
		# 距離 d のリングは [d*bst, (d+1)*bst) の間だけ有効。
		# t >= (d+1)*bst → 波面通過済み → 当たり判定なし
		if t > 0 and t >= (d + 1) * bst:
			continue

		return {"danger": true, "x": bd["masu_x"], "y": bd["masu_y"]}

	# ── くるの爆発射程判定（実際の爆発フレーム × 閾値フレーム以内のみ） ──────
	# 壁衝突による早期爆発がある場合は explosion["frame"] が frames_to_wall になる。
	# これにより count が KURU_IMMDANGER_FRAMES 以上でも、壁到達で実際には
	# 近いうちに爆発するくるを正しく即時危険として検出できる。
	if kuru_container != null:
		for kuru_node in kuru_container.get_children():
			var kd: Dictionary = kuru_node.data
			var c:  int = int(kd.get("count", SAFE_INF))
			if c <= 0:
				continue
			var explosion:     Dictionary = _predict_kuru_explosion(kd)
			var actual_frame:  int        = explosion["frame"]
			# 実際の爆発フレームで閾値判定（壁早期爆発を含む）
			if actual_frame <= 0 or actual_frame >= KURU_IMMDANGER_FRAMES:
				continue  # 爆発まで余裕あり → 即時危険扱いしない
			var pos: Vector2i = explosion["pos"]
			var kp:  int      = int(kd.get("power", 2))
			var in_kuru_range: bool = (
				(x == pos.x and abs(y - pos.y) <= kp) \
				or (y == pos.y and abs(x - pos.x) <= kp)
			)
			if in_kuru_range and not _is_blast_blocked(pos.x, pos.y, x, y):
				return {"danger": true, "x": pos.x, "y": pos.y}

	# ── 危険なくるの物理接触判定 ────────────────────────────────────────────
	if has_dangerous_kuru_at(x, y, kuru_container):
		return {"danger": true, "x": x, "y": y}

	return {"danger": false, "x": -1, "y": -1}


# ============================================================
# bomb_danger_score()
#
# マス (x, y) の爆弾危険度スコアを返す。
#   -100 : 爆発範囲内（進入禁止）
#   20   : 爆弾なし（安全）
#   1〜  : 爆弾と同行列だが射程外（値が大きいほど安全）
#
# ■ 爆風波面の通過チェック（修正）
#   爆発展開中の爆弾（t > 0）について、距離 d のマスが -100 になるのは
#   [d*bst, (d+1)*bst) の間だけ。t >= (d+1)*bst ならすでに通過済みなので
#   -100 を返さない（同行・同列の近傍スコアとして min_dist だけ更新）。
# ============================================================
func bomb_danger_score(x: int, y: int, bomb_container: Node) -> int:
	var bst: int = Constants.BOMB_SPREAD_TIME
	var min_dist := 999
	for bomb in bomb_container.get_children():
		var bd: Dictionary = bomb.data
		var t: int  = int(bd["count"])
		var pw: int = int(bd["power"])
		if t < -bst * 2 or t > (pw + 1) * bst:
			continue
		var bx: int = int(bd["masu_x"])
		var by: int = int(bd["masu_y"])
		if x == bx:
			var d: int = abs(y - by)
			if d <= pw and not _is_blast_blocked(bx, by, x, y):
				# 爆発展開中かつ爆風波面がすでにこの距離を通過済みなら -100 にしない
				if t > 0 and t >= (d + 1) * bst:
					min_dist = mini(min_dist, d)
				else:
					return -100
			min_dist = mini(min_dist, abs(y - by))
		elif y == by:
			var d: int = abs(x - bx)
			if d <= pw and not _is_blast_blocked(bx, by, x, y):
				if t > 0 and t >= (d + 1) * bst:
					min_dist = mini(min_dist, d)
				else:
					return -100
			min_dist = mini(min_dist, abs(x - bx))
	if min_dist == 999:
		return 20
	return min_dist


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
