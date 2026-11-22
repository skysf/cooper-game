extends RefCounted

const Rules = preload("res://rules.gd")
const MIN_CORNER := Rules.MIN_CORNER
const MAX_CORNER := Rules.MAX_CORNER
const EXTENT := MAX_CORNER - MIN_CORNER
const MAX_PINS := 32
static var LANDMARKS := {
	"vine_gap": {"name":"藤蔓谷口","at":Vector2(123,-87),"landing":Vector2(116.4,-84.0),"view":Vector2(136,-91),"viewHeight":2.25},
	"boar_wood":{"name":"野猪林地","at":Vector2(45,-77),"landing":Vector2(46.1,-68.2),"view":Vector2(45,-77),"viewHeight":.65},
	"root_trail": {"name":"根影林径","at":Vector2(58,-76),"landing":Vector2(58,-75.7)},
	"coal_mine": {"name":"林坡煤矿","at":Vector2(90,-49),"landing":Vector2(90,-55)},
	"flower_valley": {"name":"箭袋树花谷","at":Vector2(191,-52),"landing":Vector2(191,-52)},
	"iron_mine": {"name":"层岩铁矿","at":Vector2(265,-62),"landing":Vector2(265,-56)},
	"shale_steps": {"name":"赤层岩坡","at":Vector2(307,-49),"landing":Vector2(301,-20),"view":Vector2(310,-52),"viewHeight":1.0},
	"east_ridge": {"name":"层岩台地","at":Vector2(322,-32),"landing":Vector2(322,-32.4)},
	"camp": {"name": "营地木屋", "at": Vector2(1.9, -89.6), "landing": Vector2(1.9, -85.0)},
	"reed_bank": {"name":"湖岸芦苇荡","at":Vector2(-20.27,-35.08),"landing":Vector2(-17.9,-32.6),"view":Vector2(-21.6,-35.2),"viewHeight":1.38},
	"lake": {"name": "鹿鸣湖", "at": Vector2(-26.0, -50.0), "landing": Vector2(-8.55, -49.1)},
	"ridge": {"name": "海湾崖顶", "at": Vector2(-72.25, -51.8), "landing": Vector2(-69.9, -53.15)},
	"beach": {"name": "海湾沙滩", "at": Vector2(-85.1, -51.0), "landing": Vector2(-84.8, -50.7)},
	"buddha": {"name": "乐山大佛", "at": Rules.LakeLayout.Coast.buddha.pose.origin, "landing": Rules.LakeLayout.Coast.buddha.landing},
	"island": {"name": "外海小岛", "at": Vector2(-188.0, -58.5), "landing": Vector2(-187.55, -57.1)},
	"tower": {"name": "瞭望塔", "at": Vector2(9.0, -17.0), "landing": Vector2(6.7, -16.9)},
}

static func contains(point: Vector2) -> bool:
	return point.is_finite() and point == point.clamp(MIN_CORNER, MAX_CORNER)

static func read_point(value: Dictionary) -> Vector2:
	var x: Variant = value.get("x")
	var z: Variant = value.get("z")
	if not ((x is float or x is int) and (z is float or z is int)):
		return Vector2.INF
	var point := Vector2(x, z)
	return point if contains(point) else Vector2.INF

static func pin_id_valid(value: Variant) -> bool:
	return value is String and value.length() == 16 and value.is_valid_hex_number(false) and value == value.to_lower()

static func pins_from_save(saved: Variant) -> Dictionary:
	var result := {}
	if saved is Dictionary:
		for owner: Variant in saved:
			if not pin_id_valid(owner) or not saved[owner] is Dictionary:
				continue
			var pins := {}
			for id: Variant in saved[owner]:
				var data: Variant = saved[owner][id]
				if pin_id_valid(id) and data is Dictionary and read_point(data).is_finite():
					pins[id] = {"x": data.x, "z": data.z}
				if pins.size() >= MAX_PINS:
					break
			if not pins.is_empty():
				result[owner] = pins
	return result
