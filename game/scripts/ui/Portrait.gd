extends Control
## Holographic portrait plate: white-background keying, scanlines, flicker, breathing.

var portrait_texture: Texture2D
var tint_color: Color = Color(0.42, 0.92, 1.0, 1.0)
var portrait_size: Vector2 = Vector2(112, 134)
var idle: bool = true

var _texture_rect: TextureRect
var _material: ShaderMaterial
var _corners = null
var _built := false

const PORTRAIT_SHADER := """
shader_type canvas_item;
uniform vec3 tint = vec3(0.42, 0.92, 1.0);
uniform float scan_strength = 0.055;
uniform float glitch_strength = 1.0;

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	// rare horizontal tear
	float tear = step(0.992, fract(sin(floor(t * 1.7) * 12.9898) * 43758.5453));
	uv.x += tear * 0.006 * glitch_strength * sin(t * 40.0);
	vec4 src = texture(TEXTURE, uv);
	float mn = min(src.r, min(src.g, src.b));
	float mx = max(src.r, max(src.g, src.b));
	float white = smoothstep(0.90, 0.985, mn) * smoothstep(0.95, 0.995, mx);
	float a = (1.0 - white) * src.a;
	vec3 col = src.rgb;
	col = mix(col, tint * (0.30 + 0.72 * col), 0.52);
	float scan = 0.5 + 0.5 * sin(UV.y * 520.0 - t * 3.4);
	col += tint * scan * scan_strength;
	float flick = 0.93 + 0.07 * sin(t * 19.0) * sin(t * 5.3);
	col *= flick;
	float breathe = 0.94 + 0.06 * sin(t * 1.25);
	col *= breathe;
	float edge = smoothstep(0.0, 0.035, UV.x) * smoothstep(1.0, 0.965, UV.x)
		* smoothstep(0.0, 0.025, UV.y) * smoothstep(1.0, 0.975, UV.y);
	COLOR = vec4(col, a * edge * 0.97);
}
"""

func _ready() -> void:
	custom_minimum_size = portrait_size
	clip_contents = true
	_build()
	resized.connect(_on_resized)
	_on_resized()
	if idle:
		_start_idle()

func _build() -> void:
	if _built:
		return
	_built = true
	if portrait_texture == null:
		portrait_texture = UI.fixer_texture
	var frame := PanelContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", UI.style_bg(Color(0.008, 0.022, 0.030, 0.96), Color(0.20, 0.78, 0.90, 0.55), 1, 3, 1))
	add_child(frame)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 3)
	margin.add_theme_constant_override("margin_right", 3)
	margin.add_theme_constant_override("margin_top", 3)
	margin.add_theme_constant_override("margin_bottom", 3)
	frame.add_child(margin)
	_texture_rect = TextureRect.new()
	_texture_rect.texture = portrait_texture
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_material = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = PORTRAIT_SHADER
	_material.shader = sh
	_material.set_shader_parameter("tint", Vector3(tint_color.r, tint_color.g, tint_color.b))
	_texture_rect.material = _material
	margin.add_child(_texture_rect)
	_corners = preload("res://scripts/ui/FrameCorners.gd").new()
	_corners.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_corners.color = Color(tint_color.r, tint_color.g, tint_color.b, 0.72)
	_corners.inset = 4.0
	_corners.length = 9.0
	add_child(_corners)

func _on_resized() -> void:
	pivot_offset = size * 0.5

func _start_idle() -> void:
	var tw := create_tween().set_loops()
	tw.tween_property(self, "scale", Vector2(1.012, 1.012), 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var tw2 := create_tween().set_loops()
	tw2.tween_property(self, "modulate:a", 0.86, 0.9).set_trans(Tween.TRANS_SINE)
	tw2.tween_property(self, "modulate:a", 1.0, 2.9).set_trans(Tween.TRANS_SINE)
	tw2.tween_property(self, "modulate:a", 0.93, 0.6).set_trans(Tween.TRANS_SINE)
	tw2.tween_property(self, "modulate:a", 1.0, 2.2).set_trans(Tween.TRANS_SINE)

