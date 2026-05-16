# OnlineMenu.gd
# オンライン対戦メニュー ─ 名前欄追加・マウス操作版

extends Control

const ITEM_NAMES      := ["無し", "くるロケット", "透明マント", "スピード靴", "くる兄弟"]
const ITEM_MAX        := 5   # wrapi の上限（0〜4 の 5 種類）

var _name_btn:    Button
var _name_edit:   LineEdit
var _ip_edit:     LineEdit
var _status_lbl:  Label
var _char_status_lbl: Label
var _ready_btn:   Button
var _main_panel:  Control
var _lobby_panel: Control
var _update_fns:  Array[Callable] = []
var _waiting:     bool = false

var _character_overlay: CharacterSelectOverlay = null
var _kuru_overlay: KuruSelectOverlay = null
var _item_overlay: ItemSelectOverlay = null
var _stage_overlay: StageSelectOverlay = null

# ═══════════════════════════════════════════════════════════
# ライフサイクル
# ═══════════════════════════════════════════════════════════

func _ready() -> void:
	_clear_children()
	_ensure_online_menu_defaults()

	NetworkManager.connected_to_peer.connect(_on_connected)
	NetworkManager.peer_disconnected.connect(_on_disconnected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.game_start_requested.connect(_on_game_start)
	NetworkManager.remote_ready_updated.connect(_on_remote_ready_updated)
	
	_build_ui()
	_update_display()

func _clear_children() -> void:
	for child in get_children():
		child.free()

func _exit_tree() -> void:
	if NetworkManager.connected_to_peer.is_connected(_on_connected):
		NetworkManager.connected_to_peer.disconnect(_on_connected)
	if NetworkManager.peer_disconnected.is_connected(_on_disconnected):
		NetworkManager.peer_disconnected.disconnect(_on_disconnected)
	if NetworkManager.connection_failed.is_connected(_on_connection_failed):
		NetworkManager.connection_failed.disconnect(_on_connection_failed)
	if NetworkManager.game_start_requested.is_connected(_on_game_start):
		NetworkManager.game_start_requested.disconnect(_on_game_start)
	if NetworkManager.remote_ready_updated.is_connected(_on_remote_ready_updated):
		NetworkManager.remote_ready_updated.disconnect(_on_remote_ready_updated)

# online_menu に必須キーが無い場合のみ初期化（値の上書きは行わない）
func _ensure_online_menu_defaults() -> void:
	if not GameState.online_menu.has("name"):
		GameState.online_menu["name"] = "Player"
	elif typeof(GameState.online_menu["name"]) != TYPE_STRING:
		GameState.online_menu["name"] = str(GameState.online_menu["name"])
	GameState.online_menu["name"] = GameState.sanitize_chat_text(
		String(GameState.online_menu["name"]),
		GameState.CHAT_MAX_NAME_LENGTH
	)
	if GameState.online_menu["name"] == "":
		GameState.online_menu["name"] = "Player"
	if not GameState.online_menu.has("ip_address"):
		GameState.online_menu["ip_address"] = "127.0.0.1"
	elif typeof(GameState.online_menu["ip_address"]) != TYPE_STRING:
		GameState.online_menu["ip_address"] = str(GameState.online_menu["ip_address"])
	if not GameState.online_menu.has("item_type"):
		GameState.online_menu["item_type"] = [0, 0, 0]
	else:
		var item_src: Variant = GameState.online_menu["item_type"]
		var normalized_items: Array[int] = [0, 0, 0]
		if typeof(item_src) == TYPE_ARRAY:
			var item_arr: Array = item_src
			for i in range(min(3, item_arr.size())):
				normalized_items[i] = clampi(int(item_arr[i]), 0, ITEM_MAX - 1)
		GameState.online_menu["item_type"] = normalized_items
	if not GameState.online_menu.has("character"):
		GameState.online_menu["character"] = 0
	else:
		GameState.online_menu["character"] = clampi(int(GameState.online_menu["character"]), 0, Constants.get_character_count() - 1)
	if not GameState.online_menu.has("stage"):
		GameState.online_menu["stage"] = 0
	else:
		GameState.online_menu["stage"] = GameState.clamp_stage(int(GameState.online_menu["stage"]))
	if not GameState.online_menu.has("kuru_type"):
		GameState.online_menu["kuru_type"] = 0
	else:
		GameState.online_menu["kuru_type"] = clampi(int(GameState.online_menu["kuru_type"]), 0, Constants.get_kuru_count() - 1)


# ═══════════════════════════════════════════════════════════
# UI 構築
# ═══════════════════════════════════════════════════════════

func _build_ui() -> void:
	_update_fns.clear()   # 再入時に旧クロージャが残らないようリセット
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 3)
	add_child(root)

	_lbl(root, "── オンライン対戦メニュー ──")
	root.add_child(HSeparator.new())

	_ensure_character_overlay()
	_ensure_kuru_overlay()
	_ensure_item_overlay()
	_ensure_stage_overlay()
	
	_build_main_panel(root)
	_build_lobby_panel(root)

