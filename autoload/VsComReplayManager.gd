extends Node

const REPLAY_DIR := "user://replays/"
const REPLAY_EXT := ".dat"
const REPLAY_PREFIX := "vscom"
const TERMINATOR := GameState.REPLAY_TERMINATOR
const FORMAT_MAGIC := "VSC2"
const FORMAT_VERSION := 2

func vs_com_replay_data_read(num: int) -> bool:
	GameState.init_replay()   # 古いデータを完全にクリアする
	GameState.vs_com_replay_frame_count = 0
	
	var path := REPLAY_DIR + REPLAY_PREFIX + "%02d%s" % [num, REPLAY_EXT]
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	if f.get_length() < FORMAT_MAGIC.length() + 1:
		f.close()
		return false
	if f.get_buffer(FORMAT_MAGIC.length()).get_string_from_ascii() != FORMAT_MAGIC:
		# 旧フォーマットは入力値 255 と終端を区別できず同期ズレの原因になるため読み込まない。
		f.close()
		return false
	var version := int(f.get_8())
	if version != FORMAT_VERSION:
		f.close()
		return false

	GameState.current_stage = GameState.clamp_stage(f.get_8())
	var player_count := clampi(int(f.get_8()), 2, Constants.MAX_PLAYER)
	GameState.vs_com_replay_player_count = player_count
	for i in range(player_count):
		var p: Dictionary = GameState.player[i]
		p["name"] = _read_string(f, 32)
		p["character"] = f.get_32()
		p["kuru_type"] = f.get_32()
		for j in range(3):
			p["cr_item"][j] = f.get_32()

	if f.get_position() + 4 > f.get_length():
		f.close()
		return false
	var frame_count := clampi(int(f.get_32()), 0, Constants.MAX_REPLAY_FLAME - 1)
	GameState.vs_com_replay_frame_count = frame_count
	for frame in range(frame_count):
		if f.get_position() + Constants.MAX_PLAYER > f.get_length():
			f.close()
			return false
		for j in range(Constants.MAX_PLAYER):
			GameState.replay_data[j][frame] = f.get_8()

	GameState.p_replay_data = frame_count
	for j in range(Constants.MAX_PLAYER):
		GameState.replay_data[j][GameState.p_replay_data] = TERMINATOR

	GameState.replay_chat_events = _read_chat_events(f)
	GameState.replay_chat_event_cursor = 0
	
	# 開始位置割り当て情報があれば復元、なければ空
	if f.get_position() < f.get_length():
		var size := f.get_8()
		var assignments: Array[int] = []
		for _i in range(size):
			if f.get_position() >= f.get_length():
				break
			assignments.append(f.get_8())
		GameState.vs_com_start_assignments = assignments
	else:
		GameState.vs_com_start_assignments = []

	f.close()

	for j in range(Constants.MAX_PLAYER):
		for i in range(8):
			GameState.use_key[j][i] = 0
	GameState.p_replay_data = 0
	return true

func vs_com_replay_data_write(num: int) -> void:
	if not GameState.has_last_vs_replay or not GameState.last_vs_replay_is_com:
		return
	DirAccess.make_dir_recursive_absolute(REPLAY_DIR)
	var path := REPLAY_DIR + REPLAY_PREFIX + "%02d%s" % [num, REPLAY_EXT]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return

	var vm: Dictionary = GameState.last_vs_replay_menu
	var player_count := int(vm.get("player_count", Constants.MAX_PLAYER))
	f.store_buffer(FORMAT_MAGIC.to_ascii_buffer())
	f.store_8(FORMAT_VERSION)
	f.store_8(GameState.clamp_stage(int(vm.get("stage", 0))))
	f.store_8(clampi(player_count, 2, Constants.MAX_PLAYER))
	for i in range(player_count):
		_write_string(f, vm["name"][i], 32)
		f.store_32(vm["player_type"][i])
		f.store_32(vm["kuru_type"][i])
		for j in range(3):
			f.store_32(vm["item_type"][i][j])

	var frame_count := clampi(GameState.last_vs_replay_frame_count, 0, Constants.MAX_REPLAY_FLAME - 1)
	f.store_32(frame_count)
	for i in range(frame_count):
		for j in range(Constants.MAX_PLAYER):
			var data: PackedByteArray = GameState.last_vs_replay_data[j]
			f.store_8(data[i] if i < data.size() else 0)
	_write_chat_events(f, GameState.last_vs_replay_chat_events)
	
	# 開始位置割り当て情報を追記（スナップショットから取得）
	var assignments: Array = vm.get("start_assignments", [])
	f.store_8(assignments.size())
	for a in assignments:
		f.store_8(a)
		
	f.close()

