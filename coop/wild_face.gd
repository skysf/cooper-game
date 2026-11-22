extends RefCounted

const MALE = preload("res://sounds/ai/resident_male.wav")
const FEMALE = preload("res://sounds/ai/resident_female.wav")
const HZ := 50
static var envelopes := {}
var skin: MeshInstance3D
var shapes := PackedInt32Array()
var weights := Vector3.ZERO

func _init(model: Node3D) -> void:
	for node: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var jaw := node.find_blend_shape_by_name(&"MouthOpen")
		if jaw < 0:
			continue
		skin = node
		shapes = PackedInt32Array([jaw, node.find_blend_shape_by_name(&"MouthRound"), node.find_blend_shape_by_name(&"Blink")])
		break

# Sample once per recording. A relative noise floor lets both voices close their
# lips in the gaps despite their different recording levels.
static func envelope(female: bool) -> PackedFloat32Array:
	if envelopes.has(female):
		return envelopes[female]
	var clip: AudioStreamWAV = FEMALE if female else MALE
	var pcm := clip.data
	var frame_size := 4 if clip.stereo else 2
	var hop := maxi(1, roundi(float(clip.mix_rate) / HZ))
	var levels := PackedFloat32Array()
	for start in range(0, pcm.size(), hop * frame_size):
		var energy := 0.0
		var count := 0
		for at in range(start, mini(pcm.size(), start + hop * frame_size), frame_size * 4):
			var sample := pcm.decode_s16(at) / 32768.0
			energy += sample * sample
			count += 1
		levels.append(sqrt(energy / maxi(count, 1)))
	var sorted := levels.duplicate()
	sorted.sort()
	var reference := maxf(0.0001, sorted[floori((sorted.size() - 1) * 0.93)])
	for i in levels.size():
		levels[i] = smoothstep(0.035, 0.99, pow(levels[i] / reference, 0.73))
	envelopes[female] = levels
	return levels

static func pose(npc: Dictionary, elapsed: float) -> Vector3:
	if npc.phase in ["dead", "down"]:
		return Vector3(0, 0, 1)
	var seed_value := int(str(npc.id).hash())
	var half_cycle := 3.15 + (seed_value % 113) * 0.014
	var period := 2.0 * half_cycle + 0.79
	var phase := fposmod(elapsed + float(seed_value % 701) * 0.017, period)
	if phase >= half_cycle:
		phase -= half_cycle
	var blink := smoothstep(0.0, 0.063, phase) * (1.0 - smoothstep(0.083, 0.209, phase))
	var age := elapsed - float(npc.get("speechAt", -1000.0))
	if age < 0.0 or age >= (FEMALE if npc.sex == "female" else MALE).get_length():
		return Vector3(0, 0, blink)
	var levels := envelope(npc.sex == "female")
	var position := age * HZ
	var i := mini(floori(position), levels.size() - 1)
	var opening := lerpf(levels[i], levels[mini(i + 1, levels.size() - 1)], fmod(position, 1.0))
	var roundness := opening * (0.25 + 0.45 * (0.5 + 0.5 * sin(age * 13.1 + float(seed_value % 9))))
	return Vector3(opening, roundness, blink)

func apply(value: Vector3) -> void:
	if skin == null or weights.is_equal_approx(value):
		return
	for i in 3:
		if shapes[i] >= 0 and not is_equal_approx(weights[i], value[i]):
			skin.set_blend_shape_value(shapes[i], value[i])
	weights = value
