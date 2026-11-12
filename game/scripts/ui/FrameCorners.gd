extends Control
## HUD corner brackets drawn in code; used on portraits and key panels.

var color: Color = Color(0.30, 0.92, 1.0, 0.65)
var inset: float = 5.0
var length: float = 11.0
var line_width: float = 1.5

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var w := size.x
	var h := size.y
	var i := inset
	var l := length
	var c := color
	# top-left
	draw_line(Vector2(i, i), Vector2(i + l, i), c, line_width)
	draw_line(Vector2(i, i), Vector2(i, i + l), c, line_width)
	# top-right
	draw_line(Vector2(w - i, i), Vector2(w - i - l, i), c, line_width)
	draw_line(Vector2(w - i, i), Vector2(w - i, i + l), c, line_width)
	# bottom-left
	draw_line(Vector2(i, h - i), Vector2(i + l, h - i), c, line_width)
	draw_line(Vector2(i, h - i), Vector2(i, h - i - l), c, line_width)
	# bottom-right
	draw_line(Vector2(w - i, h - i), Vector2(w - i - l, h - i), c, line_width)
	draw_line(Vector2(w - i, h - i), Vector2(w - i, h - i - l), c, line_width)


