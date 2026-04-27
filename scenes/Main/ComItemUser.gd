class_name ComItemUser
extends RefCounted

# ============================================================
# ComItemUser
#
# COMのアイテム使用判断を担当するクラス。
# _build_com_input() の各優先度ステップに挟み込んで使用する。
#
# 対応アイテム:
#   スピード靴    : 逃げ余裕が乏しいとき（危険状態）に使用
#   くるロケット  : 敵に十分接近 かつ 逃げ余裕が十分なときに使用
#   くる兄弟      : 敵に十分接近 かつ 逃げ余裕が十分なときに使用
#   透明マント    : 敵にある程度接近しているときに使用
# ============================================================

## ── 使用判断の閾値 ──────────────────────────────────────────────────────────

# スピード靴：逃げ先の frames_until_hit がこれ以下なら使用を検討
const SPEED_DEST_FUH_THRESHOLD : int = 30
# スピード靴：経路余裕（path_margin）がこれ以下なら使用を検討（0 = 既に被弾中）
const SPEED_MARGIN_THRESHOLD   : int = 30

# 攻撃アイテム（ロケット・兄弟）：経路余裕がこれ以上あるときだけ使用
const ATTACK_SAFE_MARGIN       : int = 100
# ロケット：この距離以内に敵がいるとき使用を検討（マンハッタン距離）
const ROCKET_USE_DISTANCE      : int = 6
# くる兄弟：この距離以内に敵がいるとき使用を検討（マンハッタン距離）
const BROTHER_USE_DISTANCE     : int = 4

# 透明マント：この距離以内に敵がいるとき使用を検討（マンハッタン距離）
const CLOAK_USE_DISTANCE       : int = 8
# 条件を満たした攻撃/奇襲アイテムを実際に使う確率（0.0〜1.0）
const OPTIONAL_ITEM_USE_CHANCE : float = 0.002


## ── 依存 ──────────────────────────────────────────────────────────────────
var _detector: ComDangerDetector


func _init(detector: ComDangerDetector) -> void:
	_detector = detector


# ============================================================
# decide()
#
# アイテム使用の判断を行い、使用すべきアイテムタイプを返す。
# 使用不要・条件不成立なら Enums.ItemType.NO_ITEM を返す。
#
# [引数]
#   me              : COM プレイヤーデータ（GameState.player[1]）
#   me_x, me_y      : COM の現在マス座標
#   enemy_x, enemy_y: 敵の現在マス座標
#   escape_quality  : ComPathfinder.pick_escape_quality() の戻り値
#                     { "dir", "is_safe", "path_margin", "dest_fuh" }
#   in_danger       : ComDangerDetector.find_bomb_danger() の "danger" フラグ
#
# [優先度]
#   1. スピード靴（危険状態 かつ 逃げ余裕が乏しい）
#   2. くるロケット（安全 かつ 近距離 かつ 余裕十分）
#   3. くる兄弟（安全 かつ 近距離 かつ 余裕十分）
#   4. 透明マント（安全 かつ 中距離）
# ============================================================
func decide(
	me: Dictionary,
	me_x: int, me_y: int,
	enemy_x: int, enemy_y: int,
	escape_quality: Dictionary,
	in_danger: bool
) -> int:
	# 既に何らかのアイテム効果中なら新規使用不可
	if int(me.get("cr_item_count", 0)) > 0:
		return Enums.ItemType.NO_ITEM

	var path_margin: int = escape_quality.get("path_margin", 0)
	var dest_fuh:    int = escape_quality.get("dest_fuh",    ComDangerDetector.SAFE_INF)
	var dist:        int = abs(enemy_x - me_x) + abs(enemy_y - me_y)

	# ── 優先度1: スピード靴 ──────────────────────────────────────────────────
	# 危険状態 かつ 逃げ余裕が乏しい場合に使用する。
	# スピードが上がることで BFS が検出できなかった安全マスへ到達できるようになる。
	if in_danger and _has_speed_item(me):
		var margin_tight: bool = (path_margin <= SPEED_MARGIN_THRESHOLD)
		var dest_tight:   bool = (dest_fuh    <= SPEED_DEST_FUH_THRESHOLD)
		if margin_tight or dest_tight:
			return Enums.ItemType.SHOES

	# 以降は安全な状態でのみ使用する
	if in_danger:
		return Enums.ItemType.NO_ITEM

	# ── 優先度2: くるロケット ────────────────────────────────────────────────
	# 十分近くかつ逃げ余裕が十分ある場合に使用する。
	# ロケットは射程が長いため、通常よりやや離れた距離でも有効。
	if dist <= ROCKET_USE_DISTANCE \
	   and path_margin >= ATTACK_SAFE_MARGIN \
	   and _has_rocket_item(me) \
	   and _should_use_optional_item():
		return Enums.ItemType.ROCKET

	# ── 優先度3: くる兄弟 ────────────────────────────────────────────────────
	# 兄弟は一度に多方向へ飛ぶため、近距離でより効果的。
	if dist <= BROTHER_USE_DISTANCE \
	   and path_margin >= ATTACK_SAFE_MARGIN \
	   and _has_brother_item(me) \
	   and _should_use_optional_item():
		return Enums.ItemType.BROTHER

	# ── 優先度4: 透明マント ──────────────────────────────────────────────────
	# 敵にある程度近づいたタイミングで使用する。
	# 効果中は再使用しない。
	if dist <= CLOAK_USE_DISTANCE \
	   and not _is_cloak_active(me) \
	   and _has_cloak_item(me) \
	   and _should_use_optional_item():
		return Enums.ItemType.INVISIBLE

	return Enums.ItemType.NO_ITEM


func _should_use_optional_item() -> bool:
	return randf() < OPTIONAL_ITEM_USE_CHANCE


# ============================================================
# アイテム所持チェック
# 実ゲーム仕様に合わせ、プレイヤー辞書の cr_item[3] を参照する。
# ============================================================

func _has_speed_item(me: Dictionary) -> bool:
	return _has_item_in_inventory(me, Enums.ItemType.SHOES)

func _has_rocket_item(me: Dictionary) -> bool:
	return _has_item_in_inventory(me, Enums.ItemType.ROCKET)

func _has_brother_item(me: Dictionary) -> bool:
	return _has_item_in_inventory(me, Enums.ItemType.BROTHER)

func _has_cloak_item(me: Dictionary) -> bool:
	return _has_item_in_inventory(me, Enums.ItemType.INVISIBLE)


func _is_cloak_active(me: Dictionary) -> bool:
	return int(me.get("cr_item_use", Enums.ItemType.NO_ITEM)) == Enums.ItemType.INVISIBLE \
		and int(me.get("cr_item_count", 0)) > 0


func _has_item_in_inventory(me: Dictionary, item_type: int) -> bool:
	var items: Array = me.get("cr_item", [])
	for item in items:
		if int(item) == item_type:
			return true
	return false
