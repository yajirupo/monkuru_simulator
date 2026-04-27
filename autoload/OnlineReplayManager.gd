# OnlineReplayManager.gd
# オンライン対戦用リプレイ管理
# Autoload 名: OnlineReplayManager
#
# ファイル形式は VsReplayManager と同一。プレフィックスのみ "online" で区別する。
# ヘッダ構造:
#   [1 byte]  stage
#   [2 × (32 + 4 + 4 + 4×3) bytes]  各プレイヤーの name / character / kuru_type / item_type[3]
#   [N × 2 bytes]  フレーム入力 (player0, player1) … 終端 = 255
#   [チャットイベント]  _write_chat_events / _read_chat_events 参照

extends Node

const REPLAY_DIR    := "user://replays/"
const REPLAY_EXT    := ".dat"
const REPLAY_PREFIX := "online"
const TERMINATOR    := GameState.REPLAY_TERMINATOR
const STATE_EVENT_DEATH := 1
const STATE_EVENT_RESPAWN := 2
const STATE_EVENT_EXPLOSION := 3
const KURU_SCENE: PackedScene = preload("res://scenes/Kuru/Kuru.tscn")


# ============================================================
# ファイル読み込み（再生準備）
# ============================================================
func online_replay_data_read(num: int) -> bool:
	var path := REPLAY_DIR + REPLAY_PREFIX + "%02d%s" % [num, REPLAY_EXT]
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false

	GameState.current_stage = GameState.clamp_stage(f.get_8())

	# ファイルに保存されたインデックス順(0,1)でプレイヤーデータを復元する。
	# remember_last_online_game_replay() の修正により、
	# player[i] の character / kuru_type / cr_item は正しいインデックスで保存される。
	for i in range(2):
		var p: Dictionary = GameState.player[i]
		p["name"]          = _read_string(f, 32)
		p["character"]     = f.get_32()
		p["kuru_type"]     = f.get_32()
		for j in range(3):
			p["cr_item"][j] = f.get_32()

	GameState.p_replay_data = 0
	while true:
		if GameState.p_replay_data >= Constants.MAX_REPLAY_FLAME - 1:
			f.close()
			return false
		if f.get_position() + 2 > f.get_length():
			f.close()
			return false
		var b0 := f.get_8()
		var b1 := f.get_8()
		GameState.replay_data[0][GameState.p_replay_data] = b0
		GameState.replay_data[1][GameState.p_replay_data] = b1
		if b1 == TERMINATOR:
			break
		GameState.p_replay_data += 1

	GameState.replay_chat_events = _read_chat_events(f)
	GameState.replay_chat_event_cursor = 0
	GameState.online_replay_sync_events = _read_sync_events(f)
	GameState.online_replay_sync_event_cursor = 0
	GameState.online_replay_kuru_events = _read_kuru_events(f)
	GameState.online_replay_kuru_event_cursor = 0
	GameState.online_replay_state_events = _read_state_events(f)
	GameState.online_replay_state_event_cursor = 0

	# BUG FIX: local_player_idx の推定はすべてのイベントを読み込んだ後に行う。
	# （以前は _read_state_events より先に呼ばれていたため state_events が空で推定失敗することがあった）
	GameState.online_replay_local_player_idx = _infer_replay_local_player_idx()

	GameState.replay_data[0][GameState.p_replay_data] = TERMINATOR
	GameState.replay_data[1][GameState.p_replay_data] = TERMINATOR
	f.close()

	# 再生前に use_key をゼロクリアする
	# replay_to_key() が += 1 でインクリメントするため、残余値があるとズレが生じる
	for i in range(8):
		GameState.use_key[0][i] = 0
		GameState.use_key[1][i] = 0

	GameState.p_replay_data = 0
	return true

