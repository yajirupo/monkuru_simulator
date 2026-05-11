# Main.gd
# main.cpp の WinMain ループの移植
# メインシーンのルートノードにアタッチ

extends Node2D

# ============================================================
# 子ノード参照
# ============================================================
@onready var field:          Node2D           = $Field
@onready var player_1p:      CharacterBody2D  = $Player1P
@onready var player_2p:      CharacterBody2D  = $Player2P
@onready var kuru_container: Node2D           = $KuruContainer
@onready var bomb_container: Node2D           = $BombContainer
@onready var hard_block_container: Node2D      = $HardBlockContainer
@onready var dbg:            Control = $ComDebugOverlay
@onready var esc_hint_lbl:   Label = $GameHintLayer/EscHintLabel

# UI シーン参照（add_child で切り替え）
var _current_ui: Node = null

# UI シーンのパス
const UI_SCENES := {
	Enums.JoutaiType.MAIN_MENU:           "res://scenes/UI/MainMenu.tscn",
	Enums.JoutaiType.SINGLE_MENU:         "res://scenes/UI/Menu.tscn",
	Enums.JoutaiType.VS_MENU:             "res://scenes/UI/VsMenu.tscn",
	Enums.JoutaiType.VS_COM_MENU:         "res://scenes/UI/VsComMenu.tscn",
	Enums.JoutaiType.ONLINE_MENU:         "res://scenes/UI/OnlineMenu.tscn",
	Enums.JoutaiType.ONLINE_LOBBY:        "res://scenes/UI/OnlineMenu.tscn",
	Enums.JoutaiType.KEY_CONFIG_MENU:     "res://scenes/UI/KeyConfigMenu.tscn",
	Enums.JoutaiType.SOUND_CONFIG_MENU:   "res://scenes/UI/SoundConfigMenu.tscn",
	Enums.JoutaiType.KEY_CONFIG_SINGLE:   "res://scenes/UI/KeyConfig.tscn",
	Enums.JoutaiType.KEY_CONFIG_VS_1P:    "res://scenes/UI/KeyConfig.tscn",
	Enums.JoutaiType.KEY_CONFIG_VS_2P:    "res://scenes/UI/KeyConfig.tscn",
	Enums.JoutaiType.SINGLE_REPLAY_READ:  "res://scenes/UI/ReplayMenu.tscn",
	Enums.JoutaiType.SINGLE_REPLAY_WRITE: "res://scenes/UI/ReplayMenu.tscn",
	Enums.JoutaiType.VS_REPLAY_READ:      "res://scenes/UI/ReplayMenu.tscn",
	Enums.JoutaiType.VS_REPLAY_WRITE:     "res://scenes/UI/ReplayMenu.tscn",
	Enums.JoutaiType.VS_COM_REPLAY_READ:  "res://scenes/UI/VsComReplayMenu.tscn",
	Enums.JoutaiType.VS_COM_REPLAY_WRITE: "res://scenes/UI/VsComReplayMenu.tscn",
	Enums.JoutaiType.ONLINE_REPLAY_READ:  "res://scenes/UI/OnlineReplayMenu.tscn",
	Enums.JoutaiType.ONLINE_REPLAY_WRITE: "res://scenes/UI/OnlineReplayMenu.tscn",
}

var _prev_joutai: int  = -1
var _is_quitting: bool = false

# ヘルパーオブジェクト
var _com_think:    ComThinkRoutine  # COM キー生成
var _chat_mgr:     ChatInputManager # チャット UI・入力管理
var _game_obj_mgr: GameObjectManager# くる・爆弾・描画順管理
var _online_loop:  OnlineGameLoop   # オンラインロックステップ

var _was_f12_pressed: bool = false

