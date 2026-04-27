# Enums.gd
# struct.h の enum 移植
# Autoload（Project > Project Settings > Autoload）に登録してください
# 名前: Enums

extends Node


# ============================================================
# 向き
# ============================================================
enum Muki {
	RIGHT,
	LEFT,
	DOWN,
	UP,
}


# ============================================================
# マスの種類
# ============================================================
enum MasuKind {
	BROKEN,      # 空きマス
	SOFT_BLOCK,  # 壊せるブロック
	HARD_BLOCK,  # 壊せないブロック
}


# ============================================================
# プレイヤーキャラクター
# ============================================================
enum PlayerType {
	YAMI,
	SHUNNI,
	UCHI,
	SUGAR,
	NUPI,
	MUNCHI,
	BODORI,
}


# ============================================================
# くるの種類
# ============================================================
enum KuruType {
	KIHON,   # 基本くる
	POPURI,  # ポプリ
	CHEAT,   # チートくる
	KUSHI,   # クシィ
}


# ============================================================
# アイテムの種類
# ============================================================
enum ItemType {
	NO_ITEM,
	ROCKET,
	INVISIBLE,
	SHOES,
	BROTHER,
}


# ============================================================
# ゲーム全体の状態（画面遷移管理）
# ============================================================
enum JoutaiType {
	MAIN_MENU,
	SINGLE_MENU,
	SINGLE_GAME,
	SINGLE_REPLAY,
	SINGLE_REPLAY_READ,
	SINGLE_REPLAY_WRITE,
	VS_MENU,
	VS_GAME,
	VS_REPLAY,
	VS_REPLAY_READ,
	VS_REPLAY_WRITE,
	VS_COM_MENU,
	VS_COM_GAME,
	VS_COM_REPLAY,
	VS_COM_REPLAY_READ,
	VS_COM_REPLAY_WRITE,
	ONLINE_MENU,
	ONLINE_LOBBY,
	ONLINE_GAME,
	ONLINE_REPLAY,
	ONLINE_REPLAY_READ,
	ONLINE_REPLAY_WRITE,
	KEY_CONFIG_MENU,
	KEY_CONFIG_SINGLE,
	KEY_CONFIG_VS_1P,
	KEY_CONFIG_VS_2P,
	SOUND_CONFIG_MENU,
}


# ============================================================
# プレイヤーのアニメーション状態
# ============================================================
enum PlayerJoutaiType {
	STAND_RIGHT,
	STAND_LEFT,
	STAND_DOWN,
	STAND_UP,
	RUN_RIGHT,
	RUN_LEFT,
	RUN_DOWN,
	RUN_UP,
	DEATH,
}


# ============================================================
# ヘルパー関数
# ============================================================

# Muki → アニメーション文字列（AnimationPlayer等で使用）
static func muki_to_str(muki: Muki) -> String:
	match muki:
		Muki.RIGHT: return "right"
		Muki.LEFT:  return "left"
		Muki.DOWN:  return "down"
		Muki.UP:    return "up"
	return "right"

# PlayerJoutaiType → AnimationPlayer用アニメーション名
static func joutai_to_anim(joutai: PlayerJoutaiType) -> String:
	match joutai:
		PlayerJoutaiType.STAND_RIGHT: return "stand_right"
		PlayerJoutaiType.STAND_LEFT:  return "stand_left"
		PlayerJoutaiType.STAND_DOWN:  return "stand_down"
		PlayerJoutaiType.STAND_UP:    return "stand_up"
		PlayerJoutaiType.RUN_RIGHT:   return "run_right"
		PlayerJoutaiType.RUN_LEFT:    return "run_left"
		PlayerJoutaiType.RUN_DOWN:    return "run_down"
		PlayerJoutaiType.RUN_UP:      return "run_up"
		PlayerJoutaiType.DEATH:       return "death"
	return "stand_down"
