# CharacterSelectOverlay.gd
class_name CharacterSelectOverlay
extends Window

var _grid: GridContainer
var _selected_callback: Callable
var _thumbnail_textures: Array[Texture2D] = []

func _ready() -> void:
	title = "キャラクター選択"
	popup_window = true
	unresizable = true
	close_requested.connect(_on_close_requested)
	wrap_controls = true
	_build_grid()
	hide()

# [fix] ウィンドウ外クリック検出: フォーカスが外れた瞬間に閉じる
# (_input 内での Rect2 判定は Window 内ローカル座標とスクリーン座標が混在して
#  正しく動作しないため削除し、OS レベルのフォーカス通知に置き換え)
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and visible:
		_on_close_requested()

func _build_grid() -> void:
	# [fix] MarginContainer で余白を作り、グリッド全体をウィンドウ内に収める
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top",    8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.add_theme_constant_override("margin_left",   8)
	margin.add_theme_constant_override("margin_right",  8)
	add_child(margin)

	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	margin.add_child(_grid)   # [fix] margin の子に変更（元は Window 直下）

	_load_thumbnails()
	var count     := Constants.get_character_count()
	var cell_size := Vector2(108, 140)   # [fix] キャラ名の横幅確保のため 100→108

	for i in range(count):
		var btn := Button.new()
		btn.custom_minimum_size = cell_size
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_character_button_pressed.bind(i))

		# [fix] VBoxContainer を PRESET_FULL_RECT でボタン全体に広げてセンタリングの基準にする
		#       (旧: CenterContainer > VBoxContainer → VBox 幅がコンテンツ幅になりセンタリング不能)
		var vbox := VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_theme_constant_override("separation", 2)
		vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		# キャラ画像（StandD 先頭フレーム）
		var tex_rect := TextureRect.new()
		tex_rect.expand_mode    = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex_rect.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.custom_minimum_size = Vector2(80, 80)
		tex_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if i < _thumbnail_textures.size() and _thumbnail_textures[i]:
			tex_rect.texture = _thumbnail_textures[i]
		vbox.add_child(tex_rect)

		# キャラ名
		var name_label := Label.new()
		name_label.text = Constants.get_character_name(i)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF      # [fix] 折り返し無効
		name_label.clip_text     = true                           # [fix] 長い名前はクリップ
		# [fix] SIZE_FILL で VBox 幅いっぱいに広げ、horizontal_alignment CENTER でテキストを中央に
		name_label.size_flags_horizontal = Control.SIZE_FILL
		name_label.custom_minimum_size.x = cell_size.x - 4       # [fix] ボタン幅に合わせた最低幅
		vbox.add_child(name_label)

		# ベースステータス (速度/ショット/パワー)
		var stats_label := Label.new()
		var max_stats := Constants.get_character_max_stats(i)
		stats_label.text = "速度:%d パワー:%d くる数:%d" % [
			int(max_stats.get("speed", 0)),
			int(max_stats.get("power", 0)),
			int(max_stats.get("shot", 0))
		]
		stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stats_label.add_theme_font_size_override("font_size", 10)
		stats_label.autowrap_mode        = TextServer.AUTOWRAP_OFF     # [fix]
		stats_label.size_flags_horizontal = Control.SIZE_FILL            # [fix]
		vbox.add_child(stats_label)

		btn.add_child(vbox)
		_grid.add_child(btn)

	reset_size()

func _load_thumbnails() -> void:
	var count := Constants.get_character_count()
	for ch in range(count):
		var sprite_info := Constants.get_character_sprite_info(ch, "stand_d")
		if sprite_info.is_empty():
			_thumbnail_textures.append(null)
			continue
		var suffix := str(sprite_info.get("suffix", "StandD"))
		var cols   := int(sprite_info.get("cols", 1))
		var rows   := int(sprite_info.get("rows", 1))
		var path   := "res://assets/images/character/character%d%s.png" % [ch, suffix]
		if not ResourceLoader.exists(path):
			_thumbnail_textures.append(null)
			continue
		var sheet_tex := ImageManager.get_image(path)
		if sheet_tex == null:
			_thumbnail_textures.append(null)
			continue
		@warning_ignore("integer_division")
		var frame_w := maxi(sheet_tex.get_width()  / maxi(cols, 1), 1)
		@warning_ignore("integer_division")
		var frame_h := maxi(sheet_tex.get_height() / maxi(rows, 1), 1)
		var thumb   := ImageManager.get_transparent_image(path, 0, 0, frame_w, frame_h)
		_thumbnail_textures.append(thumb)

func show_overlay(callback: Callable) -> void:
	_selected_callback = callback
	reset_size()        # [fix] コンテンツサイズを確定してから中央表示
	popup_centered()    # [fix] 引数なしで現在の size を使用（旧: popup_centered(size) は _ready 直後の未確定サイズを渡す恐れがある）

func _on_character_button_pressed(index: int) -> void:
	if _selected_callback.is_valid():
		_selected_callback.call(index)
	hide()

func _on_close_requested() -> void:
	_selected_callback = Callable()
	hide()

# [fix] _input メソッドを削除
# 旧実装の問題点:
#   - Window 内の _input では event.global_position はウィンドウ内ローカル座標 (0,0 起点) になる
#   - 一方 position はスクリーン座標 (例: x=700) なので Rect2(position, size) との比較が常にズレる
#   - 結果として左端の1番目ボタン (x≈8) が position.x より小さいため「ウィンドウ外」と
#     誤判定され、button_down 時点で即 hide() → コールバック未実行でウィンドウが閉じる
#   - また Window 外のマウスイベントは Window の _input には届かないため
#     「ウィンドウ外クリックで閉じる」機能自体が根本的に成立しない
#   → _notification(NOTIFICATION_WM_WINDOW_FOCUS_OUT) に置き換えることで両問題を解決
