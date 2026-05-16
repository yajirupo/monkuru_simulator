# KeyInput.gd
# keyInput.cpp の移植
# Autoload 名: KeyInput

extends Node

var key: Array[int] = []

# DXキーコード定数
const KEY_INPUT_ESCAPE  := 0x01

# DXキーコード → Godot Key の対応表（配列で管理）
# [dx_code, godot_key] のペア
const DX_GODOT_MAP: Array = [
	[0x01, KEY_ESCAPE],
	[0x0E, KEY_BACKSPACE], [0x0F, KEY_TAB],
	[0x1C, KEY_ENTER],
	[0x39, KEY_SPACE],
	[0xC8, KEY_UP], [0xD0, KEY_DOWN],
	[0xCB, KEY_LEFT], [0xCD, KEY_RIGHT],
	[0x1E, KEY_A], [0x30, KEY_B], [0x2E, KEY_C], [0x20, KEY_D],
	[0x12, KEY_E], [0x21, KEY_F], [0x22, KEY_G], [0x23, KEY_H],
	[0x17, KEY_I], [0x24, KEY_J], [0x25, KEY_K], [0x26, KEY_L],
	[0x32, KEY_M], [0x31, KEY_N], [0x18, KEY_O], [0x19, KEY_P],
	[0x10, KEY_Q], [0x13, KEY_R], [0x1F, KEY_S], [0x14, KEY_T],
	[0x16, KEY_U], [0x2F, KEY_V], [0x11, KEY_W], [0x2D, KEY_X],
	[0x15, KEY_Y], [0x2C, KEY_Z],
	[0x02, KEY_1], [0x03, KEY_2], [0x04, KEY_3], [0x05, KEY_4],
	[0x06, KEY_5], [0x07, KEY_6], [0x08, KEY_7], [0x09, KEY_8],
	[0x0A, KEY_9], [0x0B, KEY_0],
	[0x27, KEY_SEMICOLON], [0x28, KEY_COLON], [0x29, KEY_APOSTROPHE], [0x2B, KEY_BACKSLASH],
	[0x33, KEY_COMMA], [0x34, KEY_PERIOD], [0x35, KEY_SLASH],
	# テンキー
	[0x52, KEY_KP_0], [0x4F, KEY_KP_1], [0x50, KEY_KP_2], [0x51, KEY_KP_3],
	[0x4B, KEY_KP_4], [0x4C, KEY_KP_5], [0x4D, KEY_KP_6],
	[0x47, KEY_KP_7], [0x48, KEY_KP_8], [0x49, KEY_KP_9],
	[0x37, KEY_KP_MULTIPLY], [0x4E, KEY_KP_ADD],
	[0x4A, KEY_KP_SUBTRACT], [0x53, KEY_KP_PERIOD], [0x35, KEY_KP_DIVIDE],
	[0x9C, KEY_KP_ENTER],
	# ファンクションキー
	[0x3B, KEY_F1], [0x3C, KEY_F2], [0x3D, KEY_F3], [0x3E, KEY_F4],
	[0x3F, KEY_F5], [0x40, KEY_F6], [0x41, KEY_F7], [0x42, KEY_F8],
	[0x43, KEY_F9], [0x44, KEY_F10], [0x57, KEY_F11], [0x58, KEY_F12],
]

# dx_code -> godot key (int) の高速ルックアップ配列
var _dx_to_godot: Array[int] = []
# godot key -> dx_code の辞書
var _godot_to_dx: Dictionary = {}

func _ready() -> void:
	key.resize(256)
	key.fill(0)
	_dx_to_godot.resize(256)
	_dx_to_godot.fill(0)
	for pair in DX_GODOT_MAP:
		var dx: int = pair[0]
		var gk: int = pair[1]
		_dx_to_godot[dx] = gk
		_godot_to_dx[gk] = dx

func update_keys() -> void:
	for pair in DX_GODOT_MAP:
		var dx: int = pair[0]
		var gk: int = pair[1]
		if Input.is_key_pressed(gk as Key):
			key[dx] += 1
		else:
			key[dx] = 0

func get_key(godot_key_code: int) -> int:
	var dx: int = _godot_to_dx.get(godot_key_code, -1)
	if dx < 0 or dx >= 256:
		return 0
	return key[dx]

func clear_gameplay_key_counters(godot_key_codes: Array) -> void:
	# READY?/APPEAR 中の人間プレイヤー操作はゲーム入力として扱わない。
	# ESC はメニュー制御用なので、プレイヤー操作キーに割り当てられていても残す。
	for godot_key_code in godot_key_codes:
		var dx: int = _godot_to_dx.get(int(godot_key_code), -1)
		if dx >= 0 and dx < key.size() and dx != KEY_INPUT_ESCAPE:
			key[dx] = 0

func update_use_keys() -> void:
	match GameState.joutai_flag:
		Enums.JoutaiType.SINGLE_GAME:
			for i in range(8):
				GameState.use_key[0][i] = get_key(GameState.use_key_single[i])
		Enums.JoutaiType.VS_GAME:
			for i in range(8):
				GameState.use_key[0][i] = get_key(GameState.use_key_vs_1p[i])
				GameState.use_key[1][i] = get_key(GameState.use_key_vs_2p[i])
		Enums.JoutaiType.VS_COM_GAME:
			# P1 は Main.gd の COM ロジックで毎フレーム更新する
			for i in range(8):
				GameState.use_key[0][i] = get_key(GameState.use_key_single[i])
		Enums.JoutaiType.ONLINE_GAME:
			# 自分のインデックスの use_key だけ更新（相手は NetworkManager が更新）
			var my_idx := NetworkManager.my_player_index()
			for i in range(8):
				GameState.use_key[my_idx][i] = get_key(GameState.use_key_single[i])

## 入力をゼロクリアする
func zero_player_input() -> void:
	match GameState.joutai_flag:
		Enums.JoutaiType.SINGLE_GAME:
			for i in range(8):
				GameState.use_key[0][i] = 0
		Enums.JoutaiType.VS_GAME:
			for i in range(8):
				GameState.use_key[0][i] = 0
				GameState.use_key[1][i] = 0
		Enums.JoutaiType.VS_COM_GAME:
			# P1 は Main.gd の COM ロジックで毎フレーム更新する
			for i in range(8):
				GameState.use_key[0][i] = 0
		Enums.JoutaiType.ONLINE_GAME:
			# 自分のインデックスの use_key だけ更新（相手は NetworkManager が更新）
			var my_idx := NetworkManager.my_player_index()
			for i in range(8):
				GameState.use_key[my_idx][i] = 0

func update_use_keys_for_player(player_idx: int) -> void:
	# ONLINE_GAMEでは常に練習モード用キー(use_key_single)を自分のインデックスに設定
	var my_idx := NetworkManager.my_player_index()
	if player_idx != my_idx:
		return
	for i in range(8):
		GameState.use_key[my_idx][i] = get_key(GameState.use_key_single[i])
