extends SceneTree

func _initialize() -> void:
	call_deferred("write_library")

func write_library() -> void:
	var source := load("res://baked.glb") as PackedScene
	var model := source.instantiate()
	root.add_child(model)
	var player: AnimationPlayer = model.find_children("*","AnimationPlayer",true,false)[0]
	var result := AnimationLibrary.new()
	var standing := player.get_animation(&"Stand")
	var args := OS.get_cmdline_user_args()
	var clips := args[1].split(",") if args.size() > 1 else PackedStringArray(["Walk","Run","Takeoff","Air","Land","Swim","Tread"])
	for clip: StringName in clips:
		if not player.has_animation(clip):
			push_error("Missing clip " + String(clip))
			quit(1)
			return
		var action := player.get_animation(clip).duplicate(true) as Animation
		if clip in [&"Walk",&"Run",&"Air",&"Swim",&"Tread"]:
			action.loop_mode = Animation.LOOP_LINEAR
		result.add_animation(clip,action)
		print(clip," ",action.length," ",action.get_track_count()," ",action.track_get_path(0))
	var destination := args[0]
	var error := ResourceSaver.save(result,destination)
	print("Stand rig path ",standing.track_get_path(0)," output ",destination," ",error)
	quit(error)
