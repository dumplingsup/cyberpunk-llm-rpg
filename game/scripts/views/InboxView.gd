extends Control
## Contract board: pick a job, read the brief, accept or refresh.

var main = null
var selected_id := ""
var list_box: VBoxContainer
var detail_box: VBoxContainer
var refresh_button: Button
var fixer_stat: PanelContainer
var _list_sig := ""

func _ready() -> void:
	_build()
	refresh()

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	root.add_child(vb)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	vb.add_child(head)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	head.add_child(titles)
	titles.add_child(UI.mk_kicker("INBOX // 加密委托"))
	titles.add_child(UI.mk_label("委托板", 24, UI.C_TEXT, {"bold": true}))
	var sub := UI.mk_label("蜃楼把活递给你。先看价钱，再看风险，最后看谁去送命。", 12, UI.C_MUTED)
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(sub)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(spacer)
	fixer_stat = UI.mk_stat("MIRAGE TRUST", "50", UI.C_MAGENTA, 132)
	head.add_child(fixer_stat)
	var talk := UI.mk_button("联系蜃楼", "default", 120, 40)
	talk.pressed.connect(func():
		GS.negotiating_contract = null
		main.open_chat("fixer")
	)
	head.add_child(talk)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(body)

	var left := UI.mk_panel(Color(0.012, 0.024, 0.034, 0.92), UI.C_BORDER_DIM, {"margin": 12})
	left.custom_minimum_size.x = 390
	body.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	left.add_child(lv)
	var lh := HBoxContainer.new()
	lh.add_theme_constant_override("separation", 8)
	lv.add_child(lh)
	lh.add_child(UI.mk_kicker("AVAILABLE / 可接委托"))
	var grow := Control.new()
	grow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lh.add_child(grow)
	refresh_button = UI.mk_button("刷新 ¥100", "ghost", 92, 28)
	refresh_button.add_theme_font_size_override("font_size", 11)
	refresh_button.pressed.connect(_refresh_offers)
	lh.add_child(refresh_button)
	lv.add_child(UI.mk_hline(UI.C_BORDER_DIM))
	var scroll := UI.mk_scroll()
	lv.add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 8)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_box)

	var right := UI.mk_panel(Color(0.014, 0.026, 0.036, 0.94), UI.C_BORDER_DIM, {"margin": 0})
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var scroll2 := UI.mk_scroll()
	right.add_child(scroll2)
	detail_box = VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 14)
	detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 22)
	pad.add_theme_constant_override("margin_right", 22)
	pad.add_theme_constant_override("margin_top", 18)
	pad.add_theme_constant_override("margin_bottom", 18)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(detail_box)
	scroll2.add_child(pad)

func refresh() -> void:
	if fixer_stat != null:
		fixer_stat.get_meta("value").text = str(GS.fixer_trust)
	_refresh_list()
	_refresh_detail()
	main._refresh_header()

func _refresh_list() -> void:
	if list_box == null:
		return
	for ch in list_box.get_children():
		ch.queue_free()
	var open := GS.open_contracts()
	if open.is_empty():
		var empty := VBoxContainer.new()
		empty.add_theme_constant_override("separation", 8)
		var l := UI.mk_label("没有可接的委托。", 14, UI.C_MUTED)
		empty.add_child(l)
		var b := UI.mk_button("刷新委托 · ¥100", "primary", 320, 42)
		b.pressed.connect(_refresh_offers)
		empty.add_child(b)
		list_box.add_child(empty)
		refresh_button.disabled = false
		return
	var found := false
	for c in open:
		if str(c.get("id", "")) == selected_id:
			found = true
	if not found:
		selected_id = str(open[0].get("id", ""))
	refresh_button.disabled = false
	for c in open:
		list_box.add_child(_make_card(c))
	var sig := ""
	for c in open:
		sig += str(c.get("id", ""))
	if sig != _list_sig:
		_list_sig = sig
		FX.stagger(list_box, 0.045, 0.965)

