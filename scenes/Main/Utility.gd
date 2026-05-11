# Utility.gd
# 静的ヘルパー関数を集めたユーティリティクラス。
# すべての関数は static であり、インスタンスを生成せずに呼び出せる。
# 主に座標計算・方向変換・当たり判定など、ゲーム全体で使われる低レベルな処理を提供する。

class_name Utility
extends RefCounted


## 切り上げ除算 (ceil division) を行う。
## 整数の割り算で、余りが出る場合に商を 1 増やす。
## 例: ceil_div(10, 3) → 4
## [param num] 分子 (被除数)
## [param dnm] 分母 (除数)
## [return] 切り上げた商 (num + dnm - 1) // dnm
static func ceil_div(num: int, dnm: int) -> int:
	if dnm == 0:
		return 999999
	@warning_ignore("integer_division")
	return (num + dnm - 1) / dnm


## 方向の反対を返す。
## 方向は 0=右(RIGHT), 1=左(LEFT), 2=下(DOWN), 3=上(UP) として定義されている。
## 右 ↔ 左、下 ↔ 上を反転させる。
## [param dir] 元の方向 (0～3)
## [return] 反対方向 (0～3)。不正な値の場合は -1 を返す。
static func opposite_dir(dir: int) -> int:
	match dir:
		0: return 1
		1: return 0
		2: return 3
		3: return 2
	return -1


## 方向から X 方向の差分 (dx) を返す。
## 右なら +1, 左なら -1, 上下方向なら 0。
## [param d] 方向 (0=右,1=左,2=下,3=上)
## [return] dx (1, -1, 0)
static func dx_from_dir(d: int) -> int:
	match d:
		0: return 1
		1: return -1
		2: return 0
		3: return 0
	return 0


## 方向から Y 方向の差分 (dy) を返す。
## 下なら +1, 上なら -1, 左右方向なら 0。
## [param d] 方向 (0=右,1=左,2=下,3=上)
## [return] dy (1, -1, 0)
static func dy_from_dir(d: int) -> int:
	match d:
		0: return 0
		1: return 0
		2: return 1
		3: return -1
	return 0


## 指定マス座標から dir 方向に 1 マス進んだマス座標を返す。
## プレイヤー/くるの位置データ (Dictionary) から "masu_x", "masu_y" を読み取り、
## 隣接セルの Vector2i を計算する。
## [param p] 位置情報を持つ辞書 (少なくとも "masu_x", "masu_y" を含む)
## [param dir] 方向 (0=右,1=左,2=下,3=上)
## [return] 隣接マスの座標 (Vector2i)
static func get_front_cell(p: Dictionary, dir: int) -> Vector2i:
	var mx: int = p["masu_x"]
	var my: int = p["masu_y"]
	match dir:
		0: mx += 1   # 右
		1: mx -= 1   # 左
		2: my += 1   # 下
		3: my -= 1   # 上
	return Vector2i(mx, my)


