class_name OnlineReplay
extends RefCounted

# use_key の先頭8要素（方向4 + 射出 + アイテム3）を
# 1フレーム分の入力としてビット圧縮する。
const INPUT_KEY_COUNT := 8

# use_key[player_idx][0..7] を 1byte にエンコードする。
# 下位ビット側が use_key[*][0] になるように保存しているため、
# 復号時はビットシフトだけで元の入力を復元できる。
static func encode_input(player_idx: int) -> int:
	var tmp := 0
	for i in range(INPUT_KEY_COUNT):
		tmp *= 2
		if GameState.use_key[player_idx][INPUT_KEY_COUNT - 1 - i] > 0:
			tmp += 1
	return tmp

# 受信した 1byte 入力を use_key に反映する。
# 押下中キーは「連続フレーム押下」として扱うため +1、
# 離されているキーは 0 へリセットする。
static func decode_input(player_idx: int, byte: int) -> void:
	var value := byte
	for i in range(INPUT_KEY_COUNT):
		if value & 1 == 1:
			GameState.use_key[player_idx][i] += 1
		else:
			GameState.use_key[player_idx][i] = 0
		value >>= 1
