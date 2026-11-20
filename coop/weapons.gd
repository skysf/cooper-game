extends RefCounted

const CAMP_MODELS := {
	"katana": "res://weapons/katana.glb",
	"rifle": "res://weapons/rifle.glb",
	"pistol": "res://weapons/pistol.glb",
}
const CAMP_START := {
	"katana": Vector2(0.69, -85.67),
	"rifle": Vector2(1.86, -86.60),
	"pistol": Vector2(1.43, -85.56),
}
const KEYS := {
	KEY_1: "", KEY_2: "club", KEY_3: "spear", KEY_4: "stone",
	KEY_6: "katana", KEY_7: "rifle", KEY_8: "pistol",
}
const ATTACKS := {
	"": {"damage": 7.0, "reach": 2.25, "time": 0.67, "sharp": false},
	"stone": {"damage": 14.0, "reach": 2.25, "time": 0.67, "sharp": false},
	"club": {"damage": 14.0, "reach": 2.25, "time": 0.67, "sharp": false},
	"spear": {"damage": 27.0, "reach": 2.95, "time": 0.67, "sharp": true},
	"katana": {"damage": 36.0, "reach": 2.48, "time": 0.32, "sharp": true},
	"rifle": {"damage": 58.0, "reach": 80.0, "time": 1.10, "sharp": true, "aim_fov": 27.0},
	"pistol": {"damage": 30.0, "reach": 34.0, "time": 0.34, "sharp": true, "aim_fov": 58.0},
}

static func stats(item: String) -> Dictionary:
	return ATTACKS.get(item, ATTACKS[""])

static func firearm(item: String) -> bool:
	return stats(item).has("aim_fov")