func _build_main_panel(root: Control) -> void:
	_main_panel = VBoxContainer.new()
	_main_panel.add_theme_constant_override("separation", 3)
	root.add_child(_main_panel)

	# ── 名前 ────────────────────────────────────────────────
	var name_row := HBoxContainer.new()
	_lbl_w(name_row, "名前：", 110)
	_name_btn = _mk_btn("")
	_name_btn.custom_minimum_size.x = 120
	_name_btn.pressed.connect(_on_name_btn_pressed)
	name_row.add_child(_name_btn)
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size.x = 120
	_name_edit.max_length = GameState.CHAT_MAX_NAME_LENGTH
	_name_edit.visible = false
	_name_edit.text_submitted.connect(_on_name_submitted)
	name_row.add_child(_name_edit)
	_main_panel.add_child(name_row)
	_update_fns.append(func():
		if not _name_edit.visible:
			_name_btn.text = GameState.online_menu.get("name", "Player") as String)

	_main_panel.add_child(HSeparator.new())
	
	# ── サーバー起動 ─────────────────────────────────────────
	_add_btn(_main_panel, "サーバーとして開始", _on_start_server)

	# ── クライアント接続 ─────────────────────────────────────
	var client_row := HBoxContainer.new()
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text    = "IPアドレス:ポート (例: 127.0.0.1:9999)"
	_ip_edit.text                = GameState.online_menu.get("ip_address", "127.0.0.1:9999") as String
	_ip_edit.custom_minimum_size = Vector2(150, 0)
	_ip_edit.text_changed.connect(func(new_text: String): GameState.online_menu["ip_address"] = new_text)
	client_row.add_child(_ip_edit)
	_add_btn(client_row, "クライアントとして接続", _on_start_client)
	_main_panel.add_child(client_row)

	_main_panel.add_child(HSeparator.new())

	# ── キャラ・くる ─────────────────────────────────────────
	var char_row := HBoxContainer.new()
	_lbl_w(char_row, "キャラ：", 110)
	var bl := _mk_btn("◀")
	bl.pressed.connect(func():
		GameState.online_menu["character"] = wrapi(GameState.online_menu["character"] - 1, 0, Constants.get_character_count())
		_update_display()
	)
	char_row.add_child(bl)
	var name_btn := _mk_btn("")
	name_btn.custom_minimum_size.x = 80
	name_btn.pressed.connect(func():
		_character_overlay.show_overlay(func(new_idx: int):
			GameState.online_menu["character"] = new_idx
			_update_display()
		)
	)
	char_row.add_child(name_btn)
	var br := _mk_btn("▶")
	br.pressed.connect(func():
		GameState.online_menu["character"] = wrapi(GameState.online_menu["character"] + 1, 0, Constants.get_character_count())
		_update_display()
	)
	char_row.add_child(br)
	_main_panel.add_child(char_row)
	_update_fns.append(func(): name_btn.text = Constants.get_character_name(GameState.online_menu["character"]))
	
	_make_kuru_row(_main_panel,
		func(): return GameState.online_menu["kuru_type"],
		func(v: int): GameState.online_menu["kuru_type"] = v)
		
	_char_status_lbl = Label.new()
	_char_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_main_panel.add_child(_char_status_lbl)
	_update_fns.append(func():
		var st := Constants.get_status_with_kuru_bonus(GameState.online_menu["character"], GameState.online_menu["kuru_type"])
		_char_status_lbl.text = "速度:%d%s  パワー:%d%s  くる数:%d%s\nくる速度:%d  くる段階:%d  発射間隔:%.1f秒" % [
			st["speed_base"], Constants.format_signed_bonus(st["speed_bonus"]),
			st["power_base"], Constants.format_signed_bonus(st["power_bonus"]),
			st["shot_base"],  Constants.format_signed_bonus(st["shot_bonus"]),
			st["kuru_speed_stat"], st["kuru_dankai"], st["kuru_kankaku"] / 60.0
		])

	# ── アイテム ─────────────────────────────────────────────
	# サーバー・クライアント両方で正しく表示されるよう
	# slot 変数を var で明示的にコピーしてクロージャに渡す
	for i in range(3):
		var slot: int = i
		_arrow_row(_main_panel, "アイテム%d" % (i + 1),
			func() -> String:
				var v: int = GameState.online_menu["item_type"][slot]
				return ITEM_NAMES[clampi(v, 0, ITEM_NAMES.size() - 1)],
			func():
				var cur: int = GameState.online_menu["item_type"][slot]
				GameState.online_menu["item_type"][slot] = wrapi(cur - 1, 0, ITEM_MAX),
			func():
				var cur: int = GameState.online_menu["item_type"][slot]
				GameState.online_menu["item_type"][slot] = wrapi(cur + 1, 0, ITEM_MAX),
			func():
				_item_overlay.show_overlay(func(new_val: int):
					GameState.online_menu["item_type"][slot] = new_val
					_update_display()
				)
		)

	_arrow_row(_main_panel, "ステージ",
		func(): return GameState.get_stage_name(GameState.online_menu["stage"]),
		func(): GameState.online_menu["stage"] = wrapi(GameState.online_menu["stage"] - 1, 0, GameState.STAGE_COUNT),
		func(): GameState.online_menu["stage"] = wrapi(GameState.online_menu["stage"] + 1, 0, GameState.STAGE_COUNT),
		# ▼ 追加
		func():
			_stage_overlay.show_overlay(func(new_val: int):
				GameState.online_menu["stage"] = new_val
				_update_display()
			)
	)
	
	_main_panel.add_child(HSeparator.new())
	var replay_row := HBoxContainer.new()
	replay_row.add_theme_constant_override("separation", 8)
	_add_btn(replay_row, "リプレイ保存", _on_replay_save)
	_add_btn(replay_row, "リプレイ読込", _on_replay_load)
	_add_btn(replay_row, "戻る", _on_back)
	_main_panel.add_child(replay_row)