## 収録イベントから「ローカルがどちら側か」を推定して再生基準を決める。
func _infer_replay_local_player_idx() -> int:
	if not GameState.online_replay_sync_events.is_empty():
		var remote_idx := int(GameState.online_replay_sync_events[0].get("target_player", 1))
		return 1 - clampi(remote_idx, 0, 1)
	if not GameState.online_replay_state_events.is_empty():
		var payload: Dictionary = GameState.online_replay_state_events[0].get("payload", {})
		var remote_idx := int(payload.get("player_idx", 1))
		return 1 - clampi(remote_idx, 0, 1)
	if not GameState.online_replay_kuru_events.is_empty():
		var remote_idx := int(GameState.online_replay_kuru_events[0].get("player", 1))
		return 1 - clampi(remote_idx, 0, 1)
	return 0


# ============================================================
# ファイル書き込み（試合終了後の保存）
# ============================================================
## オンライン対戦の最終リプレイデータをファイルへ保存する。
func online_replay_data_write(num: int) -> void:
	if not GameState.has_last_online_replay:
		return

	DirAccess.make_dir_recursive_absolute(REPLAY_DIR)
	var path := REPLAY_DIR + REPLAY_PREFIX + "%02d%s" % [num, REPLAY_EXT]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return

	var vm: Dictionary = GameState.last_online_replay_menu
	f.store_8(GameState.clamp_stage(int(vm.get("stage", 0))))
	for i in range(2):
		_write_string(f, vm["name"][i], 32)
		f.store_32(vm["player_type"][i])
		f.store_32(vm["kuru_type"][i])
		for j in range(3):
			f.store_32(vm["item_type"][i][j])

	var d0: PackedByteArray = GameState.last_online_replay_data[0]
	var d1: PackedByteArray = GameState.last_online_replay_data[1]
	var frame_count := mini(d0.size(), d1.size())
	for i in range(frame_count):
		f.store_8(d0[i])
		f.store_8(d1[i])
		if d1[i] == TERMINATOR:
			break
	_write_chat_events(f, GameState.last_online_replay_chat_events)
	_write_sync_events(f, GameState.last_online_replay_sync_events)
	_write_kuru_events(f, GameState.last_online_replay_kuru_events)
	_write_state_events(f, GameState.last_online_replay_state_events)
	f.close()


# ============================================================
# 記録（ゲームプレイ中に毎フレーム呼び出す）
# OnlineGameLoop.process() の「入力確定後・ゲームロジック前」で呼ぶこと。
# ============================================================
func online_key_to_replay() -> bool:
	if GameState.p_replay_data == Constants.MAX_REPLAY_FLAME - 1:
		GameState.replay_data[0][Constants.MAX_REPLAY_FLAME - 1] = TERMINATOR
		GameState.replay_data[1][Constants.MAX_REPLAY_FLAME - 1] = TERMINATOR
		return false

	for j in range(2):
		GameState.replay_data[j][GameState.p_replay_data] = OnlineReplay.encode_input(j)

	GameState.p_replay_data += 1
	return true


# ============================================================
# 再生（リプレイモードで毎フレーム呼び出す）
# ============================================================
func online_replay_to_key() -> bool:
	if GameState.replay_data[1][GameState.p_replay_data] == TERMINATOR:
		return false

	for j in range(2):
		OnlineReplay.decode_input(j, int(GameState.replay_data[j][GameState.p_replay_data]))

	GameState.p_replay_data += 1
	return true

## 同期補正イベントを現在フレームで記録する。
func record_sync_event(target_player: int, x: int, y: int, muki: int, speed: int) -> void:
	GameState.online_replay_sync_events.append({
		"frame": GameState.count,
		"target_player": target_player,
		"x": x,
		"y": y,
		"muki": muki,
		"speed": speed,
	})

