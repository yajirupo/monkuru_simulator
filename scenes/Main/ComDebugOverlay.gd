# ============================================================
# ComDebugOverlay.gd
#
# COMの思考プロセスをリアルタイムで可視化するデバッグオーバーレイ。
# CanvasLayer として動作し、ゲーム画面の最前面にグリッド情報を描画する。
#
# ■ セットアップ方法
#   1. Main シーンに CanvasLayer ノードを追加し、このスクリプトをアタッチ
#   2. Main.gd の _ready() または VsCOM セットアップ箇所で参照を渡す:
#        $ComDebugOverlay.bomb_container = $BombContainer   # 実際のパスに合わせる
#        $ComDebugOverlay.kuru_container = $KuruContainer
#        $ComDebugOverlay.com_think = _com_think            # ComThinkRoutine インスタンス
#   3. Inspector で cell_size と field_origin をフィールドの表示座標に合わせる
#      （フィールドが画面全体なら field_origin = Vector2.ZERO が多い）
#
# ■ 操作方法
#   F12     : 表示モード切り替え（OFF / MAP / MAP+PANEL）
#   F11     : 表示レイヤー切り替え（危険度 / 接近スコア / 全表示）
#
# ■ 依存
#   ComThinkRoutine.gd（debug_snapshot フィールドが追加された版）
#   ComPlayerTracker.gd（is_tracking() メソッドが追加された版）
# ============================================================
class_name ComDebugOverlay
extends CanvasLayer

# ── 方向定数（ComPathfinder.gd の DIRS と同じ） ──────────────
# index: 0=右, 1=左, 2=下, 3=上
const DIRS: Array = [[1, 0], [-1, 0], [0, 1], [0, -1]]
const DIR_ARROWS: Array[String] = ["→", "←", "↓", "↑"]

# ── 表示レイヤー定数 ─────────────────────────────────────────
enum ViewLayer { ALL, DANGER_ONLY, APPROACH_ONLY }

# ── 設定 (Inspector で調整) ──────────────────────────────────
enum DebugDisplayMode { OFF, MAP_ONLY, MAP_AND_PANEL }

## デバッグ表示モード（F12で循環）
@export var debug_mode: DebugDisplayMode = DebugDisplayMode.OFF
## 1マスの画面ピクセルサイズ。Field ノードの表示サイズに合わせる
@export var cell_size: int = 32
## フィールド左上マス(0,0)の画面座標
@export var field_origin: Vector2 = Vector2(32.0, 30.5)
## ON/OFFトグルキー
@export var toggle_key: Key = KEY_F12
## 表示レイヤー切り替えキー
@export var layer_key: Key = KEY_F11
## ステータスパネルのフォントサイズ
@export var panel_font_size: int = 14
## グリッドフォントサイズ（マス内の数値）
@export var grid_font_size: int = 10

# ── 外部参照 (Main.gd からセット) ────────────────────────────
var bomb_container: Node = null
var kuru_container: Node = null
## ComThinkRoutine のインスタンス。debug_snapshot を読む。
## null の場合はオーバーレイ内部で独立計算する
var com_think: ComThinkRoutine = null

# ── 内部インスタンス ─────────────────────────────────────────
var _detector: ComDangerDetector
var _pathfinder: ComPathfinder

# ── フレームキャッシュ ───────────────────────────────────────
## build_event_list() の結果キャッシュ
var _events: Array = []
## [y][x] -> hit_frame（SAFE_INF = 99999 なら安全）
var _cell_hit_frames: Array = []
## [d] -> 接近スコア（4方向分）
var _approach_scores: Array[int] = [0, 0, 0, 0]
## 最終確定したスナップショット
var _snapshot: Dictionary = {}

# ── 表示状態 ─────────────────────────────────────────────────
var _view_layer: ViewLayer = ViewLayer.ALL
var _draw_node: Control  # 実描画を担当する Control 子ノード


func _is_debug_visible() -> bool:
	return debug_mode != DebugDisplayMode.OFF


func _is_panel_visible() -> bool:
	return debug_mode == DebugDisplayMode.MAP_AND_PANEL


# ============================================================
func _init() -> void:
	_detector  = ComDangerDetector.new()
	_pathfinder = ComPathfinder.new(_detector)


