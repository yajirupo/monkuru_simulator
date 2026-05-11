# Replay.gd
# replay.cpp の移植（シングル用リプレイ）
# Autoload 名: Replay

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
	var _kuru_speed_stat: int = _ks if _ks < 0x80000000 else _ks - 0x100000000
	p["kuru_speed"]  = Constants.kuru_speed_stat_to_move_speed(_kuru_speed_stat)
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

	f.close()
	return true


# ============================================================
# replayDataWrite(num) の移植
# ============================================================
func replay_data_write(num: int) -> void:
	DirAccess.make_dir_recursive_absolute(REPLAY_DIR)
	var path := REPLAY_DIR + "plac%02d%s" % [num, REPLAY_EXT]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return

	var m := GameData.menu_tmp
	_write_string(f, m["name"], 13)
	f.store_32(m["speed"])
	f.store_32(m["shot"])
	f.store_32(m["power"])
	f.store_32(m["kuru_speed"])
	f.store_32(m["kuru_dankai"])
	f.store_32(m["kuru_kankaku"])
	for i in range(3):
		f.store_32(m["item_type"][i])

	GameState.p_replay_data = 0
	while GameState.replay_data[0][GameState.p_replay_data] != TERMINATOR:
		f.store_8(GameState.replay_data[0][GameState.p_replay_data])
		GameState.p_replay_data += 1
	f.store_8(TERMINATOR)
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
	var result := ""
	for b in bytes:
		if b == 0:
			break
		result += char(b)
	return result

func _write_string(f: FileAccess, s: String, length: int) -> void:
	var bytes := s.to_ascii_buffer()
	for i in range(length):
		f.store_8(bytes[i] if i < bytes.size() else 0)
