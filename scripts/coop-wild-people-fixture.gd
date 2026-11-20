extends SceneTree

# Offline fixture authoring only: production protocol exposes no spawn/teleport/stat commands.
const People = preload("res://wild_people.gd")
const Survival = preload("res://survival.gd")
const TOKEN := "cafe00112233445566778899aabbccdd"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 1:
		push_error("Use -- <empty-save-directory> [combat|captive|companion|stress]")
		quit(2)
		return
	var mode: String = args[1] if args.size() > 1 else "combat"
	if mode not in ["combat", "captive", "companion", "stress"]:
		quit(2)
		return
	var code := "wild-qa-" + mode
	DirAccess.make_dir_recursive_absolute(args[0])
	var path := args[0].path_join(code + ".json")
	if FileAccess.file_exists(path):
		push_error("Refusing to overwrite existing fixture: " + path)
		quit(2)
		return
	var player := (code + ":" + TOKEN).sha256_text().left(16)
	var state := People.initial(140.0)
	state.raid.nextAt = 2000.0
	state.publicFood = true
	var npc := People.make_person("person-1", 3 if mode == "combat" else 0, "female", Vector2(4.6, -83.0), 140.0)
	npc.name = "禾岚"
	npc.yaw = PI
	npc.careNeed = 5
	npc.careDuration = 65.0
	if mode in ["captive", "companion", "stress"]:
		npc.phase = "captive" if mode == "captive" else "companion"
		npc.health = 52.0
		npc.legL = 38.0
		npc.clip = "Captive" if mode == "captive" else "Guard"
		npc.weapon = ""
		npc.loot = {"club": 1, "shield": 1}
		if mode != "captive":
			npc.joinedAt = -100.0
			npc.health = npc.maxHealth
			npc.legL = 0
			npc.romanceOpen = true
			var rel := People.relation(npc, player)
			rel.trust = 76.0
			rel.affection = 52.0
			rel.food = 2.0
			rel.water = 2.0
			rel.treatments = 1.0
			rel.care = 6.0
			npc.careSeconds = 65.0
	state.people[npc.id] = npc
	state.nextId = 2
	if mode == "stress":
		state.raid.phase = "warning"
		state.raid.nextAt = 190.0
		state.raid.warningAt = 140.0
		state.raid.wave = 6
		state.settings.damageScale = 0.25
		for i in 3:
			var id := "person-%d" % (i + 2)
			var person := People.make_person(id, 2, "male" if i % 2 == 0 else "female", Vector2(0.0 + i * 1.4, -80.0), 140.0)
			person.phase = "companion"
			person.clip = "Guard"
			state.people[id] = person
		state.nextId = 5
	var personal := Survival.initial_state()
	personal.bag = {"apple": 3, "water": 3, "herb": 3, "club": 1, "spear": 1, "shield": 1}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		quit(2)
		return
	file.store_string(JSON.stringify({"version": 1, "elapsed": 140.0, "groveStartedAt": 0.0, "quest": {"wood": true, "tarp": true, "repaired": true}, "homes": {player: {"x": 4.6, "z": -81.4, "yaw": 0.0}}, "survival": {player: personal}, "wildPeople": state}))
	file.close()
	print("COOP_WILD_FIXTURE ", JSON.stringify({"room": code, "token": TOKEN, "playerId": player, "scenario": mode, "path": path}))
	quit()
