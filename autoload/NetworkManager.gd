# NetworkManager.gd
# Autoload 名: NetworkManager
#
# 同期の4層構造:
#   毎フレーム    : 移動キー4つ・アイテムキー3つ・くるアイテム使用 を unreliable_ordered で送る
#                   ※ 直近 INPUT_REDUNDANCY フレーム分を1パケットに同梱 → ドロップ対策
#                   ※ 死亡フラグは unreliable から切り離し (→ 専用 reliable RPC へ)
#   0.5秒おき    : プレイヤーの位置・向き・速さ を reliable で送る
#   くる射出時    : 位置・速度・寿命・向き・火力・送信タイムスタンプ を reliable で送る
#   死亡 / 爆発時 : 専用 reliable RPC で送る (消失リスクをゼロにする)
#
# ── drop 耐性の改良点 (v2) ───────────────────────────────────────
#
# [1] 入力冗長送信 (INPUT_REDUNDANCY = 3)
#   毎フレームパケットに直近3フレーム分の入力を PackedInt32Array で同梱。
#   1フレームがドロップしても次のパケットに含まれるため自動補完される。
#   受信側は _last_recv_frame より新しいフレームをすべて処理し、最新状態に更新する。
#
# [2] 入力ホールド (INPUT_HOLD_MAX_MS = 200 ms)
#   パケットが落ちた間も最後に受信した入力を保持し続ける。
#   has_remote_frame() は最終受信から INPUT_HOLD_MAX_MS 以内なら true を返す。
#   200ms を超えると false に戻り、ゲーム側が「切断に近い状態」と判断できる。
#
# [3] クロック同期の多サンプル化 (CLOCK_PING_COUNT = 5)
#   5回 Ping-Pong を行い、RTT が最小のサンプルのオフセットを採用する。
#   RTT 非対称時のブレを抑え、elapsed_ms の誤差を最小化する。
#   サンプル間は 50ms 待機（最低限のジッター分離）。
#
# ── 時刻同期について (v1 から変更なし) ─────────────────────────
# Time.get_ticks_msec() はOS起動時からの経過時間であり、端末ごとに異なる。
# NTP方式の Ping-Pong で「ゲーム内共通時刻」を確立する。
#   1. クライアントが _rpc_clock_ping(T1) をサーバーに送る
#   2. サーバーは T2 を添えて _rpc_clock_pong(T1, T2) を返す
#   3. クライアントは T4 で受信し:
#        RTT = T4 - T1 / 片道遅延 ≈ RTT/2
#        オフセット = (T2 + 片道遅延) - T4
#   4. get_synced_time_ms() = local_ticks + offset ≈ サーバー時刻
# ─────────────────────────────────────────────────────────────

extends Node

const PORT        := 9999
const MAX_CLIENTS := 1

# ── 入力冗長設定 ──────────────────────────────────────────────
const INPUT_FIELDS      := 9   # 1フレーム分のフィールド数: frame,r,l,d,u,item1,item2,item3,cr_use
const INPUT_REDUNDANCY  := 3   # 何フレーム分を同梱するか（パケットサイズ: 9×3×4 = 108 bytes）

# ── 入力ホールド設定 ──────────────────────────────────────────
# ドロップ中、この時間[ms]まで最後の入力を保持する
const INPUT_HOLD_MAX_MS := 200

# ── 時刻同期設定 ─────────────────────────────────────────────
const CLOCK_PING_COUNT       := 5     # Ping-Pong 計測回数
const CLOCK_PING_INTERVAL_MS := 50    # 計測間隔 [ms]

# ── くるシーンはプリロードでキャッシュ ───────────────────────
const KURU_SCENE: PackedScene = preload("res://scenes/Kuru/Kuru.tscn")

enum Role { NONE, SERVER, CLIENT }
var role: Role = Role.NONE

var is_linked:  bool = false
var peer_ready: bool = false
var my_ready:   bool = false

