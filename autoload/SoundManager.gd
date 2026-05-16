# SoundManager.gd
# init.cpp の imgSoundLoad() / setColorFont() の移植
# Autoload 名: SoundManager

extends Node

# ============================================================
# BGM
# ============================================================
var _bgm_root: Node
var _se_root: Node
var bgm_player: AudioStreamPlayer
var _current_bgm_path: String = ""
var _bgm_stream_cache: Dictionary = {}
var _audio_loaded: bool = false

# ============================================================
# SE プレイヤープール（同名SEの重複再生対応）
# ============================================================
var _se_players: Dictionary = {}  # path -> AudioStreamPlayer

var _bgm_volume_percent: float = 100.0
var _se_volume_percent: float = 100.0

# imgSoundLoad() の移植
## BGM/SE 用ノードを初期化し、必要な音声リソースをまとめて読み込む。
func load_all() -> void:
	if _audio_loaded:
		return
	_audio_loaded = true
	_ensure_audio_roots()
	_load_bgm()
	_load_se()

## BGM/SE プレイヤーの親ノードを未作成時のみ生成する。
func _ensure_audio_roots() -> void:
	if _bgm_root == null:
		_bgm_root = Node.new()
		_bgm_root.name = "BGMPlayers"
		add_child(_bgm_root)
	if _se_root == null:
		_se_root = Node.new()
		_se_root.name = "SEPlayers"
		add_child(_se_root)

## BGM プレイヤーを初期化し、初期トラック（ロビー曲）を再生する。
func _load_bgm() -> void:
	if _bgm_root == null:
		return
	if bgm_player != null and is_instance_valid(bgm_player):
		return
	bgm_player = AudioStreamPlayer.new()
	bgm_player.name = "BGMPlayer"
	_bgm_root.add_child(bgm_player)
	for path in _bgm_paths():
		var stream := _safe_load_audio(path)
		if stream != null:
			_bgm_stream_cache[path] = stream
	# 初期値はロビー曲（存在しない場合はbgm.oggにフォールバック）
	_apply_bgm_volume()
	play_bgm_track("res://assets/bgm/lobby.ogg", true)

## 使用する SE をプレイヤープールへ事前登録して再生準備を整える。
func _load_se() -> void:
	var se_paths := [
		"res://assets/sounds/miss.wav",
		"res://assets/sounds/bomb.wav",
		"res://assets/sounds/gm_Monster00_damage.wav",
		"res://assets/sounds/gm_Monster01_damage.wav",
		"res://assets/sounds/gm_Monster02_damage.wav",
		"res://assets/sounds/gm_Monster03_damage.wav",
		"res://assets/sounds/gm_Monster04_damage.wav",
		"res://assets/sounds/gm_Monster05_damage.wav",
		"res://assets/sounds/gm_Monster06_damage.wav",
		"res://assets/sounds/gm_Monster00_attack.wav",
		"res://assets/sounds/gm_Monster01_attack.wav",
		"res://assets/sounds/gm_Monster02_attack.wav",
		"res://assets/sounds/gm_Monster03_attack.wav",
		"res://assets/sounds/gm_Monster04_attack.wav",
		"res://assets/sounds/gm_Monster05_attack.wav",
		"res://assets/sounds/gm_Monster06_attack.wav",
		"res://assets/sounds/crItemShoes.wav",
		"res://assets/sounds/crItemRocket.wav",
		"res://assets/sounds/crItemBrother.wav",
		"res://assets/sounds/crItemInvisibleStart.wav",
		"res://assets/sounds/crItemInvisibleEnd.wav",
		"res://assets/sounds/gm_ready.wav",
	]
	for path in se_paths:
		if _se_players.has(path):
			continue
		var player := AudioStreamPlayer.new()
		player.name = path.get_file().get_basename()
		_se_root.add_child(player)
		var stream := _safe_load_audio(path)
		if stream:
			player.stream = stream
		_se_players[path] = player
	_apply_se_volume()

# ============================================================
# 再生API
# ============================================================
## 既定の BGM（ロビー曲）を再生するショートカット。
func play_bgm(loop: bool = true) -> void:
	play_bgm_track("res://assets/bgm/lobby.ogg", loop)

## 指定 BGM をキャッシュ付きで切り替えて再生する。
func play_bgm_track(path: String, loop: bool = true) -> void:
	if bgm_player == null:
		return
	var canonical := _canonical_bgm_path(path)
	if canonical == "":
		return
	if _current_bgm_path == canonical and bgm_player.playing:
		return
	var stream: AudioStream = _bgm_stream_cache.get(canonical)
	if stream == null:
		stream = _safe_load_audio(canonical)
		if stream == null:
			return
		_bgm_stream_cache[canonical] = stream
	bgm_player.stream = stream
	if bgm_player.stream is AudioStreamOggVorbis:
		bgm_player.stream.loop = loop
	bgm_player.play()
	_current_bgm_path = canonical

## 現在の BGM 再生を停止する。
func stop_bgm() -> void:
	if bgm_player:
		bgm_player.stop()

## 指定パスの SE を再生する（同名再生中は再スタート）。
func play_se(path: String) -> void:
	var player: AudioStreamPlayer = _se_players.get(path)
	if player and player.stream:
		if player.playing:
			player.stop()
		player.play()