func _ready() -> void:
	layer = 100  # 最前面
	# 実描画は _ComDebugDraw スクリプトを持つ Control ノードに委譲
	_draw_node = _ComDebugDraw.new()
	(_draw_node as _ComDebugDraw).overlay = self
	_draw_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_draw_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_node.visible = _is_debug_visible()
	add_child(_draw_node)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == toggle_key:
		debug_mode = wrapi(debug_mode + 1, 0, 3) as DebugDisplayMode
		_draw_node.visible = _is_debug_visible() # ノードごと隠す
		var mode_label := ["OFF", "MAP", "MAP+PANEL"]
		print("[ComDebug] 表示モード: ", mode_label[debug_mode])
	elif event.keycode == layer_key:
		_view_layer = wrapi(_view_layer + 1, 0, 3) as ViewLayer \
			if _view_layer < ViewLayer.APPROACH_ONLY \
			else ViewLayer.ALL
		var label := ["全表示", "危険度のみ", "接近スコアのみ"]
		print("[ComDebug] 表示レイヤー: ", label[_view_layer])


func _process(_delta: float) -> void:
	# OFF の時は描画をクリアして終了する
	if not _is_debug_visible():
		_draw_node.queue_redraw() # 常にクリア命令を出し続けるか、切り替わった瞬間だけでOK
		return
	if bomb_container == null or kuru_container == null:
		return
	if GameState.player.size() < 2:
		return
	_update_snapshot()
	_draw_node.queue_redraw()


# ============================================================
# _update_snapshot()
#
# 毎フレーム呼ばれ、描画に必要な情報を収集してキャッシュする。
# ============================================================
func _update_snapshot() -> void:
	var me: Dictionary    = GameState.player[1]
	var enemy: Dictionary = GameState.player[0]

	if not me.get("life_flag", false):
		return

	var me_x: int    = int(me.get("masu_x", 0))
	var me_y: int    = int(me.get("masu_y", 0))
	var my_power: int = int(me.get("max_power", 0))
	var real_ex: int = int(enemy.get("masu_x", 0))
	var real_ey: int = int(enemy.get("masu_y", 0))

	# ── com_think の debug_snapshot を参照 ─────────────────
	var enemy_x: int   = real_ex
	var enemy_y: int   = real_ey
	var is_cloaked: bool  = false
	var phase: String     = "IDLE"
	var escape_dir: int   = -1
	var in_danger: bool   = false
	var danger_x: int     = -1
	var danger_y: int     = -1
	var escape_is_safe: bool  = false
	var escape_path_margin: int = 0
	var bomb_just_placed: bool = false
	var escape_path: Array = []

	if com_think != null and com_think.debug_snapshot.size() > 0:
		var s: Dictionary = com_think.debug_snapshot
		enemy_x           = s.get("enemy_x",           real_ex)
		enemy_y           = s.get("enemy_y",           real_ey)
		is_cloaked        = s.get("is_enemy_cloaked",  false)
		phase             = s.get("phase",             "IDLE")
		escape_dir        = s.get("escape_dir",        -1)
		in_danger         = s.get("in_danger",         false)
		danger_x          = s.get("danger_x",          -1)
		danger_y          = s.get("danger_y",          -1)
		escape_is_safe    = s.get("escape_is_safe",    false)
		escape_path_margin = s.get("escape_path_margin", 0)
		bomb_just_placed  = s.get("bomb_just_placed",  false)
		escape_path       = s.get("escape_path",       [])
	else:
		# com_think が未接続の場合は独自計算
		var danger_info = _detector.find_bomb_danger(me_x, me_y, bomb_container, kuru_container)
		in_danger = danger_info["danger"]
		danger_x  = danger_info.get("x", -1)
		danger_y  = danger_info.get("y", -1)
		var eq = _pathfinder.pick_escape_quality(me_x, me_y, bomb_container, kuru_container)
		escape_dir        = eq.get("dir", -1)
		escape_is_safe    = eq.get("is_safe", false)
		escape_path_margin = eq.get("path_margin", 0)
		escape_path       = eq.get("escape_path", [])
		if in_danger or bomb_just_placed:
			phase = "ESCAPE"
		elif _is_in_range(me_x, me_y, enemy_x, enemy_y, my_power):
			phase = "ATTACK"
		else:
			phase = "APPROACH"

	# ── 全マスの被弾フレームを計算 ────────────────────────
	_events = _detector.build_event_list(bomb_container, kuru_container)
	_cell_hit_frames.resize(Constants.FIELD_ROWS)
	for y in range(Constants.FIELD_ROWS):
		var row: Array = []
		row.resize(Constants.FIELD_COLS)
		for x in range(Constants.FIELD_COLS):
			row[x] = _detector.hit_frame_from_events(x, y, _events)
		_cell_hit_frames[y] = row

	# ── 接近スコアを4方向計算 ─────────────────────────────
	for d in range(4):
		var nx: int = me_x + DIRS[d][0]
		var ny: int = me_y + DIRS[d][1]
		if nx < 0 or nx >= Constants.FIELD_COLS or ny < 0 or ny >= Constants.FIELD_ROWS:
			_approach_scores[d] = -999999
			continue
		if _detector.has_dangerous_kuru_at(nx, ny, kuru_container):
			_approach_scores[d] = -999999
			continue
		var dscore: int = _detector.bomb_danger_score(nx, ny, bomb_container)
		if dscore < 0:
			_approach_scores[d] = -999999
			continue
		var score: int = dscore * 50
		if nx == enemy_x or ny == enemy_y:
			score += 500
		if _is_in_range(nx, ny, enemy_x, enemy_y, my_power):
			score += 1000
		score -= (abs(enemy_x - nx) + abs(enemy_y - ny)) * 10
		_approach_scores[d] = score

	_snapshot = {
		"me_x":              me_x,
		"me_y":              me_y,
		"my_power":          my_power,
		"enemy_x":           enemy_x,
		"enemy_y":           enemy_y,
		"real_enemy_x":      real_ex,
		"real_enemy_y":      real_ey,
		"is_cloaked":        is_cloaked,
		"phase":             phase,
		"escape_dir":        escape_dir,
		"escape_is_safe":    escape_is_safe,
		"escape_path_margin":escape_path_margin,
		"escape_path":       escape_path,
		"in_danger":         in_danger,
		"danger_x":          danger_x,
		"danger_y":          danger_y,
		"bomb_just_placed":  bomb_just_placed,
	}


