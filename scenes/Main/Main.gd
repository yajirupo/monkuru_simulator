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
@onready var player_3p:      CharacterBody2D  = $Player3P
@onready var player_4p:      CharacterBody2D  = $Player4P
@onready var player_5p:      CharacterBody2D  = $Player5P
@onready var player_6p:      CharacterBody2D  = $Player6P
@onready var player_7p:      CharacterBody2D  = $Player7P
@onready var player_8p:      CharacterBody2D  = $Player8P
@onready var kuru_container: Node2D           = $KuruContainer
@onready var bomb_container: Node2D           = $BombContainer
@onready var hard_block_container: Node2D      = $HardBlockContainer
@onready var dbg:            Control = $ComDebugOverlay
@onready var esc_hint_lbl:   Label = $GameHintLayer/EscHintLabel

# UI シーン参照（add_child で切り替え）
var _current_ui: Node = null

# UI シーンはすべてプリロード
const UI_SCENES := {
	Enums.JoutaiType.MAIN_MENU:           preload("res://scenes/UI/MainMenu.tscn"),
	Enums.JoutaiType.SINGLE_MENU:         preload("res://scenes/UI/Menu.tscn"),
	Enums.JoutaiType.VS_MENU:             preload("res://scenes/UI/VsMenu.tscn"),
	Enums.JoutaiType.VS_COM_MENU:         preload("res://scenes/UI/VsComMenu.tscn"),
	Enums.JoutaiType.ONLINE_MENU:         preload("res://scenes/UI/OnlineMenu.tscn"),
	Enums.JoutaiType.ONLINE_LOBBY:        preload("res://scenes/UI/OnlineMenu.tscn"),
	Enums.JoutaiType.KEY_CONFIG_MENU:     preload("res://scenes/UI/KeyConfigMenu.tscn"),
	Enums.JoutaiType.SOUND_CONFIG_MENU:   preload("res://scenes/UI/SoundConfigMenu.tscn"),
	Enums.JoutaiType.KEY_CONFIG_SINGLE:   preload("res://scenes/UI/KeyConfig.tscn"),
	Enums.JoutaiType.KEY_CONFIG_VS_1P:    preload("res://scenes/UI/KeyConfig.tscn"),
	Enums.JoutaiType.KEY_CONFIG_VS_2P:    preload("res://scenes/UI/KeyConfig.tscn"),
	Enums.JoutaiType.SINGLE_REPLAY_READ:  preload("res://scenes/UI/ReplayMenu.tscn"),
	Enums.JoutaiType.SINGLE_REPLAY_WRITE: preload("res://scenes/UI/ReplayMenu.tscn"),
	Enums.JoutaiType.VS_REPLAY_READ:      preload("res://scenes/UI/ReplayMenu.tscn"),
	Enums.JoutaiType.VS_REPLAY_WRITE:     preload("res://scenes/UI/ReplayMenu.tscn"),
	Enums.JoutaiType.VS_COM_REPLAY_READ:  preload("res://scenes/UI/VsComReplayMenu.tscn"),
	Enums.JoutaiType.VS_COM_REPLAY_WRITE: preload("res://scenes/UI/VsComReplayMenu.tscn"),
	Enums.JoutaiType.ONLINE_REPLAY_READ:  preload("res://scenes/UI/OnlineReplayMenu.tscn"),
	Enums.JoutaiType.ONLINE_REPLAY_WRITE: preload("res://scenes/UI/OnlineReplayMenu.tscn"),
}

var _prev_joutai: int  = -1
var _is_quitting: bool = false

# ヘルパーオブジェクト
var _com_thinks:   Array[ComThinkRoutine] = []  # COM キー生成
var _chat_mgr:     ChatInputManager # チャット UI・入力管理
var _game_obj_mgr: GameObjectManager# くる・爆風・描画順管理
var _online_loop:  OnlineGameLoop   # オンラインロックステップ
var _shared_com_danger_detector: ComDangerDetector

var _was_f12_pressed: bool = false
var _player_nodes: Array[Node] = []

# smoke.png 管理（VS COM ゲーム開始演出）
const _SMOKE_OVERLAY_PATH := "res://assets/images/others/smoke.png"
const _SMOKE_OVERLAY_COLS := 35
const _READY_PATH           := "res://assets/images/others/ready.png"
const _APPEAR_STATE_FRAMES  := 23 * 4  # = 92 フレーム