func _build_lobby_panel(root: Control) -> void:
	_lobby_panel = VBoxContainer.new()
	_lobby_panel.add_theme_constant_override("separation", 6)
	_lobby_panel.visible = false
	root.add_child(_lobby_panel)

	_lbl(_lobby_panel, "── 待機ロビー ──")
	_status_lbl = Label.new()
	_status_lbl.text = ""
	_lobby_panel.add_child(_status_lbl)

	var lobby_btns := HBoxContainer.new()
	lobby_btns.add_theme_constant_override("separation", 8)
	_ready_btn = _add_btn(lobby_btns, "準備完了", _on_ready_up)
	_ready_btn.disabled = true
	_add_btn(lobby_btns, "切断してメニューへ戻る", _on_disconnect)
	_lobby_panel.add_child(lobby_btns)

# ═══════════════════════════════════════════════════════════
# ロビー表示切替
# ═══════════════════════════════════════════════════════════

func _enter_lobby() -> void:
	_main_panel.visible  = false
	_lobby_panel.visible = true

func _exit_lobby() -> void:
	_main_panel.visible  = true
	_lobby_panel.visible = false
	_waiting = false

# ═══════════════════════════════════════════════════════════
# UI ユーティリティ
# ═══════════════════════════════════════════════════════════

func _mk_btn(text: String) -> Button:
	var b := Button.new()
	b.text       = text
	b.focus_mode = Control.FOCUS_NONE
	return b

func _add_btn(parent: Control, text: String, cb: Callable) -> Button:
	var b := _mk_btn(text)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _lbl(parent: Control, text: String) -> Label:
	var l := Label.new(); l.text = text
	parent.add_child(l); return l

func _lbl_w(parent: Control, text: String, w: float) -> Label:
	var l := _lbl(parent, text)
	l.custom_minimum_size.x = w; return l

