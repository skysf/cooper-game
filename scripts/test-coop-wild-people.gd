extends "res://server.gd"

const ROOM := "wild-people-fixture"
const TOKEN_A := "000000000000000000000000000000a1"
const TOKEN_B := "000000000000000000000000000000b2"
var received := {}
var failures := 0
var assertions := 0
var checks: Array[Dictionary] = []

func _initialize() -> void:
	_verify.call_deferred()

func _process(_delta: float) -> bool:
	return false

func _send(ws: WebSocketPeer, msg: Dictionary) -> bool:
	var key := ws.get_instance_id()
	if not received.has(key):
		received[key] = {}
	received[key][msg.t] = msg.duplicate(true)
	return true

func _verify() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(2)
		return
	save_dir = args[0]
	DirAccess.make_dir_recursive_absolute(save_dir)
	world = JSON.parse_string(FileAccess.get_file_as_string("res://world.json"))
	grid = Rules.collision_grid(world.obstacles)
	var a := _connect(1, TOKEN_A)
	var b := _connect(2, TOKEN_B)
	var room: Dictionary = rooms[ROOM]
	var state: Dictionary = room.data.wildPeople
	_expect(state.raid.nextAt >= 540.0 and state.raid.wave == 0, "new camps get a build buffer before one unarmed adult")
	for key: String in WildPeople.SOURCES:
		var source: Dictionary = WildPeople.SOURCES[key]
		_expect(Rules.free_at(Vector2(source.x, source.z), grid), "every real gathering source stands on walkable ground: " + key)
	for location: Vector2 in [WildPeople.HOME, WildPeople.REST, Survival.TABLE_CENTER + Vector2(0, 0.85)]:
		_expect(Rules.free_at(location, grid), "camp rest, guard and communal table access positions are walkable")
	var water_source := WildPeople.WATER
	var actual_water := false
	for x in range(-10, 11):
		for z in range(-10, 11):
			actual_water = actual_water or is_finite(LakeLayout.surface_height(water_source + Vector2(x, z) * 0.1))
	_expect(Rules.free_at(water_source, grid) and actual_water, "water source is a walkable bank within one metre of actual lake water")
	var npc := WildPeople.make_person("person-1", 2, "female", Vector2(1.5, -83.0), room.data.elapsed)
	npc.yaw = -2.5
	state.people[npc.id] = npc
	state.nextId = 2
	room.actors[a.id].point = Vector2(1.5, -85.0)
	room.actors[b.id].point = Vector2(1.6, -85.0)
	room.actors[a.id].yaw = PI
	room.actors[b.id].yaw = PI
	# A precise first-person aim at each physical leg, independent of a requested hit-zone parameter.
	var leg_target := Vector3(npc.x, 0.40, npc.z) + Vector3(-0.14, 0, 0).rotated(Vector3.UP, npc.yaw)
	var origin := Vector3(1.5, PlayerMotion.WALK_EYE, -85.0)
	var direction := origin.direction_to(leg_target)
	room.data.survival[a.id].bag.spear = 1
	room.data.survival[a.id].weapon = "spear"
	room.actors[a.id].yaw = atan2(-direction.x, -direction.z)
	_do(a, "attack", "", "", room.actors[a.id].yaw, asin(direction.y))
	_expect(npc.legL > 50 and npc.legR == 0 and npc.health < npc.maxHealth, "normal camera ray aimed at left leg really injures only the left leg")
	var head_ray := WildPeople.ray_hit(npc, Vector3(npc.x, 1.62, npc.z - 2), Vector3(npc.x, 1.62, npc.z + 0.2))
	_expect(not head_ray.is_empty() and head_ray.zone == "body", "aiming at the real standing head registers a normal body/stun hit")
	var down_probe := WildPeople.make_person("down-probe", 0, "male", Vector2(1.5, -83), room.data.elapsed)
	down_probe.phase = "down"
	var down_ray := WildPeople.ray_hit(down_probe, Vector3(1.5, 1.6, -82.3), Vector3(1.5, 0.05, -82.3))
	_expect(not down_ray.is_empty() and down_ray.zone == "body", "Down hit area follows the actual exported head behind the instance root")
	var right_probe := WildPeople.make_person("right-probe", 0, "male", Vector2(5, -83), room.data.elapsed)
	var right_hit := WildPeople.ray_hit(right_probe, Vector3(5.14, PlayerMotion.WALK_EYE, -85), Vector3(5.14, 0.40, -83))
	if not right_hit.is_empty():
		WildPeople.harm(state, right_probe, 22, false, right_hit.zone, a.id, room.data.elapsed)
	_expect(not right_hit.is_empty() and right_hit.zone == "legR" and right_probe.legR > 45 and right_probe.legL == 0, "an actual ray through the right leg injures only the right leg")
	var saved_roundtrip := WildPeople.from_save(JSON.parse_string(JSON.stringify(state)), room.data.elapsed, grid)
	var saved_npc: Dictionary = saved_roundtrip.people[npc.id]
	_expect(is_equal_approx(saved_npc.z, -83.0) and is_equal_approx(saved_npc.x, 1.5) and is_equal_approx(saved_npc.yaw, -2.5) and saved_npc.legL == npc.legL, "negative world position, yaw and leg wound survive JSON round trip")
	var negative := WildPeople.make_person("negative", 0, "male", Vector2(-8.0, -76.0), room.data.elapsed)
	negative.yaw = -2.8
	var negative_state := WildPeople.initial(0)
	negative_state.people.negative = negative
	var negative_saved := WildPeople.from_save(JSON.parse_string(JSON.stringify(negative_state)), 0, grid)
	_expect(negative_saved.people.negative.x == -8.0 and negative_saved.people.negative.z == -76.0 and is_equal_approx(negative_saved.people.negative.yaw, -2.8), "both negative x/z coordinates and negative heading remain exact after save")
	# Switch to a blunt weapon, attack the torso and subdue without silently killing.
	room.data.survival[a.id].weapon = ""
	for i in 4:
		room.data.elapsed += 0.8
		var aim := origin.direction_to(Vector3(npc.x, 1.14, npc.z))
		room.actors[a.id].yaw = atan2(-aim.x, -aim.z)
		_do(a, "attack", "", "", room.actors[a.id].yaw, asin(aim.y))
	_expect(npc.phase == "down" and npc.health > 0, "four real blunt attacks stun a wounded adult without killing")
	room.actors[a.id].point = Vector2(1.5, -84.0)
	room.actors[b.id].point = Vector2(1.6, -84.0)
	_do(a, "capture", "", npc.id)
	_expect(npc.phase == "captive", "stunned attacker can be explicitly restrained")
	_do(a, "loot", "", npc.id)
	_do(b, "loot", "", npc.id)
	_expect(room.data.survival[a.id].bag.get("club", 0) == 1 and room.data.survival[b.id].bag.get("club", 0) == 0 and npc.weapon == "", "only one player can confiscate the same real weapon")
	_do(a, "invite", "", npc.id)
	_expect(not _notice(a).ok and npc.phase == "captive", "waiting or capture alone never recruits an uncared-for prisoner")
	room.data.survival[a.id].bag.apple = 3
	room.data.survival[a.id].bag.water = 2
	room.data.survival[a.id].bag.herb = 2
	_do(a, "feed", "apple", npc.id)
	_do(b, "feed", "apple", npc.id)
	_expect(room.data.survival[a.id].bag.apple == 2 and WildPeople.relation(npc, a.id).food == 1 and WildPeople.relation(npc, b.id).food == 0, "care consumes the actual caregiver's food; another player gains no trust or duplicate food")
	_do(a, "feed", "apple", npc.id)
	_do(a, "water", "", npc.id)
	_do(a, "water", "", npc.id)
	_do(a, "treat", "", npc.id)
	var rel := WildPeople.relation(npc, a.id)
	_expect(rel.food == 2 and rel.water == 2 and rel.treatments == 1 and room.data.survival[a.id].bag.herb == 1 and room.data.survival[a.id].bag.water == 0, "food, water and medical care each deduct a real inventory item")
	var wounded: float = npc.legL
	_step(room, 60)
	_expect(npc.legL < wounded and npc.health > 0 and npc.careSeconds > 50, "properly supplied treated prisoner recovers leg injury and accumulates effective care")
	# Top up medicine only after its actual cooldown and let randomized care duration finish.
	_do(a, "treat", "", npc.id)
	if rel.care < npc.careNeed:
		_do(a, "feed", "apple", npc.id)
	_step(room, 65)
	_do(a, "invite", "", npc.id)
	_expect(npc.phase == "companion" and npc.joinedAt > 0 and _notice(a).ok, "only completed care plus a voluntary invitation recruits a free companion")
	_expect(WildPeople.relation(npc, b.id).trust == 0, "trust stays personal after shared recruitment")
	_do(a, "give_equipment", "club", npc.id)
	_expect(npc.weapon == "club" and room.data.survival[a.id].bag.club == 0, "giving confiscated equipment transfers ownership without duplication")
	_do(b, "romance", "", npc.id)
	_expect(not _notice(b).ok and npc.partner.is_empty(), "fresh recruitment and another player's care do not unlock romance")
	# Refusal is a persisted NPC decision with a real cooldown, not a spammable success button.
	npc.joinedAt = room.data.elapsed - 200
	npc.romanceOpen = false
	rel.trust = 75
	rel.affection = 50
	_do(a, "romance", "", npc.id)
	var refused_until: float = rel.refusedUntil
	_do(a, "romance", "", npc.id)
	_expect(refused_until > room.data.elapsed + 590 and not _notice(a).ok and npc.partner.is_empty(), "a refusal prevents repeated proposals for ten online minutes")
	npc.romanceOpen = true
	rel.refusedUntil = 0
	_do(a, "romance", "", npc.id)
	_expect(npc.partner == a.id, "eligible free adults can mutually choose a relationship")
	var snap_a := WildPeople.snapshot(state, a.id, room.data.elapsed)
	var snap_b := WildPeople.snapshot(state, b.id, room.data.elapsed)
	_expect(snap_a.people[npc.id].relation.trust == 75 and snap_b.people[npc.id].relation.trust == 0 and not snap_b.people[npc.id].has("relations") and snap_b.people[npc.id].relationship == "已有伴侣", "snapshots project each player's own relationship without exposing the relationship map")
	# Verify transaction rollback across both the prisoner and actual inventory on failed saves.
	var prior_mood: float = npc.mood
	var prior_trust: float = rel.trust
	var original_dir := save_dir
	save_dir = save_dir.path_join("missing-parent/unavailable")
	_do(a, "chat", "", npc.id)
	save_dir = original_dir
	npc = room.data.wildPeople.people[npc.id]
	state = room.data.wildPeople
	rel = WildPeople.relation(npc, a.id)
	_expect(not _notice(a).ok and npc.mood == prior_mood and rel.trust == prior_trust, "failed atomic save rolls social state back")
	room.actors[a.id].point = Vector2(20, -100)
	var before_health: float = npc.health
	_do(a, "treat", "", npc.id)
	_expect(not _notice(a).ok and npc.health == before_health, "remote and stale care requests cannot reach the NPC")
	room.actors[a.id].point = WildPeople.WATER
	_do(a, "gather", "water")
	_expect(not state.resources.has("water") and room.data.survival[a.id].bag.water == 1, "lake water fills a carried portion without a station")
	# Companion food is physical, public permission is explicit, and it can forage instead.
	npc.hunger = 30
	npc.water = 95
	npc.health = npc.maxHealth
	npc.legL = 0
	npc.order = "guard"
	npc.x = WildPeople.FOOD.x
	npc.z = WildPeople.FOOD.y
	state.publicFood = false
	var fruit_stock: int = state.resources.fruit.stock
	people_motion.tick(room, grid, 0.1)
	_expect(state.resources.fruit.stock == fruit_stock - 1 and npc.hunger > 45, "a free companion forages at the actual source and consumes its finite fruit stock")
	room.data.elapsed = ceilf(room.data.elapsed + float(WildPeople.WORK_SECONDS["GatherFruit"]))
	npc.hunger = 30
	npc.x = Survival.TABLE_CENTER.x
	npc.z = Survival.TABLE_CENTER.y + 0.85
	state.publicFood = true
	var table_count: int = room.data.provisions.size()
	people_motion.tick(room, grid, 0.1)
	_expect(room.data.provisions.size() == table_count - 1 and npc.hunger > 40, "authorized public food comes out of the shared table inventory")
	# Shared death is irreversible, persists, and cannot be abused by stale care/recruit packets.
	WildPeople.kill(state, npc, room.data.elapsed)
	room.actors[a.id].point = WildPeople.position(npc)
	_do(a, "invite", "", npc.id)
	var before_dead_loot := int(room.data.survival[a.id].bag.get("club", 0))
	_do(a, "loot", "", npc.id)
	var after_dead_loot := int(room.data.survival[a.id].bag.get("club", 0))
	_do(a, "loot", "", npc.id)
	var dead_hit := WildPeople.harm(state, npc, 80, false, "body", a.id, room.data.elapsed)
	WildPeople.kill(state, npc, room.data.elapsed)
	_expect(after_dead_loot == before_dead_loot + 1 and room.data.survival[a.id].bag.club == after_dead_loot and npc.loot.is_empty() and not dead_hit.ok and npc.health == 0, "dead NPCs cannot be damaged again or yield the same weapon twice")
	_step(room, 2)
	_expect(npc.phase == "dead" and npc.health == 0 and not _notice(a).ok and npc.partner.is_empty(), "NPC death ends relationships and cannot be undone by shelter, treatment or recruit requests")
	_expect(_checkpoint(ROOM), "final lifecycle checkpoint saves atomically")
	var original_x: float = npc.x
	var original_z: float = npc.z
	rooms.clear()
	_load_room(ROOM)
	var restored: Dictionary = rooms[ROOM].data.wildPeople.people[npc.id]
	_expect(restored.phase == "dead" and restored.health == 0 and is_equal_approx(restored.x, original_x) and is_equal_approx(restored.z, original_z) and WildPeople.relation(restored, a.id).trust == prior_trust and restored.careNeed == npc.careNeed and is_equal_approx(restored.careDuration, npc.careDuration), "death, exact position, random care requirement, treatment and personal trust persist on room reload")
	var raid_room: Dictionary = rooms[ROOM]
	var raid_state: Dictionary = raid_room.data.wildPeople
	raid_state.people.clear()
	raid_state.raid = {"phase": "rest", "nextAt": raid_room.data.elapsed + 29.0, "wave": 0, "warningAt": 0.0, "startedAt": 0.0}
	people_motion.tick(raid_room, grid, 0.1)
	_expect(raid_state.raid.phase == "warning" and raid_state.people.is_empty(), "first raid warns before spawning")
	raid_room.data.elapsed += 30
	people_motion.tick(raid_room, grid, 0.1)
	_expect(raid_state.people.size() == 1 and raid_state.people.values()[0].weapon == "", "first raid is exactly one unarmed adult")
	raid_state.people.values()[0].phase = "gone"
	people_motion.tick(raid_room, grid, 0.1)
	_expect(raid_state.raid.phase == "rest" and raid_state.raid.nextAt - raid_room.data.elapsed >= 300, "waves end with a conservative online rest period")
	raid_state.raid.wave = 25
	raid_state.raid.phase = "warning"
	raid_state.raid.nextAt = raid_room.data.elapsed
	people_motion.tick(raid_room, grid, 0.1)
	var alive := 0
	for enemy: Dictionary in raid_state.people.values():
		if enemy.phase == "raider":
			alive += 1
			_expect(enemy.weapon == "spear" and enemy.shield, "highest-tier adults have ordinary spear and shield equipment")
	_expect(alive == 4, "raid population respects the configured web-friendly cap")
	# Old unclaimed corpse loot must never consume the live-wave budget.
	raid_state.people.clear()
	for i in 64:
		var corpse_id := "corpse-%d" % i
		var corpse := WildPeople.make_person(corpse_id, 4, "male", WildPeople.HOME, raid_room.data.elapsed)
		corpse.phase = "dead"
		corpse.health = 0
		corpse.deadAt = raid_room.data.elapsed
		corpse.loot = {"spear": 1, "shield": 1}
		raid_state.people[corpse_id] = corpse
	raid_state.raid.phase = "warning"
	raid_state.raid.nextAt = raid_room.data.elapsed
	people_motion.tick(raid_room, grid, 0.1)
	var spawned_after_corpses := 0
	for person: Dictionary in raid_state.people.values():
		if person.phase == "raider":
			spawned_after_corpses += 1
	_expect(spawned_after_corpses == 4 and raid_state.people.size() < 64, "64 fresh corpses with unclaimed equipment cannot block subsequent live raids")
	_extra_behaviors()
	if failures == 0:
		print("COOP_WILD_PEOPLE_OK ", JSON.stringify({"assertions": assertions, "lifecycle": true, "actualAim": true, "resourceConsumption": true, "personalRelationships": true, "persistence": true, "raidCap": alive, "checks": checks}))
	quit(0 if failures == 0 else 1)


