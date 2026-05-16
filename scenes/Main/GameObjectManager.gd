# GameObjectManager.gd
# くる・爆風の毎フレーム計算、描画順序の更新、ゲームオブジェクトのクリアを担当
# res://scenes/Main/GameObjectManager.gd に配置

class_name GameObjectManager
extends RefCounted

# ============================================================
# 内部ノード参照
# ============================================================
var _kuru_container: Node2D
var _bomb_container: Node2D
var _hard_block_container: Node2D
var _player_nodes:   Array[Node] = []
var _field:          Node2D

const HARD_BLOCK_SCENE: PackedScene = preload("res://scenes/HardBlock/HardBlock.tscn")


# ============================================================
# セットアップ
# ============================================================

func setup(
		kuru_container: Node2D,
		bomb_container: Node2D,
		hard_block_container: Node2D,
		player_nodes:   Array[Node],
		field:          Node2D) -> void:
	_kuru_container = kuru_container
	_bomb_container = bomb_container
	_hard_block_container = hard_block_container
	_player_nodes   = player_nodes
	_field          = field


# ============================================================
# 毎フレーム計算
# ============================================================

## くるの calc を呼び、終了したものをコンテナから外して queue_free する
func calc_kuru() -> void:
	if _kuru_container == null:
		return
	var to_remove: Array[Node] = []
	for kuru in _kuru_container.get_children():
		if not is_instance_valid(kuru):
			continue
		if not kuru.kuru_calc():
			to_remove.append(kuru)
	for kuru in to_remove:
		_release_child(_kuru_container, kuru)

## 爆風の calc を呼び、終了したものをコンテナから外して queue_free する
func calc_bomb() -> void:
	if _bomb_container == null:
		return
	var to_remove: Array[Node] = []
	for bomb in _bomb_container.get_children():
		if not is_instance_valid(bomb):
			continue
		if not bomb.bomb_calc():
			to_remove.append(bomb)
	for bomb in to_remove:
		_release_child(_bomb_container, bomb)


func refresh_hard_blocks() -> void:
	if _hard_block_container == null:
		return
	_free_children(_hard_block_container)

	for y in range(Constants.FIELD_ROWS):
		for x in range(Constants.FIELD_COLS):
			if GameState.masu[x][y]["kind"] != Enums.MasuKind.HARD_BLOCK:
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
	for player_node in _player_nodes:
		if player_node and player_node is Node2D and (player_node as Node2D).visible:
			(player_node as Node2D).z_index = BASE_Z + int((player_node as Node2D).position.y)

	if _kuru_container:
		for kuru in _kuru_container.get_children():
			if kuru is Node2D:
				kuru.z_index = BASE_Z + int(kuru.position.y) - 10


# ============================================================
# クリア
# ============================================================

## ゲーム終了時にくる・爆風を全て削除する
func clear_game_objects() -> void:
	_free_children(_kuru_container)
	_free_children(_bomb_container)
	_free_children(_hard_block_container)


func _free_children(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		_release_child(container, child)


func _release_child(container: Node, child: Node) -> void:
	if child == null or not is_instance_valid(child):
		return
	if child.has_method("prepare_for_free"):
		child.call("prepare_for_free")
	if child.get_parent() == container:
		container.remove_child(child)
	child.queue_free()
