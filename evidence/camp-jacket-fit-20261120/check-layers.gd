extends SceneTree

const Hiker = preload("res://hiker.gd")
const Clothing = preload("res://clothing.gd")
const Survival = preload("res://survival.gd")
var check: Dictionary = {}

func _initialize() -> void:
	_verify.call_deferred()

func _person(gear: Dictionary) -> Hiker:
	var h := Hiker.new()
	root.add_child(h)
	h.outfit(1)
	h.wear_clothes(gear)
	return h

func _mesh_lods(mesh: Mesh) -> Array:
	return RenderingServer.mesh_get_surface(mesh.get_rid(),0).get("lods",[])

func _verify() -> void:
	var h := _person({"pants":true})
	var base := h.pants_instance.mesh
	var skin := h.pants_instance.skin
	var base_arrays: Array = base.surface_get_arrays(0)
	var raw: PackedVector3Array = base_arrays[Mesh.ARRAY_VERTEX]
	var started := Time.get_ticks_usec()
	h.wear_clothes(Survival.initial_wear())
	var fitting_us := Time.get_ticks_usec()-started
	var tucked := h.pants_instance.mesh
	var arrays: Array = tucked.surface_get_arrays(0)
	var fitted: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	check.separate_fit = base != tucked
	check.skin_same = h.pants_instance.skin == skin
	check.material_same = base.surface_get_material(0) == tucked.surface_get_material(0)
	check.surface_arrays = base_arrays[Mesh.ARRAY_BONES] == arrays[Mesh.ARRAY_BONES] 			and base_arrays[Mesh.ARRAY_WEIGHTS] == arrays[Mesh.ARRAY_WEIGHTS] 			and base_arrays[Mesh.ARRAY_TEX_UV] == arrays[Mesh.ARRAY_TEX_UV] 			and base_arrays[Mesh.ARRAY_INDEX] == arrays[Mesh.ARRAY_INDEX]
	check.lods = _mesh_lods(tucked) == _mesh_lods(base) and _mesh_lods(base).size() == 4
	var waist_vertices := 0
	var lower_unchanged := true
	for i in raw.size():
		if raw[i].y <= 0.72 and raw[i] != fitted[i]:
			lower_unchanged = false
		elif raw[i].y > 0.72 and raw[i] != fitted[i]:
			waist_vertices += 1
	check.leg_geometry = lower_unchanged and waist_vertices > 0
	var a := _person(Survival.initial_wear())
	check.shared_after_first_equip = a.pants_instance.mesh == tucked
	h.wear_clothes({"pants":true})
	check.untucked_after_jacket_removal = h.pants_instance.mesh == base and h.torso.visible and not h.jacket_liner.visible 		and not h.garments.jacket.visible
	check.other_wearer_unaffected = a.pants_instance.mesh == tucked and a.jacket_liner.visible
	h.wear_clothes({"jacket":true})
	check.bare_legs_after_pants_removal = h.bare_legs.visible and not h.garments.pants.visible and h.jacket_liner.visible
	h.wear_clothes(Survival.initial_wear())
	check.fitted_after_redress = h.pants_instance.mesh == tucked and h.jacket_liner.visible
	var drop := Clothing.on_ground("pants")
	check.dropped_pants_original = (drop.get_child(0) as MeshInstance3D).mesh == base
	drop.free()
	var shell: PackedVector3Array = h.jacket_liner.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var back := -INF
	for p: Vector3 in shell:
		back = maxf(back,p.z)
	check.liner_kept_behind_seam = back < -0.013
	var crop_clock := Time.get_ticks_usec()
	for i in 15:
		h._tucked_pants(base)
	var single_us := float(Time.get_ticks_usec()-crop_clock)/15
	print("CAMP_JACKET_LAYERS ",JSON.stringify({"checks":check,"fittedVertices":waist_vertices,
		"coldEquipUs":fitting_us,"meshFitAvgUs":single_us,"assetLods":_mesh_lods(base).size(),"linerLocalBackM":back}))
	var success := not check.values().has(false)
	h.free()
	a.free()
	quit(0 if success else 1)
