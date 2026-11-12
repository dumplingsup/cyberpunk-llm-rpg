extends Node
## Shared visual language: fonts, palette, theme, widget factories.

const C_BG := Color("#05080d")
const C_BG2 := Color("#080e16")
const C_PANEL := Color(0.024, 0.039, 0.055, 0.94)
const C_PANEL_SOFT := Color(0.031, 0.051, 0.068, 0.82)
const C_PANEL_HI := Color(0.043, 0.075, 0.094, 0.96)
const C_BORDER := Color(0.067, 0.180, 0.220, 0.95)
const C_BORDER_DIM := Color(0.055, 0.110, 0.135, 0.9)
const C_CYAN := Color("#46f0ff")
const C_CYAN_DIM := Color("#1f8fa0")
const C_MAGENTA := Color("#ff2f78")
const C_AMBER := Color("#ffb454")
const C_GREEN := Color("#63ffb4")
const C_GREEN_DIM := Color("#2f9c74")
const C_MAGENTA_DIM := Color("#a02050")
const C_RED := Color("#ff5f5f")
const C_TEXT := Color("#d6eaef")
const C_MUTED := Color("#7896a0")
const C_DIM := Color("#45626d")
const C_BLACK := Color("#03060a")

var city_texture: Texture2D
var fixer_texture: Texture2D
var operation_texture: Texture2D
var mercenary_atlas: Texture2D
var font_ui: FontFile
var font_mono: Font
var font_bold: FontVariation
var font_mono_bold: FontVariation
var theme: Theme

func _ready() -> void:
	_load_fonts()
	_load_art()
	_build_theme()

func _load_fonts() -> void:
	font_ui = FontFile.new()
	font_ui.data = FileAccess.get_file_as_bytes("res://assets/fonts/NotoSansSC-VF.ttf")
	font_ui.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font_ui.hinting = TextServer.HINTING_LIGHT
	# Use the OS monospace font instead of bundling Consolas, which is not
	# redistributable. Windows resolves Consolas; other platforms fall back.
	var system_mono := SystemFont.new()
	system_mono.font_names = PackedStringArray([
		"Consolas", "Menlo", "DejaVu Sans Mono", "Liberation Mono", "monospace",
	])
	font_mono = system_mono
	font_bold = FontVariation.new()
	font_bold.base_font = font_ui
	font_bold.variation_embolden = 0.55
	font_mono_bold = FontVariation.new()
	font_mono_bold.base_font = font_mono
	font_mono_bold.variation_embolden = 0.35

func _load_art() -> void:
	city_texture = _texture_from_png("res://assets/generated/neon-city-background.png")
	fixer_texture = _texture_from_png("res://assets/generated/fixer-mirage-portrait.png")
	operation_texture = _texture_from_png("res://assets/generated/neon-operation-scene.png")
	mercenary_atlas = _texture_from_png("res://assets/generated/mercenary-portrait-atlas.png")
	print("[art] city=", city_texture != null, " fixer=", fixer_texture != null, " operation=", operation_texture != null, " mercs=", mercenary_atlas != null)