var _smoke_overlay_sprite:     Sprite2D = null
var _smoke_overlay_elapsed:    int = 0
var _smoke_overlay_global_pos: Vector2 = Vector2.ZERO
var _ready_sprite:           Sprite2D = null
var _ready_elapsed:          int = 0

# 名前ラベル等より確実に最前面へ描画するための専用 CanvasLayer
# ready.png / win.png / lose.png はここに追加し、smoke.png は Player 配下で描画する
var _overlay_layer: CanvasLayer = null

# 勝敗演出管理（VS COM ゲーム/リプレイ 終了演出）
const _WIN_SOUND_PATH        := "res://assets/sounds/gm_win.wav"
const _LOSE_SOUND_PATH       := "res://assets/sounds/gm_lose.wav"
const _WIN_IMAGE_PATH        := "res://assets/images/others/win.png"
const _LOSE_IMAGE_PATH       := "res://assets/images/others/lose.png"
const _RESULT_DISPLAY_FRAMES := 300  # 5秒 × 60fps

var _result_phase:          int      = 0    # 0=なし, 1=演出進行中
var _result_elapsed:        int      = 0    # 演出フレームカウンタ
var _result_overlay_sprite: Sprite2D = null # win.png / lose.png

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

	_collect_player_nodes()

	# 起動時はフィールドとプレイヤーを非表示
	if field: field.visible = false
	for player_node in _player_nodes:
		if player_node and player_node is CanvasItem:
			(player_node as CanvasItem).visible = false
	if hard_block_container: hard_block_container.visible = false

	# ヘルパー初期化
	_shared_com_danger_detector = ComDangerDetector.new()
	_shared_com_danger_detector.initialize(GameState.masu)
	_com_thinks.clear()
	for i in range(1, Constants.MAX_PLAYER):
		var com_think := ComThinkRoutine.new()
		com_think.setup(GameState.masu)
		com_think.set_shared_danger_detector(_shared_com_danger_detector)
		com_think.com_player_index = i
		_com_thinks.append(com_think)

	_chat_mgr     = ChatInputManager.new()
	_chat_mgr.build_ui(self)

	_game_obj_mgr = GameObjectManager.new()
	_game_obj_mgr.setup(kuru_container, bomb_container, hard_block_container, _player_nodes, field)

	_online_loop  = OnlineGameLoop.new()
	_online_loop.setup(field, player_1p, _game_obj_mgr, _chat_mgr)

	# シグナル接続
	if NetworkManager:
		NetworkManager.remote_chat_received.connect(_chat_mgr.on_remote_chat_received)

	_update_bgm_for_state(GameState.joutai_flag)
	
	dbg.bomb_container = bomb_container
	dbg.kuru_container = kuru_container
	if _com_thinks.size() > 0:
		dbg.com_think      = _com_thinks[0]

	# 最前面オーバーレイ用 CanvasLayer（Control/名前ラベルより必ず上に描画）
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 128
	add_child(_overlay_layer)


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
		_cleanup_finished_game_state(_prev_joutai, jf)
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
				GameState.replay_data[0][GameState.p_replay_data] = GameState.REPLAY_TERMINATOR
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
				GameState.replay_data[0][GameState.p_replay_data] = GameState.REPLAY_TERMINATOR
				GameState.replay_data[1][GameState.p_replay_data] = GameState.REPLAY_TERMINATOR
				GameState.remember_last_vs_game_replay(false)
				_game_obj_mgr.clear_game_objects()
				GameState.joutai_flag = Enums.JoutaiType.VS_MENU

		Enums.JoutaiType.VS_COM_GAME:
			# COM（2P）のキー生成はチャット中でも継続する
			var active_count := _active_vs_com_player_count()
			var is_appearing  := _is_any_player_appearing()
			var force_return_to_menu := false

			if is_appearing:
				_clear_vs_com_appear_inputs()
			else:
				if _result_phase != 0:
					# 勝敗演出中: 全プレイヤー入力を封鎖してタイマーを進める
					for i in range(active_count):
						_zero_use_key_for_player(i)
					_result_elapsed += 1
					if _result_elapsed >= _RESULT_DISPLAY_FRAMES:
						force_return_to_menu = true
				else:
					# APPEAR 終了後のみ COM・プレイヤー入力を処理する
					_shared_com_danger_detector.build_event_list(bomb_container, kuru_container)
					for i in range(active_count - 1):
						if not GameState.player[i + 1]["life_flag"]:
							_zero_use_key_for_player(i + 1)
							continue
						var com_think := _com_thinks[i]
						com_think.com_player_index = i + 1
						com_think.update_com_keys(kuru_container)
					if _chat_mgr.is_active:
						KeyInput.zero_player_input()
					else:
						KeyInput.update_use_keys()
					# 被弾退場済みプレイヤーは入力を受け付けない
					for i in range(active_count):
						if not GameState.player[i]["life_flag"]:
							_zero_use_key_for_player(i)

			# player_calc は APPEAR 中も呼ぶ（内部でカウンタ更新・終了判定を行う）
			player_1p.player_calc()
			_game_obj_mgr.calc_kuru()
			_game_obj_mgr.calc_bomb()

			if not is_appearing:
				if _result_phase == 0:
					if not GameState.player[0]["life_flag"]:
						for com_think in _com_thinks:
							com_think.cancel_rush()
					VsComReplayManager.vs_com_key_to_replay() # APPEAR 中はリプレイに書かない
					_check_vs_com_result()

			_update_intro_effects()
			field.field_disp()

			if KeyInput.key[KeyInput.KEY_INPUT_ESCAPE] == 1 or force_return_to_menu:
				var _active := _active_vs_com_player_count()
				for i in range(_active):
					GameState.replay_data[i][GameState.p_replay_data] = GameState.REPLAY_TERMINATOR
				GameState.remember_last_vs_game_replay(true)
				_end_result_phase()
				_game_obj_mgr.clear_game_objects()
				_stop_intro_effects()
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
			var is_appearing   := _is_any_player_appearing()
			var replay_active  := true
			var force_return_to_menu := false

			if not is_appearing:
				if _result_phase != 0:
					# 勝敗演出中: replay_to_key を止め、タイマーを進める
					for i in range(_active_vs_com_player_count()):
						_zero_use_key_for_player(i)
					_result_elapsed += 1
					if _result_elapsed >= _RESULT_DISPLAY_FRAMES:
						force_return_to_menu = true
				else:
					replay_active = VsComReplayManager.vs_com_replay_to_key()

			if not replay_active or KeyInput.key[KeyInput.KEY_INPUT_ESCAPE] == 1 or force_return_to_menu:
				_end_result_phase()
				_stop_intro_effects()
				_game_obj_mgr.clear_game_objects()
				GameState.joutai_flag = Enums.JoutaiType.VS_COM_REPLAY_READ
			else:
				player_1p.player_calc()
				_game_obj_mgr.calc_kuru()
				_game_obj_mgr.calc_bomb()

				if not is_appearing:
					GameState.process_replay_chat_events()
					if _result_phase == 0:
						_check_vs_com_result()

				_update_intro_effects()
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