# ============================================================
# _do_draw()  ─ _ComDebugDraw から呼ばれる描画メイン
# ============================================================
func _do_draw(canvas: Control) -> void:
	if _snapshot.is_empty():
		return

	var font: Font = ThemeDB.fallback_font
	var safe_inf: int = ComDangerDetector.SAFE_INF
	var cols: int     = Constants.FIELD_COLS
	var rows: int     = Constants.FIELD_ROWS
	var cs: float     = float(cell_size)
	var orig: Vector2 = field_origin

	var snap: Dictionary  = _snapshot
	var me_x: int         = snap["me_x"]
	var me_y: int         = snap["me_y"]
	var my_power: int     = snap["my_power"]
	var ex: int           = snap["enemy_x"]
	var ey: int           = snap["enemy_y"]
	var phase: String     = snap["phase"]
	var escape_dir: int   = snap["escape_dir"]
	var in_danger: bool   = snap["in_danger"]
	var is_cloaked: bool  = snap["is_cloaked"]

	# ══ 1. 全マス背景色 + 被弾フレーム数 ═══════════════════════
	if _view_layer == ViewLayer.ALL or _view_layer == ViewLayer.DANGER_ONLY:
		for y in range(rows):
			for x in range(cols):
				var rect := Rect2(orig + Vector2(x * cs, y * cs), Vector2(cs, cs))
				var hf: int = _cell_hit_frames[y][x] if _cell_hit_frames.size() > y else safe_inf

				# 背景色（危険度グラデーション）
				var bg: Color
				if hf <= 0:
					bg = Color(0.05, 0.05, 0.05, 0.80)   # 爆発中: 黒
				elif hf < 20:
					bg = Color(0.95, 0.05, 0.05, 0.65)   # 即死: 赤
				elif hf < 60:
					bg = Color(0.95, 0.40, 0.00, 0.55)   # 危険: オレンジ
				elif hf < 120:
					bg = Color(0.90, 0.85, 0.00, 0.40)   # 注意: 黄
				elif hf < safe_inf:
					bg = Color(0.20, 0.75, 0.20, 0.20)   # 比較的安全: 薄緑
				else:
					bg = Color(0, 0, 0, 0)               # 完全安全: 透明

				if bg.a > 0.01:
					canvas.draw_rect(rect, bg)

				# 被弾フレーム数（安全マスは表示省略）
				if hf < safe_inf:
					var hf_txt: String = str(hf) if hf > 0 else "💥"
					canvas.draw_string(font,
						rect.position + Vector2(2, rect.size.y - 2),
						hf_txt, HORIZONTAL_ALIGNMENT_LEFT, -1,
						grid_font_size, Color(1, 1, 1, 0.95))

	# ══ 2. 爆発イベント予測位置（爆弾・くるの着弾予測マス）═══
	if _view_layer == ViewLayer.ALL or _view_layer == ViewLayer.DANGER_ONLY:
		for ev in _events:
			var evx: int = ev.get("x", -1)
			var evy: int = ev.get("y", -1)
			var cf: int  = ev.get("center_frame", 0)
			var ep: int  = ev.get("power", 0)
			if evx < 0 or evy < 0 or cf <= 0:
				continue
			# 爆発中心マスに予告マーカー（マゼンタ小矩形）
			var cx_px: float = orig.x + evx * cs + cs * 0.30
			var cy_px: float = orig.y + evy * cs + cs * 0.05
			var ev_rect := Rect2(Vector2(cx_px, cy_px), Vector2(cs * 0.40, cs * 0.25))
			canvas.draw_rect(ev_rect, Color(1.0, 0.1, 1.0, 0.70), true)
			canvas.draw_string(font,
				Vector2(cx_px + 1, cy_px + cs * 0.22),
				"f%d p%d" % [cf, ep],
				HORIZONTAL_ALIGNMENT_LEFT, -1,
				grid_font_size, Color(1, 0.9, 1, 1))

	# ══ 3. 接近スコア表示（APPROACH フェーズ時のみ） ═══════════
	if _view_layer == ViewLayer.ALL or _view_layer == ViewLayer.APPROACH_ONLY:
		if phase == "APPROACH":
			for d in range(4):
				var nx: int = me_x + DIRS[d][0]
				var ny: int = me_y + DIRS[d][1]
				if nx < 0 or nx >= cols or ny < 0 or ny >= rows:
					continue
				var sc: int = _approach_scores[d]
				if sc <= -999990:
					continue
				var crect := Rect2(orig + Vector2(nx * cs, ny * cs), Vector2(cs, cs))
				# 高スコアほど青、低スコアほど暗い
				var ratio: float = clampf(float(sc) / 1500.0, 0.0, 1.0)
				var sc_color := Color(0.1 + ratio * 0.2, 0.3 + ratio * 0.4, 0.8, 0.55)
				canvas.draw_rect(crect, sc_color)
				# スコア値
				canvas.draw_string(font,
					crect.position + Vector2(2, cs * 0.45),
					"sc:%d" % sc,
					HORIZONTAL_ALIGNMENT_LEFT, -1,
					grid_font_size, Color(1, 1, 1, 1))
				# 射程チェック
				if _is_in_range(nx, ny, ex, ey, my_power):
					canvas.draw_string(font,
						crect.position + Vector2(2, cs * 0.65),
						"★RANGE",
						HORIZONTAL_ALIGNMENT_LEFT, -1,
						grid_font_size, Color(1, 1, 0, 1))

	# ══ 4. 敵の射程ライン（COMから見て狙いに行く同行・同列） ═══
	if phase == "APPROACH":
		# 縦ライン（x == enemy_x）
		for y in range(rows):
			var lrect := Rect2(orig + Vector2(ex * cs, y * cs), Vector2(cs, cs))
			canvas.draw_rect(lrect, Color(1.0, 0.0, 0.0, 0.12))
		# 横ライン（y == enemy_y）
		for x in range(cols):
			var lrect := Rect2(orig + Vector2(x * cs, ey * cs), Vector2(cs, cs))
			canvas.draw_rect(lrect, Color(1.0, 0.0, 0.0, 0.12))

	# ══ 5. 敵プレイヤーのマス ════════════════════════════════
	var e_rect := Rect2(orig + Vector2(ex * cs, ey * cs), Vector2(cs, cs))
	if is_cloaked:
		# 透明マント中: 推定位置をオレンジで表示
		canvas.draw_rect(e_rect, Color(1.0, 0.55, 0.0, 0.35), true)
		canvas.draw_rect(e_rect, Color(1.0, 0.55, 0.0, 1.0), false, 3.0)
		canvas.draw_string(font,
			e_rect.get_center() - Vector2(cs * 0.3, -grid_font_size * 0.5),
			"EST?", HORIZONTAL_ALIGNMENT_CENTER, -1,
			grid_font_size, Color(1.0, 0.7, 0.0, 1.0))
	else:
		canvas.draw_rect(e_rect, Color(1.0, 0.1, 0.1, 0.35), true)
		canvas.draw_rect(e_rect, Color(1.0, 0.1, 0.1, 1.0), false, 3.0)
		canvas.draw_string(font,
			e_rect.get_center() - Vector2(cs * 0.25, -grid_font_size * 0.5),
			"PLR", HORIZONTAL_ALIGNMENT_CENTER, -1,
			grid_font_size, Color(1, 1, 1, 1.0))

	# ══ 6. COMのマス ════════════════════════════════════════
	var me_rect := Rect2(orig + Vector2(me_x * cs, me_y * cs), Vector2(cs, cs))
	var me_fill_color: Color = Color(0.15, 0.45, 1.0, 0.45)
	if in_danger:
		me_fill_color = Color(1.0, 0.1, 0.1, 0.55)  # 危険中は赤みがかる
	canvas.draw_rect(me_rect, me_fill_color, true)
	canvas.draw_rect(me_rect, Color(0.1, 0.4, 1.0, 1.0), false, 3.5)
	canvas.draw_string(font,
		me_rect.get_center() - Vector2(cs * 0.25, -grid_font_size * 0.5),
		"COM", HORIZONTAL_ALIGNMENT_CENTER, -1,
		grid_font_size, Color(1, 1, 1, 1.0))

	# ══ 7. 逃げ方向の矢印 ═══════════════════════════════════
	if escape_dir >= 0 and escape_dir < 4:
		var center: Vector2 = me_rect.get_center()
		var dir_vec := Vector2(DIRS[escape_dir][0], DIRS[escape_dir][1])
		var arrow_len: float = cs * 0.48
		var arrow_end: Vector2 = center + dir_vec * arrow_len
		var arrow_color: Color = Color(0.0, 0.95, 0.95, 1.0) if snap["escape_is_safe"] \
			else Color(1.0, 0.5, 0.0, 1.0)
		canvas.draw_line(center, arrow_end, arrow_color, 3.5, true)
		var perp := Vector2(-dir_vec.y, dir_vec.x)
		var head_back := arrow_end - dir_vec * cs * 0.18
		canvas.draw_colored_polygon(PackedVector2Array([
			arrow_end,
			head_back + perp * cs * 0.12,
			head_back - perp * cs * 0.12,
		]), arrow_color)

	# ══ 7b. BFS 逃走経路の可視化 ════════════════════════════
	var escape_path: Array = snap.get("escape_path", [])
	var escape_is_safe: bool = snap.get("escape_is_safe", false)
	if escape_path.size() > 0:
		# 経路セルの塗り・番号
		var path_fill:   Color = Color(0.0, 0.9, 0.9, 0.22) if escape_is_safe \
			else Color(1.0, 0.5, 0.0, 0.22)
		var path_border: Color = Color(0.0, 0.9, 0.9, 0.85) if escape_is_safe \
			else Color(1.0, 0.5, 0.0, 0.85)
		for step_i in range(escape_path.size()):
			var cell: Vector2i = escape_path[step_i]
			var prect := Rect2(orig + Vector2(cell.x * cs, cell.y * cs), Vector2(cs, cs))
			canvas.draw_rect(prect, path_fill, true)
			canvas.draw_rect(prect, path_border, false, 1.8)
			# ステップ番号（左上）
			canvas.draw_string(font,
				prect.position + Vector2(2, grid_font_size + 1),
				str(step_i + 1),
				HORIZONTAL_ALIGNMENT_LEFT, -1,
				grid_font_size, path_border)
		# セル間を線で結ぶ（COM位置→パス各ステップ）
		var prev_center: Vector2 = me_rect.get_center()
		for step_i in range(escape_path.size()):
			var cell: Vector2i = escape_path[step_i]
			var cur_center: Vector2 = orig + Vector2(cell.x * cs + cs * 0.5, cell.y * cs + cs * 0.5)
			canvas.draw_line(prev_center, cur_center, path_border, 2.0, true)
			prev_center = cur_center

	# ══ 8. ステータスパネル ══════════════════════════════════
	if _is_panel_visible():
		_draw_status_panel(canvas, font, snap)