func _make_card(c: Dictionary) -> Control:
	var selected := str(c.get("id", "")) == selected_id
	var bg := Color(0.03, 0.075, 0.095, 0.95) if selected else Color(0.016, 0.032, 0.044, 0.92)
	var border := UI.C_CYAN if selected else UI.C_BORDER_DIM
	var card := UI.mk_panel(bg, border, {"margin": 10})
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	var tags0: Array = c.get("tags", [])
	var glyph := str(tags0[0]).substr(0, 1) if not tags0.is_empty() else "?"
	row.add_child(UI.mk_sigil(glyph, UI.risk_color(str(c.get("risk", "中"))), 32))
	row.add_child(UI.mk_label(str(c.get("codename", "未命名")), 16, UI.C_TEXT if selected else UI.C_TEXT, {"bold": true}))
	var grow := Control.new()
	grow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(grow)
	row.add_child(UI.mk_label("¥%s" % UI.fmt_money(int(c.get("pay", 0))), 14, UI.C_AMBER, {"mono": true}))
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", 4)
	tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tags)
	for t in c.get("tags", []):
		tags.add_child(UI.mk_tag(str(t), UI.C_CYAN_DIM))
	tags.add_child(UI.mk_tag("风险 " + str(c.get("risk", "中")), UI.risk_color(str(c.get("risk", "中")))))
	var brief := UI.mk_label(str(c.get("brief", "")), 11, UI.C_MUTED, {"wrap": true, "width": 330})
	brief.max_lines_visible = 2
	brief.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(brief)
	var foot := HBoxContainer.new()
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(foot)
	foot.add_child(UI.mk_label(str(c.get("location", "")), 10, UI.C_DIM, {"mono": true}))
	var cid := str(c.get("id", ""))
	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			selected_id = cid
			Sfx.play("click")
			refresh()
	)
	card.mouse_entered.connect(func():
		if selected_id != cid:
			card.add_theme_stylebox_override("panel", UI.panel_style(Color(0.025, 0.06, 0.078, 0.95), UI.C_CYAN_DIM, 10, 2))
	)
	card.mouse_exited.connect(func():
		if selected_id != cid:
			card.add_theme_stylebox_override("panel", UI.panel_style(Color(0.016, 0.032, 0.044, 0.92), UI.C_BORDER_DIM, 10, 2))
	)
	return card

