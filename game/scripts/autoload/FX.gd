extends Node
## Presentation-only effects. Never owns game state; all helpers are tween/shader based.

var layer: Control
var flash_rect: ColorRect
var _flash_tween: Tween

func attach(parent: Node) -> void:
	layer = Control.new()
	layer.name = "FXLayer"
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(layer)
	flash_rect = ColorRect.new()
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_rect.color = Color(0, 0, 0, 0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash_rect)

func flash(color: Color, alpha: float = 0.22, duration: float = 0.35) -> void:
	if flash_rect == null or not is_instance_valid(flash_rect):
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	flash_rect.color = Color(color.r, color.g, color.b, 0.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(flash_rect, "color:a", alpha, 0.05)
	_flash_tween.tween_property(flash_rect, "color:a", 0.0, duration)

func pulse(node: Control, amount: float = 1.05, duration: float = 0.2) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.pivot_offset = node.size * 0.5
	var tw := create_tween()
	tw.bind_node(node)
	tw.tween_property(node, "scale", Vector2(amount, amount), duration * 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector2.ONE, duration * 0.7).set_trans(Tween.TRANS_QUAD)

func fade_in(node: Control, duration: float = 0.25, delay: float = 0.0) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.modulate.a = 0.0
	var tw := create_tween()
	tw.bind_node(node)
	tw.tween_interval(delay)
	tw.tween_property(node, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_SINE)

func stagger(container: Container, step: float = 0.045, from_scale: float = 0.965) -> void:
	if container == null or not is_instance_valid(container):
		return
	await get_tree().process_frame
	if not is_instance_valid(container):
		return
	var i := 0
	for child in container.get_children():
		if not (child is Control) or child.is_queued_for_deletion():
			continue
		var c := child as Control
		c.pivot_offset = c.size * 0.5
		c.modulate.a = 0.0
		c.scale = Vector2(from_scale, from_scale)
		var tw := create_tween()
		tw.bind_node(c)
		tw.tween_interval(float(i) * step)
		tw.tween_property(c, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_SINE)
		tw.parallel().tween_property(c, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		i += 1

func message_in(node: Control, step: float = 0.0) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.pivot_offset = node.size * 0.5
	node.modulate.a = 0.0
	node.scale = Vector2(0.985, 0.985)
	var tw := create_tween()
	tw.bind_node(node)
	tw.tween_interval(step)
	tw.tween_property(node, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(node, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func money_count(label: Label, target: int, duration: float = 0.9, prefix: String = "¥ ") -> Tween:
	if label == null or not is_instance_valid(label):
		return null
	var cb := func(v: float) -> void:
		if is_instance_valid(label):
			label.text = prefix + UI.fmt_money(int(round(v)))
	var tw := create_tween()
	tw.bind_node(label)
	tw.tween_method(cb, 0.0, float(target), duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tw

func number_count(label: Label, target: int, duration: float = 0.8, prefix: String = "", suffix: String = "") -> void:
	if label == null or not is_instance_valid(label):
		return
	var cb := func(v: float) -> void:
		if is_instance_valid(label):
			label.text = prefix + str(int(round(v))) + suffix
	var tw := create_tween()
	tw.bind_node(label)
	tw.tween_method(cb, 0.0, float(target), duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func stamp(parent: Control, text: String, color: Color, position: Vector2, font_size: int = 28) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var l := UI.mk_label(text, font_size, color, {"bold": true, "mono": true})
	l.position = position
	l.modulate.a = 0.0
	l.pivot_offset = Vector2(140, 24)
	parent.add_child(l)
	var tw := create_tween()
	tw.bind_node(l)
	tw.tween_property(l, "modulate:a", 1.0, 0.08)
	tw.parallel().tween_property(l, "scale", Vector2(1.06, 1.06), 0.12).set_trans(Tween.TRANS_BACK)
	tw.tween_property(l, "scale", Vector2.ONE, 0.15)
	tw.tween_interval(0.55)
	tw.tween_property(l, "modulate:a", 0.0, 0.35)
	tw.tween_callback(l.queue_free)

