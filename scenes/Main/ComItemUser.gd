# scenes/Main/ComItemUser.gd
class_name ComItemUser
extends Node

# ====================================================================
#  COM のアイテム使用判断を行うクラス
#
#  所持しているアイテムを状況に応じて使用するかどうかを決定する。
#  危険度マップ (ComDangerDetector) と経路探索 (ComPathfinder) を利用し、
#  特にスピード靴は「現在の速度では安全な脱出先がないが、使用後は脱出可能」な時のみ使う。
#
#  アイテムの優先順位：
#    1. スピード靴（危険で、かつ脱出不可→使用後脱出可の時のみ）
#    2. ロケット（敵が遠く、安全なときに確率で使用）
#    3. 兄弟（同上）
#    4. 透明マント（同上）
#
#  確率で使用するアイテムは、判定ごとに 0.2% の確率で抽選される。
# ====================================================================

# --- 任意アイテムの使用条件 ---
const ROCKET_USE_DISTANCE: int = 6
const BROTHER_USE_DISTANCE: int = 4
const CLOAK_USE_DISTANCE: int = 8
const OPTIONAL_ITEM_USE_CHANCE: float = 0.001


var _game_state: GameState = null
var _danger_detector: ComDangerDetector = null
var _pathfinder: ComPathfinder = null

# デバッグ用：最後の決定理由
var debug_decision_reason: String = ""

func initialize(gs: GameState, detector: ComDangerDetector, pathfinder: ComPathfinder) -> void:
	_game_state = gs
	_danger_detector = detector
	_pathfinder = pathfinder

# --------------------------------------------------------------------
# メインの判断関数
# 戻り値：使用するアイテムのスロット番号 (0～2)。使わなければ -1。
# --------------------------------------------------------------------
func decide(player_num: int, op_estimated: Dictionary) -> int:
	debug_decision_reason = ""   # 毎回リセット
	var p: Dictionary = _game_state.player[player_num]
	var op: Dictionary = op_estimated

	# すでに何かアイテムを発動中なら、新たに使用しない
	if p["cr_item_count"] > 0:
		return -1

	# 現在位置が危険かどうか（被弾までの猶予が DANGER_FRAME_THRESHOLD 以内か）
	var danger: bool = _danger_detector.is_cell_danger(p["masu_x"], p["masu_y"])

	# 敵とのマンハッタン距離
	var dist: int = abs(p["masu_x"] - op["masu_x"]) + abs(p["masu_y"] - op["masu_y"])
	
	# ---------- 優先順位 1: スピード靴 ----------
	if danger:
		# 現在の速度で安全な脱出先がない、かつスピード靴使用時に脱出先がある場合のみ使用
		var can_escape_now: bool = _pathfinder.can_escape_safely(player_num, 0)
		if not can_escape_now:
			var can_escape_with_shoes: bool = _pathfinder.can_escape_safely(player_num, Constants.SHOES_SPEED)
			if can_escape_with_shoes:
				var slot: int = _find_item_slot(p, Enums.ItemType.SHOES)
				if slot != -1:
					debug_decision_reason = "Shoes: danger, no escape now, escape only possible with Shoes"
					return slot

	# ---------- 優先順位 2: ロケット ----------
	if not danger and dist <= ROCKET_USE_DISTANCE:
		if randf() < OPTIONAL_ITEM_USE_CHANCE:
			var slot: int = _find_item_slot(p, Enums.ItemType.ROCKET)
			if slot != -1:
				debug_decision_reason = "Rocket: safe & close, random (%.1f%%)" % (OPTIONAL_ITEM_USE_CHANCE * 100)
				return slot

	# ---------- 優先順位 3: 兄弟 ----------
	if not danger and dist <= BROTHER_USE_DISTANCE:
		if randf() < OPTIONAL_ITEM_USE_CHANCE:
			var slot: int = _find_item_slot(p, Enums.ItemType.BROTHER)
			if slot != -1:
				debug_decision_reason = "Brother: safe & close, random (%.1f%%)" % (OPTIONAL_ITEM_USE_CHANCE * 100)
				return slot

	# ---------- 優先順位 4: 透明マント ----------
	if not danger and dist <= CLOAK_USE_DISTANCE:
		if randf() < OPTIONAL_ITEM_USE_CHANCE:
			var slot: int = _find_item_slot(p, Enums.ItemType.INVISIBLE)
			if slot != -1:
				debug_decision_reason = "Cloak: safe & close, random (%.1f%%)" % (OPTIONAL_ITEM_USE_CHANCE * 100)
				return slot

	return -1

func _find_item_slot(p: Dictionary, item_type: int) -> int:
	for i in range(min(3, p["cr_item"].size())):
		if p["cr_item"][i] == item_type:
			return i
	return -1