func _active_vs_com_player_count() -> int:
	if GameState.joutai_flag == Enums.JoutaiType.VS_COM_REPLAY:
		return clampi(GameState.vs_com_replay_player_count, 2, Constants.MAX_PLAYER)
	var cc: int = int(GameData.vs_com_menu.get("com_count", 1))
	cc = clampi(cc, 1, Constants.MAX_PLAYER - 1)
	return cc + 1

func _zero_use_key_for_player(player_idx: int) -> void:
	if player_idx < 0 or player_idx >= GameState.use_key.size():
		return
	for k in range(8):
		GameState.use_key[player_idx][k] = 0

func _clear_vs_com_appear_inputs() -> void:
	# READY?/APPEAR 中は人間プレイヤーのゲーム入力をすべて無視する。
	# キーカウンタを毎フレーム消すことで、押しっぱなしで開始しても
	# プレイ可能になった最初のフレームが use_key == 1 になり、
	# 記録時とリプレイ再生時の入力カウンタが一致する。
	KeyInput.clear_gameplay_key_counters(GameState.use_key_single)
	_zero_use_key_for_player(0)

func _collect_player_nodes() -> void:
	_player_nodes.clear()
	_player_nodes.append(player_1p)
	_player_nodes.append(player_2p)
	_player_nodes.append(player_3p)
	_player_nodes.append(player_4p)
	_player_nodes.append(player_5p)
	_player_nodes.append(player_6p)
	_player_nodes.append(player_7p)
	_player_nodes.append(player_8p)


