extends Control
class_name NeonMeter
## Segmented meter used for heat, loyalty and system load.

var value: float = 0.0
var max_value: float = 10.0
var fill_color: Color = Color("#46f0ff")
var back_color: Color = Color(0.08, 0.16, 0.19, 0.7)
var segments: int = 10
var gap: float = 2.0

func set_value(v: float) -> void:
	value = v
	queue_redraw()

func _draw() -> void:
	var n := maxi(1, segments)
	var gap_total: float = gap * float(n - 1)
	var seg_w: float = maxf(1.0, (size.x - gap_total) / float(n))
	var ratio: float = 0.0
	if max_value > 0.0:
		ratio = clampf(value / max_value, 0.0, 1.0)
	var filled: int = int(round(ratio * float(n)))
	for i in range(n):
		var x := float(i) * (seg_w + gap)
		var rect := Rect2(x, 0.0, seg_w, size.y)
		if i < filled:
			draw_rect(rect, fill_color)
		else:
			draw_rect(rect, back_color)