# ── 毎フレームデータ受信バッファ ──────────────────────────────
var remote_frame_data: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
var _frame_received:   bool = false
var _last_recv_time_ms: int = 0      # 最後に受信した時刻 (入力ホールド判定用)

var _last_recv_frame: int = 0
var _local_frame:     int = 0

# ── 入力履歴バッファ (冗長送信用) ────────────────────────────
# [frame, r, l, d, u, item1, item2, item3, cr_use] × INPUT_REDUNDANCY
var _input_history: PackedInt32Array

# ── 受信統計 (デバッグ用) ─────────────────────────────────────
var _recv_count: int = 0
var _drop_count: int = 0

var _peer: ENetMultiplayerPeer = null
var remote_stats: Dictionary = {}
var online_stage: int = 0
var _game_start_fired: bool = false

# ── 時刻同期 ──────────────────────────────────────────────────
var _clock_offset_ms: int  = 0
var _clock_synced:    bool = false
var _ping_sent_at_ms: int  = 0
var _ping_sample_idx: int  = 0
# [rtt_ms, offset_ms] の配列
var _ping_samples: Array   = []

# ── シグナル ──────────────────────────────────────────────────
signal connected_to_peer
signal peer_disconnected
signal connection_failed
signal game_start_requested
signal remote_player_died
signal remote_player_respawned
signal remote_explosion_triggered(masu_x: int, masu_y: int, power: int)
signal remote_chat_received(player_idx: int, message: String)
signal clock_sync_completed
signal remote_ready_updated

func _is_rpc_from_remote_peer() -> bool:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return false
	return sender_id != multiplayer.get_unique_id()


# ─── 接続管理 ────────────────────────────────────────────────
## Signal の二重接続を防ぎつつ、指定コールバックを安全に接続する。
func _connect_safe(sig: Signal, callable: Callable) -> void:
	if sig.is_connected(callable):
		sig.disconnect(callable)
	sig.connect(callable)

## Signal が接続済みの場合のみ切断し、未接続時のエラーを防ぐ。
func _disconnect_safe(sig: Signal, callable: Callable) -> void:
	if sig.is_connected(callable):
		sig.disconnect(callable)

## ENet サーバーを起動し、マルチプレイヤー用シグナルと状態を初期化する。
func start_server() -> String:
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		return "ポート%dでの起動に失敗しました (error %d)" % [PORT, err]
	multiplayer.multiplayer_peer = _peer
	_connect_safe(multiplayer.peer_connected,    _on_peer_connected)
	_connect_safe(multiplayer.peer_disconnected, _on_peer_disconnected)
	role             = Role.SERVER
	is_linked        = false
	_clock_offset_ms = 0
	_clock_synced    = true
	return ""

## 指定 IP のサーバーへクライアント接続し、接続イベント受信用シグナルを設定する。
func connect_to_server(ip: String) -> String:
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(ip, PORT)
	if err != OK:
		return "%s:%dへの接続に失敗しました (error %d)" % [ip, PORT, err]
	multiplayer.multiplayer_peer = _peer
	_connect_safe(multiplayer.connection_failed,   _on_connection_failed)
	_connect_safe(multiplayer.connected_to_server, _on_connected_to_server)
	_connect_safe(multiplayer.peer_disconnected,   _on_peer_disconnected)
	role      = Role.CLIENT
	is_linked = false
	return ""

