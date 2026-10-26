extends RefCounted
## Shared procedural rain and thunder sounds for outdoor scenes.

static func synthesize_sound(looped: bool) -> AudioStreamWAV:
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = 22050
	var count := 22050 * (4 if looped else 5)
	var samples := PackedByteArray()
	samples.resize(count * 2)
	var noise := RandomNumberGenerator.new()
	noise.seed = 9471 if looped else 29731
	var low := 0.0
	for i in range(count):
		var n := noise.randf_range(-1, 1)
		low = lerpf(low, n, 0.025)
		var t := float(i) / 22050.0
		var value := n * 0.3 + low * 0.65
		if not looped:
			value = (low * 3.0 + sin(t * 42.0) * 0.12) * minf(t * 8.0, 1.0) * exp(-t * 0.9)
		else:
			# A short fade on the loop seam avoids a click.
			value *= minf(1.0, minf(t, 4.0 - t) * 40.0)
		samples.encode_s16(i * 2, int(clampf(value, -1, 1) * 25000))
	sound.data = samples
	if looped:
		sound.loop_mode = AudioStreamWAV.LOOP_FORWARD
		sound.loop_end = count
	return sound
