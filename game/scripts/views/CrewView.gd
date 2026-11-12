extends Control
## Crew roster: evaluate freelancers, recruit them, and keep the relationship alive.

const SKILL_LABELS := {
	"intrusion": "入侵", "ew": "电子战", "analysis": "分析", "stealth": "潜行",
	"tech": "技术", "social": "交涉", "combat": "战斗", "nerve": "意志",
}

var main = null
var selected_id := ""
var list_box: GridContainer
var detail_box: VBoxContainer
var head_stat: PanelContainer
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
	titles.add_child(UI.mk_kicker("CREW / 现场网络"))
	titles.add_child(UI.mk_label("团队", 24, UI.C_TEXT, {"bold": true}))
	var sub := UI.mk_label("你从不露面。屏幕那头的人替你走进去、开口、开枪、流血。", 12, UI.C_MUTED)
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(sub)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(spacer)
	head_stat = UI.mk_stat("HIRED", "0/3", UI.C_GREEN, 110)
	head.add_child(head_stat)
	var refresh_btn := UI.mk_button("联系人脉", "ghost", 110, 36)
	refresh_btn.tooltip_text = "让蜃楼再介绍几名佣兵（免费，冷却一天）"
	refresh_btn.pressed.connect(_ask_for_contacts)
	head.add_child(refresh_btn)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(body)

	var left := UI.mk_panel(Color(0.012, 0.024, 0.034, 0.92), UI.C_BORDER_DIM, {"margin": 14})
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	left.add_child(lv)
	lv.add_child(UI.mk_kicker("FREELANCERS / 可联系的人"))
	lv.add_child(UI.mk_hline(UI.C_BORDER_DIM))
	var scroll := UI.mk_scroll()
	lv.add_child(scroll)
	list_box = GridContainer.new()
	list_box.columns = 2
	list_box.add_theme_constant_override("h_separation", 10)
	list_box.add_theme_constant_override("v_separation", 10)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_box)

	var right := UI.mk_panel(Color(0.014, 0.026, 0.036, 0.94), UI.C_BORDER_DIM, {"margin": 0})
	right.custom_minimum_size.x = 430
	body.add_child(right)
	var scroll2 := UI.mk_scroll()
	right.add_child(scroll2)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 20)
	pad.add_theme_constant_override("margin_right", 20)
	pad.add_theme_constant_override("margin_top", 18)
	pad.add_theme_constant_override("margin_bottom", 18)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll2.add_child(pad)
	detail_box = VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 12)
	pad.add_child(detail_box)

func refresh() -> void:
	if head_stat == null:
		return
	head_stat.get_meta("value").text = "%d/3" % GS.hired_crew().size()
	_refresh_list()
	_refresh_detail()
	main._refresh_header()

func _refresh_list() -> void:
	if list_box == null:
		return
	for ch in list_box.get_children():
		ch.queue_free()
	if GS.crew.is_empty():
		var empty := VBoxContainer.new()
		empty.add_theme_constant_override("separation", 8)
		empty.add_child(UI.mk_label("频道里还没有人。", 14, UI.C_MUTED))
		var b := UI.mk_button("让蜃楼联系人脉", "primary", 240, 40)
		b.pressed.connect(_ask_for_contacts)
		empty.add_child(b)
		list_box.add_child(empty)
		return
	var found := false
	for c in GS.crew:
		if str(c.get("id", "")) == selected_id:
			found = true
	if not found and not GS.crew.is_empty():
		selected_id = str(GS.crew[0].get("id", ""))
	var sorted := GS.crew.duplicate()
	sorted.sort_custom(func(a, b): return bool(a.get("hired", false)) and not bool(b.get("hired", false)))
	for c in sorted:
		list_box.add_child(_make_card(c))
	var sig := ""
	for c in sorted:
		sig += str(c.get("id", ""))
	if sig != _list_sig:
		_list_sig = sig
		FX.stagger(list_box, 0.05, 0.965)

