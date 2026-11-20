extends SceneTree
const People = preload("res://wild_people.gd")
const PeopleScene = preload("res://wild_people_scene.gd")
const PeoplePanel = preload("res://wild_people_panel.gd")
const Survival = preload("res://survival.gd")

func _initialize() -> void:
	_verify.call_deferred()

func _verify() -> void:
	root.size = Vector2i(1280, 720)
	var scene := PeopleScene.new()
	root.add_child(scene)
	var panel := PeoplePanel.new()
	root.add_child(panel)
	var state := People.initial(140)
	var player := "0123456789abcdef"
	for i in 4:
		var id := "model-%d" % i
		var npc := People.make_person(id, 4 if i > 1 else 1, "female" if i % 2 == 1 else "male", Vector2(i * 2.0, -84.0), 140)
		npc.phase = "captive" if i == 1 else "companion" if i == 2 else "raider"
		npc.weapon = "spear"
		npc.shield = true
		state.people[id] = npc
	var sampled := People.snapshot(state, player, 140)
	scene.sync(sampled.people, 140, 0.1, Vector3(1.5, 1.67, -81.4))
	scene.sync_sources(sampled, Vector3(1.5, 1.67, -81.4))
	panel.set_open(true, "model-1")
	panel.refresh(sampled, Survival.initial_state(), Vector2(1.5, -81.4), 140, "测试照料反馈", 1)
	await process_frame
	await process_frame
	var missing := []
	var animations := []
	var overhead_rules := true
	for id: String in scene.actors:
		var actor: Dictionary = scene.actors[id]
		overhead_rules = overhead_rules and actor.label.visible == (sampled.people[id].phase == "companion")
		for clip: String in ["Idle", "Walk", "Run", "Attack", "Throw", "Block", "Limp", "LimpLeft", "Down", "Captive", "Rest", "Guard"]:
			if not actor.animator.has_animation(clip):
				missing.append(id + "/" + clip)
		animations.append(actor.animator.get_animation_list().size())
	sampled.people["model-1"].phase = "companion"
	scene.sync(sampled.people, 140.5, 0.1, Vector3(1.5, 1.67, -81.4))
	overhead_rules = overhead_rules and scene.actors["model-1"].label.visible
	if not missing.is_empty() or scene.actors.size() != 4 or not overhead_rules:
		push_error("Missing real models/animations: " + str(missing))
		quit(1)
		return
	for clip: String in ["Walk", "Run", "Attack", "Limp", "LimpLeft", "Down", "Captive", "Rest"]:
		for npc: Dictionary in sampled.people.values():
			npc.clip = clip
			npc.clipAt = 140.0
		scene.sync(sampled.people, 140.5, 0.1, Vector3(1.5, 1.67, -81.4))
		await process_frame
	print("COOP_WILD_PEOPLE_SCENE_OK ", JSON.stringify({"realModels": scene.actors.size(), "animationsPerModel": animations, "panel": panel.is_open, "sourceMarkers": scene.sources.size(), "companionOnlyOverheadLabels": overhead_rules}))
	scene.queue_free()
	panel.queue_free()
	await process_frame
	await process_frame
	quit()