func _arrow_row(parent: Control, label_text: String,
		get_fn: Callable, dec_fn: Callable, inc_fn: Callable,
		overlay_callback: Callable = Callable()) -> void:
	var hbox := HBoxContainer.new()
	_lbl_w(hbox, label_text + "：", 110)
	var bl := _mk_btn("◀")
	bl.pressed.connect(func(): dec_fn.call(); _update_display())
	hbox.add_child(bl)

	# ★ オーバーレイ用コールバックがあれば Button、なければ Label
	if overlay_callback.is_valid():
		var val_btn := _mk_btn("")
		val_btn.custom_minimum_size.x = 80
		val_btn.pressed.connect(overlay_callback)
		hbox.add_child(val_btn)
		_update_fns.append(func(): val_btn.text = get_fn.call())
	else:
		var vl := Label.new()
		vl.custom_minimum_size.x = 80
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hbox.add_child(vl)
		_update_fns.append(func(): vl.text = get_fn.call())

	var br := _mk_btn("▶")
	br.pressed.connect(func(): inc_fn.call(); _update_display())
	hbox.add_child(br)
	parent.add_child(hbox)

func _update_display() -> void:
	for fn in _update_fns:
		fn.call()

# ═══════════════════════════════════════════════════════════
# 名前入力
# ═══════════════════════════════════════════════════════════

func _on_name_btn_pressed() -> void:
	_name_edit.text    = GameState.online_menu.get("name", "Player") as String
	_name_btn.visible  = false
	_name_edit.visible = true
	_name_edit.grab_focus()
	_name_edit.select_all()

func _on_name_submitted(new_name: String) -> void:
	var t := GameState.sanitize_chat_text(new_name, GameState.CHAT_MAX_NAME_LENGTH)
	if t != "":
		GameState.online_menu["name"] = t
	_name_btn.text     = GameState.online_menu.get("name", "Player") as String
	_name_edit.visible = false
	_name_btn.visible  = true

# ═══════════════════════════════════════════════════════════
# サーバー / クライアント起動
# ═══════════════════════════════════════════════════════════

func _on_start_server() -> void:
	NetworkManager.disconnect_all()
	
	# IP:ポート からポートだけ抽出（サーバーは待ち受けポート）
	var parsed := _parse_ip_and_port(_ip_edit.text, 9999)
	NetworkManager.port = parsed["port"]
	
	var err: String = NetworkManager.start_server()
	if err != "":
		_set_status("エラー: " + err); return
	_waiting = true
	_enter_lobby()
	GameState.joutai_flag = Enums.JoutaiType.ONLINE_LOBBY
	_set_status("待機中... ポート %d" % NetworkManager.port)

func _on_start_client() -> void:
	NetworkManager.disconnect_all()
	
	var raw: String = _ip_edit.text.strip_edges()
	var parsed := _parse_ip_and_port(raw, 9999)
	NetworkManager.port = parsed["port"]
	var ip: String = parsed["ip"]
	if ip == "":
		ip = "127.0.0.1"
		
	GameState.online_menu["ip_address"] = "%s:%d" % [ip, NetworkManager.port]
	
	var err: String = NetworkManager.connect_to_server(ip)
	if err != "":
		_set_status("エラー: " + err); return
	_waiting = true
	_enter_lobby()
	GameState.joutai_flag = Enums.JoutaiType.ONLINE_LOBBY
	_set_status("接続中... %s:%d" % [ip, NetworkManager.port])

func _on_ready_up() -> void:
	NetworkManager.send_ready()
	_ready_btn.disabled = true
	_set_status("準備完了！相手を待っています...")

func _on_disconnect() -> void:
	NetworkManager.disconnect_all()
	_exit_lobby()
	GameState.joutai_flag = Enums.JoutaiType.ONLINE_MENU

func _on_back() -> void:
	NetworkManager.disconnect_all()
	GameState.joutai_flag = Enums.JoutaiType.MAIN_MENU

func _on_replay_save() -> void:
	_backup_online_menu_for_replay()
	GameState.joutai_flag = Enums.JoutaiType.ONLINE_REPLAY_WRITE

func _on_replay_load() -> void:
	GameState.joutai_flag = Enums.JoutaiType.ONLINE_REPLAY_READ

# ═══════════════════════════════════════════════════════════
# NetworkManager シグナルハンドラ
# ═══════════════════════════════════════════════════════════