# ============================================================
# 起動処理
# ============================================================
func _ready() -> void:
	Engine.max_fps = Constants.FPS

	# プレイヤーデータ初期化
	GameState.player.clear()
	for i in range(Constants.MAX_PLAYER):
		GameState.player.append(GameData.make_player_data())

	# セーブデータ読み込み・全体初期化・音量同期・アセットロード
	PlayerIni.player_ini_open()
	GameInit.init_all()
	SoundManager.sync_volume_from_state()
	ImageManager.load_all()
	SoundManager.load_all()

	# 起動時はフィールドとプレイヤーを非表示
	if field:     field.visible     = false
	if player_1p: player_1p.visible = false
	if player_2p: player_2p.visible = false
	if hard_block_container: hard_block_container.visible = false

	# ヘルパー初期化
	_com_think    = ComThinkRoutine.new()
	_com_think.setup(GameState.masu)

	_chat_mgr     = ChatInputManager.new()
	_chat_mgr.build_ui(self)

	_game_obj_mgr = GameObjectManager.new()
	_game_obj_mgr.setup(kuru_container, bomb_container, hard_block_container, player_1p, player_2p, field)

	_online_loop  = OnlineGameLoop.new()
	_online_loop.setup(field, player_1p, _game_obj_mgr, _chat_mgr)

	# シグナル接続
	if NetworkManager:
		NetworkManager.remote_chat_received.connect(_chat_mgr.on_remote_chat_received)

	_update_bgm_for_state(GameState.joutai_flag)
	
	dbg.bomb_container = bomb_container
	dbg.kuru_container = kuru_container
	dbg.com_think      = _com_think


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if _chat_mgr.handle_unhandled_key(key_event):
		get_viewport().set_input_as_handled()