## 現在フレーム分の同期補正イベントを適用する。
func apply_sync_events_for_current_frame() -> void:
	while GameState.online_replay_sync_event_cursor < GameState.online_replay_sync_events.size():
		var ev: Dictionary = GameState.online_replay_sync_events[GameState.online_replay_sync_event_cursor]
		if int(ev.get("frame", -1)) != GameState.count:
			return
		var target := int(ev.get("target_player", 1))
		if target >= 0 and target < GameState.player.size():
			var p: Dictionary = GameState.player[target]
			var p_x := int(ev.get("x", p["x"]))
			var p_y := int(ev.get("y", p["y"]))
			p["x"] = p_x
			p["y"] = p_y
			p["muki"] = int(ev.get("muki", p["muki"]))
			p["speed"] = int(ev.get("speed", p["speed"]))
			@warning_ignore("integer_division")
			p["masu_x"] = (p_x + 160) / 320
			@warning_ignore("integer_division")
			p["masu_y"] = (p_y + 160) / 320
		GameState.online_replay_sync_event_cursor += 1

## くる生成イベントを現在フレームで記録する。
func record_kuru_event(kuru_data: Dictionary) -> void:
	var ev := kuru_data.duplicate(true)
	ev["frame"] = GameState.count
	GameState.online_replay_kuru_events.append(ev)

## 現在フレーム分のくる生成イベントを再生シーンへ反映する。
func apply_kuru_events_for_current_frame() -> void:
	while GameState.online_replay_kuru_event_cursor < GameState.online_replay_kuru_events.size():
		var ev: Dictionary = GameState.online_replay_kuru_events[GameState.online_replay_kuru_event_cursor]
		if int(ev.get("frame", -1)) != GameState.count:
			return
		var scene := KURU_SCENE
		if scene != null:
			var shooter_idx := int(ev.get("player", -1))
			if shooter_idx >= 0 and shooter_idx < GameState.player.size():
				var shooter: Dictionary = GameState.player[shooter_idx]
				SoundManager.play_shot(int(shooter.get("character", 0)))
			var kuru_node = scene.instantiate()
			kuru_node.data["x"] = int(ev.get("x", 0))
			kuru_node.data["y"] = int(ev.get("y", 0))
			kuru_node.data["masu_x"] = int(ev.get("masu_x", 0))
			kuru_node.data["masu_y"] = int(ev.get("masu_y", 0))
			kuru_node.data["bomb_x"] = int(ev.get("bomb_x", 0))
			kuru_node.data["bomb_y"] = int(ev.get("bomb_y", 0))
			kuru_node.data["muki"] = int(ev.get("muki", 0))
			kuru_node.data["move_muki"] = int(ev.get("move_muki", 0))
			kuru_node.data["speed"] = int(ev.get("speed", 0))
			kuru_node.data["count"] = int(ev.get("count", 0))
			kuru_node.data["power"] = int(ev.get("power", 1))
			kuru_node.data["player"] = int(ev.get("player", 1))
			kuru_node.data["kuru_type"] = int(ev.get("kuru_type", 0))
			var current_scene := get_tree().current_scene
			var container := current_scene.get_node_or_null("KuruContainer") if current_scene else null
			if container:
				container.add_child(kuru_node)
				kuru_node._sync_position()
		GameState.online_replay_kuru_event_cursor += 1

## 死亡/復活/爆発などの状態イベントを現在フレームで記録する。
func record_state_event(event_type: int, payload: Dictionary = {}) -> void:
	GameState.online_replay_state_events.append({
		"frame": GameState.count,
		"type": event_type,
		"payload": payload.duplicate(true),
	})

## 現在フレーム分の状態イベントを順次適用する。
func apply_state_events_for_current_frame() -> void:
	while GameState.online_replay_state_event_cursor < GameState.online_replay_state_events.size():
		var ev: Dictionary = GameState.online_replay_state_events[GameState.online_replay_state_event_cursor]
		if int(ev.get("frame", -1)) != GameState.count:
			return
		var event_type := int(ev.get("type", 0))
		var payload: Dictionary = ev.get("payload", {})
		match event_type:
			STATE_EVENT_DEATH:
				_apply_replay_death_event(int(payload.get("player_idx", -1)))
			STATE_EVENT_RESPAWN:
				_apply_replay_respawn_event(int(payload.get("player_idx", -1)))
			STATE_EVENT_EXPLOSION:
				NetworkManager.remote_explosion_triggered.emit(
					int(payload.get("masu_x", 0)),
					int(payload.get("masu_y", 0)),
					int(payload.get("power", 1))
				)
		GameState.online_replay_state_event_cursor += 1

