extends Control

var _bgm_label: Label
var _se_label: Label

func _ready() -> void:
	_clear_children()
	_build_ui()
	_sync_labels()

func _clear_children() -> void:
	for child in get_children():
		child.free()

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	root.custom_minimum_size = Vector2(420, 220)
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var title := Label.new()
	title.text = "── 音量設定 ──"
	root.add_child(title)
	root.add_child(HSeparator.new())

	_bgm_label = _add_slider_row(root, "BGM", SoundManager.get_bgm_volume_percent(), _on_bgm_changed)
	_se_label = _add_slider_row(root, "効果音", SoundManager.get_se_volume_percent(), _on_se_changed)

	root.add_child(HSeparator.new())
	var back_btn := Button.new()
	back_btn.text = "戻る"
	back_btn.focus_mode = Control.FOCUS_NONE
	back_btn.pressed.connect(_on_back)
	root.add_child(back_btn)

func _add_slider_row(parent: Control, label_text: String, initial: float, on_changed: Callable) -> Label:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	var text := Label.new()
	text.text = "%s: %d%%" % [label_text, int(round(initial))]
	row.add_child(text)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value = initial
	slider.value_changed.connect(on_changed)
	row.add_child(slider)
	return text

func _on_bgm_changed(value: float) -> void:
	SoundManager.set_bgm_volume_percent(value)
	_sync_labels()

func _on_se_changed(value: float) -> void:
	SoundManager.set_se_volume_percent(value)
	SoundManager.play_shot(0)
	_sync_labels()

func _sync_labels() -> void:
	if _bgm_label:
		_bgm_label.text = "BGM: %d%%" % int(round(SoundManager.get_bgm_volume_percent()))
	if _se_label:
		_se_label.text = "効果音: %d%%" % int(round(SoundManager.get_se_volume_percent()))

func _on_back() -> void:
	GameState.joutai_flag = Enums.JoutaiType.MAIN_MENU