func _on_connected() -> void:
	_waiting = false
	_ready_btn.disabled = false
	var role_str: String = "サーバー" if NetworkManager.role == NetworkManager.Role.SERVER else "クライアント"
	_set_status("接続完了！[%s]\n選択ステージ:%s\n「準備完了」を押してください" % [
		role_str,
		GameState.get_stage_name(int(GameState.online_menu.get("stage", 0)))
	])

func _on_remote_ready_updated() -> void:
	var my_stage := GameState.clamp_stage(int(GameState.online_menu.get("stage", 0)))
	var remote_stage := GameState.clamp_stage(int(NetworkManager.remote_stats.get("stage", my_stage)))
	_set_status("相手の準備情報を受信:\n自分ステージ=%s / 相手ステージ=%s（開始時に50%%で抽選）" % [
		GameState.get_stage_name(my_stage),
		GameState.get_stage_name(remote_stage)
	])

func _on_disconnected() -> void:
	_waiting = false
	_exit_lobby()
	_set_status("切断されました")
	GameState.joutai_flag = Enums.JoutaiType.ONLINE_MENU

func _on_connection_failed() -> void:
	_waiting = false
	_exit_lobby()
	_set_status("接続失敗：サーバーが起動していないか、IPアドレスが誤っています")
	GameState.joutai_flag = Enums.JoutaiType.ONLINE_MENU

func _on_game_start() -> void:
	OnlineGameSetup.setup()
	GameState.joutai_flag = Enums.JoutaiType.ONLINE_GAME

# ═══════════════════════════════════════════════════════════
# ステータス表示
# ═══════════════════════════════════════════════════════════

func _set_status(msg: String) -> void:
	if _status_lbl:
		_status_lbl.text = msg

func _backup_online_menu_for_replay() -> void:
	# 保存時に参照するメニュー値を確定しておく
	GameState.online_menu = GameState.online_menu.duplicate(true)


# IPアドレス文字列 "192.168.1.6:12345" から IP とポートを抽出する。
# ポートが省略された場合は default_port を返す。
func _parse_ip_and_port(raw: String, default_port: int = 9999) -> Dictionary:
	var parts := raw.split(":")
	var ip: String
	var port: int = default_port

	if parts.size() >= 2:
		ip = parts[0].strip_edges()
		var port_str := parts[1].strip_edges()
		if port_str.is_valid_int():
			port = int(port_str)
			if port <= 0 or port > 65535:
				port = default_port
	else:
		ip = raw.strip_edges()

	return { "ip": ip, "port": port }
	
# オーバーレイ生成
func _ensure_character_overlay() -> void:
	if _character_overlay == null:
		_character_overlay = CharacterSelectOverlay.new()
		add_child(_character_overlay)

func _make_kuru_row(parent: Control, getter: Callable, setter: Callable) -> void:
	var hbox := HBoxContainer.new()
	_lbl_w(hbox, "くる：", 110)  # OnlineMenuはラベル幅110

	var bl := _mk_btn("◀")
	bl.pressed.connect(func():
		setter.call(wrapi(getter.call() - 1, 0, Constants.get_kuru_count()))
		_update_display()
	)
	hbox.add_child(bl)

	var name_btn := _mk_btn("")
	name_btn.custom_minimum_size.x = 80
	name_btn.pressed.connect(func():
		_kuru_overlay.show_overlay(func(new_idx: int):
			setter.call(new_idx)
			_update_display()
		)
	)
	hbox.add_child(name_btn)

	var br := _mk_btn("▶")
	br.pressed.connect(func():
		setter.call(wrapi(getter.call() + 1, 0, Constants.get_kuru_count()))
		_update_display()
	)
	hbox.add_child(br)

	parent.add_child(hbox)
	_update_fns.append(func(): name_btn.text = Constants.get_kuru_name(getter.call()))

func _ensure_kuru_overlay() -> void:
	if _kuru_overlay == null:
		_kuru_overlay = KuruSelectOverlay.new()
		add_child(_kuru_overlay)

func _ensure_item_overlay() -> void:
	if _item_overlay == null:
		_item_overlay = ItemSelectOverlay.new()
		add_child(_item_overlay)

func _ensure_stage_overlay() -> void:
	if _stage_overlay == null:
		_stage_overlay = StageSelectOverlay.new()
		add_child(_stage_overlay)