## リプレイ中の死亡イベントを適用し、必要なら被弾チャットも補完する。
func _apply_replay_death_event(player_idx: int) -> void:
	if player_idx < 0 or player_idx >= GameState.player.size():
		return
	var p: Dictionary = GameState.player[player_idx]
	if not p["life_flag"]:
		return
	SoundManager.play_death(int(p.get("character", 0)), false)
	p["life_flag"] = false
	p["joutai_count"] = 0
	p["joutai"] = Enums.PlayerJoutaiType.DEATH
	# ローカルプレイヤーの死亡は _player_hit_bomb → _kill_player → _update_chat() で表示される。
	# リモートプレイヤーの死亡はstate_eventでここに来るため、
	# Player.gd _update_chat() と完全同一フォーマットでチャットを表示する。
	if player_idx != GameState.online_replay_local_player_idx:
		_push_death_chat(player_idx)


## Player.gd の _update_chat() と完全同一フォーマットでチャットに被弾を書き込む。
## 「[被弾] 名前 (x分xx秒xx)」黒で表示。
func _push_death_chat(player_idx: int) -> void:
	var pi: Dictionary = GameState.player[player_idx]
	var line: int = 0
	if GameState.chat_str[0] != "":
		if GameState.chat_str[1] != "":
			line = 2
			if GameState.chat_str[2] != "":
				GameState.chat_str[0]   = GameState.chat_str[1]
				GameState.chat_str[1]   = GameState.chat_str[2]
				GameState.chat_color[0] = GameState.chat_color[1]
				GameState.chat_color[1] = GameState.chat_color[2]
		else:
			line = 1
	var c: int = GameState.count
	@warning_ignore("integer_division")
	var minutes: int = c / 3600
	@warning_ignore("integer_division")
	var seconds: int = (c % 3600) / 60
	var frames:  int = c % 60
	var csec:    int = frames + int(frames * 2 / 3.0)
	GameState.chat_str[line]   = "[被弾] %s (%d分%02d秒%02d)" % [pi["name"], minutes, seconds, csec]
	GameState.chat_color[line] = Color.BLACK

## リプレイ中の復活イベントを適用してプレイヤー状態を通常へ戻す。
func _apply_replay_respawn_event(player_idx: int) -> void:
	if player_idx < 0 or player_idx >= GameState.player.size():
		return
	var p: Dictionary = GameState.player[player_idx]
	p["life_flag"] = true
	p["joutai"] = p["muki"]
	p["joutai_count"] = 0


# ============================================================
# ヘルパー（VsReplayManager と同一実装）
# ============================================================
## 固定長バッファから NULL 終端文字列を読み取る。
func _read_string(f: FileAccess, length: int) -> String:
	var bytes := f.get_buffer(length)
	var end := bytes.size()
	for i in range(bytes.size()):
		if bytes[i] == 0:
			end = i
			break
	return bytes.slice(0, end).get_string_from_utf8()

## 文字列を固定長 UTF-8（NULL 終端）で書き込む。
func _write_string(f: FileAccess, s: String, length: int) -> void:
	var bytes := s.to_utf8_buffer()
	while bytes.size() >= length:
		bytes.resize(bytes.size() - 1)
		while bytes.size() > 0 and (bytes[bytes.size() - 1] & 0xC0) == 0x80:
			bytes.resize(bytes.size() - 1)
		if bytes.size() > 0 and bytes[bytes.size() - 1] >= 0xC0:
			bytes.resize(bytes.size() - 1)
	for i in range(length):
		f.store_8(bytes[i] if i < bytes.size() else 0)

func _can_read(f: FileAccess, required_bytes: int) -> bool:
	return f.get_position() + required_bytes <= f.get_length()