# よく使うSEへのショートカット
## キャラクターに応じた被弾 SE を再生する（練習用固定音にも対応）。
func play_death(character_idx: int = 0, use_practice_sound: bool = false) -> void:
	var clamped_idx: int = clampi(character_idx, 0, 6)
	var se_path := "res://assets/sounds/gm_Monster%02d_damage.wav" % clamped_idx
	if use_practice_sound:
		se_path = "res://assets/sounds/gm_Monster00_damage.wav"
	play_se(se_path)

## 爆風爆発 SE を再生する。
func play_bomb() -> void:
	play_se("res://assets/sounds/bomb.wav")

## キャラクターに応じた射出 SE を再生する。
func play_shot(character_idx: int) -> void:
	play_se("res://assets/sounds/gm_Monster%02d_attack.wav" % character_idx)

## ロケットアイテム使用 SE を再生する。
func play_cr_rocket() -> void:
	play_se("res://assets/sounds/crItemRocket.wav")

## 透明アイテム開始 SE を再生する。
func play_cr_invisible_start() -> void:
	play_se("res://assets/sounds/crItemInvisibleStart.wav")

## 透明アイテム終了 SE を再生する。
func play_cr_invisible_end() -> void:
	play_se("res://assets/sounds/crItemInvisibleEnd.wav")

## スピード靴アイテム使用 SE を再生する。
func play_cr_shoes() -> void:
	play_se("res://assets/sounds/crItemShoes.wav")

## 兄弟アイテム使用 SE を再生する。
func play_cr_brother() -> void:
	play_se("res://assets/sounds/crItemBrother.wav")

## VS COM ゲーム開始 SE を再生する。
func play_ready() -> void:
	play_se("res://assets/sounds/gm_ready.wav")

## VS COM 勝利 BGM を1回再生する（現在の BGM を停止して切り替える）。
func play_win_bgm() -> void:
	play_bgm_track("res://assets/bgm/gm_win.ogg", false)

## VS COM 敗北 BGM を1回再生する（現在の BGM を停止して切り替える）。
func play_lose_bgm() -> void:
	play_bgm_track("res://assets/bgm/gm_lose.ogg", false)

## 人間プレイヤー被弾時の BGM をループ再生する（現在の BGM を停止して切り替える）。
func play_death_bgm() -> void:
	play_bgm_track("res://assets/bgm/death.ogg", true)

## 勝敗 BGM を停止する（メニューへ戻るときに呼ぶ）。
## その後 _update_bgm_for_state() が適切な BGM を再開する。
func stop_win_lose() -> void:
	if _current_bgm_path in [
		"res://assets/bgm/gm_win.ogg",
		"res://assets/bgm/gm_lose.ogg",
	]:
		stop_bgm()
		_current_bgm_path = ""
	
## BGM 音量（%）を更新し、GameState と再生中プレイヤーへ反映する。
func set_bgm_volume_percent(percent: float) -> void:
	_bgm_volume_percent = clampf(percent, 0.0, 100.0)
	GameState.bgm_volume_percent = _bgm_volume_percent
	_apply_bgm_volume()

## SE 音量（%）を更新し、GameState と全 SE プレイヤーへ反映する。
func set_se_volume_percent(percent: float) -> void:
	_se_volume_percent = clampf(percent, 0.0, 100.0)
	GameState.se_volume_percent = _se_volume_percent
	_apply_se_volume()

## 現在の BGM 音量（%）を返す。
func get_bgm_volume_percent() -> float:
	return _bgm_volume_percent

## 現在の SE 音量（%）を返す。
func get_se_volume_percent() -> float:
	return _se_volume_percent

## GameState に保存された音量設定を SoundManager 側へ再適用する。
func sync_volume_from_state() -> void:
	set_bgm_volume_percent(GameState.bgm_volume_percent)
	set_se_volume_percent(GameState.se_volume_percent)

## BGM プレイヤーへ現在の音量設定を dB 変換して反映する。
func _apply_bgm_volume() -> void:
	if bgm_player == null:
		return
	bgm_player.volume_db = _percent_to_db(_bgm_volume_percent)

## すべての SE プレイヤーへ現在の音量設定を dB 変換して反映する。
func _apply_se_volume() -> void:
	for player in _se_players.values():
		if player != null:
			player.volume_db = _percent_to_db(_se_volume_percent)

## 0〜100% の線形音量を Godot 用の dB 値へ変換する。
func _percent_to_db(percent: float) -> float:
	if percent <= 0.0:
		return -80.0
	return linear_to_db(percent / 100.0)

## BGM パスを実在パスへ正規化し、必要に応じて stage0 にフォールバックする。
func _canonical_bgm_path(path: String) -> String:
	if ResourceLoader.exists(path):
		return path
	if path != "res://assets/bgm/stage0.ogg" and ResourceLoader.exists("res://assets/bgm/stage0.ogg"):
		return "res://assets/bgm/stage0.ogg"
	return ""

# ============================================================
# ヘルパー
# ============================================================
## 指定パスの AudioStream を存在確認つきで安全に読み込む。
func _safe_load_audio(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream

## BGM 一覧（ロビー + 各ステージ）を返す。
func _bgm_paths() -> Array[String]:
	var result: Array[String] = ["res://assets/bgm/lobby.ogg"]
	for stage in range(4):
		result.append("res://assets/bgm/stage%d.ogg" % stage)
	result.append("res://assets/bgm/death.ogg")
	result.append("res://assets/bgm/gm_win.ogg")
	result.append("res://assets/bgm/gm_lose.ogg")
	return result
