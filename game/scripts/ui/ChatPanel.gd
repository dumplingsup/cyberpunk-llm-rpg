extends Control
## Encrypted comms overlay. Streams in-character dialogue and applies its markers.

var main = null
var kind := "fixer"
var actor_id := ""
var actor: Dictionary = {}
var msg_box: VBoxContainer
var scroll: ScrollContainer
var input_line: LineEdit
var typing_label: Label
var send_button: Button
var current_id := ""
var current_body: RichTextLabel = null
var awaiting := false
var _panel_ref: Control = null
var _typing_t := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if kind == "crew":
		actor = GS.crew_by_id(actor_id)
	_build()
	Bridge.task_delta.connect(_on_delta)
	Bridge.task_finished.connect(_on_finished)
	_intro()
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.18)
	if _panel_ref != null:
		_panel_ref.pivot_offset = _panel_ref.size * 0.5
		_panel_ref.scale = Vector2(0.985, 0.985)
		var pt := create_tween()
		pt.tween_property(_panel_ref, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.004, 0.007, 0.012, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -586.0
	panel.offset_right = -18.0
	panel.offset_top = 18.0
	panel.offset_bottom = -18.0
	panel.add_theme_stylebox_override("panel", UI.panel_style(Color(0.012, 0.026, 0.036, 0.985), UI.C_CYAN_DIM, 16, 2))
	_panel_ref = panel
	add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	if kind == "fixer":
		head.add_child(UI.mk_portrait(Vector2(84, 102), UI.C_CYAN))
	else:
		var portrait := UI.mk_panel(Color(0.03, 0.08, 0.10, 0.95), UI.C_CYAN_DIM, {"margin": 0, "min_width": 44, "min_height": 44})
		portrait.custom_minimum_size = Vector2(44, 44)
		var initial := UI.mk_label(_initials(), 18, UI.C_CYAN, {"bold": true, "align": HORIZONTAL_ALIGNMENT_CENTER})
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		portrait.add_child(initial)
		head.add_child(portrait)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	head.add_child(tv)
	tv.add_child(UI.mk_label(_display_name(), 17, UI.C_TEXT, {"bold": true}))
	tv.add_child(UI.mk_label(_subtitle(), 10, UI.C_CYAN_DIM, {"mono": true}))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(sp)
	var close := UI.mk_button("✕", "ghost", 40, 32)
	close.add_theme_font_size_override("font_size", 16)
	close.pressed.connect(func(): queue_free())
	head.add_child(close)

	var context := HBoxContainer.new()
	context.add_theme_constant_override("separation", 10)
	v.add_child(context)
	context.add_child(UI.mk_label(_context_text(), 10, UI.C_MUTED, {"mono": true}))
	var csp := Control.new()
	csp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	csp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	context.add_child(csp)
	context.add_child(UI.mk_label("ENCRYPTED / 链路加密", 10, UI.C_GREEN_DIM, {"mono": true}))
	v.add_child(UI.mk_hline(UI.C_BORDER_DIM))

	scroll = UI.mk_scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	msg_box = VBoxContainer.new()
	msg_box.add_theme_constant_override("separation", 10)
	msg_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(msg_box)

	typing_label = UI.mk_label("▍对方正在说话……", 10, UI.C_AMBER, {"mono": true})
	typing_label.visible = false
	v.add_child(typing_label)

	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 4)
	v.add_child(chips)
	for chip in _chips():
		var b := UI.mk_button(chip, "default", 0, 28)
		b.add_theme_font_size_override("font_size", 10)
		b.add_theme_color_override("font_color", UI.C_CYAN_DIM)
		b.pressed.connect(func(): _quick(chip))
		chips.add_child(b)

	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 6)
	v.add_child(input_row)
	input_line = LineEdit.new()
	input_line.placeholder_text = "输入你要说的话……"
	input_line.max_length = 300
	input_line.custom_minimum_size.y = 42
	input_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_line.text_submitted.connect(func(_t: String): _send())
	input_row.add_child(input_line)
	send_button = UI.mk_button("发送", "primary", 88, 42)
	send_button.pressed.connect(_send)
	input_row.add_child(send_button)

func _initials() -> String:
	if kind == "fixer":
		return "蜃"
	return str(actor.get("name", "?")).substr(0, 1)

func _display_name() -> String:
	if kind == "fixer":
		return "蜃楼 MIRAGE-7"
	return str(actor.get("name", "未知"))

func _subtitle() -> String:
	if kind == "fixer":
		return "中间人 · 只以加密语音出现"
	return "%s · %s · %s" % [str(actor.get("handle", "")), str(actor.get("role", "")), str(actor.get("origin", ""))]

func _context_text() -> String:
	if kind == "fixer":
		if GS.active_contract == null and GS.negotiating_contract != null:
			return "TRUST %d/100 · NEGOTIATING「%s」" % [GS.fixer_trust, str(GS.negotiating_contract.get("codename", ""))]
		return "TRUST %d/100" % GS.fixer_trust
	return "LOYALTY %d/100 · INJURY %d/%d · CUT ¥%s" % [
		int(actor.get("loyalty", 50)), int(actor.get("injury", 0)), GS.MAX_INJURY, UI.fmt_money(int(actor.get("price", 0))),
	]

