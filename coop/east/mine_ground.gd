extends RefCounted

static var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://props/mines/mines_manifest.json")).mines
static var portals := {}

static func _static_init() -> void:
	for id: String in data:
		var site: Dictionary = data[id]
		var p: Array = site.origin
		var pose := Transform3D(Basis(Vector3.UP,float(site.yaw)), Vector3(p[0],p[1],p[2]))
		portals[id] = {"pose":pose, "inverse":pose.affine_inverse()}

# Floor record stores forward station, elevation, lane centre and half width.
static func section(id: String, depth: float) -> Vector3:
	var rows: Array = data[id].floor
	var low := 0
	var high := rows.size()-1
	while high-low > 1:
		var mid := (low+high) >> 1
		if float(rows[mid][0]) < depth:
			low = mid
		else:
			high = mid
	var a: Array = rows[low]
	var b: Array = rows[high]
	var t := clampf(inverse_lerp(a[0],b[0],depth),0,1)
	return Vector3(a[2],a[1],a[3]).lerp(Vector3(b[2],b[1],b[3]),t)

static func station(id: String, depth: float, offset := 0.0) -> Vector3:
	var row := section(id,depth)
	return portals[id].pose * Vector3(row.x+offset,row.y,depth)

static func _near(at: Vector2, id: String) -> bool:
	var origin: Array = data[id].origin
	return absf(at.x-float(origin[0])) < 6 and absf(at.y-float(origin[2])) < 33

static func floor_at(at: Vector2, feet: float, margin := .10, headroom := 2.22) -> float:
	if not is_finite(feet):
		return -INF
	for id: String in portals:
		if not _near(at,id):
			continue
		var p: Vector3 = portals[id].inverse * Vector3(at.x,feet,at.y)
		if p.z < -3.45 or p.z > 32.0+margin:
			continue
		var row := section(id,p.z)
		if absf(p.x-row.x) <= row.z+margin and p.y < row.y+headroom:
			return float(data[id].origin[1])+row.y
	return -INF

static func darkness(eye: Vector3) -> float:
	for id: String in portals:
		if not _near(Vector2(eye.x,eye.z),id):
			continue
		var p: Vector3 = portals[id].inverse * eye
		if p.z <= 0 or p.z > 32.5:
			continue
		var row := section(id,p.z)
		if absf(p.x-row.x) <= row.z+.53 and p.y <= row.y+3.05:
			return 0.69*smoothstep(0,8,p.z) + 0.31*smoothstep(8,30,p.z)
	return 0.0