## ネットワーク接続を完全に終了し、オンライン関連の内部状態を初期値に戻す。
func disconnect_all() -> void:
	_disconnect_safe(multiplayer.peer_connected,    _on_peer_connected)
	_disconnect_safe(multiplayer.peer_disconnected, _on_peer_disconnected)
	_disconnect_safe(multiplayer.connection_failed,   _on_connection_failed)
	_disconnect_safe(multiplayer.connected_to_server, _on_connected_to_server)
	if _peer:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null
	role              = Role.NONE
	is_linked         = false
	my_ready          = false
	peer_ready        = false
	remote_frame_data = [0, 0, 0, 0, 0, 0, 0, 0]
	_frame_received   = false
	_last_recv_frame  = 0
	_last_recv_time_ms = 0
	_local_frame      = 0
	_input_history    = PackedInt32Array()
	remote_stats      = {}
	online_stage      = 0
	_game_start_fired = false
	# 時刻同期リセット
	_clock_offset_ms  = 0
	_clock_synced     = false
	_ping_sent_at_ms  = 0
	_ping_sample_idx  = 0
	_ping_samples     = []
	# 統計リセット
	_recv_count = 0
	_drop_count = 0


# ─── 時刻同期（NTP Ping-Pong 多サンプル版）──────────────────
#
# 【改良点】
#   単発1回 → CLOCK_PING_COUNT (5) 回計測。
#   RTT が最小のサンプルを採用する（RTT最小 ≒ 片道遅延が最も対称なサンプル）。
#   これにより50ms遅延環境でも ±5ms 程度の誤差に収まる。

## クライアント側で時刻同期のサンプリングを開始する。
func start_clock_sync() -> void:
	if role != Role.CLIENT:
		return
	_ping_sample_idx = 0
	_ping_samples    = []
	_send_next_ping()

## 次回の Ping 送信時刻を記録し、サーバーへ同期要求を送る。
func _send_next_ping() -> void:
	_ping_sent_at_ms = Time.get_ticks_msec()
	_rpc_clock_ping.rpc(_ping_sent_at_ms)

## サーバー側で Ping を受け取り、受信時刻付きで Pong を返す。
@rpc("any_peer", "reliable")
func _rpc_clock_ping(client_t1: int) -> void:
	var server_t2: int = Time.get_ticks_msec()
	_rpc_clock_pong.rpc(client_t1, server_t2)

## クライアント側で Pong を処理し、RTT 最小サンプルから時刻オフセットを確定する。
@rpc("any_peer", "reliable")
func _rpc_clock_pong(client_t1: int, server_t2: int) -> void:
	var t4: int = Time.get_ticks_msec()

	var rtt_ms: int     = t4 - client_t1
	@warning_ignore("integer_division")
	var one_way_ms: int = rtt_ms / 2
	var offset: int     = (server_t2 + one_way_ms) - t4

	_ping_samples.append([rtt_ms, offset])
	_ping_sample_idx += 1

	if _ping_sample_idx < CLOCK_PING_COUNT:
		# 次の Ping まで少し待機（ジッター分離）
		await get_tree().create_timer(CLOCK_PING_INTERVAL_MS / 1000.0).timeout
		_send_next_ping()
	else:
		# RTT 最小のサンプルを採用（最も対称な経路を選ぶ）
		var best: Array = _ping_samples[0]
		for s: Array in _ping_samples:
			if s[0] < best[0]:
				best = s
		_clock_offset_ms = best[1]
		_clock_synced    = true
		clock_sync_completed.emit()

## 補正済みの共通時刻（ミリ秒）を返す。
func get_synced_time_ms() -> int:
	return Time.get_ticks_msec() + _clock_offset_ms

## 計測した RTT の最小値を返す（デバッグ・UI 表示用）
func get_min_rtt_ms() -> int:
	if _ping_samples.is_empty():
		return -1
	var min_rtt: int = _ping_samples[0][0]
	for s: Array in _ping_samples:
		if s[0] < min_rtt:
			min_rtt = s[0]
	return min_rtt

## ドロップ率を返す（デバッグ・UI 表示用）
## 戻り値: 0.0 〜 1.0
func get_drop_rate() -> float:
	var total := _recv_count + _drop_count
	if total == 0:
		return 0.0
	return float(_drop_count) / float(total)