func vs_com_key_to_replay() -> bool:
	if GameState.p_replay_data == Constants.MAX_REPLAY_FLAME - 1:
		for j in range(Constants.MAX_PLAYER):
			GameState.replay_data[j][Constants.MAX_REPLAY_FLAME - 1] = TERMINATOR
		GameState.vs_com_replay_frame_count = Constants.MAX_REPLAY_FLAME - 1
		return false
	for j in range(Constants.MAX_PLAYER):
		var tmp := 0
		for i in range(8):
			if GameState.use_key[j][i] > 0:
				tmp |= 1 << i
		GameState.replay_data[j][GameState.p_replay_data] = tmp
	GameState.p_replay_data += 1
	GameState.vs_com_replay_frame_count = GameState.p_replay_data
	return true

func vs_com_replay_to_key() -> bool:
	if GameState.p_replay_data >= GameState.vs_com_replay_frame_count:
		return false
	for j in range(Constants.MAX_PLAYER):
		var tmp: int = GameState.replay_data[j][GameState.p_replay_data]
		for i in range(8):
			if (tmp & (1 << i)) != 0:
				GameState.use_key[j][i] += 1
			else:
				GameState.use_key[j][i] = 0
	GameState.p_replay_data += 1
	return true

func _read_string(f: FileAccess, length: int) -> String:
	var bytes := f.get_buffer(length)
	var end := bytes.size()
	for i in range(bytes.size()):
		if bytes[i] == 0:
			end = i
			break
	return bytes.slice(0, end).get_string_from_utf8()

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

func _read_chat_events(f: FileAccess) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if f.get_position() >= f.get_length():
		return events
	var count := f.get_16()
	for _i in range(count):
		if f.get_position() >= f.get_length():
			break
		var frame := f.get_32()
		var c := Color(
			float(f.get_8()) / 255.0,
			float(f.get_8()) / 255.0,
			float(f.get_8()) / 255.0,
			float(f.get_8()) / 255.0
		)
		var name_bytes := f.get_buffer(f.get_16()).get_string_from_utf8()
		var msg_bytes := f.get_buffer(f.get_16()).get_string_from_utf8()
		events.append({
			"frame": frame,
			"player_name": name_bytes,
			"message": msg_bytes,
			"color": c,
		})
	return events

func _write_chat_events(f: FileAccess, events: Array[Dictionary]) -> void:
	f.store_16(events.size())
	for ev in events:
		f.store_32(int(ev.get("frame", 0)))
		var c: Color = ev.get("color", Color.BLACK)
		f.store_8(int(round(clamp(c.r, 0.0, 1.0) * 255.0)))
		f.store_8(int(round(clamp(c.g, 0.0, 1.0) * 255.0)))
		f.store_8(int(round(clamp(c.b, 0.0, 1.0) * 255.0)))
		f.store_8(int(round(clamp(c.a, 0.0, 1.0) * 255.0)))
		var n := String(ev.get("player_name", "")).to_utf8_buffer()
		f.store_16(n.size()); f.store_buffer(n)
		var m := String(ev.get("message", "")).to_utf8_buffer()
		f.store_16(m.size()); f.store_buffer(m)
