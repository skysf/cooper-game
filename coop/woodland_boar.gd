extends RefCounted

const Rules = preload("res://rules.gd")
const Lake = preload("res://lake_layout.gd")
const Footing = preload("res://companion_footing.gd")
const Survival = preload("res://survival.gd")
const HOME := Vector2(45,-77)
const TRAIL := [HOME,Vector2(49,-78.5),Vector2(48,-74),Vector2(43,-73.8)]
const BODY := Vector2(.34,.92)
const DAMAGE := 19.0
const WARN_TIME := 1.2
const COLLAPSE_TIME := .90
const RESPAWN_TIME := 900.0
const LOOPING := ["Forage","Walk","Run","Charge","Rest"]

static func start(now: float) -> Dictionary:
	return {"x":HOME.x,"z":HOME.y,"y":Lake.walk_height(HOME),"yaw":-.2,"clip":"Forage",
		"clipAt":now,"until":now+4.2,"cooldown":now,"route":0,"lap":0,"struck":false,"target":""}

static func from_save(raw: Variant, now: float, grid: Dictionary) -> Dictionary:
	var fresh := start(now)
	if raw is not Dictionary or not Survival.finite_number(raw.get("x")) or not Survival.finite_number(raw.get("z")):
		return fresh
	var p := Vector2(raw.x,raw.z)
	if p.distance_to(HOME)>25.0 or not Rules.free_at(p,grid):
		return fresh
	fresh.x=p.x
	fresh.z=p.y
	fresh.y=Lake.walk_height(p)
	if Survival.finite_number(raw.get("yaw")):
		fresh.yaw=wrapf(raw.yaw,-PI,PI)
	if Survival.finite_number(raw.get("route")):
		fresh.route=posmod(int(raw.route),TRAIL.size())
	if Survival.finite_number(raw.get("lap")):
		fresh.lap=clampi(int(raw.lap),0,1000000)
	if raw.get("clip") in ["Forage","Rest","Walk"] and Survival.finite_number(raw.get("clipAt")) and Survival.finite_number(raw.get("until")):
		fresh.clip=raw.clip
		fresh.clipAt=clampf(raw.clipAt,now-14.0,now)
		fresh.until=clampf(raw.until,now,now+14.0)
	fresh.cooldown=now+2.0
	return fresh

static func position(b: Dictionary) -> Vector2:
	return Vector2(b.x,b.z)

static func world_at(b: Dictionary) -> Vector3:
	return Vector3(b.x,b.y,b.z)

# The Blender animal looks down local -X.
static func facing(yaw: float) -> Vector2:
	return Vector2(-cos(yaw),sin(yaw))

static func heading(dir: Vector2) -> float:
	return atan2(dir.y,-dir.x)

# Sample terrain between fore and hind feet and across the body; the returned basis is yaw-local.
static func ground_tilt(at: Vector2, yaw: float) -> Basis:
	var forward:=facing(yaw)
	var side:=Vector2(forward.y,-forward.x)
	var sx:=(Lake.walk_height(at-forward*.64)-Lake.walk_height(at+forward*.64))/1.28
	var sz:=(Lake.walk_height(at+side*.28)-Lake.walk_height(at-side*.28))/.56
	var x_axis:=Vector3(1,clampf(sx,-.65,.65),0).normalized()
	var up:=Vector3(0,clampf(sz,-.65,.65),1).cross(x_axis).normalized()
	return Basis(x_axis,up,x_axis.cross(up).normalized())

# Both the local prediction and the room keep a walker's camera outside the live body.
static func clear_body(actor: Dictionary, previous: Vector2, b: Dictionary, grid: Dictionary) -> void:
	if b.is_empty() or actor.get("onFerry",false) or actor.get("swimming",false):
		return
	var at:=position(b)
	var foot: Vector2=actor.point
	if at.distance_squared_to(foot)>2.25 or absf(float(actor.y)-float(b.y))>1.04:
		return
	var direction:=facing(b.yaw)
	var axis:=Geometry2D.get_closest_point_to_segment(foot,at-direction*.50,at+direction*.60)
	var offset:=foot-axis
	if offset.length_squared()>=.62*.62:
		return
	if offset.is_zero_approx():
		offset=previous-axis
	var normal:=offset.normalized() if not offset.is_zero_approx() else direction.orthogonal()
	var edge:=axis+normal*.62
	var surface:=Lake.walk_height(edge,actor.y)
	if not Rules.free_at(edge,grid) or absf(surface-float(actor.y))>.40:
		edge=previous
		surface=Lake.walk_height(edge,actor.y)
	actor.point=edge
	if actor.get("grounded",false):
		actor.y=surface
		actor.floorY=surface

static func _pose(b: Dictionary, clip: String, now: float, duration: float) -> void:
	b.clip=clip
	b.clipAt=now
	b.until=now+duration

