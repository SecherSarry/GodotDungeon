extends Room
class_name StandardRoom

# 普通房间：尺寸按档位定。
# SIZE_TABLE 直译 SPD 的 SizeCategory —— (min, max, weight)：min/max 同时约束宽与高。
# 第三个数不是生成概率，别拿它当抽档权重用。
# 本工程地图只有 30x20，档位上界（GIANT 18）远超合理范围，故 min/max_width/height 一律夹紧后再返回。

enum SizeCategory {NORMAL, LARGE, GIANT}

const SIZE_TABLE: Dictionary = {
	SizeCategory.NORMAL: [4, 10, 1],
	SizeCategory.LARGE: [10, 14, 2],
	SizeCategory.GIANT: [14, 18, 3]
}

# 夹紧后要给"房间不贴图边 + 后续还能塞下别的房间"留出的余量。
const MAP_CLEARANCE := 4

var size_cat: SizeCategory = SizeCategory.NORMAL

func _init(cat: int = -1):
	# 不指定档位就用 NORMAL。当前地图 30x20 塞不下大房间，先一律小房。
	size_cat = SizeCategory.NORMAL if cat < 0 else cat


# ---------- 尺寸区间（覆写基类）----------
func min_width() -> int:
	return mini(_table_min(), _cap_width())

func max_width() -> int:
	return mini(_table_max(), _cap_width())

func min_height() -> int:
	return mini(_table_min(), _cap_height())

func max_height() -> int:
	return mini(_table_max(), _cap_height())

func _table_min() -> int:
	return SIZE_TABLE[size_cat][0]

func _table_max() -> int:
	return SIZE_TABLE[size_cat][1]

func _cap_width() -> int:
	return LevelManager.MAP_WIDTH - 2 * MARGIN - MAP_CLEARANCE

func _cap_height() -> int:
	return LevelManager.MAP_HEIGHT - 2 * MARGIN - MAP_CLEARANCE


# ---------- 绘制 ----------
# 把自己整个矩形铺成地板。四周的墙由地图初始化的 WALL 提供（房间与墙之间隔着 MARGIN 余量）。
# 走廊与门不归这里，由 RegularLevel 在连接阶段补。
func paint(map_data: Array) -> void:
	for y in range(top, bottom + 1):
		for x in range(left, right + 1):
			map_data[y][x] = Terrain.EMPTY