func _initialize_player_nodes(active_count: int) -> void:
	active_count = clampi(active_count, 1, _player_nodes.size())
	for i in range(active_count):
		var player_node := _player_nodes[i]
		if player_node and player_node.has_method("ini_player"):
			player_node.call("ini_player")


func _deactivate_inactive_vs_com_players(active_count: int) -> void:
	for i in range(active_count, Constants.MAX_PLAYER):
		GameState.player[i]["life_flag"] = false

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
		_initialize_player_nodes(2)
		return
		
	# リプレイ時は replayDataRead で設定済みのデータを保持する
	if not is_replay:
		GameState.player.clear()
		for i in range(Constants.MAX_PLAYER):
			GameState.player.append(GameData.make_player_data())
		GameState.current_stage = _selected_stage_for_current_mode()
		
		# 新規 VS COM ゲームの場合、開始位置割り当てをランダム化
		if GameState.joutai_flag == Enums.JoutaiType.VS_COM_GAME:
			var active_count := _active_vs_com_player_count()
			var assignments: Array[int]= Array(range(active_count), TYPE_INT, &"", null)
			assignments.shuffle()
			GameState.vs_com_start_assignments = assignments
		else:
			GameState.vs_com_start_assignments.clear()
		
	GameInit.ini_game(self)
	if GameState.joutai_flag == Enums.JoutaiType.VS_COM_GAME:
		for com_think in _com_thinks:
			com_think.reset_for_new_game()
	_game_obj_mgr.refresh_hard_blocks()
	var active_player_count := 1
	if GameState.joutai_flag in [
		Enums.JoutaiType.VS_GAME, Enums.JoutaiType.VS_REPLAY,
		Enums.JoutaiType.ONLINE_REPLAY,
	]:
		active_player_count = 2
	elif GameState.joutai_flag in [Enums.JoutaiType.VS_COM_GAME, Enums.JoutaiType.VS_COM_REPLAY]:
		active_player_count = _active_vs_com_player_count()
	_initialize_player_nodes(active_player_count)
	if GameState.joutai_flag in [Enums.JoutaiType.VS_COM_GAME, Enums.JoutaiType.VS_COM_REPLAY]:
		_deactivate_inactive_vs_com_players(active_player_count)
	
	# VS COM ゲーム・リプレイ開始演出（ini_player でプレイヤー位置確定後に呼ぶ）
	if GameState.joutai_flag in [Enums.JoutaiType.VS_COM_GAME, Enums.JoutaiType.VS_COM_REPLAY]:
		SoundManager.play_ready()
		_start_intro_effects()

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
	# VS COM ゲーム/リプレイ以外に遷移するとき勝敗演出を確実に片付ける
	if jf not in [Enums.JoutaiType.VS_COM_GAME, Enums.JoutaiType.VS_COM_REPLAY]:
		_end_result_phase()

	# ONLINE_MENU ↔ ONLINE_LOBBY はシーンが同一なので切り替えない
	var keep_ui := (
		_prev_joutai == Enums.JoutaiType.ONLINE_MENU  and jf == Enums.JoutaiType.ONLINE_LOBBY
		or _prev_joutai == Enums.JoutaiType.ONLINE_LOBBY and jf == Enums.JoutaiType.ONLINE_MENU
	)

	if not keep_ui:
		if _current_ui:
			_current_ui.queue_free()
			_current_ui = null

	# preload 済みの PackedScene をそのまま使用
	if jf in UI_SCENES and not keep_ui:
		var scene: PackedScene = UI_SCENES[jf]
		if scene:
			_current_ui = scene.instantiate()
			add_child(_current_ui)

	# ゲーム開始トリガー
	if jf in [
		Enums.JoutaiType.SINGLE_GAME, Enums.JoutaiType.VS_GAME, Enums.JoutaiType.VS_COM_GAME,
		Enums.JoutaiType.SINGLE_REPLAY, Enums.JoutaiType.VS_REPLAY, Enums.JoutaiType.VS_COM_REPLAY,
		Enums.JoutaiType.ONLINE_GAME, Enums.JoutaiType.ONLINE_REPLAY,
	]:
		start_game()


