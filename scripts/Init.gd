# Init.gd
# init.cpp の移植（init() / iniGame()）
# Autoload 名: Init

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

	# 各メニュー初期化
	GameState.main_menu_cursor = 0
	GameData.menu["cursor"] = 12
	GameData.vs_menu["cursor"] = 16
	GameState.key_config_menu_cursor = 0

	# チャット初期化
	GameState.chat_str = ["", "", ""]
	GameState.chat_color = [Color.BLACK, Color.BLACK, Color.BLACK]


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

	# BGM再生
	SoundManager.play_bgm(true)

	# チャット初期化
	GameState.chat_str = ["", "", ""]
	GameState.chat_color = [Color.BLACK, Color.BLACK, Color.BLACK]

	# リプレイ記録ポインタ初期化
	GameState.p_replay_data = 0
	GameState.init_replay()

	# useKey初期化
	for j in range(2):
		for i in range(8):
			GameState.use_key[j][i] = 0

	# カウンタリセット
	GameState.count = 0


func _apply_stage_hard_blocks() -> void:
	# 現状は試験実装として、ステージ1のみ中央に 2x2 のハードブロックを配置する
	if GameState.clamp_stage(GameState.current_stage) != 1:
		return

	var center_x0 := 8
	var center_y0 := 5
	for y in range(center_y0, center_y0 + 2):
		for x in range(center_x0, center_x0 + 2):
			if y >= 0 and y < Constants.FIELD_ROWS and x >= 0 and x < Constants.FIELD_COLS:
				GameState.masu[x][y]["kind"] = Enums.MasuKind.HARD_BLOCK


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