# ─── Ready ───────────────────────────────────────────────────
## 自分の準備完了状態と設定値を相手へ通知し、ゲーム開始判定を進める。
func send_ready() -> void:
	my_ready = true
	var om   := GameState.online_menu
	var ch: int          = om["character"]
	var kt: int          = om["kuru_type"]
	var st: int          = GameState.clamp_stage(int(om.get("stage", 0)))
	var kdef: Dictionary = Constants.get_kuru_def(kt)
	_rpc_ready_with_stats.rpc(
		om.get("name", "Player") as String,
		ch, kt, st,
		0, 0, 0,
		kdef["speed"], kdef["dankai"], kdef["kankaku"],
		om["item_type"][0], om["item_type"][1], om["item_type"][2]
	)
	_check_game_start()

@rpc("any_peer", "reliable")
## 相手プレイヤーの準備情報を受信して保存し、開始条件を再判定する。
func _rpc_ready_with_stats(
	p_name: String, p_character: int, p_kuru_type: int, p_stage: int,
	p_speed: int, p_shot: int, p_power: int,
	p_kuru_speed: int, p_kuru_dankai: int, p_kuru_kankaku: int,
	p_item0: int, p_item1: int, p_item2: int
) -> void:
	if not _is_rpc_from_remote_peer():
		return
	peer_ready = true
	remote_stats = {
		"name": p_name, "character": p_character, "kuru_type": p_kuru_type,
		"stage": GameState.clamp_stage(p_stage),
		"speed": p_speed, "shot": p_shot, "power": p_power,
		"kuru_speed": p_kuru_speed, "kuru_dankai": p_kuru_dankai,
		"kuru_kankaku": p_kuru_kankaku,
		"item_type": [p_item0, p_item1, p_item2],
	}
	remote_ready_updated.emit()
	_check_game_start()


# ─── 毎フレーム: 移動(4) + アイテム使用(3) + cr_item_use(1) ──
#
# 【改良: 入力冗長送信】
#   _input_history に直近 INPUT_REDUNDANCY フレーム分を蓄積し、
#   PackedInt32Array として1パケットに全て含めて送る。
#
#   パケット構造（newest = 末尾）:
#     [frame0, r0, l0, d0, u0, item1_0, item2_0, item3_0, cr0,   <- 最古
#      frame1, r1, l1, d1, u1, item1_1, item2_1, item3_1, cr1,
#      frame2, r2, l2, d2, u2, item1_2, item2_2, item3_2, cr2]   <- 最新
#
#   受信側は _last_recv_frame より新しいエントリをすべて適用するため、
#   1フレームのドロップは次のパケットで補完される。
func send_frame_state(player_idx: int) -> void:
	_local_frame += 1
	var uk: Array     = GameState.use_key[player_idx]
	var p: Dictionary = GameState.player[player_idx]
	var cr_use: int   = p.get("cr_item_use", 0)

	# 今フレームの入力を履歴に追加
	var entry := PackedInt32Array([
		_local_frame, uk[0], uk[1], uk[2], uk[3], uk[5], uk[6], uk[7], cr_use
	])
	_input_history.append_array(entry)

	# 最大 INPUT_REDUNDANCY フレーム分だけ保持
	var max_size := INPUT_REDUNDANCY * INPUT_FIELDS
	if _input_history.size() > max_size:
		_input_history = _input_history.slice(_input_history.size() - max_size)

	_rpc_frame_state_v2.rpc(_input_history)

## フレームデータを受信しているか（入力ホールド込み）
func has_remote_frame() -> bool:
	if _frame_received:
		return true
	# 入力ホールド: 最後の受信から INPUT_HOLD_MAX_MS 以内なら保持入力を使う
	if _last_recv_time_ms > 0:
		var age_ms := Time.get_ticks_msec() - _last_recv_time_ms
		if age_ms < INPUT_HOLD_MAX_MS:
			return true
	return false