func _cleanup_finished_game_state(prev_jf: int, next_jf: int) -> void:
	if prev_jf < 0:
		return
	if not _is_in_game_display_state(prev_jf) or _is_in_game_display_state(next_jf):
		return
	if _game_obj_mgr:
		_game_obj_mgr.clear_game_objects()
	_stop_intro_effects()
	_end_result_phase()


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
	var visible_player_count := 1 if in_game else 0
	if in_game:
		if jf in [Enums.JoutaiType.VS_COM_GAME, Enums.JoutaiType.VS_COM_REPLAY]:
			visible_player_count = _active_vs_com_player_count()
		elif _is_2p_active_state(jf):
			visible_player_count = 2
	for i in range(_player_nodes.size()):
		var player_node := _player_nodes[i]
		if player_node and player_node is CanvasItem:
			(player_node as CanvasItem).visible = i < visible_player_count
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


## 開始演出の CanvasLayer・スプライトを初期化する
func _start_intro_effects() -> void:
	_stop_intro_effects()
	
	# smoke.png 作成（Player 配下で shadow.png などと同じ描画順に乗せる）
	_smoke_overlay_sprite = _get_intro_smoke_sprite()
	if _smoke_overlay_sprite:
		_smoke_overlay_sprite.position = Vector2(12, 0)
		_smoke_overlay_global_pos = _smoke_overlay_sprite.global_position
		_smoke_overlay_sprite.z_index = 2
		_smoke_overlay_sprite.visible = true
		_smoke_overlay_sprite.texture = null
	_smoke_overlay_elapsed = 0

	# ready.png 作成（最前面）
	_ready_sprite = Sprite2D.new()
	_ready_sprite.position = get_viewport_rect().size / 2.0 + Vector2(8, -11)
	_ready_sprite.texture = ImageManager.get_image(_READY_PATH)
	_overlay_layer.add_child(_ready_sprite)
	_ready_elapsed = 0


## smoke.png・ready.png を毎フレーム更新する
func _update_intro_effects() -> void:
	# smoke.png アニメーション（Player 配下の z_index で描画順を制御）
	if _smoke_overlay_sprite:
		var rpt := Constants.REFRESH_PICTURE_TIME
		@warning_ignore("integer_division")
		var frame := _smoke_overlay_elapsed / rpt
		if frame >= _SMOKE_OVERLAY_COLS:
			_smoke_overlay_sprite.visible = false
			_smoke_overlay_sprite.texture = null
			_smoke_overlay_sprite = null
		else:
			# プレイヤーが移動しても、開始時に記録した画面上の位置へ固定する
			_smoke_overlay_sprite.global_position = _smoke_overlay_global_pos
			var base_tex: Texture2D = ImageManager.get_image(_SMOKE_OVERLAY_PATH)
			@warning_ignore("integer_division")
			var fw: int = maxi(base_tex.get_width() / _SMOKE_OVERLAY_COLS, 1)
			var fh: int = base_tex.get_height()
			var tex := ImageManager.get_transparent_image(
					_SMOKE_OVERLAY_PATH, frame, 0, fw, fh)
			_smoke_overlay_sprite.texture = tex
		_smoke_overlay_elapsed += 1

	# ready.png：92フレームで消去
	if _ready_sprite != null:
		_ready_elapsed += 1
		if _ready_elapsed >= _APPEAR_STATE_FRAMES:
			_ready_sprite.queue_free()
			_ready_sprite = null

func _get_intro_smoke_sprite() -> Sprite2D:
	if _player_nodes.is_empty():
		return null
	var player_node := _player_nodes[0]
	if player_node == null:
		return null
	var sprite := player_node.get_node_or_null("IntroSmokeSprite") as Sprite2D
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = "IntroSmokeSprite"
		player_node.add_child(sprite)
	sprite.centered = true
	return sprite


## 演出を中断してすべて解放する（ESC 離脱時に呼ぶ）
func _stop_intro_effects() -> void:
	if _smoke_overlay_sprite:
		_smoke_overlay_sprite.visible = false
		_smoke_overlay_sprite.texture = null
		_smoke_overlay_sprite = null
	if _ready_sprite:
		_ready_sprite.queue_free()
		_ready_sprite = null
	_smoke_overlay_elapsed = 0
	_smoke_overlay_global_pos = Vector2.ZERO
	_ready_elapsed = 0