func _intro() -> void:
	if kind == "fixer":
		push_system("频道已加密。当前对蜃楼信任 %d/100。" % GS.fixer_trust)
		_add_npc_bubble("蜃楼", "说。我这边还有三单在排队，别浪费我的加密带宽。", UI.C_MAGENTA)
	else:
		push_system("加密语音已接通。背景里有雨声和机器的低鸣。")
		var line := "频道通了。"
		if str(actor.get("voice", "")) != "":
			line = "频道通了。%s" % str(actor.get("voice", ""))
		_add_npc_bubble(str(actor.get("name", "佣兵")), line, UI.C_CYAN)

func _chips() -> Array:
	if kind == "fixer":
		return ["这单有什么内幕？", "报酬再加一点。", "最近城里有什么风声？"]
	return ["这单你怎么看？", "分成可以谈吗？", "行动时听我指挥。"]

func debug_send(text: String) -> void:
	input_line.text = text
	_send()

func _quick(text: String) -> void:
	if awaiting:
		return
	input_line.text = text
	_send()

func _send() -> void:
	var text := input_line.text.strip_edges()
	if text == "" or awaiting:
		return
	input_line.text = ""
	_add_player_bubble(text)
	awaiting = true
	current_body = _add_npc_bubble(_display_name(), "", ui_color())
	typing_label.visible = true
	var chat_state := GS.state_for_bridge()
	if chat_state.get("contract", null) == null and GS.negotiating_contract != null:
		chat_state["contract"] = GS.negotiating_contract
	var payload := {"state": chat_state, "message": text}
	var actor_payload := {"kind": kind, "id": actor_id, "persona": actor}
	current_id = Bridge.ask_now("dialogue", payload, {"stream": true, "actor": actor_payload})
	_scroll_bottom()

func _on_delta(id: String, text: String) -> void:
	if id != current_id or current_body == null or text == "":
		return
	typing_label.visible = false
	current_body.add_text(text)
	_scroll_bottom()

func _on_finished(id: String, msg: Dictionary) -> void:
	if id != current_id:
		return
	awaiting = false
	typing_label.visible = false
	if str(msg.get("type", "")) == "error" or not bool(msg.get("ok", false)):
		push_system("链路错误：%s" % str(msg.get("message", "无响应")), UI.C_RED)
		current_id = ""
		current_body = null
		return
	var text := str(msg.get("text", ""))
	if current_body != null:
		current_body.clear()
		current_body.add_text(text)
	var markers: Dictionary = msg.get("markers", {})
	var applied := GS.apply_dialogue_markers(markers, kind, actor_id)
	for a in applied:
		push_system("· %s" % str(a), UI.C_GREEN)
	if bool(msg.get("degraded", false)):
		push_system("本地叙事引擎接管了这次回复。", UI.C_AMBER)
	main._refresh_header()
	if main.current_nav in ["crew", "inbox", "plan"]:
		main.refresh_current()
	if kind == "crew":
		actor = GS.crew_by_id(actor_id)
	var quick := ""
	match kind:
		"fixer":
			quick = "频道安静了两秒。蜃楼在等你的下一句。"
		_:
			quick = "对方没有挂断。"
	push_system(quick)
	current_id = ""
	current_body = null
	_scroll_bottom()

func _add_player_bubble(text: String) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sp)
	var p := UI.mk_panel(Color(0.02, 0.055, 0.07, 0.95), UI.C_CYAN_DIM, {"margin": 10})
	p.custom_minimum_size.x = 300
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var who := UI.mk_label("%s / 你" % str(GS.player.get("handle", "GHOST")), 9, UI.C_CYAN_DIM, {"mono": true, "align": HORIZONTAL_ALIGNMENT_RIGHT})
	v.add_child(who)
	var body := UI.mk_label(text, 13, UI.C_TEXT, {"wrap": true, "width": 350, "align": HORIZONTAL_ALIGNMENT_RIGHT})
	v.add_child(body)
	row.add_child(p)
	msg_box.add_child(row)
	FX.message_in(row)
	_scroll_bottom()

func _add_npc_bubble(speaker: String, text: String, color: Color) -> RichTextLabel:
	var p := UI.mk_panel(Color(0.014, 0.032, 0.044, 0.96), Color(color.r, color.g, color.b, 0.35), {"margin": 10})
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.custom_minimum_size.x = 380
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	v.add_child(UI.mk_label(speaker, 9, color, {"mono": true}))
	var body := UI.mk_rich(13, UI.C_TEXT)
	body.fit_content = true
	body.scroll_active = false
	body.custom_minimum_size = Vector2(360, 0)
	body.add_text(text)
	v.add_child(body)
	msg_box.add_child(p)
	FX.message_in(p)
	_scroll_bottom()
	return body

func push_system(text: String, color: Color = UI.C_DIM) -> void:
	var l := UI.mk_label("// " + text, 10, color, {"mono": true, "wrap": true, "width": 500})
	msg_box.add_child(l)
	_scroll_bottom()

func push_npc(text: String) -> void:
	var body := _add_npc_bubble(_display_name(), text, ui_color())
	body.add_text("")
	_scroll_bottom()

func set_typing(on: bool) -> void:
	typing_label.visible = on

func ui_color() -> Color:
	return UI.C_MAGENTA if kind == "fixer" else UI.C_CYAN

func _process(delta: float) -> void:
	if typing_label != null and typing_label.visible:
		_typing_t += delta
		typing_label.text = "▍对方正在说话" + ".".repeat(1 + int(_typing_t * 3.0) % 3)

func _scroll_bottom() -> void:
	await get_tree().process_frame
	if scroll != null:
		var bar := scroll.get_v_scroll_bar()
		if bar != null:
			scroll.scroll_vertical = int(bar.max_value)






