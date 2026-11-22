extends RefCounted

const LIMIT := 362
const Rocks = preload("res://east/rock_surface.gd")
static var springs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://east/springs.json"))
static var wet_cells := FileAccess.get_file_as_bytes("res://east/spring_water_cells.bin")
static var beds := FileAccess.get_file_as_bytes("res://east/spring_beds.bin").to_float32_array()
static var region: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://east/region.json"))
static var obstacles: Array = JSON.parse_string(FileAccess.get_file_as_string("res://east/obstacles.json"))
static var heights := FileAccess.get_file_as_bytes("res://east/elevation.bin").to_float32_array()
static var soil_footing := FileAccess.get_file_as_bytes("res://east/soil_footing.bin")
static var origin := Vector2(region.origin[0], region.origin[1])
static var cells := Vector2i(region.cells[0], region.cells[1])
static var portal_tiles := _load_portal_tiles()

static func _load_portal_tiles() -> Dictionary:
	var tiles := {}
	var records: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://east/portal_ground.json"))
	for patch: Dictionary in records.values():
		patch.field = PackedFloat32Array(patch.heights)
		patch.erase("heights")
		patch.openCells = PackedInt32Array(patch.openCells)
		patch.start = Vector2(patch.origin[0], patch.origin[1])
		patch.grid_size = Vector2i(patch.cells[0], patch.cells[1])
		var last: Vector2 = patch.start + Vector2(patch.grid_size) * float(patch.spacing)
		for z in range(floori(patch.start.y/16), floori(last.y/16)+1):
			for x in range(floori(patch.start.x/16), floori(last.x/16)+1):
				var tile := Vector2i(x,z)
				if not tiles.has(tile):
					tiles[tile] = []
				tiles[tile].append(patch)
	return tiles

static func contains(at: Vector2) -> bool:
	return at.x >= origin.x

static func is_bare_ground(at: Vector2) -> bool:
	var cell := Vector2i(((at - origin) / float(region.spacing)).floor()).clamp(Vector2i.ZERO, cells - Vector2i.ONE)
	return soil_footing[cell.y * cells.x + cell.x] != 0

static func height(at: Vector2) -> float:
	var tile := Vector2i(floori(at.x/16),floori(at.y/16))
	if portal_tiles.has(tile):
		for patch: Dictionary in portal_tiles[tile]:
			var uv: Vector2 = (at-patch.start)/float(patch.spacing)
			var size: Vector2i = patch.grid_size
			if uv.x>=0 and uv.y>=0 and uv.x<=size.x and uv.y<=size.y:
				var cell := Vector2i(uv.floor()).min(size-Vector2i.ONE)
				if not patch.openCells.has(cell.y*size.x+cell.x):
					return _sample(patch.field,uv,size,0)
	for spring: Dictionary in springs.values():
		var uv := _spring_uv(at,spring)
		if uv.x >= 0:
			return _sample(beds,uv,Vector2i.ONE*int(spring.cells),int(spring.first))
	var uv := ((at-origin)/float(region.spacing)).clamp(Vector2.ZERO,Vector2(cells))
	return _sample(heights,uv,cells,0)

static func _spring_uv(at: Vector2, spring: Dictionary) -> Vector2:
	var uv := (at-Vector2(spring.origin[0],spring.origin[1]))/float(spring.spacing)
	if uv.x<0 or uv.y<0 or uv.x>spring.cells or uv.y>spring.cells:
		return Vector2(-1,-1)
	return uv

static func water_height(at: Vector2) -> float:
	for spring: Dictionary in springs.values():
		var uv := _spring_uv(at,spring)
		if uv.x<0:
			continue
		var n := int(spring.cells)
		var i := mini(floori(uv.x),n-1)
		var j := mini(floori(uv.y),n-1)
		var half := 1 if uv.x-i+uv.y-j<=1.0 else 2
		if wet_cells[int(spring.waterFirst)+j*n+i] & half and _sample(beds,uv,Vector2i.ONE*n,int(spring.first))<float(spring.level):
			return spring.level
	return -INF

static func _sample(field: PackedFloat32Array, uv: Vector2, size: Vector2i, first: int) -> float:
	var ix := mini(floori(uv.x), size.x - 1)
	var iz := mini(floori(uv.y), size.y - 1)
	var u := uv.x - ix
	var v := uv.y - iz
	var stride := size.x + 1
	var a := first + ix + iz * stride
	if u + v <= 1.0:
		return field[a] + (field[a+1]-field[a])*u + (field[a+stride]-field[a])*v
	var d := field[a+stride+1]
	return d + (field[a+stride]-d)*(1.0-u) + (field[a+1]-d)*(1.0-v)