## チャットイベント配列を読み込む。
func _read_chat_events(f: FileAccess) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if f.get_position() >= f.get_length():
		return events
	if not _can_read(f, 2):
		push_warning("OnlineReplayManager: チャットイベント数の読み込みに必要なデータが不足しています。")
		return events
	var count := f.get_16()
	for _i in range(count):
		# frame(4) + color(4) + name_len(2) = 最低 10 bytes
		if not _can_read(f, 10):
			push_warning("OnlineReplayManager: チャットイベントのヘッダ読み込み中にEOFに到達しました。")
			break
		var frame := f.get_32()
		var r := float(f.get_8()) / 255.0
		var g := float(f.get_8()) / 255.0
		var b := float(f.get_8()) / 255.0
		var a := float(f.get_8()) / 255.0
		var name_len := f.get_16()
		if not _can_read(f, name_len + 2):
			push_warning("OnlineReplayManager: チャットイベント(name/message)長が不正です。")
			break
		var myname := f.get_buffer(name_len).get_string_from_utf8()
		var msg_len := f.get_16()
		if not _can_read(f, msg_len):
			push_warning("OnlineReplayManager: チャットメッセージが途中で切れています。")
			break
		var message := f.get_buffer(msg_len).get_string_from_utf8()
		events.append({
			"frame":       frame,
			"player_name": myname,
			"message":     message,
			"color":       Color(r, g, b, a),
		})
	return events

## チャットイベント配列をファイルへ書き込む。
func _write_chat_events(f: FileAccess, events: Array[Dictionary]) -> void:
	f.store_16(events.size())
	for ev in events:
		f.store_32(int(ev.get("frame", 0)))
		var c: Color = ev.get("color", Color.BLACK)
		f.store_8(int(round(clamp(c.r, 0.0, 1.0) * 255.0)))
		f.store_8(int(round(clamp(c.g, 0.0, 1.0) * 255.0)))
		f.store_8(int(round(clamp(c.b, 0.0, 1.0) * 255.0)))
		f.store_8(int(round(clamp(c.a, 0.0, 1.0) * 255.0)))
		var name_bytes := String(ev.get("player_name", "")).to_utf8_buffer()
		f.store_16(name_bytes.size())
		f.store_buffer(name_bytes)
		var msg_bytes := String(ev.get("message", "")).to_utf8_buffer()
		f.store_16(msg_bytes.size())
		f.store_buffer(msg_bytes)

## 位置同期イベント配列を読み込む。
func _read_sync_events(f: FileAccess) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if f.get_position() >= f.get_length():
		return events
	if not _can_read(f, 2):
		push_warning("OnlineReplayManager: syncイベント数の読み込みに必要なデータが不足しています。")
		return events
	var count := f.get_16()
	for _i in range(count):
		# frame(4) + target(1) + x,y,muki,speed(4*4) = 21 bytes
		if not _can_read(f, 21):
			push_warning("OnlineReplayManager: syncイベント読み込み中にEOFに到達しました。")
			break
		events.append({
			"frame": f.get_32(),
			"target_player": f.get_8(),
			"x": f.get_32(),
			"y": f.get_32(),
			"muki": f.get_32(),
			"speed": f.get_32(),
		})
	return events

## 位置同期イベント配列をファイルへ書き込む。
func _write_sync_events(f: FileAccess, events: Array[Dictionary]) -> void:
	f.store_16(events.size())
	for ev in events:
		f.store_32(int(ev.get("frame", 0)))
		f.store_8(int(ev.get("target_player", 1)))
		f.store_32(int(ev.get("x", 0)))
		f.store_32(int(ev.get("y", 0)))
		f.store_32(int(ev.get("muki", 0)))
		f.store_32(int(ev.get("speed", 0)))

