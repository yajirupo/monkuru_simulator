# VsComReplayManager.gd
# vsReplay.cpp の移植（VS COM用リプレイ）
# Autoload 名: VsComReplayManager

extends Node

const REPLAY_DIR := "user://replays/"
const REPLAY_EXT := ".dat"
const REPLAY_PREFIX := "vscom"
const TERMINATOR := GameState.REPLAY_TERMINATOR

## VS COM リプレイファイルを読み込み、プレイヤー情報と入力列を復元する。
func vs_com_replay_data_read(num: int) -> bool:
	var path := REPLAY_DIR + REPLAY_PREFIX + "%02d%s" % [num, REPLAY_EXT]
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false

	GameState.current_stage = GameState.clamp_stage(f.get_8())

	for i in range(2):
		var p: Dictionary = GameState.player[i]
		p["name"]          = _read_string(f, 32)
		p["character"]     = f.get_32()
		p["kuru_type"]     = f.get_32()
		for j in range(3):
			p["cr_item"][j] = f.get_32()

	GameState.p_replay_data = 0
	while true:
		var b0 := f.get_8()
		var b1 := f.get_8()
		GameState.replay_data[0][GameState.p_replay_data] = b0
		GameState.replay_data[1][GameState.p_replay_data] = b1
		if b1 == TERMINATOR:
			break
		GameState.p_replay_data += 1

	GameState.replay_chat_events = _read_chat_events(f)
	GameState.replay_chat_event_cursor = 0

	GameState.replay_data[0][GameState.p_replay_data] = TERMINATOR
	GameState.replay_data[1][GameState.p_replay_data] = TERMINATOR
	f.close()
	
	# 追加：再生前に use_key を必ずゼロクリアする
	# replay_to_key() が += 1 でインクリメントするため、
	# 前回ゲームの残余値が残っていると最初のフレームでズレが生じる
	for i in range(8):
		GameState.use_key[0][i] = 0
		GameState.use_key[1][i] = 0
		
	GameState.p_replay_data = 0
	return true


## VS COM 対戦終了時に保存済みリプレイ情報をファイルへ書き出す。
func vs_com_replay_data_write(num: int) -> void:
	if not GameState.has_last_vs_replay or not GameState.last_vs_replay_is_com:
		return

	DirAccess.make_dir_recursive_absolute(REPLAY_DIR)
	var path := REPLAY_DIR + REPLAY_PREFIX + "%02d%s" % [num, REPLAY_EXT]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return

	var vm: Dictionary = GameState.last_vs_replay_menu
	f.store_8(GameState.clamp_stage(int(vm.get("stage", 0))))
	for i in range(2):
		_write_string(f, vm["name"][i], 32)
		f.store_32(vm["player_type"][i])
		f.store_32(vm["kuru_type"][i])
		for j in range(3):
			f.store_32(vm["item_type"][i][j])

	var frame_count := mini(GameState.last_vs_replay_data[0].size(), GameState.last_vs_replay_data[1].size())
	for i in range(frame_count):
		f.store_8(GameState.last_vs_replay_data[0][i])
		f.store_8(GameState.last_vs_replay_data[1][i])
		if GameState.last_vs_replay_data[1][i] == TERMINATOR:
			break
	_write_chat_events(f, GameState.last_vs_replay_chat_events)
	f.close()


## 現在フレームの両プレイヤー入力を 1byte ずつに圧縮して記録する。
func vs_com_key_to_replay() -> bool:
	if GameState.p_replay_data == Constants.MAX_REPLAY_FLAME - 1:
		GameState.replay_data[0][Constants.MAX_REPLAY_FLAME - 1] = TERMINATOR
		GameState.replay_data[1][Constants.MAX_REPLAY_FLAME - 1] = TERMINATOR
		return false

	for j in range(2):
		var tmp := 0
		for i in range(8):
			tmp *= 2
			if GameState.use_key[j][7 - i] > 0:
				tmp += 1
		GameState.replay_data[j][GameState.p_replay_data] = tmp

	GameState.p_replay_data += 1
	return true


## 記録済み入力を復元し、VS COM 再生用の use_key に反映する。
func vs_com_replay_to_key() -> bool:
	if GameState.replay_data[1][GameState.p_replay_data] == TERMINATOR:
		return false

	for j in range(2):
		var tmp: int = GameState.replay_data[j][GameState.p_replay_data]
		for i in range(8):
			if tmp % 2 == 1:
				GameState.use_key[j][i] += 1
			else:
				GameState.use_key[j][i] = 0
			tmp /= 2

	GameState.p_replay_data += 1
	return true


## 固定長バッファから NULL 終端文字列を読み取る。
func _read_string(f: FileAccess, length: int) -> String:
	var bytes := f.get_buffer(length)
	# null 終端を探してその手前までを UTF-8 としてデコード
	var end := bytes.size()
	for i in range(bytes.size()):
		if bytes[i] == 0:
			end = i
			break
	return bytes.slice(0, end).get_string_from_utf8()

## 文字列を固定長 UTF-8（NULL 終端）で書き込む。
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

## VS COM リプレイ末尾のチャットイベント列を読み込む。
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

## チャットイベント列を VS COM リプレイ形式で書き込む。
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