func _texture_from_png(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		push_warning("缺少美术资源: " + path)
		return null
	var img := Image.new()
	var err := img.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	if err != OK:
		push_warning("无法解码 PNG: %s (%s)" % [path, error_string(err)])
		return null
	return ImageTexture.create_from_image(img)

func mk_portrait(size: Vector2 = Vector2(112, 134), tint: Color = C_CYAN, idle: bool = true) -> Control:
	var p := preload("res://scripts/ui/Portrait.gd").new()
	p.portrait_size = size
	p.custom_minimum_size = size
	p.tint_color = tint
	p.idle = idle
	p.portrait_texture = fixer_texture
	return p

const MERC_ROLE_PORTRAIT := {"潜入": 0, "重装": 1, "技术": 1, "交涉": 2, "撤离": 3}

func merc_role_color(role: String) -> Color:
	match role:
		"重装":
			return C_RED
		"技术":
			return C_AMBER
		"交涉":
			return C_MAGENTA
		"撤离":
			return C_GREEN
	return C_CYAN

func merc_portrait_index(crew: Dictionary) -> int:
	if crew.has("portrait_index"):
		return clampi(int(crew.get("portrait_index", 0)), 0, 3)
	var role := str(crew.get("role", ""))
	if MERC_ROLE_PORTRAIT.has(role):
		return int(MERC_ROLE_PORTRAIT[role])
	var key := str(crew.get("handle", "")) + str(crew.get("name", ""))
	return absi(key.hash()) % 4

func mk_merc_portrait(crew: Dictionary, display_size: Vector2 = Vector2(96, 96), compact: bool = false) -> Control:
	if mercenary_atlas == null:
		var fallback := mk_sigil(str(crew.get("name", "?")).substr(0, 1), merc_role_color(str(crew.get("role", ""))), display_size.y)
		return fallback
	var cell := float(mercenary_atlas.get_width()) / 2.0
	var idx := merc_portrait_index(crew)
	var at := AtlasTexture.new()
	at.atlas = mercenary_atlas
	at.region = Rect2(float(idx % 2) * cell, float(int(idx / 2.0)) * cell, cell, cell)
	at.filter_clip = true
	var p = preload("res://scripts/ui/MercPortrait.gd").new()
	p.texture = at
	p.portrait_size = display_size
	p.compact = compact
	p.tint = merc_role_color(str(crew.get("role", "")))
	p.custom_minimum_size = display_size
	return p

func _build_theme() -> void:
	theme = Theme.new()
	theme.default_font = font_ui
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", C_TEXT)
	theme.set_color("default_color", "RichTextLabel", C_TEXT)
	theme.set_font("normal_font", "RichTextLabel", font_ui)
	theme.set_font("bold_font", "RichTextLabel", font_bold)
	theme.set_font("mono_font", "RichTextLabel", font_mono)
	theme.set_font_size("normal_font_size", "RichTextLabel", 16)
	theme.set_font_size("bold_font_size", "RichTextLabel", 16)
	theme.set_stylebox("panel", "PanelContainer", panel_style(C_PANEL, C_BORDER_DIM))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", C_TEXT)
	theme.set_color("font_hover_color", "Button", C_CYAN)
	theme.set_color("font_pressed_color", "Button", C_CYAN)
	theme.set_color("font_disabled_color", "Button", C_DIM)
	theme.set_font("font", "Button", font_ui)
	theme.set_font_size("font_size", "Button", 15)
	theme.set_stylebox("normal", "Button", button_style("default", false))
	theme.set_stylebox("hover", "Button", button_style("default", true))
	theme.set_stylebox("pressed", "Button", button_style("default", true, true))
	theme.set_stylebox("disabled", "Button", button_style("disabled", false))
	theme.set_stylebox("normal", "LineEdit", style_bg(Color(0.016, 0.035, 0.047, 0.95), C_BORDER, 1, 10, 2))
	theme.set_stylebox("focus", "LineEdit", style_bg(Color(0.02, 0.05, 0.065, 0.98), C_CYAN_DIM, 1, 10, 2))
	theme.set_stylebox("read_only", "LineEdit", style_bg(Color(0.02, 0.03, 0.04, 0.9), C_BORDER_DIM, 1, 10, 2))
	theme.set_color("font_color", "LineEdit", C_TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", C_DIM)
	theme.set_color("caret_color", "LineEdit", C_CYAN)
	theme.set_color("selection_color", "LineEdit", Color(0.1, 0.55, 0.65, 0.35))
	theme.set_font("font", "LineEdit", font_ui)
	theme.set_font_size("font_size", "LineEdit", 16)
	theme.set_stylebox("panel", "PopupPanel", style_bg(C_PANEL_HI, C_BORDER, 1, 6))
	theme.set_color("font_color", "PopupMenu", C_TEXT)
	theme.set_color("font_hover_color", "PopupMenu", C_CYAN)
	theme.set_stylebox("panel", "PopupMenu", style_bg(C_PANEL_HI, C_BORDER, 1, 4))
	theme.set_stylebox("hover", "PopupMenu", style_bg(Color(0.05, 0.14, 0.18, 1), C_CYAN_DIM, 1, 2))
	theme.set_font("font", "PopupMenu", font_ui)
	theme.set_font_size("font_size", "PopupMenu", 15)
	theme.set_stylebox("background", "ProgressBar", style_bg(Color(0.03, 0.06, 0.08, 0.8), C_BORDER_DIM, 0, 0, 0))
	theme.set_stylebox("fill", "ProgressBar", style_bg(C_CYAN_DIM, C_CYAN_DIM, 0, 0, 0))
	theme.set_color("font_color", "ProgressBar", C_CYAN)
	theme.set_font("font", "ProgressBar", font_mono)
	theme.set_font_size("font_size", "ProgressBar", 12)
	theme.set_stylebox("panel", "TooltipPanel", style_bg(Color(0.02, 0.04, 0.055, 0.98), C_CYAN_DIM, 1, 4))
	theme.set_color("font_color", "TooltipLabel", C_TEXT)
	theme.set_font("font", "TooltipLabel", font_ui)
	theme.set_font_size("font_size", "TooltipLabel", 13)
	theme.set_stylebox("grabber", "VScrollBar", style_bg(Color(0.1, 0.35, 0.42, 0.7), C_BORDER_DIM, 0, 0, 0))
	theme.set_stylebox("grabber_highlight", "VScrollBar", style_bg(C_CYAN_DIM, C_CYAN_DIM, 0, 0, 0))
	theme.set_stylebox("grabber_pressed", "VScrollBar", style_bg(C_CYAN, C_CYAN, 0, 0, 0))

func style_bg(bg: Color, border: Color, border_w: int = 1, margin: int = 12, radius: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin
	sb.content_margin_bottom = margin
	return sb

func panel_style(bg: Color = C_PANEL, border: Color = C_BORDER_DIM, margin: int = 14, radius: int = 2) -> StyleBoxFlat:
	var sb := style_bg(bg, border, 1, margin, radius)
	return sb

func button_style(kind: String, hover: bool, pressed: bool = false) -> StyleBoxFlat:
	var bg := Color(0.024, 0.055, 0.070, 0.95)
	var border := C_BORDER
	var fg := 1
	match kind:
		"primary":
			bg = Color(0.02, 0.10, 0.125, 0.95)
			border = C_CYAN_DIM
			if hover:
				bg = Color(0.03, 0.16, 0.195, 1)
				border = C_CYAN
		"danger":
			bg = Color(0.075, 0.02, 0.045, 0.95)
			border = Color(0.35, 0.08, 0.17, 1)
			if hover:
				bg = Color(0.14, 0.03, 0.08, 1)
				border = C_MAGENTA
		"ghost":
			bg = Color(0, 0, 0, 0)
			border = Color(0, 0, 0, 0)
			if hover:
				bg = Color(0.04, 0.10, 0.12, 0.55)
				border = C_BORDER_DIM
		"disabled":
			bg = Color(0.02, 0.03, 0.04, 0.7)
			border = C_BORDER_DIM
		_:
			if hover:
				bg = Color(0.035, 0.105, 0.13, 1)
				border = C_CYAN_DIM
	if pressed:
		bg = Color(0.06, 0.18, 0.21, 1)
		border = C_CYAN
	var sb := style_bg(bg, border, 1, 12, 2)
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	return sb

func mk_label(text: String, size: int = 16, color: Color = C_TEXT, opts: Dictionary = {}) -> Label:
	var l := Label.new()
	l.text = text
	var font: Font = font_ui
	if opts.get("mono", false):
		font = font_mono
	if opts.get("bold", false):
		font = font_mono_bold if opts.get("mono", false) else font_bold
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if opts.get("wrap", false):
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if opts.has("width"):
		l.custom_minimum_size.x = float(opts.width)
	if opts.has("align"):
		l.horizontal_alignment = int(opts.align)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func mk_kicker(text: String, color: Color = C_MUTED) -> Label:
	return mk_label(text, 11, color, {"mono": true})

func mk_panel(bg: Color = C_PANEL, border: Color = C_BORDER_DIM, opts: Dictionary = {}) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := style_bg(bg, border, int(opts.get("border_w", 1)), int(opts.get("margin", 14)), int(opts.get("radius", 2)))
	p.add_theme_stylebox_override("panel", sb)
	if opts.has("min_width"):
		p.custom_minimum_size.x = float(opts.min_width)
	if opts.has("min_height"):
		p.custom_minimum_size.y = float(opts.min_height)
	return p

func mk_button(text: String, kind: String = "default", min_width: float = 0.0, min_height: float = 40.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(min_width, min_height)
	b.add_theme_font_override("font", font_ui)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_stylebox_override("normal", button_style(kind, false))
	b.add_theme_stylebox_override("hover", button_style(kind, true))
	b.add_theme_stylebox_override("pressed", button_style(kind, true, true))
	b.add_theme_stylebox_override("disabled", button_style("disabled", false))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if kind == "primary":
		b.add_theme_color_override("font_color", C_CYAN)
		b.add_theme_color_override("font_pressed_color", C_CYAN)
	elif kind == "danger":
		b.add_theme_color_override("font_color", C_MAGENTA)
		b.add_theme_color_override("font_pressed_color", C_MAGENTA)
	elif kind == "ghost":
		b.add_theme_color_override("font_color", C_MUTED)
	b.add_theme_color_override("font_hover_color", C_CYAN)
	b.add_theme_color_override("font_focus_color", C_CYAN)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if Sfx != null:
		b.mouse_entered.connect(func(): Sfx.play("hover"))
		b.pressed.connect(func(): Sfx.play("click"))
	b.mouse_entered.connect(func(): _hover_button(b, true))
	b.mouse_exited.connect(func(): _hover_button(b, false))
	return b

func _hover_button(b: Button, on: bool) -> void:
	if not is_instance_valid(b) or b.disabled:
		return
	b.pivot_offset = b.size * 0.5
	var prev = b.get_meta("hover_tween", null)
	if prev is Tween and prev.is_valid():
		prev.kill()
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector2(1.022, 1.022) if on else Vector2.ONE, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	b.set_meta("hover_tween", tw)

func mk_stat(caption: String, value: String, color: Color = C_CYAN, min_width: float = 0.0) -> PanelContainer:
	var p := mk_panel(Color(0.012, 0.024, 0.033, 0.92), C_BORDER_DIM, {"margin": 8, "radius": 2})
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	h.add_child(mk_label(caption, 10, C_DIM, {"mono": true}))
	var v := mk_label(value, 16, color, {"mono": true, "bold": true})
	h.add_child(v)
	p.set_meta("value", v)
	p.set_meta("caption", h.get_child(0))
	if min_width > 0:
		p.custom_minimum_size.x = min_width
	return p

func mk_tag(text: String, color: Color = C_CYAN) -> PanelContainer:
	var p := mk_panel(Color(color.r * 0.10, color.g * 0.10, color.b * 0.10, 0.85), Color(color.r, color.g, color.b, 0.35), {"margin": 5, "radius": 1})
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(mk_label(text, 11, color, {"mono": true}))
	return p

func mk_sigil(text: String, color: Color = C_CYAN, sigil_size: float = 34.0) -> PanelContainer:
	var p := mk_panel(Color(color.r * 0.10, color.g * 0.10, color.b * 0.10, 0.9), Color(color.r, color.g, color.b, 0.45), {"margin": 0, "radius": 1})
	p.custom_minimum_size = Vector2(sigil_size, sigil_size)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := mk_label(text, int(sigil_size * 0.46), color, {"bold": true, "align": HORIZONTAL_ALIGNMENT_CENTER})
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(sigil_size, sigil_size)
	p.add_child(l)
	return p

func mk_hline(color: Color = C_BORDER_DIM, height: int = 1) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size.y = height
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func mk_vline(color: Color = C_BORDER_DIM, width: int = 1) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size.x = width
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func mk_scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return s

func mk_spacer(height: float = 0.0, expand: bool = false) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if height > 0:
		c.custom_minimum_size.y = height
	if expand:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

func mk_meter(value: float, max_value: float, color: Color, width: float = 120.0, segments: int = 10) -> Control:
	var m := preload("res://scripts/ui/Meter.gd").new()
	m.value = value
	m.max_value = max_value
	m.fill_color = color
	m.segments = segments
	m.custom_minimum_size = Vector2(width, 8)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return m

func mk_dot(color: Color, size: int = 7) -> PanelContainer:
	var sb := style_bg(color, color, 0, 0, 99)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(size, size)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

func mk_rich(size: int = 16, color: Color = C_TEXT) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = false
	r.scroll_active = true
	r.scroll_following = true
	r.selection_enabled = true
	r.add_theme_font_override("normal_font", font_ui)
	r.add_theme_font_override("bold_font", font_bold)
	r.add_theme_font_override("mono_font", font_mono)
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_font_size_override("mono_font_size", size)
	r.add_theme_color_override("default_color", color)
	return r

func fmt_money(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out

func risk_color(risk: String) -> Color:
	match risk:
		"低":
			return C_GREEN
		"高":
			return C_RED
		_:
			return C_AMBER

func risk_index(risk: String) -> int:
	match risk:
		"低":
			return 1
		"高":
			return 3
		_:
			return 2







