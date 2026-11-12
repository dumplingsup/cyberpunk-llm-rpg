extends Control
## Cracked cell from the 2x2 mercenary atlas: subtle holographic idle, no white keying.

var texture: Texture2D
var portrait_size: Vector2 = Vector2(96, 96)
var compact: bool = false
var tint: Color = Color(0.45, 0.92, 1.0, 1.0)

var _texture_rect: TextureRect
var _material: ShaderMaterial
var _built := false

const MERC_SHADER := """
shader_type canvas_item;
uniform vec3 tint = vec3(0.45, 0.92, 1.0);

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	vec3 col = src.rgb;
	// barely-there cyan hologram grade, keeps skin and costumes readable
	col = mix(col, tint * (0.35 + 0.65 * col), 0.10);
	float scan = 0.5 + 0.5 * sin(UV.y * 460.0 - TIME * 2.6);
	col += tint * scan * 0.035;
	float flick = 0.95 + 0.05 * sin(TIME * 17.0 + sin(TIME * 3.1));
	col *= flick;
	// silhouette rim glow from the alpha edge
	float a_right = texture(TEXTURE, UV + vec2(0.006, 0.0)).a;
	float rim = abs(src.a - a_right);
	col += tint * rim * 0.42;
	float edge = smoothstep(0.0, 0.035, UV.x) * smoothstep(1.0, 0.965, UV.x)
		* smoothstep(0.0, 0.03, UV.y) * smoothstep(1.0, 0.97, UV.y);
	COLOR = vec4(col, src.a * edge * 0.98);
}
"""

func _ready() -> void:
	custom_minimum_size = portrait_size
	clip_contents = true
	_build()
	resized.connect(_on_resized)
	_on_resized()
	if not compact:
		var tw := create_tween().set_loops()
		tw.tween_property(self, "scale", Vector2(1.010, 1.010), 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(self, "scale", Vector2.ONE, 2.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _build() -> void:
	if _built:
		return
	_built = true
	var frame := PanelContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := 2 if compact else 3
	frame.add_theme_stylebox_override("panel", UI.style_bg(Color(0.010, 0.022, 0.030, 0.96), Color(tint.r, tint.g, tint.b, 0.45 if compact else 0.60), 1, margin, 1))
	add_child(frame)
	var inner := MarginContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_constant_override("margin_left", margin)
	inner.add_theme_constant_override("margin_right", margin)
	inner.add_theme_constant_override("margin_top", margin)
	inner.add_theme_constant_override("margin_bottom", margin)
	frame.add_child(inner)
	_texture_rect = TextureRect.new()
	_texture_rect.texture = texture
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = MERC_SHADER
	_material.shader = sh
	_material.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	_texture_rect.material = _material
	inner.add_child(_texture_rect)
	if not compact:
		var corners = preload("res://scripts/ui/FrameCorners.gd").new()
		corners.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		corners.color = Color(tint.r, tint.g, tint.b, 0.65)
		corners.inset = 4.0
		corners.length = 10.0
		add_child(corners)

func _on_resized() -> void:
	pivot_offset = size * 0.5
