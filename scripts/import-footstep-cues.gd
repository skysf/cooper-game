extends SceneTree
## Import the six marked SkyCut cuts into the game's mono PCM voice bank.

const SOUND_PROJECT := "res://../art/game_audio/雨线营地 · 环境与生物音效.skycut"
const OUTPUT := "res://sounds/ai/"
const CUES := ["step_loam_1", "step_loam_2", "step_loam_3", "step_soil_1", "step_soil_2", "step_soil_3"]

func _initialize() -> void:
	var project_path := ProjectSettings.globalize_path(SOUND_PROJECT)
	var project: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(project_path))
	var sources := {}
	for entry: Dictionary in project.media:
		sources[entry.fileName] = project_path.get_base_dir().path_join(entry.relativePath)
	var bank := {}
	for track: Dictionary in project.timeline.audioTracks:
		for clip: Dictionary in track.clips:
			for marker: Dictionary in clip.get("markers", []):
				var name := String(marker.text)
				if name not in CUES:
					continue
				var file := String(clip.sourceURL).uri_decode().get_file()
				var source := AudioStreamWAV.load_from_file(sources[file], {"force/mono": true})
				if source == null or source.stereo or source.format != AudioStreamWAV.FORMAT_16_BITS or bank.has(name):
					push_error("Invalid footstep source for " + name)
					quit(1)
					return
				bank[name] = _game_clip(source, clip)
	if bank.size() != CUES.size():
		push_error("Expected six distinct marked footsteps, found %d" % bank.size())
		quit(1)
		return
	for name: String in bank:
		var sound: AudioStreamWAV = bank[name]
		var path := ProjectSettings.globalize_path(OUTPUT + name + ".wav")
		if sound.save_to_wav(path) != OK:
			push_error("Cannot import " + path)
			quit(1)
			return
	print("Imported six SkyCut footsteps into the game.")
	quit()

func _game_clip(source: AudioStreamWAV, clip: Dictionary) -> AudioStreamWAV:
	var rate := source.mix_rate
	var start := roundi(float(clip.sourceStart) * rate)
	var end := roundi((float(clip.sourceStart) + float(clip.sourceDuration)) * rate)
	var pcm := source.data.slice(2 * start, 2 * end)
	var frames := pcm.size() / 2
	var fade_in := maxf(1.0, float(clip.fadeInDuration) * rate)
	var fade_out := maxf(1.0, float(clip.fadeOutDuration) * rate)
	for i in frames:
		var envelope := minf(1.0, minf(i / fade_in, (frames - 1 - i) / fade_out))
		var sample := roundi(pcm.decode_s16(2 * i) * envelope * float(clip.volume))
		pcm.encode_s16(2 * i, clampi(sample, -32768, 32767))
	var game_clip := AudioStreamWAV.new()
	game_clip.format = AudioStreamWAV.FORMAT_16_BITS
	game_clip.mix_rate = rate
	game_clip.data = pcm
	return game_clip