func _refresh_detail() -> void:
	if detail_box == null:
		return
	for ch in detail_box.get_children():
		ch.queue_free()
	var c = GS.contract_by_id(selected_id)
	if c == null or str(c.get("status", "open")) != "open":
		var empty := VBoxContainer.new()
		empty.add_theme_constant_override("separation", 10)
		empty.add_child(UI.mk_spacer(40))
		empty.add_child(UI.mk_kicker("NO SIGNAL / 没有选中委托"))
		empty.add_child(UI.mk_label("左边是一排加密委托。点开一份，先读清楚它要什么。", 14, UI.C_MUTED))
		detail_box.add_child(empty)
		return

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	detail_box.add_child(top)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 2)
	top.add_child(tv)
	tv.add_child(UI.mk_kicker("OPERATION / 行动代号"))
	tv.add_child(UI.mk_label(str(c.get("codename", "")), 30, UI.C_TEXT, {"bold": true}))
	var grow := Control.new()
	grow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(grow)
	var pay_box := VBoxContainer.new()
	pay_box.add_theme_constant_override("separation", 0)
	pay_box.alignment = BoxContainer.ALIGNMENT_END
	top.add_child(pay_box)
	pay_box.add_child(UI.mk_label("CONTRACT VALUE", 10, UI.C_DIM, {"mono": true, "align": HORIZONTAL_ALIGNMENT_RIGHT}))
	pay_box.add_child(UI.mk_label("¥ " + UI.fmt_money(int(c.get("pay", 0))), 26, UI.C_AMBER, {"mono": true, "bold": true, "align": HORIZONTAL_ALIGNMENT_RIGHT}))

	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", 5)
	for t in c.get("tags", []):
		tags.add_child(UI.mk_tag(str(t), UI.C_CYAN_DIM))
	tags.add_child(UI.mk_tag("风险 " + str(c.get("risk", "中")), UI.risk_color(str(c.get("risk", "中")))))
	tags.add_child(UI.mk_tag("热度 +%d" % int(c.get("heat", 1)), UI.C_MAGENTA))
	detail_box.add_child(tags)
	detail_box.add_child(UI.mk_hline(UI.C_BORDER_DIM))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 12)
	detail_box.add_child(grid)
	grid.add_child(_kv("CLIENT / 雇主", str(c.get("client", "未知"))))
	grid.add_child(_kv("TARGET / 目标", str(c.get("target", "未知"))))
	grid.add_child(_kv("LOCATION / 地点", str(c.get("location", "未知"))))
	grid.add_child(_kv("ADVANCE / 预付款", "¥ " + UI.fmt_money(int(c.get("advance", 0))), UI.C_GREEN))

	detail_box.add_child(_section("OBJECTIVE / 目标", str(c.get("objective", ""))))
	var brief := UI.mk_label(str(c.get("brief", "")), 15, UI.C_TEXT, {"wrap": true})
	brief.custom_minimum_size.y = 70
	detail_box.add_child(brief)
	if str(c.get("hook", "")) != "":
		var hook := UI.mk_label("「%s」" % str(c.get("hook", "")), 13, UI.C_AMBER, {"wrap": true})
		detail_box.add_child(hook)
	if str(c.get("approach_hint", "")) != "":
		detail_box.add_child(UI.mk_label("蜃楼备注：%s" % str(c.get("approach_hint", "")), 11, UI.C_DIM, {"wrap": true}))

	detail_box.add_child(UI.mk_spacer(2))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	detail_box.add_child(buttons)
	var accept := UI.mk_button("接受委托 / ACCEPT", "primary", 220, 46)
	accept.pressed.connect(func(): _accept(str(c.get("id", ""))))
	buttons.add_child(accept)
	var talk := UI.mk_button("和蜃楼谈谈", "default", 150, 46)
	talk.pressed.connect(func():
		GS.negotiating_contract = c
		main.open_chat("fixer")
	)
	buttons.add_child(talk)
	var decline := UI.mk_button("拒绝", "danger", 100, 46)
	decline.pressed.connect(func(): _decline(str(c.get("id", ""))))
	buttons.add_child(decline)
	var hint := UI.mk_label("接受后进入 PLAN：分配队友、选择手段，然后开始现场行动。", 11, UI.C_DIM)
	detail_box.add_child(hint)
	var feed := UI.mk_panel(Color(0.010, 0.024, 0.032, 0.92), UI.C_BORDER_DIM, {"margin": 10})
	var feed_row := HBoxContainer.new()
	feed_row.add_theme_constant_override("separation", 12)
	feed.add_child(feed_row)
	feed_row.add_child(UI.mk_portrait(Vector2(76, 92), UI.C_CYAN))
	var feed_text := VBoxContainer.new()
	feed_text.add_theme_constant_override("separation", 2)
	feed_row.add_child(feed_text)
	feed_text.add_child(UI.mk_kicker("MIRAGE FEED / 加密语音"))
	feed_text.add_child(UI.mk_label("蜃楼在线。信任 %d/100。" % GS.fixer_trust, 12, UI.C_TEXT))
	feed_text.add_child(UI.mk_label("「先看价钱，再看风险。别问雇主是谁。」", 10, UI.C_MUTED, {"wrap": true, "width": 420}))
	detail_box.add_child(feed)
	FX.fade_in(detail_box, 0.18)

func _kv(kicker: String, value: String, color: Color = UI.C_TEXT) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.custom_minimum_size.x = 300
	v.add_child(UI.mk_kicker(kicker))
	v.add_child(UI.mk_label(value, 13, color, {"wrap": true, "width": 300}))
	return v

func _section(title: String, text: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.add_child(UI.mk_kicker(title))
	v.add_child(UI.mk_label(text, 14, UI.C_CYAN, {"wrap": true}))
	return v

func _accept(id: String) -> void:
	if GS.accept_contract(id):
		Sfx.play("confirm")
		main.toast("委托已接受。现在决定谁去现场。", UI.C_CYAN)
		main.navigate("plan")
	else:
		main.toast("暂时不能接受这个委托。", UI.C_RED)

func _decline(id: String) -> void:
	GS.decline_contract(id)
	selected_id = ""
	refresh()
	main.toast("你把委托扔回了暗网。", UI.C_MUTED)

func _refresh_offers() -> void:
	if GS.credits < 100:
		main.toast("刷新委托需要 100 信用点。", UI.C_RED)
		return
	GS.credits -= 100
	GS.save_game()
	main._refresh_header()
	main._ensure_offers(true)
	refresh()







