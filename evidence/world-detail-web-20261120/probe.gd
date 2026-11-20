extends SceneTree
const Mine = preload("res://mines_layout.gd")
const World = preload("res://placement_world.gd")
const Placement = preload("res://placement.gd")
const Lake = preload("res://lake_layout.gd")
const Motion = preload("res://player_motion.gd")
const Rules = preload("res://rules.gd")
func _initialize() -> void:
	var steps := 0
	var genuine := 0
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world.json"))
	var grid := Rules.collision_grid(world.obstacles)
	for x in [-72.32,-72.20,-72.079,-72.05,-71.92,-71.82]:
		var last := -1
		for i in range(160):
			var point := Vector2(x, -62.5 + i * .01)
			var floor_y := Lake.walk_height(point)
			var objects := World.nearby(World.mine_grid(),{},point,3.15)
			var from := Vector3(point.x,21.2,point.y)
			var to := Vector3(point.x,floor_y-.04,point.y)
			var authored := -INF
			for part: Dictionary in objects:
				if not part.get("walk_surface",false): continue
				var single: Dictionary = Placement.trace(from,to,[part])
				if not single.is_empty() and single.id == "iron_mine" and single.support:
					authored = maxf(authored,single.point.y)
			if not is_finite(authored) or authored < floor_y+.18: continue
			var from_game := World.floor_height(objects,point,authored,floor_y)
			if authored-from_game>.10:
				if last < 0 or i-last>20:
					var hit := Placement.trace(Vector3(point.x,authored+.215,point.y),to,objects)
					print("FLOOR_LOST ",point," expected=",authored," game=",from_game," terrain=",floor_y," first=",hit)
				last = i
				genuine += 1
			steps += 1
		var actor := Motion.spawn(Vector2(x,-62.30))
		var near := World.nearby(World.mine_grid(),{},actor.point,3.15)
		actor.y = World.floor_height(near,actor.point,20.08,Lake.walk_height(actor.point))
		var before: float = actor.y
		var ground_min := before
		for i in 24:
			Motion.step(actor,Vector2(0,1),0.0,1.0/60.0,grid,{})
			ground_min = minf(ground_min,actor.y)
		print("WALKNORTH x=",x," startY=",before," reach=",actor.point," y=",actor.y," minY=",ground_min)
	print("SAMPLES ",steps," LOST ",genuine)
	quit()
