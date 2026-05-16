# GameInit.gd
# init.cpp の移植（init() / iniGame()）
# Autoload 名: GameInit

extends Node

# ============================================================
# init() の移植
# アプリ起動時に一度だけ呼ぶ
# ============================================================
func init_all() -> void:
	GameState.count = 0

	# キー入力初期化
	KeyInput.key.fill(0)

	# 状態初期化
	GameState.joutai_flag = Enums.JoutaiType.MAIN_MENU

	# リプレイデータ初期化
	GameState.p_replay_data = 0
	GameState.init_replay()
	GameState.vs_replay_return_state = Enums.JoutaiType.VS_MENU

	# 各メニュー初期化
	GameState.main_menu_cursor = 0
	GameData.menu["cursor"] = 12
	GameData.vs_menu["cursor"] = 16
	GameState.key_config_menu_cursor = 0

	# チャット初期化
	GameState.chat_str = ["", "", ""]
	GameState.chat_color = [Color.BLACK, Color.BLACK, Color.BLACK]
	GameState.reset_replay_chat_events()
	GameState.reset_online_replay_sync_events()
	

# ============================================================
# iniGame() の移植
# ゲーム開始・リスタート時に呼ぶ
# ============================================================
func ini_game(scene_root: Node) -> void:
	# プレイヤー初期化は Player ノードが行う
	# （scene_root.get_node("Player").ini_player() を Main.gd から呼ぶ）

	# くる全削除
	_release_dynamic_children(scene_root.get_node_or_null("KuruContainer"))

	# 爆風全削除
	_release_dynamic_children(scene_root.get_node_or_null("BombContainer"))

	# フィールド初期化（全マスをBROKENに）
	for x in range(Constants.FIELD_COLS):
		for y in range(Constants.FIELD_ROWS):
			GameState.masu[x][y]["kind"] = Enums.MasuKind.BROKEN
	_apply_stage_hard_blocks()

	# チャット初期化
	GameState.chat_str = ["", "", ""]
	GameState.chat_color = [Color.BLACK, Color.BLACK, Color.BLACK]
	GameState.replay_chat_event_cursor = 0

	# リプレイ記録ポインタ初期化
	# リプレイ再生中はデータを消さない
	if GameState.joutai_flag not in [
		Enums.JoutaiType.SINGLE_REPLAY, Enums.JoutaiType.VS_REPLAY,
		Enums.JoutaiType.VS_COM_REPLAY, Enums.JoutaiType.ONLINE_REPLAY
	]:
		GameState.p_replay_data = 0
		GameState.init_replay()
		GameState.reset_replay_chat_events()
		GameState.reset_online_replay_sync_events()

	# useKey初期化
	for j in range(Constants.MAX_PLAYER):
		for i in range(8):
			GameState.use_key[j][i] = 0

	# カウンタリセット
	GameState.count = 0


func _apply_stage_hard_blocks() -> void:
	var stage := GameState.clamp_stage(GameState.current_stage)
	var hard_block_cells: Array[Vector2i] = GameState.get_stage_hard_block_cells(stage)

	for cell in hard_block_cells:
		if cell.y >= 0 and cell.y < Constants.FIELD_ROWS and cell.x >= 0 and cell.x < Constants.FIELD_COLS:
			GameState.masu[cell.x][cell.y]["kind"] = Enums.MasuKind.HARD_BLOCK


func _release_dynamic_children(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		if child == null or not is_instance_valid(child):
			continue
		if child.has_method("prepare_for_free"):
			child.call("prepare_for_free")
		if child.get_parent() == container:
			container.remove_child(child)
		child.queue_free()
