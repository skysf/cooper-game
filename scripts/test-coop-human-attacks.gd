extends SceneTree

const Hiker = preload("res://hiker.gd")
const People = preload("res://wild_people.gd")
const PeopleScene = preload("res://wild_people_scene.gd")
const Survival = preload("res://survival.gd")
const Weapons = preload("res://weapons.gd")
const DT := 1.0 / 60.0
var errors: Array[String] = []
var checks := 0

func _initialize() -> void:
	_verify.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors.append(message)

func _point(rig: Skeleton3D, name: String) -> Vector3:
	return rig.get_bone_global_pose(rig.find_bone(name)).origin

func _verify() -> void:
	var h := Hiker.new()
	root.add_child(h)
	h.outfit(1)
	h.wear_clothes(Survival.initial_wear())
	var state := {"health": 100.0, "weapon": "", "shield": false, "attackAt": 10., "attackWeapon": ""}
	h.advance(DT, true)
	var base_hips := _point(h.rig,"hips")
	var base_hand := _point(h.rig,"hand_R")
	var ankles := [_point(h.rig,"foot_L"), _point(h.rig,"foot_R")]
	var poses := {}
	for step in 3:
		state.punchStep = step
		state.attackAt += 2.
		var side := "R" if step==1 else "L"
		var other := "L" if step==1 else "R"
		var guard: Vector3
		for frame in 76:
			h.melee.sync(state, float(state.attackAt) + frame*DT)
			h.advance(DT, true)
			if frame == 7:
				guard = _point(h.rig,"hand_"+side)
			if frame == 14:
				var wrist := _point(h.rig,"hand_"+side)
				var support := _point(h.rig,"hand_"+other)
				poses[String(h.melee.clip)] = [str(guard), str(wrist)]
				_check(wrist.z < support.z-.13 and wrist.z < -.32, "Striking wrist travels in front of the covering hand: "+str(step))
				_check(wrist.distance_to(guard) > .14, "Each take has a distinct load and extension: "+str(step))
				_check(_point(h.rig,"hips").distance_to(base_hips) > .02, "The planted strike transfers weight: "+str(step))
				for ankle in 2:
					_check(_point(h.rig,"foot_"+("L" if ankle==0 else "R")).distance_to(ankles[ankle]) < .025, "Support ankle stays planted")
				var fist_span := _point(h.rig,"middle_03_"+side).distance_to(_point(h.rig,"middle_01_"+side))
				_check(fist_span < .057, "Skinned fingers curl into the fist: "+str(fist_span))
		_check(_point(h.rig,"hand_R").distance_to(base_hand) < .012, "The hand releases back to its previous locomotion pose")
	_check(poses.size()==3, "Three separate unarmed takes are used")
	h.set_eye_view(true,true)
	_check(not h.head_mesh.visible and not h.glasses.visible and not h.garments.cap.visible and h.garments.pants.visible and h.boots[0].visible and h.hands.visible, "First-person head and body visibility")
	# The game locks horizontal FOV. Check the actual framing on a widescreen viewport.
	var wide := SubViewport.new()
	wide.size = Vector2i(1280,720)
	root.add_child(wide)
	var eye := Camera3D.new()
	wide.add_child(eye)
	eye.keep_aspect = Camera3D.KEEP_WIDTH
	eye.fov = 78.
	eye.position.y = 1.67
	eye.rotation.x = -1.55
	h.eye_pitch = eye.rotation.x
	h.advance(DT,true)
	for side in ["L", "R"]:
		var ankle_pixel := eye.unproject_position(h.rig.to_global(_point(h.rig,"foot_"+side)))
		var knee_pixel := eye.unproject_position(h.rig.to_global(_point(h.rig,"shin_"+side)))
		_check(ankle_pixel.y > 360 and knee_pixel.y > ankle_pixel.y and knee_pixel.y < 625,
			"Both ankle and knee are framed above the shortcut bar: "+str([side,ankle_pixel,knee_pixel]))
	wide.free()
	h.wear_clothes({"pants": false, "jacket": false})
	_check(h.bare_legs.visible and h.shorts.visible and h.torso.visible, "Bare legs and body switch with the outfit")
	h.set_eye_view(false,true)
	_check(h.head_mesh.visible and h.glasses.visible, "The full local head returns in third person")
	state.attackAt += 2.
	state.shield = true
	h.shielding = true
	h.melee.sync(state,state.attackAt+.22)
	h.advance(DT,true)
	_check(h.melee.clip == &"PunchCross" and _point(h.rig,"hand_R").z < -.34, "Shield bearers keep the left arm free to guard")
	h.set_seated(true)
	var seat := _point(h.rig,"hand_R")
	h.advance(DT,true)
	_check(seat.distance_to(_point(h.rig,"hand_R")) < .001, "Sitting interrupts the strike")
	h.set_seated(false)
	for item: String in ["club","spear","katana"]:
		state.weapon = item
		state.attackWeapon = item
		state.attackAt += 2.
		h.melee.sync(state,state.attackAt+Weapons.stats(item).time*.33)
		h.advance(DT,true)
		var mount := h.melee_mount(item)
		_check(mount.origin.distance_to(h.held_item_position()) < .001, "Weapon follows the actual palm: "+item)
		if item == "spear":
			_check(mount.basis.y.dot(Vector3.FORWARD) > .87, "Spear follows the baked forward thrust")
	h.swimming = true
	h.advance(DT,true)
	_check(h.melee.underneath.is_empty(), "Swimming suspends attack overlay")

	var scene := PeopleScene.new()
	root.add_child(scene)
	for i in 4:
		var npc := People.make_person("npc",4 if i>=2 else 0,"male" if i%2==0 else "female",Vector2.ZERO,20.)
		npc.shield = false
		npc.weapon = ""
		var group := {"npc":npc}
		scene.sync(group,20.,DT)
		for step in 3:
			var start := 21. + 2.*step
			People._start_swing(npc,start)
			scene.sync(group,start,DT)
			for frame in 40:
				scene.sync(group,start+(frame+1)*DT,DT)
			var actor: Dictionary = scene.actors.npc
			var rig: Skeleton3D = actor.rig
			var side := "R" if step==1 else "L"
			_check(actor.clip == Weapons.PUNCHES[step] and _point(rig,"hand_"+side).z < -.33, "NPC variant reaches forward at room contact time: "+str([i,step,actor.clip]))
		for item: String in ["club","spear","stone"]:
			npc.weapon = item
			People._start_swing(npc,30.,item=="stone")
			scene.sync(group,30.66,.1)
			_check(scene.actors.npc.clip == ("Throw" if item=="stone" else String(Weapons.melee_clip(item,0,false))), "NPC equipment selects its own take")
			_check(scene.actors.npc.right != null, "NPC weapon remains attached")
		scene.sync({},32.,DT)
	scene.free()
	h.free()
	if errors.is_empty():
		print("COOP_HUMAN_ATTACKS_OK ", checks, " ", JSON.stringify(poses))
	else:
		for msg in errors:
			push_error(msg)
	quit(0 if errors.is_empty() else 1)
