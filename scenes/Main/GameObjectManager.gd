# GameObjectManager.gd
# くる・爆弾の毎フレーム計算、描画順序の更新、ゲームオブジェクトのクリアを担当
# res://scenes/Main/GameObjectManager.gd に配置

class_name GameObjectManager
extends RefCounted

# ============================================================
# 内部ノード参照
# ============================================================
var _kuru_container: Node2D
var _bomb_container: Node2D
var _hard_block_container: Node2D
var _player_1p:      CharacterBody2D
var _player_2p:      CharacterBody2D
var _field:          Node2D

const HARD_BLOCK_SCENE: PackedScene = preload("res://scenes/HardBlock/HardBlock.tscn")


# ============================================================
# セットアップ
# ============================================================

func setup(
		kuru_container: Node2D,
		bomb_container: Node2D,
		hard_block_container: Node2D,
		player_1p:      CharacterBody2D,
		player_2p:      CharacterBody2D,
		field:          Node2D) -> void:
	_kuru_container = kuru_container
	_bomb_container = bomb_container
	_hard_block_container = hard_block_container
	_player_1p      = player_1p
	_player_2p      = player_2p
	_field          = field


# ============================================================
# 毎フレーム計算
# ============================================================

## くるの calc を呼び、終了したものを queue_free する
func calc_kuru() -> void:
	var to_remove := []
	for kuru in _kuru_container.get_children():
		if not kuru.kuru_calc():
			to_remove.append(kuru)
	for kuru in to_remove:
		kuru.queue_free()

## 爆弾の calc を呼び、終了したものを queue_free する
func calc_bomb() -> void:
	var to_remove := []
	for bomb in _bomb_container.get_children():
		if not bomb.bomb_calc():
			to_remove.append(bomb)
	for bomb in to_remove:
		bomb.queue_free()



func refresh_hard_blocks() -> void:
	if _hard_block_container == null:
		return
	for child in _hard_block_container.get_children():
		child.queue_free()

	for y in range(Constants.FIELD_ROWS):
		for x in range(Constants.FIELD_COLS):
			if GameState.masu[y][x]["kind"] != Enums.MasuKind.HARD_BLOCK:
				continue
			var hard_block = HARD_BLOCK_SCENE.instantiate()
			if hard_block and hard_block.has_method("init_hard_block"):
				_hard_block_container.add_child(hard_block)
				hard_block.init_hard_block(x, y)


# ============================================================
# 描画順序
# ============================================================

## z_index を Y 座標ベースで更新する
## 描画順: 背景(0) → 爆風(1) → ハードブロック・プレイヤー・くる(10 + Y座標)
func update_draw_order() -> void:
	if _field:
		_field.z_index = 0
	if _bomb_container:
		_bomb_container.z_index = 1

	const BASE_Z := 10
	if _player_1p and _player_1p.visible:
		_player_1p.z_index = BASE_Z + int(_player_1p.position.y)
	if _player_2p and _player_2p.visible:
		_player_2p.z_index = BASE_Z + int(_player_2p.position.y)

	if _kuru_container:
		for kuru in _kuru_container.get_children():
			if kuru is Node2D:
				kuru.z_index = BASE_Z + int(kuru.position.y) - 10


# ============================================================
# クリア
# ============================================================

## ゲーム終了時にくる・爆弾を全て削除する
func clear_game_objects() -> void:
	for child in _kuru_container.get_children():
		child.queue_free()
	for child in _bomb_container.get_children():
		child.queue_free()
	for child in _hard_block_container.get_children():
		child.queue_free()
