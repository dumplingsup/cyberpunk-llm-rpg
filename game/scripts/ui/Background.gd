extends Control
## Rain-night city backdrop. The generated art is graded and animated in a shader;
## mouse parallax and a slow drift keep the workbench alive without touching input.

var _rect: TextureRect
var _material: ShaderMaterial
var _parallax := Vector2.ZERO
var _t := 0.0
var _last := 0.0

const CITY_SHADER := """
shader_type canvas_item;
uniform vec2 parallax = vec2(0.0);
uniform float zoom = 1.045;
uniform float darken = 0.66;
uniform float rain_strength = 0.055;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = (UV - 0.5) / zoom + 0.5 + parallax;
	vec3 col = texture(TEXTURE, clamp(uv, vec2(0.001), vec2(0.999))).rgb;
	// cool neon grade + darken so panels and text always win
	col = pow(col, vec3(0.94, 1.01, 1.06));
	col *= darken;
	// keep the city readable behind the center but fade the extreme edges
	col *= 0.80 + 0.20 * smoothstep(0.0, 0.30, UV.y);
	col *= 0.78 + 0.22 * smoothstep(1.0, 0.68, UV.y);
	// rain streaks
	float lane = floor(UV.x * 190.0);
	float fall = fract(UV.y * 0.55 - TIME * (0.16 + hash(vec2(lane, 3.0)) * 0.18));
	float streak = smoothstep(0.86, 1.0, fall) * step(0.55, hash(vec2(lane, 7.0)));
	col += vec3(0.26, 0.62, 0.78) * streak * rain_strength;
	// second, slower sheet of rain
	float lane2 = floor(UV.x * 78.0 + 17.0);
	float fall2 = fract(UV.y * 0.30 - TIME * (0.08 + hash(vec2(lane2, 9.0)) * 0.08));
	col += vec3(0.18, 0.45, 0.60) * smoothstep(0.94, 1.0, fall2) * rain_strength * 0.9;
	// scanline CRT + vignette
	col *= 0.955 + 0.045 * sin(UV.y * 1400.0 + TIME * 0.5);
	vec2 d = UV - 0.5;
	col *= smoothstep(1.12, 0.34, length(d));
	// faint moving data sweep
	float sweep = 1.0 - smoothstep(0.0, 0.002, abs(UV.y - fract(TIME * 0.035)));
	col += vec3(0.08, 0.40, 0.48) * sweep * 0.035;
	COLOR = vec4(col, 1.0);
}
"""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fallback := ColorRect.new()
	fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fallback.color = Color(0.006, 0.012, 0.02, 1.0)
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fallback)
	if UI.city_texture == null:
		return
	_rect = TextureRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.texture = UI.city_texture
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_material = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = CITY_SHADER
	_material.shader = sh
	_rect.material = _material
	add_child(_rect)
	set_process(true)

func _process(delta: float) -> void:
	_t += delta
	_last += delta
	if _material == null:
		return
	var vp := get_viewport_rect().size
	if vp.x > 1.0 and vp.y > 1.0:
		var mp := get_viewport().get_mouse_position() / vp - Vector2(0.5, 0.5)
		mp = Vector2(clampf(mp.x, -0.5, 0.5), clampf(mp.y, -0.5, 0.5))
		_parallax = _parallax.lerp(mp * Vector2(0.020, 0.014), clampf(delta * 1.8, 0.0, 1.0))
		_material.set_shader_parameter("parallax", _parallax)
		_material.set_shader_parameter("zoom", 1.045 + sin(_t * 0.09) * 0.006)