static func _vulnerable(room: Dictionary, id: String) -> bool:
	var actor: Dictionary=room.actors[id]
	return id!=room.get("ship",{}).get("pilot","") and not actor.get("swimming",false) and not actor.get("onFerry",false) and str(actor.get("bed","")).is_empty() and absf(float(actor.y)-Lake.walk_height(actor.point,actor.y))<1.12 and float(room.data.survival[id].health)>0.0

static func _clear(a: Vector2, b: Vector2, feet: float, grid: Dictionary, surface: RefCounted) -> bool:
	if not surface.clear(a,b,feet,BODY):
		return false
	var steps := maxi(1,ceili(a.distance_to(b)/.24))
	var previous:=Lake.walk_height(a,feet)
	for i in range(1,steps+1):
		var point:=a.lerp(b,float(i)/steps)
		var floor_y:=Lake.walk_height(point,previous)
		if absf(floor_y-previous)>.23 or not Rules.free_at(point,grid):
			return false
		previous=floor_y
	return true

static func _closest(room: Dictionary, b: Dictionary, radius: float, grid: Dictionary, surface: RefCounted) -> String:
	var at:=position(b)
	var best:=radius*radius
	var found:=""
	for id: String in room.actors:
		var p: Vector2=room.actors[id].point
		var d:=at.distance_squared_to(p)
		if d<best and _vulnerable(room,id) and _clear(at,p,b.y,grid,surface):
			best=d
			found=id
	return found

static func _retreat(b: Dictionary, now: float) -> void:
	_pose(b,"Run",now,1.45)
	b.target=""
	b.cooldown=now+9.0

static func tick(room: Dictionary, grid: Dictionary, delta: float) -> Dictionary:
	var b: Dictionary=room.data.boar
	var now: float=room.data.elapsed
	var at:=position(b)
	var surface:=Footing.for_room(room)
	var event:={}
	var disturbed: bool=b.get("disturbed",false)
	b.erase("disturbed")
	if b.clip in ["Forage","Walk","Rest","LieDown","Rise"] and now>=float(b.cooldown):
		var target:=_closest(room,b,12.0 if disturbed else 4.6,grid,surface)
		if not target.is_empty():
			if b.clip in ["Rest","LieDown"]:
				_pose(b,"Rise",now,1.1)
				b.cooldown=now+1.1
			else:
				b.target=target
				b.yaw=heading(at.direction_to(room.actors[target].point))
				b.struck=false
				_pose(b,"Warn",now,WARN_TIME)
				event={"cue":"boar_warn","warn":target}
		elif disturbed:
			_retreat(b,now)
	elif b.clip=="Warn" and (not room.actors.has(str(b.target)) or not _vulnerable(room,str(b.target))):
		_retreat(b,now)
	var due:=now>=float(b.until)
	match b.clip:
		"Warn":
			if due:
				# The charge commits to the direction shown during the warning.
				_pose(b,"Charge",now,1.35)
				event.cue="boar_rush"
		"Charge","Run","Walk":
			var goal: Vector2=TRAIL[int(b.route)]
			var walking: bool=b.clip=="Walk"
			var direction:=at.direction_to(goal) if walking else facing(b.yaw)
			if walking and not direction.is_zero_approx():
				b.yaw=lerp_angle(b.yaw,heading(direction),minf(delta*5.,1.))
			var speed:=.98 if walking else 4.4 if b.clip=="Run" else 6.1
			var moved: Vector3=surface.move(at,direction,delta,grid,speed,b.y,BODY)
			var next:=Vector2(moved.x,moved.z)
			var blocked:=next.distance_to(at)<.42*speed*minf(delta,.10) or next.distance_to(HOME)>18.
			if next.distance_to(HOME)<=18.:
				b.x=next.x
				b.z=next.y
				b.y=moved.y
			if b.clip=="Charge" and not b.struck:
				var old_tip:=at+direction*.76
				var tip:=position(b)+direction*.76
				for id: String in room.actors:
					if not _vulnerable(room,id):continue
					var p: Vector2=room.actors[id].point
					var impact:=Geometry2D.get_closest_point_to_segment(p,old_tip,tip) if not old_tip.is_equal_approx(tip) else tip
					if absf(float(room.actors[id].y)-float(b.y))<1.12 and impact.distance_squared_to(p)<.70*.70 and _clear(position(b),p,b.y,grid,surface):
						b.struck=true
						event.hurt=id
						break
			if due or blocked or (walking and next.distance_to(goal)<.14):
				if b.clip=="Charge":
					if blocked:b.yaw=wrapf(b.yaw+PI,-PI,PI)
					_retreat(b,now)
				elif b.clip=="Walk" and int(b.lap)%2==1:
					_pose(b,"LieDown",now,1.3)
				else:
					_pose(b,"Forage",now,5.4)
					event.cue="boar_root"
		"Forage","Rise":
			if due:
				b.route=(int(b.route)+1)%TRAIL.size()
				b.lap=int(b.lap)+1
				_pose(b,"Walk",now,13.0)
		"LieDown":
			if due:_pose(b,"Rest",now,8.0)
		"Rest":
			if due:_pose(b,"Rise",now,1.1)
	return event