# ============================================================
# メインループ
# main.cpp の while(ProcessLoop()) 相当
# ============================================================
func _process(_delta: float) -> void:
	KeyInput.update_keys()

	# F12 でデバッグオーバーレイ表示切替
	var f12_pressed: bool = Input.is_key_pressed(KEY_F12)
	if f12_pressed and not _was_f12_pressed:
		dbg.visible = not dbg.visible
	_was_f12_pressed = f12_pressed

	var jf := GameState.joutai_flag

	# 状態遷移があったら UI・BGM を切り替える
	if jf != _prev_joutai:
		_switch_ui(jf)
		_update_bgm_for_state(jf)
		_update_visibility(jf)
		_prev_joutai = jf

	# ゲームロジック（状態別）
	match jf:

		Enums.JoutaiType.MAIN_MENU:
			if KeyInput.key[KeyInput.KEY_INPUT_ESCAPE] == 1:
				_quit()

		Enums.JoutaiType.SINGLE_MENU:
			if KeyInput.key[KeyInput.KEY_INPUT_ESCAPE] == 1:
				GameState.joutai_flag = Enums.JoutaiType.MAIN_MENU

		Enums.JoutaiType.SINGLE_GAME:
			if _chat_mgr.is_active:
				KeyInput.zero_player_input()
			else:
				KeyInput.update_use_keys()
			player_1p.player_calc()
			_game_obj_mgr.calc_kuru()
			_game_obj_mgr.calc_bomb()
			ReplayManager.key_to_replay()
			field.field_disp()
			if KeyInput.key[KeyInput.KEY_INPUT_ESCAPE] == 1:
				GameState.replay_data[0][GameState.p_replay_data] = ReplayManager.TERMINATOR
				GameState.remember_last_single_game_replay()
				_game_obj_mgr.clear_game_objects()
				GameState.joutai_flag = Enums.JoutaiType.SINGLE_MENU

		Enums.JoutaiType.SINGLE_REPLAY:
			if not ReplayManager.replay_to_key() or KeyInput.key[KeyInput.KEY_INPUT_ESCAPE] == 1:
				_game_obj_mgr.clear_game_objects()
				GameState.joutai_flag = Enums.JoutaiType.SINGLE_REPLAY_READ
			else:
				player_1p.player_calc()
				_game_obj_mgr.calc_kuru()
				_game_obj_mgr.calc_bomb()
				GameState.process_replay_chat_events()
				field.field_disp()

		Enums.JoutaiType.SINGLE_REPLAY_READ, Enums.JoutaiType.SINGLE_REPLAY_WRITE:
			if KeyInput.key[KeyInput.KEY_INPUT_ESCAPE] == 1:
				GameState.joutai_flag = Enums.JoutaiType.SINGLE_MENU

		Enums.JoutaiType.VS_MENU:
			if KeyInput.key[KeyInput.KEY_INPUT_ESCAPE] == 1:
				GameState.joutai_flag = Enums.JoutaiType.MAIN_MENU

		Enums.JoutaiType.VS_COM_MENU:
			if KeyInput.key[KeyInput.KEY_INPUT_ESCAPE] == 1:
				GameState.joutai_flag = Enums.JoutaiType.MAIN_MENU

		Enums.JoutaiType.VS_GAME:
			KeyInput.update_use_keys()
			player_1p.player_calc()
			_game_obj_mgr.calc_kuru()
			_game_obj_mgr.calc_bomb()
			VsReplayManager.vs_key_to_replay()
			field.field_disp2()
			if KeyInput.key[KeyInput.KEY_INPUT_ESCAPE] == 1:
				GameState.replay_data[0][GameState.p_replay_data] = VsReplayManager.TERMINATOR
				GameState.replay_data[1][GameState.p_replay_data] = VsReplayManager.TERMINATOR
				GameState.remember_last_vs_game_replay(false)
				_game_obj_mgr.clear_game_objects()
				GameState.joutai_flag = Enums.JoutaiType.VS_MENU

		Enums.JoutaiType.VS_COM_GAME:
			# COM（2P）のキー生成はチャット中でも継続する
			_com_think.update_com_keys(bomb_container, kuru_container)
			if _chat_mgr.is_active:
				KeyInput.zero_player_input()
			else:
				KeyInput.update_use_keys()
			player_1p.player_calc()
			_game_obj_mgr.calc_kuru()
			_game_obj_mgr.calc_bomb()
			if not GameState.player[0]["life_flag"] or not GameState.player[1]["life_flag"]:
				_com_think.cancel_rush()
			VsComReplayManager.vs_com_key_to_replay()
			field.field_disp()
			if KeyInput.key[KeyInput.KEY_INPUT_ESCAPE] == 1:
				GameState.replay_data[0][GameState.p_replay_data] = VsComReplayManager.TERMINATOR
				GameState.replay_data[1][GameState.p_replay_data] = VsComReplayManager.TERMINATOR
				GameState.remember_last_vs_game_replay(true)
				_game_obj_mgr.clear_game_objects()
				GameState.joutai_flag = Enums.JoutaiType.VS_COM_MENU

		Enums.JoutaiType.VS_REPLAY:
			if not VsReplayManager.vs_replay_to_key() or KeyInput.key[KeyInput.KEY_INPUT_ESCAPE] == 1:
				_game_obj_mgr.clear_game_objects()
				GameState.joutai_flag = Enums.JoutaiType.VS_REPLAY_READ
			else:
				player_1p.player_calc()
				_game_obj_mgr.calc_kuru()
				_game_obj_mgr.calc_bomb()
				GameState.process_replay_chat_events()
				field.field_disp2()

		Enums.JoutaiType.VS_COM_REPLAY:
			if not VsComReplayManager.vs_com_replay_to_key() or KeyInput.key[KeyInput.KEY_INPUT_ESCAPE] == 1:
				_game_obj_mgr.clear_game_objects()
				GameState.joutai_flag = Enums.JoutaiType.VS_COM_REPLAY_READ
			else:
				player_1p.player_calc()
				_game_obj_mgr.calc_kuru()
				_game_obj_mgr.calc_bomb()
				GameState.process_replay_chat_events()
				field.field_disp()

		Enums.JoutaiType.VS_REPLAY_READ, Enums.JoutaiType.VS_REPLAY_WRITE:
			if KeyInput.key[KeyInput.KEY_INPUT_ESCAPE] == 1:
				GameState.joutai_flag = Enums.JoutaiType.VS_MENU

		Enums.JoutaiType.VS_COM_REPLAY_READ, Enums.JoutaiType.VS_COM_REPLAY_WRITE:
			if KeyInput.key[KeyInput.KEY_INPUT_ESCAPE] == 1:
				GameState.joutai_flag = Enums.JoutaiType.VS_COM_MENU

		Enums.JoutaiType.ONLINE_MENU, Enums.JoutaiType.ONLINE_LOBBY:
			if KeyInput.key[KeyInput.KEY_INPUT_ESCAPE] == 1:
				NetworkManager.disconnect_all()
				GameState.joutai_flag = Enums.JoutaiType.MAIN_MENU

		Enums.JoutaiType.ONLINE_GAME:
			_online_loop.process()

		Enums.JoutaiType.ONLINE_REPLAY:
			if not OnlineReplayManager.online_replay_to_key() or KeyInput.key[KeyInput.KEY_INPUT_ESCAPE] == 1:
				_game_obj_mgr.clear_game_objects()
				GameState.joutai_flag = Enums.JoutaiType.ONLINE_REPLAY_READ
			else:
				OnlineReplayManager.apply_sync_events_for_current_frame()
				OnlineReplayManager.apply_kuru_events_for_current_frame()
				OnlineReplayManager.apply_state_events_for_current_frame()
				player_1p.player_calc()
				_game_obj_mgr.calc_kuru()
				_game_obj_mgr.calc_bomb()
				GameState.process_replay_chat_events()
				field.field_disp()

		Enums.JoutaiType.ONLINE_REPLAY_READ, Enums.JoutaiType.ONLINE_REPLAY_WRITE:
			if KeyInput.key[KeyInput.KEY_INPUT_ESCAPE] == 1:
				GameState.joutai_flag = Enums.JoutaiType.ONLINE_MENU

		Enums.JoutaiType.KEY_CONFIG_MENU, Enums.JoutaiType.SOUND_CONFIG_MENU:
			if KeyInput.key[KeyInput.KEY_INPUT_ESCAPE] == 1:
				GameState.joutai_flag = Enums.JoutaiType.MAIN_MENU

		Enums.JoutaiType.KEY_CONFIG_SINGLE, \
		Enums.JoutaiType.KEY_CONFIG_VS_1P, \
		Enums.JoutaiType.KEY_CONFIG_VS_2P:
			if KeyInput.key[KeyInput.KEY_INPUT_ESCAPE] == 1:
				GameState.joutai_flag = Enums.JoutaiType.KEY_CONFIG_MENU

	GameState.count += 1

	_update_visibility(GameState.joutai_flag)