## フレームデータを取得して消費する
## ドロップ中は最後の入力をそのまま返す（_frame_received はクリアされるが remote_frame_data は保持）
func consume_remote_frame() -> Array[int]:
	_frame_received = false
	return remote_frame_data

@rpc("any_peer", "unreliable_ordered")
## 冗長化された入力履歴を受信し、未適用の最新フレームだけを順に反映する。
func _rpc_frame_state_v2(history: PackedInt32Array) -> void:
	if not _is_rpc_from_remote_peer():
		return
	@warning_ignore("integer_division")
	var count := history.size() / INPUT_FIELDS
	if count <= 0:
		return

	# 受信カウント更新（統計）
	_recv_count += 1

	# 最新の連続フレームを選んで適用（冗長エントリを順に処理）
	var applied := false
	for i in range(count):
		var base  := i * INPUT_FIELDS
		var frame := history[base]
		if frame <= _last_recv_frame:
			continue  # 既に処理済み

		# gap 検出（統計用。_last_recv_frame+1 より大きければドロップあり）
		if _last_recv_frame > 0 and frame > _last_recv_frame + 1:
			_drop_count += frame - _last_recv_frame - 1

		_last_recv_frame     = frame
		remote_frame_data[0] = history[base + 1]  # r
		remote_frame_data[1] = history[base + 2]  # l
		remote_frame_data[2] = history[base + 3]  # d
		remote_frame_data[3] = history[base + 4]  # u
		remote_frame_data[4] = history[base + 5]  # item1
		remote_frame_data[5] = history[base + 6]  # item2
		remote_frame_data[6] = history[base + 7]  # item3
		remote_frame_data[7] = history[base + 8]  # cr_use
		applied = true

	if applied:
		_frame_received    = true
		_last_recv_time_ms = Time.get_ticks_msec()
		var remote_idx := remote_player_index()
		if GameState.player.size() > remote_idx:
			GameState.player[remote_idx]["cr_item_use"] = remote_frame_data[7]


# ─── 死亡・復活イベント（reliable 専用 RPC）─────────────────
## 死亡イベントを reliable RPC で相手へ送信する。
func send_death_event(player_idx: int) -> void:
	_rpc_death_event.rpc(player_idx)

## 復活イベントを reliable RPC で相手へ送信する。
func send_respawn_event(player_idx: int) -> void:
	_rpc_respawn_event.rpc(player_idx)

@rpc("any_peer", "reliable")
## 相手の死亡イベントを受信し、リプレイ記録と通知シグナル発火を行う。
func _rpc_death_event(player_idx: int) -> void:
	if not _is_rpc_from_remote_peer():
		return
	if player_idx == remote_player_index():
		if GameState.joutai_flag == Enums.JoutaiType.ONLINE_GAME:
			OnlineReplayManager.record_state_event(
				OnlineReplayManager.STATE_EVENT_DEATH,
				{"player_idx": player_idx}
			)
		remote_player_died.emit()

@rpc("any_peer", "reliable")
## 相手の復活イベントを受信し、リプレイ記録と通知シグナル発火を行う。
func _rpc_respawn_event(player_idx: int) -> void:
	if not _is_rpc_from_remote_peer():
		return
	if player_idx == remote_player_index():
		if GameState.joutai_flag == Enums.JoutaiType.ONLINE_GAME:
			OnlineReplayManager.record_state_event(
				OnlineReplayManager.STATE_EVENT_RESPAWN,
				{"player_idx": player_idx}
			)
		remote_player_respawned.emit()


# ─── 0.5秒おき: プレイヤー位置・向き・速さ（reliable）──────
## 自分の位置・向き・速度を定期同期用に送信する。
func send_player_sync(player_idx: int) -> void:
	var p: Dictionary = GameState.player[player_idx]
	_rpc_player_sync.rpc(p["x"], p["y"], p["muki"], p["speed"])

