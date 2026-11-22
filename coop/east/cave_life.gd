extends RefCounted

const Land = preload("res://east/land.gd")
const Gallery = preload("res://east/mine_ground.gd")
const DUTIES := ["rest","fire","water","food","wood","craft"]
const OUTSIDE := ["food","water","wood"]
const TEXT := {"rest":"在火塘旁休息","fire":"照料火塘","water":"出洞取水","food":"外出采果","wood":"拾取枯枝","craft":"在洞内制作装备"}

static func camps_from_save(saved: Variant, now: float) -> Dictionary:
	var result := {}
	for id: String in Land.region.camps:
		var camp := {"settled":false,"food":0,"water":0,"wood":2,"crafted":0,"fires":0,"fireUntil":0.0,"fruitOnBush":6,"deadfall":8,"fruitAt":0.0,"woodAt":0.0}
		var old: Variant = saved.get(id) if saved is Dictionary else null
		if old is Dictionary:
			camp.settled = old.get("settled") == true
			for k in ["food","water","wood","crafted","fires","fruitOnBush","deadfall"]:
				var v: Variant = old.get(k)
				if (v is int or v is float) and is_finite(float(v)):
					camp[k] = clampi(int(v),0,100000 if k in ["crafted","fires"] else 12)
			for timer: String in ["fireUntil","fruitAt","woodAt"]:
				var until: Variant = old.get(timer)
				if (until is float or until is int) and is_finite(float(until)):
					camp[timer] = clampf(float(until),0,now+150)
		result[id] = camp
	return result

static func restore(npc: Dictionary, old: Dictionary, now: float) -> void:
	var id := String(old.get("homeMine",""))
	if not Land.region.camps.has(id):
		return
	npc.homeMine = id
	npc.carry = clampi(int(old.get("carry",0)),0,4) if str(old.get("carry",0)).is_valid_float() else 0
	npc.berth = 1 if old.get("berth") == 1 else 0
	npc.duty = old.get("duty") if old.get("duty") in DUTIES else "rest"
	npc.leg = clampi(int(old.get("leg",0)),0,9) if str(old.get("leg",0)).is_valid_float() else 0
	var until: Variant = old.get("workUntil")
	npc.workUntil = clampf(float(until),0,now+18) if (until is float or until is int) else 0.0

static func discover(room: Dictionary, people_ai) -> void:
	var state: Dictionary = room.data.wildPeople
	for id: String in state.caves:
		var camp: Dictionary = state.caves[id]
		if camp.settled:
			for source: Array in [["fruitOnBush","fruitAt",6,48.0],["deadfall","woodAt",8,57.0]]:
				if int(camp[source[0]]) < int(source[2]) and float(room.data.elapsed)>=float(camp[source[1]]):
					camp[source[0]] += 1
					camp[source[1]] = room.data.elapsed+float(source[3])
			continue
		var portal := Gallery.station(id,0)
		var seen := false
		for actor: Dictionary in room.actors.values():
			if actor.point.distance_squared_to(Vector2(portal.x,portal.z)) < 45.0*45.0:
				seen = true
				break
		if not seen:
			continue
		camp.settled = true
		for index in 2:
			var tag := id+"-dweller-"+str(index)
			var p := Gallery.station(id,8.0+index*2.4,-.58 if index==0 else .64)
			var npc: Dictionary = people_ai.make_person(tag,index,"female" if index==0 else "male",Vector2(p.x,p.z),room.data.elapsed)
			npc.merge({"phase":"resident","y":p.y,"homeMine":id,"berth":index,"weapon":"","duty":"rest","leg":0,"workUntil":0.0,"carry":0},true)
			npc.duty = _choose(npc,state,camp,room.data.elapsed)
			state.people[tag] = npc

static func _choose(npc: Dictionary, state: Dictionary, camp: Dictionary, now: float) -> String:
	var busy := {}
	for other: Dictionary in state.people.values():
		if other.id != npc.id and other.phase=="resident" and other.homeMine==npc.homeMine:
			busy[other.duty] = true
	var choices := []
	if float(camp.fireUntil)-now < 10:
		if int(camp.wood)>0:
			choices.append("fire")
		elif int(camp.deadfall)>0:
			choices.append("wood")
	if int(camp.water)<2:
		choices.append("water")
	if int(camp.food)<2 and int(camp.fruitOnBush)>0:
		choices.append("food")
	if int(camp.wood)<2 and int(camp.deadfall)>0:
		choices.append("wood")
	if npc.weapon=="" and int(camp.wood)>0 and float(camp.fireUntil)>now+4:
		choices.append("craft")
	for duty: String in choices:
		if not busy.has(duty):
			return duty
	return "rest"