# ============================================================
# ゲーム開始処理（iniGame() の移植）
# ============================================================
func start_game() -> void:
	var is_replay := GameState.joutai_flag in [
		Enums.JoutaiType.SINGLE_REPLAY, Enums.JoutaiType.VS_REPLAY,
		Enums.JoutaiType.VS_COM_REPLAY, Enums.JoutaiType.ONLINE_REPLAY
	]
	# ONLINE_GAME: OnlineMenu.gd でプレイヤーデータ設定済み → 上書きせず ini_game だけ
	if GameState.joutai_flag == Enums.JoutaiType.ONLINE_GAME:
		GameState.current_stage = GameState.clamp_stage(NetworkManager.online_stage)
		GameInit.ini_game(self)
		_game_obj_mgr.refresh_hard_blocks()
		player_1p.ini_player()
		player_2p.ini_player()
		return
	# リプレイ時は replayDataRead で設定済みのデータを保持する
	if not is_replay:
		GameState.player.clear()
		for i in range(Constants.MAX_PLAYER):
			GameState.player.append(GameData.make_player_data())
		GameState.current_stage = _selected_stage_for_current_mode()
	GameInit.ini_game(self)
	if GameState.joutai_flag == Enums.JoutaiType.VS_COM_GAME:
		_com_think.reset_for_new_game()
	_game_obj_mgr.refresh_hard_blocks()
	player_1p.ini_player()
	if GameState.joutai_flag in [
		Enums.JoutaiType.VS_GAME, Enums.JoutaiType.VS_REPLAY,
		Enums.JoutaiType.VS_COM_REPLAY, Enums.JoutaiType.VS_COM_GAME,
		Enums.JoutaiType.ONLINE_REPLAY,
	]:
		player_2p.ini_player()

func _selected_stage_for_current_mode() -> int:
	match GameState.joutai_flag:
		Enums.JoutaiType.SINGLE_GAME:
			return GameState.clamp_stage(int(GameData.menu.get("stage", 0)))
		Enums.JoutaiType.VS_GAME:
			return GameState.clamp_stage(int(GameData.vs_menu.get("stage", 0)))
		Enums.JoutaiType.VS_COM_GAME:
			return GameState.clamp_stage(int(GameData.vs_com_menu.get("stage", 0)))
		_:
			return GameState.pick_random_stage()