## 0.1px座標から中心基準のマス座標を返す。
## [param x] X座標（0.1px単位）
## [param y] Y座標（0.1px単位）
## [return] 中心点が属するマス座標
static func world_to_cell(x: int, y: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i((x + 160) / 320, (y + 160) / 320)


## 辞書に x/y がある前提で masu_x/masu_y を同期する。
## [param data] "x","y","masu_x","masu_y" を持つ辞書
static func sync_masu_from_world(data: Dictionary) -> void:
	var cell := world_to_cell(int(data["x"]), int(data["y"]))
	data["masu_x"] = cell.x
	data["masu_y"] = cell.y


## 現在の GameState のマス配列を用いて、指定座標が進入可能か（硬ブロックでないか）を判定する。
## フィールド範囲外なら false を返す。
## [param x] マス X 座標 (0～FIELD_COLS-1)
## [param y] マス Y 座標 (0～FIELD_ROWS-1)
## [return] 進入可能なら true、硬ブロックまたは範囲外なら false
static func is_walkable_cell(x: int, y: int) -> bool:
	if x < 0 or x >= Constants.FIELD_COLS or y < 0 or y >= Constants.FIELD_ROWS:
		return false
	return GameState.masu[x][y]["kind"] != Enums.MasuKind.HARD_BLOCK


## 指定マスから step 方向へ distance マス先までに硬ブロックがあるか判定する。
static func is_blast_blocked(origin_x: int, origin_y: int, step_x: int, step_y: int, distance: int) -> bool:
	for step in range(1, distance + 1):
		if not is_walkable_cell(origin_x + step_x * step, origin_y + step_y * step):
			return true
	return false


## 現在位置から、指定方向の現在のマスを抜け切るまでに必要なフレーム数を計算する。
## 内部的には、キャラクターの座標（0.1px 単位）がマスの境界を越えるまでの距離を求め、
## 移動速度 speed（0.1px/フレーム）で割る。ただし最低 1 フレームとする。
## [param x] 現在の X 座標 (0.1px 単位)
## [param y] 現在の Y 座標 (0.1px 単位)
## [param d] 方向 (0=右,1=左,2=下,3=上)
## [param speed] 1フレームあたりの移動量 (0.1px)
## [return] マス抜けまでのフレーム数。move <= 0 なら 999999 を返す（無限大相当）
static func frames_to_exit_at(x: int, y: int, d: int, speed: int) -> int:
	if speed <= 0:
		return 999999
	var dist: int
	# 各方向について、現在のマス内の残り距離を計算する。
	# 座標系: マスは 320 単位（1マス = 320 × 0.1px = 32px）。
	# 基準点 (x+160, y+160) がキャラクターの中心として、そのマス座標を求め、
	# マスの境界までの距離を算出する。
	if d == 0:   # 右
		@warning_ignore("integer_division")
		var mx: int = (x + 160) / 320   # 中心が所属するマスの X インデックス
		dist = (mx + 1) * 320 - x - 160  # 次のマス境界までの距離
	elif d == 1: # 左
		@warning_ignore("integer_division")
		var mx: int = (x + 160) / 320
		dist = x + 160 - mx * 320 + 1
	elif d == 2: # 下
		@warning_ignore("integer_division")
		var my: int = (y + 160) / 320
		dist = (my + 1) * 320 - y - 160
	elif d == 3: # 上
		@warning_ignore("integer_division")
		var my: int = (y + 160) / 320
		dist = y + 160 - my * 320 + 1
	else:
		return 999999
	# 距離が 0 にならないよう 1 以上にし、ceil_div で切り上げ除算
	return ceil_div(maxi(dist, 1), speed)


## 指定マス (mx, my) に方向 d から進入する際の X 座標を返す。
## 右から進入する場合はマスの左端 (左から 160 = 16px? 内部単位: 320 単位/マスなので 320*mx - 160 は中央より左側) など。
## [param mx] マス X インデックス
## [param d] 進入方向 (0=左から来て入る → 右端、1=右から来て入る → 左端)
## [return] X 座標 (0.1px 単位)
static func entry_x(mx: int, d: int) -> int:
	match d:
		0: return mx * 320 - 160   # 右方向移動時のエントリ座標 (マスの左寄り)
		1: return mx * 320 + 159   # 左方向移動時のエントリ座標 (マスの右寄り)
	return mx * 320                # 上下方向移動時はマスの左端（デフォルト）


## 指定マス (mx, my) に方向 d から進入する際の Y 座標を返す。
## [param my] マス Y インデックス
## [param d] 進入方向 (2=下から来て入る → 上端、3=上から来て入る → 下端)
## [return] Y 座標 (0.1px 単位)
static func entry_y(my: int, d: int) -> int:
	match d:
		2: return my * 320 - 160   # 下方向移動時のエントリ (マスの上寄り)
		3: return my * 320 + 159   # 上方向移動時のエントリ (マスの下寄り)
	return my * 320                # 左右方向移動時はマスの上端


## 方向 (muki) を Vector2i に変換する。
## [param muki] 方向 (0=右,1=左,2=下,3=上)
## [return] 対応する単位ベクトル (右: (1,0), 左: (-1,0), 下: (0,1), 上: (0,-1))
static func dir_to_vec(muki: int) -> Vector2i:
	return Vector2i(dx_from_dir(muki), dy_from_dir(muki))


## ある距離 dist を 1 フレームあたり move_per_frame の速度で移動する際の、
## 衝突までのフレーム数を計算する。
## use_gte が true なら「切り上げ（ceil）」、false なら「切り捨て + 1」で余分に 1 フレーム追加する。
## [param dist] 距離 (単位は move_per_frame と整合していること)
## [param move_per_frame] 1フレームあたりの移動量
## [param use_gte] true なら ceil_div、false なら整数除算の結果に +1
## [return] 衝突までのフレーム数 (dist <= 0 のとき 0)
static func calc_collision_frames(dist: int, move_per_frame: int, use_gte: bool) -> int:
	if dist <= 0:
		return 0
	if use_gte:
		return ceil_div(dist, move_per_frame)
	else:
		@warning_ignore("integer_division")
		return dist / move_per_frame + 1


## くる (Kuru) の爆発中心マス座標を、そのくるのデータから計算する。
## くるの移動方向に応じて、進行方向側の境界に接するマスを中心とする。
## [param data] くるの状態辞書 ("x","y","muki" を含む)
## [return] 爆風の中心マス (Vector2i)
static func kuru_bomb_center(x: int, y: int, muki: int) -> Vector2i:
	match muki:
		Enums.Muki.RIGHT:
			@warning_ignore("integer_division")
			return Vector2i((x + 319) / 320, (y + 160) / 320)   # 右端基準
		Enums.Muki.LEFT:
			@warning_ignore("integer_division")
			return Vector2i(x / 320, (y + 160) / 320)           # 左端基準
		Enums.Muki.DOWN:
			@warning_ignore("integer_division")
			return Vector2i((x + 160) / 320, (y + 319) / 320)   # 下端基準
		Enums.Muki.UP:
			@warning_ignore("integer_division")
			return Vector2i((x + 160) / 320, y / 320)           # 上端基準
	# デフォルト（不明な方向）は中心マス
	@warning_ignore("integer_division")
	return Vector2i((x + 160) / 320, (y + 160) / 320)