@rpc("any_peer", "reliable")
## 相手プレイヤーの同期データを反映し、座標と向き・速度を補正する。
func _rpc_player_sync(p_x: int, p_y: int, p_muki: int, p_speed: int) -> void:
	if not _is_rpc_from_remote_peer():
		return
	var target := remote_player_index()
	if GameState.player.size() <= target:
		return
	if GameState.joutai_flag == Enums.JoutaiType.ONLINE_GAME:
		OnlineReplayManager.record_sync_event(target, p_x, p_y, p_muki, p_speed)
	var p: Dictionary = GameState.player[target]
	p["x"]    = p_x
	p["y"]    = p_y
	p["muki"] = p_muki
	@warning_ignore("integer_division")
	p["masu_x"] = (p_x + 160) / 320
	@warning_ignore("integer_division")
	p["masu_y"] = (p_y + 160) / 320
	p["speed"] = p_speed


# ─── くる射出: reliable + タイムスタンプ補正 ─────────────────
## くる生成情報を送信し、送信時刻を添えて遅延補正に備える。
func send_kuru_spawn(
	p_x: int, p_y: int,
	muki: int, move_muki: int,
	speed: int, count: int, power: int,
	player_idx: int, kuru_type: int
) -> void:
	if not _clock_synced and role == Role.CLIENT:
		push_warning("NetworkManager: 時刻未同期のまま send_kuru_spawn が呼ばれました。再同期を試みます。")
		start_clock_sync()
	var sent_at_ms: int = get_synced_time_ms()
	_rpc_kuru_spawn.rpc(p_x, p_y, muki, move_muki, speed, count, power,
						player_idx, kuru_type, sent_at_ms)

@rpc("any_peer", "reliable")
## 相手が射出したくるを生成し、通信遅延分だけ寿命カウントを補正して配置する。
func _rpc_kuru_spawn(
	p_x: int, p_y: int,
	muki: int, move_muki: int,
	speed: int, count: int, power: int,
	player_idx: int, kuru_type: int,
	sent_at_ms: int
) -> void:
	if not _is_rpc_from_remote_peer():
		return
	if player_idx != remote_player_index():
		return
	if KURU_SCENE == null:
		return

	if GameState.player.size() > player_idx:
		var shooter: Dictionary = GameState.player[player_idx]
		SoundManager.play_shot(int(shooter.get("character", 0)))

	var recv_at_ms: int     = get_synced_time_ms()
	var elapsed_ms: int     = recv_at_ms - sent_at_ms
	elapsed_ms = clampi(elapsed_ms, 0, 500)
	var frames_elapsed: int  = int(elapsed_ms * 60.0 / 1000.0)
	var corrected_count: int = maxi(0, count - frames_elapsed)

	var kuru_node = KURU_SCENE.instantiate()
	kuru_node.data["x"]         = p_x
	kuru_node.data["y"]         = p_y
	@warning_ignore("integer_division")
	kuru_node.data["masu_x"]    = (p_x + 160) / 320
	@warning_ignore("integer_division")
	kuru_node.data["masu_y"]    = (p_y + 160) / 320
	@warning_ignore("integer_division")
	kuru_node.data["bomb_x"]    = (p_x + 160) / 320
	@warning_ignore("integer_division")
	kuru_node.data["bomb_y"]    = (p_y + 160) / 320
	kuru_node.data["muki"]      = muki
	kuru_node.data["move_muki"] = move_muki
	kuru_node.data["speed"]     = speed
	kuru_node.data["count"]     = corrected_count
	kuru_node.data["power"]     = power
	kuru_node.data["player"]    = player_idx
	kuru_node.data["kuru_type"] = kuru_type

	var scene_root: Node = (Engine.get_main_loop() as SceneTree).current_scene
	var container := scene_root.get_node_or_null("KuruContainer")
	if container:
		container.add_child(kuru_node)
		kuru_node._sync_position()
		kuru_node._update_sprite()
	if GameState.joutai_flag == Enums.JoutaiType.ONLINE_GAME:
		OnlineReplayManager.record_kuru_event(kuru_node.data)