# ============================================================
# _draw_status_panel()  ─ 右上に情報パネルを描画
# ============================================================
func _draw_status_panel(canvas: Control, font: Font, snap: Dictionary) -> void:
	var phase: String         = snap.get("phase", "IDLE")
	var in_danger: bool       = snap.get("in_danger", false)
	var is_cloaked: bool      = snap.get("is_cloaked", false)
	var escape_is_safe: bool  = snap.get("escape_is_safe", false)
	var me_x: int             = snap.get("me_x", 0)
	var me_y: int             = snap.get("me_y", 0)
	var ex: int               = snap.get("enemy_x", 0)
	var ey: int               = snap.get("enemy_y", 0)
	var rex: int              = snap.get("real_enemy_x", 0)
	var rey: int              = snap.get("real_enemy_y", 0)
	var escape_dir: int       = snap.get("escape_dir", -1)
	var esc_margin: int       = snap.get("escape_path_margin", 0)
	var danger_x: int         = snap.get("danger_x", -1)
	var danger_y: int         = snap.get("danger_y", -1)
	var bomb_placed: bool     = snap.get("bomb_just_placed", false)
	var my_power: int         = snap.get("my_power", 2)

	var pfs: int   = panel_font_size
	var lh: float  = float(pfs) + 5
	var pw: float  = 310.0
	var ph: float  = lh * 14 + 10
	var px: float  = get_viewport().get_visible_rect().size.x - pw - 6
	var py: float  = 6.0

	# パネル背景
	canvas.draw_rect(Rect2(Vector2(px, py), Vector2(pw, ph)),
		Color(0.0, 0.0, 0.05, 0.82), true)
	canvas.draw_rect(Rect2(Vector2(px, py), Vector2(pw, ph)),
		Color(0.6, 0.6, 0.6, 0.6), false, 1.0)

	var x0: float = px + 8
	var y0: float = py + pfs + 4

	# ── フェーズ ──
	var phase_color: Color
	var phase_label: String
	match phase:
		"ESCAPE":
			phase_color = Color(1.0, 0.25, 0.25, 1)
			phase_label = "🔴 ESCAPE  (逃走中%s)" % (" 💣直後" if bomb_placed else "")
		"ATTACK":
			phase_color = Color(1.0, 0.75, 0.0, 1)
			phase_label = "💥 ATTACK  (爆弾設置！)"
		"APPROACH":
			phase_color = Color(0.25, 1.0, 0.25, 1)
			phase_label = "➡ APPROACH (接近中)"
		_:
			phase_color = Color(0.7, 0.7, 0.7, 1)
			phase_label = "⏸ IDLE"
	canvas.draw_string(font, Vector2(x0, y0), phase_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, pfs + 1, phase_color)

	y0 += lh + 2
	canvas.draw_line(Vector2(px + 4, y0 - lh * 0.3), Vector2(px + pw - 4, y0 - lh * 0.3),
		Color(0.5, 0.5, 0.5, 0.5), 1.0)

	# ── COM 状態 ──
	var danger_txt: String = "🔥YES (%d,%d)" % [danger_x, danger_y] if in_danger else "✓ no"
	canvas.draw_string(font, Vector2(x0, y0),
		"COM  : (%d,%d)  power=%d" % [me_x, me_y, my_power],
		HORIZONTAL_ALIGNMENT_LEFT, -1, pfs, Color(0.5, 0.8, 1.0))
	y0 += lh
	canvas.draw_string(font, Vector2(x0, y0),
		"危険 : %s" % danger_txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, pfs,
		Color(1, 0.3, 0.3) if in_danger else Color(0.6, 0.9, 0.6))

	y0 += lh + 2
	# ── 逃走ルート ──
	var esc_dir_txt: String = DIR_ARROWS[escape_dir] if escape_dir >= 0 else "なし"
	var safe_txt: String    = "(安全経路)" if escape_is_safe else "(次善経路⚠)"
	var margin_txt: String  = "margin=%d" % esc_margin if escape_dir >= 0 else ""
	canvas.draw_string(font, Vector2(x0, y0),
		"逃走 : %s %s  %s" % [esc_dir_txt, safe_txt, margin_txt],
		HORIZONTAL_ALIGNMENT_LEFT, -1, pfs,
		Color(0.0, 1.0, 1.0) if escape_is_safe else Color(1.0, 0.5, 0.0))

	# ── 逃走パス（BFS経路座標） ──
	var escape_path: Array = snap.get("escape_path", [])
	if escape_path.size() > 0:
		y0 += lh * 0.85
		var path_strs: Array = []
		for cell: Vector2i in escape_path:
			path_strs.append("(%d,%d)" % [cell.x, cell.y])
		var path_color: Color = Color(0.0, 0.9, 0.9, 1.0) if escape_is_safe \
			else Color(1.0, 0.6, 0.1, 1.0)
		canvas.draw_string(font, Vector2(x0 + 10, y0),
			"  → " + "→".join(path_strs),
			HORIZONTAL_ALIGNMENT_LEFT, -1, pfs - 2, path_color)

	y0 += lh + 2
	# ── 敵位置 ──
	canvas.draw_string(font, Vector2(x0, y0),
		"敵   : (%d,%d)%s" % [ex, ey, "  [推定中]" if is_cloaked else ""],
		HORIZONTAL_ALIGNMENT_LEFT, -1, pfs,
		Color(1.0, 0.55, 0.0) if is_cloaked else Color(1.0, 0.5, 0.5))
	if is_cloaked:
		y0 += lh * 0.8
		canvas.draw_string(font, Vector2(x0 + 10, y0),
			"  実座標: (%d,%d)  ← COMには見えない" % [rex, rey],
			HORIZONTAL_ALIGNMENT_LEFT, -1, pfs - 1, Color(0.5, 0.5, 0.5))

	y0 += lh + 2
	# ── 接近スコア ──
	if phase == "APPROACH":
		canvas.draw_string(font, Vector2(x0, y0),
			"接近スコア:",
			HORIZONTAL_ALIGNMENT_LEFT, -1, pfs, Color(0.5, 0.8, 1.0))
		y0 += lh * 0.9
		for d in range(4):
			var sc: int = _approach_scores[d]
			var sc_txt: String = "×(壁/危険)" if sc <= -999990 else str(sc)
			canvas.draw_string(font, Vector2(x0 + 12, y0),
				"%s %s" % [DIR_ARROWS[d], sc_txt],
				HORIZONTAL_ALIGNMENT_LEFT, -1, pfs - 1,
				Color(1, 1, 0, 1) if d == snap.get("best_approach_dir", -1) else Color(0.85, 0.85, 0.85))
			y0 += lh * 0.85

	y0 += 2
	canvas.draw_line(Vector2(px + 4, y0), Vector2(px + pw - 4, y0),
		Color(0.4, 0.4, 0.4, 0.5), 1.0)
	y0 += lh * 0.8

	# ── 表示凡例 ──
	var layer_names := ["全表示", "危険度のみ", "接近スコアのみ"]
	canvas.draw_string(font, Vector2(x0, y0),
		"[F12] OFF→MAP→MAP+PANEL  [F11] %s" % layer_names[_view_layer],
		HORIZONTAL_ALIGNMENT_LEFT, -1, pfs - 2, Color(0.5, 0.5, 0.5))


# ── 内部ヘルパー ──────────────────────────────────────────────
func _is_in_range(ax: int, ay: int, bx: int, by: int, power: int) -> bool:
	if ax == bx and abs(ay - by) <= power:
		return true
	if ay == by and abs(ax - bx) <= power:
		return true
	return false


# ============================================================
# _ComDebugDraw  ─ 実描画を担当する Control ノード（内部クラス）
# ============================================================
class _ComDebugDraw extends Control:
	var overlay: ComDebugOverlay

	func _draw() -> void:
		if overlay == null or not overlay._is_debug_visible():
			return
		overlay._do_draw(self)
