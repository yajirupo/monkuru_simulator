# VsComReplay.gd
# vsReplay.cpp の移植（VS COM用リプレイ）
# Autoload 名: VsComReplay

extends Node

const REPLAY_DIR := "user://replays/"
const REPLAY_EXT := ".dat"
const REPLAY_PREFIX := "vscom"
const TERMINATOR := GameState.REPLAY_TERMINATOR

# VS COM リプレイをファイルから読み込む。
# 2人分のキャラ設定を復元し、入力列を終端まで展開する。
func vs_com_replay_data_read(num: int) -> bool:
	var path := REPLAY_DIR + REPLAY_PREFIX + "%02d%s" % [num, REPLAY_EXT]
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false

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

	GameState.replay_data[0][GameState.p_replay_data] = TERMINATOR
	GameState.replay_data[1][GameState.p_replay_data] = TERMINATOR
	f.close()
	return true


# VS COM リプレイをファイルへ保存する。
# 事前設定（名前/タイプ/くる/装備）と入力ログをまとめて書き込む。
func vs_com_replay_data_write(num: int) -> void:
	DirAccess.make_dir_recursive_absolute(REPLAY_DIR)
	var path := REPLAY_DIR + REPLAY_PREFIX + "%02d%s" % [num, REPLAY_EXT]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return

	var vm := GameData.vs_com_menu_tmp
	for i in range(2):
		_write_string(f, vm["name"][i], 32)
		f.store_32(vm["player_type"][i])
		f.store_32(vm["kuru_type"][i])
		for j in range(3):
			f.store_32(vm["item_type"][i][j])

	GameState.p_replay_data = 0
	while GameState.replay_data[1][GameState.p_replay_data] != TERMINATOR:
		f.store_8(GameState.replay_data[0][GameState.p_replay_data])
		f.store_8(GameState.replay_data[1][GameState.p_replay_data])
		GameState.p_replay_data += 1
	f.store_8(GameState.replay_data[0][GameState.p_replay_data])
	f.store_8(GameState.replay_data[1][GameState.p_replay_data])
	f.close()


# 2P 分の use_key を 1byte ずつ圧縮して replay_data に記録する。
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


# replay_data から 2P 分の入力状態を復元する。
# 押下中キーのカウンタを進め、未押下キーはリセットする。
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


# 固定長バイト列（ヌル終端）を文字列として読み出す。
func _read_string(f: FileAccess, length: int) -> String:
	var bytes := f.get_buffer(length)
	var result := ""
	for b in bytes:
		if b == 0:
			break
		result += char(b)
	return result

# 文字列を固定長で書き込み、余剰分は 0 埋めする。
func _write_string(f: FileAccess, s: String, length: int) -> void:
	var bytes := s.to_ascii_buffer()
	for i in range(length):
		f.store_8(bytes[i] if i < bytes.size() else 0)