func _make_card(c: Dictionary) -> Control:
	var selected := str(c.get("id", "")) == selected_id
	var hired := bool(c.get("hired", false))
	var border := UI.C_CYAN if selected else (UI.C_GREEN_DIM if hired else UI.C_BORDER_DIM)
	var bg := Color(0.03, 0.075, 0.095, 0.95) if selected else Color(0.016, 0.032, 0.044, 0.92)
	var card := UI.mk_panel(bg, border, {"margin": 10})
	card.custom_minimum_size = Vector2(300, 150)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	var role := str(c.get("role", ""))
	top.add_theme_constant_override("separation", 8)
	top.add_child(UI.mk_merc_portrait(c, Vector2(52, 52), true))
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(UI.mk_label(str(c.get("name", "")), 16, UI.C_TEXT, {"bold": true}))
	info.add_child(UI.mk_label("%s · %s" % [str(c.get("handle", "")), role], 9, UI.C_CYAN_DIM, {"mono": true}))
	top.add_child(info)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(sp)
	if hired:
		top.add_child(UI.mk_tag("已入队", UI.C_GREEN))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	row.add_child(UI.mk_label("忠诚", 10, UI.C_DIM, {"mono": true}))
	var meter := UI.mk_meter(int(c.get("loyalty", 50)), 100, UI.C_CYAN, 96, 10)
	row.add_child(meter)
	row.add_child(UI.mk_label(str(int(c.get("loyalty", 50))), 10, UI.C_MUTED, {"mono": true}))
	v.add_child(UI.mk_label("分成 ¥%s · 伤势 %d/%d" % [UI.fmt_money(int(c.get("price", 0))), int(c.get("injury", 0)), GS.MAX_INJURY], 11, UI.C_MUTED))
	var tag_row := HBoxContainer.new()
	tag_row.add_theme_constant_override("separation", 4)
	tag_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tag_row)
	var skills: Dictionary = c.get("skills", {})
	var top_skills := skills.keys()
	top_skills.sort_custom(func(a, b): return int(skills[a]) > int(skills[b]))
	for i in range(mini(2, top_skills.size())):
		var k := str(top_skills[i])
		tag_row.add_child(UI.mk_tag("%s %d" % [SKILL_LABELS.get(k, k), int(skills[k])], UI.C_AMBER))
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
			card.add_theme_stylebox_override("panel", UI.panel_style(bg, border, 10, 2))
	)
	return card