func _extra_behaviors() -> void:
	connections.clear()
	var a := _connect(3, TOKEN_A)
	var b := _connect(5, TOKEN_B)
	var room: Dictionary = rooms[ROOM]
	var state: Dictionary = room.data.wildPeople
	state.people.clear()
	state.raid.nextAt = room.data.elapsed + 1000
	state.raid.phase = "rest"
	room.actors[a.id].point = Vector2(1.8, -84.9)
	room.actors[b.id].point = Vector2(-10.0, -78.0)
	var enemy := WildPeople.make_person("test-attacker", 0, "male", Vector2(1.8, -83.7), room.data.elapsed)
	state.people[enemy.id] = enemy
	room.data.survival[a.id].health = 6.0
	people_motion._enemy(room, enemy, grid, 0.1)
	room.data.elapsed += 0.7
	people_motion._enemy(room, enemy, grid, 0.1)
	var personal: Dictionary = room.data.survival[a.id]
	_expect(personal.health == 0, "an actual telegraphed enemy swing can incapacitate a player")
	var before_point: Vector2 = room.actors[a.id].point
	room.actors[a.id].direction = Vector2.RIGHT
	_tick_player(room, a.id, 0.0, _grove_time(room.data), 0.1)
	_resolve_knockouts(ROOM, room)
	var down_at: float = personal.downAt
	_expect(room.actors[a.id].point == before_point and room.actors[a.id].direction == Vector2.ZERO and down_at == room.data.elapsed, "incapacitated players cannot move and start an online down timer")
	var before_health: float = enemy.health
	_do(a, "attack", "", "", 0, 0)
	_message(a, {"t": "stone", "action": "pick", "id": "camp-round"})
	_expect(enemy.health == before_health and Stones.held_by(room.data.stones, a.id).is_empty(), "down players cannot melee or pick/throw stones")
	_do(a, "respawn")
	_expect(not _notice(a).ok and personal.health == 0, "the old manual return cannot shorten the team rescue window")
	Survival.tick(personal, Survival.TABLE_CENTER, true, 0.0, 15.0)
	_expect(personal.health == 0, "repaired shelter never auto-revives an incapacitated player")
	_checkpoint(ROOM)
	connections.clear()
	rooms.clear()
	_load_room(ROOM)
	b = _connect(5, TOKEN_B)
	a = _connect(4, TOKEN_A)
	room = rooms[ROOM]
	personal = room.data.survival[a.id]
	_expect(personal.health == 0 and personal.downAt == down_at and room.actors[a.id].point == before_point,
		"a reconnect with a teammate online restores the original countdown and fallen position")
	room.actors[b.id].point = Vector2(3.8, -81.9)
	_message(b, {"t":"rescue","id":a.id})
	_expect(not _notice(b).ok and personal.health == 0, "teammates outside physical reach cannot rescue")
	var helper_at := before_point + Vector2(1.35, 0.0)
	room.actors[b.id].merge(PlayerMotion.spawn(helper_at), true)
	var wall := Storage._record("cabin_wall", before_point + Vector2(.65, 0.0), PI * .5)
	room.data.storage["rescue-test-wall"] = wall
	_message(b, {"t":"rescue","id":a.id})
	_expect(not _notice(b).ok and personal.health == 0 and _notice(b).text.contains("遮挡"), "a real placed cabin wall blocks the rescue ray")
	room.data.storage.erase("rescue-test-wall")
	var original_save_dir := save_dir
	save_dir = original_save_dir.path_join("missing")
	_message(b, {"t":"rescue","id":a.id})
	_expect(not _notice(b).ok and personal.health == 0 and personal.downAt == down_at and _notice(b).text.contains("保存"),
		"a failed checkpoint restores the down state and the original timer")
	save_dir = original_save_dir
	room.data.elapsed = down_at + 14.99
	_message(b, {"t":"rescue","id":a.id})
	_expect(_notice(b).ok and personal.health == 45 and personal.downAt < 0 and room.actors[a.id].point == before_point,
		"the near teammate can revive at the original location just before the 15 second deadline")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_dir.path_join(ROOM + ".json")))
	_expect(saved.survival[a.id].health == 45 and is_equal_approx(float(saved.homes[a.id].x), before_point.x),
		"successful recovery persists the player's health and exact position")
	_message(b, {"t":"rescue","id":a.id})
	_expect(not _notice(b).ok and personal.health == 45, "duplicate rescue requests cannot repeat health or equipment changes")
	room.actors[a.id].point = before_point + Vector2(0, -2.0)
	personal.health = 0.0
	_resolve_knockouts(ROOM, room)
	room.data.elapsed = float(personal.downAt) + 15.0
	_resolve_knockouts(ROOM, room)
	_expect(personal.health == 45 and room.actors[a.id].point == WildPeople.HOME and personal.downAt < 0,
		"at exactly 15 room seconds the downed player returns to camp without pressing a key")
	room.actors[a.id].point = before_point + Vector2(0, -2.0)
	personal.health = 0.0
	_resolve_knockouts(ROOM, room)
	_leave(5)
	_expect(personal.health == 45 and room.actors[a.id].point == WildPeople.HOME and personal.downAt < 0,
		"a casualty gets the solo return when the last teammate disconnects")
	room.actors[a.id].point = before_point + Vector2(0, -2.0)
	personal.health = 0.0
	_resolve_knockouts(ROOM, room)
	_expect(personal.health == 45 and room.actors[a.id].point == WildPeople.HOME and personal.downAt < 0,
		"the solo player returns to camp on the same update as the knockout")
	state = room.data.wildPeople
	state.people.clear()
	var stone_target := WildPeople.make_person("stone-target", 0, "male", Vector2(1.8, -83.7), room.data.elapsed)
	state.people[stone_target.id] = stone_target
	var launch: float = room.data.elapsed
	room.data.stones["qa-sharp"] = {"mode": "air", "at": [1.66, 0.40, -84.05], "velocity": [0.0, 0.0, 10.0], "launch": launch, "edge": 3, "thrower": a.id}
	room.data.elapsed += 0.05
	_tick_stones(room, 0.05)
	_expect(stone_target.legL > 45 and stone_target.legR == 0 and room.data.stones["qa-sharp"].mode == "ground", "an actual flying sharpened stone injures its physical leg contact and then lands")
	room.data.stones.erase("qa-sharp")
	stone_target.phase = "captive"
	stone_target.stunUntil = 0
	stone_target.resistance = 70
	stone_target.mood = 30
	room.actors[a.id].point = Vector2(1.8, -84.5)
	var before_resist: float = personal.health
	people_motion._captive(room, stone_target, grid, 0.1)
	_expect(personal.health == before_resist - 4.0 and stone_target.resistance < 70, "an awake distrustful captive can physically resist a nearby player")
	state.people.clear()
	room.actors.clear()
	# An unguarded table loses exactly the item carried by the retreating thief.
	var thief := WildPeople.make_person("thief", 1, "female", Survival.TABLE_CENTER + Vector2(0, 0.85), room.data.elapsed)
	thief.actionAt = room.data.elapsed - 10.0
	state.people[thief.id] = thief
	room.data.provisions = Survival.initial_provisions()
	var stock: int = room.data.provisions.size()
	people_motion._enemy(room, thief, grid, 0.1)
	_expect(room.data.provisions.size() == stock - 1 and thief.loot.get("apple", 0) == 1 and thief.phase == "retreat", "a raider steals one real table item, carries the loot and retreats")
	var breaker := WildPeople.make_person("breaker", 4, "male", WildPeople.HOME, room.data.elapsed)
	breaker.actionAt = room.data.elapsed - 10.0
	state.people[breaker.id] = breaker
	room.data.provisions.clear()
	state.facility = 8.0
	room.data.quest.repaired = true
	people_motion._enemy(room, breaker, grid, 0.1)
	_expect(state.facility == 0 and not room.data.quest.repaired, "unopposed ordinary attacks can really destroy the roof and extinguish camp lights")
	breaker.health = breaker.maxHealth * 0.2
	people_motion._enemy(room, breaker, grid, 0.1)
	_expect(breaker.phase == "retreat", "seriously injured raiders withdraw instead of fighting forever")
	var prisoner := WildPeople.make_person("sick-prisoner", 0, "male", WildPeople.HOME, room.data.elapsed)
	prisoner.phase = "captive"
	prisoner.hunger = 0
	prisoner.water = 0
	prisoner.sickProgress = 80
	state.people[prisoner.id] = prisoner
	people_motion.tick(room, grid, 0.1)
	_expect(prisoner.escapeAt > room.data.elapsed and prisoner.disease > 0, "neglected captives can become ill and visibly start escaping")
	room.data.elapsed += 25.0
	people_motion.tick(room, grid, 0.1)
	_expect(prisoner.phase in ["retreat", "gone"], "escape warning expires into a real fleeing person")

func _step(room: Dictionary, seconds: float) -> void:
	for i in ceili(seconds * 10):
		room.data.elapsed += 0.1
		people_motion.tick(room, grid, 0.1)

func _connect(key: int, token: String) -> Dictionary:
	var con := {"ws": WebSocketPeer.new(), "room": "", "id": "", "rejected": false}
	connections[key] = con
	_message(con, {"t": "join", "room": ROOM, "token": token})
	return con

func _do(con: Dictionary, action: String, item := "", id := "", yaw := 0.0, pitch := 0.0) -> void:
	con.person_next_ms = 0
	_message(con, {"t": "person", "action": action, "item": item, "id": id, "yaw": yaw, "pitch": pitch})

func _notice(con: Dictionary) -> Dictionary:
	return received[con.ws.get_instance_id()].get("notice", {})

func _expect(ok: bool, message: String) -> void:
	assertions += 1
	checks.append({"passed": ok, "check": message})
	if not ok:
		failures += 1
		push_error(message)
