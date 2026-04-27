class_name ComPlayerTracker
extends RefCounted

# ============================================================
# ComPlayerTracker
#
# 敵（プレイヤー0）が透明マントを使用中のとき、
# 実座標の代わりに「推定位置」を返す。
# ============================================================

var _cloak_was_active: bool = false
var _estimated_pos: Vector2i = Vector2i(-1, -1)
var _seen_kuru_ids: Dictionary = {}


func get_estimated_enemy_pos(enemy: Dictionary, kuru_container: Node) -> Vector2i:
	var real_pos := Vector2i(
		int(enemy.get("masu_x", 0)),
		int(enemy.get("masu_y", 0))
	)

	if not _is_cloaked(enemy):
		if _cloak_was_active:
			_reset()
		return real_pos

	if not _cloak_was_active:
		_cloak_was_active = true
		_estimated_pos    = real_pos

	_update_from_new_kuru(kuru_container)

	return _estimated_pos


# ============================================================
# [追加] is_tracking()
#
# ComDebugOverlay / ComThinkRoutine が「現在マント追跡中か」を
# 外部から参照するための公開ゲッター。
# 戻り値が true = 敵はマント中で、推定座標を使用している。
# ============================================================
func is_tracking() -> bool:
	return _cloak_was_active


func _update_from_new_kuru(kuru_container: Node) -> void:
	if kuru_container == null:
		return

	for kuru_node in kuru_container.get_children():
		var node_id: int = kuru_node.get_instance_id()
		if _seen_kuru_ids.has(node_id):
			continue
		_seen_kuru_ids[node_id] = true

		var kd: Dictionary = kuru_node.data
		if int(kd.get("player", -1)) != 0:
			continue

		var kx: int = int(kd.get("bomb_x", kd.get("masu_x", -1)))
		var ky: int = int(kd.get("bomb_y", kd.get("masu_y", -1)))
		if kx < 0 or ky < 0:
			continue

		_estimated_pos = Vector2i(kx, ky)


func _is_cloaked(enemy: Dictionary) -> bool:
	return int(enemy.get("cr_item_use",   Enums.ItemType.NO_ITEM)) == Enums.ItemType.INVISIBLE \
	   and int(enemy.get("cr_item_count", 0)) > 0


func _reset() -> void:
	_cloak_was_active = false
	_estimated_pos    = Vector2i(-1, -1)
	_seen_kuru_ids.clear()
