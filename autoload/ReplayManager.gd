# Replay.gd
# replay.cpp の移植（シングル用リプレイ）
# Autoload 名: ReplayManager

extends Node

const REPLAY_DIR  := "user://replays/"
const REPLAY_EXT  := ".dat"
const TERMINATOR  := 255  # char(255) 終端マーカー

# ============================================================
# replayDataRead(num) の移植
# ============================================================
func replay_data_read(num: int) -> bool:
	var path := REPLAY_DIR + "plac%02d%s" % [num, REPLAY_EXT]
	if not FileAccess.file_exists(path):
		return false

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false

	GameState.current_stage = GameState.clamp_stage(f.get_8())

	var p: Dictionary = GameState.player[0]
	p["name"]        = _read_string(f, 32)
	p["max_speed"]   = f.get_32()
	p["max_shot"]    = f.get_32()
	p["max_power"]   = f.get_32()
	p["item_speed"]  = p["max_speed"]
	p["item_shot"]   = p["max_shot"]
	p["item_power"]  = p["max_power"]
	p["speed"]       = Constants.PLAYER_DEFAULT_SPEED + p["item_speed"] * Constants.PLAYER_SPEED_UP
	var _ks := f.get_32()
	p["kuru_speed"]  = _ks if _ks < 0x80000000 else _ks - 0x100000000
	p["kuru_dankai"] = f.get_32()
	p["kuru_kankaku"]= f.get_32()
	for i in range(3):
		p["cr_item"][i] = f.get_32()

	GameState.p_replay_data = 0
	while true:
		var b := f.get_8()
		GameState.replay_data[0][GameState.p_replay_data] = b
		if b == TERMINATOR:
			break
		GameState.p_replay_data += 1

	GameState.replay_chat_events = _read_chat_events(f)
	GameState.replay_chat_event_cursor = 0

	f.close()
	
	# 追加：再生前に use_key を必ずゼロクリアする
	# replay_to_key() が += 1 でインクリメントするため、
	# 前回ゲームの残余値が残っていると最初のフレームでズレが生じる
	for i in range(8):
		GameState.use_key[0][i] = 0
	
	# 再生開始位置を先頭に戻す
	GameState.p_replay_data = 0
	return true


# ============================================================
# replayDataWrite(num) の移植
# ============================================================
func replay_data_write(num: int) -> void:
	if not GameState.has_last_single_replay:
		return

	DirAccess.make_dir_recursive_absolute(REPLAY_DIR)
	var path := REPLAY_DIR + "plac%02d%s" % [num, REPLAY_EXT]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return

	var m: Dictionary = GameState.last_single_replay_menu
	f.store_8(GameState.clamp_stage(int(m.get("stage", 0))))
	_write_string(f, m["name"], 32)
	f.store_32(m["speed"])
	f.store_32(m["shot"])
	f.store_32(m["power"])
	f.store_32(m["kuru_speed"])
	f.store_32(m["kuru_dankai"])
	f.store_32(m["kuru_kankaku"])
	for i in range(3):
		f.store_32(m["item_type"][i])

	for b in GameState.last_single_replay_data:
		f.store_8(b)
		if b == TERMINATOR:
			break
	_write_chat_events(f, GameState.last_single_replay_chat_events)
	f.close()


# ============================================================
# keyToReplay() の移植
# キー入力を1バイトに圧縮してリプレイ配列に記録
# ============================================================
func key_to_replay() -> bool:
	if GameState.p_replay_data == Constants.MAX_REPLAY_FLAME - 1:
		GameState.replay_data[0][Constants.MAX_REPLAY_FLAME - 1] = TERMINATOR
		return false

	var tmp := 0
	for i in range(8):
		tmp *= 2
		if GameState.use_key[0][7 - i] > 0:
			tmp += 1

	GameState.replay_data[0][GameState.p_replay_data] = tmp
	GameState.p_replay_data += 1
	return true


# ============================================================
# ReplayToKey() の移植
# リプレイ配列からキー入力を復元
# ============================================================
func replay_to_key() -> bool:
	if GameState.replay_data[0][GameState.p_replay_data] == TERMINATOR:
		return false

	var tmp: int = GameState.replay_data[0][GameState.p_replay_data]
	for i in range(8):
		if tmp % 2 == 1:
			GameState.use_key[0][i] += 1
		else:
			GameState.use_key[0][i] = 0
		tmp /= 2

	GameState.p_replay_data += 1
	return true


# ============================================================
# ファイルI/Oヘルパー
# ============================================================
func _read_string(f: FileAccess, length: int) -> String:
	var bytes := f.get_buffer(length)
	# null 終端を探してその手前までを UTF-8 としてデコード
	var end := bytes.size()
	for i in range(bytes.size()):
		if bytes[i] == 0:
			end = i
			break
	return bytes.slice(0, end).get_string_from_utf8()

## 文字列を固定長バッファへ UTF-8 + NULL 終端形式で書き込む。
func _write_string(f: FileAccess, s: String, length: int) -> void:
	var bytes := s.to_utf8_buffer()
	# null 終端が収まるよう (length-1) バイトに切り詰める
	while bytes.size() >= length:
		bytes.resize(bytes.size() - 1)
		# 継続バイト (0x80〜0xBF) を末尾から除去
		while bytes.size() > 0 and (bytes[bytes.size() - 1] & 0xC0) == 0x80:
			bytes.resize(bytes.size() - 1)
		# 継続バイトを除去した後に残ったマルチバイト先頭バイト (0xC0〜0xFF) も除去
		# （先頭バイトだけ残すと不完全な UTF-8 シーケンスになるため）
		if bytes.size() > 0 and bytes[bytes.size() - 1] >= 0xC0:
			bytes.resize(bytes.size() - 1)
	for i in range(length):
		f.store_8(bytes[i] if i < bytes.size() else 0)

## リプレイ末尾に保存されたチャットイベント配列を読み込む。
func _read_chat_events(f: FileAccess) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if f.get_position() >= f.get_length():
		return events
	var count := f.get_16()
	for _i in range(count):
		if f.get_position() >= f.get_length():
			break
		var frame := f.get_32()
		var r := float(f.get_8()) / 255.0
		var g := float(f.get_8()) / 255.0
		var b := float(f.get_8()) / 255.0
		var a := float(f.get_8()) / 255.0
		var name_len := f.get_16()
		var name2 := f.get_buffer(name_len).get_string_from_utf8()
		var msg_len := f.get_16()
		var message := f.get_buffer(msg_len).get_string_from_utf8()
		events.append({
			"frame": frame,
			"player_name": name2,
			"message": message,
			"color": Color(r, g, b, a),
		})
	return events

## チャットイベント配列をリプレイファイル形式で書き込む。
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
