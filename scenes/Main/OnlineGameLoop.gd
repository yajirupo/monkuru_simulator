# OnlineGameLoop.gd
# オンラインゲームのロックステップ処理を担当
# 自分の入力送信 → 相手の入力受取 → ゲームロジック実行 の順で毎フレーム実行する
# res://scenes/Main/OnlineGameLoop.gd に配置

class_name OnlineGameLoop
extends RefCounted

# ============================================================
# 内部参照
# ============================================================
var _field:        Node2D
var _player_1p:    CharacterBody2D
var _game_obj_mgr: GameObjectManager
var _chat_mgr:     ChatInputManager

var _sync_timer: int = 0


# ============================================================
# セットアップ
# ============================================================

func setup(
		field:        Node2D,
		player_1p:    CharacterBody2D,
		game_obj_mgr: GameObjectManager,
		chat_mgr:     ChatInputManager) -> void:
	_field        = field
	_player_1p    = player_1p
	_game_obj_mgr = game_obj_mgr
	_chat_mgr     = chat_mgr


# ============================================================
# メインループ（_process から毎フレーム呼び出す）
# ============================================================

## ロックステップ処理を 1 フレーム分実行する。
## 切断・ESC による中断時は GameState.joutai_flag を更新して返る。
func process() -> void:
	# 切断検出 → メニューへ
	if not NetworkManager.is_linked:
		SoundManager.stop_bgm()
		_finalize_online_replay()
		_game_obj_mgr.clear_game_objects()
		GameState.joutai_flag = Enums.JoutaiType.ONLINE_MENU
		return

	# ESC で中断
	if KeyInput.key[KeyInput.KEY_INPUT_ESCAPE] == 1:
		SoundManager.stop_bgm()
		_finalize_online_replay()
		_game_obj_mgr.clear_game_objects()
		NetworkManager.disconnect_all()
		GameState.joutai_flag = Enums.JoutaiType.ONLINE_MENU
		return

	var my_idx:     int = NetworkManager.my_player_index()
	var remote_idx: int = NetworkManager.remote_player_index()

	# ① 自分の入力を確定して送信
	if _chat_mgr.is_active:
		KeyInput.zero_player_input()
	else:
		KeyInput.update_use_keys_for_player(my_idx)
	NetworkManager.send_frame_state(my_idx)

	# ② 相手のフレームデータを受取・GameState へ反映
	var fd_cr_use := -1
	if NetworkManager.has_remote_frame():
		var fd: Array = NetworkManager.consume_remote_frame()
		# 移動キー (fd[0-3] → use_key[0-3])
		for i in range(4):
			GameState.use_key[remote_idx][i] = fd[i]
		# アイテムキー (fd[4-6] → use_key[5-7])
		GameState.use_key[remote_idx][5] = fd[4]
		GameState.use_key[remote_idx][6] = fd[5]
		GameState.use_key[remote_idx][7] = fd[6]
		# くる射出キー (use_key[4]) は RPC で届くので 0
		GameState.use_key[remote_idx][4] = 0
		# fd[7] は cr_item_use
		if fd.size() > 7:
			fd_cr_use = fd[7]
	else:
		# 入力ホールド期限切れ後は相手入力を明示的にクリアする
		# （最終受信値の残留による押しっぱなし状態を防止）
		for i in range(8):
			GameState.use_key[remote_idx][i] = 0

	# ③ ゲームロジック実行
	OnlineReplayManager.online_key_to_replay()
	_player_1p.player_calc()
	_game_obj_mgr.calc_kuru()
	_game_obj_mgr.calc_bomb()

	# ④ cr_item_use を player_calc 後に上書き（player_calc によるリセットを上書きするため後勝ち）
	if fd_cr_use >= 0:
		GameState.player[remote_idx]["cr_item_use"] = fd_cr_use

	_field.field_disp_online(my_idx)

	# ⑤ 0.5 秒ごとに位置・向き・速さを送信して同期補正
	_sync_timer += 1
	if _sync_timer >= 30:
		_sync_timer = 0
		NetworkManager.send_player_sync(my_idx)


# ============================================================
# 入力エンコード / デコードユーティリティ
# ============================================================

## use_key を 1 バイト整数にエンコードする
func encode_input(player_idx: int) -> int:
	return OnlineReplay.encode_input(player_idx)

## 1 バイト整数を use_key にデコードする
func decode_input(player_idx: int, byte: int) -> void:
	OnlineReplay.decode_input(player_idx, byte)

func _finalize_online_replay() -> void:
	GameState.replay_data[0][GameState.p_replay_data] = OnlineReplayManager.TERMINATOR
	GameState.replay_data[1][GameState.p_replay_data] = OnlineReplayManager.TERMINATOR
	GameState.remember_last_online_game_replay()