func _refresh_detail() -> void:
	if detail_box == null:
		return
	for ch in detail_box.get_children():
		ch.queue_free()
	var c = GS.crew_by_id(selected_id)
	if c == null:
		detail_box.add_child(UI.mk_spacer(30))
		detail_box.add_child(UI.mk_kicker("NO CONTACT / 没有选中的人"))
		detail_box.add_child(UI.mk_label("左侧是你能联系到的现场佣兵。点击查看档案。", 13, UI.C_MUTED, {"wrap": true}))
		return

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	detail_box.add_child(top)
	top.add_child(UI.mk_merc_portrait(c, Vector2(112, 112), false))
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 1)
	top.add_child(tv)
	tv.add_child(UI.mk_kicker("FIELD OPERATIVE / 现场佣兵"))
	tv.add_child(UI.mk_label(str(c.get("name", "")), 24, UI.C_TEXT, {"bold": true}))
	tv.add_child(UI.mk_label("%s · %s" % [str(c.get("handle", "")), str(c.get("role", ""))], 11, UI.C_CYAN_DIM, {"mono": true}))
	if bool(c.get("hired", false)):
		tv.add_child(UI.mk_tag("已入队", UI.C_GREEN))

	var origin := UI.mk_label(str(c.get("origin", "")), 12, UI.C_MUTED, {"wrap": true})
	detail_box.add_child(origin)
	detail_box.add_child(UI.mk_hline(UI.C_BORDER_DIM))

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	detail_box.add_child(info)
	info.add_child(_kv("性格", str(c.get("personality", ""))))
	info.add_child(_kv("怪癖", str(c.get("quirk", ""))))
	info.add_child(_kv("专长", str(c.get("perk", ""))))
	info.add_child(_kv("喜欢 / 讨厌", "%s / %s" % [str(c.get("like", "")), str(c.get("dislike", ""))]))

	var skill_title := HBoxContainer.new()
	skill_title.add_child(UI.mk_kicker("CAPABILITY / 能力"))
	detail_box.add_child(skill_title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 5)
	detail_box.add_child(grid)
	var skills: Dictionary = c.get("skills", {})
	for k in ["intrusion", "stealth", "tech", "combat", "ew", "social", "analysis", "nerve"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.custom_minimum_size.x = 175
		row.add_child(UI.mk_label(SKILL_LABELS.get(k, k), 11, UI.C_MUTED, {"width": 42}))
		row.add_child(UI.mk_meter(int(skills.get(k, 1)), 5, UI.C_CYAN, 90, 5))
		row.add_child(UI.mk_label(str(int(skills.get(k, 1))), 11, UI.C_TEXT, {"mono": true}))
		grid.add_child(row)

	var vitals := HBoxContainer.new()
	vitals.add_theme_constant_override("separation", 18)
	detail_box.add_child(vitals)
	var loyalty_box := VBoxContainer.new()
	loyalty_box.add_theme_constant_override("separation", 3)
	loyalty_box.add_child(UI.mk_label("忠诚度 %d/100" % int(c.get("loyalty", 50)), 11, UI.C_MUTED, {"mono": true}))
	loyalty_box.add_child(UI.mk_meter(int(c.get("loyalty", 50)), 100, UI.C_CYAN, 140, 10))
	vitals.add_child(loyalty_box)
	var injury_box := VBoxContainer.new()
	injury_box.add_theme_constant_override("separation", 3)
	injury_box.add_child(UI.mk_label("伤势 %d/%d" % [int(c.get("injury", 0)), GS.MAX_INJURY], 11, UI.C_RED, {"mono": true}))
	injury_box.add_child(UI.mk_meter(int(c.get("injury", 0)), GS.MAX_INJURY, UI.C_RED, 90, 3))
	vitals.add_child(injury_box)

	var price_row := HBoxContainer.new()
	price_row.add_theme_constant_override("separation", 8)
	price_row.add_child(UI.mk_label("分成要求", 11, UI.C_DIM, {"mono": true}))
	price_row.add_child(UI.mk_label("¥ " + UI.fmt_money(int(c.get("price", 0))), 18, UI.C_AMBER, {"mono": true, "bold": true}))
	detail_box.add_child(price_row)

	if bool(c.get("secret_revealed", false)) and str(c.get("secret", "")) != "":
		var secret := UI.mk_label("秘密：%s" % str(c.get("secret", "")), 12, UI.C_MAGENTA, {"wrap": true})
		detail_box.add_child(secret)
	else:
		detail_box.add_child(UI.mk_label("秘密：???（忠诚度 70 以上，或合适的时机才会说出口）", 11, UI.C_DIM, {"wrap": true}))
	if str(c.get("pitch", "")) != "":
		detail_box.add_child(UI.mk_label("「%s」" % str(c.get("pitch", "")), 12, UI.C_CYAN_DIM, {"wrap": true}))

	detail_box.add_child(UI.mk_hline(UI.C_BORDER_DIM))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	detail_box.add_child(buttons)
	var talk := UI.mk_button("通讯", "default", 110, 42)
	talk.pressed.connect(func(): main.open_chat("crew", str(c.get("id", ""))))
	buttons.add_child(talk)
	if bool(c.get("hired", false)):
		var fire := UI.mk_button("解除合作", "danger", 130, 42)
		fire.pressed.connect(func(): _confirm_fire(c))
		buttons.add_child(fire)
		var note := UI.mk_label("已加入行动名单。去 PLAN 选择随行人员。", 10, UI.C_GREEN, {"wrap": true})
		detail_box.add_child(note)
	else:
		var recruit := UI.mk_button("招募 / RECRUIT", "primary", 180, 42)
		recruit.disabled = GS.hired_crew().size() >= GS.MAX_CREW
		recruit.pressed.connect(func(): _confirm_recruit(c))
		buttons.add_child(recruit)
		var note2 := UI.mk_label("招募不预付报酬，行动结算时从分成里扣。", 10, UI.C_DIM, {"wrap": true})
		detail_box.add_child(note2)
	FX.fade_in(detail_box, 0.18)

func _kv(kicker: String, value: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.add_child(UI.mk_kicker(kicker))
	v.add_child(UI.mk_label(value, 12, UI.C_TEXT, {"wrap": true}))
	return v

func debug_recruit_first() -> void:
	var list := GS.available_crew()
	if list.is_empty():
		return
	_do_recruit(list[0], int(list[0].get("price", 300)))

func _confirm_recruit(c: Dictionary) -> void:
	var price := int(c.get("price", 300))
	var low := int(round(price * 0.9))
	var body := "「%s」开价 ¥%s。招募后不预付报酬，结算时从你的净收入里扣。\n\n报价越高，对方越愿意接；低于八折基本不会谈。" % [str(c.get("name", "")), UI.fmt_money(price)]
	main.show_modal("招募 · %s" % str(c.get("name", "")), body, [
		{"label": "按报价 ¥%s" % UI.fmt_money(price), "kind": "primary", "callback": func(): _do_recruit(c, price)},
		{"label": "压价 ¥%s" % UI.fmt_money(low), "kind": "default", "callback": func(): _do_recruit(c, low)},
		{"label": "取消", "kind": "ghost"},
	], UI.C_CYAN)

func _do_recruit(c: Dictionary, cut: int) -> void:
	if GS.hired_crew().size() >= GS.MAX_CREW:
		main.toast("最多只能带 3 个人进现场。", UI.C_RED)
		return
	var cid := str(c.get("id", ""))
	var chat = main.open_chat("crew", cid)
	chat.push_system("（你向 %s 发出行动邀请：分成 ¥%s。）" % [str(c.get("name", "")), UI.fmt_money(cut)])
	chat.set_typing(true)
	var res: Dictionary = await Bridge.request("recruit", {
		"state": GS.state_for_bridge(),
		"crew": c,
		"offer": {"cut": cut},
	}, {"stream": false, "actor": {"kind": "crew", "id": cid, "persona": c}})
	chat.set_typing(false)
	var text := str(res.get("text", ""))
	var markers: Dictionary = res.get("markers", {})
	var mechanical := false
	var price := int(c.get("price", 300))
	if cut >= int(round(price * 0.95)):
		mechanical = true
	elif cut < int(round(price * 0.8)):
		mechanical = false
	else:
		mechanical = bool(markers.get("accepted", false)) or int(c.get("loyalty", 50)) >= 65
	if text == "":
		text = "「%s」在通讯那头沉默了一会儿。" % str(c.get("name", ""))
	chat.push_npc(text)
	if mechanical:
		if GS.hire_crew(cid, cut):
			main.toast("「%s」加入了行动名单。" % str(c.get("name", "")), UI.C_GREEN)
			Sfx.play("confirm")
			refresh()
	else:
		main.toast("「%s」拒绝了这个价。" % str(c.get("name", "")), UI.C_AMBER)
		Sfx.play("deny")

func _confirm_fire(c: Dictionary) -> void:
	main.show_modal("解除合作", "确定让「%s」离开名单？对方不会忘记这件事。" % str(c.get("name", "")), [
		{"label": "解除", "kind": "danger", "callback": func(): _do_fire(c)},
		{"label": "算了", "kind": "ghost"},
	], UI.C_MAGENTA)

func _do_fire(c: Dictionary) -> void:
	GS.fire_crew(str(c.get("id", "")))
	refresh()

func _ask_for_contacts() -> void:
	if GS.credits < 50:
		main.toast("联系人脉需要 50 信用点。", UI.C_RED)
		return
	GS.credits -= 50
	GS.save_game()
	main._refresh_header()
	main._ensure_crew()
	main.toast("蜃楼把你的需求转给了几个人。", UI.C_CYAN)