static func _route(npc: Dictionary) -> Array[Vector2]:
	var id: String = npc.homeMine
	var side := -.66 if npc.berth==0 else .72
	var path: Array[Vector2] = []
	var work_spot := Gallery.station(id,10.4 if npc.duty=="fire" else 12.5 if npc.duty=="craft" else 9.5+int(npc.berth),side)
	if npc.duty in OUTSIDE:
		var camp: Dictionary = Land.region.camps[id]
		var gate := Gallery.station(id,-3.45)
		var near_gate := Gallery.station(id,1.4,side*.26)
		var bend := Gallery.station(id,5.7,side*.31)
		var destination: Array = camp[npc.duty]
		var source := Vector2(destination[0],destination[1])
		if npc.duty=="water":
			# Stand at the shallow bank, facing the spring.
			source += source.direction_to(Vector2(gate.x,gate.z))*1.85
		path.assign([Vector2(bend.x,bend.z),Vector2(near_gate.x,near_gate.z),Vector2(gate.x,gate.z),
				source,Vector2(gate.x,gate.z),Vector2(near_gate.x,near_gate.z),Vector2(bend.x,bend.z)])
	path.append(Vector2(work_spot.x,work_spot.z))
	return path

static func _work_clip(duty: String) -> String:
	return "DrawWater" if duty=="water" else "Rest" if duty=="rest" else "GatherFruit"

static func _finish(npc: Dictionary, camp: Dictionary, now: float) -> void:
	match npc.duty:
		"water","food","wood":
			camp[npc.duty] = mini(12,int(camp[npc.duty])+int(npc.carry))
			npc.carry = 0
		"fire":
			if int(camp.wood)>0:
				camp.wood -= 1
				camp.fireUntil = now+118.0
				camp.fires += 1
		"craft":
			if int(camp.wood)>0 and float(camp.fireUntil)>now and npc.weapon=="":
				camp.wood -= 1
				npc.weapon = "club" if npc.berth==0 else "spear"
				camp.crafted += 1
	if npc.water < 72 and int(camp.water)>0:
		camp.water -= 1
		npc.water = minf(100,npc.water+34.0)
	if npc.hunger < 72 and int(camp.food)>0:
		camp.food -= 1
		npc.hunger = minf(100,npc.hunger+32.0)

static func step(room: Dictionary, npc: Dictionary, grid: Dictionary, dt: float, ai) -> void:
	var now: float = room.data.elapsed
	var state: Dictionary = room.data.wildPeople
	var camp: Dictionary = state.caves[npc.homeMine]
	if now - float(npc.speechAt) < 3.0:
		return
	if npc.duty == "rest" and npc.workUntil > now and now - float(npc.speechAt) > 65.0 and now - float(camp.get("greetAt", -1000.0)) > 28.0:
		for actor: Dictionary in room.actors.values():
			if absf(float(npc.y) - float(actor.get("y", 0))) < 1.4 and ai.can_reach(actor.point, Vector2(npc.x, npc.z), grid, 2.4):
				camp.greetAt = now
				npc.speechAt = now
				ai._face(npc, actor.point)
				ai._clip(npc, "Idle", now)
				return
	var path := _route(npc)
	var index := clampi(int(npc.leg),0,path.size()-1)
	var outside: bool = npc.duty in OUTSIDE
	npc.help = "带回补给" if outside and index>=4 else TEXT[npc.duty]
	if npc.workUntil > 0:
		if now < float(npc.workUntil):
			return
		npc.workUntil = 0.0
		if outside and index==3:
			npc.carry = 3
			if npc.duty in ["food","wood"]:
				var resource := "fruitOnBush" if npc.duty=="food" else "deadfall"
				var timer := "fruitAt" if npc.duty=="food" else "woodAt"
				npc.carry = mini(4 if npc.duty=="wood" else 3,int(camp[resource]))
				camp[resource] -= npc.carry
				if float(camp[timer])<=now:
					camp[timer] = now+(48.0 if npc.duty=="food" else 57.0)
			npc.leg = 4
			return
		_finish(npc,camp,now)
		npc.duty = _choose(npc,state,camp,now)
		npc.leg = 0
		return
	var at := Vector2(npc.x,npc.z)
	if at.distance_to(path[index]) > .18:
		ai._drive(room,npc,path[index],1.30 if outside and index>=4 else 1.48,grid,dt)
		return
	if index==path.size()-1 or outside and index==3:
		var clip := _work_clip(npc.duty)
		var work_target := Gallery.station(npc.homeMine,10.4,-1.36)
		var facing := Vector2(work_target.x,work_target.z)
		if outside and index==3:
			var source: Array = Land.region.camps[npc.homeMine][npc.duty]
			facing = Vector2(source[0],source[1])
		elif outside:
			clip = "GatherFruit"
		ai._work(npc,clip,facing,now)
		npc.workUntil = now+(7.0+float(npc.berth) if npc.duty=="rest" else 3.3 if npc.duty in ["fire","craft"] else 1.8)
	else:
		npc.leg = index+1