# ============================================================
# UI 切り替え
# ============================================================
func _switch_ui(jf: int) -> void:
	if not _is_gameplay_state(jf):
		_chat_mgr.close()

	# ONLINE_MENU ↔ ONLINE_LOBBY はシーンが同一なので切り替えない
	var keep_ui := (
		_prev_joutai == Enums.JoutaiType.ONLINE_MENU  and jf == Enums.JoutaiType.ONLINE_LOBBY
		or _prev_joutai == Enums.JoutaiType.ONLINE_LOBBY and jf == Enums.JoutaiType.ONLINE_MENU
	)

	if not keep_ui:
		if _current_ui:
			_current_ui.queue_free()
			_current_ui = null

	if jf in UI_SCENES and not keep_ui:
		var path: String = UI_SCENES[jf]
		if ResourceLoader.exists(path):
			var scene := load(path) as PackedScene
			if scene:
				_current_ui = scene.instantiate()
				add_child(_current_ui)

	_update_visibility(jf)

	# ゲーム開始トリガー
	if jf in [
		Enums.JoutaiType.SINGLE_GAME, Enums.JoutaiType.VS_GAME, Enums.JoutaiType.VS_COM_GAME,
		Enums.JoutaiType.SINGLE_REPLAY, Enums.JoutaiType.VS_REPLAY, Enums.JoutaiType.VS_COM_REPLAY,
		Enums.JoutaiType.ONLINE_GAME, Enums.JoutaiType.ONLINE_REPLAY,
	]:
		start_game()


func _update_bgm_for_state(jf: int) -> void:
	var in_battle := jf in [
		Enums.JoutaiType.SINGLE_GAME,  Enums.JoutaiType.SINGLE_REPLAY,
		Enums.JoutaiType.VS_GAME,      Enums.JoutaiType.VS_COM_GAME,
		Enums.JoutaiType.VS_REPLAY,    Enums.JoutaiType.VS_COM_REPLAY,
		Enums.JoutaiType.ONLINE_GAME,  Enums.JoutaiType.ONLINE_REPLAY,
	]
	if in_battle:
		var stage := GameState.clamp_stage(GameState.current_stage)
		SoundManager.play_bgm_track("res://assets/bgm/stage%d.ogg" % stage, true)
	else:
		SoundManager.play_bgm_track("res://assets/bgm/lobby.ogg", true)


func _update_visibility(jf: int) -> void:
	var in_game := _is_in_game_display_state(jf)
	if field:
		field.visible = in_game
	if hard_block_container:
		hard_block_container.visible = in_game
	if player_1p:
		player_1p.visible = in_game
	if player_2p:
		player_2p.visible = in_game and _is_2p_active_state(jf)
	if esc_hint_lbl:
		esc_hint_lbl.visible = in_game
	if in_game:
		_game_obj_mgr.update_draw_order()


func _is_in_game_display_state(jf: int) -> bool:
	return jf in [
		Enums.JoutaiType.SINGLE_GAME, Enums.JoutaiType.SINGLE_REPLAY,
		Enums.JoutaiType.VS_GAME, Enums.JoutaiType.VS_REPLAY,
		Enums.JoutaiType.VS_COM_GAME, Enums.JoutaiType.VS_COM_REPLAY,
		Enums.JoutaiType.ONLINE_GAME, Enums.JoutaiType.ONLINE_REPLAY,
	]


func _is_2p_active_state(jf: int) -> bool:
	return jf in [
		Enums.JoutaiType.VS_GAME, Enums.JoutaiType.VS_REPLAY,
		Enums.JoutaiType.VS_COM_GAME, Enums.JoutaiType.VS_COM_REPLAY,
		Enums.JoutaiType.ONLINE_GAME, Enums.JoutaiType.ONLINE_REPLAY,
	]


func _is_gameplay_state(jf: int) -> bool:
	return jf in [
		Enums.JoutaiType.SINGLE_GAME,
		Enums.JoutaiType.VS_COM_GAME,
		Enums.JoutaiType.ONLINE_GAME,
		Enums.JoutaiType.ONLINE_REPLAY,
	]


# ============================================================
# 終了処理
# ============================================================
func _quit() -> void:
	if _is_quitting:
		return
	_is_quitting = true
	PlayerIni.player_ini_close()
	get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()