## くる生成イベント配列を読み込む。
func _read_kuru_events(f: FileAccess) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if f.get_position() >= f.get_length():
		return events
	if not _can_read(f, 2):
		push_warning("OnlineReplayManager: kuruイベント数の読み込みに必要なデータが不足しています。")
		return events
	var count := f.get_16()
	for _i in range(count):
		# frame(4) + int32*11 + player(1) + kuru_type(4) = 53 bytes
		if not _can_read(f, 53):
			push_warning("OnlineReplayManager: kuruイベント読み込み中にEOFに到達しました。")
			break
		events.append({
			"frame": f.get_32(),
			"x": f.get_32(),
			"y": f.get_32(),
			"masu_x": f.get_32(),
			"masu_y": f.get_32(),
			"bomb_x": f.get_32(),
			"bomb_y": f.get_32(),
			"muki": f.get_32(),
			"move_muki": f.get_32(),
			"speed": f.get_32(),
			"count": f.get_32(),
			"power": f.get_32(),
			"player": f.get_8(),
			"kuru_type": f.get_32(),
		})
	return events

## くる生成イベント配列をファイルへ書き込む。
func _write_kuru_events(f: FileAccess, events: Array[Dictionary]) -> void:
	f.store_16(events.size())
	for ev in events:
		f.store_32(int(ev.get("frame", 0)))
		f.store_32(int(ev.get("x", 0)))
		f.store_32(int(ev.get("y", 0)))
		f.store_32(int(ev.get("masu_x", 0)))
		f.store_32(int(ev.get("masu_y", 0)))
		f.store_32(int(ev.get("bomb_x", 0)))
		f.store_32(int(ev.get("bomb_y", 0)))
		f.store_32(int(ev.get("muki", 0)))
		f.store_32(int(ev.get("move_muki", 0)))
		f.store_32(int(ev.get("speed", 0)))
		f.store_32(int(ev.get("count", 0)))
		f.store_32(int(ev.get("power", 1)))
		f.store_8(int(ev.get("player", 1)))
		f.store_32(int(ev.get("kuru_type", 0)))

## 死亡/復活/爆発の状態イベント配列を読み込む。
func _read_state_events(f: FileAccess) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if f.get_position() >= f.get_length():
		return events
	if not _can_read(f, 2):
		push_warning("OnlineReplayManager: stateイベント数の読み込みに必要なデータが不足しています。")
		return events
	var count := f.get_16()
	for _i in range(count):
		if not _can_read(f, 5):
			push_warning("OnlineReplayManager: stateイベントのヘッダ読み込み中にEOFに到達しました。")
			break
		var frame := f.get_32()
		var event_type := f.get_8()
		var payload: Dictionary = {}
		match event_type:
			STATE_EVENT_DEATH, STATE_EVENT_RESPAWN:
				if not _can_read(f, 1):
					push_warning("OnlineReplayManager: stateイベント(player_idx)の読み込みに失敗しました。")
					break
				payload["player_idx"] = f.get_8()
			STATE_EVENT_EXPLOSION:
				if not _can_read(f, 12):
					push_warning("OnlineReplayManager: stateイベント(explosion)の読み込みに失敗しました。")
					break
				payload["masu_x"] = f.get_32()
				payload["masu_y"] = f.get_32()
				payload["power"] = f.get_32()
		events.append({
			"frame": frame,
			"type": event_type,
			"payload": payload,
		})
	return events

## 状態イベント配列をファイルへ書き込み、種類ごとに payload を直列化する。
func _write_state_events(f: FileAccess, events: Array[Dictionary]) -> void:
	f.store_16(events.size())
	for ev in events:
		var event_type := int(ev.get("type", 0))
		var payload: Dictionary = ev.get("payload", {})
		f.store_32(int(ev.get("frame", 0)))
		f.store_8(event_type)
		match event_type:
			STATE_EVENT_DEATH, STATE_EVENT_RESPAWN:
				f.store_8(int(payload.get("player_idx", 0)))
			STATE_EVENT_EXPLOSION:
				f.store_32(int(payload.get("masu_x", 0)))
				f.store_32(int(payload.get("masu_y", 0)))
				f.store_32(int(payload.get("power", 1)))