## APPEAR 状態のプレイヤーが1人でもいれば true を返す
func _is_any_player_appearing() -> bool:
	var active_count := _active_vs_com_player_count()
	for i in range(active_count):
		if GameState.player[i].get("joutai") == Enums.PlayerJoutaiType.APPEAR:
			return true
	return false


## 生存プレイヤーが1人になり、かつ全敗者の DEATH アニメーション終了後に WIN/LOSE 演出を開始する
func _check_vs_com_result() -> void:
	if _result_phase != 0:
		return
	var active_count := _active_vs_com_player_count()
	var alive_count  := 0
	var alive_idx    := -1
	for i in range(active_count):
		if GameState.player[i]["life_flag"]:
			alive_count += 1
			alive_idx    = i
	# 2人以上生存中はまだ結果なし
	if alive_count > 1:
		return

	# ─── 勝者インデックスをアニメ待ちより先に決定 ───────────────────────
	# alive_count == 1: 生存者が勝者
	# alive_count == 0: 最後に被弾したプレイヤーが1人のみなら勝者、同着なら全員 LOSE
	var winner_idx := alive_idx  # alive_count==1 なら alive_idx、0 なら -1 のまま

	if alive_count == 0:
		var latest_frame := -1
		for i in range(active_count):
			latest_frame = maxi(latest_frame, int(GameState.player[i].get("death_frame", -1)))
		var last_dead_count := 0
		var last_dead_idx   := -1
		for i in range(active_count):
			if int(GameState.player[i].get("death_frame", -1)) == latest_frame:
				last_dead_count += 1
				last_dead_idx    = i
		# 1人だけが最後なら勝者、複数同着なら全員 LOSE（winner_idx = -1 のまま）
		if last_dead_count == 1:
			winner_idx = last_dead_idx

	# ─── DEATH アニメーション終了を待つ（勝者はスキップ） ───────────────
	for i in range(active_count):
		if i == winner_idx:
			continue  # 勝者のアニメはスキップして即 WIN 遷移
		if GameState.player[i]["life_flag"]:
			continue  # 生存者（alive_count==1 の場合）
		var pi: Dictionary = GameState.player[i]
		var death_end: int = int(pi.get("death_cols", 1)) * Constants.REFRESH_PICTURE_TIME - 1
		if pi["joutai"] != Enums.PlayerJoutaiType.DEATH or pi["joutai_count"] < death_end:
			return  # まだアニメーション再生中

	# ─── WIN/LOSE 状態を設定 ──────────────────────────────────────────────
	for i in range(active_count):
		var pi: Dictionary = GameState.player[i]
		if i == winner_idx:
			pi["joutai"]       = Enums.PlayerJoutaiType.WIN
			pi["joutai_count"] = 0
		else:
			pi["joutai"]       = Enums.PlayerJoutaiType.LOSE
			pi["joutai_count"] = 0

	# 人間プレイヤー（0番）が勝者かどうかで BGM・画像を分岐
	var human_won: bool = (winner_idx == 0)
	if human_won:
		SoundManager.play_win_bgm()
	else:
		SoundManager.play_lose_bgm()

	# win/lose 画像を最前面 CanvasLayer に表示
	var image_path := _WIN_IMAGE_PATH if human_won else _LOSE_IMAGE_PATH
	_result_overlay_sprite          = Sprite2D.new()
	_result_overlay_sprite.texture  = ImageManager.get_image(image_path)
	_result_overlay_sprite.position = get_viewport_rect().size / 2.0
	if human_won:
		_result_overlay_sprite.position += Vector2(-2, -12)
	else:
		_result_overlay_sprite.position += Vector2(30, -14)
	_overlay_layer.add_child(_result_overlay_sprite)

	_result_phase   = 1
	_result_elapsed = 0


## 勝敗演出をすべて解放する（メニューへ戻るとき・ESC 時に呼ぶ）
func _end_result_phase() -> void:
	if _result_overlay_sprite:
		_result_overlay_sprite.queue_free()
		_result_overlay_sprite = null
	SoundManager.stop_win_lose()
	_result_phase   = 0
	_result_elapsed = 0