# ─── 爆発イベント（reliable）────────────────────────────────
## 爆発イベントを reliable RPC で相手へ通知する。
func send_explosion(masu_x: int, masu_y: int, power: int) -> void:
	_rpc_explosion.rpc(masu_x, masu_y, power)

@rpc("any_peer", "reliable")
## 相手の爆発イベントを受信し、リプレイ記録と通知シグナル発火を行う。
func _rpc_explosion(masu_x: int, masu_y: int, power: int) -> void:
	if not _is_rpc_from_remote_peer():
		return
	if GameState.joutai_flag == Enums.JoutaiType.ONLINE_GAME:
		OnlineReplayManager.record_state_event(
			OnlineReplayManager.STATE_EVENT_EXPLOSION,
			{"masu_x": masu_x, "masu_y": masu_y, "power": power}
		)
	remote_explosion_triggered.emit(masu_x, masu_y, power)


## チャットメッセージを相手へ送信する。
func send_chat_message(player_idx: int, message: String) -> void:
	_rpc_chat_message.rpc(player_idx, message)

@rpc("any_peer", "reliable")
## 相手から受信したチャットを UI 側へシグナル通知する。
func _rpc_chat_message(player_idx: int, message: String) -> void:
	if not _is_rpc_from_remote_peer():
		return
	var sender_idx := remote_player_index()
	if player_idx >= 0 and player_idx < Constants.MAX_PLAYER:
		sender_idx = player_idx
	remote_chat_received.emit(sender_idx, message)


# ─── ヘルパー ─────────────────────────────────────────────────
## 現在のロールから自分のプレイヤーインデックスを返す。
func my_player_index() -> int:
	return 0 if role == Role.SERVER else 1

## 現在のロールから相手のプレイヤーインデックスを返す。
func remote_player_index() -> int:
	return 1 if role == Role.SERVER else 0

## 両者 Ready 後、ステージ確定とゲーム開始通知を一度だけ実行する。
func _check_game_start() -> void:
	if _game_start_fired:
		return
	if not (my_ready and peer_ready):
		return
	if role == Role.SERVER:
		var my_stage := GameState.clamp_stage(int(GameState.online_menu.get("stage", 0)))
		var remote_stage := GameState.clamp_stage(int(remote_stats.get("stage", my_stage)))
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		online_stage = my_stage if rng.randi_range(0, 1) == 0 else remote_stage
		GameState.current_stage = online_stage
		_rpc_set_online_stage.rpc(online_stage)
		_game_start_fired = true
		game_start_requested.emit()

@rpc("any_peer", "reliable")
## サーバーが確定したオンライン対戦ステージを受信して開始処理を進める。
func _rpc_set_online_stage(stage: int) -> void:
	if not _is_rpc_from_remote_peer():
		return
	if role != Role.CLIENT:
		return
	online_stage = GameState.clamp_stage(stage)
	GameState.current_stage = online_stage
	if role == Role.CLIENT and my_ready and peer_ready and not _game_start_fired:
		_game_start_fired = true
		game_start_requested.emit()

## サーバー側でクライアント接続を検知し、リンク状態を更新する。
func _on_peer_connected(_id: int) -> void:
	is_linked = true
	connected_to_peer.emit()

## クライアント側でサーバー接続完了を検知し、時刻同期を開始する。
func _on_connected_to_server() -> void:
	is_linked = true
	connected_to_peer.emit()
	start_clock_sync()

## 接続失敗時に状態をクリーンアップし、失敗通知シグナルを発火する。
func _on_connection_failed() -> void:
	is_linked = false
	disconnect_all()
	connection_failed.emit()

## 相手切断時にリンク・Ready 状態を解除し、切断通知を送る。
func _on_peer_disconnected(_id: int) -> void:
	is_linked  = false
	peer_ready = false
	peer_disconnected.emit()
